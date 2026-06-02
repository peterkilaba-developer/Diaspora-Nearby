import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  CollectionReference get _requestsCol =>
      _firestore.collection('hosting_requests');

  CollectionReference get _sessionsCol =>
      _firestore.collection('hosting_sessions');

  // =========================================================================
  // HOSTING REQUESTS
  // =========================================================================

  /// Create a new hosting request from a traveler.
  Future<HostingRequest> createRequest(HostingRequest request) async {
    final docRef = _requestsCol.doc(request.id);
    await docRef.set(request.toMap());
    debugPrint('Ã¢Å“â€¦ [Hosting] Request created: ${request.id}');
    return request;
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
      debugPrint('Ã¢ÂÅ’ [Hosting] Error getting request: $e');
      return null;
    }
  }

  /// Watch open hosting requests for a community (for the community chat broadcast).
  Stream<List<HostingRequest>> watchCommunityRequests(String communityId) {
    return _requestsCol
        .where('communityId', isEqualTo: communityId)
        .where('status', whereIn: ['pending', 'matched'])
        .orderBy('createdAt', descending: true)
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
      debugPrint(
        '[Hosting] Request $requestId not found Ã¢â‚¬â€ may have expired.',
      );
      throw Exception(
        'This hosting request no longer exists. It may have expired.',
      );
    }
    await _requestsCol.doc(requestId).update({
      'interestedHostIds': FieldValue.arrayUnion([hostId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    debugPrint('Ã¢Å“â€¦ [Hosting] Host $hostId showed interest in $requestId');
  }

  /// Host withdraws interest.
  Future<void> withdrawInterest(String requestId, String hostId) async {
    final doc = await _requestsCol.doc(requestId).get();
    if (!doc.exists) {
      debugPrint(
        '[Hosting] Request $requestId not found Ã¢â‚¬â€ may have expired.',
      );
      return;
    }
    await _requestsCol.doc(requestId).update({
      'interestedHostIds': FieldValue.arrayRemove([hostId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    debugPrint('[Hosting] Host $hostId withdrew interest from $requestId');
  }

  /// Traveler selects a host Ã¢â‚¬â€ updates request to 'matched' status.
  Future<void> selectHost({
    required String requestId,
    required String hostId,
    required String hostName,
  }) async {
    final doc = await _requestsCol.doc(requestId).get();
    if (!doc.exists) {
      debugPrint(
        '[Hosting] Request $requestId not found Ã¢â‚¬â€ may have expired.',
      );
      throw Exception(
        'This hosting request no longer exists. It may have expired.',
      );
    }
    await _requestsCol.doc(requestId).update({
      'matchedHostId': hostId,
      'matchedHostName': hostName,
      'status': HostingRequestStatus.matched.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    debugPrint(
      '[Hosting] Traveler selected host $hostName for request $requestId',
    );
  }

  /// Cancel a hosting request (traveler only, before check-in).
  Future<void> cancelRequest(String requestId) async {
    await _requestsCol.doc(requestId).update({
      'status': HostingRequestStatus.cancelled.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    debugPrint('Ã¢Å“â€¦ [Hosting] Request $requestId cancelled');
  }

  // =========================================================================
  // HOSTING SESSIONS
  // =========================================================================

  /// Create a hosting session after both parties agree.
  Future<HostingSession> createSession(HostingSession session) async {
    debugPrint(
      'Ã°Å¸â€œÂ [createSession] Writing session ${session.id} to Firestore...',
    );
    final batch = _firestore.batch();
    batch.set(_sessionsCol.doc(session.id), session.toMap());
    batch.update(_requestsCol.doc(session.requestId), {
      'status': HostingRequestStatus.active.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    debugPrint(
      'Ã°Å¸â€œÂ [createSession] Ã¢Å“â€¦ Session + request committed atomically',
    );
    debugPrint('Ã¢Å“â€¦ [Hosting] Session created: ${session.id}');
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
      debugPrint('Ã¢ÂÅ’ [Hosting] Error getting session: $e');
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

  /// QR Check-in Ã¢â‚¬â€ activates the session.
  Future<void> checkIn(String sessionId) async {
    await _sessionsCol.doc(sessionId).update({
      'checkInTime': FieldValue.serverTimestamp(),
      'status': HostingSessionStatus.active.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    debugPrint('Ã¢Å“â€¦ [Hosting] Session $sessionId checked in');
  }

  /// One party requests to end the session.
  Future<void> requestEnd({
    required String sessionId,
    required String requestedByUserId,
  }) async {
    await _sessionsCol.doc(sessionId).update({
      'endRequestedBy': requestedByUserId,
      'endRequestedAt': FieldValue.serverTimestamp(),
      'status': HostingSessionStatus.endRequested.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    debugPrint(
      'Ã¢Å“â€¦ [Hosting] End requested for session $sessionId by $requestedByUserId',
    );
  }

  /// Both parties confirmed end Ã¢â‚¬â€ calculates final duration and marks as ended.
  Future<void> confirmEnd(String sessionId) async {
    final session = await getSession(sessionId);
    if (session == null) return;

    final checkIn = session.checkInTime ?? session.createdAt;
    final checkOut = DateTime.now();
    final days = checkOut.difference(checkIn).inDays;
    final actualDays = days < 1 ? 1 : days;

    await _sessionsCol.doc(sessionId).update({
      'checkOutTime': Timestamp.fromDate(checkOut),
      'actualDays': actualDays,
      'status': HostingSessionStatus.ended.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    debugPrint('Ã¢Å“â€¦ [Hosting] Session $sessionId ended: $actualDays days');
  }

  /// Mark session as settled (both parties confirmed completion).
  Future<void> markSettled(String sessionId) async {
    // Read the session once up front so we can batch both writes atomically.
    final session = await getSession(sessionId);
    if (session == null) {
      debugPrint('[Hosting] markSettled: session $sessionId not found');
      return;
    }

    final batch = _firestore.batch();
    batch.update(_sessionsCol.doc(sessionId), {
      'travelerSettled': true,
      'hostSettled': true,
      'status': HostingSessionStatus.settled.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(_requestsCol.doc(session.requestId), {
      'status': HostingRequestStatus.completed.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();

    debugPrint('[Hosting] Session $sessionId settled');
  }

  /// Cancel a session (before check-in only).
  Future<void> cancelSession(String sessionId) async {
    final session = await getSession(sessionId);
    if (session == null) return;

    // Only allow cancellation if not yet active
    if (session.status == HostingSessionStatus.confirmed) {
      await _sessionsCol.doc(sessionId).update({
        'status': HostingSessionStatus.cancelled.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Revert request to pending so traveler can find another host
      await _requestsCol.doc(session.requestId).update({
        'matchedHostId': null,
        'matchedHostName': null,
        'status': HostingRequestStatus.pending.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      debugPrint('Ã¢Å“â€¦ [Hosting] Session $sessionId cancelled');
    }
  }

  // =========================================================================
  // HELPERS
  // =========================================================================

  /// Generate a unique ID for a hosting request or session.
  String generateId() => _firestore.collection('_').doc().id;
}
