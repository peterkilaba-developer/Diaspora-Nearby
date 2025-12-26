import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
// Needed for FirebaseAuthException
import '../repository/auth_repository.dart';
import 'package:diaspora_nearby/services/session_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

final authControllerProvider = NotifierProvider<AuthController, bool>(AuthController.new);

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
          state = false;
          final userCredential = await repository.signInWithCredential(credential);
          if (userCredential?.user != null) {
            await _handleSuccessfulSignIn(context, userCredential!.user!);
          }
        },
        verificationFailed: (e) {
             state = false;
             ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'Verification failed')));
        },
        codeSent: (verificationId, resendToken) {
            state = false;
            context.push('/auth/otp', extra: {'verificationId': verificationId, 'phoneNumber': phoneNumber});
        },
        codeAutoRetrievalTimeout: (verificationId) {},
      );
    } catch (e) {
      state = false;
      if (context.mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _handleSuccessfulSignIn(BuildContext context, User user) async {
    try {
      // Check if user profile exists in Firestore
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final profileExists = userDoc.exists;

      // Update Session based on Profile Existence
      await ref.read(sessionServiceProvider).saveSession(
        userId: user.uid,
        hasCompletedOnboarding: true, // Assuming if they are here, they passed onboarding
        profileComplete: profileExists, // Only complete if profile exists
        isReturningUser: profileExists, // New users start as non-returning (for router logic)
      );

      if (context.mounted) {
        if (profileExists) {
           context.go('/chats'); 
        } else {
           context.go('/profile-setup');
        }
      }
    } catch (e) {
      print('Auth Controller Error: $e');
      // Fallback: If firestore fails, we assume incomplete but let them in? 
      // Or we just default to profile setup to be safe.
       if (context.mounted) context.go('/profile-setup');
    }
  }


  void verifyOTP(BuildContext context, String verificationId, String smsCode) async {
    state = true;
    final repository = ref.read(authRepositoryProvider);
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      final userCredential = await repository.signInWithCredential(credential);
      
      if (userCredential?.user != null) {
         await _handleSuccessfulSignIn(context, userCredential!.user!);
      }
      
      state = false;
      // Navigation is now handled inside _handleSuccessfulSignIn
    } catch (e) {
      state = false;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }
}
