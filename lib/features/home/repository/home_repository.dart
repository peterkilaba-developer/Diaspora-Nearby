import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/models/profile_data.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';

final homeRepositoryProvider = Provider((ref) {
  final auth = ref.watch(authRepositoryProvider);
  return HomeRepository(FirebaseFirestore.instance, auth);
});

class HomeRepository {
  final FirebaseFirestore _firestore;
  final AuthRepository _auth;

  HomeRepository(this._firestore, this._auth);

  Future<List<ProfileData>> getNearbyUsers({bool isGlobal = false}) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return [];

      final currentUserDoc = await _firestore.collection('users').doc(currentUser.uid).get();
      if (!currentUserDoc.exists) return [];
      
      final currentUserData = currentUserDoc.data()!;
      Query query = _firestore.collection('users');

      if (!isGlobal) {
        final homeCountryCode = currentUserData['homeCountryCode'] as String?;
        if (homeCountryCode != null) {
          query = query.where('homeCountryCode', isEqualTo: homeCountryCode);
        }
      }

      final snapshot = await query.limit(50).get();
      
      // Fix casting issue: Explicitly cast 'data' to Map<String, dynamic>
      return snapshot.docs
          .where((doc) => doc.id != currentUser.uid)
          .map((doc) {
             final data = doc.data() as Map<String, dynamic>; // CAST ADDED
             final profile = ProfileData.fromJson(data);
             profile.uid = doc.id;
             return profile;
          }).toList();
    } catch (e) {
      return [];
    }
  }
}

