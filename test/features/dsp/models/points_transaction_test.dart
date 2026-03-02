import 'package:flutter_test/flutter_test.dart';
import 'package:diaspora_nearby/features/dsp/models/points_transaction.dart';

void main() {
  group('PointsTransaction', () {
    final now = DateTime.now().toUtc();
    final id = 'trans_123';
    final transactionMap = {
      'userId': 'user_1',
      'type': 'earn',
      'action': 'message_sent',
      'points': 10,
      'timestamp': now.toIso8601String(),
      'metadata': {'communityId': 'comm_1'},
    };

    test('fromMap should create a valid PointsTransaction object', () {
      final transaction = PointsTransaction.fromMap(transactionMap, id);

      expect(transaction.id, id);
      expect(transaction.userId, 'user_1');
      expect(transaction.type, 'earn');
      expect(transaction.action, 'message_sent');
      expect(transaction.points, 10);
      expect(transaction.timestamp.toIso8601String(), now.toIso8601String());
      expect(transaction.metadata?['communityId'], 'comm_1');
    });

    test('toMap should return a valid map representation', () {
      final transaction = PointsTransaction(
        id: id,
        userId: 'user_1',
        type: 'earn',
        action: 'message_sent',
        points: 10,
        timestamp: now,
        metadata: {'communityId': 'comm_1'},
      );
      final map = transaction.toMap();

      expect(map['userId'], 'user_1');
      expect(map['type'], 'earn');
      expect(map['action'], 'message_sent');
      expect(map['points'], 10);
      expect(map['timestamp'], now.toIso8601String());
      expect(map['metadata']['communityId'], 'comm_1');
      // id is not in toMap according to the current implementation
    });

    group('displayAction', () {
      test('should use description from metadata if available', () {
        final transaction = PointsTransaction(
          id: id,
          userId: 'user_1',
          type: 'earn',
          action: 'other',
          points: 10,
          timestamp: now,
          metadata: {'description': 'Custom Action'},
        );
        expect(transaction.displayAction, 'Custom Action');
      });

      test('should humanize common actions', () {
        final transaction = PointsTransaction(
          id: id,
          userId: 'user_1',
          type: 'earn',
          action: 'referral_signup',
          points: 50,
          timestamp: now,
        );
        expect(transaction.displayAction, 'Referral Signup');
      });

      test('should humanize snake_case actions', () {
        final transaction = PointsTransaction(
          id: id,
          userId: 'user_1',
          type: 'earn',
          action: 'joined_community_event',
          points: 20,
          timestamp: now,
        );
        expect(transaction.displayAction, 'Joined Community Event');
      });

      test('should humanize exploration rewards', () {
        final transaction = PointsTransaction(
          id: id,
          userId: 'user_1',
          type: 'earn',
          action: 'exploration_complete',
          points: 100,
          timestamp: now,
          metadata: {'description': 'Exploration Reward: welcome_tour'},
        );
        expect(transaction.displayAction, 'Exploration Reward: Welcome Tour');
      });
    });
  });
}
