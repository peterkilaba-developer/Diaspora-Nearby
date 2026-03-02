import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
// ignore: unused_import
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import 'package:diaspora_nearby/features/dsp/models/user_points.dart';
// ignore: unused_import
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';
// ignore: unused_import
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import '../../../utils/test_data.dart';
import '../../../utils/mocks.mocks.dart';

void main() {
  late PointsService pointsService;
  late MockPointsRepository mockRepository;
  late MockTrustService mockTrustService;
  late MockProfileRepository mockProfileRepository;

  setUp(() {
    mockRepository = MockPointsRepository();
    mockTrustService = MockTrustService();
    mockProfileRepository = MockProfileRepository();
    pointsService = PointsService(mockRepository, mockTrustService, mockProfileRepository);
  });

  group('PointsService', () {
    const userId = TestData.userId1;

    test('initializeUserPoints should call repository', () async {
      when(mockRepository.initializeUserPoints(any))
          .thenAnswer((_) async => {});

      await pointsService.initializeUserPoints(userId);

      verify(mockRepository.initializeUserPoints(userId)).called(1);
    });

    test('awardPoints should proxy to repository and update streak', () async {
      const action = 'message_sent';
      const points = 10;
      final userPoints = UserPoints(
        userId: userId,
        totalPoints: 100,
        availablePoints: 100,
        currentStreak: 1,
        dailyMessageCount: 1,
        lastUpdated: DateTime.now(),
        signupDate: DateTime.now(),
      );

      when(mockRepository.getUserPoints(userId))
          .thenAnswer((_) async => userPoints);

      when(mockRepository.addPoints(
        userId,
        points,
        action,
        metadata: anyNamed('metadata'),
      )).thenAnswer((_) async => {});

      await pointsService.awardManualPoints(
        userId,
        points,
        action,
      );

      verify(mockRepository.addPoints(
        userId,
        points,
        action,
        metadata: anyNamed('metadata'),
      )).called(1);
    });

    test('trackExplorationReward should initialize user points if null', () async {
      const actionId = 'test_action';
      when(mockRepository.getUserPoints(userId)).thenAnswer((_) async => null);
      when(mockRepository.initializeUserPoints(userId))
          .thenAnswer((_) async => {});
      when(mockRepository.awardExplorationPoints(
        userId: userId,
        actionId: actionId,
        points: anyNamed('points'),
        metadata: anyNamed('metadata'),
      )).thenAnswer((_) async => {});

      final rewarded = await pointsService.trackExplorationReward(userId, actionId);

      expect(rewarded, isTrue);
      verify(mockRepository.initializeUserPoints(userId)).called(1);
      verify(mockRepository.awardExplorationPoints(
        userId: userId,
        actionId: actionId,
        points: anyNamed('points'),
        metadata: anyNamed('metadata'),
      )).called(1);
    });
  });
}
