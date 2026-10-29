import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final adminRepositoryProvider = Provider((ref) => AdminRepository());

class AdminRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Map<String, int>? _cachedStats;
  Map<String, int>? getCachedDashboardStats() => _cachedStats;

  // Aggregate Stats (parallelized via Future.wait)
  Future<Map<String, int>> getDashboardStats() async {
    try {
      final results = await Future.wait<dynamic>([
        _firestore.collection('users').count().get(),
        _firestore.collection('communities').count().get(),
        _firestore.collection('events').count().get(),
        _firestore
            .collection('reports')
            .count()
            .get()
            .then<AggregateQuerySnapshot?>((r) => r)
            .catchError((_) => null),
      ]);

      final userCount = results[0] as AggregateQuerySnapshot;
      final communityCount = results[1] as AggregateQuerySnapshot;
      final eventCount = results[2] as AggregateQuerySnapshot;
      final reports = results[3] as AggregateQuerySnapshot?;

      final stats = {
        'users': userCount.count ?? 0,
        'communities': communityCount.count ?? 0,
        'events': eventCount.count ?? 0,
        'reports': reports?.count ?? 0,
      };
      _cachedStats = stats;
      return stats;
    } catch (e) {
      return _cachedStats ??
          {'users': 0, 'communities': 0, 'events': 0, 'reports': 0};
    }
  }

  // User Management
  Future<List<Map<String, dynamic>>> getAllUsers({
    int limit = 50,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      Query query = _firestore
          .collection('users')
          .orderBy('createdAt', descending: true)
          .limit(limit);
      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snapshot = await query.get();

      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> banUser(String userId, bool ban) async {
    await _firestore.collection('users').doc(userId).update({
      'isBanned': ban,
      'bannedAt': ban ? DateTime.now().toIso8601String() : null,
    });
  }

  // Community Management
  Future<List<Map<String, dynamic>>> getAllCommunities({int limit = 50}) async {
    try {
      final snapshot = await _firestore
          .collection('communities')
          .limit(limit)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> deleteCommunity(String communityId) async {
    await _firestore.collection('communities').doc(communityId).delete();
  }
}
