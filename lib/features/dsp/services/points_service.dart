import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import 'package:diaspora_nearby/models/user_points.dart';

final pointsServiceProvider = Provider<PointsService>((ref) {
  return PointsService(ref.read(pointsRepositoryProvider));
});

class PointsService {
  final PointsRepository _repository;

  PointsService(this._repository);

  // Initialize points for new user
  Future<void> initializeUserPoints(String userId) async {
    await _repository.initializeUserPoints(userId);
  }

  // Track daily app open (first open of the day awards 1 point)
  Future<void> trackDailyOpen(String userId) async {
    try {
      final userPoints = await _repository.getUserPoints(userId);
      if (userPoints == null) {
        // Initialize if doesn't exist
        await initializeUserPoints(userId);
        return;
      }

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      
      // Check if last activity was today
      if (userPoints.lastActivityDate != null) {
        final lastActivity = DateTime(
          userPoints.lastActivityDate!.year,
          userPoints.lastActivityDate!.month,
          userPoints.lastActivityDate!.day,
        );

        if (lastActivity == today) {
          // Already opened today, no points
          return;
        }
      }

      // Award 1 point for daily open
      await _repository.addPoints(userId, 1, 'daily_open');

      // Update streak
      await _updateStreak(userId, userPoints);
    } catch (e) {
      print('Error tracking daily open: $e');
    }
  }

  // Track message sent (1 point per message, max 100/day)
  Future<void> trackMessageSent(String userId) async {
    try {
      final userPoints = await _repository.getUserPoints(userId);
      if (userPoints == null) return;

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // Check if we need to reset daily count
      if (userPoints.lastActivityDate != null) {
        final lastActivity = DateTime(
          userPoints.lastActivityDate!.year,
          userPoints.lastActivityDate!.month,
          userPoints.lastActivityDate!.day,
        );

        if (lastActivity != today) {
          // New day, reset count
          await _repository.resetDailyMessageCount(userId);
        }
      }

      // Check if under daily cap
      if (userPoints.dailyMessageCount < 100) {
        await _repository.addPoints(userId, 1, 'message_sent');
        await _repository.incrementDailyMessageCount(userId);
      }
    } catch (e) {
      print('Error tracking message sent: $e');
    }
  }

  // Update streak and check for bonuses
  Future<void> _updateStreak(String userId, UserPoints userPoints) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    int newStreak = 1;

    if (userPoints.lastActivityDate != null) {
      final lastActivity = DateTime(
        userPoints.lastActivityDate!.year,
        userPoints.lastActivityDate!.month,
        userPoints.lastActivityDate!.day,
      );

      final daysDifference = today.difference(lastActivity).inDays;

      if (daysDifference == 1) {
        // Consecutive day
        newStreak = userPoints.currentStreak + 1;
      } else if (daysDifference > 1) {
        // Streak broken
        newStreak = 1;
      } else {
        // Same day (shouldn't happen in this flow)
        newStreak = userPoints.currentStreak;
      }
    }

    // Update streak
    await _repository.updateStreak(userId, newStreak);

    // Check for streak bonuses
    if (newStreak == 7) {
      await _repository.addPoints(
        userId,
        10,
        'streak_7',
        metadata: {'streak': 7},
      );
    } else if (newStreak == 30) {
      await _repository.addPoints(
        userId,
        60,
        'streak_30',
        metadata: {'streak': 30},
      );
    }
  }

  // Process referral (called during signup)
  Future<void> processReferral(String code, String newUserId) async {
    try {
      // Validate code and get referrer ID
      final referrerId = await _repository.validateReferralCode(code);
      
      if (referrerId == null) {
        throw Exception('Invalid referral code');
      }

      // Prevent self-referral
      if (referrerId == newUserId) {
        throw Exception('Cannot use your own referral code');
      }

      // Award points to both users
      await _repository.processReferralSignup(referrerId, newUserId, code);
    } catch (e) {
      print('Error processing referral: $e');
      rethrow;
    }
  }

  // Generate referral code for user
  Future<String> generateReferralCode(
    String userId,
    String firstName,
    String countryCode,
  ) async {
    // Check if user already has a code
    final existingCode = await _repository.getReferralCode(userId);
    if (existingCode != null) {
      return existingCode;
    }

    // Generate new code
    return await _repository.generateReferralCode(
      userId,
      firstName,
      countryCode,
    );
  }

  // Get user's referral code
  Future<String?> getReferralCode(String userId) async {
    return await _repository.getReferralCode(userId);
  }
  // Transfer points
  Future<void> transferPoints({
    required String fromUserId,
    required String toUserId,
    required int amount, // DSP Amount
  }) async {
    await _repository.transferPoints(
      fromUserId: fromUserId,
      toUserId: toUserId,
      amount: amount,
    );
  }

  // Track exploration action (returns true if rewarded)
  Future<bool> trackExplorationReward(String userId, String actionId, {int points = 1}) async {
    try {
      final userPoints = await _repository.getUserPoints(userId);
      if (userPoints == null) return false;
      
      // Check if already completed
      if (userPoints.completedExplorationActions.contains(actionId)) {
        return false;
      }
      
      // Award Points
      await _repository.awardExplorationPoints(
        userId: userId,
        actionId: actionId,
        points: points,
        metadata: {'description': 'Exploration Reward: $actionId'},
      );
      
      return true;
    } catch (e) {
      print('Error tracking exploration reward: $e');
      return false;
    }
  }
}
