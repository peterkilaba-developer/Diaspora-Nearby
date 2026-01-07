import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
  // ignore: unused_field
  final Ref _ref;
  final FirebaseDatabase _rtdb = FirebaseDatabase.instance;
  
  // Cache for geocoding results
  final Map<String, Map<String, double>> _geocodingCache = {};

  EventRepository(this._firestore, this._storage, this._ref);

  // Fetch all active events with enrichment and distance calculation
  // Fetch events with filtering
  // isGlobal: true -> Show all events (worldwide)
  // isGlobal: false -> Show only events where creator's homeCountryCode matches current user's
  Stream<List<Event>> getEvents({
    bool isGlobal = false, 
    String? homeCountryCode,
    required String currentUserId,
    required List<String> userCommunityMemberships
  }) {
    cf.Query query = _firestore.collection('events');

    if (!isGlobal && homeCountryCode != null) {
      // Filter by organizer's home country code (Legacy/Optimization)
      query = query.where('homeCountryCode', isEqualTo: homeCountryCode);
    }

    // Filter out past events (Show events starting today or in future)
    final today = DateTime.now();
    final todayStr = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
    query = query.where('startDate', isGreaterThanOrEqualTo: todayStr);
    
    return query
        .snapshots() 
        .asyncMap((snapshot) async {
      final events = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        try {
          return Event.fromJson(data);
        } catch (e) {
          return null;
        }
      }).whereType<Event>().where((event) {
         // Visibility Logic
         final permission = event.attendingPermission;
         final creatorId = event.creatorId;
         
        // 1. Creator always sees their event
        if (creatorId == currentUserId) return true;
        
        // 1.5 Must be published for others
        if (event.status != 'published') return false;
        
        // 2. Global/Public
        if (permission == null || permission == 'global' || permission == 'all') return true;
         
         // 3. Private
         if (permission == 'private') {
           return event.invitedUserIds?.contains(currentUserId) ?? false;
         }
         
         // 4. Community Membership
         // If permission is a community ID, user must be a member
         return userCommunityMemberships.contains(permission);
      }).toList();

      // Sort by Start Date (client-side)
      events.sort((a, b) => a.startDate.compareTo(b.startDate));
      
      // Enrich with Creator Info
      final enrichedEvents = await _enrichEvents(events);

      // Calculate Distances
      try {
        final position = await Geolocator.getCurrentPosition();
        return await _addDistancesToEvents(enrichedEvents, position);
      } catch (e) {
        return enrichedEvents; // Return without distance if fails
      }
    });
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

  Future<String> createEvent(Event event, File? imageFile) async {
    try {
      String? imageUrl;
      
      // Upload Image if present
      if (imageFile != null) {
        final ref = _storage.ref().child('event_images/${event.id}');
        await ref.putFile(imageFile);
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
  }

  // Helper to remove user from event chat
  Future<void> _removeUserFromEventChat(String chatId, String userId) async {
      await _rtdb.ref('userChats/$userId/$chatId').remove();
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
  Stream<List<Event>> getUserEvents(String userId) async* {
    // 1. Yield Cached First
    final cachedData = LocalCacheService.getMyCachedEvents();
    final cachedEvents = cachedData.map((d) {
        try { return Event.fromJson(d); } catch(_) { return null; }
    }).whereType<Event>().where((e) => e.creatorId == userId).toList();
    
    if (cachedEvents.isNotEmpty) {
       yield await _enrichEvents(cachedEvents);
    }
    
    // 2. Listen to Firestore
    yield* _firestore
        .collection('events')
        .where('creatorId', isEqualTo: userId)
        .snapshots()
        .asyncMap((snapshot) async {
      final firestoreEvents = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        try {
          return Event.fromJson(data);
        } catch (e) {
             return null;
        }
      }).whereType<Event>().toList();
      
      // Merge: prefer Firestore, but include local if missing
      final mergedMap = {for (var e in firestoreEvents) e.id: e};
      for (var e in cachedEvents) {
         if (!mergedMap.containsKey(e.id)) {
            mergedMap[e.id] = e;
         }
      }
      
      final events = mergedMap.values.toList();
      
      // Enrich & Add Distance
      final enriched = await _enrichEvents(events);
      
      try {
         final position = await Geolocator.getCurrentPosition();
         return await _addDistancesToEvents(enriched, position);
      } catch (e) {
         return enriched;
      }
    });
  }

  // Fetch events where the user is an attendee (Joined Events)
  Stream<List<Event>> getJoinedEvents(String userId) async* {
    // 1. Yield Cached First
    final cachedData = LocalCacheService.getMyCachedEvents();
    final cachedEvents = cachedData.map((d) {
        try { return Event.fromJson(d); } catch(_) { return null; }
    }).whereType<Event>().where((e) => e.attendees?.contains(userId) ?? false).toList();
    
    if (cachedEvents.isNotEmpty) {
       yield await _enrichEvents(cachedEvents);
    }

    yield* _firestore
        .collection('events')
        .where('attendees', arrayContains: userId)
        .snapshots()
        .asyncMap((snapshot) async {
      final firestoreEvents = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        try {
          return Event.fromJson(data);
        } catch (e) {
             return null;
        }
      }).whereType<Event>().toList();

      // Merge check
      final mergedMap = {for (var e in firestoreEvents) e.id: e};
      for (var e in cachedEvents) {
         if (!mergedMap.containsKey(e.id)) {
            mergedMap[e.id] = e;
         }
      }
      final events = mergedMap.values.toList();

      // Enrich & Add Distance
      final enriched = await _enrichEvents(events);
      
      try {
         final position = await Geolocator.getCurrentPosition();
         return await _addDistancesToEvents(enriched, position);
      } catch (e) {
         return enriched;
      }
    });
  }

  // Update Event
  Future<void> updateEvent(Event event, File? newImage) async {
    try {
      final data = event.toJson();
      
      // If new image provided, upload it
      if (newImage != null) {
         final ref = _storage.ref().child('event_images/${event.id}');
         await ref.putFile(newImage);
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



