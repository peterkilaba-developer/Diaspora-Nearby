import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:whatsapp_zero_tap/whatsapp_zero_tap.dart';
import '../repository/auth_repository.dart';
import 'package:diaspora_nearby/features/auth/services/session_service.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diaspora_nearby/features/dsp/services/smart_wallet_service.dart';

final authControllerProvider = NotifierProvider<AuthController, bool>(
  AuthController.new,
);

/// Holds the most recent SMS `verificationId` emitted by `verifyPhoneNumber`
/// so navigating to `/auth/otp` immediately on tap works before `codeSent` fires.
final latestVerificationIdProvider =
    NotifierProvider<LatestVerificationIdNotifier, String?>(
      LatestVerificationIdNotifier.new,
    );

class LatestVerificationIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setVerificationId(String? id) => state = id;
}

/// Holds the active pre-flight WhatsApp Zero-Tap OTP Future started before
/// calling the Cloud Function so that zero-tap broadcasts arriving while the
/// network call / navigation is in-flight are never dropped.
final pendingWhatsAppZeroTapProvider = Provider<WhatsAppZeroTapSession>((ref) {
  return WhatsAppZeroTapSession();
});

class WhatsAppZeroTapSession {
  Future<String?>? _activeFuture;

  /// Starts the WhatsApp Zero-Tap handshake and BroadcastReceiver before
  /// the OTP request is sent over the network, avoiding race conditions.
  Future<String?> startPreFlightListener() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(null);
    }
    final future = _listen();
    _activeFuture = future;
    return future;
  }

  /// Consumes the pre-flight listener if one is active, or starts a new one.
  Future<String?> consumeOrStartListener() {
    final existing = _activeFuture;
    _activeFuture = null;
    if (existing != null) {
      return existing;
    }
    return startPreFlightListener();
  }

  Future<String?> _listen() async {
    try {
      final zeroTap = WhatsappZeroTap();
      final isSupported = await zeroTap.isWhatsAppOtpHandshakeSupported();
      if (!isSupported) {
        debugPrint('WhatsApp Zero-Tap handshake not supported on this device');
        return null;
      }
      debugPrint('WhatsApp Zero-Tap: listening for incoming OTP...');
      return await zeroTap.listenForOTP(timeout: const Duration(minutes: 2));
    } catch (e) {
      debugPrint('WhatsApp Zero-Tap listener completed or skipped: $e');
      return null;
    }
  }
}

class AuthController extends Notifier<bool> {
  @override
  bool build() {
    return false;
  }

  void signInWithPhone(BuildContext context, String phoneNumber) async {
    final repository = ref.read(authRepositoryProvider);
    ref.read(latestVerificationIdProvider.notifier).setVerificationId(null);

    // [PERF] Navigate to /auth/otp immediately on tap (0ms) so the user never
    // waits on verifyPhoneNumber network handshakes on PhoneAuthScreen.
    if (context.mounted) {
      final currentPath = GoRouterState.of(context).uri.toString();
      final isAlreadyOnOtp = currentPath.contains('/auth/otp');
      final extraData = {
        'verificationId': '',
        'phoneNumber': phoneNumber,
        'isWhatsApp': false,
      };
      if (!isAlreadyOnOtp) {
        unawaited(context.push('/auth/otp', extra: extraData));
      }
    }

    try {
      await repository.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (credential) async {
          debugPrint('Phone Auth: verificationCompleted triggered');
          state = true;
          try {
            final userCredential = await repository.signInWithCredential(
              credential,
            );
            if (context.mounted) {
              await _handleSuccessfulSignIn(context, userCredential.user!);
            }
          } catch (e) {
            state = false;
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Auto-sign in failed: ${e.toString()}')),
              );
            }
          }
        },
        verificationFailed: (e) {
          debugPrint('Phone Auth: verificationFailed: ${e.message}');
          state = false;
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(e.message ?? 'Verification failed')),
            );
          }
        },
        codeSent: (verificationId, resendToken) {
          debugPrint('Phone Auth: codeSent. ID: $verificationId');
          state = false;
          ref
              .read(latestVerificationIdProvider.notifier)
              .setVerificationId(verificationId);
        },
        codeAutoRetrievalTimeout: (verificationId) {
          debugPrint(
            'Phone Auth: codeAutoRetrievalTimeout. ID: $verificationId',
          );
          ref
              .read(latestVerificationIdProvider.notifier)
              .setVerificationId(verificationId);
        },
      );
    } catch (e) {
      state = false;
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _handleSuccessfulSignIn(BuildContext context, User user) async {
    debugPrint('AuthCtrl: _handleSuccessfulSignIn START for uid=${user.uid}');
    try {
      final sessionService = ref.read(sessionServiceProvider);
      final profileRepo = ref.read(profileRepositoryProvider);

      // [PERF] Fast synchronous check from memory or session cache first
      bool profileExists =
          profileRepo.getCachedProfile(user.uid) != null ||
          sessionService.isUserCached(user.uid);

      if (!profileExists) {
        // Check local Firestore cache before hitting server
        DocumentSnapshot<Map<String, dynamic>>? userDoc;
        try {
          userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get(const GetOptions(source: Source.cache));
        } catch (_) {}
        if (userDoc == null || !userDoc.exists) {
          userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
        }
        profileExists =
            userDoc.exists &&
            userDoc.data() != null &&
            userDoc.data()!.containsKey('firstName') &&
            (userDoc.data()!['firstName'] as String?)?.isNotEmpty == true;
      }

      // [PERF] Persist session & trigger smart wallet in background so navigation is 0ms
      unawaited(
        sessionService.saveSession(
          userId: user.uid,
          hasCompletedOnboarding: true,
          profileComplete: profileExists,
          isReturningUser: profileExists,
        ),
      );

      try {
        ref.read(smartWalletServiceProvider).ensureWalletOnSignIn();
      } catch (e) {
        debugPrint('AuthCtrl: Smart wallet trigger failed (non-blocking): $e');
      }

      if (context.mounted) {
        if (profileExists) {
          context.go('/chats');
        } else {
          context.go('/profile-setup');
        }
      }
    } catch (e) {
      debugPrint('AuthCtrl: ERROR in _handleSuccessfulSignIn: $e');
      if (context.mounted) context.go('/profile-setup');
    }
  }

  void verifyOTP(
    BuildContext context,
    String verificationId,
    String smsCode,
  ) async {
    final resolvedVerificationId = verificationId.isNotEmpty
        ? verificationId
        : (ref.read(latestVerificationIdProvider) ?? '');
    if (resolvedVerificationId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Waiting for SMS verification session…')),
      );
      return;
    }

    state = true;
    final repository = ref.read(authRepositoryProvider);
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: resolvedVerificationId,
        smsCode: smsCode,
      );
      final userCredential = await repository.signInWithCredential(credential);

      if (userCredential.user != null && context.mounted) {
        await _handleSuccessfulSignIn(context, userCredential.user!);
      }

      state = false;
    } catch (e) {
      debugPrint('AuthCtrl: verifyOTP ERROR: $e');
      state = false;
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  String _formatAuthError(dynamic e) {
    if (e is FirebaseFunctionsException) {
      return e.message ?? e.code;
    }
    if (e is FirebaseException && e.message != null && e.message!.isNotEmpty) {
      return e.message!;
    }
    final raw = e.toString();
    final firstLine = raw.split('\n').first.trim();
    return firstLine.replaceFirst(RegExp(r'^Exception:\s*'), '');
  }

  void signInWithWhatsApp(BuildContext context, String phoneNumber) async {
    final repository = ref.read(authRepositoryProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);

    // Initiate the WhatsApp Zero-Tap handshake BEFORE requesting the OTP
    // so the BroadcastReceiver is ready before the WhatsApp message arrives.
    ref.read(pendingWhatsAppZeroTapProvider).startPreFlightListener();

    // [PERF] Navigate to /auth/otp immediately on tap (0ms) and fire the
    // WhatsApp OTP Cloud Function in the background.
    if (context.mounted) {
      final currentPath = GoRouterState.of(context).uri.toString();
      final isAlreadyOnOtp = currentPath.contains('/auth/otp');
      final extraData = {
        'verificationId': 'whatsapp',
        'phoneNumber': phoneNumber,
        'isWhatsApp': true,
      };
      if (!isAlreadyOnOtp) {
        unawaited(context.push('/auth/otp', extra: extraData));
      }
    }

    unawaited(() async {
      try {
        await repository.requestWhatsAppOtp(phoneNumber);
      } catch (e) {
        final message = _formatAuthError(e);
        messenger?.showSnackBar(
          SnackBar(content: Text('WhatsApp request failed: $message')),
        );
      }
    }());
  }

  void verifyWhatsAppOTP(
    BuildContext context,
    String phoneNumber,
    String otp,
  ) async {
    state = true;
    final repository = ref.read(authRepositoryProvider);
    try {
      final customToken = await repository.verifyWhatsAppOtp(phoneNumber, otp);
      final userCredential = await repository.signInWithCustomToken(
        customToken,
      );

      if (userCredential.user != null && context.mounted) {
        await _handleSuccessfulSignIn(context, userCredential.user!);
      }
      state = false;
    } catch (e) {
      debugPrint('AuthCtrl: verifyWhatsAppOTP ERROR: $e');
      state = false;
      if (context.mounted) {
        final message = _formatAuthError(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('WhatsApp verification failed: $message')),
        );
      }
    }
  }
}
