import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';
import 'package:diaspora_nearby/features/dsp/models/user_points.dart';
import 'package:diaspora_nearby/features/dsp/models/points_transaction.dart';
import 'package:diaspora_nearby/features/dsp/models/corridor_model.dart';
import 'package:diaspora_nearby/core/data/countries.dart'
    hide getContinentByCountryCode;

final pointsRepositoryProvider = Provider<PointsRepository>((ref) {
  return PointsRepository(
    FirebaseFirestore.instance,
    FirebaseFunctions.instance,
  );
});

final userPointsProvider = StreamProvider.family<UserPoints?, String>((
  ref,
  userId,
) {
  return ref.watch(pointsRepositoryProvider).streamUserPoints(userId);
});

final countryLeaderboardProvider = StreamProvider<List<Map<String, String>>>((
  ref,
) {
  return ref.watch(pointsRepositoryProvider).streamCountryLeaderboard();
});

final communityPointsProvider = StreamProvider.family<int, String>((
  ref,
  communityId,
) {
  return ref.watch(pointsRepositoryProvider).streamCommunityPoints(communityId);
});

final globalSupplyProvider = StreamProvider<int>((ref) {
  return ref.watch(pointsRepositoryProvider).streamGlobalSupply();
});

final systemTreasuryProvider = StreamProvider<Map<String, dynamic>>((ref) {
  return ref.watch(pointsRepositoryProvider).streamSystemTreasury();
});

final globalMemberCountProvider = StreamProvider<int>((ref) {
  return ref.watch(pointsRepositoryProvider).streamGlobalMemberCount();
});

final userTransactionsProvider =
    StreamProvider.family<List<PointsTransaction>, String>((ref, userId) {
      return ref.watch(pointsRepositoryProvider).streamUserTransactions(userId);
    });

final p2pUserTransactionsProvider =
    StreamProvider.family<
      List<PointsTransaction>,
      ({String userId, String recipientId})
    >((ref, args) {
      return ref
          .watch(pointsRepositoryProvider)
          .streamP2PUserTransactions(
            currentUserId: args.userId,
            recipientId: args.recipientId,
          );
    });

final internalGdpProvider = StreamProvider<int>((ref) {
  return ref.watch(pointsRepositoryProvider).streamInternalGdp();
});

final fiatGdpProvider = StreamProvider<double>((ref) {
  return ref.watch(pointsRepositoryProvider).streamFiatGdpUsd();
});

final corridorsProvider = StreamProvider<List<Corridor>>((ref) {
  return ref.watch(pointsRepositoryProvider).streamCorridors();
});

class PointsRepository {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  PointsRepository(this._firestore, this._functions);

  // --- Real-time Leaderboard & Community Stats ---

  /// Streams the country leaderboard by points.
  /// Filters for type: 'country' and locationType: 'home'.
  Stream<List<Map<String, String>>> streamCountryLeaderboard() {
    return _firestore
        .collection('communities')
        .where('type', isEqualTo: 'country')
        .where('locationType', isEqualTo: 'home')
        .orderBy('points', descending: true)
        .limit(200)
        .snapshots()
        .map((snapshot) {
          // Fetch data and sort in Dart for better precision/secondary criteria without complex composite indices
          final List<Map<String, dynamic>> rawData = snapshot.docs
              .map((doc) => doc.data())
              .toList();

          // Sort: primary points, secondary cumulativeEarnings
          rawData.sort((a, b) {
            final int aPoints = a['points'] as int? ?? 0;
            final int bPoints = b['points'] as int? ?? 0;
            if (aPoints != bPoints) return bPoints.compareTo(aPoints);

            final int aCum = a['cumulativeEarnings'] as int? ?? 0;
            final int bCum = b['cumulativeEarnings'] as int? ?? 0;
            return bCum.compareTo(aCum);
          });

          return rawData.asMap().entries.map((entry) {
            final index = entry.key;
            final data = entry.value;
            final points = data['points'] as int? ?? 0;
            final cumulative = data['cumulativeEarnings'] as int? ?? 0;
            final countryCode =
                (data['location'] as Map<String, dynamic>?)?['countryCode']
                    as String? ??
                '';
            final country = getCountryByCode(countryCode);
            final rawName = data['name'] as String? ?? 'Unknown';
            final cleanName = rawName.replaceAll(' Community', '').trim();

            return {
              'rank': '${index + 1}',
              'name': country?.name ?? cleanName,
              'flag': country?.flag ?? '',
              'balance':
                  '${points.toString().replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]},")} DSP',
              'points': '$points',
              'cumulativeEarnings': '$cumulative',
              'memberPoints': '${data['memberPoints'] ?? 0}',
              'memberCount': '${data['memberCount'] ?? 0}',
              'averagePoCT': '${data['averagePoCT'] ?? 0.0}',
            };
          }).toList();
        })
        .onErrorReturn(const <Map<String, String>>[])
        .startWith(const <Map<String, String>>[]);
  }

  /// Streams points for a specific community.
  Stream<int> streamCommunityPoints(String communityId) {
    return _firestore
        .collection('communities')
        .doc(communityId)
        .snapshots()
        .map((doc) => doc.data()?['points'] as int? ?? 0)
        .onErrorReturn(0)
        .startWith(0);
  }

  /// Streams system treasury data.
  Stream<Map<String, dynamic>> streamSystemTreasury() {
    return _firestore
        .collection('system_stats')
        .doc('treasury')
        .snapshots()
        .map((doc) => doc.data() ?? {})
        .onErrorReturn(const <String, dynamic>{})
        .startWith(const <String, dynamic>{});
  }

  /// Streams the total internal GDP from system stats.
  ///
  /// The backend transaction updates this materialized global counter with
  /// every accepted economic operation, avoiding a platform-wide chamber scan.
  Stream<int> streamInternalGdp() {
    return _firestore
        .collection('system_stats')
        .doc('treasury')
        .snapshots()
        .map((doc) => (doc.data()?['totalInternalGdp'] as num? ?? 0).toInt())
        .onErrorReturn(0)
        .startWith(0);
  }

  /// Streams the total fiat GDP in USD from system stats.
  ///
  /// This is the real economic output: the cumulative fiat value (in USD)
  /// of all completed economic transactions (marketplace purchases, bookings,
  /// remittances, paid event tickets, etc.).
  Stream<double> streamFiatGdpUsd() {
    return _firestore
        .collection('system_stats')
        .doc('treasury')
        .snapshots()
        .map(
          (doc) => (doc.data()?['totalFiatGdpUsd'] as num?)?.toDouble() ?? 0.0,
        )
        .onErrorReturn(0)
        .startWith(0);
  }

  /// Records a completed real-economy transaction's fiat value as GDP output.
  /// [SECURITY] Routes through Cloud Function (system_stats writes blocked).
  Future<void> recordFiatGdp(
    double amountUsd,
    String activityType, {
    Map<String, dynamic>? metadata,
  }) async {
    if (amountUsd <= 0) return;
    try {
      final callable = _functions.httpsCallable('recordFiatGdp');
      await callable.call({
        'amountUsd': amountUsd,
        'activityType': activityType,
        'metadata': metadata,
      });
    } catch (e) {
      debugPrint('[recordFiatGdp] Cloud Function error: $e');
      rethrow;
    }
  }

  /// Streams the 200 most economically active bilateral corridors.
  ///
  /// Source of truth is now the chamber doc (`organizations` where
  /// `kind == 'corridor_chamber'`). Each chamber projects into a
  /// drop-in-compatible [Corridor] view so existing UIs keep working.
  /// Bilateral (single doc per real corridor); the legacy directional
  /// `corridors/{senderCC_receiverCC}` collection is no longer read.
  Stream<List<Corridor>> streamCorridors() {
    return _firestore
        .collection('organizations')
        .where('kind', isEqualTo: 'corridor_chamber')
        .orderBy('gdpTotal', descending: true)
        .limit(200)
        .snapshots()
        .map((snapshot) {
          final corridors = snapshot.docs.map((doc) {
            final d = doc.data();
            final host = (d['hostCountryCode'] as String?) ?? '';
            final home = (d['homeCountryCode'] as String?) ?? '';
            return Corridor(
              id: doc.id,
              // Sender / receiver kept for shape compatibility — host
              // represents the country the activity happens IN, home is
              // the diaspora origin. The UI uses them only for flag icons.
              senderCountry: host,
              receiverCountry: home,
              cumulativeGdp: (d['gdpTotal'] as num? ?? 0).toInt(),
              transactionCount: (d['transactionCount'] as num? ?? 0).toInt(),
              lastTransactionAt: Corridor.parseTimestamp(
                d['lastTransactionAt'],
              ),
            );
          }).toList();
          // Sort client-side by GDP desc (Firestore index would also work).
          corridors.sort((a, b) => b.cumulativeGdp.compareTo(a.cumulativeGdp));
          return corridors;
        })
        .onErrorReturn(const <Corridor>[])
        .startWith(const <Corridor>[]);
  }

  // NOTE: Global supply tracking and treasury distribution are now handled
  // entirely by Cloud Functions (awardPoints, awardMessagePoints, etc.).
  // See functions/lib/dsp.js for the server-side implementation.

  // Get current Global Supply
  Future<int> getGlobalSupply() async {
    try {
      final doc = await _firestore
          .collection('system_stats')
          .doc('dsp_supply')
          .get();
      if (!doc.exists) return 0;
      return doc.data()?['totalMinted'] as int? ?? 0;
    } catch (e) {
      debugPrint('Error fetching global supply: $e');
      return 0;
    }
  }

  /// Force sync treasury balances based on total global supply.
  /// [SECURITY] Routes through Cloud Function (admin-only reconciliation).
  Future<void> syncTreasuryBalances() async {
    try {
      final callable = _functions.httpsCallable(
        'syncTreasuryBalances',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 300)),
      );
      await callable.call({});
    } catch (e) {
      debugPrint('[syncTreasuryBalances] Cloud Function error: $e');
      rethrow;
    }
  }

  // [NEW] Stream Global Supply for Real-time Stats
  Stream<int> streamGlobalSupply() {
    return _firestore
        .collection('system_stats')
        .doc('dsp_supply')
        .snapshots()
        .map((doc) => doc.data()?['totalMinted'] as int? ?? 0)
        .onErrorReturn(0)
        .startWith(0);
  }

  // [NEW] Stream global member count for Community Epoch logic
  Stream<int> streamGlobalMemberCount() {
    return _firestore
        .collection('communities')
        .doc('global_community')
        .snapshots()
        .map((doc) {
          return (doc.data()?['memberCount'] as int?) ?? 0;
        })
        .onErrorReturn(0)
        .startWith(0);
  }

  // [NEW] Update Wallet Address
  Future<void> updateWalletAddress(String userId, String walletAddress) async {
    try {
      if (walletAddress.isEmpty) return;
      await _firestore.collection('user_points').doc(userId).update({
        'walletAddress': walletAddress,
        'lastUpdated': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error updating wallet address: $e');
      rethrow;
    }
  }

  // [NEW] Get all system wallet addresses for the allocation table
  Future<Map<String, String>> getSystemWallets() async {
    try {
      final doc = await _firestore
          .collection('system_stats')
          .doc('treasury')
          .get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        return {
          'ecosystem': data['ecosystemWallet'] as String? ?? 'Pending TGE...',
          'founders': data['foundersWallet'] as String? ?? 'Pending Vesting...',
          'liquidity': data['liquidityWallet'] as String? ?? 'Pending...',
        };
      }
      return {
        'ecosystem': 'Pending TGE...',
        'founders': 'Pending Vesting...',
        'liquidity': 'Pending...',
      };
    } catch (e) {
      debugPrint('Error fetching treasury wallets: $e');
      return {
        'ecosystem': 'Error loading...',
        'founders': 'Error loading...',
        'liquidity': 'Error loading...',
      };
    }
  }

  /// [NEW] Fetches all Pillars (100k+ DSP, 67+ PCT) for a given country.
  Future<List<UserPoints>> getPillars({String? countryCode}) async {
    Query query = _firestore
        .collection('user_points')
        .where('totalPoints', isGreaterThanOrEqualTo: 10000)
        .orderBy('totalPoints', descending: true)
        .limit(100);

    final snapshot = await query.get();

    List<UserPoints> pillars = snapshot.docs
        .map((doc) => UserPoints.fromMap(doc.data() as Map<String, dynamic>))
        .where((up) => (up.trustScore ?? 0) >= 67)
        .toList();

    return pillars;
  }

  // --- User Points ---
  Future<UserPoints?> getUserPoints(String userId) async {
    try {
      final doc = await _firestore.collection('user_points').doc(userId).get();
      if (!doc.exists) return null;
      return UserPoints.fromMap(doc.data()!);
    } catch (e) {
      throw Exception('Failed to get user points: $e');
    }
  }

  // Stream user's points balance
  Stream<UserPoints?> streamUserPoints(String userId) {
    return _firestore
        .collection('user_points')
        .doc(userId)
        .snapshots()
        .map((doc) => doc.exists ? UserPoints.fromMap(doc.data()!) : null)
        .onErrorReturn(null)
        .startWith(null);
  }

  // [NEW] Stream user transactions history
  Stream<List<PointsTransaction>> streamUserTransactions(
    String userId, {
    int limit = 100,
  }) {
    return _firestore
        .collection('points_transactions')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            return PointsTransaction.fromMap(doc.data(), doc.id);
          }).toList();
        })
        .onErrorReturn(const <PointsTransaction>[])
        .startWith(const <PointsTransaction>[]);
  }

  // Stream P2P transfer transactions between two users
  Stream<List<PointsTransaction>> streamP2PUserTransactions({
    required String currentUserId,
    required String recipientId,
    int limit = 100,
  }) {
    return _firestore
        .collection('points_transactions')
        .where('userId', isEqualTo: currentUserId)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          final all = snapshot.docs.map((doc) {
            return PointsTransaction.fromMap(doc.data(), doc.id);
          }).toList();

          return all.where((tx) {
            final meta = tx.metadata ?? {};
            final toUser = meta['toUserId'] as String?;
            final fromUser = meta['fromUserId'] as String?;
            return toUser == recipientId || fromUser == recipientId;
          }).toList();
        })
        .onErrorReturn(const <PointsTransaction>[])
        .startWith(const <PointsTransaction>[]);
  }

  // Initialize points for new user — [SECURITY] Routes through Cloud Function
  /// Counts completed transfer activity from the authoritative points ledger.
  Future<int> getCompletedEconomicTransactionCount(String userId) async {
    const economicActions = {
      'dsp_transfer_sent',
      'dsp_transfer_received',
      'fiat_transfer_sent',
      'fiat_transfer_received',
      'token_transfer_sent',
      'token_transfer_received',
      'p2p_transfer',
      'b2b_transfer',
      'c2b_transfer',
      'b2c_transfer',
    };

    final snapshot = await _firestore
        .collection('points_transactions')
        .where('userId', isEqualTo: userId)
        .limit(500)
        .get();

    return snapshot.docs.where((doc) {
      final data = doc.data();
      final action = data['action'] as String?;
      final status = data['status'] as String?;
      return economicActions.contains(action) &&
          (status == null || status == 'success');
    }).length;
  }

  // New-user points initialization routes through Cloud Functions.
  Future<void> initializeUserPoints(String userId) async {
    try {
      final callable = _functions.httpsCallable('initializeUserPoints');
      await callable.call({});
    } catch (e) {
      debugPrint('[initializeUserPoints] Cloud Function error: $e');
      rethrow;
    }
  }

  /// Evaluates 7 Proof of Humanity milestones and auto-credits 7,000 $DIASPORA token distribution if met.
  Future<Map<String, dynamic>> evaluateWelcomeBonus() async {
    try {
      final callable = _functions.httpsCallable('evaluateWelcomeBonus');
      final result = await callable.call({});
      return Map<String, dynamic>.from(result.data as Map);
    } catch (e) {
      debugPrint('[evaluateWelcomeBonus] Cloud Function error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Add points to user — [SECURITY] Routes through Cloud Function
  // All financial balance writes are now server-side only.
  Future<void> addPoints(
    String userId,
    int points,
    String action, {
    Map<String, dynamic>? metadata,
    bool skipTreasury = false,
  }) async {
    try {
      final callable = _functions.httpsCallable('awardPoints');
      await callable.call({
        'userId': userId,
        'points': points,
        'action': action,
        'metadata': metadata,
        'skipTreasury': skipTreasury,
      });
    } catch (e) {
      debugPrint('[addPoints] Cloud Function error: $e');
      rethrow;
    }
  }

  // Add staged (locked) points — [SECURITY] Routes through Cloud Function
  Future<void> addStagedPoints(
    String userId,
    int points,
    String action, {
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final callable = _functions.httpsCallable('awardPoints');
      await callable.call({
        'userId': userId,
        'points': points,
        'action': action,
        'metadata': {...?metadata, 'staged': true, 'locked': true},
        'skipTreasury': false,
      });
    } catch (e) {
      debugPrint('[addStagedPoints] Cloud Function error: $e');
      rethrow;
    }
  }

  // Deduct points from user (Penalty or Sink) — [SECURITY] Routes through Cloud Function
  Future<void> deductPoints(
    String userId,
    int points,
    String action, {
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final callable = _functions.httpsCallable('deductPoints');
      await callable.call({
        'userId': userId,
        'points': points,
        'action': action,
        'metadata': metadata,
      });
    } catch (e) {
      debugPrint('[deductPoints] Cloud Function error: $e');
      rethrow;
    }
  }

  // Update streak
  Future<void> updateStreak(String userId, int newStreak) async {
    await _firestore.collection('user_points').doc(userId).update({
      'currentStreak': newStreak,
      'lastActivityDate': DateTime.now().toUtc().toIso8601String(),
      'lastUpdated': DateTime.now().toUtc().toIso8601String(),
    });
  }

  // Increment daily message count
  Future<void> incrementDailyMessageCount(String userId) async {
    await _firestore.collection('user_points').doc(userId).update({
      'dailyMessageCount': FieldValue.increment(1),
      'lastUpdated': DateTime.now().toUtc().toIso8601String(),
    });
  }

  // [NEW] Reset ALL daily counters
  Future<void> resetDailyCounters(String userId) async {
    await _firestore.collection('user_points').doc(userId).update({
      'dailyMessageCount': 0,
      'dailyShareCount': 0,
      'dailyCommunitiesMessaged': [],
      'lastUpdated': DateTime.now().toUtc().toIso8601String(),
    });
  }

  // [NEW] Increment daily share count
  Future<void> incrementDailyShareCount(String userId) async {
    await _firestore.collection('user_points').doc(userId).update({
      'dailyShareCount': FieldValue.increment(1),
      'lastUpdated': DateTime.now().toUtc().toIso8601String(),
    });
  }

  // [NEW] Mark community as messaged for today
  Future<void> markCommunityAsMessaged(
    String userId,
    String communityId,
  ) async {
    await _firestore.collection('user_points').doc(userId).update({
      'dailyCommunitiesMessaged': FieldValue.arrayUnion([communityId]),
      'lastUpdated': DateTime.now().toUtc().toIso8601String(),
    });
  }

  // Generate unique referral code
  Future<String> generateReferralCode(
    String userId,
    String firstName,
    String countryCode,
  ) async {
    final response = await _functions
        .httpsCallable('getOrCreateReferralCode')
        .call<Map<String, dynamic>>({
          'firstName': firstName,
          'countryCode': countryCode,
        });
    final code = response.data['code'] as String?;
    if (code == null || code.isEmpty) {
      throw StateError('Referral service returned no code.');
    }
    return code;
  }

  // Transfer liquid on-chain tokens ($DIASPORA) via Cloud Function
  Future<void> transferAsset({
    required String fromUserId,
    required String toUserId,
    required int amount,
    required String assetType, // 'token'
  }) async {
    if (assetType == 'points') {
      throw ArgumentError(
        'DSP points cannot be transferred between users to preserve Proof of Community Trust (PCT) integrity.',
      );
    }
    try {
      final callable = _functions.httpsCallable('transferDiaspora');
      await callable.call({
        'toUserId': toUserId, // [FIX] param name match with Cloud Function
        'amount': amount,
        'assetType': assetType,
        'idempotencyKey':
            '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}',
      });
      // The function handles the logic. We just await success.
    } catch (e) {
      debugPrint('Error transferring $assetType: $e');
      rethrow;
    }
  }

  // Get user's referral code
  Future<String?> getReferralCode(String userId) async {
    try {
      // Source.server forces the SDK to go to Firestore directly instead of
      // waiting on an internally-queued request that may never resolve when
      // the index is missing or the connection is partial.
      final snapshot = await _firestore
          .collection('referral_codes')
          .where('userId', isEqualTo: userId)
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () => throw Exception('Referral code lookup timed out'),
          );

      if (snapshot.docs.isEmpty) return null;
      return snapshot.docs.first.data()['code'] as String;
    } catch (e) {
      throw Exception('Failed to get referral code: $e');
    }
  }

  /// Checks if the user has received a specific action reward within the last duration.
  Future<bool> hasReceivedRecentReward(
    String userId,
    String action,
    Duration period,
  ) async {
    final cutoff = DateTime.now().toUtc().subtract(period);

    final snapshot = await _firestore
        .collection('points_transactions')
        .where('userId', isEqualTo: userId)
        .where('action', isEqualTo: action)
        .where('timestamp', isGreaterThan: cutoff.toIso8601String())
        .limit(1)
        .get();

    return snapshot.docs.isNotEmpty;
  }

  // Get referral stats (code and usage count)
  Future<Map<String, dynamic>?> getReferralStats(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('referral_codes')
          .where('userId', isEqualTo: userId)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;
      return snapshot.docs.first.data();
    } catch (e) {
      throw Exception('Failed to get referral stats: $e');
    }
  }

  // Validate referral code and get referrer ID
  Future<String?> validateReferralCode(String code) async {
    try {
      final doc = await _firestore.collection('referral_codes').doc(code).get();
      if (!doc.exists) return null;
      return doc.data()?['userId'] as String?;
    } catch (e) {
      throw Exception('Failed to validate referral code: $e');
    }
  }

  // Complete referral signup
  Future<void> completeReferralSignup(
    String referrerId,
    String newUserId,
    String code,
  ) async {
    try {
      await _functions.httpsCallable('redeemReferralCode').call({'code': code});
    } catch (e) {
      // Fallback to awardPoints using whitelisted referral_reward action
      await addPoints(
        referrerId,
        1000,
        'referral_reward',
        metadata: {'referredUserId': newUserId, 'code': code},
      );
    }
  }

  // Manually increment referral count
  Future<void> incrementReferralCount(String code) async {
    await _firestore.collection('referral_codes').doc(code).update({
      'usedCount': FieldValue.increment(1),
    });
  }

  // Get transaction history
  Future<List<PointsTransaction>> getTransactionHistory(
    String userId, {
    int limit = 50,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('points_transactions')
          .where('userId', isEqualTo: userId)
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => PointsTransaction.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      throw Exception('Failed to get transaction history: $e');
    }
  }

  // Stream transaction history
  Stream<List<PointsTransaction>> streamTransactionHistory(
    String userId, {
    int limit = 50,
  }) {
    return _firestore
        .collection('points_transactions')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => PointsTransaction.fromMap(doc.data(), doc.id))
              .toList();
        })
        .onErrorReturn(const <PointsTransaction>[])
        .startWith(const <PointsTransaction>[]);
  }

  // Award points for sending a message — [SECURITY] Routes through Cloud Function
  Future<void> awardMessagePoint(
    String userId,
    int points, {
    int multiplier = 1,
  }) async {
    try {
      final callable = _functions.httpsCallable('awardMessagePoints');
      await callable.call({'points': points, 'multiplier': multiplier});
    } catch (e) {
      debugPrint('[awardMessagePoint] Cloud Function error: $e');
      rethrow;
    }
  }

  // Award exploration points unique per action — [SECURITY] Routes through Cloud Function
  Future<void> awardExplorationPoints({
    required String userId,
    required String actionId,
    required int points,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final callable = _functions.httpsCallable('awardExplorationPoints');
      await callable.call({
        'actionId': actionId,
        'points': points,
        'metadata': metadata,
      });
    } catch (e) {
      debugPrint('[awardExplorationPoints] Cloud Function error: $e');
      rethrow;
    }
  }

  // Award points for sharing content — [SECURITY] Routes through Cloud Function
  Future<bool> awardSharePoints(
    String userId,
    int points,
    String contentType,
  ) async {
    try {
      final callable = _functions.httpsCallable('awardSharePoints');
      final result = await callable.call({
        'points': points,
        'contentType': contentType,
      });
      return result.data['rewarded'] == true;
    } catch (e) {
      debugPrint('[awardSharePoints] Cloud Function error: $e');
      return false;
    }
  }

  /// Updates the PCT score in the user_points collection.
  Future<void> updateTrustScore(String userId, double score) =>
      Future<void>.error(
        UnsupportedError('Trust projections are server-owned.'),
      );

  /// Calculates and updates the average PCT score of ALL users in a country.
  Future<void> updateCommunityOverallAveragePoCT(String countryCode) =>
      Future<void>.error(
        UnsupportedError('Community trust aggregates are server-owned.'),
      );

  /// Calculates and updates the average PCT score of ALL users in a continent.
  Future<void> updateContinentOverallAveragePoCT(String continentCode) =>
      Future<void>.error(
        UnsupportedError('Continent trust aggregates are server-owned.'),
      );

  /// Calculates and updates the global average PCT score.
  Future<void> updateGlobalOverallAveragePoCT() => Future<void>.error(
    UnsupportedError('Global trust aggregates are server-owned.'),
  );

  // [NEW] Increment Verified Count (for Trust/Milestones)
  Future<void> incrementVerifiedCount(String userId) async {
    await _firestore.collection('user_points').doc(userId).update({
      'verifiedCount': FieldValue.increment(1),
      'lastUpdated': DateTime.now().toUtc().toIso8601String(),
    });
  }

  // [NEW] Increment Family Connection Count
  Future<void> incrementFamilyConnectionCount(String userId) async {
    await _firestore.collection('user_points').doc(userId).update({
      'familyConnectionCount': FieldValue.increment(1),
      'lastUpdated': DateTime.now().toUtc().toIso8601String(),
    });
  }

  // [NEW] Increment QR Connection Count
  Future<void> incrementQrConnectionCount(String userId) async {
    await _firestore.collection('user_points').doc(userId).update({
      'qrConnectionCount': FieldValue.increment(1),
      'lastUpdated': DateTime.now().toUtc().toIso8601String(),
    });
  }

  // [NEW] Mark an exploration action (milestone) as completed
  Future<void> markExplorationActionCompleted(
    String userId,
    String actionId,
  ) async {
    await _firestore.collection('user_points').doc(userId).update({
      'completedExplorationActions': FieldValue.arrayUnion([actionId]),
      'lastUpdated': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Check if user has received a specific reward for a target
  Future<bool> hasReceivedRewardForTarget(
    String userId,
    String action,
    String targetId,
  ) async {
    final query = await _firestore
        .collection('points_transactions')
        .where('userId', isEqualTo: userId)
        .where('action', isEqualTo: action)
        .where('metadata.targetId', isEqualTo: targetId)
        .limit(1)
        .get();

    return query.docs.isNotEmpty;
  }

  /// Records a check-in and returns true if it's the first one of the day.
  Future<bool> recordDailyCheckIn(String userId) async {
    final userPointsRef = _firestore.collection('user_points').doc(userId);
    final doc = await userPointsRef.get();
    if (!doc.exists) return false;

    final data = doc.data()!;
    final lastCheckIn = _parseDateTime(data['lastCheckInDate']);
    final now = DateTime.now();

    if (lastCheckIn == null ||
        lastCheckIn.year != now.year ||
        lastCheckIn.month != now.month ||
        lastCheckIn.day != now.day) {
      await userPointsRef.update({
        'lastCheckInDate': now.toUtc().toIso8601String(),
        'lastUpdated': now.toUtc().toIso8601String(),
      });
      return true;
    }
    return false;
  }

  /// Retrieves the last peer visit reward timestamp between a host and a visitor.
  Future<DateTime?> getLastPeerVisitTime({
    required String hostUserId,
    required String visitorUserId,
  }) async {
    final pairId = '${hostUserId}_$visitorUserId';
    final reversePairId = '${visitorUserId}_$hostUserId';

    final doc = await _firestore.collection('peer_visits').doc(pairId).get();
    if (doc.exists && doc.data() != null) {
      final ts = doc.data()!['lastVisitTimestamp'];
      return _parseDateTime(ts);
    }

    final reverseDoc = await _firestore
        .collection('peer_visits')
        .doc(reversePairId)
        .get();
    if (reverseDoc.exists && reverseDoc.data() != null) {
      final ts = reverseDoc.data()!['lastVisitTimestamp'];
      return _parseDateTime(ts);
    }

    return null;
  }

  /// Records a peer visit timestamp between a host and a visitor.
  Future<void> recordPeerVisit({
    required String hostUserId,
    required String visitorUserId,
    String? locationAddress,
  }) async {
    final pairId = '${hostUserId}_$visitorUserId';
    final now = DateTime.now().toUtc().toIso8601String();

    await _firestore.collection('peer_visits').doc(pairId).set({
      'hostUserId': hostUserId,
      'visitorUserId': visitorUserId,
      'locationAddress': locationAddress,
      'lastVisitTimestamp': now,
      'visitCount': FieldValue.increment(1),
    }, SetOptions(merge: true));
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
