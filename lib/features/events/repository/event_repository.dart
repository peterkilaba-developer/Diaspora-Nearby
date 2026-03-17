import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:image_picker/image_picker.dart';
import 'package:diaspora_nearby/features/travel/utils/geo_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/events/models/event_data.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'package:diaspora_nearby/config/env.dart';
import 'package:diaspora_nearby/features/events/repository/event_local_service.dart';
import 'package:diaspora_nearby/features/trust/repository/trust_repository.dart';
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';

final eventRepositoryProvider = Provider<EventRepository>((ref) {
  return EventRepository(
    cf.FirebaseFirestore.instance,
    FirebaseStorage.instance,
    ref,
  );
});

final eventDetailsProvider = FutureProvider.family<Event?, String>((
  ref,
  eventId,
) {
  return ref.read(eventRepositoryProvider).getEvent(eventId);
});

final userEventsProvider = StreamProvider.family<List<Event>, String>((
  ref,
  userId,
) {
  return ref.watch(eventRepositoryProvider).getUserEvents(userId);
});

final joinedEventsProvider = StreamProvider.family<List<Event>, String>((
  ref,
  userId,
) {
  return ref.watch(eventRepositoryProvider).getJoinedEvents(userId);
});

enum VerificationResult { success, invalidCode, alreadyCheckedIn, error }

class EventRepository {
  final cf.FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final Ref _ref;

  final EventLocalService _localService;

  // Cache for geocoding results
  final Map<String, Map<String, double>> _geocodingCache = {};

  EventRepository(this._firestore, this._storage, this._ref)
    : _localService = EventLocalService();
  // isGlobal: false -> Show only events where creator's homeCountryCode matches current user's
  // ============================================
  // FETCHING & STREAMS
  // ============================================

  Stream<List<Event>> getEvents({
    bool isGlobal = false,
    String? homeCountryCode,
    required String currentUserId,
    required List<String> userCommunityMemberships,
  }) {
    // 1. Trigger Sync (Fire and Forget)
    _syncEvents(isGlobal: isGlobal, homeCountryCode: homeCountryCode);

    // 2. Watch Local DB
    // We watch ALL events and filter in memory because filtering logic (permissions) is complex
    // and datasets are relatively small for events (< 1000 active usually).
    // Optimization: Filter by date in Isar query.

    // 2. Watch Local DB (Native)
    // On Web, we fall back to Firestore logic above if kIsWeb check was passed
    if (kIsWeb) {
      // WEB: Direct Firestore watch with basic filtering
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
            final todayStr =
                "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

            return events.where((event) {
              // Show events until midnight after they end
              final effectiveEndDate =
                  (event.endDate != null && event.endDate!.isNotEmpty)
                  ? event.endDate!
                  : event.startDate;
              if (effectiveEndDate.compareTo(todayStr) < 0) return false;

              // Visibility Logic (Reproduced from mobile logic)
              final permission = event.attendingPermission;
              final creatorId = event.creatorId;

              if (creatorId == currentUserId) return true;
              if (permission == null ||
                  permission == 'global' ||
                  permission == 'all') {
                return true;
              }
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

    return _localService.watchFutureEvents().asyncMap((events) async {
      final filteredEvents = events.where((event) {
        // Visibility Logic (Reproduced from original)
        final permission = event.attendingPermission;
        final creatorId = event.creatorId;

        // 1. Creator always sees their event
        if (creatorId == currentUserId) return true;

        // 1.5 Must be published for others
        if (event.status != 'published') return false;

        // 2. Global/Public
        if (permission == null ||
            permission == 'global' ||
            permission == 'all') {
          return true;
        }

        // 2.1 Country Filter (If not global view)
        if (!isGlobal && homeCountryCode != null) {
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
      filteredEvents.sort((a, b) => a.startDate.compareTo(b.startDate));

      // Enrich with Distance (Client-side, uses Geolocator)
      try {
        final position = await Geolocator.getCurrentPosition();
        return await _addDistancesToEvents(filteredEvents, position);
      } catch (e) {
        return filteredEvents;
      }
    });
  }

  Future<void> _syncEvents({
    bool isGlobal = false,
    String? homeCountryCode,
  }) async {
    try {
      // Only sync active events
      final today = DateTime.now();
      final todayStr =
          "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

      cf.Query query = _firestore
          .collection('events')
          .where('startDate', isGreaterThanOrEqualTo: todayStr);

      if (!isGlobal && homeCountryCode != null) {
        query = query.where('homeCountryCode', isEqualTo: homeCountryCode);
      }

      // [OPTIMIZATION] Limit to 50 events for scalability
      query = query.limit(50);

      final snapshot = await query.get();
      final events = <Event>[];

      for (var doc in snapshot.docs) {
        try {
          final data = doc.data() as Map<String, dynamic>;
          data['id'] = doc.id;
          events.add(Event.fromJson(data));
        } catch (_) {}
      }

      // Enrich with Creator Profiles (Fetch from Firestore to store Name/Photo in Isar)
      final enrichedEvents = await _enrichEvents(events);

      await _localService.saveEvents(enrichedEvents);
    } catch (e) {
      debugPrint('Error syncing events: $e');
    }
  }

  // Enrich events with creator profiles
  Future<List<Event>> _enrichEvents(List<Event> events) async {
    final creatorIds = events.map((e) => e.creatorId).toSet().toList();
    if (creatorIds.isEmpty) return events;

    // Fetch profiles
    final profiles = <String, Map<String, dynamic>>{};

    final futures = creatorIds.map(
      (id) => _firestore.collection('users').doc(id).get(),
    );
    final snapshots = await Future.wait(futures);

    for (var doc in snapshots) {
      if (doc.exists) {
        profiles[doc.id] = doc.data()!;
      }
    }

    for (var event in events) {
      final profile = profiles[event.creatorId];
      if (profile != null) {
        event.creatorName =
            '${profile['firstName'] ?? ''} ${profile['lastName'] ?? ''}'.trim();
        event.creatorPhoto = profile['profilePhoto']; // Use Firestore key
      }
    }

    return events;
  }

  // Add distances to events
  Future<List<Event>> _addDistancesToEvents(
    List<Event> events,
    Position userLocation,
  ) async {
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
        event.distance = GeoUtils.haversine(
          userLocation.latitude,
          userLocation.longitude,
          lat,
          lng,
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
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(address)}&key=$apiKey',
      );

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

  // Fetch Single Event by ID
  Future<Event?> getEvent(String eventId, {bool force = false}) async {
    // 1. Try Local
    if (!force) {
      final localEvent = await _localService.getEvent(eventId);
      if (localEvent != null) {
        // Background refresh
        _fetchAndSaveEvent(eventId);
        return localEvent;
      }
    }

    return await _fetchAndSaveEvent(eventId);
  }

  Future<Event?> _fetchAndSaveEvent(String eventId) async {
    try {
      final doc = await _firestore.collection('events').doc(eventId).get();
      if (!doc.exists) return null;

      final data = doc.data()!;
      data['id'] = doc.id;

      final event = Event.fromJson(data);

      // Enrich with Creator Info
      final enrichedEvents = await _enrichEvents([event]);
      final finalEvent = enrichedEvents.first;

      // Calculate Distance (Optional for details, but good for cache)
      try {
        final position = await Geolocator.getCurrentPosition();
        final withDistance = await _addDistancesToEvents([
          finalEvent,
        ], position);
        final enrichedWithDist = withDistance.first;

        // Save to Isar
        await _localService.saveEvent(enrichedWithDist);
        return enrichedWithDist;
      } catch (e) {
        // Save without distance
        await _localService.saveEvent(finalEvent);
        return finalEvent;
      }
    } catch (e) {
      debugPrint('Error fetching/saving event: $e');
      return null;
    }
  }

  Future<String> createEvent(Event event, XFile? imageFile) async {
    try {
      String? imageUrl;

      // Upload Image if present
      if (imageFile != null) {
        final ref = _storage.ref().child('event_images/${event.id}');
        final metadata = SettableMetadata(
          cacheControl: 'public, max-age=31536000',
          contentType: 'image/jpeg',
        );

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
      final eventDataWithId = Event.fromJson(eventData);
      await _localService.saveEvent(eventDataWithId);

      // 2. Save to Firestore
      await _firestore.collection('events').doc(event.id).set(eventData);

      await _createEventChat(
        event.id,
        event.title,
        event.creatorId,
        imageUrl,
        event.invitedUserIds,
      );

      return event.id;
    } catch (e) {
      debugPrint('Error creating event: $e');
      rethrow;
    }
  }

  // Create Event Chat in Firestore
  Future<void> _createEventChat(
    String eventId,
    String title,
    String creatorId,
    String? imageUrl,
    List<String>? invitedUserIds,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final chatId = 'event_$eventId'; // Deterministic ID

    final allParticipants = <String>[creatorId];
    if (invitedUserIds != null && invitedUserIds.isNotEmpty) {
      for (final uid in invitedUserIds) {
        if (!allParticipants.contains(uid)) allParticipants.add(uid);
      }
    }

    // 1. Create chat document in Firestore
    final chatData = {
      'id': chatId,
      'type': 'event',
      'eventId': eventId,
      'name': title,
      'photoUrl': imageUrl,
      'createdAt': now,
      'updatedAt': now,
      'createdBy': creatorId,
      'memberCount': allParticipants.length,
      'participants': allParticipants,
    };

    await _firestore.collection('chats').doc(chatId).set(chatData);

    // 2. Add all participants to their userChats subcollection
    final batch = _firestore.batch();
    for (final userId in allParticipants) {
      final userChatRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('userChats')
          .doc(chatId);
      batch.set(userChatRef, {'chatId': chatId, 'updatedAt': now});
    }
    await batch.commit();

    // 3. Update Event with chatId
    await _firestore.collection('events').doc(eventId).update({
      'chatId': chatId,
    });
  }

  // Helper to add user to event chat (Firestore)
  Future<void> _addUserToEventChat(
    String chatId,
    String userId,
    String chatName,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // 1. Add to userChats subcollection
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('userChats')
        .doc(chatId)
        .set({'chatId': chatId, 'updatedAt': now}, cf.SetOptions(merge: true));

    // 2. Add to participants array in chat document
    await _firestore.collection('chats').doc(chatId).update({
      'participants': cf.FieldValue.arrayUnion([userId]),
    });
  }

  // Helper to remove user from event chat (Firestore)
  Future<void> _removeUserFromEventChat(String chatId, String userId) async {
    // 1. Remove from userChats subcollection
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('userChats')
        .doc(chatId)
        .delete();

    // 2. Remove from participants array in chat document
    await _firestore.collection('chats').doc(chatId).update({
      'participants': cf.FieldValue.arrayRemove([userId]),
    });
  }

  // Attend Event (RSVP)
  Future<void> joinEvent(String eventId, String userId) async {
    // 0. Fetch event to check if it's paid
    final eventDoc = await _firestore.collection('events').doc(eventId).get();
    if (!eventDoc.exists) throw Exception('Event not found');
    final event = Event.fromJson(eventDoc.data()!);

    // 1. Update Firestore atomically
    await _firestore.collection('events').doc(eventId).update({
      'attendees': cf.FieldValue.arrayUnion([userId]),
      'attendeeCount': cf.FieldValue.increment(1),
    });

    // 1.1 Track joined event for trust
    try {
      final trustRepo = _ref.read(trustRepositoryProvider);
      await trustRepo.incrementJoinedEventsCount(userId);
    } catch (e) {
      debugPrint('Error updating trustJoinedEvents: $e');
    }

    // 1.2 Record fiat GDP for paid events
    if (event.isPaid == true &&
        event.ticketPrice != null &&
        event.ticketPrice! > 0) {
      try {
        await _ref
            .read(pointsServiceProvider)
            .recordFiatGdp(
              amount: event.ticketPrice!,
              countryCode: event.hostCountryCode,
              activityType: 'event_ticket_purchase',
              metadata: {
                'eventId': eventId,
                'attendeeId': userId,
                'creatorId': event.creatorId,
              },
            );
      } catch (e) {
        debugPrint('⚠️ [GDP] Record event ticket GDP error: $e');
      }
    }

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
          debugPrint('JoinEvent Chat Error (Ignored): $e');
        }
      }
    }

    // 3. Refresh Local Cache
    await getEvent(eventId, force: true);
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
          debugPrint('LeaveEvent Chat Error (Ignored): $e');
        }
      }
    }

    // 3. Refresh Local Cache
    await getEvent(eventId, force: true);
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
    // In a real app, this should be a signed JWT or similar.
    // For now, we use a simple format that verifies the event ID.
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'attendance:$eventId:$timestamp';
  }

  // Verify and Mark Attendance
  Future<VerificationResult> verifyAndMarkAttendance(
    String eventId,
    String userId,
    String code,
  ) async {
    try {
      // 1. Verify Code Format
      if (!code.startsWith('attendance:$eventId:')) {
        debugPrint(
          '❌ Attendance Verification Failed: Invalid Code Format or Event ID Mismatch',
        );
        return VerificationResult.invalidCode;
      }

      // 2. Check if already attended
      final eventDoc = await _firestore.collection('events').doc(eventId).get();
      if (eventDoc.exists) {
        final data = eventDoc.data();
        final confirmed = List<String>.from(data?['confirmedAttendees'] ?? []);
        if (confirmed.contains(userId)) {
          debugPrint('⚠️ User already checked in.');
          return VerificationResult
              .alreadyCheckedIn; // Prevent duplicate check-in
        }
      }

      // 3. Mark Attendance in Firestore
      // We use arrayUnion to ensure uniqueness
      await _firestore.collection('events').doc(eventId).update({
        'confirmedAttendees': cf.FieldValue.arrayUnion([userId]),
      });

      // 4. Trigger Physical Presence Check-In via TrustService
      // This awards DSP and updates Trust Score
      final trustService = _ref.read(trustServiceProvider);

      // We perform the check-in with a placeholder location for now.
      // In a more advanced implementation, we would verify the user's location matches the event's venue.
      await trustService.performCheckIn(
        userId: userId,
        entityId: eventId,
        type: 'event',
        lat: 0.0,
        lng: 0.0,
      );

      return VerificationResult.success;
    } catch (e) {
      debugPrint('Error verifying/marking attendance: $e');
      return VerificationResult.error;
    }
  }

  // Fetch events created by a specific user
  // Fetch events created by a specific user
  Stream<List<Event>> getUserEvents(String userId) {
    _syncUserEvents(userId);

    if (kIsWeb) return const Stream.empty(); // Web handling if needed
    return _localService.watchUserEvents(userId);
  }

  // Fetch events where the user is an attendee (Joined Events)
  Stream<List<Event>> getJoinedEvents(String userId) {
    _syncJoinedEvents(userId);

    if (kIsWeb) return const Stream.empty(); // Web handling if needed
    return _localService.watchJoinedEvents(userId);
  }

  Future<void> _syncUserEvents(String uid) async {
    try {
      final snapshot = await _firestore
          .collection('events')
          .where('creatorId', isEqualTo: uid)
          .get();

      final events = snapshot.docs.map((doc) {
        final data = doc.data();
        return Event.fromJson({...data, 'id': doc.id});
      }).toList();

      await _localService.saveEvents(events);
    } catch (e) {
      debugPrint('EventRepository: Error syncing user events: $e');
    }
  }

  Future<void> _syncJoinedEvents(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('events')
          .where('attendees', arrayContains: userId)
          .get();

      final events = snapshot.docs
          .map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            try {
              return Event.fromJson(data);
            } catch (_) {
              return null;
            }
          })
          .whereType<Event>()
          .toList();

      await _localService.saveEvents(events);
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
        final metadata = SettableMetadata(
          cacheControl: 'public, max-age=31536000',
          contentType: 'image/jpeg',
        );

        if (kIsWeb) {
          final bytes = await newImage.readAsBytes();
          await ref.putData(bytes, metadata);
        } else {
          await ref.putFile(File(newImage.path), metadata);
        }
        final imageUrl = await ref.getDownloadURL();
        data['imageUrl'] = imageUrl;

        // Also update chat image in Firestore if exists
        final chatId = event.chatId;
        if (chatId != null) {
          await _firestore.collection('chats').doc(chatId).update({
            'photoUrl': imageUrl,
          });
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

      // Ensure paid fields are explicitly set (not reliant on toJson nullability)
      data['isPaid'] = event.isPaid ?? false;
      if (event.isPaid == true && event.ticketPrice != null) {
        data['ticketPrice'] = event.ticketPrice;
      } else {
        data['ticketPrice'] = cf.FieldValue.delete();
      }

      await _firestore.collection('events').doc(event.id).update(data);

      // Update Chat Name in Firestore if title changed
      if (event.chatId != null) {
        await _firestore.collection('chats').doc(event.chatId).update({
          'name': event.title,
        });
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

      // 4. Delete Chat (Firestore)
      if (chatId != null) {
        // Remove chat document
        await _firestore.collection('chats').doc(chatId).delete();

        // Remove from all attendees' userChats
        final attendees = List<String>.from(data['attendees'] ?? []);
        final batch = _firestore.batch();
        for (var userId in attendees) {
          batch.delete(
            _firestore
                .collection('users')
                .doc(userId)
                .collection('userChats')
                .doc(chatId),
          );
        }
        await batch.commit();
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
      final todayStr =
          "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

      final snapshot = await _firestore
          .collection('events')
          .where('startDate', isGreaterThanOrEqualTo: todayStr)
          .get();

      final events = snapshot.docs
          .map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            try {
              return Event.fromJson(data);
            } catch (e) {
              return null;
            }
          })
          .whereType<Event>()
          .where((event) {
            if (query.isEmpty) return true;
            return event.title.toLowerCase().contains(queryLower);
          })
          .toList();

      return await _enrichEvents(events);
    } catch (e) {
      return [];
    }
  }
}
