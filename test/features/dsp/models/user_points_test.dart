import 'package:flutter_test/flutter_test.dart';
import 'package:diaspora_nearby/features/dsp/models/user_points.dart';

void main() {
  group('UserPoints', () {
    final now = DateTime.now();
    final userPointsMap = {
      'userId': 'user_1',
      'totalPoints': 1000,
      'availablePoints': 800,
      'currentStreak': 5,
      'lastActivityDate': now.toIso8601String(),
      'dailyMessageCount': 10,
      'lastUpdated': now.toIso8601String(),
      'signupDate': now.toIso8601String(),
      'dailyShareCount': 2,
      'dailyCommunitiesMessaged': ['comm_1'],
      'completedExplorationActions': ['action_1'],
      'walletAddress': '0x123',
      'trustScore': 75,
      'homeCountryCode': 'TZ',
      'lifetimeEarnings': {'message_sent': 500},
      'tgeHistory': [
        {
          'epoch': 1,
          'tgeNumber': 1,
          'amount': 100.0,
          'efficiency': 1.0,
          'date': now.toIso8601String(),
        }
      ],
    };

    test('fromMap should create a valid UserPoints object', () {
      final userPoints = UserPoints.fromMap(userPointsMap);

      expect(userPoints.userId, 'user_1');
      expect(userPoints.totalPoints, 1000);
      expect(userPoints.availablePoints, 800);
      expect(userPoints.currentStreak, 5);
      expect(userPoints.dailyMessageCount, 10);
      expect(userPoints.dailyShareCount, 2);
      expect(userPoints.walletAddress, '0x123');
      expect(userPoints.trustScore, 75);
      expect(userPoints.homeCountryCode, 'TZ');
      expect(userPoints.lifetimeEarnings['message_sent'], 500);
      expect(userPoints.tgeHistory.length, 1);
      expect(userPoints.tgeHistory.first.amount, 100.0);
    });

    test('toMap should return a valid map representation', () {
      final userPoints = UserPoints.fromMap(userPointsMap);
      final map = userPoints.toMap();

      expect(map['userId'], 'user_1');
      expect(map['totalPoints'], 1000);
      expect(map['availablePoints'], 800);
      expect(map['currentStreak'], 5);
      expect(map['dailyMessageCount'], 10);
      expect(map['walletAddress'], '0x123');
      expect(map['trustScore'], 75);
      expect(map['homeCountryCode'], 'TZ');
      expect(map['lifetimeEarnings']['message_sent'], 500);
      expect(map['tgeHistory'].length, 1);
    });

    test('copyWith should update specified fields', () {
      final userPoints = UserPoints.fromMap(userPointsMap);
      final updated = userPoints.copyWith(totalPoints: 1200, currentStreak: 6);

      expect(updated.totalPoints, 1200);
      expect(updated.currentStreak, 6);
      expect(updated.userId, userPoints.userId); // Unchanged
    });
  });
}
