import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/trust/models/trust_data.dart';

final trustRepositoryProvider = Provider<TrustRepository>((ref) {
  return TrustRepository(FirebaseFirestore.instance);
});

final trustDataProvider = FutureProvider.family<TrustData?, String>((
  ref,
  uid,
) async {
  return ref.watch(trustRepositoryProvider).getTrustData(uid);
});

class TrustRepository {
  final FirebaseFirestore _firestore;

  TrustRepository(this._firestore);

  // --- Trust Data ---

  Future<TrustData?> getTrustData(String uid) async {
    try {
      final doc = await _firestore.collection('trust_data').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        return TrustData.fromJson(doc.data()!);
      }
      return null;
    } catch (e) {
      debugPrint('Error getting trust data: $e');
      return null;
    }
  }

  Future<void> saveTrustData(TrustData data) async {
    try {
      await _firestore
          .collection('trust_data')
          .doc(data.uid)
          .set(data.toJson(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error saving trust data: $e');
      rethrow;
    }
  }

  Future<List<TrustData>> getCouncilEligibleUsers() async {
    try {
      final snapshot = await _firestore
          .collection('trust_data')
          .where('isCouncilEligible', isEqualTo: true)
          .limit(100) // Limit for safety, pagination might be needed later
          .get();

      return snapshot.docs
          .map((doc) => TrustData.fromJson(doc.data()))
          .toList();
    } catch (e) {
      debugPrint('Error fetching council eligible users: $e');
      return [];
    }
  }

  // --- Increments & Helpers ---

  Future<void> incrementJoinedEventsCount(String userId) async {
    await _firestore.collection('trust_data').doc(userId).set({
      'joinedEventsCount': FieldValue.increment(1),
      'lastUpdated': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  Future<void> incrementAttendedEventsCount(String userId) async {
    await _firestore.collection('trust_data').doc(userId).set({
      'attendedEventsCount': FieldValue.increment(1),
      'lastUpdated': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  Future<void> incrementVerifiedSolutionsCount(String userId) async {
    await _firestore.collection('trust_data').doc(userId).set({
      'verifiedSolutionsCount': FieldValue.increment(1),
      'lastUpdated': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  Future<void> incrementVerifiedCheckInCount(String userId) async {
    await _firestore.collection('trust_data').doc(userId).set({
      'verifiedCheckInCount': FieldValue.increment(1),
      'lastUpdated': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  Future<void> markIdentityQRExchanged(String userId) async {
    await _firestore.collection('trust_data').doc(userId).set({
      'identityQRExchange': true,
      'lastUpdated': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  Future<void> saveQRExchangeRecord(
    String fromUid,
    String toUid, {
    String? locationAddress,
  }) async {
    final id = '${fromUid}_${toUid}_qr';
    await _firestore.collection('qr_exchanges').doc(id).set({
      'fromUid': fromUid,
      'toUid': toUid,
      'locationAddress': locationAddress,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<bool> hasExchangedQR(String fromUid, String toUid) async {
    try {
      final id = '${fromUid}_${toUid}_qr';
      final doc = await _firestore.collection('qr_exchanges').doc(id).get();
      return doc.exists;
    } catch (e) {
      return false;
    }
  }

  Future<List<String>> getQrExchangeUserIds(String userId) async {
    try {
      final fromQuery = await _firestore
          .collection('qr_exchanges')
          .where('fromUid', isEqualTo: userId)
          .get();

      final toQuery = await _firestore
          .collection('qr_exchanges')
          .where('toUid', isEqualTo: userId)
          .get();

      final userIds = <String>{};

      for (var doc in fromQuery.docs) {
        userIds.add(doc['toUid'] as String);
      }
      for (var doc in toQuery.docs) {
        userIds.add(doc['fromUid'] as String);
      }

      return userIds.toList();
    } catch (e) {
      debugPrint('Error fetching QR exchanges: $e');
      return [];
    }
  }

  Future<void> saveCheckInRecord(
    String userId,
    String entityId,
    String type,
  ) async {
    final id = '${userId}_${entityId}_checkin';
    await _firestore.collection('check_ins').doc(id).set({
      'userId': userId,
      'entityId': entityId,
      'type': type, // 'event' or 'org'
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // --- Vouches ---

  Future<void> createVouch(Vouch vouch) async {
    try {
      await _firestore.collection('vouches').doc(vouch.id).set(vouch.toJson());

      // Update the "vouchedBy" list in the target user's trust data atomically (if possible)
      // This is best done in the Service via a recalculation, but appending here is good for immediate feedback
      // We will leave the heavy lifting to the Service.
    } catch (e) {
      debugPrint('Error creating vouch: $e');
      rethrow;
    }
  }

  Future<List<Vouch>> getVouchesForUser(String userId) async {
    try {
      final query = await _firestore
          .collection('vouches')
          .where('toUserId', isEqualTo: userId)
          .get();

      return query.docs.map((doc) => Vouch.fromJson(doc.data())).toList();
    } catch (e) {
      debugPrint('Error getting vouches for user: $e');
      return [];
    }
  }

  Future<List<Vouch>> getVouchesByVoucher(String userId) async {
    try {
      final query = await _firestore
          .collection('vouches')
          .where('fromUserId', isEqualTo: userId)
          .get();

      return query.docs.map((doc) => Vouch.fromJson(doc.data())).toList();
    } catch (e) {
      debugPrint('Error getting vouches by voucher: $e');
      return [];
    }
  }

  Future<bool> hasVouched(String fromUserId, String toUserId) async {
    try {
      final query = await _firestore
          .collection('vouches')
          .where('fromUserId', isEqualTo: fromUserId)
          .where('toUserId', isEqualTo: toUserId)
          .limit(1)
          .get();
      return query.docs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  // --- Trust Ratings ---

  Future<void> saveTrustRating({
    required String fromUserId,
    required String toUserId,
    required double score,
  }) async {
    final id = '${fromUserId}_$toUserId';
    await _firestore.collection('trust_ratings').doc(id).set({
      'fromUserId': fromUserId,
      'toUserId': toUserId,
      'score': score,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<List<double>> getTrustRatingsForUser(String userId) async {
    final details = await getDetailedTrustRatingsForUser(userId);
    return details.map((d) => (d['score'] as num).toDouble()).toList();
  }

  Future<List<Map<String, dynamic>>> getDetailedTrustRatingsForUser(
    String userId,
  ) async {
    try {
      final query = await _firestore
          .collection('trust_ratings')
          .where('toUserId', isEqualTo: userId)
          .get();

      return query.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      debugPrint('Error getting trust ratings: $e');
      return [];
    }
  }

  Future<double?> getRating({
    required String fromUserId,
    required String toUserId,
  }) async {
    try {
      final id = '${fromUserId}_$toUserId';
      final doc = await _firestore.collection('trust_ratings').doc(id).get();
      if (doc.exists && doc.data() != null) {
        return (doc.data()!['score'] as num).toDouble();
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // --- Field Verifications ---
  Future<void> saveVerificationEvent({
    required String fromUserId,
    required String toUserId,
    required Map<String, bool> fields,
  }) async {
    final id =
        '${fromUserId}_${toUserId}_${DateTime.now().millisecondsSinceEpoch}';
    await _firestore.collection('field_verifications').doc(id).set({
      'fromUserId': fromUserId,
      'toUserId': toUserId,
      'fields': fields,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<List<String>> getFlaggedFields(String userId) async {
    try {
      // Query recent verifications targeting this user
      final query = await _firestore
          .collection('field_verifications')
          .where('toUserId', isEqualTo: userId)
          .limit(50) // Analyze last 50 verifications
          .get();

      final Map<String, int> falseCounts = {};

      for (final doc in query.docs) {
        final data = doc.data();
        final fields = Map<String, dynamic>.from(
          data['fields'] ?? {},
        ); // Safe cast
        fields.forEach((key, value) {
          if (value == false) {
            falseCounts[key] = (falseCounts[key] ?? 0) + 1;
          }
        });
      }

      // Return fields with at least 1 negative verification
      return falseCounts.entries
          .where((e) => e.value >= 1)
          .map((e) => e.key)
          .toList();
    } catch (e) {
      // Ignore index errors or empty states
      return [];
    }
  }

  Future<bool> hasVerifiedUser(String fromUserId, String toUserId) async {
    try {
      final query = await _firestore
          .collection('field_verifications')
          .where('fromUserId', isEqualTo: fromUserId)
          .where('toUserId', isEqualTo: toUserId)
          .limit(1)
          .get();
      return query.docs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<DateTime?> getLastVerificationTime(String fromUserId) async {
    try {
      final query = await _firestore
          .collection('field_verifications')
          .where('fromUserId', isEqualTo: fromUserId)
          .get();

      if (query.docs.isNotEmpty) {
        final data = query.docs.first.data();
        if (data['timestamp'] is Timestamp) {
          return (data['timestamp'] as Timestamp).toDate();
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getAllVerificationsForUser(
    String userId,
  ) async {
    try {
      final query = await _firestore
          .collection('field_verifications')
          .where('toUserId', isEqualTo: userId)
          .get();

      return query.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      debugPrint('Error getting all verifications: $e');
      return [];
    }
  }

  Future<void> updateTrustCounter(
    String userId,
    String field,
    int value,
  ) async {
    await _firestore.collection('trust_data').doc(userId).set({
      field: value,
      'lastUpdated': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  Future<void> incrementTrustMetric(String userId, String fieldName) async {
    await _firestore.collection('trust_data').doc(userId).set({
      fieldName: FieldValue.increment(1),
      'lastUpdated': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }
}
