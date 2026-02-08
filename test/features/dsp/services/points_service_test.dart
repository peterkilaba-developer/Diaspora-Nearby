import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/dsp/models/point_record.dart';
import '../../../utils/test_data.dart';

// Generate mocks with build_runner:
// flutter pub run build_runner build

class MockPointsService extends Mock implements PointsService {}

void main() {
  group('PointsService', () {
    late MockPointsService mockPointsService;

    setUp(() {
      mockPointsService = MockPointsService();
    });

    test('awardPoints should create a point record', () async {
      // Arrange
      const userId = TestData.userId1;
      const activityType = 'message_sent';
      const points = 1;

      when(mockPointsService.awardPoints(
        userId: userId,
        activityType: activityType,
        points: points,
      )).thenAnswer((_) async => {});

      // Act
      await mockPointsService.awardPoints(
        userId: userId,
        activityType: activityType,
        points: points,
      );

      // Assert
      verify(mockPointsService.awardPoints(
        userId: userId,
        activityType: activityType,
        points: points,
      )).called(1);
    });

    test('getUserBalance should return current balance', () async {
      // Arrange
      const userId = TestData.userId1;
      const expectedBalance = 100;

      when(mockPointsService.getUserBalance(userId))
          .thenAnswer((_) async => expectedBalance);

      // Act
      final balance = await mockPointsService.getUserBalance(userId);

      // Assert
      expect(balance, equals(expectedBalance));
    });

    test('getPointsHistory should return list of point records', () async {
      // Arrange
      const userId = TestData.userId1;
      final expectedRecords = [
        TestData.createPointRecord(userId: userId, points: 1),
        TestData.createPointRecord(userId: userId, points: 10),
      ];

      when(mockPointsService.getPointsHistory(userId))
          .thenAnswer((_) async => expectedRecords);

      // Act
      final records = await mockPointsService.getPointsHistory(userId);

      // Assert
      expect(records.length, equals(2));
      expect(records[0].points, equals(1));
      expect(records[1].points, equals(10));
    });
  });
}
