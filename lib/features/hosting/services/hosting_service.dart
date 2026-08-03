import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';

import 'package:diaspora_nearby/features/hosting/models/hosting_request.dart';
import 'package:diaspora_nearby/features/hosting/models/hosting_session.dart';
import 'package:diaspora_nearby/features/hosting/repository/hosting_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final hostingServiceProvider = Provider((ref) => HostingService(ref));

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Orchestrates the entire hosting flow:
/// 1. Traveler creates a request → broadcasts to community chat
/// 2. Hosts show interest → traveler selects a host
/// 3. Both agree → session created
/// 4. QR check-in → session active
/// 5. Both confirm end → session settled
class HostingService {
  final Ref _ref;

  HostingService(this._ref);

  HostingRepository get _hostingRepo => _ref.read(hostingRepositoryProvider);

  ChatRepository get _chatRepo => _ref.read(chatRepositoryProvider);

  // =========================================================================
  // PHASE 2: Request Flow
  // =========================================================================

  /// Traveler creates a hosting request and broadcasts it to the community chat.
  ///
  /// Returns the created [HostingRequest] or null if an error occurs.
  Future<HostingRequest?> createHostingRequest({
    required String communityId,
    required String communityName,
    required String? communityChatId,
    required DateTime arrivalDate,
    required DateTime departureDate,
    String? purpose,
    String? notes,
    int guestCount = 1,
    String? preferredArea,
    List<String>? languages,
  }) async {
    try {
      // Get current user info
      final user = _ref.read(authRepositoryProvider).currentUser;
      if (user == null) {
        debugPrint('❌ [Hosting] No authenticated user');
        return null;
      }

      final profile = _ref.read(userProfileProvider).value;
      if (profile == null) {
        debugPrint('❌ [Hosting] No user profile loaded');
        return null;
      }

      // Create the hosting request
      final requestId = _hostingRepo.generateId();
      final request = HostingRequest(
        id: requestId,
        travelerId: user.uid,
        travelerName: profile.fullName,
        travelerPhoto: profile.profileImage,
        travelerFlag: profile.homeCountryCode,
        communityId: communityId,
        communityName: communityName,
        arrivalDate: arrivalDate,
        departureDate: departureDate,
        purpose: purpose,
        notes: notes,
        guestCount: guestCount,
        preferredArea: preferredArea,
        languages: languages,
        createdAt: DateTime.now(),
      );

      // Save to Firestore
      await _hostingRepo.createRequest(request);

      // Broadcast to community chat (if chat exists)
      if (communityChatId != null && communityChatId.isNotEmpty) {
        await _broadcastToCommunityChatMessage(request, communityChatId);
      }

      debugPrint('✅ [Hosting] Request created and broadcast: $requestId');
      return request;
    } catch (e) {
      debugPrint('❌ [Hosting] Error creating request: $e');
      return null;
    }
  }

  /// Broadcasts a hosting request as a system message to the community chat.
  Future<void> _broadcastToCommunityChatMessage(
    HostingRequest request,
    String chatId,
  ) async {
    try {
      final arrivalStr =
          '${request.arrivalDate.month}/${request.arrivalDate.day}/${request.arrivalDate.year}';
      final departureStr =
          '${request.departureDate.month}/${request.departureDate.day}/${request.departureDate.year}';

      final content =
          '🧳 ${request.travelerName} is visiting ${request.communityName} '
          'from $arrivalStr to $departureStr and is looking for a host. '
          '${request.purpose != null ? "Purpose: ${request.purpose}. " : ""}'
          'Tap to view their profile and show interest.';

      await _chatRepo.sendTextMessage(
        chatId,
        content,
        type: 'system',
        senderIdOverride: 'system',
        senderNameOverride: 'Hosting Request',
        metadata: {
          'systemType': 'hosting_request',
          'hostingRequestId': request.id,
          'travelerId': request.travelerId,
          'travelerName': request.travelerName,
          'travelerPhoto': request.travelerPhoto,
          'travelerFlag': request.travelerFlag,
          'communityId': request.communityId,
          'arrivalDate': request.arrivalDate.toIso8601String(),
          'departureDate': request.departureDate.toIso8601String(),
          'purpose': request.purpose,
          'guestCount': request.guestCount,
          'stayDuration': request.stayDuration,
        },
      );

      // Update the request with the chat message reference
      debugPrint('✅ [Hosting] Broadcast sent to community chat: $chatId');
    } catch (e) {
      debugPrint('❌ [Hosting] Error broadcasting to chat: $e');
    }
  }

  // =========================================================================
  // PHASE 3: Host Discovery
  // =========================================================================

  /// Host shows interest in a hosting request.
  Future<void> showInterest(String requestId) async {
    final user = _ref.read(authRepositoryProvider).currentUser;
    if (user == null) return;
    await _hostingRepo.showInterest(requestId, user.uid);
  }

  /// Host withdraws interest.
  Future<void> withdrawInterest(String requestId) async {
    final user = _ref.read(authRepositoryProvider).currentUser;
    if (user == null) return;
    await _hostingRepo.withdrawInterest(requestId, user.uid);
  }

  // =========================================================================
  // PHASE 4: DM Arrangement
  // =========================================================================

  /// Traveler selects a host and creates a hosting session.
  Future<HostingSession?> confirmArrangement({
    required HostingRequest request,
    required String hostId,
    required String hostName,
    String? hostPhoto,
    String? chatId,
  }) async {
    try {
      debugPrint('🏠 [confirmArrangement] Starting for request ${request.id}');
      debugPrint(
        '🏠 [confirmArrangement] Host: $hostName ($hostId), chatId: $chatId',
      );

      // 1. Update request to 'matched'
      debugPrint('🏠 [confirmArrangement] Step 1: selectHost...');
      await _hostingRepo.selectHost(
        requestId: request.id,
        hostId: hostId,
        hostName: hostName,
      );
      debugPrint('🏠 [confirmArrangement] Step 1 ✅ selectHost done');

      // 2. Create a hosting session
      debugPrint('🏠 [confirmArrangement] Step 2: Creating session object...');
      final sessionId = _hostingRepo.generateId();
      debugPrint('🏠 [confirmArrangement] Generated session ID: $sessionId');

      final session = HostingSession(
        id: sessionId,
        requestId: request.id,
        travelerId: request.travelerId,
        travelerName: request.travelerName,
        travelerPhoto: request.travelerPhoto,
        hostId: hostId,
        hostName: hostName,
        hostPhoto: hostPhoto,
        communityId: request.communityId,
        communityName: request.communityName,
        plannedArrival: request.arrivalDate,
        plannedDeparture: request.departureDate,
        createdAt: DateTime.now(),
        chatId: chatId,
      );
      debugPrint('🏠 [confirmArrangement] Session object created');

      debugPrint(
        '🏠 [confirmArrangement] Step 3: Saving session to Firestore...',
      );
      await _hostingRepo.createSession(session);
      debugPrint('🏠 [confirmArrangement] Step 3 ✅ Session saved');

      debugPrint('✅ [Hosting] Arrangement confirmed, session: $sessionId');
      return session;
    } catch (e, stackTrace) {
      debugPrint('❌ [Hosting] Error confirming arrangement: $e');
      debugPrint('❌ [Hosting] Stack trace: $stackTrace');
      return null;
    }
  }

  // =========================================================================
  // PHASE 5: QR Check-in / Check-out + DSP Settlement
  // =========================================================================

  /// QR Check-in: Activates the hosting session.
  Future<bool> checkIn(String sessionId) async {
    try {
      await _hostingRepo.checkIn(sessionId);
      return true;
    } catch (e) {
      debugPrint('❌ [Hosting] Check-in error: $e');
      return false;
    }
  }

  /// One party requests to end the stay.
  Future<bool> requestEndStay(String sessionId) async {
    try {
      final user = _ref.read(authRepositoryProvider).currentUser;
      if (user == null) return false;

      await _hostingRepo.requestEnd(
        sessionId: sessionId,
        requestedByUserId: user.uid,
      );
      return true;
    } catch (e) {
      debugPrint('❌ [Hosting] End request error: $e');
      return false;
    }
  }

  /// Both parties confirmed end — settle the session.
  Future<bool> settleSession(String sessionId) async {
    try {
      // 1. Calculate final days and mark as ended
      await _hostingRepo.confirmEnd(sessionId);

      // 2. Mark as settled (no DSP fee — hosting is free)
      await _hostingRepo.markSettled(sessionId);

      // 3. Award DSP for Peer Hosting (1000 flat + 100 per night)
      final session = await _hostingRepo.getSession(sessionId);
      if (session != null) {
        final nights = session.plannedDeparture.difference(session.plannedArrival).inDays;
        final actualNights = nights > 0 ? nights : 1;
        await _ref.read(pointsServiceProvider).trackHostATraveler(
          session.hostId,
          session.travelerId,
          nights: actualNights,
        );
      }

      debugPrint('✅ [Hosting] Session $sessionId settled');
      return true;
    } catch (e) {
      debugPrint('❌ [Hosting] Settlement error: $e');
      return false;
    }
  }

  /// Cancel a session before check-in.
  Future<bool> cancelSession(String sessionId) async {
    try {
      await _hostingRepo.cancelSession(sessionId);
      return true;
    } catch (e) {
      debugPrint('❌ [Hosting] Cancel error: $e');
      return false;
    }
  }

  /// Cancel a hosting request.
  Future<bool> cancelRequest(String requestId) async {
    try {
      await _hostingRepo.cancelRequest(requestId);
      return true;
    } catch (e) {
      debugPrint('❌ [Hosting] Cancel request error: $e');
      return false;
    }
  }
}
