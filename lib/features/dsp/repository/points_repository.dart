import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/dsp/models/user_points.dart';
import 'package:diaspora_nearby/features/dsp/models/points_transaction.dart';
import 'package:diaspora_nearby/features/dsp/models/corridor_model.dart';
import 'package:diaspora_nearby/core/data/countries.dart'
    hide getContinentByCountryCode;
import 'package:diaspora_nearby/core/utils/location_utils.dart';

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
        });
  }

  /// Streams points for a specific community.
  Stream<int> streamCommunityPoints(String communityId) {
    return _firestore
        .collection('communities')
        .doc(communityId)
        .snapshots()
        .map((doc) => doc.data()?['points'] as int? ?? 0);
  }

  /// Streams system treasury data.
  Stream<Map<String, dynamic>> streamSystemTreasury() {
    return _firestore
        .collection('system_stats')
        .doc('treasury')
        .snapshots()
        .map((doc) => doc.data() ?? {});
  }

  /// Streams the total internal GDP from system stats.
  Stream<int> streamInternalGdp() {
    return _firestore
        .collection('system_stats')
        .doc('treasury')
        .snapshots()
        .map((doc) => doc.data()?['totalInternalGdp'] as int? ?? 0);
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
        .map((doc) =>
            (doc.data()?['totalFiatGdpUsd'] as num?)?.toDouble() ?? 0.0);
  }

  /// Records a completed real-economy transaction's fiat value as GDP output.
  ///
  /// [amountUsd] — the transaction's value already converted to USD.
  /// [activityType] — e.g. 'marketplace_purchase', 'flight_booking', etc.
  /// [metadata] — optional extra context (listing id, user ids, etc.).
  Future<void> recordFiatGdp(
    double amountUsd,
    String activityType, {
    Map<String, dynamic>? metadata,
  }) async {
    if (amountUsd <= 0) return;

    final batch = _firestore.batch();

    // Increment global fiat GDP counter
    final treasuryRef = _firestore.collection('system_stats').doc('treasury');
    batch.set(
      treasuryRef,
      {
        'totalFiatGdpUsd': FieldValue.increment(amountUsd),
        'lastFiatGdpUpdate': DateTime.now().toUtc().toIso8601String(),
      },
      SetOptions(merge: true),
    );

    // Log individual GDP transaction for audit trail
    final gdpTxRef = _firestore.collection('gdp_transactions').doc();
    batch.set(gdpTxRef, {
      'id': gdpTxRef.id,
      'amountUsd': amountUsd,
      'activityType': activityType,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      ...?metadata,
    });

    await batch.commit();
  }

  /// Streams all bilateral corridors.
  Stream<List<Corridor>> streamCorridors() {
    return _firestore
        .collection('corridors')
        .orderBy('cumulativeGdp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Corridor.fromJson(doc.data()))
            .toList());
  }

  // --- Global Supply Tracker ---

  /// Helper to strictly increment the Global Supply Counter.
  void _incrementGlobalSupplyBatch(WriteBatch batch, int amount) {
    if (amount <= 0) return;

    // 7+3 Expansion Model Logic:
    // User: 100% (Base)
    // ---------------------------
    // Community Tribute: 70% (7 slots * 10%)
    // Founders: 10%
    // Investors: 10%
    // Fixed Burn: 10%
    // ---------------------------
    // Total Expansion Factor: 2.0x (1:1 Match)

    final int totalMinted = (amount * 2.0).round();

    final supplyRef = _firestore.collection('system_stats').doc('dsp_supply');
    batch.set(supplyRef, {
      'totalMinted': FieldValue.increment(totalMinted),
      'lastUpdated': DateTime.now().toUtc().toIso8601String(),
    }, SetOptions(merge: true));
  }

  void _incrementGlobalSupplyTx(Transaction transaction, int amount) {
    if (amount <= 0) return;

    // 7+3 Expansion Model Logic:
    // User: 100% (Base)
    // ---------------------------
    // Community Tribute: 70% (7 slots * 10%)
    // Founders: 10%
    // Investors: 10%
    // Fixed Burn: 10%
    // ---------------------------
    // Total Expansion Factor: 2.0x (1:1 Match)

    final int totalMinted = (amount * 2.0).round();

    final supplyRef = _firestore.collection('system_stats').doc('dsp_supply');
    transaction.set(supplyRef, {
      'totalMinted': FieldValue.increment(totalMinted),
      'lastUpdated': DateTime.now().toUtc().toIso8601String(),
    }, SetOptions(merge: true));
  }

  /// Internal helper to distribute points across all treasuries
  /// Implements the 10-slot community distribution + system treasuries.
  Future<void> _distributeTreasuryPoints(
    WriteBatch batch,
    String userId,
    int amount,
  ) async {
    try {
      if (amount <= 0) return;

      final int unit = (amount * 0.1).round();
      if (unit <= 0 && amount > 0) {
        return; // Ignore micro-earnings for treasury if they round to 0
      }

      // 1. Identify 7 slots for the user (Global + 3 Home + 3 Host)
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) return;

      final userData = userDoc.data();
      final List<dynamic> memberships = userData?['communityMemberships'] ?? [];

      // 2. Identify 7 Community Slots (Tributes)
      // If a slot is missing (e.g. no city), it defaults to 'global_community'.
      // This ensures 70% is ALWAYS distributed to community treasuries.
      final Map<String, int> communityMultipliers = {};
      void addToSlot(String? id) {
        final effectiveId = (id == null || id.isEmpty)
            ? 'global_community'
            : id;
        communityMultipliers[effectiveId] =
            (communityMultipliers[effectiveId] ?? 0) + 1;
      }

      // Home Hierarchy
      final homeContinent = memberships.firstWhere(
        (id) => id.toString().startsWith('home_continent_'),
        orElse: () => '',
      );
      final homeCountry = memberships.firstWhere(
        (id) => id.toString().startsWith('home_country_'),
        orElse: () => '',
      );
      final homeCity = memberships.firstWhere(
        (id) => id.toString().startsWith('home_city_'),
        orElse: () => '',
      );

      // Host Hierarchy
      final hostContinent = memberships.firstWhere(
        (id) => id.toString().startsWith('host_continent_'),
        orElse: () => '',
      );
      final hostCountry = memberships.firstWhere(
        (id) => id.toString().startsWith('host_country_'),
        orElse: () => '',
      );
      final hostCity = memberships.firstWhere(
        (id) => id.toString().startsWith('host_city_'),
        orElse: () => '',
      );

      // Fill 7 Slots
      addToSlot('global_community'); // Slot 1: Global
      addToSlot(homeContinent.toString());
      addToSlot(homeCountry.toString());
      addToSlot(homeCity.toString());
      addToSlot(hostContinent.toString());
      addToSlot(hostCountry.toString());
      addToSlot(hostCity.toString());

      // 3. Distribute to Communities
      communityMultipliers.forEach((commId, multiplier) {
        final int commUnit = unit * multiplier;
        final int commBasis = amount * multiplier;

        final tRef = _firestore
            .collection('communities')
            .doc(commId)
            .collection('treasury')
            .doc('current');
        batch.set(tRef, {
          'cumulativeEarnings': FieldValue.increment(commBasis + commUnit),
          'memberPoints': FieldValue.increment(commBasis),
          'points': FieldValue.increment(commUnit),
          'awardedBalance': FieldValue.increment(commUnit.toDouble()),
          'updatedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
        }, SetOptions(merge: true));

        // Sync to Governance
        final govId = commId == 'global_community'
            ? 'global_community'
            : (commId.contains('_')
                  ? commId.substring(commId.indexOf('_') + 1)
                  : commId);
        batch.set(_firestore.collection('governance').doc(govId), {
          'treasuryBalance': FieldValue.increment(commUnit.toDouble()),
          'updatedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
        }, SetOptions(merge: true));

        // Mirror to top-level community document
        batch.set(
          _firestore.collection('communities').doc(commId),
          {
            'cumulativeEarnings': FieldValue.increment(commBasis + commUnit),
            'memberPoints': FieldValue.increment(commBasis),
            'points': FieldValue.increment(commUnit),
            'awardedBalance': FieldValue.increment(commUnit.toDouble()),
            'updatedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
          },
          SetOptions(merge: true),
        );
      });

      // 4. System Treasuries (Founders + Investors + Fixed Burn)
      // Total 10 units: 1 F + 1 I + 1 B + 7 C. NO unassigned slots.
      final int investorsPoints = unit;
      final int totalBurnAmount = unit; // Fixed 10%

      final treasuryRef = _firestore.collection('system_stats').doc('treasury');
      batch.set(treasuryRef, {
        'foundersPoints': FieldValue.increment(unit),
        'investorsPoints': FieldValue.increment(investorsPoints),
        'burnedPoints': FieldValue.increment(totalBurnAmount),
        'lastUpdated': DateTime.now().toUtc().toIso8601String(),
      }, SetOptions(merge: true));

      // Sync Founders Treasury to Governance
      final foundersRef = _firestore.collection('governance').doc('founders');
      batch.set(foundersRef, {
        'id': 'founders',
        'name': 'Founders & Core Team',
        'type': 'system',
        'treasuryBalance': FieldValue.increment(unit),
        'updatedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
      }, SetOptions(merge: true));

      // Sync Investors Treasury to Governance
      final investorsRef = _firestore.collection('governance').doc('investors');
      batch.set(investorsRef, {
        'id': 'investors',
        'name': 'Investors & Partners',
        'type': 'system',
        'treasuryBalance': FieldValue.increment(investorsPoints),
        'updatedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
      }, SetOptions(merge: true));

      // Sync System Treasuries to Governance
      // Sync System Treasuries to Governance
      // Ecosystem removed from active distribution, but we keep the doc or stop updating it.
      // For cleanup, we just stop updating it here since it receives 0 flux.

      // Liquidity removed from active distribution

      batch.set(
        _firestore.collection('governance').doc('founders'),
        {
          'treasuryBalance': FieldValue.increment(unit.toDouble()),
          'title': 'Founders Treasury',
          'updatedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      // No-log error

    }
  }

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
      print('Error fetching global supply: $e');
      return 0;
    }
  }

  /// Force sync treasury balances based on total global supply.
  Future<void> syncTreasuryBalances() async {
    try {
      final userPointsSnap = await _firestore.collection('user_points').get();
      final usersSnap = await _firestore.collection('users').get();

      final Map<String, Map<String, dynamic>> userProfiles = {};
      for (var doc in usersSnap.docs) {
        userProfiles[doc.id] = doc.data();
      }

      final Map<String, int> communityPointsMap = {};
      final Map<String, int> communityBasisMap = {};
      final Map<String, int> communityMemberPointsMap = {};
      final Map<String, List<double>> communityPoCTs = {};

      int totalUserPoints = 0;
      int totalFoundersPoints = 0;
      int totalInvestorsPoints = 0;
      int totalBurnedPoints = 0;

      for (var doc in userPointsSnap.docs) {
        final userId = doc.id;
        final pointsData = doc.data();
        final int userPoints = pointsData['totalPoints'] as int? ?? 0;
        final double trustScore = (pointsData['trustScore'] as num? ?? 0.0)
            .toDouble();

        if (userPoints <= 0) continue;

        totalUserPoints += userPoints;

        final int unit = (userPoints * 0.10).round();

        totalFoundersPoints += unit; // Slot 0: Founders (10%)
        totalInvestorsPoints += unit; // Slot 1: Investors (10%)

        // Community Hierarchy: 7 Slots (Global + 3 Home + 3 Host)
        // Missing slots default to Global.
        final List<String> userSlots = [];
        final userMemberships =
            (userProfiles[userId]?['communityMemberships'] as List? ?? []);

        void addUserSlot(String? id) {
          final effectiveId = (id == null || id.isEmpty)
              ? 'global_community'
              : id;
          userSlots.add(effectiveId);
        }

        addUserSlot('global_community');
        addUserSlot(
          userMemberships
              .firstWhere(
                (id) => id.toString().startsWith('home_continent_'),
                orElse: () => '',
              )
              ?.toString(),
        );
        addUserSlot(
          userMemberships
              .firstWhere(
                (id) => id.toString().startsWith('home_country_'),
                orElse: () => '',
              )
              ?.toString(),
        );
        addUserSlot(
          userMemberships
              .firstWhere(
                (id) => id.toString().startsWith('home_city_'),
                orElse: () => '',
              )
              ?.toString(),
        );
        addUserSlot(
          userMemberships
              .firstWhere(
                (id) => id.toString().startsWith('host_continent_'),
                orElse: () => '',
              )
              ?.toString(),
        );
        addUserSlot(
          userMemberships
              .firstWhere(
                (id) => id.toString().startsWith('host_country_'),
                orElse: () => '',
              )
              ?.toString(),
        );
        addUserSlot(
          userMemberships
              .firstWhere(
                (id) => id.toString().startsWith('host_city_'),
                orElse: () => '',
              )
              ?.toString(),
        );

        totalBurnedPoints += unit; // Slot 3: Fixed Burn (10%)
        // Total matched expansion is always 10 units (Founders + Investors + Burn + 7 Community)

        for (final cid in userSlots) {
          communityPointsMap[cid] = (communityPointsMap[cid] ?? 0) + unit;
          // Basis Calculation: Pro-rated
          communityBasisMap[cid] =
              (communityBasisMap[cid] ?? 0) + userPoints + unit;
          communityMemberPointsMap[cid] =
              (communityMemberPointsMap[cid] ?? 0) + userPoints;
          communityPoCTs.putIfAbsent(cid, () => []).add(trustScore);
        }
      }

      final batch = _firestore.batch();

      batch.set(
        _firestore.collection('system_stats').doc('treasury'),
        {
          'foundersPoints': totalFoundersPoints,
          'investorsPoints': totalInvestorsPoints,
          'burnedPoints': totalBurnedPoints,
          'lastUpdated': DateTime.now().toUtc().toIso8601String(),
        },
        SetOptions(merge: true),
      );

      batch.set(
        _firestore.collection('governance').doc('founders'),
        {
          'treasuryBalance': totalFoundersPoints.toDouble(),
          'updatedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
        },
        SetOptions(merge: true),
      );

      batch.set(
        _firestore.collection('governance').doc('investors'),
        {
          'treasuryBalance': totalInvestorsPoints.toDouble(),
          'updatedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
        },
        SetOptions(merge: true),
      );

      for (var commId in communityPointsMap.keys) {
        final treasuryRef = _firestore
            .collection('communities')
            .doc(commId)
            .collection('treasury')
            .doc('current');
        final pocts = communityPoCTs[commId] ?? [];
        double avgPoCT = pocts.isEmpty
            ? 0
            : pocts.reduce((a, b) => a + b) / pocts.length;

        batch.set(treasuryRef, {
          'points': communityPointsMap[commId],
          'cumulativeEarnings': communityBasisMap[commId],
          'memberPoints': communityMemberPointsMap[commId],
          'awardedBalance': communityPointsMap[commId],
          'averagePoCT': avgPoCT,
          'updatedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
        }, SetOptions(merge: true));

        final govId = commId == 'global_community'
            ? 'global_community'
            : (commId.contains('_')
                  ? commId.substring(commId.indexOf('_') + 1)
                  : commId);
        batch.set(_firestore.collection('governance').doc(govId), {
          'treasuryBalance': (communityPointsMap[commId] ?? 0).toDouble(),
          'updatedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
        }, SetOptions(merge: true));

        // [FIX] Mirror data to top-level community document for list view efficiency
        batch.set(
          _firestore.collection('communities').doc(commId),
          {
            'points': communityPointsMap[commId],
            'cumulativeEarnings': communityBasisMap[commId],
            'memberPoints': communityMemberPointsMap[commId],
            'awardedBalance': (communityPointsMap[commId] ?? 0).toDouble(),
            'averagePoCT': avgPoCT,
            'updatedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
          },
          SetOptions(merge: true),
        );
      }

      batch.set(
        _firestore.collection('system_stats').doc('dsp_supply'),
        {
          'totalMinted': (totalUserPoints * 2.0).round(),
          'lastUpdated': DateTime.now().toUtc().toIso8601String(),
        },
        SetOptions(merge: true),
      );

      await batch.commit();
    } catch (e) {
      // No-log error

      rethrow;
    }
  }

  // [NEW] Stream Global Supply for Real-time Stats
  Stream<int> streamGlobalSupply() {
    return _firestore
        .collection('system_stats')
        .doc('dsp_supply')
        .snapshots()
        .map((doc) => doc.data()?['totalMinted'] as int? ?? 0);
  }

  // [NEW] Stream global member count for Community Epoch logic
  Stream<int> streamGlobalMemberCount() {
    return _firestore
        .collection('communities')
        .doc('global_community')
        .snapshots()
        .map((doc) {
          return (doc.data()?['memberCount'] as int?) ?? 0;
        });
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
      print('Error updating wallet address: $e');
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
      print('Error fetching treasury wallets: $e');
      return {
        'ecosystem': 'Error loading...',
        'founders': 'Error loading...',
        'liquidity': 'Error loading...',
      };
    }
  }

  /// [NEW] Fetches all Pillars (100k+ DSP, 67+ PoCT) for a given country.
  Future<List<UserPoints>> getPillars({String? countryCode}) async {
    Query query = _firestore
        .collection('user_points')
        .where('totalPoints', isGreaterThanOrEqualTo: 10000);

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
        .map((doc) => doc.exists ? UserPoints.fromMap(doc.data()!) : null);
  }

  // [NEW] Stream user transactions history
  Stream<List<PointsTransaction>> streamUserTransactions(String userId) {
    return _firestore
        .collection('points_transactions')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .limit(20)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            return PointsTransaction.fromMap(doc.data(), doc.id);
          }).toList();
        });
  }

  // Initialize points for new user
  Future<void> initializeUserPoints(String userId) async {
    final doc = await _firestore.collection('user_points').doc(userId).get();
    if (doc.exists) {
      // No-log: Already initialized

      return;
    }

    final userDoc = await _firestore.collection('users').doc(userId).get();
    final countryCode = userDoc.data()?['homeCountryCode'] as String?;

    final batch = _firestore.batch();

    final userPoints = UserPoints(
      userId: userId,
      totalPoints: 1000,
      availablePoints: 1000,
      currentStreak: 0,
      lastActivityDate: null,
      dailyMessageCount: 0,
      lastUpdated: DateTime.now().toUtc(),
      completedExplorationActions: [],
      signupDate: DateTime.now().toUtc(),
      dailyShareCount: 0,
      dailyCommunitiesMessaged: [],
      homeCountryCode: countryCode,
      verifiedCount: 0,
      familyConnectionCount: 0,
      qrConnectionCount: 0,
      lifetimeEarnings: const {'welcome_bonus': 1000},
    );

    final userPointsRef = _firestore.collection('user_points').doc(userId);
    batch.set(userPointsRef, userPoints.toMap());

    final transactionRef = _firestore.collection('points_transactions').doc();
    final transaction = PointsTransaction(
      id: transactionRef.id,
      userId: userId,
      type: 'earn',
      action: 'welcome_bonus',
      points: 1000,
      timestamp: DateTime.now().toUtc(),
      metadata: const {'description': 'Welcome to Diaspora!'},
    );
    batch.set(transactionRef, transaction.toMap());

    await batch.commit();
  }

  // Add points to user
  Future<void> addPoints(
    String userId,
    int points,
    String action, {
    Map<String, dynamic>? metadata,
  }) async {
    final batch = _firestore.batch();

    final userPointsRef = _firestore.collection('user_points').doc(userId);
    batch.set(userPointsRef, {
      'totalPoints': FieldValue.increment(points),
      'availablePoints': FieldValue.increment(points),
      'lastUpdated': DateTime.now().toUtc().toIso8601String(),
      'lifetimeEarnings.$action': FieldValue.increment(points),
    }, SetOptions(merge: true));

    final transactionRef = _firestore.collection('points_transactions').doc();
    final transaction = PointsTransaction(
      id: transactionRef.id,
      userId: userId,
      type: 'earn',
      action: action,
      points: points,
      timestamp: DateTime.now().toUtc(),
      metadata: metadata,
    );
    batch.set(transactionRef, transaction.toMap());

    final userDoc = await _firestore.collection('users').doc(userId).get();
    final countryCode = userDoc.data()?['homeCountryCode'] as String?;

    if (countryCode != null) {
      batch.update(userPointsRef, {'homeCountryCode': countryCode});
    }

    await _distributeTreasuryPoints(batch, userId, points);
    // 1:1 Expansion: User Points + Treasury Points
    _incrementGlobalSupplyBatch(batch, points);

    await batch.commit();
  }

  Future<void> addStagedPoints(
    String userId,
    int points,
    String action, {
    Map<String, dynamic>? metadata,
  }) async {
    final batch = _firestore.batch();

    final userPointsRef = _firestore.collection('user_points').doc(userId);
    batch.set(userPointsRef, {
      'totalPoints': FieldValue.increment(points),
      'lastUpdated': DateTime.now().toUtc().toIso8601String(),
      'lifetimeEarnings.$action': FieldValue.increment(points),
    }, SetOptions(merge: true));

    final transactionRef = _firestore.collection('points_transactions').doc();
    final transaction = PointsTransaction(
      id: transactionRef.id,
      userId: userId,
      type: 'earn',
      action: action,
      points: points,
      timestamp: DateTime.now().toUtc(),
      metadata: {...?metadata, 'staged': true, 'locked': true},
    );
    batch.set(transactionRef, transaction.toMap());

    await _distributeTreasuryPoints(batch, userId, points);
    // 1:1 Expansion. Helper internally applies 2x expansion factor.
    _incrementGlobalSupplyBatch(batch, points);

    await batch.commit();
  }

  // Deduct points from user (Penalty or Sink)
  Future<void> deductPoints(
    String userId,
    int points,
    String action, {
    Map<String, dynamic>? metadata,
  }) async {
    final batch = _firestore.batch();

    final userPointsRef = _firestore.collection('user_points').doc(userId);
    batch.set(userPointsRef, {
      'availablePoints': FieldValue.increment(-points),
      'lastUpdated': DateTime.now().toUtc().toIso8601String(),
    }, SetOptions(merge: true));

    final transactionRef = _firestore.collection('points_transactions').doc();
    final transaction = PointsTransaction(
      id: transactionRef.id,
      userId: userId,
      type: 'spend',
      action: action,
      points: -points,
      timestamp: DateTime.now().toUtc(),
      metadata: metadata,
    );
    batch.set(transactionRef, transaction.toMap());

    // [VALUE SINK] Record as Burned Utility and Internal GDP
    final treasuryRef = _firestore.collection('system_stats').doc('treasury');
    batch.set(treasuryRef, {
      'totalInternalGdp': FieldValue.increment(points),
      'totalBurnedUtility': FieldValue.increment(points),
      'lastUpdated': DateTime.now().toUtc().toIso8601String(),
    }, SetOptions(merge: true));

    await batch.commit();
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
    final random = Random();
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

    String generateRandomId() {
      return List.generate(
        4,
        (_) => chars[random.nextInt(chars.length)],
      ).join();
    }

    String code;
    bool isUnique = false;
    int attempts = 0;

    do {
      final randomId = generateRandomId();
      code =
          '${firstName.toUpperCase()}-${countryCode.toUpperCase()}-$randomId';

      final existing = await _firestore
          .collection('referral_codes')
          .doc(code)
          .get();
      isUnique = !existing.exists;
      attempts++;
    } while (!isUnique && attempts < 10);

    if (!isUnique) throw Exception('Failed to generate unique referral code');

    // Persist the referral code to Firestore
    await _firestore.collection('referral_codes').doc(code).set({
      'code': code,
      'userId': userId,
      'firstName': firstName,
      'countryCode': countryCode.toUpperCase(),
      'usedCount': 0,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });

    return code;
  }

  // Transfer asset (Points or Tokens) via Cloud Function
  Future<void> transferAsset({
    required String fromUserId,
    required String toUserId,
    required int amount,
    required String assetType, // 'points' | 'token'
  }) async {
    try {
      final callable = _functions.httpsCallable('transferDiaspora');
      await callable.call({
        'toUserId': toUserId, // [FIX] param name match with Cloud Function
        'amount': amount,
        'assetType': assetType,
      });
      // The function handles the logic. We just await success.
    } catch (e) {
      print('Error transferring $assetType: $e');
      rethrow;
    }
  }

  // Get user's referral code
  Future<String?> getReferralCode(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('referral_codes')
          .where('userId', isEqualTo: userId)
          .limit(1)
          .get();

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
    await addPoints(
      referrerId,
      1000,
      'referral_signup',
      metadata: {'referredUserId': newUserId, 'code': code},
    );
    await addPoints(
      newUserId,
      1000,
      'referral_signup',
      metadata: {'referrerId': referrerId, 'code': code},
    );

    await _firestore.collection('referral_codes').doc(code).update({
      'usedCount': FieldValue.increment(1),
    });
    // Note: supply is already incremented inside each addPoints() call above.
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
        });
  }

  // Award points for sending a message
  Future<void> awardMessagePoint(
    String userId,
    int points, {
    int multiplier = 1,
  }) async {
    final now = DateTime.now().toUtc();
    final userPointsRef = _firestore.collection('user_points').doc(userId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(userPointsRef);
      if (!snapshot.exists) return;

      final data = snapshot.data()!;
      final lastUpdatedStr = data['lastUpdated'] as String?;
      final lastUpdated = lastUpdatedStr != null
          ? DateTime.parse(lastUpdatedStr)
          : null;

      int dailyCount = data['dailyMessageCount'] as int? ?? 0;
      if (lastUpdated == null || lastUpdated.day != now.day) dailyCount = 0;

      if (dailyCount >= 100) return;

      final pointsToAward = points * multiplier;
      transaction.update(userPointsRef, {
        'totalPoints': FieldValue.increment(pointsToAward),
        'availablePoints': FieldValue.increment(pointsToAward),
        'dailyMessageCount': dailyCount + 1,
        'lastUpdated': now.toIso8601String(),
        'lifetimeEarnings.daily_message': FieldValue.increment(
          pointsToAward,
        ), // [FIX] Track lifetime earnings
      });

      final transactionRef = _firestore.collection('points_transactions').doc();
      transaction.set(
        transactionRef,
        PointsTransaction(
          id: transactionRef.id,
          userId: userId,
          type: 'earn',
          action: 'message_sent',
          points: pointsToAward,
          timestamp: now,
        ).toMap(),
      );

      // Allocate Treasuries (Multi-community split + Eco/Liq/Founders)
      // 1:1 Expansion: 10 slots * 10% = 100% Match
      final int tenPercentShare = (pointsToAward * 0.1).round();
      if (tenPercentShare > 0) {
        final userRef = _firestore.collection('users').doc(userId);
        final userSnap = await transaction.get(userRef);
        int homeOverflow = 0;
        int hostOverflow = 0;

        if (userSnap.exists) {
          final List<dynamic> memberships =
              userSnap.data()?['communityMemberships'] ?? [];
          final homePool = memberships
              .where((id) => id.toString().startsWith('home_'))
              .toList();
          final hostPool = memberships
              .where(
                (id) =>
                    id.toString().startsWith('host_') ||
                    id.toString().startsWith('past_'),
              )
              .toList();

          if (homePool.isNotEmpty) {
            final int pPer = (tenPercentShare / homePool.length).round();
            int rem = tenPercentShare - (pPer * homePool.length);
            for (int i = 0; i < homePool.length; i++) {
              final String cid = homePool[i].toString();
              final int cPoints = pPer + (i == 0 ? rem : 0);
              final tRef = _firestore
                  .collection('communities')
                  .doc(cid)
                  .collection('treasury')
                  .doc('current');
              transaction.set(tRef, {
                'cumulativeEarnings': FieldValue.increment(pointsToAward * 2),
                'memberPoints': FieldValue.increment(pointsToAward),
                'points': FieldValue.increment(cPoints),
                'awardedBalance': FieldValue.increment(cPoints),
                'updatedAt': now.millisecondsSinceEpoch,
              }, SetOptions(merge: true));
            }
          } else {
            homeOverflow = tenPercentShare;
          }

          if (hostPool.isNotEmpty) {
            final int pPer = (tenPercentShare / hostPool.length).round();
            int rem = tenPercentShare - (pPer * hostPool.length);
            for (int i = 0; i < hostPool.length; i++) {
              final String cid = hostPool[i].toString();
              final int cPoints = pPer + (i == 0 ? rem : 0);
              final tRef = _firestore
                  .collection('communities')
                  .doc(cid)
                  .collection('treasury')
                  .doc('current');
              transaction.set(tRef, {
                'cumulativeEarnings': FieldValue.increment(pointsToAward * 2),
                'memberPoints': FieldValue.increment(pointsToAward),
                'points': FieldValue.increment(cPoints),
                'awardedBalance': FieldValue.increment(cPoints),
                'updatedAt': now.millisecondsSinceEpoch,
              }, SetOptions(merge: true));
            }
          } else {
            hostOverflow = tenPercentShare;
          }
        } else {
          // If no user profile found, all community shares go to Ecosystem
          homeOverflow = tenPercentShare;
          hostOverflow = tenPercentShare;
        }

        final sysTreasuryRef = _firestore
            .collection('system_stats')
            .doc('treasury');
        transaction.set(sysTreasuryRef, {
          'ecosystemPoints': FieldValue.increment(
            tenPercentShare + homeOverflow + hostOverflow,
          ),
          'liquidityPoints': FieldValue.increment(tenPercentShare),
          'foundersPoints': FieldValue.increment(tenPercentShare),
          'lastUpdated': now.toIso8601String(),
        }, SetOptions(merge: true));
      }

      // 1:1 Expansion. Helper internally applies 2x expansion factor.
      _incrementGlobalSupplyTx(transaction, pointsToAward);
    });
  }

  // Award exploration points unique per action
  Future<void> awardExplorationPoints({
    required String userId,
    required String actionId,
    required int points,
    Map<String, dynamic>? metadata,
  }) async {
    final userPointsRef = _firestore.collection('user_points').doc(userId);
    final userRef = _firestore.collection('users').doc(userId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(userPointsRef);
      final userSnap = await transaction.get(userRef);

      if (!snapshot.exists) {
        // [SAFETY] Initialize if missing
        final newUserPoints = UserPoints(
          userId: userId,
          totalPoints: 0,
          availablePoints: 0,
          currentStreak: 0,
          lastActivityDate: null,
          dailyMessageCount: 0,
          lastUpdated: DateTime.now().toUtc(),
          signupDate: DateTime.now().toUtc(),
        );
        transaction.set(userPointsRef, newUserPoints.toMap());
      } else {
        final data = snapshot.data()!;
        final completedActions = List<String>.from(
          data['completedExplorationActions'] ?? [],
        );
        if (completedActions.contains(actionId)) {
          throw Exception('Action already completed');
        }
      }

      // 1. Update User Points
      transaction.update(userPointsRef, {
        'totalPoints': FieldValue.increment(points),
        'availablePoints': FieldValue.increment(points),
        'lastUpdated': DateTime.now().toUtc().toIso8601String(),
        'completedExplorationActions': FieldValue.arrayUnion([actionId]),
        'lifetimeEarnings.exploration_reward': FieldValue.increment(
          points,
        ), // [FIX] Track lifetime earnings
      });

      // 2. Create Transaction Record
      final transactionRef = _firestore.collection('points_transactions').doc();
      transaction.set(
        transactionRef,
        PointsTransaction(
          id: transactionRef.id,
          userId: userId,
          type: 'earn',
          action: 'exploration_$actionId',
          points: points,
          timestamp: DateTime.now().toUtc(),
          metadata: metadata,
        ).toMap(),
      );

      // 3. Allocate Treasuries (1:1 Expansion: 10 slots * 10% = 100% Match)
      final int unit = (points * 0.1).round();
      final nowStr = DateTime.now().toUtc().toIso8601String();
      final nowMillis = DateTime.now().toUtc().millisecondsSinceEpoch;

      int ecosystemOverflow = 0;

      // Slot 1: Global
      final globalTRef = _firestore
          .collection('communities')
          .doc('global_community')
          .collection('treasury')
          .doc('current');
      transaction.set(globalTRef, {
        'cumulativeEarnings': FieldValue.increment(points + unit),
        'memberPoints': FieldValue.increment(points),
        'points': FieldValue.increment(unit),
        'awardedBalance': FieldValue.increment(unit),
        'updatedAt': nowMillis,
      }, SetOptions(merge: true));

      if (userSnap.exists) {
        final List<dynamic> memberships =
            userSnap.data()?['communityMemberships'] ?? [];

        // Slots 2-5: Home Hierarchy
        final homeLevels = [
          'home_continent_',
          'home_country_',
          'home_state_',
          'home_city_',
        ];
        for (final level in homeLevels) {
          final cid = memberships.firstWhere(
            (id) => id.toString().startsWith(level),
            orElse: () => null,
          );
          if (cid != null) {
            final tRef = _firestore
                .collection('communities')
                .doc(cid.toString())
                .collection('treasury')
                .doc('current');
            transaction.set(tRef, {
              'cumulativeEarnings': FieldValue.increment(points + unit),
              'memberPoints': FieldValue.increment(points),
              'points': FieldValue.increment(unit),
              'awardedBalance': FieldValue.increment(unit),
              'updatedAt': nowMillis,
            }, SetOptions(merge: true));
          } else {
            ecosystemOverflow += unit;
          }
        }

        // Slots 6-9: Host Hierarchy
        final hostLevels = [
          'host_continent_',
          'host_country_',
          'host_state_',
          'host_city_',
        ];
        for (final level in hostLevels) {
          final cid = memberships.firstWhere(
            (id) => id.toString().startsWith(level),
            orElse: () => null,
          );
          if (cid != null) {
            final tRef = _firestore
                .collection('communities')
                .doc(cid.toString())
                .collection('treasury')
                .doc('current');
            transaction.set(tRef, {
              'cumulativeEarnings': FieldValue.increment(points + unit),
              'memberPoints': FieldValue.increment(points),
              'points': FieldValue.increment(unit),
              'awardedBalance': FieldValue.increment(unit),
              'updatedAt': nowMillis,
            }, SetOptions(merge: true));
          } else {
            ecosystemOverflow += unit;
          }
        }
      } else {
        // All 8 hierarchy slots overflow
        ecosystemOverflow += (unit * 8);
      }

      // Slot 10: Founders + Ecosystem Overflow
      final sysTreasuryRef = _firestore
          .collection('system_stats')
          .doc('treasury');
      transaction.set(sysTreasuryRef, {
        'ecosystemPoints': FieldValue.increment(ecosystemOverflow),
        'foundersPoints': FieldValue.increment(unit),
        'lastUpdated': nowStr,
      }, SetOptions(merge: true));

      // 1:1 Expansion. Helper internally applies 2x expansion factor.
      _incrementGlobalSupplyTx(transaction, points);
    });
  }

  // Award points for sharing content
  Future<bool> awardSharePoints(
    String userId,
    int points,
    String contentType,
  ) async {
    final now = DateTime.now().toUtc();
    final userPointsRef = _firestore.collection('user_points').doc(userId);
    bool rewarded = false;

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(userPointsRef);
      if (!snapshot.exists) return;

      final data = snapshot.data()!;
      final lastUpdatedStr = data['lastUpdated'] as String?;
      final lastUpdated = lastUpdatedStr != null
          ? DateTime.parse(lastUpdatedStr)
          : null;

      int dailyShareCount = data['dailyShareCount'] as int? ?? 0;
      if (lastUpdated == null || lastUpdated.day != now.day) {
        dailyShareCount = 0;
      }

      if (dailyShareCount >= 12) return;

      transaction.update(userPointsRef, {
        'totalPoints': FieldValue.increment(points),
        'availablePoints': FieldValue.increment(points),
        'dailyShareCount': dailyShareCount + 1,
        'lastUpdated': now.toIso8601String(),
        'lifetimeEarnings.content_shared': FieldValue.increment(
          points,
        ), // [FIX] Track lifetime earnings
      });

      final transactionRef = _firestore.collection('points_transactions').doc();
      transaction.set(
        transactionRef,
        PointsTransaction(
          id: transactionRef.id,
          userId: userId,
          type: 'earn',
          action: 'content_shared',
          points: points,
          timestamp: now,
          metadata: {'contentType': contentType},
        ).toMap(),
      );
      _incrementGlobalSupplyTx(transaction, points);
      rewarded = true;
    });

    return rewarded;
  }

  /// Updates the PoCT score in the user_points collection.
  Future<void> updateTrustScore(String userId, double score) async {
    await _firestore.collection('user_points').doc(userId).update({
      'trustScore': score,
      'lastUpdated': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Calculates and updates the average PoCT score of ALL users in a country.
  Future<void> updateCommunityOverallAveragePoCT(String countryCode) async {
    final countryId = 'home_country_${countryCode.toLowerCase()}';
    final snapshot = await _firestore
        .collection('user_points')
        .where('homeCountryCode', isEqualTo: countryCode)
        .get();
    if (snapshot.docs.isEmpty) return;

    double totalScore = 0;
    for (var doc in snapshot.docs) {
      totalScore += (doc.data()['trustScore'] as num? ?? 0).toDouble();
    }
    final double average = totalScore / snapshot.docs.length;

    await _firestore.collection('communities').doc(countryId).update({
      'averagePoCT': average,
      'lastUpdatedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
    });
  }

  /// Calculates and updates the average PoCT score of ALL users in a continent.
  Future<void> updateContinentOverallAveragePoCT(String continentCode) async {
    final continentName = getContinentName(continentCode);
    final continentId = generateCommunityId(
      locationType: 'home',
      type: 'continent',
      continent: continentName,
    );

    final countriesSnap = await _firestore
        .collection('communities')
        .where('type', isEqualTo: 'country')
        .where('continent', isEqualTo: continentName)
        .get();

    if (countriesSnap.docs.isEmpty) return;

    double weightedSum = 0;
    int totalMembers = 0;
    for (var doc in countriesSnap.docs) {
      final data = doc.data();
      final double avg = (data['averagePoCT'] as num? ?? 0).toDouble();
      final int count = data['memberCount'] as int? ?? 0;
      weightedSum += avg * count;
      totalMembers += count;
    }

    if (totalMembers == 0) return;
    await _firestore.collection('communities').doc(continentId).update({
      'averagePoCT': weightedSum / totalMembers,
      'lastUpdatedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
    });
  }

  /// Calculates and updates the global average PoCT score.
  Future<void> updateGlobalOverallAveragePoCT() async {
    final countriesSnap = await _firestore
        .collection('communities')
        .where('type', isEqualTo: 'country')
        .get();
    if (countriesSnap.docs.isEmpty) return;

    double weightedSum = 0;
    int totalMembers = 0;
    for (var doc in countriesSnap.docs) {
      final data = doc.data();
      final double avg = (data['averagePoCT'] as num? ?? 0).toDouble();
      final int count = data['memberCount'] as int? ?? 0;
      weightedSum += avg * count;
      totalMembers += count;
    }

    if (totalMembers == 0) return;
    await _firestore.collection('communities').doc('global_community').update({
      'averagePoCT': weightedSum / totalMembers,
      'lastUpdatedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
    });
  }

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

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
