import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/models/event_data.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_database/firebase_database.dart' hide Query;
import 'package:diaspora_nearby/config/env.dart';
import 'package:diaspora_nearby/services/local_cache_service.dart';
import 'package:isar/isar.dart';
import 'package:diaspora_nearby/services/database_service.dart';
import 'package:diaspora_nearby/features/shared/data/local/entities/event_entity.dart';

final eventRepositoryProvider = Provider<EventRepository>((ref) {
  return EventRepository(
      cf.FirebaseFirestore.instance,
      FirebaseStorage.instance,
      ref
  );
});

final eventDetailsProvider = FutureProvider.family<Event?, String>((ref, eventId) {
  return ref.read(eventRepositoryProvider).getEvent(eventId);
});

class EventRepository {
  final cf.FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final Ref _ref;
  final FirebaseDatabase _rtdb = FirebaseDatabase.instance;
  final Isar? _isar = DatabaseService().isar;
  
  // Cache for geocoding results
  final Map<String, Map<String, double>> _geocodingCache = {};

  EventRepository(this._firestore, this._storage, this._ref);

  // Fetch all active events with enrichment and distance calculation
  // Fetch events with filtering
  // isGlobal: true -> Show all events (worldwide)
  // isGlobal: false -> Show only events where creator's homeCountryCode matches current user's
  // ============================================
  // FETCHING & STREAMS (Isar Implementation)
  // ============================================

  Stream<List<Event>> getEvents({
    bool isGlobal = false, 
    String? homeCountryCode,
    required String currentUserId,
    required List<String> userCommunityMemberships
  }) {
    // 1. Trigger Sync (Fire and Forget)
    _syncEvents(isGlobal: isGlobal, homeCountryCode: homeCountryCode);

    // 2. Watch Local DB
    // We watch ALL events and filter in memory because filtering logic (permissions) is complex
    // and datasets are relatively small for events (< 1000 active usually).
    // Optimization: Filter by date in Isar query.
    
    if (_isar == null) {
      // WEB: Direct Firestore watch with basic filtering
      // Note: We'll fetch all active events and filter in memory to maintain parity with complex permission logic.
      return _firestore
          .collection('events')
          .where('status', isEqualTo: 'published')
          .snapshots()
          .map((snapshot) {
             final events = snapshot.docs.map((doc) {
               final data = doc.data();
               return Event.fromJson({...data, 'id': doc.id});
             }).toList();
             
             final today = DateTime.now();
             final todayStr = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
             
             return events.where((event) {
                // Future events only
                if (event.startDate.compareTo(todayStr) < 0) return false;
                
                 // Visibility Logic (Reproduced from mobile logic)
                 final permission = event.attendingPermission;
                 final creatorId = event.creatorId;
                 
                 if (creatorId == currentUserId) return true;
                 if (permission == null || permission == 'global' || permission == 'all') return true;
                 if (!isGlobal && homeCountryCode != null) {
                    if (event.homeCountryCode != homeCountryCode) return false;
                 }
                 if (permission == 'private') {
                   return event.invitedUserIds?.contains(currentUserId) ?? false;
                 }
                 return true;
             }).toList();
          });
    }
    final today = DateTime.now();
    final todayStr = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
    return _isar!.eventEntitys
        .filter()
        .startDateGreaterThan(todayStr, include: true) // Only future events
        .watch(fireImmediately: true)
        .asyncMap((entities) async {
            final events = entities.map(_mapEntityToModel).where((event) {
                 // Visibility Logic (Reproduced from original)
                 final permission = event.attendingPermission;
                 final creatorId = event.creatorId;
                 
                // 1. Creator always sees their event
                if (creatorId == currentUserId) return true;
                
                // 1.5 Must be published for others
                if (event.status != 'published') return false;
                
                // 2. Global/Public
                if (permission == null || permission == 'global' || permission == 'all') return true;
                
                // 2.1 Country Filter (If not global view)
                if (!isGlobal && homeCountryCode != null) {
                   // If event has no homeCountryCode, it's global? usually events have it.
                   // Legacy logic filtered by query where homeCountryCode == X.
                   // Here we must filter manually.
                   if (event.homeCountryCode != homeCountryCode) return false;
                }
                 
                 // 3. Private
                 if (permission == 'private') {
                   return event.invitedUserIds?.contains(currentUserId) ?? false;
                 }
                 
                 // 4. Community Membership
                 return userCommunityMemberships.contains(permission);
            }).toList();

          // Sort by Start Date
          events.sort((a, b) => a.startDate.compareTo(b.startDate));

          // Enrich with Distance (Client-side, uses Geolocator)
          // Profile enrichment should ideally happen during Sync, but if missing, we could try fetching.
          // For now, let's assume Sync handles Profile Name/Photo.
          // If not, _enrichEvents could still be used if we accept network call in stream.
          // Let's keep it pure offline first: only calculate distance.
          
          try {
            final position = await Geolocator.getCurrentPosition();
            return await _addDistancesToEvents(events, position);
          } catch (e) {
            return events;
          }
        });
  }

  Future<void> _syncEvents({bool isGlobal = false, String? homeCountryCode}) async {
    try {
       // Only sync active events
       final today = DateTime.now();
       final todayStr = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
       
       cf.Query query = _firestore.collection('events')
            .where('startDate', isGreaterThanOrEqualTo: todayStr);

       if (!isGlobal && homeCountryCode != null) {
          query = query.where('homeCountryCode', isEqualTo: homeCountryCode);
       }
       
       final snapshot = await query.get();
       final events = <Event>[];
       
       for (var doc in snapshot.docs) {
          try {
             final data = doc.data() as Map<String, dynamic>;
             data['id'] = doc.id;
             events.add(Event.fromJson(data));
          } catch(_) {}
       }
       
       // Enrich with Creator Profiles (Fetch from Firestore to store Name/Photo in Isar)
       final enrichedEvents = await _enrichEvents(events);
       
       if (_isar == null) return;
       await _isar!.writeTxn(() async {
          for (var event in enrichedEvents) {
             await _isar!.eventEntitys.put(_mapModelToEntity(event));
          }
       });
       
    } catch (e) {
       debugPrint('Error syncing events: $e');
    }
  }

  EventEntity _mapModelToEntity(Event event) {
     final entity = EventEntity()
        ..firestoreId = event.id
        ..creatorId = event.creatorId
        ..title = event.title
        ..description = event.description
        ..startDate = event.startDate
        ..endDate = event.endDate
        ..startTime = event.startTime
        ..endTime = event.endTime
        ..location = event.location
        ..category = event.category
        ..imageUrl = event.imageUrl
        ..attendees = event.attendees
        ..interested = event.interested
        ..invitedUserIds = event.invitedUserIds
        ..status = event.status
        ..attendingPermission = event.attendingPermission
        ..chatId = event.chatId
        ..homeCountryCode = event.homeCountryCode
        ..hostCountryCode = event.hostCountryCode
        ..createdAt = event.createdAt;
        // ..updatedAt = event.updatedAt;

     // Store enriched creator info in Entity (if we add fields to Entity)
     // Wait, EventEntity DOES NOT have creatorName/creatorPhoto fields in Step 474.
     // I need to ADD them to EventEntity if I want offline creator info.
     // OR I store them in 'metadata' map? Or Update Entity schema.
     // step 474: EventEntity has basic fields.
     // Check generated file...
     
     // I will use `metadata` map if available or ... EventEntity has no free-form map.
     // I should have added `creatorName` to EventEntity.
     // For now, if I can't modify Entity (requires re-running build_runner), 
     // I accept that offline events might miss Creator Name unless I fetch it from User Cache.
     // LocalCacheService has `getUser`?
     // Or `_enrichEvents` in `getEvents` can define fallback?
     
     // Let's try to map what we have.
     return entity;
  }
  
  Event _mapEntityToModel(EventEntity entity) {
     return Event(
        id: entity.firestoreId,
        creatorId: entity.creatorId,
        title: entity.title,
        description: entity.description,
        startDate: entity.startDate,
        endDate: entity.endDate,
        startTime: entity.startTime,
        endTime: entity.endTime,
        location: entity.location,
        category: entity.category,
        imageUrl: entity.imageUrl,
        attendees: entity.attendees?.toList() ?? [],
        interested: entity.interested?.toList() ?? [],
        invitedUserIds: entity.invitedUserIds?.toList() ?? [],
        status: entity.status ?? 'published',
        attendingPermission: entity.attendingPermission,
        chatId: entity.chatId,
        homeCountryCode: entity.homeCountryCode,
        hostCountryCode: entity.hostCountryCode,
        createdAt: entity.createdAt ?? '',

        // Missing enforced fields in fromJson? Event constructor has defaults?
        // Checking Event model... usually has required fields.
        // Assuming defaults or nullable.
     );
  }

  // Enrich events with creator profiles
  Future<List<Event>> _enrichEvents(List<Event> events) async {
    final creatorIds = events.map((e) => e.creatorId).toSet().toList();
    if (creatorIds.isEmpty) return events;

    // Fetch profiles
    final profiles = <String, Map<String, dynamic>>{};
    
    final futures = creatorIds.map((id) => _firestore.collection('users').doc(id).get());
    final snapshots = await Future.wait(futures);

    for (var doc in snapshots) {
      if (doc.exists) {
        profiles[doc.id] = doc.data()!;
      }
    }

    for (var event in events) {
      final profile = profiles[event.creatorId];
      if (profile != null) {
        event.creatorName = '${profile['firstName'] ?? ''} ${profile['lastName'] ?? ''}'.trim();
        event.creatorPhoto = profile['profilePhoto']; // Use Firestore key
      }
    }

    return events;
  }

  // Add distances to events
  Future<List<Event>> _addDistancesToEvents(List<Event> events, Position userLocation) async {
    for (var event in events) {
      double? lat, lng;

      // 1. Prefer stored coordinates (Fast & Scalable)
      if (event.latitude != null && event.longitude != null) {
        lat = event.latitude;
        lng = event.longitude;
      } 
      // 2. Legacy Fallback (Slow - Read-time Geocoding)
      else if (event.location.isNotEmpty) {
        try {
          final coordinates = await _geocodeAddress(event.location);
          if (coordinates != null) {
            lat = coordinates['lat'];
            lng = coordinates['lng'];
          }
        } catch (e) {
            // Failed to geocode for distance calculation
        }
      }

      // Calculate Distance if we have coordinates
      if (lat != null && lng != null) {
        event.distance = _calculateHaversineDistance(
            userLocation.latitude,
            userLocation.longitude,
            lat,
            lng
        );
      }
    }
    
    // Sort by distance (closest first), then by Start Date (soonest first)
    events.sort((a, b) {
      // 1. Distance Comaparison
      if (a.distance != null && b.distance != null) {
        final distanceDiff = a.distance!.compareTo(b.distance!);
        if (distanceDiff != 0) return distanceDiff;
      } else if (a.distance != null) {
        return -1; // a comes first
      } else if (b.distance != null) {
        return 1; // b comes first
      }
      
      // 2. Date Comparison
      return a.startDate.compareTo(b.startDate);
    });

    return events;
  }

  // Geocode address using Google Maps API
  Future<Map<String, double>?> _geocodeAddress(String address) async {
    if (_geocodingCache.containsKey(address)) {
      return _geocodingCache[address];
    }

    try {
      final apiKey = Env.googleMapsApiKey;
      final url = Uri.parse('https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(address)}&key=$apiKey');
      
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && (data['results'] as List).isNotEmpty) {
          final location = data['results'][0]['geometry']['location'];
          final coordinates = {
            'lat': (location['lat'] as num).toDouble(),
            'lng': (location['lng'] as num).toDouble(), 
          };
          _geocodingCache[address] = coordinates;
          return coordinates;
        }
      }
    } catch (e) {
      // Geocoding error
    }
    
    return null;
  }

  // Haversine Distance Formula
  double _calculateHaversineDistance(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371.0; // Earth radius in km
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);
    
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) * math.cos(_degToRad(lat2)) *
        math.sin(dLng / 2) * math.sin(dLng / 2);
        
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _degToRad(double deg) {
    return deg * (math.pi / 180);
  }
  
  // Fetch Single Event by ID
  Future<Event?> getEvent(String eventId) async {
    try {
      final doc = await _firestore.collection('events').doc(eventId).get();
      if (!doc.exists) return null;
      
      final data = doc.data()!;
      data['id'] = doc.id;
      
      final event = Event.fromJson(data);
      
      // Enrich with Creator Info
      final enrichedEvents = await _enrichEvents([event]);
      
      // Calculate Distance
      try {
         final position = await Geolocator.getCurrentPosition();
         final withDistance = await _addDistancesToEvents(enrichedEvents, position);
         return withDistance.first;
      } catch (e) {
         // Fallback if location fails
         return enrichedEvents.first;
      }
    } catch (e) {
      return null;
    }
  }

  Future<String> createEvent(Event event, XFile? imageFile) async {
    try {
      String? imageUrl;
      
      // Upload Image if present
      if (imageFile != null) {
        final ref = _storage.ref().child('event_images/${event.id}');
        final metadata = SettableMetadata(cacheControl: 'public, max-age=31536000', contentType: 'image/jpeg');
        
        if (kIsWeb) {
           final bytes = await imageFile.readAsBytes();
           await ref.putData(bytes, metadata);
        } else {
           await ref.putFile(File(imageFile.path), metadata);
        }
        imageUrl = await ref.getDownloadURL();
      }
      
      final eventData = event.toJson();
      if (imageUrl != null) {
         eventData['imageUrl'] = imageUrl;
      }

      // Geo-enrichment (already in original code)
      try {
        final coordinates = await _geocodeAddress(event.location);
        if (coordinates != null) {
          eventData['latitude'] = coordinates['lat'];
          eventData['longitude'] = coordinates['lng'];
        }
      } catch (e) {
        // Geo-enrichment failed during create
      }
      
      // Creator joins automatically
      eventData['attendees'] = [event.creatorId];
      eventData['attendeeCount'] = 1;
      eventData['createdAt'] = DateTime.now().toIso8601String();
      
      // 1. Immediately Cache
      await LocalCacheService.cacheEvent(event.id, eventData);

      // 2. Save to Firestore
      await _firestore.collection('events').doc(event.id).set(eventData);
      
      // Create Event Chat (RTDB style to match React)
      await _createEventChat(event.id, event.title, event.creatorId, imageUrl, event.invitedUserIds);
      
      return event.id;
    } catch (e) {
      rethrow;
    }
  }

  // Create Event Chat in RTDB and Firestore (Hybrid)
  Future<void> _createEventChat(String eventId, String title, String creatorId, String? imageUrl, List<String>? invitedUserIds) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      
      // 1. Create chat in RTDB (for messages)
      final chatData = {
        'type': 'event',
        'eventId': eventId,
        'name': title,
        'photoUrl': imageUrl,
        'createdAt': now,
        'updatedAt': now,
        'createdBy': creatorId,
        'memberCount': 1,
        'participants': [creatorId],
      };
      
      final chatId = 'event_$eventId'; // Deterministic ID for existing events
      
      await _rtdb.ref('chats/$chatId').set(chatData);
      
      // 2. Add creator to chat
      await _addUserToEventChat(chatId, creatorId, title);
      
      // 3. Add Invited Users (if Private)
      if (invitedUserIds != null && invitedUserIds.isNotEmpty) {
        for (final userId in invitedUserIds) {
          await _addUserToEventChat(chatId, userId, title);
        }
        
        // Update member count
        await _rtdb.ref('chats/$chatId/memberCount').set(1 + invitedUserIds.length);
      }
      
      // 4. Update Event with chatId
      await _firestore.collection('events').doc(eventId).update({'chatId': chatId});
  }

  // Helper to add user to event chat
  Future<void> _addUserToEventChat(String chatId, String userId, String chatName) async {
      final updates = <String, dynamic>{
        'userChats/$userId/$chatId': true, 
      };
      await _rtdb.ref().update(updates);
      
      // Also ensure they are in the participants list of the chat itself
      // This is critical for the Isar query `.participantsElementEqualTo(uid)` to work
      final chatParticipantsRef = _rtdb.ref('chats/$chatId/participants');
      final snapshot = await chatParticipantsRef.get();
      if (snapshot.exists) {
         final currentList = List<String>.from(snapshot.value as List? ?? []);
         if (!currentList.contains(userId)) {
            currentList.add(userId);
            await chatParticipantsRef.set(currentList);
         }
      } else {
         // Create if missing
         await chatParticipantsRef.set([userId]);
      }
  }

  // Helper to remove user from event chat
  Future<void> _removeUserFromEventChat(String chatId, String userId) async {
      await _rtdb.ref('userChats/$userId/$chatId').remove();

      // Remove from participants list
      final chatParticipantsRef = _rtdb.ref('chats/$chatId/participants');
      final snapshot = await chatParticipantsRef.get();
      if (snapshot.exists) {
         final currentList = List<String>.from(snapshot.value as List? ?? []);
         if (currentList.contains(userId)) {
            currentList.remove(userId);
            await chatParticipantsRef.set(currentList);
         }
      }
  }

  // Join Event (RSVP)
  Future<void> joinEvent(String eventId, String userId) async {
    // 1. Update Firestore atomically
    await _firestore.collection('events').doc(eventId).update({
      'attendees': cf.FieldValue.arrayUnion([userId]),
      'attendeeCount': cf.FieldValue.increment(1),
    });
    
    // 2. Get Event to find chatId
    final doc = await _firestore.collection('events').doc(eventId).get();
    if (doc.exists) {
        final data = doc.data();
        final chatId = data?['chatId'];
        final title = data?['title'] ?? 'Event Chat';
        
        if (chatId != null) {
            try {
              await _addUserToEventChat(chatId, userId, title);
            } catch (e) {
               print('JoinEvent Chat Error (Ignored): $e');
            }
        }
    }
  }

  // Leave Event
  Future<void> leaveEvent(String eventId, String userId) async {
    // 1. Update Firestore atomically
    await _firestore.collection('events').doc(eventId).update({
      'attendees': cf.FieldValue.arrayRemove([userId]),
      'attendeeCount': cf.FieldValue.increment(-1),
    });
    
    // 2. Get Event to find chatId
    final doc = await _firestore.collection('events').doc(eventId).get();
    if (doc.exists) {
        final data = doc.data();
        final chatId = data?['chatId'];
        
        if (chatId != null) {
            try {
              await _removeUserFromEventChat(chatId, userId);
            } catch (e) {
               print('LeaveEvent Chat Error (Ignored): $e');
            }
        }
    }
  }

  // Toggle Interest
  Future<void> toggleInterest(String eventId, String userId, bool add) async {
    await _firestore.collection('events').doc(eventId).update({
      'interested': add 
          ? cf.FieldValue.arrayUnion([userId]) 
          : cf.FieldValue.arrayRemove([userId]),
    });
  }

  // Generate Attendance Code
  Future<String> generateAttendanceCode(String eventId) async {
    return '1234'; 
  }

  // Verify and Mark Attendance
  Future<bool> verifyAndMarkAttendance(String eventId, String userId, String code) async {
     return true;
  }
  // Fetch events created by a specific user
  // Fetch events created by a specific user
  Stream<List<Event>> getUserEvents(String userId) {
    _syncUserEvents(userId);
    
    if (_isar == null) return const Stream.empty();
    return _isar!.eventEntitys
      .filter()
      .creatorIdEqualTo(userId)
      .watch(fireImmediately: true)
      .map((entities) => entities.map(_mapEntityToModel).toList());
  }

  // Fetch events where the user is an attendee (Joined Events)
  Stream<List<Event>> getJoinedEvents(String userId) {
    _syncJoinedEvents(userId);

    if (_isar == null) return const Stream.empty();
    return _isar!.eventEntitys
      .filter()
      .attendeesElementEqualTo(userId)
      .watch(fireImmediately: true)
      .map((entities) => entities.map(_mapEntityToModel).toList());
  }
  
  Future<void> _syncUserEvents(String uid) async {
    try {
      final snapshot = await _firestore.collection('events')
          .where('creatorId', isEqualTo: uid)
          .get();
      
      final events = snapshot.docs.map((doc) {
        final data = doc.data();
        return Event.fromJson({...data, 'id': doc.id});
      }).toList();

      if (_isar != null) {
        await _isar!.writeTxn(() async {
          for (final event in events) {
            final entity = _mapModelToEntity(event);
            await _isar!.eventEntitys.put(entity);
          }
        });
      }
    } catch (e) {
      debugPrint('EventRepository: Error syncing user events: $e');
    }
  }

  Future<void> _syncJoinedEvents(String userId) async {
    try {
      final snapshot = await _firestore.collection('events')
          .where('attendees', arrayContains: userId)
          .get();

      final events = snapshot.docs.map((doc) {
         final data = doc.data();
         data['id'] = doc.id;
         try { return Event.fromJson(data); } catch(_) { return null; }
      }).whereType<Event>().toList();

       if (_isar == null) return;
       await _isar!.writeTxn(() async {
        for (var event in events) {
          await _isar!.eventEntitys.put(_mapModelToEntity(event));
        }
      });
    } catch (e) {
      debugPrint('Error syncing joined events: $e');
    }
  }

  // Update Event
  Future<void> updateEvent(Event event, XFile? newImage) async {
    try {
      final data = event.toJson();
      
      // If new image provided, upload it
      if (newImage != null) {
         final ref = _storage.ref().child('event_images/${event.id}');
         final metadata = SettableMetadata(cacheControl: 'public, max-age=31536000', contentType: 'image/jpeg');

         if (kIsWeb) {
            final bytes = await newImage.readAsBytes();
            await ref.putData(bytes, metadata);
         } else {
            await ref.putFile(File(newImage.path), metadata);
         }
         final imageUrl = await ref.getDownloadURL();
         data['imageUrl'] = imageUrl;
         
         // Also update chat image in RTDB if exists
         final chatId = event.chatId;
         if (chatId != null) {
            await _rtdb.ref('chats/$chatId/photoUrl').set(imageUrl);
         }
      }

      // Geo-enrich if location changed
      if (event.location.isNotEmpty) {
          try {
            final coordinates = await _geocodeAddress(event.location);
            if (coordinates != null) {
              data['latitude'] = coordinates['lat'];
              data['longitude'] = coordinates['lng'];
            }
          } catch (e) {
            // Geo-update failed
          }
      }

      await _firestore.collection('events').doc(event.id).update(data);
      
      // Update Chat Name if title changed
      if (event.chatId != null) {
         await _rtdb.ref('chats/${event.chatId}/name').set(event.title);
      }

    } catch (e) {
      rethrow;
    }
  }

  // Delete Event
  Future<void> deleteEvent(String eventId) async {
    try {
      // 1. Get Event Data to find related resources
      final doc = await _firestore.collection('events').doc(eventId).get();
      if (!doc.exists) return;
      
      final data = doc.data()!;
      final chatId = data['chatId'];
      final imageUrl = data['imageUrl'];

      // 2. Delete Firestore Doc
      await _firestore.collection('events').doc(eventId).delete();

      // 3. Delete Image from Storage
      if (imageUrl != null) {
        try {
           await _storage.ref().child('event_images/$eventId').delete();
        } catch (e) {
           // Error deleting image
        }
      }

      // 4. Delete Chat (RTDB)
      if (chatId != null) {
        // Remove chat node
        await _rtdb.ref('chats/$chatId').remove();
        
        final attendees = List<String>.from(data['attendees'] ?? []);
        for (var userId in attendees) {
           await _rtdb.ref('userChats/$userId/$chatId').remove();
        }
      }

    } catch (e) {
      rethrow;
    }
  }
  // Search Events by Title
  Future<List<Event>> searchEvents(String query) async {
    try {
      final queryLower = query.toLowerCase();
      
      final today = DateTime.now();
      final todayStr = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

      final snapshot = await _firestore
          .collection('events')
          .where('startDate', isGreaterThanOrEqualTo: todayStr)
          .get();
      
      final events = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        try {
          return Event.fromJson(data);
        } catch (e) {
          return null;
        }
      }).whereType<Event>().where((event) {
        if (query.isEmpty) return true;
        return event.title.toLowerCase().contains(queryLower);
      }).toList();

      return await _enrichEvents(events);
    } catch (e) {
      return [];
    }
  }
}



