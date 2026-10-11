import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(FirebaseAuth.instance);
});

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

class AuthRepository {
  final FirebaseAuth _firebaseAuth;
  AuthRepository(this._firebaseAuth);
  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();
  User? get currentUser => _firebaseAuth.currentUser;
  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required void Function(PhoneAuthCredential) verificationCompleted,
    required void Function(FirebaseAuthException) verificationFailed,
    required void Function(String, int?) codeSent,
    required void Function(String) codeAutoRetrievalTimeout,
  }) async {
    await _firebaseAuth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: verificationCompleted,
      verificationFailed: verificationFailed,
      codeSent: codeSent,
      codeAutoRetrievalTimeout: codeAutoRetrievalTimeout,
    );
  }

  Future<UserCredential> signInWithCredential(
    PhoneAuthCredential credential,
  ) async {
    return await _firebaseAuth.signInWithCredential(credential);
  }

  Future<UserCredential> signInWithCustomToken(String token) async {
    return await _firebaseAuth.signInWithCustomToken(token);
  }

  Future<void> signOut() async {
    await _firebaseAuth.signOut();
  }

  /// Deletes the authenticated account through the privileged, recursive
  /// server erasure workflow. Client rules intentionally deny these deletes.
  Future<void> deleteAccount() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return;
    await FirebaseFunctions.instance.httpsCallable('deleteMyAccount').call({
      'confirm': true,
    });
    await _firebaseAuth.signOut();
  }

  /// Custom WhatsApp Auth Flow
  Future<Map<String, dynamic>> requestWhatsAppOtp(String phoneNumber) async {
    final callable = FirebaseFunctions.instance.httpsCallable(
      'requestWhatsAppOtp',
    );
    final result = await callable.call({'phoneNumber': phoneNumber});
    if (result.data is Map) {
      return Map<String, dynamic>.from(result.data as Map);
    }
    return {'success': true};
  }

  Future<String> verifyWhatsAppOtp(String phoneNumber, String otp) async {
    final callable = FirebaseFunctions.instance.httpsCallable(
      'verifyWhatsAppOtp',
    );
    final result = await callable.call({
      'phoneNumber': phoneNumber,
      'otp': otp,
    });
    return result.data['token'] as String;
  }
}
