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

  CollectionReference get _requestsCol =>
      _firestore.collection('hosting_requests');

  CollectionReference get _sessionsCol =>
      _firestore.collection('hosting_sessions');

  // =========================================================================
  // HOSTING REQUESTS
  // =========================================================================

  /// Create a new hosting request from a traveler.
  Future<HostingRequest> createRequest(HostingRequest request) async {
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
    final created = await getRequest(request.id);
    if (created == null) {
      throw StateError('The hosting request could not be loaded.');
    }
    debugPrint('✅ [Hosting] Request created: ${request.id}');
    return created;
  }

  /// Get a single hosting request by ID.
  Future<HostingRequest?> getRequest(String requestId) async {
    try {
      final doc = await _requestsCol.doc(requestId).get();
      if (!doc.exists) return null;
      return HostingRequest.fromMap({
        ...doc.data() as Map<String, dynamic>,
        'id': doc.id,
      });
    } catch (e) {
      debugPrint('❌ [Hosting] Error getting request: $e');
      return null;
    }
  }

  /// Watch open hosting requests for a community (for the community chat broadcast).
  Stream<List<HostingRequest>> watchCommunityRequests(String communityId) {
    return _requestsCol
        .where('communityId', isEqualTo: communityId)
        .where('status', whereIn: ['pending', 'matched'])
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (doc) => HostingRequest.fromMap({
                  ...doc.data() as Map<String, dynamic>,
                  'id': doc.id,
                }),
              )
              .toList(),
        );
  }

  /// Watch all requests created by a specific traveler.
  Stream<List<HostingRequest>> watchTravelerRequests(String travelerId) {
    return _requestsCol
        .where('travelerId', isEqualTo: travelerId)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (doc) => HostingRequest.fromMap({
                  ...doc.data() as Map<String, dynamic>,
                  'id': doc.id,
                }),
              )
              .toList(),
        );
  }

  /// Host shows interest in a hosting request.
  Future<void> showInterest(String requestId, String hostId) async {
    final doc = await _requestsCol.doc(requestId).get();
    if (!doc.exists) {
      debugPrint('[Hosting] Request $requestId not found — may have expired.');
      throw Exception(
        'This hosting request no longer exists. It may have expired.',
      );
    }
    await _requestsCol.doc(requestId).update({
      'interestedHostIds': FieldValue.arrayUnion([hostId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    debugPrint('✅ [Hosting] Host $hostId showed interest in $requestId');
  }

  /// Host withdraws interest.
  Future<void> withdrawInterest(String requestId, String hostId) async {
    final doc = await _requestsCol.doc(requestId).get();
    if (!doc.exists) {
      debugPrint('[Hosting] Request $requestId not found — may have expired.');
      return;
    }
    await _requestsCol.doc(requestId).update({
      'interestedHostIds': FieldValue.arrayRemove([hostId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    debugPrint('[Hosting] Host $hostId withdrew interest from $requestId');
  }

  /// Cancel a hosting request (traveler only, before check-in).
  Future<void> cancelRequest(String requestId) async {
    await _requestsCol.doc(requestId).update({
      'status': HostingRequestStatus.cancelled.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    debugPrint('✅ [Hosting] Request $requestId cancelled');
  }

  // =========================================================================
  // HOSTING SESSIONS
  // =========================================================================

  /// Create a hosting session after both parties agree.
  Future<HostingSession> createSession({
    required String requestId,
    required String hostId,
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
    final session = await getSession(sessionId);
    if (session == null) {
      throw StateError('The hosting session could not be loaded.');
    }
    return session;
  }

  /// Get a single session by ID.
  Future<HostingSession?> getSession(String sessionId) async {
    try {
      final doc = await _sessionsCol.doc(sessionId).get();
      if (!doc.exists) return null;
      return HostingSession.fromMap({
        ...doc.data() as Map<String, dynamic>,
        'id': doc.id,
      });
    } catch (e) {
      debugPrint('❌ [Hosting] Error getting session: $e');
      return null;
    }
  }

  /// Watch active hosting session for a user (as traveler or host).
  /// Only 1 active session at a time per user.
  Stream<HostingSession?> watchActiveSession(String userId) {
    // We listen to both streams and combine their latest values.
    // A null from one stream must NOT overwrite a valid result from the other.
    final controller = StreamController<HostingSession?>.broadcast();

    HostingSession? latestTraveler;
    HostingSession? latestHost;
    bool travelerReady = false;
    bool hostReady = false;

    void emit() {
      // Only emit once both streams have fired at least once
      if (!travelerReady || !hostReady) return;
      // Prefer traveler session if it exists, otherwise host session
      controller.add(latestTraveler ?? latestHost);
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
        });

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
        });

    controller.onCancel = () {
      travelerSub.cancel();
      hostSub.cancel();
      controller.close();
    };

    return controller.stream;
  }

  /// Watch all sessions for a user (history).
  Stream<List<HostingSession>> watchUserSessions(String userId) {
    return _sessionsCol
        .where('travelerId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (doc) => HostingSession.fromMap({
                  ...doc.data() as Map<String, dynamic>,
                  'id': doc.id,
                }),
              )
              .toList(),
        );
  }

  /// QR Check-in — activates the session.
  Future<String> createCheckInChallenge(String sessionId) async {
    final callable = _functions.httpsCallable('createHostingCheckInChallenge');
    final result = await callable.call<Map<String, dynamic>>({
      'sessionId': sessionId,
    });
    final token = result.data['token'] as String?;
    if (token == null || token.isEmpty) {
      throw StateError('The server did not return a check-in challenge.');
    }
    return token;
  }

  /// QR Check-in — consumes a one-time host-issued challenge.
  Future<void> checkIn(String sessionId, String token) async {
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
    await _updateSessionState(sessionId, 'request_end');
  }

  /// The other party confirms the end and the server settles the stay.
  Future<void> confirmEnd(String sessionId) async {
    await _updateSessionState(sessionId, 'confirm_end');
  }

  /// Cancel a session before check-in only.
  Future<void> cancelSession(String sessionId) async {
    await _updateSessionState(sessionId, 'cancel');
  }

  // =========================================================================
  // HELPERS
  // =========================================================================

  /// Generate a unique ID for a hosting request or session.
  String generateId() => _firestore.collection('_').doc().id;
}
