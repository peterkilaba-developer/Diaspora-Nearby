import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/epoch_service.dart';
import 'package:diaspora_nearby/features/dsp/models/user_points.dart';
import 'package:diaspora_nearby/features/dsp/models/points_transaction.dart';
import 'package:diaspora_nearby/core/data/countries.dart' hide getContinentByCountryCode;
import 'package:diaspora_nearby/core/utils/location_utils.dart';

final pointsRepositoryProvider = Provider<PointsRepository>((ref) {
  return PointsRepository(
    FirebaseFirestore.instance,
    ref.read(epochServiceProvider),
  );
});

final userPointsProvider = StreamProvider.family<UserPoints?, String>((
  ref,
  userId,
) {
  return ref.watch(pointsRepositoryProvider).streamUserPoints(userId);
});

final countryLeaderboardProvider = StreamProvider<List<Map<String, String>>>((ref) {
  return ref.watch(pointsRepositoryProvider).streamCountryLeaderboard();
});

final communityPointsProvider = StreamProvider.family<int, String>((ref, communityId) {
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

class PointsRepository {
  final FirebaseFirestore _firestore;
  final EpochService _epochService;

  PointsRepository(this._firestore, this._epochService);

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
      final List<Map<String, dynamic>> rawData = snapshot.docs.map((doc) => doc.data()).toList();
      
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
        final countryCode = (data['location'] as Map<String, dynamic>?)?['countryCode'] as String? ?? '';
        final country = getCountryByCode(countryCode);
        final rawName = data['name'] as String? ?? 'Unknown';
        final cleanName = rawName.replaceAll(' Community', '').trim();
      
        return {
          'rank': '${index + 1}',
          'name': country?.name ?? cleanName,
          'flag': country?.flag ?? '🌍',
          'balance': '${points.toString().replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]},")} DSP',
          'cumulativeEarnings': '$cumulative',
          'memberPoints': '${data['memberPoints'] ?? 0}',
          'memberCount': '${data['memberCount'] ?? 0}',
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

  // --- Global Supply Tracker ---

  /// Helper to strictly increment the Global Supply Counter.
  /// Must be called within a transaction or batch (if batch is used, passed as arg).
  /// For Batch: We can't read-then-write easily for a counter without potential race conditions 
  /// if we don't use a Transaction.
  /// However, for simplicity and performance in this specific use case, we will use FieldValue.increment
  /// on the 'system_stats/dsp_supply' doc. This is safe for counters.
  void _incrementGlobalSupplyBatch(WriteBatch batch, int amount) {
    if (amount <= 0) return;
    
    // Total minted:
    // User (50%) + System (50%)
    // System Split: Continent (10%) + Country (10%) + Plat (10%) + Liq (10%) + Founders (10%)
    // Total = User / 0.5 = amount * 2
    final int totalMinted = amount * 2;
    
    final supplyRef = _firestore.collection('system_stats').doc('dsp_supply');
    batch.set(supplyRef, {
      'totalMinted': FieldValue.increment(totalMinted),
      'lastUpdated': DateTime.now().toUtc().toIso8601String(),
    }, SetOptions(merge: true));
  }

  void _incrementGlobalSupplyTx(Transaction transaction, int amount) {
     if (amount <= 0) return;
     final int totalMinted = amount * 2;
     final supplyRef = _firestore.collection('system_stats').doc('dsp_supply');
     transaction.set(supplyRef, {
      'totalMinted': FieldValue.increment(totalMinted),
      'lastUpdated': DateTime.now().toUtc().toIso8601String(),
    }, SetOptions(merge: true));
  }

  /// [NEW] Internal helper to distribute points across all treasuries
  /// This implements the 50/10/10/10/10/10 split (User/Home/Cont/Eco/Liq/Found).
  /// amount: the points earned by the USER (the 50% share)
  /// [NEW] Internal helper to distribute points across all treasuries
  /// This implements the 50/10/10/10/10/10 split (User/Home/Cont/Eco/Liq/Found).
  /// amount: the points earned by the USER (the 50% share)
  Future<void> _distributeTreasuryPoints(WriteBatch batch, String userId, int amount, String? countryCode) async {
    try {
      print('🔍 [DEBUG] _distributeTreasuryPoints called: userId=$userId, amount=$amount, countryCode=$countryCode');
      
      if (amount <= 0) {
        print('⚠️ [DEBUG] Amount is <= 0, returning early');
        return;
      }
      
      // [UPDATED] Helper to get Continent (DRY)
      
      // [UPDATED] Helper to get Continent (DRY)
      String? continentKey;
      if (countryCode != null) {
        try {
          final continentCode = getContinentByCountryCode(countryCode); 
          final continentName = getContinentName(continentCode); 
          
          continentKey = generateCommunityId(
            locationType: 'home', 
            type: 'continent',
            continent: continentName
          );
          print('✅ [DEBUG] Continent key generated: $continentKey');
        } catch (e) {
          print('❌ [DEBUG] Error generating continent key: $e');
        }
      }

      // [UPDATED] 5-Way Split Base (10% of Total Minted)
      // User gets 50% (amount).
      // Total Minted = amount * 2.
      // 10% share = Total Minted * 0.10 = amount * 0.2 = amount / 5.
      final int tenPercentShare = (amount / 5).round();
      print('✅ [DEBUG] Ten percent share calculated: $tenPercentShare');

      // [REMOVED] Global Community (10% Potential) - Absorbed into User Share.
      // Logic previously here has been removed to prioritize miners.

      // 2. Home Country Community (10% of Member Earnings)
    if (countryCode != null) {
      try {
        final countryId = 'home_country_${countryCode.toLowerCase()}';
        final countryRef = _firestore.collection('communities').doc(countryId);
        
        // Simple 10% distribution (no efficiency at distribution time)
        // Efficiency is applied at TGE conversion, not distribution
        final int countryPoints = tenPercentShare;

        final int totalBasisIncrement = amount * 2;
        
        // Get country name for display
        final country = getCountryByCode(countryCode);
        final countryName = country?.name ?? countryCode;
        
        print('✅ [DEBUG] Setting country treasury: $countryId, points=$countryPoints, name=$countryName');
      
      final treasuryRef = countryRef.collection('treasury').doc('current');
      
      batch.set(treasuryRef, {
        // Treasury data only - NO community metadata like 'name' or 'type'
        'cumulativeEarnings': FieldValue.increment(totalBasisIncrement), 
        'memberPoints': FieldValue.increment(amount), 
        'points': FieldValue.increment(countryPoints), // Raw 10% (no efficiency)
        'awardedBalance': FieldValue.increment(countryPoints), // Same as points for now
        'updatedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
      }, SetOptions(merge: true));
      
      print('✅ [DEBUG] Country treasury batch operation added successfully');
      } catch (e) {
        print('❌ [DEBUG] Error setting country treasury: $e');
        print('❌ [DEBUG] Stack trace: ${StackTrace.current}');
      }
    }
      
      // 3. Continent Treasury (10% of Member Earnings)
    if (continentKey != null && countryCode != null) {
      try {
        final continentCode = getContinentByCountryCode(countryCode);
        final continentName = getContinentName(continentCode);
        final continentAdjective = getContinentAdjective(continentCode);
        
        final continentRef = _firestore.collection('communities').doc(continentKey);
        
        // Simple 10% distribution (no efficiency at distribution time)
        // Efficiency is applied at TGE conversion, not distribution
        final int continentPoints = tenPercentShare;

        final int totalBasisIncrement = amount * 2;
        
        print('✅ [DEBUG] Setting continent treasury: $continentKey, points=$continentPoints, name=$continentAdjective Community Treasury');
      
      final treasuryRef = continentRef.collection('treasury').doc('current');
      
      batch.set(treasuryRef, {
        // Treasury data only - NO community metadata
        'cumulativeEarnings': FieldValue.increment(totalBasisIncrement),
        'memberPoints': FieldValue.increment(amount),
        'points': FieldValue.increment(continentPoints), // Raw 10% (no efficiency)
        'awardedBalance': FieldValue.increment(continentPoints), // Same as points for now
        'updatedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
      }, SetOptions(merge: true));
        
        print('✅ [DEBUG] Continent treasury batch operation added successfully');
      } catch (e) {
        print('❌ [DEBUG] Error setting continent treasury: $e');
        print('❌ [DEBUG] Stack trace: ${StackTrace.current}');
      }
    }

      // 4. System Treasuries (Ecosystem, Liquidity, Founders: 10% each)
      // Efficiency is 100% (1.0)
      try {
        final treasuryRef = _firestore.collection('system_stats').doc('treasury');
        
        print('✅ [DEBUG] Setting system treasuries: $tenPercentShare each');
        
        batch.set(treasuryRef, {
          'ecosystemPoints': FieldValue.increment(tenPercentShare), // 100%
          'liquidityPoints': FieldValue.increment(tenPercentShare), // 100%
          'foundersPoints': FieldValue.increment(tenPercentShare),  // 100%
          'lastUpdated': DateTime.now().toUtc().toIso8601String(),
        }, SetOptions(merge: true));
        
        print('✅ [DEBUG] System treasuries batch operation added successfully');
      } catch (e) {
        print('❌ [DEBUG] Error setting system treasuries: $e');
        print('❌ [DEBUG] Stack trace: ${StackTrace.current}');
      }

      // [REMOVED] Legacy Milestone Triggers (checkAndAward...)
      // Since we award percentage continuously based on efficiency, 
      // we no longer gate by "Milestones".
      
      print('✅ [DEBUG] _distributeTreasuryPoints completed successfully');
    } catch (e) {
      print('❌ [DEBUG] CRITICAL ERROR in _distributeTreasuryPoints: $e');
      print('❌ [DEBUG] Stack trace: ${StackTrace.current}');
      rethrow; // Re-throw to ensure calling code knows there was an error
    }
  }

  // Get current Global Supply
  Future<int> getGlobalSupply() async {
    try {
      final doc = await _firestore.collection('system_stats').doc('dsp_supply').get();
      if (!doc.exists) return 0;
      return doc.data()?['totalMinted'] as int? ?? 0;
    } catch (e) {
      print('Error fetching global supply: $e');
      return 0;
    }
  }

  /// [NEW] Force sync treasury balances based on total global supply.
  /// Used for backfilling or correcting discrepancies.
  Future<void> syncTreasuryBalances() async {
    try {
      // 1. Fetch all user points
      final userPointsSnap = await _firestore.collection('user_points').get();
      
      // [FIX] Fetch all user profiles to map UID -> Country Code
      final usersSnap = await _firestore.collection('users').get();
      final Map<String, String> userCountryMap = {};
      for (var doc in usersSnap.docs) {
         if (doc.data().containsKey('homeCountryCode')) {
            userCountryMap[doc.id] = doc.data()['homeCountryCode'];
         }
      }

      int totalUserPoints = 0;
      Map<String, int> countryPointsMap = {};
      
      // Tracking for Averaging PoCT
      Map<String, List<double>> countryPoCTs = {};

      for (var doc in userPointsSnap.docs) {
        final userId = doc.id;
        final data = doc.data();
        final points = data['totalPoints'] as int? ?? 0;
        final poct = (data['trustScore'] as num? ?? 0.0).toDouble();
        totalUserPoints += points;

        // [FIX] Fetch user's home country code from pre-fetched map
        final countryCode = userCountryMap[userId];
        if (countryCode != null) {
          final code = countryCode.toLowerCase();
          countryPointsMap[code] = (countryPointsMap[code] ?? 0) + points;
          countryPoCTs.putIfAbsent(code, () => []).add(poct);
        }
      }

      final batch = _firestore.batch();
      
      // [REMOVED] Global Community Treasury - Absorbed into User Share.
      // 2. System Treasuries (Platform, Liquidity, Founders: 10% each)
      // Efficiency is 100% (1.0)
      final int systemShare = (totalUserPoints / 5).round();
      final treasuryRef = _firestore.collection('system_stats').doc('treasury');
      batch.set(treasuryRef, {
        'ecosystemPoints': systemShare, // 100% Efficiency
        'liquidityPoints': systemShare, // 100% Efficiency
        'foundersPoints': systemShare,  // 100% Efficiency
        'lastUpdated': DateTime.now().toUtc().toIso8601String(),
      }, SetOptions(merge: true));

      // 4. Home Country Communities
      for (var entry in countryPointsMap.entries) {
        final countryId = 'home_country_${entry.key}';
        final countryRef = _firestore.collection('communities').doc(countryId);
        
        final int totalEarned = entry.value;
        final String countryCode = entry.key;
        
        // Calculate Avg PoCT for this country
        final pocts = countryPoCTs[countryCode] ?? [];
        double avgPoCT = 0;
        if (pocts.isNotEmpty) {
           avgPoCT = pocts.reduce((a, b) => a + b) / pocts.length;
        }

        // [UPDATED] Country Treasury: Simple 10% Distribution
        // Raw Share = 10% (MemberPoints / 5)
        // Efficiency is applied at TGE conversion, not distribution
        final int rawShare = (totalEarned / 5).round();
        
        print('✅ [DEBUG] Syncing country treasury: $countryId, points=$rawShare');

      final treasuryRef = countryRef.collection('treasury').doc('current');
      batch.set(treasuryRef, {
        // Treasury data only - NO community metadata
        'points': rawShare, // Raw 10% (no efficiency)
        'cumulativeEarnings': totalEarned * 2, // 100% Basis
        'memberPoints': totalEarned, 
        'awardedBalance': rawShare, // Same as points for now
        'averagePoCT': avgPoCT, // Track for future TGE conversion
        'updatedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
      }, SetOptions(merge: true));
    }
      
      // 4.1 Sync Continent Treasuries
      Map<String, int> continentPointsMap = {};
      Map<String, List<double>> continentPoCTs = {};
      Map<String, String> continentAdjectiveMap = {};

      for (var entry in countryPointsMap.entries) {
          final countryCode = entry.key;
          final points = entry.value;
          final pocts = countryPoCTs[countryCode] ?? [];
          
          final continentCode = getContinentByCountryCode(countryCode); 
          final continentName = getContinentName(continentCode); 

          if (continentCode.isNotEmpty) {
              final key = generateCommunityId(
                 locationType: 'home',
                 type: 'continent', 
                 continent: continentName
              );
              continentPointsMap[key] = (continentPointsMap[key] ?? 0) + points;
              continentPoCTs.putIfAbsent(key, () => []).addAll(pocts);
              continentAdjectiveMap[key] = getContinentAdjective(continentCode);
          }
      }
      
      for (var entry in continentPointsMap.entries) {
          final continentId = entry.key;
          final totalCommEarned = entry.value;

          final continentRef = _firestore.collection('communities').doc(continentId);
          final continentAdjective = continentAdjectiveMap[continentId] ?? 'Continent';
          
          final pocts = continentPoCTs[continentId] ?? [];
          double avgPoCT = 0;
          if (pocts.isNotEmpty) {
            avgPoCT = pocts.reduce((a, b) => a + b) / pocts.length;
          }
          
          // Extract continent name from ID (e.g., home_continent_africa -> africa)
          final continentName = continentId.split('_').last;

          // [UPDATED] Continent Treasury: Simple 10% Distribution
          // Efficiency is applied at TGE conversion, not distribution
          final int rawShare = (totalCommEarned / 5).round();

          final treasuryRef = continentRef.collection('treasury').doc('current');
          batch.set(treasuryRef, {
             // Treasury data only - NO community metadata
             'points': rawShare, // Raw 10% (no efficiency)
             'cumulativeEarnings': totalCommEarned * 2, // 100% Basis
             'memberPoints': totalCommEarned, 
             'awardedBalance': rawShare, // Same as points for now
             'averagePoCT': avgPoCT, // Track for future TGE conversion
             'updatedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
          }, SetOptions(merge: true));
      }

      // 5. Update Global Total Supply
      final int totalMinted = (totalUserPoints / 0.5).round();
      final supplyRef = _firestore.collection('system_stats').doc('dsp_supply');
      batch.set(supplyRef, {
        'totalMinted': totalMinted,
        'lastUpdated': DateTime.now().toUtc().toIso8601String(),
      }, SetOptions(merge: true));

      await batch.commit();
      print('Treasury sync completed successfully. Total User Points: $totalUserPoints');
    } catch (e) {
      print('Error syncing treasury balances: $e');
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
    // For real-time updates without high read costs, we should use a counter doc.
    // However, if one doesn't exist, we can use count(). But count() is a Future, not a Stream.
    // So we will stream the 'system_stats/user_stats' doc if it exists, or fallback to polling/count.
    // DESIGN DECISION: Assuming 'system_stats/user_stats' is maintained by cloud functions.
    // If not, we'll fall back to just returning a periodical count or 0 for now until the backend is confirmed.
    
    // For now, let's try to read from 'system_stats/global_community' (where we track members)
    return _firestore.collection('communities').doc('global_community').snapshots().map((doc) {
       return (doc.data()?['memberCount'] as int?) ?? 0;
    });
  }

  // [NEW] Update Wallet Address
  Future<void> updateWalletAddress(String userId, String walletAddress) async {
    try {
      if (walletAddress.isEmpty) return; // Basic validation
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
      final doc = await _firestore.collection('system_stats').doc('treasury').get();
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
    Query query = _firestore.collection('user_points')
        .where('totalPoints', isGreaterThanOrEqualTo: 100000);
    
    final snapshot = await query.get();
    
    // Firestore doesn't support multiple range/inequality filters on different fields 
    // unless you create composite indices. To keep it flexible, we'll filter trustScore in Dart.
    List<UserPoints> pillars = snapshot.docs
        .map((doc) => UserPoints.fromMap(doc.data() as Map<String, dynamic>))
        .where((up) => (up.trustScore ?? 0) >= 67)
        .toList();

    // Secondary filter: Country (Fetch from users collection if needed, or if stored in user_points)
    // For now, we'll return the list and assume the UI/Service handles regional logic if needed.
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

  // Initialize points for new user
  Future<void> initializeUserPoints(String userId) async {
    final doc = await _firestore.collection('user_points').doc(userId).get();
    if (doc.exists) {
      print('Points already initialized for user $userId. Skipping.');
      return;
    }

    // Fetch user's home country code from users collection for initialization
    final userDoc = await _firestore.collection('users').doc(userId).get();
    final countryCode = userDoc.data()?['homeCountryCode'] as String?;

    final batch = _firestore.batch();

    // 1. Create User Points Doc (Start with 1,000 DSP)
    final userPoints = UserPoints(
      userId: userId,
      totalPoints: 1000, // [NEW] Welcome Bonus
      availablePoints: 1000, // [NEW] Welcome Bonus
      currentStreak: 0,
      lastActivityDate: null,
      dailyMessageCount: 0,
      lastUpdated: DateTime.now().toUtc(),
      completedExplorationActions: [],
      signupDate: DateTime.now().toUtc(), // [NEW]
      dailyShareCount: 0,
      dailyCommunitiesMessaged: [],
      homeCountryCode: countryCode, // [NEW]
    );

    final userPointsRef = _firestore.collection('user_points').doc(userId);
    batch.set(userPointsRef, userPoints.toMap());

    // 2. Create Transaction Record for Welcome Bonus
    final transactionRef = _firestore.collection('points_transactions').doc();
    final transaction = PointsTransaction(
      id: transactionRef.id,
      userId: userId,
      type: 'earn',
      action: 'welcome_bonus',
      points: 1000,
      timestamp: DateTime.now().toUtc(),
      metadata: {'description': 'Welcome to Diaspora!'},
    );
    batch.set(transactionRef, transaction.toMap());

    // 3. Allocate Treasuries
    await _distributeTreasuryPoints(batch, userId, 1000, countryCode);

    // 4. Increment Global Supply
    _incrementGlobalSupplyBatch(batch, 1000);

    // [NEW] Increment Member Count for Home Country
    if (countryCode != null) {
      final countryId = 'home_country_${countryCode.toLowerCase()}';
      final countryRef = _firestore.collection('communities').doc(countryId);
      batch.update(countryRef, {
        'memberCount': FieldValue.increment(1),
        'lastUpdated': DateTime.now().toUtc().millisecondsSinceEpoch,
      });
    }

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

    // Update user points
    final userPointsRef = _firestore.collection('user_points').doc(userId);
    batch.set(userPointsRef, {
      'totalPoints': FieldValue.increment(points),
      'availablePoints': FieldValue.increment(points),
      'lastUpdated': DateTime.now().toUtc().toIso8601String(),
      'lifetimeEarnings.$action': FieldValue.increment(points), // [NEW] Track lifetime per activity
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

    // [FIX] Fetch country code to ensure it's saved and distributed
    final userDoc = await _firestore.collection('users').doc(userId).get();
    final countryCode = userDoc.data()?['homeCountryCode'] as String?;
    
    // Ensure homeCountryCode is in user_points for future syncs
    if (countryCode != null) {
       batch.update(userPointsRef, {'homeCountryCode': countryCode});
    }

    // Allocate Treasuries
    await _distributeTreasuryPoints(batch, userId, points, countryCode);

    // Increment Global Supply
    _incrementGlobalSupplyBatch(batch, points);

    await batch.commit();
  }

  /// [NEW] Add points to 'total' but not 'available' (Staged/Locked Rewards)
  Future<void> addStagedPoints(
    String userId,
    int points,
    String action, {
    Map<String, dynamic>? metadata,
  }) async {
    final batch = _firestore.batch();

    // Update user total points (Lifetime Stake)
    final userPointsRef = _firestore.collection('user_points').doc(userId);
    batch.set(userPointsRef, {
      'totalPoints': FieldValue.increment(points),
      'lastUpdated': DateTime.now().toUtc().toIso8601String(),
      'lifetimeEarnings.$action': FieldValue.increment(points), // [NEW] Track lifetime per activity
    }, SetOptions(merge: true));

    // Create transaction record (Marked as staged/locked)
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

    // [FIX] Fetch country code for distribution
    final userDoc = await _firestore.collection('users').doc(userId).get();
    final countryCode = userDoc.data()?['homeCountryCode'] as String?;

    // Treasury and Supply still increment because these tokens ARE minted/reserved
    await _distributeTreasuryPoints(batch, userId, points, countryCode);
    _incrementGlobalSupplyBatch(batch, points);

    await batch.commit();
  }

  // [REMOVED] Legacy checkAndAwardCollectiveTribute/ContinentTribute/GlobalTribute
  // Logic replaced by continuous streaming to 'awardedBalance' in _distributeTreasuryPoints.

  // Deduct points from user (Penalty)
  Future<void> deductPoints(
    String userId,
    int points,
    String action, {
    Map<String, dynamic>? metadata,
  }) async {
    final batch = _firestore.batch();

    // Update user points
    final userPointsRef = _firestore.collection('user_points').doc(userId);
    batch.set(userPointsRef, {
      'availablePoints': FieldValue.increment(-points),
      'lastUpdated': DateTime.now().toUtc().toIso8601String(),
    }, SetOptions(merge: true));

    // Create transaction record
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
    // Format: FIRSTNAME-CC-XXXX (e.g., PETER-TZ-A7B9)
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

      // Check if code already exists
      final existing = await _firestore
          .collection('referral_codes')
          .doc(code)
          .get();

      isUnique = !existing.exists;
      attempts++;

      if (attempts > 10) {
        throw Exception('Failed to generate unique referral code');
      }
    } while (!isUnique);

    // Store referral code
    await _firestore.collection('referral_codes').doc(code).set({
      'userId': userId,
      'code': code,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'usedCount': 0,
    });

    return code;
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
      return doc.data()!['userId'] as String;
    } catch (e) {
      throw Exception('Failed to validate referral code: $e');
    }
  }

  // Process referral signup (award points to both users)
  Future<void> processReferralSignup(
    String referrerId,
    String newUserId,
    String code,
  ) async {
    // Award 1000 DSP to referrer
    await addPoints(
      referrerId,
      1000,
      'referral_signup',
      metadata: {'referredUserId': newUserId, 'code': code},
    );

    // Award 1000 DSP to new user
    await addPoints(
      newUserId,
      1000,
      'referral_signup',
      metadata: {'referrerId': referrerId, 'code': code},
    );

    // Increment usage count
    await _firestore.collection('referral_codes').doc(code).update({
      'usedCount': FieldValue.increment(1),
    });

    // Increment Global Supply (1000 for referrer + 1000 for new user = 2000)
    final batch = _firestore.batch();
    _incrementGlobalSupplyBatch(batch, 2000);
    await batch.commit();
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

  Future<void> transferPoints({
    required String fromUserId,
    required String toUserId,
    required int amount,
  }) async {
    if (amount <= 0) throw Exception('Amount must be greater than 0');

    final batch = _firestore.batch();

    // We use a transaction to ensure atomicity but since we are using helper methods
    // that might not be compatible with runTransaction if we want to reuse logic.
    // However, simplest way for separate docs is runTransaction.

    // Re-implementing with runTransaction for safety
    await _firestore.runTransaction((transaction) async {
      final fromRef = _firestore.collection('user_points').doc(fromUserId);
      final toRef = _firestore.collection('user_points').doc(toUserId);

      final fromSnapshot = await transaction.get(fromRef);
      final toSnapshot = await transaction.get(toRef);

      if (!fromSnapshot.exists) throw Exception('Sender wallet not found');

      final fromData = UserPoints.fromMap(fromSnapshot.data()!);

      if (fromData.availablePoints < amount) {
        throw Exception('Insufficient funds');
      }

      // Deduct from sender (Only available points, preserve lifetime total)
      transaction.update(fromRef, {
        'availablePoints': fromData.availablePoints - amount,
        // 'totalPoints': fromData.totalPoints - amount, // [FIX] Do not deduct from lifetime earnings
        'lastUpdated': DateTime.now().toUtc().toIso8601String(),
      });

      // Add to recipient
      if (toSnapshot.exists) {
        final toData = UserPoints.fromMap(toSnapshot.data()!);
        transaction.update(toRef, {
          'availablePoints': toData.availablePoints + amount,
          // 'totalPoints': toData.totalPoints + amount, // [FIX] REMOVED: Total Points tracks MINED DSP only.
          // Preventing wash-trading for Tributes.
          'lastUpdated': DateTime.now().toUtc().toIso8601String(),
        });
      } else {
        // Initialize recipient if needed
        final toUserPoints = UserPoints(
          userId: toUserId,
          totalPoints: 0, // [FIX] 0 because this is a transfer, not a mint event.

          availablePoints: amount,
          currentStreak: 0,
          lastActivityDate: null,
          dailyMessageCount: 0,
          lastUpdated: DateTime.now().toUtc(),
          signupDate: DateTime.now().toUtc(), // [FIX] Added
        );
        transaction.set(toRef, toUserPoints.toMap());
      }

      // Create Transaction Records
      final timestamp = DateTime.now().toUtc();

      // outgoing
      final outRef = _firestore.collection('points_transactions').doc();
      final outTx = PointsTransaction(
        id: outRef.id,
        userId: fromUserId,
        type: 'spend',
        action: 'transfer_sent',
        points: -amount,
        timestamp: timestamp,
        metadata: {'recipientId': toUserId},
      );
      transaction.set(outRef, outTx.toMap());

      // incoming
      final inRef = _firestore.collection('points_transactions').doc();
      final inTx = PointsTransaction(
        id: inRef.id,
        userId: toUserId,
        type: 'earn',
        action: 'transfer_received',
        points: amount,
        timestamp: timestamp,
        metadata: {'senderId': fromUserId},
      );
      transaction.set(inRef, inTx.toMap());
    });
  }

  // Award points for sending a message (Daily Cap enforced)
  Future<void> awardMessagePoint(
    String userId,
    int points, {
    int multiplier = 1,
  }) async {
    final now = DateTime.now().toUtc();

    // Check daily limit (100 messages)
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

      // Reset daily count if new day
      if (lastUpdated == null ||
          lastUpdated.year != now.year ||
          lastUpdated.month != now.month ||
          lastUpdated.day != now.day) {
        dailyCount = 0;
      }

      if (dailyCount >= 100) return; // Cap reached

      final pointsToAward = points * multiplier;

      transaction.update(userPointsRef, {
        'totalPoints': FieldValue.increment(pointsToAward),
        'availablePoints': FieldValue.increment(pointsToAward),
        'dailyMessageCount': dailyCount + 1,
        'lastUpdated': now.toIso8601String(),
      });

      // Transaction Record
      final transactionRef = _firestore.collection('points_transactions').doc();
      final tx = PointsTransaction(
        id: transactionRef.id,
        userId: userId,
        type: 'earn',
        action: 'message_sent',
        points: pointsToAward,
        timestamp: now,
      );
      transaction.set(transactionRef, tx.toMap());

      // Update Global Supply
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

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(userPointsRef);
      if (!snapshot.exists) return; // Should potentially init here, but assuming user exists

      final data = snapshot.data()!;
      final completedActions = List<String>.from(data['completedExplorationActions'] ?? []);

      if (completedActions.contains(actionId)) {
        // Already completed this action
        throw Exception('Action already completed');
      }

      // 1. Update User Points
      transaction.update(userPointsRef, {
        'totalPoints': FieldValue.increment(points),
        'availablePoints': FieldValue.increment(points),
        'lastUpdated': DateTime.now().toUtc().toIso8601String(),
        'completedExplorationActions': FieldValue.arrayUnion([actionId]),
      });

      // 2. Create Transaction Record
      final transactionRef = _firestore.collection('points_transactions').doc();
      final tx = PointsTransaction(
        id: transactionRef.id,
        userId: userId,
        type: 'earn',
        action: 'exploration_$actionId',
        points: points,
        timestamp: DateTime.now().toUtc(),
        metadata: metadata,
      );
      transaction.set(transactionRef, tx.toMap());

      // Allocate Treasuries (Manual inline for Transaction compatibility)
      // 1. Global Community
      final globalCommRef = _firestore.collection('communities').doc('global_community');
      transaction.set(globalCommRef, {
        'points': FieldValue.increment(points),
        'updatedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
      }, SetOptions(merge: true));

      // 2. Home Country Community
      final userRef = _firestore.collection('users').doc(userId);
      final userSnap = await transaction.get(userRef);
      final countryCode = userSnap.data()?['homeCountryCode'] as String?;
      
      if (countryCode != null) {
        final countryId = 'home_country_${countryCode.toLowerCase()}';
        final countryRef = _firestore.collection('communities').doc(countryId);
        
        transaction.set(countryRef, {
          'cumulativeEarnings': FieldValue.increment(points),
          'updatedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
        }, SetOptions(merge: true));
      }

      // 3. System Treasuries
      final treasuryRef = _firestore.collection('system_stats').doc('treasury');
      final int systemShare = (points / 6).round();
      transaction.set(treasuryRef, {
        'ecosystemPoints': FieldValue.increment(systemShare),
        'liquidityPoints': FieldValue.increment(systemShare),
        'foundersPoints': FieldValue.increment(systemShare),
        'lastUpdated': DateTime.now().toUtc().toIso8601String(),
      }, SetOptions(merge: true));

      // Increment Global Supply
      _incrementGlobalSupplyTx(transaction, points);
    });
  }

  // [NEW] Award points for sharing content (Daily Cap enforced)
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

      // Reset daily count if new day
      if (lastUpdated == null ||
          lastUpdated.year != now.year ||
          lastUpdated.month != now.month ||
          lastUpdated.day != now.day) {
        dailyShareCount = 0;
      }

      if (dailyShareCount >= 12) return; // [UPDATED] Cap reached (12 shares per day)

      transaction.update(userPointsRef, {
        'totalPoints': FieldValue.increment(points),
        'availablePoints': FieldValue.increment(points),
        'dailyShareCount': dailyShareCount + 1,
        'lastUpdated': now.toIso8601String(),
      });

      // Transaction Record
      final transactionRef = _firestore.collection('points_transactions').doc();
      final tx = PointsTransaction(
        id: transactionRef.id,
        userId: userId,
        type: 'earn',
        action: 'content_shared',
        points: points,
        timestamp: now,
        metadata: {'contentType': contentType},
      );
      transaction.set(transactionRef, tx.toMap());
      // Update Global Supply
      _incrementGlobalSupplyTx(transaction, points);
      
      rewarded = true;
    });

    return rewarded;
  }

  /// [NEW] Updates the PoCT score in the user_points collection.
  Future<void> updateTrustScore(String userId, double score) async {
    await _firestore.collection('user_points').doc(userId).update({
      'trustScore': score,
      'lastUpdated': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// [NEW] Calculates and updates the average PoCT score of ALL users in a country.
  Future<void> updateCommunityOverallAveragePoCT(String countryCode) async {
    final countryId = 'home_country_${countryCode.toLowerCase()}';
    
    // 1. Fetch ALL users' points record for this country
    final snapshot = await _firestore.collection('user_points')
        .where('homeCountryCode', isEqualTo: countryCode)
        .get();

    if (snapshot.docs.isEmpty) return;

    // 2. Calculate average
    double totalScore = 0;
    for (var doc in snapshot.docs) {
      totalScore += (doc.data()['trustScore'] as num? ?? 0).toDouble();
    }
    final double average = totalScore / snapshot.docs.length;

    // 3. Update community doc
    await _firestore.collection('communities').doc(countryId).update({
      'averagePoCT': average,
      'lastUpdatedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
    });
    
    print('✅ Updated Community Avg PoCT for $countryCode: $average');
  }

  /// [NEW] Calculates and updates the average PoCT score of ALL users in a continent.
  Future<void> updateContinentOverallAveragePoCT(String continentCode) async {
    final continentName = getContinentName(continentCode);
    final continentId = generateCommunityId(
      locationType: 'home',
      type: 'continent',
      continent: continentName,
    );

    // 1. Fetch ALL users' points record for this continent
    // Note: We don't store continent code in user_points yet, so we have to fetch by country codes in that continent.
    // However, it's easier to just fetch and filter if collection is small, OR 
    // better: query communities for country members in this continent.
    
    // For now, let's use a simpler approach: calculate from country averages if available
    // BUT to be accurate, we need the raw scores or at least (avg * count) per country.
    
    final countriesSnap = await _firestore.collection('communities')
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
    final double average = weightedSum / totalMembers;

    // Update continent doc
    await _firestore.collection('communities').doc(continentId).update({
      'averagePoCT': average,
      'lastUpdatedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
    });
    
    print('✅ Updated Continent Avg PoCT for $continentName: $average');
  }

  /// [NEW] Calculates and updates the global average PoCT score.
  Future<void> updateGlobalOverallAveragePoCT() async {
    final globalId = 'global_community';
    
    // Fetch all country docs to calculate the global weighted average
    final countriesSnap = await _firestore.collection('communities')
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
    final double average = weightedSum / totalMembers;

    // Update global doc
    await _firestore.collection('communities').doc(globalId).update({
      'averagePoCT': average,
      'lastUpdatedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
    });
    
    print('✅ Updated Global Avg PoCT: $average');
  }
}
