import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/models/user_points.dart';
import 'package:diaspora_nearby/models/points_transaction.dart';

final pointsRepositoryProvider = Provider<PointsRepository>((ref) {
  return PointsRepository(FirebaseFirestore.instance);
});

class PointsRepository {
  final FirebaseFirestore _firestore;

  PointsRepository(this._firestore);

  // Get user's points balance
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
    final batch = _firestore.batch();
    
    // 1. Create User Points Doc (Start with 500 DSP)
    final userPoints = UserPoints(
      userId: userId,
      totalPoints: 500, // [NEW] Welcome Bonus
      availablePoints: 500, // [NEW] Welcome Bonus
      currentStreak: 0,
      lastActivityDate: null,
      dailyMessageCount: 0,
      lastUpdated: DateTime.now(),
      completedExplorationActions: [], // [NEW]
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
      points: 500,
      timestamp: DateTime.now(),
      metadata: {'description': 'Welcome to Diaspora Nearby!'},
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

    // Update user points
    final userPointsRef = _firestore.collection('user_points').doc(userId);
    batch.update(userPointsRef, {
      'totalPoints': FieldValue.increment(points),
      'availablePoints': FieldValue.increment(points),
      'lastUpdated': DateTime.now().toIso8601String(),
    });

    // Create transaction record
    final transactionRef = _firestore.collection('points_transactions').doc();
    final transaction = PointsTransaction(
      id: transactionRef.id,
      userId: userId,
      type: 'earn',
      action: action,
      points: points,
      timestamp: DateTime.now(),
      metadata: metadata,
    );
    batch.set(transactionRef, transaction.toMap());

    await batch.commit();
  }

  // Update streak
  Future<void> updateStreak(String userId, int newStreak) async {
    await _firestore.collection('user_points').doc(userId).update({
      'currentStreak': newStreak,
      'lastActivityDate': DateTime.now().toIso8601String(),
      'lastUpdated': DateTime.now().toIso8601String(),
    });
  }

  // Increment daily message count
  Future<void> incrementDailyMessageCount(String userId) async {
    await _firestore.collection('user_points').doc(userId).update({
      'dailyMessageCount': FieldValue.increment(1),
      'lastUpdated': DateTime.now().toIso8601String(),
    });
  }

  // Reset daily message count
  Future<void> resetDailyMessageCount(String userId) async {
    await _firestore.collection('user_points').doc(userId).update({
      'dailyMessageCount': 0,
      'lastUpdated': DateTime.now().toIso8601String(),
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
      return List.generate(4, (_) => chars[random.nextInt(chars.length)]).join();
    }

    String code;
    bool isUnique = false;
    int attempts = 0;

    do {
      final randomId = generateRandomId();
      code = '${firstName.toUpperCase()}-${countryCode.toUpperCase()}-$randomId';
      
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
      'createdAt': DateTime.now().toIso8601String(),
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
    // Award 100 points to referrer
    await addPoints(
      referrerId,
      100,
      'referral_signup',
      metadata: {'referredUserId': newUserId, 'code': code},
    );

    // Award 100 points to new user
    await addPoints(
      newUserId,
      100,
      'referral_signup',
      metadata: {'referrerId': referrerId, 'code': code},
    );

    // Increment usage count
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
          'lastUpdated': DateTime.now().toIso8601String(),
       });
       
       // Add to recipient
       if (toSnapshot.exists) {
          final toData = UserPoints.fromMap(toSnapshot.data()!);
           transaction.update(toRef, {
              'availablePoints': toData.availablePoints + amount,
              'totalPoints': toData.totalPoints + amount, // recipient earns points, so total increases
              'lastUpdated': DateTime.now().toIso8601String(),
           });
       } else {
          // Initialize recipient if needed
           final toUserPoints = UserPoints(
              userId: toUserId,
              totalPoints: amount,
              availablePoints: amount,
              currentStreak: 0,
              lastActivityDate: null,
              dailyMessageCount: 0,
              lastUpdated: DateTime.now(),
           );
           transaction.set(toRef, toUserPoints.toMap());
       }
       
       // Create Transaction Records
       final timestamp = DateTime.now();
       
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

  // Award exploration points unique per action
  Future<void> awardExplorationPoints({
    required String userId,
    required String actionId,
    required int points,
    Map<String, dynamic>? metadata,
  }) async {
    final batch = _firestore.batch();
    
    // 1. Update User Points
    final userPointsRef = _firestore.collection('user_points').doc(userId);
    batch.update(userPointsRef, {
      'totalPoints': FieldValue.increment(points),
      'availablePoints': FieldValue.increment(points),
      'lastUpdated': DateTime.now().toIso8601String(),
      'completedExplorationActions': FieldValue.arrayUnion([actionId]),
    });
    
    // 2. Create Transaction Record
    final transactionRef = _firestore.collection('points_transactions').doc();
    final transaction = PointsTransaction(
      id: transactionRef.id,
      userId: userId,
      type: 'earn',
      action: 'exploration_$actionId',
      points: points,
      timestamp: DateTime.now(),
      metadata: metadata,
    );
    batch.set(transactionRef, transaction.toMap());
    
    await batch.commit();
  }
}
