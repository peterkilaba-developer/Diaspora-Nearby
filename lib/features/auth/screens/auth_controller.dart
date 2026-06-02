import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
// Needed for FirebaseAuthException
import '../repository/auth_repository.dart';
import 'package:diaspora_nearby/features/auth/services/session_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diaspora_nearby/features/dsp/services/smart_wallet_service.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/auth/services/pending_phone_service.dart';

final authControllerProvider = NotifierProvider<AuthController, bool>(
  AuthController.new,
);

/// When true, the phone/OTP screens should surface a "Sign in with Google"
/// fallback because SMS verification failed.
final googleFallbackVisibleProvider =
    NotifierProvider<GoogleFallbackVisible, bool>(GoogleFallbackVisible.new);

class GoogleFallbackVisible extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool value) => state = value;
}

class AuthController extends Notifier<bool> {
  @override
  bool build() {
    return false; // Initial loading state
  }

  void signInWithPhone(BuildContext context, String phoneNumber) async {
    state = true;
    final repository = ref.read(authRepositoryProvider);
    try {
      await repository.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (credential) async {
          // Auto-verification happened (e.g. instant verification or code auto-retrieval)
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
          debugPrint(
            'Phone Auth: verificationFailed: code=${e.code} msg=${e.message}',
          );
          state = false;
          // Surface the Google sign-in fallback so the user can still get in
          // and we can link the captured phone number to their Google account.
          ref.read(googleFallbackVisibleProvider.notifier).set(true);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_friendlyAuthError(e)),
                duration: const Duration(seconds: 6),
              ),
            );
          }
        },
        codeSent: (verificationId, resendToken) {
          debugPrint('Phone Auth: codeSent. ID: $verificationId');
          state = false;
          if (context.mounted) {
            context.push(
              '/auth/otp',
              extra: {
                'verificationId': verificationId,
                'phoneNumber': phoneNumber,
              },
            );
          }
        },
        codeAutoRetrievalTimeout: (verificationId) {
          debugPrint(
            'Phone Auth: codeAutoRetrievalTimeout. ID: $verificationId',
          );
          // Do not set state = false here necessarily, as user might still be typing
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
      final profileExists = await ref
          .read(profileRepositoryProvider)
          .profileExists(user.uid);
      debugPrint(
        'AuthCtrl: profileExists=$profileExists, context.mounted=${context.mounted}',
      );

      // Update Session based on Profile Existence
      await ref
          .read(sessionServiceProvider)
          .saveSession(
            userId: user.uid,
            hasCompletedOnboarding: true,
            profileComplete: profileExists,
            isReturningUser: profileExists,
          );

      // [SMART WALLET] Trigger wallet creation after sign-in (non-blocking)
      try {
        ref.read(smartWalletServiceProvider).ensureWalletOnSignIn();
        debugPrint('AuthCtrl: Smart wallet creation triggered');
      } catch (e) {
        debugPrint('AuthCtrl: Smart wallet trigger failed (non-blocking): $e');
      }

      if (context.mounted) {
        if (profileExists) {
          debugPrint('AuthCtrl: context.go(/chats)');
          context.go('/chats');
        } else {
          debugPrint('AuthCtrl: context.go(/profile-setup)');
          context.go('/profile-setup');
        }
      } else {
        debugPrint('AuthCtrl: context NOT MOUNTED! Navigation skipped.');
      }
    } catch (e) {
      debugPrint('AuthCtrl: ERROR in _handleSuccessfulSignIn: $e');
      // On network timeout/error, assume the user is existing and send to /chats.
      // Forcing them to /profile-setup on a timeout is destructive.
      if (context.mounted) context.go('/chats');
    }
  }

  String _friendlyAuthError(FirebaseAuthException e) {
    final raw = (e.message ?? '').toLowerCase();
    switch (e.code) {
      case 'too-many-requests':
        return 'This device is temporarily blocked by our anti-abuse system. '
            'Switch to a different network (mobile data ↔ Wi-Fi), wait ~1 hour, '
            'or reinstall the app from the Play Store.';
      case 'invalid-phone-number':
        return 'That phone number is not valid. Check the country code and try again.';
      case 'quota-exceeded':
        return 'SMS quota exceeded. Please try again later.';
      case 'app-not-authorized':
      case 'missing-client-identifier':
        return 'This app build is not authorized for phone sign-in. '
            'Please install the latest version from the Play Store.';
      case 'network-request-failed':
        return 'No internet connection. Check your network and try again.';
      default:
        if (raw.contains('blocked all requests') ||
            raw.contains('unusual activity')) {
          return 'This device is temporarily blocked. Switch networks or '
              'try again in about an hour.';
        }
        return e.message ?? 'Verification failed';
    }
  }

  void verifyOTP(
    BuildContext context,
    String verificationId,
    String smsCode,
  ) async {
    debugPrint('AuthCtrl: verifyOTP called');
    state = true;
    final repository = ref.read(authRepositoryProvider);
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      debugPrint('AuthCtrl: calling signInWithCredential...');
      final userCredential = await repository.signInWithCredential(credential);
      debugPrint(
        'AuthCtrl: signInWithCredential SUCCESS, user=${userCredential.user?.uid}',
      );

      if (userCredential.user != null) {
        if (context.mounted) {
          debugPrint(
            'AuthCtrl: context is mounted, calling _handleSuccessfulSignIn',
          );
          await _handleSuccessfulSignIn(context, userCredential.user!);
        } else {
          debugPrint('AuthCtrl: context NOT mounted after signIn!');
        }
      }

      state = false;
    } catch (e) {
      debugPrint('AuthCtrl: verifyOTP ERROR: $e');
      state = false;
      // OTP failed — offer Google sign-in as a fallback.
      ref.read(googleFallbackVisibleProvider.notifier).set(true);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  /// Google sign-in fallback used when SMS verification fails. After a
  /// successful Google sign-in, attaches the pending phone number (captured
  /// before SMS was attempted) to the user's Firestore profile.
  Future<void> signInWithGoogleFallback(BuildContext context) async {
    state = true;
    try {
      final repository = ref.read(authRepositoryProvider);
      final userCredential = await repository.signInWithGoogle();
      if (userCredential == null) {
        state = false;
        return; // user cancelled
      }
      final user = userCredential.user!;

      // Attach the pending phone number to the user's Firestore profile.
      final pendingPhoneService = ref.read(pendingPhoneServiceProvider);
      final pendingPhone = await pendingPhoneService.read();
      if (pendingPhone != null && pendingPhone.isNotEmpty) {
        // Dedupe: refuse if another user already owns this phone. Catches the
        // race the server-side walletPhoneHash dedupe can't — between the
        // Firestore phone-write and the eventual wallet creation.
        final collision = await FirebaseFirestore.instance
            .collection('users')
            .where('phoneNumber', isEqualTo: pendingPhone)
            .limit(2)
            .get();
        final collidingUid = collision.docs
            .map((d) => d.id)
            .firstWhere((uid) => uid != user.uid, orElse: () => '');
        if (collidingUid.isNotEmpty) {
          debugPrint(
            'AuthCtrl: phone $pendingPhone already linked to $collidingUid, aborting Google link',
          );
          await repository.signOut();
          state = false;
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'This phone number is already linked to another account. '
                  'Sign in using SMS verification with that phone.',
                ),
                duration: Duration(seconds: 6),
              ),
            );
          }
          return;
        }

        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({
                'phoneNumber': pendingPhone,
                'phoneLinkedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
          await pendingPhoneService.clear();
          debugPrint(
            'AuthCtrl: linked pending phone $pendingPhone to ${user.uid}',
          );
        } catch (e) {
          debugPrint('AuthCtrl: failed to link pending phone: $e');
        }
      }

      ref.read(googleFallbackVisibleProvider.notifier).set(false);

      if (context.mounted) {
        await _handleSuccessfulSignIn(context, user);
      }
      state = false;
    } catch (e) {
      debugPrint('AuthCtrl: Google fallback ERROR: $e');
      state = false;
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Google sign-in failed: $e')));
      }
    }
  }
}
