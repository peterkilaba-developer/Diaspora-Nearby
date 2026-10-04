import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';
import 'package:diaspora_nearby/features/trust/repository/trust_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/relationship_repository.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/trust/models/trust_data.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/dsp/models/user_points.dart';
import 'package:diaspora_nearby/features/shared/models/location.dart';
import 'package:diaspora_nearby/features/profile/models/relationship.dart';
import 'package:diaspora_nearby/features/dsp/services/emergency_fund_service.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@GenerateMocks([
  TrustRepository,
  PointsService,
  RelationshipRepository,
  ProfileRepository,
  PointsRepository,
])
import 'hts_ledger_test.mocks.dart';

class _FakeEmergencyFundService extends Fake implements EmergencyFundService {
  @override
  Future<bool> hasStaked(String userId) async => false;
}

class _FakeChatRepository extends Fake implements ChatRepository {
  @override
  Future<bool> isAdminOfLargeGroupChat(
    String uid, {
    int minMembers = 100,
  }) async => false;
}

/// Helper to create a fully complete profile
ProfileData _completeProfile(String userId) => ProfileData(
  uid: userId,
  firstName: 'A',
  lastName: 'B',
  phone: '1',
  profileImage: '',
  homeLocation: const UserLocation(formattedAddress: 'A', placeId: 'B'),
  hostLocation: const UserLocation(formattedAddress: 'A', placeId: 'B'),
  bio: 'Bio',
  occupation: 'Dev',
  yearsInHostCountry: '5',
  industry: ['Tech'],
  profession: ['Engineer'],
  languages: ['English'],
  meetingPreferences: ['Remote'],
  availability: ['Anytime'],
  servicesOffered: ['Coding'],
  lookingFor: ['Connections'],
  interests: ['Technology'],
  education: [
    Education(institution: 'Uni', degree: 'CS', graduationYear: '2020'),
  ],
);

void main() {
  late TrustService trustService;
  late MockTrustRepository mockTrustRepo;
  late MockPointsService mockPointsService;
  late MockRelationshipRepository mockRelRepo;
  late MockPointsRepository mockPointsRepo;
  late ProviderContainer container;

  setUp(() {
    mockTrustRepo = MockTrustRepository();
    mockPointsService = MockPointsService();
    mockRelRepo = MockRelationshipRepository();
    mockPointsRepo = MockPointsRepository();

    container = ProviderContainer(
      overrides: [
        trustRepositoryProvider.overrideWithValue(mockTrustRepo),
        pointsServiceProvider.overrideWithValue(mockPointsService),
        relationshipRepositoryProvider.overrideWithValue(mockRelRepo),
        profileRepositoryProvider.overrideWithValue(MockProfileRepository()),
        pointsRepositoryProvider.overrideWithValue(mockPointsRepo),
        emergencyFundServiceProvider.overrideWithValue(
          _FakeEmergencyFundService(),
        ),
        chatRepositoryProvider.overrideWithValue(_FakeChatRepository()),
      ],
    );

    trustService = container.read(trustServiceProvider);
  });

  /// Stub all common trust repository calls so tests run cleanly.
  void stubDefaults(String userId, {TrustData? existing}) {
    when(mockTrustRepo.getTrustData(any)).thenAnswer((_) async => existing);
    when(mockRelRepo.getRelationships(any)).thenAnswer((_) => Stream.value([]));
    when(mockTrustRepo.getQrExchangeUserIds(any)).thenAnswer((_) async => []);
    when(mockTrustRepo.getVouchesForUser(any)).thenAnswer((_) async => []);
    when(
      mockTrustRepo.getDetailedTrustRatingsForUser(any),
    ).thenAnswer((_) async => []);
    when(
      mockTrustRepo.getAllVerificationsForUser(any),
    ).thenAnswer((_) async => []);
    when(mockTrustRepo.saveTrustData(any)).thenAnswer((_) async {});
    when(
      mockPointsRepo.getCompletedEconomicTransactionCount(any),
    ).thenAnswer((_) async => 0);
  }

  group('HTS Engine – Governance Genesis Milestones', () {
    test(
      'awards 10,000 DSP for Profile milestone when profile is complete',
      () async {
        final userId = 'user-1';
        final profile = _completeProfile(userId);
        final points = UserPoints(
          userId: userId,
          totalPoints: 0,
          availablePoints: 0,
          lastUpdated: DateTime.now(),
          signupDate: DateTime.now(),
          currentStreak: 0,
          dailyMessageCount: 0,
        );

        stubDefaults(userId);

        await trustService.recalculateTrustScore(
          userId: userId,
          profile: profile,
          points: points,
        );

        // The Profile milestone (completedMilestoneFieldCount >= 10) should award 10,000 DSP.
        verify(
          mockPointsService.awardManualPoints(
            userId,
            10000,
            'profile_completion',
          ),
        ).called(1);

        final captured = verify(
          mockTrustRepo.saveTrustData(captureAny),
        ).captured;
        final savedData = captured.first as TrustData;
        expect(savedData.awardedHtsTracking['Profile_dsp_count'], 12);
        expect(savedData.awardedQualificationMilestones, contains('Profile'));
      },
    );

    test(
      'awards 10,000 DSP lump sum upon reaching 10 family connections',
      () async {
        final userId = 'user-1';
        final profile = _completeProfile(userId);
        final points = UserPoints(
          userId: userId,
          totalPoints: 0,
          availablePoints: 0,
          lastUpdated: DateTime.now(),
          signupDate: DateTime.now(),
          currentStreak: 0,
          dailyMessageCount: 0,
        );

        stubDefaults(userId);

        // 10 active family relationships
        when(mockRelRepo.getRelationships(any)).thenAnswer(
          (_) => Stream.value(
            List.generate(10, (i) => _makeRelationship('fam-$i', 'Brother')),
          ),
        );

        await trustService.recalculateTrustScore(
          userId: userId,
          profile: profile,
          points: points,
        );

        // 10 family connections = 10,000 DSP lump sum
        verify(
          mockPointsService.awardManualPoints(
            userId,
            10000,
            'family_connection',
          ),
        ).called(1);

        final captured = verify(
          mockTrustRepo.saveTrustData(captureAny),
        ).captured;
        final savedData = captured.first as TrustData;
        expect(savedData.awardedHtsTracking['Family_dsp_count'], 10);
        expect(savedData.uniqueFamilyCount, 10);
      },
    );

    test(
      'is idempotent: secondary recalculation does not double-award Profile milestone',
      () async {
        final userId = 'user-1';
        final profile = _completeProfile(userId);
        final points = UserPoints(
          userId: userId,
          totalPoints: 10000,
          availablePoints: 0,
          lastUpdated: DateTime.now(),
          signupDate: DateTime.now(),
          currentStreak: 0,
          dailyMessageCount: 0,
        );

        // Existing trust data already has the Profile milestone awarded.
        final existing = TrustData(
          uid: userId,
          lastUpdated: DateTime.now(),
          awardedHtsTracking: {'Profile_dsp_count': 10},
          awardedQualificationMilestones: ['Profile'],
          trustScore: 10.0,
        );

        stubDefaults(userId, existing: existing);

        await trustService.recalculateTrustScore(
          userId: userId,
          profile: profile,
          points: points,
        );

        // Profile milestone should NOT be re-awarded since Profile_dsp_count is already 10.
        verifyNever(
          mockPointsService.awardManualPoints(
            userId,
            any,
            'Governance Genesis: Profile',
          ),
        );
      },
    );

    test(
      'awards 0 DSP incrementally until 10 family connections reached',
      () async {
        final userId = 'user-1';
        final profile = _completeProfile(userId);
        final points = UserPoints(
          userId: userId,
          totalPoints: 0,
          availablePoints: 0,
          lastUpdated: DateTime.now(),
          signupDate: DateTime.now(),
          currentStreak: 0,
          dailyMessageCount: 0,
        );

        stubDefaults(userId);

        // 3 active family relationships (less than threshold of 10)
        when(mockRelRepo.getRelationships(any)).thenAnswer(
          (_) => Stream.value([
            _makeRelationship('fam-1', 'Brother'),
            _makeRelationship('fam-2', 'Sister'),
            _makeRelationship('fam-3', 'Mother'),
          ]),
        );

        await trustService.recalculateTrustScore(
          userId: userId,
          profile: profile,
          points: points,
        );

        // Option B: 0 DSP awarded until full threshold of 10 is reached
        verifyNever(
          mockPointsService.awardManualPoints(userId, any, 'family_connection'),
        );

        final captured = verify(
          mockTrustRepo.saveTrustData(captureAny),
        ).captured;
        final savedData = captured.first as TrustData;
        expect(savedData.uniqueFamilyCount, 3);
      },
    );
  });
}

// Helper to create a simple relationship mock
Relationship _makeRelationship(String id, String type) => Relationship(
  id: id,
  type: type,
  name: 'Test $id',
  createdAt: DateTime.now(),
  status: 'active',
);
