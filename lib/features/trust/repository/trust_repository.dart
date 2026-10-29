import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/trust/models/trust_data.dart';

final trustRepositoryProvider = Provider<TrustRepository>((ref) {
  return TrustRepository(FirebaseFirestore.instance);
});

final trustDataProvider = StreamProvider.family<TrustData?, String>((ref, uid) {
  return ref.watch(trustRepositoryProvider).streamTrustData(uid);
});

class TrustRepository {
  final FirebaseFirestore _firestore;

  TrustRepository(this._firestore);

  static final Map<String, TrustData> _trustCache = {};
  static final Map<String, Map<String, Map<String, dynamic>>> _qrRecordsCache =
      {};
  static final Map<String, List<String>> _qrUserIdsCache = {};
  static final Map<String, double> _ratingsCache = {};
  static final Map<String, Map<String, dynamic>> _ratingDocsCache = {};
  static final Map<String, List<String>> _flaggedFieldsCache = {};
  static final Set<String> _verifiedPairsCache = {};

  TrustData? getCachedTrustData(String uid) => _trustCache[uid];

  void cacheTrustData(TrustData data) {
    _trustCache[data.uid] = data;
  }

  Map<String, Map<String, dynamic>>? getCachedQrExchangeRecords(
    String userId,
  ) => _qrRecordsCache[userId];

  List<String>? getCachedQrExchangeUserIds(String userId) =>
      _qrUserIdsCache[userId];

  double? getCachedRating({
    required String fromUserId,
    required String toUserId,
  }) => _ratingsCache['${fromUserId}_$toUserId'];

  Map<String, dynamic>? getCachedTrustRatingDoc({
    required String fromUserId,
    required String toUserId,
  }) => _ratingDocsCache['${fromUserId}_$toUserId'];

  List<String>? getCachedFlaggedFields(String userId) =>
      _flaggedFieldsCache[userId];

  bool? getCachedHasVerifiedUser(String fromUserId, String toUserId) =>
      _verifiedPairsCache.contains('${fromUserId}_$toUserId') ? true : null;

  // --- Trust Data ---

  Future<TrustData?> getTrustData(String uid) async {
    try {
      final doc = await _firestore.collection('trust_data').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        final raw = Map<String, dynamic>.from(doc.data()!);
        raw['uid'] ??= doc.id;
        final parsed = TrustData.fromJson(raw);
        _trustCache[uid] = parsed;
        return parsed;
      }
      return _trustCache[uid];
    } catch (e) {
      debugPrint('Error getting trust data: $e');
      return _trustCache[uid];
    }
  }

  Stream<TrustData?> streamTrustData(String uid) {
    return Stream.multi((controller) {
      final cached = _trustCache[uid];
      if (cached != null) {
        controller.add(cached);
      }
      final sub = _firestore.collection('trust_data').doc(uid).snapshots().listen(
        (doc) {
          if (doc.exists && doc.data() != null) {
            final raw = Map<String, dynamic>.from(doc.data()!);
            raw['uid'] ??= doc.id;
            final parsed = TrustData.fromJson(raw);
            _trustCache[uid] = parsed;
            controller.add(parsed);
          } else {
            controller.add(null);
          }
        },
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = sub.cancel;
    });
  }

  Future<void> saveTrustData(TrustData data) async {
    _trustCache[data.uid] = data;
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
      final queries = await Future.wait([
        _firestore
            .collection('qr_exchanges')
            .where('fromUid', isEqualTo: userId)
            .limit(200)
            .get(),
        _firestore
            .collection('qr_exchanges')
            .where('toUid', isEqualTo: userId)
            .limit(200)
            .get(),
      ]);
      final fromQuery = queries[0];
      final toQuery = queries[1];

      debugPrint(
        '🔍 [TrustRepo] QR query for $userId: fromQuery=${fromQuery.docs.length} docs, toQuery=${toQuery.docs.length} docs',
      );

      final userIds = <String>{};

      for (var doc in fromQuery.docs) {
        userIds.add(doc['toUid'] as String);
      }
      for (var doc in toQuery.docs) {
        userIds.add(doc['fromUid'] as String);
      }

      debugPrint('🔍 [TrustRepo] QR userIds for $userId: $userIds');

      final result = userIds.toList();
      _qrUserIdsCache[userId] = result;
      return result;
    } catch (e) {
      debugPrint('Error fetching QR exchanges: $e');
      return _qrUserIdsCache[userId] ?? [];
    }
  }

  /// Returns full QR exchange records keyed by partner user ID.
  /// Each value contains {locationAddress, timestamp} from the exchange.
  Future<Map<String, Map<String, dynamic>>> getQrExchangeRecords(
    String userId,
  ) async {
    try {
      final queries = await Future.wait([
        _firestore
            .collection('qr_exchanges')
            .where('fromUid', isEqualTo: userId)
            .limit(200)
            .get(),
        _firestore
            .collection('qr_exchanges')
            .where('toUid', isEqualTo: userId)
            .limit(200)
            .get(),
      ]);
      final fromQuery = queries[0];
      final toQuery = queries[1];

      final records = <String, Map<String, dynamic>>{};

      for (var doc in fromQuery.docs) {
        final data = doc.data();
        final partnerId = data['toUid'] as String;
        records[partnerId] = {
          'locationAddress': data['locationAddress'],
          'timestamp': data['timestamp'],
        };
      }
      for (var doc in toQuery.docs) {
        final data = doc.data();
        final partnerId = data['fromUid'] as String;
        if (!records.containsKey(partnerId)) {
          records[partnerId] = {
            'locationAddress': data['locationAddress'],
            'timestamp': data['timestamp'],
          };
        }
      }

      _qrRecordsCache[userId] = records;
      _qrUserIdsCache[userId] = records.keys.toList();
      return records;
    } catch (e) {
      debugPrint('Error fetching QR exchange records: $e');
      return _qrRecordsCache[userId] ?? {};
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
      final id = '${vouch.fromUserId}_${vouch.toUserId}';
      await _firestore.collection('vouches').doc(id).set({
        ...vouch.toJson(),
        'id': id,
        'stakeAmount': 0,
      });

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
          .limit(500)
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
          .limit(500)
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
    bool isFullTrust = false,
    int stakedAmount = 0,
    int remainingStake = 0,
    String? fromUserName,
  }) async {
    final id = '${fromUserId}_$toUserId';
    _ratingsCache[id] = score;
    final coreData = <String, dynamic>{
      'fromUserId': fromUserId,
      'toUserId': toUserId,
      'score': score,
      'isFullTrust': isFullTrust,
      'timestamp': DateTime.now().toIso8601String(),
    };
    if (fromUserName != null) coreData['fromUserName'] = fromUserName;
    _ratingDocsCache[id] = {...?_ratingDocsCache[id], ...coreData};
    final ref = _firestore.collection('trust_ratings').doc(id);
    final existing = await ref.get();
    if (existing.exists) {
      await ref.update(coreData);
    } else {
      await ref.set({
        ...coreData,
        // Server derives these values after creation.
        'stakedAmount': 0,
        'remainingStake': 0,
      });
    }
  }

  Future<List<Map<String, dynamic>>> getTrustRatingsForUser(
    String userId,
  ) async {
    final query = await _firestore
        .collection('trust_ratings')
        .where('toUserId', isEqualTo: userId)
        .limit(500)
        .get();
    return query.docs.map((doc) => doc.data()).toList();
  }

  Future<List<Map<String, dynamic>>> getDetailedTrustRatingsForUser(
    String userId,
  ) async {
    try {
      final query = await _firestore
          .collection('trust_ratings')
          .where('toUserId', isEqualTo: userId)
          .limit(500)
          .get();

      return query.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      debugPrint('Error getting trust ratings: $e');
      return [];
    }
  }

  /// Gets all full-trust stakers for a user (score > 90 with active stake)
  Future<List<Map<String, dynamic>>> getFullTrustStakersForUser(
    String userId,
  ) async {
    try {
      final query = await _firestore
          .collection('trust_ratings')
          .where('toUserId', isEqualTo: userId)
          .where('isFullTrust', isEqualTo: true)
          .limit(100)
          .get();

      return query.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      debugPrint('Error getting full trust stakers: $e');
      return [];
    }
  }

  /// Gets the full rating document between two users
  Future<Map<String, dynamic>?> getTrustRatingDoc({
    required String fromUserId,
    required String toUserId,
  }) async {
    try {
      final id = '${fromUserId}_$toUserId';
      final doc = await _firestore.collection('trust_ratings').doc(id).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        _ratingDocsCache[id] = data;
        if (data['score'] is num) {
          _ratingsCache[id] = (data['score'] as num).toDouble();
        }
        return data;
      }
      return null;
    } catch (e) {
      debugPrint('Error getting trust rating doc: $e');
      return _ratingDocsCache['${fromUserId}_$toUserId'];
    }
  }

  /// Updates a staker's remaining stake balance
  Future<void> updateStakerBalance({
    required String fromUserId,
    required String toUserId,
    required int remainingStake,
    bool? isFullTrust,
  }) async {
    final id = '${fromUserId}_$toUserId';
    final updates = <String, dynamic>{'remainingStake': remainingStake};
    if (isFullTrust != null) updates['isFullTrust'] = isFullTrust;
    await _firestore.collection('trust_ratings').doc(id).update(updates);
  }

  Future<double?> getRating({
    required String fromUserId,
    required String toUserId,
  }) async {
    try {
      final id = '${fromUserId}_$toUserId';
      final doc = await _firestore.collection('trust_ratings').doc(id).get();
      if (doc.exists && doc.data() != null) {
        final score = (doc.data()!['score'] as num).toDouble();
        _ratingsCache[id] = score;
        return score;
      }
      return null;
    } catch (e) {
      return _ratingsCache['${fromUserId}_$toUserId'];
    }
  }

  // --- Field Verifications ---
  Future<void> saveVerificationEvent({
    required String fromUserId,
    required String toUserId,
    required Map<String, bool> fields,
  }) async {
    final id = '${fromUserId}_$toUserId';
    _verifiedPairsCache.add(id);
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
      final flagged = falseCounts.entries
          .where((e) => e.value >= 1)
          .map((e) => e.key)
          .toList();
      _flaggedFieldsCache[userId] = flagged;
      return flagged;
    } catch (e) {
      // Ignore index errors or empty states
      return _flaggedFieldsCache[userId] ?? [];
    }
  }

  Future<bool> hasVerifiedUser(String fromUserId, String toUserId) async {
    final id = '${fromUserId}_$toUserId';
    if (_verifiedPairsCache.contains(id)) return true;
    try {
      final query = await _firestore
          .collection('field_verifications')
          .where('fromUserId', isEqualTo: fromUserId)
          .where('toUserId', isEqualTo: toUserId)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        _verifiedPairsCache.add(id);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<DateTime?> getLastVerificationTime(String fromUserId) async {
    try {
      final query = await _firestore
          .collection('field_verifications')
          .where('fromUserId', isEqualTo: fromUserId)
          .limit(1)
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
          .limit(100)
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
