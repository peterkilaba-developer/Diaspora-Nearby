import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:image_picker/image_picker.dart';
import 'package:diaspora_nearby/features/travel/utils/geo_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/events/models/event_data.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'package:diaspora_nearby/config/env.dart';
import 'package:diaspora_nearby/features/events/repository/event_local_service.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';

final eventRepositoryProvider = Provider<EventRepository>((ref) {
  return EventRepository(
    cf.FirebaseFirestore.instance,
    FirebaseStorage.instance,
    ref,
  );
});

final eventDetailsStreamProvider = StreamProvider.family<Event?, String>((
  ref,
  eventId,
) {
  return ref.watch(eventRepositoryProvider).watchEvent(eventId);
});

final eventDetailsProvider = FutureProvider.family<Event?, String>((
  ref,
  eventId,
) async {
  final cached = ref.read(eventRepositoryProvider).getCachedEvent(eventId);
  if (cached != null) return cached;
  return ref.watch(eventDetailsStreamProvider(eventId).future);
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

final allRawEventsStreamProvider = StreamProvider<List<Event>>((ref) {
  return ref.watch(eventRepositoryProvider).watchAllRawEvents();
});

enum VerificationResult { success, invalidCode, alreadyCheckedIn, error }

class EventRepository {
  final cf.FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final Ref _ref;

  final EventLocalService _localService;

  // Cache for geocoding results
  static final Map<String, Map<String, double>> _geocodingCache = {};

  // [PERF] In-memory cache of events by ID for instant detail views & optimistic updates
  static final Map<String, Event> _eventsByIdCache = {};

  // [PERF] Pre-warmed attendance QR codes by eventId
  static final Map<String, String> _attendanceCodeCache = {};

  /// [PERF] Synchronously read a cached event by ID
  Event? getCachedEvent(String eventId) => _eventsByIdCache[eventId];

  /// [PERF] Synchronously read all cached raw events
  List<Event> get cachedRawEvents => _eventsByIdCache.values.toList();

  /// [PERF] Synchronously write or update an event in memory cache
  void cacheEvent(Event event) {
    _eventsByIdCache[event.id] = event;
  }

  /// [PERF] Synchronously remove an event from memory cache
  void removeCachedEvent(String eventId) {
    _eventsByIdCache.remove(eventId);
  }

  /// [PERF] Synchronously read pre-warmed attendance code
  String? getCachedAttendanceCode(String eventId) =>
      _attendanceCodeCache[eventId];

  /// [PERF] Pre-warm attendance code in background
  Future<void> prewarmAttendanceCode(String eventId) async {
    if (_attendanceCodeCache.containsKey(eventId)) return;
    try {
      await generateAttendanceCode(eventId);
    } catch (_) {}
  }

  EventRepository(this._firestore, this._storage, this._ref)
    : _localService = EventLocalService();
  // isGlobal: false -> Show only events where creator's homeCountryCode matches current user's
  // ============================================
  // FETCHING & STREAMS
  // ============================================

  /// Apply any already-cached creator profile & geocoding data synchronously
  /// so the event list can emit on frame 0 without waiting on network calls.
  List<Event> _applySyncEnrichment(List<Event> events) {
    final profileRepo = _ref.read(profileRepositoryProvider);
    final result = <Event>[];
    for (var event in events) {
      if (event.creatorId.isNotEmpty &&
          (event.creatorName == null || event.creatorName!.isEmpty)) {
        final cachedProfile = profileRepo.getCachedProfile(event.creatorId);
        if (cachedProfile != null) {
          event.creatorName =
              '${cachedProfile.firstName} ${cachedProfile.lastName}'.trim();
          event.creatorPhoto = cachedProfile.profileImage;
        }
      }
      if ((event.latitude == null || event.longitude == null) &&
          event.location.isNotEmpty &&
          _geocodingCache.containsKey(event.location)) {
        final coords = _geocodingCache[event.location]!;
        final updatedJson = event.toJson()
          ..['latitude'] = coords['lat']
          ..['longitude'] = coords['lng']
          ..['id'] = event.id;
        event = Event.fromJson(updatedJson)
          ..creatorName = event.creatorName
          ..creatorPhoto = event.creatorPhoto;
      }
      _eventsByIdCache[event.id] = event;
      result.add(event);
    }
    return result;
  }

  Stream<List<Event>> watchAllRawEvents() {
    return Stream.multi((controller) {
      if (_eventsByIdCache.isNotEmpty) {
        controller.add(_eventsByIdCache.values.toList());
      }
      final sub = _firestore
          .collection('events')
          .limit(200)
          .snapshots()
          .listen(
            (snapshot) async {
              final events = snapshot.docs
                  .map((doc) {
                    try {
                      final data = doc.data();
                      return Event.fromJson({...data, 'id': doc.id});
                    } catch (e) {
                      debugPrint('Error parsing event ${doc.id}: $e');
                      return null;
                    }
                  })
                  .whereType<Event>()
                  .toList();

              // 1. Emit immediately with synchronous cache enrichment (0ms delay)
              final immediate = _applySyncEnrichment(events);
              if (!controller.isClosed) {
                controller.add(immediate);
              }

              // 2. Enrich missing creator profiles / coordinates in the background
              final enriched = await _enrichEvents(immediate);
              for (final e in enriched) {
                _eventsByIdCache[e.id] = e;
              }
              if (!controller.isClosed) {
                controller.add(enriched);
              }
            },
            onError: controller.addError,
            onDone: controller.close,
          );
      controller.onCancel = sub.cancel;
    });
  }

  /// Returns true if the event has already ended (past its end date/time, or past midnight of its end date).
  static bool isEventExpired(Event event, [DateTime? now]) {
    final current = now ?? DateTime.now();
    final todayStr =
        "${current.year}-${current.month.toString().padLeft(2, '0')}-${current.day.toString().padLeft(2, '0')}";

    final effectiveEndDate =
        (event.endDate != null && event.endDate!.isNotEmpty)
        ? event.endDate!
        : event.startDate;

    if (effectiveEndDate.isEmpty) return false;

    // Strictly before today -> expired
    if (effectiveEndDate.compareTo(todayStr) < 0) {
      return true;
    }

    // If the event ends today and has an explicit endTime, check if endTime has passed
    if (effectiveEndDate == todayStr) {
      final timeStr = (event.endTime != null && event.endTime!.isNotEmpty)
          ? event.endTime!
          : '';
      if (timeStr.isNotEmpty) {
        final parts = timeStr.split(':');
        if (parts.length >= 2) {
          final hour = int.tryParse(parts[0]);
          final minute = int.tryParse(parts[1]);
          if (hour != null && minute != null) {
            final endDateTime = DateTime(
              current.year,
              current.month,
              current.day,
              hour,
              minute,
            );
            if (current.isAfter(endDateTime)) {
              return true;
            }
          }
        }
      }
    }

    return false;
  }

  List<Event> filterVisibleEvents(
    List<Event> events, {
    bool isGlobal = false,
    String? homeCountryCode,
    required String currentUserId,
    required List<String> userCommunityMemberships,
  }) {
    final now = DateTime.now();

    final filteredEvents = events.where((event) {
      final permission = event.attendingPermission;
      final creatorId = event.creatorId;

      // 0. Never show expired events on the main discovery feed (even to creator/attendees;
      // creators can still view/manage past events in Event Dashboard -> Manage).
      if (isEventExpired(event, now)) {
        return false;
      }

      // 1. Must be published to appear on the main discovery feed
      if (event.status != 'published') return false;

      // 1.5 Creator or RSVP'd attendee always sees upcoming published events
      if (creatorId == currentUserId) return true;
      if (event.attendees?.contains(currentUserId) ?? false) return true;

      // 2. Country Filter (If not global view)
      if (!isGlobal && homeCountryCode != null && homeCountryCode.isNotEmpty) {
        final eventHomeCode = event.homeCountryCode?.toUpperCase();
        final targetHomeCode = homeCountryCode.toUpperCase();
        if (eventHomeCode != null &&
            eventHomeCode.isNotEmpty &&
            eventHomeCode != targetHomeCode) {
          return false;
        }
      }

      // 3. Global/Public
      if (permission == null ||
          permission == 'global' ||
          permission == 'global_community' ||
          permission == 'all') {
        return true;
      }

      // 4. Private
      if (permission == 'private') {
        return event.invitedUserIds?.contains(currentUserId) ?? false;
      }

      // 5. Community Membership (also allow if event belongs to user's home country diaspora)
      if (userCommunityMemberships.contains(permission)) {
        return true;
      }
      if (homeCountryCode != null && homeCountryCode.isNotEmpty) {
        final lowerCode = homeCountryCode.toLowerCase();
        if (permission == 'home_country_$lowerCode' ||
            permission.endsWith('_$lowerCode') ||
            event.homeCountryCode?.toUpperCase() ==
                homeCountryCode.toUpperCase()) {
          return true;
        }
      }
      return false;
    }).toList();

    // Sort by Start Date + Start Time (soonest upcoming first)
    filteredEvents.sort((a, b) {
      final dateCmp = a.startDate.compareTo(b.startDate);
      if (dateCmp != 0) return dateCmp;
      return a.startTime.compareTo(b.startTime);
    });
    return filteredEvents;
  }

  Stream<List<Event>> getEvents({
    bool isGlobal = false,
    String? homeCountryCode,
    required String currentUserId,
    required List<String> userCommunityMemberships,
  }) {
    return watchAllRawEvents().map(
      (events) => filterVisibleEvents(
        events,
        isGlobal: isGlobal,
        homeCountryCode: homeCountryCode,
        currentUserId: currentUserId,
        userCommunityMemberships: userCommunityMemberships,
      ),
    );
  }

  // Enrich events with creator profiles and missing coordinates
  Future<List<Event>> _enrichEvents(List<Event> events) async {
    final profileRepo = _ref.read(profileRepositoryProvider);
    final creatorIds = events
        .map((e) => e.creatorId)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (creatorIds.isNotEmpty) {
      final profiles = await profileRepo.getProfiles(creatorIds);
      final profileMap = {
        for (final p in profiles)
          if (p.uid != null) p.uid!: p,
      };

      for (var event in events) {
        final profile =
            profileMap[event.creatorId] ??
            profileRepo.getCachedProfile(event.creatorId);
        if (profile != null) {
          event.creatorName = '${profile.firstName} ${profile.lastName}'.trim();
          event.creatorPhoto = profile.profileImage;
        }
      }
    }

    // Geocode any legacy events that are missing latitude/longitude in parallel
    final result = await Future.wait(
      events.map((event) async {
        if ((event.latitude == null || event.longitude == null) &&
            event.location.isNotEmpty) {
          try {
            final coords = await _geocodeAddress(event.location);
            if (coords != null &&
                coords['lat'] != null &&
                coords['lng'] != null) {
              final updatedJson = event.toJson()
                ..['latitude'] = coords['lat']
                ..['longitude'] = coords['lng']
                ..['id'] = event.id;
              return Event.fromJson(updatedJson)
                ..creatorName = event.creatorName
                ..creatorPhoto = event.creatorPhoto;
            }
          } catch (_) {}
        }
        return event;
      }),
    );

    return result;
  }

  // Add distances to events (parallelized geocoding)
  Future<List<Event>> _addDistancesToEvents(
    List<Event> events,
    Position userLocation,
  ) async {
    await Future.wait(
      events.map((event) async {
        double? lat, lng;

        // 1. Prefer stored coordinates (Fast & Scalable)
        if (event.latitude != null && event.longitude != null) {
          lat = event.latitude;
          lng = event.longitude;
        }
        // 2. Legacy Fallback (Parallel Read-time Geocoding)
        else if (event.location.isNotEmpty) {
          try {
            final coordinates = await _geocodeAddress(event.location);
            if (coordinates != null) {
              lat = coordinates['lat'];
              lng = coordinates['lng'];
            }
          } catch (_) {}
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
      }),
    );

    // Sort by distance (closest first), then by Start Date (soonest first)
    events.sort((a, b) {
      // 1. Distance Comparison
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

      final response = await http.get(url).timeout(const Duration(seconds: 3));
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

  // Watch Single Event by ID in real time
  Stream<Event?> watchEvent(String eventId) {
    return Stream.multi((controller) {
      final cached = _eventsByIdCache[eventId];
      if (cached != null) {
        controller.add(cached);
      }
      final sub = _firestore
          .collection('events')
          .doc(eventId)
          .snapshots()
          .listen(
            (doc) async {
              if (!doc.exists || doc.data() == null) {
                if (!controller.isClosed) controller.add(null);
                return;
              }
              try {
                final data = doc.data()!;
                final rawEvent = Event.fromJson({...data, 'id': doc.id});
                final immediate = _applySyncEnrichment([rawEvent]).first;
                if (!controller.isClosed) {
                  controller.add(immediate);
                }
                final enriched = await _enrichEvents([immediate]);
                final finalEvent = enriched.isNotEmpty
                    ? enriched.first
                    : immediate;
                _eventsByIdCache[eventId] = finalEvent;
                unawaited(_localService.saveEvent(finalEvent));
                if (!controller.isClosed) {
                  controller.add(finalEvent);
                }
              } catch (e) {
                debugPrint('Error watching event $eventId: $e');
              }
            },
            onError: controller.addError,
            onDone: controller.close,
          );
      controller.onCancel = sub.cancel;
    });
  }

  // Fetch Single Event by ID
  Future<Event?> getEvent(String eventId, {bool force = false}) async {
    // 1. Try Memory Cache
    if (!force && _eventsByIdCache.containsKey(eventId)) {
      unawaited(_fetchAndSaveEvent(eventId));
      return _eventsByIdCache[eventId];
    }
    // 2. Try Local
    if (!force) {
      final localEvent = await _localService.getEvent(eventId);
      if (localEvent != null) {
        _eventsByIdCache[eventId] = localEvent;
        // Background refresh
        unawaited(_fetchAndSaveEvent(eventId));
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
      final syncEnriched = _applySyncEnrichment([event]).first;

      // Enrich with Creator Info
      final enrichedEvents = await _enrichEvents([syncEnriched]);
      final finalEvent = enrichedEvents.first;
      _eventsByIdCache[eventId] = finalEvent;
      unawaited(_localService.saveEvent(finalEvent));

      // Update distance in background without delaying return
      unawaited(() async {
        try {
          final position = await Geolocator.getLastKnownPosition();
          if (position != null) {
            final withDistance = await _addDistancesToEvents([
              finalEvent,
            ], position);
            final enrichedWithDist = withDistance.first;
            _eventsByIdCache[eventId] = enrichedWithDist;
            await _localService.saveEvent(enrichedWithDist);
          }
        } catch (_) {}
      }());

      return finalEvent;
    } catch (e) {
      debugPrint('Error fetching/saving event: $e');
      return null;
    }
  }

  Future<String> createEvent(Event event, XFile? imageFile) async {
    try {
      if (event.isPaid == true) {
        throw UnsupportedError(
          'Paid events are disabled until verified ticket checkout is configured.',
        );
      }

      // Creator joins automatically
      event.attendees = [event.creatorId];
      event.attendeeCount = 1;
      event.chatId = 'event_${event.id}';

      // Optimistically store in memory cache on frame 0
      _applySyncEnrichment([event]);

      final eventData = event.toJson();
      eventData['attendees'] = [event.creatorId];
      eventData['attendeeCount'] = 1;
      eventData['createdAt'] = DateTime.now().toIso8601String();
      eventData['chatId'] = 'event_${event.id}';

      // Geo-enrichment
      if ((event.latitude == null || event.longitude == null) &&
          event.location.isNotEmpty) {
        try {
          final coordinates = await _geocodeAddress(event.location);
          if (coordinates != null) {
            eventData['latitude'] = coordinates['lat'];
            eventData['longitude'] = coordinates['lng'];
          }
        } catch (_) {}
      }

      // Create the canonical event first. Storage rules verify ownership by
      // reading this document, so uploading before this write is denied.
      await _firestore.collection('events').doc(event.id).set(eventData);

      String? imageUrl;
      try {
        if (imageFile != null) {
          final storageRef = _storage.ref().child('event_images/${event.id}');
          final metadata = SettableMetadata(
            cacheControl: 'public, max-age=31536000',
            contentType: 'image/jpeg',
          );
          if (kIsWeb) {
            final bytes = await imageFile.readAsBytes();
            await storageRef.putData(bytes, metadata);
          } else {
            await storageRef.putFile(File(imageFile.path), metadata);
          }
          imageUrl = await storageRef.getDownloadURL();
          eventData['imageUrl'] = imageUrl;
          event.imageUrl = imageUrl;
          _eventsByIdCache[event.id] = event;
          await _firestore.collection('events').doc(event.id).update({
            'imageUrl': imageUrl,
          });
        }
      } catch (_) {
        _eventsByIdCache.remove(event.id);
        await _firestore.collection('events').doc(event.id).delete();
        rethrow;
      }

      final finalEvent = Event.fromJson({...eventData, 'id': event.id})
        ..creatorName = event.creatorName
        ..creatorPhoto = event.creatorPhoto;
      _eventsByIdCache[event.id] = finalEvent;
      unawaited(_localService.saveEvent(finalEvent));
      unawaited(_createEventChat(event.id, event.invitedUserIds));

      return event.id;
    } catch (e) {
      debugPrint('Error creating event: $e');
      rethrow;
    }
  }

  // Create Event Chat in Firestore
  Future<void> _createEventChat(
    String eventId,
    List<String>? invitedUserIds,
  ) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('createChat')
          .call<Map<String, dynamic>>({'mode': 'event', 'eventId': eventId});
      final chatId = result.data['chatId'] as String?;
      if (chatId == null) return;

      final members = (invitedUserIds ?? const <String>[])
          .toSet()
          .take(99)
          .toList();
      if (members.isNotEmpty) {
        await Future.wait(
          members.map(
            (userId) => FirebaseFunctions.instance
                .httpsCallable('manageChatMembers')
                .call<void>({'chatId': chatId, 'inviteUserId': userId}),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error creating event chat: $e');
    }
  }

  // Attend Event (RSVP)
  Future<void> joinEvent(String eventId, String userId) async {
    // Optimistically update in-memory cache immediately
    final cached = _eventsByIdCache[eventId];
    if (cached != null) {
      final updatedAttendees = <String>{...?cached.attendees, userId}.toList();
      cached.attendees = updatedAttendees;
      cached.attendeeCount = updatedAttendees.length;
    }

    await FirebaseFunctions.instance.httpsCallable('setEventAttendance').call({
      'eventId': eventId,
      'attending': true,
    });

    // Record fiat GDP and refresh cache in the background without blocking caller
    unawaited(() async {
      try {
        Event? event = cached ?? _eventsByIdCache[eventId];
        if (event == null) {
          final eventDoc = await _firestore
              .collection('events')
              .doc(eventId)
              .get();
          if (eventDoc.exists && eventDoc.data() != null) {
            event = Event.fromJson({...eventDoc.data()!, 'id': eventId});
          }
        }
        if (event != null &&
            event.isPaid == true &&
            event.ticketPrice != null &&
            event.ticketPrice! > 0) {
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
        }
      } catch (e) {
        debugPrint('⚠️ [GDP] Record event ticket GDP error: $e');
      }
    }());

    // Refresh Local Cache
    unawaited(getEvent(eventId, force: true));
  }

  // Leave Event
  Future<void> leaveEvent(String eventId, String userId) async {
    // Optimistically update in-memory cache immediately
    final cached = _eventsByIdCache[eventId];
    if (cached != null && cached.attendees != null) {
      cached.attendees = cached.attendees!.where((id) => id != userId).toList();
      cached.attendeeCount = cached.attendees!.length;
    }

    await FirebaseFunctions.instance.httpsCallable('setEventAttendance').call({
      'eventId': eventId,
      'attending': false,
    });

    // 3. Refresh Local Cache
    unawaited(getEvent(eventId, force: true));
  }

  // Toggle Interest
  Future<void> toggleInterest(String eventId, String userId, bool add) async {
    // Optimistically update in-memory cache immediately
    final cached = _eventsByIdCache[eventId];
    if (cached != null) {
      final current = <String>{...?cached.interested};
      if (add) {
        current.add(userId);
      } else {
        current.remove(userId);
      }
      cached.interested = current.toList();
    }

    await FirebaseFunctions.instance.httpsCallable('setEventInterest').call({
      'eventId': eventId,
      'interested': add,
    });
  }

  // Generate Attendance Code
  Future<String> generateAttendanceCode(String eventId) async {
    final cached = _attendanceCodeCache[eventId];
    if (cached != null) {
      // Refresh in background for next time
      unawaited(() async {
        try {
          final response = await FirebaseFunctions.instance
              .httpsCallable('createEventCheckInChallenge')
              .call({'eventId': eventId});
          final data = Map<String, dynamic>.from(response.data as Map);
          _attendanceCodeCache[eventId] =
              'attendance:$eventId:${data['token']}';
        } catch (_) {}
      }());
      return cached;
    }

    final response = await FirebaseFunctions.instance
        .httpsCallable('createEventCheckInChallenge')
        .call({'eventId': eventId});
    final data = Map<String, dynamic>.from(response.data as Map);
    final code = 'attendance:$eventId:${data['token']}';
    _attendanceCodeCache[eventId] = code;
    return code;
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

      // Optimistically mark checked-in in local cache
      final cached = _eventsByIdCache[eventId];
      if (cached != null) {
        final updatedCheckedIn = <String>{
          ...?cached.confirmedAttendees,
          userId,
        }.toList();
        cached.confirmedAttendees = updatedCheckedIn;
      }

      final token = code.substring('attendance:$eventId:'.length);
      await FirebaseFunctions.instance
          .httpsCallable('completeEventCheckIn')
          .call({'eventId': eventId, 'token': token});

      return VerificationResult.success;
    } catch (e) {
      debugPrint('Error verifying/marking attendance: $e');
      return VerificationResult.error;
    }
  }

  /// Frictionless geofenced check-in: Automatically confirms attendance
  /// when user's location is detected inside the event venue boundary.
  Future<bool> confirmAttendeeGeofenced(
    String eventId,
    String userId, {
    required double lat,
    required double lng,
  }) async {
    debugPrint(
      'Geofenced check-in is disabled until location can be verified server-side.',
    );
    return false;
  }

  // Fetch events created by a specific user
  Stream<List<Event>> getUserEvents(String userId) {
    return Stream.multi((controller) {
      final cached = _eventsByIdCache.values
          .where((e) => e.creatorId == userId)
          .toList();
      if (cached.isNotEmpty) {
        controller.add(_applySyncEnrichment(cached));
      }

      final sub = _firestore
          .collection('events')
          .where('creatorId', isEqualTo: userId)
          .limit(200)
          .snapshots()
          .listen(
            (snapshot) async {
              final events = snapshot.docs
                  .map((doc) {
                    try {
                      final data = doc.data();
                      return Event.fromJson({...data, 'id': doc.id});
                    } catch (_) {
                      return null;
                    }
                  })
                  .whereType<Event>()
                  .toList();

              final immediate = _applySyncEnrichment(events);
              if (!controller.isClosed) {
                controller.add(immediate);
              }

              final enriched = await _enrichEvents(immediate);
              for (final e in enriched) {
                _eventsByIdCache[e.id] = e;
              }
              if (!controller.isClosed) {
                controller.add(enriched);
              }
            },
            onError: controller.addError,
            onDone: controller.close,
          );
      controller.onCancel = sub.cancel;
    });
  }

  // Fetch events where the user is an attendee (Joined Events)
  Stream<List<Event>> getJoinedEvents(String userId) {
    return Stream.multi((controller) {
      final cached = _eventsByIdCache.values
          .where((e) => e.attendees?.contains(userId) ?? false)
          .toList();
      if (cached.isNotEmpty) {
        controller.add(_applySyncEnrichment(cached));
      }

      final sub = _firestore
          .collection('events')
          .where('attendees', arrayContains: userId)
          .limit(200)
          .snapshots()
          .listen(
            (snapshot) async {
              final events = snapshot.docs
                  .map((doc) {
                    try {
                      final data = doc.data();
                      return Event.fromJson({...data, 'id': doc.id});
                    } catch (_) {
                      return null;
                    }
                  })
                  .whereType<Event>()
                  .toList();

              final immediate = _applySyncEnrichment(events);
              if (!controller.isClosed) {
                controller.add(immediate);
              }

              final enriched = await _enrichEvents(immediate);
              for (final e in enriched) {
                _eventsByIdCache[e.id] = e;
              }
              if (!controller.isClosed) {
                controller.add(enriched);
              }
            },
            onError: controller.addError,
            onDone: controller.close,
          );
      controller.onCancel = sub.cancel;
    });
  }

  // Update Event
  Future<void> updateEvent(Event event, XFile? newImage) async {
    if (event.isPaid == true) {
      throw UnsupportedError(
        'Paid events are disabled until verified ticket checkout is configured.',
      );
    }
    try {
      // Optimistically update in-memory cache immediately
      _eventsByIdCache[event.id] = event;

      final data = event.toJson();

      // Parallelize image upload and geocoding
      String? uploadedImageUrl;
      Map<String, double>? coordinates;

      await Future.wait([
        if (newImage != null)
          () async {
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
            uploadedImageUrl = await ref.getDownloadURL();
          }(),
        if (event.location.isNotEmpty &&
            (event.latitude == null || event.longitude == null))
          () async {
            try {
              coordinates = await _geocodeAddress(event.location);
            } catch (_) {}
          }(),
      ]);

      if (uploadedImageUrl != null) {
        data['imageUrl'] = uploadedImageUrl;
        event.imageUrl = uploadedImageUrl!;
      }
      if (coordinates != null) {
        data['latitude'] = coordinates!['lat'];
        data['longitude'] = coordinates!['lng'];
      }

      // Ensure paid fields are explicitly set (not reliant on toJson nullability)
      data['isPaid'] = event.isPaid ?? false;
      if (event.isPaid == true && event.ticketPrice != null) {
        data['ticketPrice'] = event.ticketPrice;
      } else {
        data['ticketPrice'] = cf.FieldValue.delete();
      }

      _eventsByIdCache[event.id] = event;
      await _firestore.collection('events').doc(event.id).update(data);

      // Update Chat Name in Firestore if title changed (non-blocking)
      if (event.chatId != null) {
        unawaited(
          FirebaseFunctions.instance
              .httpsCallable('updateChatMetadata')
              .call<void>({
                'chatId': event.chatId,
                'name': event.title,
                if (data['imageUrl'] is String) 'photoUrl': data['imageUrl'],
              })
              .then<void>((_) {})
              .catchError((_) {}),
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  // Delete Event
  Future<void> deleteEvent(String eventId) async {
    final previous = _eventsByIdCache.remove(eventId);
    try {
      // Related chat indexes and event media are removed by the backend
      // delete trigger after this canonical document is deleted.
      await _firestore.collection('events').doc(eventId).delete();
    } catch (e) {
      if (previous != null) {
        _eventsByIdCache[eventId] = previous;
      }
      rethrow;
    }
  }

  /// Synchronously filter cached events for 0ms instant search results
  List<Event> searchCachedEvents(String query) {
    final queryLower = query.toLowerCase();
    final today = DateTime.now();
    final results =
        _eventsByIdCache.values.where((event) {
          if (isEventExpired(event, today)) return false;
          if (event.status != 'published') return false;
          if (query.isEmpty) return true;
          return event.title.toLowerCase().contains(queryLower);
        }).toList()..sort((a, b) {
          final dateCmp = a.startDate.compareTo(b.startDate);
          if (dateCmp != 0) return dateCmp;
          return a.startTime.compareTo(b.startTime);
        });
    return results;
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
          .limit(200)
          .get();

      final events =
          snapshot.docs
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
                if (isEventExpired(event, today)) return false;
                if (event.status != 'published') return false;
                if (query.isEmpty) return true;
                return event.title.toLowerCase().contains(queryLower);
              })
              .toList()
            ..sort((a, b) {
              final dateCmp = a.startDate.compareTo(b.startDate);
              if (dateCmp != 0) return dateCmp;
              return a.startTime.compareTo(b.startTime);
            });

      final enriched = await _enrichEvents(events);
      for (final e in enriched) {
        _eventsByIdCache[e.id] = e;
      }
      return enriched;
    } catch (e) {
      return searchCachedEvents(query);
    }
  }
}
