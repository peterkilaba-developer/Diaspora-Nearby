import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

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

  /// Signs in with Google. Returns null if the user cancels the chooser.
  Future<UserCredential?> signInWithGoogle() async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) return null;
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    return _firebaseAuth.signInWithCredential(credential);
  }

  Future<void> signOut() async {
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    await _firebaseAuth.signOut();
  }

  /// Deletes the user's account and associated data.
  /// 1. Removes user from communities.
  /// 2. Deletes communities where the user was the only member.
  /// 3. Deletes user profile and points data.
  /// 4. Deletes Firebase Auth account.
  Future<void> deleteAccount() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return;

    final uid = user.uid;
    final firestore = FirebaseFirestore.instance;

    // 1. Get User Profile to find communities
    final userDoc = await firestore.collection('users').doc(uid).get();
    if (userDoc.exists) {
      final userData = userDoc.data();
      final communities = List<String>.from(
        userData?['communityMemberships'] ?? [],
      );

      for (final communityId in communities) {
        // Check member count (including this user)
        // If count is 1 (only this user), delete the community.
        final countQuery = await firestore
            .collection('users')
            .where('communityMemberships', arrayContains: communityId)
            .count()
            .get();

        if ((countQuery.count ?? 0) <= 1) {
          // Delete empty community
          await firestore.collection('communities').doc(communityId).delete();
        }
      }

      // 1.5. Organization Cleanup
      // Query organizations where user is an admin
      final orgsQuery = await firestore
          .collection('organizations')
          .where('admins', arrayContains: uid)
          .get();

      for (final orgDoc in orgsQuery.docs) {
        final orgData = orgDoc.data();
        final admins = List<dynamic>.from(orgData['admins'] ?? []);

        if (admins.length <= 1) {
          // Sole admin -> Delete Organization
          // (Optionally delete the associated chat if ID is known/consistent, e.g. org_ID)
          await firestore.collection('organizations').doc(orgDoc.id).delete();
        } else {
          // Multiple admins -> Remove user from admins
          await firestore.collection('organizations').doc(orgDoc.id).update({
            'admins': FieldValue.arrayRemove([uid]),
          });
        }
      }

      // 2. Delete User Profile
      await firestore.collection('users').doc(uid).delete();

      // 3. Delete auxiliary data (Points, etc.)
      await firestore.collection('user_points').doc(uid).delete();
    }

    // 4. Delete Auth Account
    await user.delete();
  }
}
