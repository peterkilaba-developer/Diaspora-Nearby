import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:diaspora_nearby/features/hosting/models/hosting_request.dart';
import 'package:diaspora_nearby/features/hosting/models/hosting_session.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final hostingRepositoryProvider = Provider((ref) => HostingRepository());

/// Stream of open hosting requests for a specific community.
final communityHostingRequestsProvider =
    StreamProvider.family<List<HostingRequest>, String>((ref, communityId) {
      return ref
          .watch(hostingRepositoryProvider)
          .watchCommunityRequests(communityId);
    });

/// Stream of all hosting requests created by a specific traveler.
final travelerRequestsProvider =
    StreamProvider.family<List<HostingRequest>, String>((ref, travelerId) {
      return ref
          .watch(hostingRepositoryProvider)
          .watchTravelerRequests(travelerId);
    });

/// Stream of active hosting session for a user (as host or traveler).
final activeHostingSessionProvider =
    StreamProvider.family<HostingSession?, String>((ref, userId) {
      return ref.watch(hostingRepositoryProvider).watchActiveSession(userId);
    });

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

class HostingRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // [PERF] Static in-memory caches for 0-latency reads & optimistic updates
  static final Map<String, HostingRequest> _requestByIdCache = {};
  static final Map<String, List<HostingRequest>> _requestsCache = {};
  static final Map<String, List<HostingRequest>> _userRequestsCache = {};
  static final Map<String, HostingSession> _sessionByIdCache = {};
  static final Map<String, HostingSession?> _activeSessionCache = {};
  static final Map<String, List<HostingSession>> _offersCache = {};
  static final Map<String, String> _checkInChallengeCache = {};

  /// Synchronously get a cached request by ID
  HostingRequest? getCachedRequest(String requestId) =>
      _requestByIdCache[requestId];

  /// Synchronously get cached open requests for a community
  List<HostingRequest> getCachedRequests(String communityId) {
    final cached = _requestsCache[communityId];
    if (cached != null) return cached;
    return _requestByIdCache.values
        .where(
          (r) =>
              r.communityId == communityId &&
              (r.status == HostingRequestStatus.pending ||
                  r.status == HostingRequestStatus.matched),
        )
        .toList();
  }

  /// Synchronously get cached requests for a traveler
  List<HostingRequest> getCachedUserRequests(String travelerId) {
    final cached = _userRequestsCache[travelerId];
    if (cached != null) return cached;
    return _requestByIdCache.values
        .where((r) => r.travelerId == travelerId)
        .toList();
  }

  /// Synchronously get cached sessions/offers for a user
  List<HostingSession> getCachedOffers(String userId) =>
      _offersCache[userId] ?? const [];

  /// Synchronously get a cached session by ID
  HostingSession? getCachedSession(String sessionId) =>
      _sessionByIdCache[sessionId];

  /// Synchronously get cached active session for a user
  HostingSession? getCachedActiveSession(String userId) =>
      _activeSessionCache[userId];

  /// Synchronously get pre-warmed check-in challenge token
  String? getCachedCheckInChallenge(String sessionId) =>
      _checkInChallengeCache[sessionId];

  /// Synchronously cache/update a hosting request
  void cacheRequest(HostingRequest request) {
    _requestByIdCache[request.id] = request;
    final commList = List<HostingRequest>.from(
      _requestsCache[request.communityId] ?? const [],
    );
    final idx = commList.indexWhere((r) => r.id == request.id);
    if (request.status == HostingRequestStatus.pending ||
        request.status == HostingRequestStatus.matched) {
      if (idx >= 0) {
        commList[idx] = request;
      } else {
        commList.insert(0, request);
      }
    } else if (idx >= 0) {
      commList.removeAt(idx);
    }
    _requestsCache[request.communityId] = commList;

    final userList = List<HostingRequest>.from(
      _userRequestsCache[request.travelerId] ?? const [],
    );
    final uIdx = userList.indexWhere((r) => r.id == request.id);
    if (uIdx >= 0) {
      userList[uIdx] = request;
    } else {
      userList.insert(0, request);
    }
    _userRequestsCache[request.travelerId] = userList;
  }

  /// Synchronously cache/update a hosting session
  void cacheSession(HostingSession session) {
    _sessionByIdCache[session.id] = session;
    final isActiveStatus =
        session.status == HostingSessionStatus.confirmed ||
        session.status == HostingSessionStatus.active ||
        session.status == HostingSessionStatus.endRequested;
    if (isActiveStatus) {
      _activeSessionCache[session.travelerId] = session;
      _activeSessionCache[session.hostId] = session;
    } else {
      if (_activeSessionCache[session.travelerId]?.id == session.id) {
        _activeSessionCache.remove(session.travelerId);
      }
      if (_activeSessionCache[session.hostId]?.id == session.id) {
        _activeSessionCache.remove(session.hostId);
      }
    }
  }

  CollectionReference get _requestsCol =>
      _firestore.collection('hosting_requests');

  CollectionReference get _sessionsCol =>
      _firestore.collection('hosting_sessions');

  // =========================================================================
  // HOSTING REQUESTS
  // =========================================================================

  /// Create a new hosting request from a traveler.
  Future<HostingRequest> createRequest(HostingRequest request) async {
    // Optimistically store in cache on frame 0
    cacheRequest(request);

    await _functions.httpsCallable('createHostingRequest').call<void>({
      'requestId': request.id,
      'communityId': request.communityId,
      'arrivalMillis': request.arrivalDate.millisecondsSinceEpoch,
      'departureMillis': request.departureDate.millisecondsSinceEpoch,
      'purpose': request.purpose,
      'notes': request.notes,
      'guestCount': request.guestCount ?? 1,
      'preferredArea': request.preferredArea,
      'languages': request.languages ?? const <String>[],
    });
    debugPrint('✅ [Hosting] Request created: ${request.id}');
    return request;
  }

  /// Get a single hosting request by ID.
  Future<HostingRequest?> getRequest(
    String requestId, {
    bool force = false,
  }) async {
    if (!force && _requestByIdCache.containsKey(requestId)) {
      // Refresh in background
      unawaited(_fetchRequestFromNetwork(requestId));
      return _requestByIdCache[requestId];
    }
    return await _fetchRequestFromNetwork(requestId);
  }

  Future<HostingRequest?> _fetchRequestFromNetwork(String requestId) async {
    try {
      final doc = await _requestsCol.doc(requestId).get();
      if (!doc.exists) return null;
      final req = HostingRequest.fromMap({
        ...doc.data() as Map<String, dynamic>,
        'id': doc.id,
      });
      cacheRequest(req);
      return req;
    } catch (e) {
      debugPrint('❌ [Hosting] Error getting request: $e');
      return _requestByIdCache[requestId];
    }
  }

  /// Watch open hosting requests for a community (for the community chat broadcast).
  Stream<List<HostingRequest>> watchCommunityRequests(String communityId) {
    return Stream.multi((controller) {
      final cached = getCachedRequests(communityId);
      if (cached.isNotEmpty) {
        controller.add(cached);
      }

      final sub = _requestsCol
          .where('communityId', isEqualTo: communityId)
          .where('status', whereIn: ['pending', 'matched'])
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots()
          .listen(
            (snapshot) {
              final list = snapshot.docs
                  .map(
                    (doc) => HostingRequest.fromMap({
                      ...doc.data() as Map<String, dynamic>,
                      'id': doc.id,
                    }),
                  )
                  .toList();
              for (final r in list) {
                _requestByIdCache[r.id] = r;
              }
              _requestsCache[communityId] = list;
              if (!controller.isClosed) {
                controller.add(list);
              }
            },
            onError: controller.addError,
            onDone: controller.close,
          );
      controller.onCancel = sub.cancel;
    });
  }

  /// Watch all requests created by a specific traveler.
  Stream<List<HostingRequest>> watchTravelerRequests(String travelerId) {
    return Stream.multi((controller) {
      final cached = getCachedUserRequests(travelerId);
      if (cached.isNotEmpty) {
        controller.add(cached);
      }

      final sub = _requestsCol
          .where('travelerId', isEqualTo: travelerId)
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots()
          .listen(
            (snapshot) {
              final list = snapshot.docs
                  .map(
                    (doc) => HostingRequest.fromMap({
                      ...doc.data() as Map<String, dynamic>,
                      'id': doc.id,
                    }),
                  )
                  .toList();
              for (final r in list) {
                _requestByIdCache[r.id] = r;
              }
              _userRequestsCache[travelerId] = list;
              if (!controller.isClosed) {
                controller.add(list);
              }
            },
            onError: controller.addError,
            onDone: controller.close,
          );
      controller.onCancel = sub.cancel;
    });
  }

  /// Host shows interest in a hosting request.
  Future<void> showInterest(String requestId, String hostId) async {
    final cached = _requestByIdCache[requestId];
    if (cached != null) {
      final updatedHosts = <String>{
        ...cached.interestedHostIds,
        hostId,
      }.toList();
      cacheRequest(cached.copyWith(interestedHostIds: updatedHosts));
    }

    try {
      await _functions.httpsCallable('updateHostingRequestState').call({
        'requestId': requestId,
        'operation': 'show_interest',
      });
      debugPrint('✅ [Hosting] Host $hostId showed interest in $requestId');
    } catch (e) {
      if (cached != null) cacheRequest(cached);
      rethrow;
    }
  }

  /// Host withdraws interest.
  Future<void> withdrawInterest(String requestId, String hostId) async {
    final cached = _requestByIdCache[requestId];
    if (cached != null) {
      final updatedHosts = cached.interestedHostIds
          .where((id) => id != hostId)
          .toList();
      cacheRequest(cached.copyWith(interestedHostIds: updatedHosts));
    }

    try {
      await _functions.httpsCallable('updateHostingRequestState').call({
        'requestId': requestId,
        'operation': 'withdraw_interest',
      });
      debugPrint('[Hosting] Host $hostId withdrew interest from $requestId');
    } catch (e) {
      if (cached != null) cacheRequest(cached);
      rethrow;
    }
  }

  /// Cancel a hosting request (traveler only, before check-in).
  Future<void> cancelRequest(String requestId) async {
    final cached = _requestByIdCache[requestId];
    if (cached != null) {
      cacheRequest(cached.copyWith(status: HostingRequestStatus.cancelled));
    }

    try {
      await _functions.httpsCallable('updateHostingRequestState').call({
        'requestId': requestId,
        'operation': 'cancel',
      });
      debugPrint('✅ [Hosting] Request $requestId cancelled');
    } catch (e) {
      if (cached != null) cacheRequest(cached);
      rethrow;
    }
  }

  // =========================================================================
  // HOSTING SESSIONS
  // =========================================================================

  /// Create a hosting session after both parties agree.
  Future<HostingSession> createSession({
    required String requestId,
    required String hostId,
    String? hostName,
    String? hostPhoto,
    String? chatId,
  }) async {
    final callable = _functions.httpsCallable('createHostingSession');
    final result = await callable.call<Map<String, dynamic>>({
      'requestId': requestId,
      'hostId': hostId,
      if (chatId != null && chatId.isNotEmpty) 'chatId': chatId,
    });
    final sessionId = result.data['sessionId'] as String?;
    if (sessionId == null || sessionId.isEmpty) {
      throw StateError('The server did not return a hosting session.');
    }

    final req = _requestByIdCache[requestId];
    if (req != null) {
      final updatedReq = req.copyWith(
        status: HostingRequestStatus.matched,
        matchedHostId: hostId,
        matchedHostName: hostName ?? req.matchedHostName,
      );
      cacheRequest(updatedReq);

      final localSession = HostingSession(
        id: sessionId,
        requestId: requestId,
        travelerId: req.travelerId,
        travelerName: req.travelerName,
        travelerPhoto: req.travelerPhoto,
        hostId: hostId,
        hostName: hostName ?? req.matchedHostName ?? 'Host',
        hostPhoto: hostPhoto,
        communityId: req.communityId,
        communityName: req.communityName,
        plannedArrival: req.arrivalDate,
        plannedDeparture: req.departureDate,
        status: HostingSessionStatus.confirmed,
        createdAt: DateTime.now(),
        chatId: chatId,
      );
      cacheSession(localSession);
      return localSession;
    }

    final session = await getSession(sessionId, force: true);
    if (session == null) {
      throw StateError('The hosting session could not be loaded.');
    }
    return session;
  }

  /// Get a single session by ID.
  Future<HostingSession?> getSession(
    String sessionId, {
    bool force = false,
  }) async {
    if (!force && _sessionByIdCache.containsKey(sessionId)) {
      unawaited(_fetchSessionFromNetwork(sessionId));
      return _sessionByIdCache[sessionId];
    }
    return await _fetchSessionFromNetwork(sessionId);
  }

  Future<HostingSession?> _fetchSessionFromNetwork(String sessionId) async {
    try {
      final doc = await _sessionsCol.doc(sessionId).get();
      if (!doc.exists) return null;
      final session = HostingSession.fromMap({
        ...doc.data() as Map<String, dynamic>,
        'id': doc.id,
      });
      cacheSession(session);
      return session;
    } catch (e) {
      debugPrint('❌ [Hosting] Error getting session: $e');
      return _sessionByIdCache[sessionId];
    }
  }

  /// Pre-warm check-in challenge token in background so QR code opens in 0ms
  Future<void> prewarmCheckInChallenge(String sessionId) async {
    if (_checkInChallengeCache.containsKey(sessionId)) return;
    try {
      await createCheckInChallenge(sessionId);
    } catch (_) {}
  }

  /// Watch active hosting session for a user (as traveler or host).
  /// Only 1 active session at a time per user.
  Stream<HostingSession?> watchActiveSession(String userId) {
    return Stream.multi((controller) {
      if (_activeSessionCache.containsKey(userId)) {
        controller.add(_activeSessionCache[userId]);
      }

      HostingSession? latestTraveler;
      HostingSession? latestHost;
      bool travelerReady = false;
      bool hostReady = false;

      void emit() {
        final active = latestTraveler ?? latestHost;
        // Emit immediately if either stream found an active session, or once both streams have reported
        if (active == null && (!travelerReady || !hostReady)) return;
        _activeSessionCache[userId] = active;
        if (active != null) {
          _sessionByIdCache[active.id] = active;
          if (active.hostId == userId &&
              active.status == HostingSessionStatus.confirmed) {
            unawaited(prewarmCheckInChallenge(active.id));
          }
        }
        if (!controller.isClosed) {
          controller.add(active);
        }
      }

      final travelerSub = _sessionsCol
          .where('travelerId', isEqualTo: userId)
          .where('status', whereIn: ['confirmed', 'active', 'endRequested'])
          .limit(1)
          .snapshots()
          .listen((snap) {
            latestTraveler = snap.docs.isEmpty
                ? null
                : HostingSession.fromMap({
                    ...snap.docs.first.data() as Map<String, dynamic>,
                    'id': snap.docs.first.id,
                  });
            travelerReady = true;
            emit();
          }, onError: controller.addError);

      final hostSub = _sessionsCol
          .where('hostId', isEqualTo: userId)
          .where('status', whereIn: ['confirmed', 'active', 'endRequested'])
          .limit(1)
          .snapshots()
          .listen((snap) {
            latestHost = snap.docs.isEmpty
                ? null
                : HostingSession.fromMap({
                    ...snap.docs.first.data() as Map<String, dynamic>,
                    'id': snap.docs.first.id,
                  });
            hostReady = true;
            emit();
          }, onError: controller.addError);

      controller.onCancel = () {
        travelerSub.cancel();
        hostSub.cancel();
      };
    });
  }

  /// Watch all sessions for a user (history).
  Stream<List<HostingSession>> watchUserSessions(String userId) {
    return Stream.multi((controller) {
      final cached = _offersCache[userId];
      if (cached != null && cached.isNotEmpty) {
        controller.add(cached);
      }

      final sub = _sessionsCol
          .where('travelerId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots()
          .listen(
            (snapshot) {
              final list = snapshot.docs
                  .map(
                    (doc) => HostingSession.fromMap({
                      ...doc.data() as Map<String, dynamic>,
                      'id': doc.id,
                    }),
                  )
                  .toList();
              for (final s in list) {
                _sessionByIdCache[s.id] = s;
              }
              _offersCache[userId] = list;
              if (!controller.isClosed) {
                controller.add(list);
              }
            },
            onError: controller.addError,
            onDone: controller.close,
          );
      controller.onCancel = sub.cancel;
    });
  }

  /// QR Check-in — activates the session.
  Future<String> createCheckInChallenge(String sessionId) async {
    final cached = _checkInChallengeCache[sessionId];
    if (cached != null) {
      unawaited(() async {
        try {
          final callable = _functions.httpsCallable(
            'createHostingCheckInChallenge',
          );
          final result = await callable.call<Map<String, dynamic>>({
            'sessionId': sessionId,
          });
          final token = result.data['token'] as String?;
          if (token != null && token.isNotEmpty) {
            _checkInChallengeCache[sessionId] = token;
          }
        } catch (_) {}
      }());
      return cached;
    }

    final callable = _functions.httpsCallable('createHostingCheckInChallenge');
    final result = await callable.call<Map<String, dynamic>>({
      'sessionId': sessionId,
    });
    final token = result.data['token'] as String?;
    if (token == null || token.isEmpty) {
      throw StateError('The server did not return a check-in challenge.');
    }
    _checkInChallengeCache[sessionId] = token;
    return token;
  }

  /// QR Check-in — consumes a one-time host-issued challenge.
  Future<void> checkIn(String sessionId, String token) async {
    final cached = _sessionByIdCache[sessionId];
    if (cached != null) {
      cacheSession(
        cached.copyWith(
          status: HostingSessionStatus.active,
          checkInTime: DateTime.now(),
        ),
      );
    }
    await _functions.httpsCallable('completeHostingCheckIn').call<void>({
      'sessionId': sessionId,
      'token': token,
    });
  }

  Future<void> _updateSessionState(String sessionId, String operation) async {
    await _functions.httpsCallable('updateHostingSessionState').call<void>({
      'sessionId': sessionId,
      'operation': operation,
    });
  }

  /// One party requests to end the session.
  Future<void> requestEnd(String sessionId) async {
    final cached = _sessionByIdCache[sessionId];
    if (cached != null) {
      cacheSession(cached.copyWith(status: HostingSessionStatus.endRequested));
    }
    await _updateSessionState(sessionId, 'request_end');
  }

  /// The other party confirms the end and the server settles the stay.
  Future<void> confirmEnd(String sessionId) async {
    final cached = _sessionByIdCache[sessionId];
    if (cached != null) {
      cacheSession(cached.copyWith(status: HostingSessionStatus.settled));
    }
    await _updateSessionState(sessionId, 'confirm_end');
  }

  /// Cancel a session before check-in only.
  Future<void> cancelSession(String sessionId) async {
    final cached = _sessionByIdCache[sessionId];
    if (cached != null) {
      cacheSession(cached.copyWith(status: HostingSessionStatus.cancelled));
    }
    await _updateSessionState(sessionId, 'cancel');
  }

  // =========================================================================
  // HELPERS
  // =========================================================================

  /// Generate a unique ID for a hosting request or session.
  String generateId() => _firestore.collection('_').doc().id;
}
