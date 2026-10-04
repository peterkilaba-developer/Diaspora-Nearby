import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';

import 'package:diaspora_nearby/features/hosting/models/hosting_request.dart';
import 'package:diaspora_nearby/features/hosting/models/hosting_session.dart';
import 'package:diaspora_nearby/features/hosting/repository/hosting_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';

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
      final createdRequest = await _hostingRepo.createRequest(request);

      // Broadcast to community chat (if chat exists)
      if (communityChatId != null && communityChatId.isNotEmpty) {
        await _broadcastToCommunityChatMessage(createdRequest, communityChatId);
      }

      debugPrint('✅ [Hosting] Request created and broadcast: $requestId');
      return createdRequest;
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

      final session = await _hostingRepo.createSession(
        requestId: request.id,
        hostId: hostId,
        chatId: chatId,
      );
      debugPrint('✅ [Hosting] Arrangement confirmed, session: ${session.id}');
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
  Future<bool> checkIn(String sessionId, String token) async {
    try {
      await _hostingRepo.checkIn(sessionId, token);
      return true;
    } catch (e) {
      debugPrint('❌ [Hosting] Check-in error: $e');
      return false;
    }
  }

  /// One party requests to end the stay.
  Future<bool> requestEndStay(String sessionId) async {
    try {
      await _hostingRepo.requestEnd(sessionId);
      return true;
    } catch (e) {
      debugPrint('❌ [Hosting] End request error: $e');
      return false;
    }
  }

  /// Both parties confirmed end — settle the session.
  Future<bool> settleSession(String sessionId) async {
    try {
      await _hostingRepo.confirmEnd(sessionId);
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
