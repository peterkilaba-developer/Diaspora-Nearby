import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
// Needed for FirebaseAuthException
import '../repository/auth_repository.dart';
import 'package:diaspora_nearby/features/auth/services/session_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diaspora_nearby/features/dsp/services/smart_wallet_service.dart';

final authControllerProvider = NotifierProvider<AuthController, bool>(
  AuthController.new,
);

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
      // [FIX] Check for firstName being present and non-empty, not just doc.exists.
      // A bare FCM-only doc ({fcmToken, notificationsEnabled}) would return exists=true
      // but should NOT be treated as a completed profile.
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final profileExists =
          userDoc.exists &&
          userDoc.data() != null &&
          userDoc.data()!.containsKey('firstName') &&
          (userDoc.data()!['firstName'] as String?)?.isNotEmpty == true;
      debugPrint(
        'AuthCtrl: profileExists=$profileExists (docExists=${userDoc.exists}, hasFirstName=${userDoc.data()?.containsKey('firstName') ?? false}), context.mounted=${context.mounted}',
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
      if (context.mounted) context.go('/profile-setup');
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
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }
}
