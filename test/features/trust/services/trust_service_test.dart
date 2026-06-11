import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';
import 'package:diaspora_nearby/features/trust/repository/trust_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/relationship_repository.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import 'package:diaspora_nearby/features/trust/models/trust_data.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/dsp/models/user_points.dart';
import 'package:diaspora_nearby/features/profile/models/relationship.dart';
import 'package:diaspora_nearby/features/shared/models/location.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/chat/repository/report_repository.dart';
import 'package:diaspora_nearby/features/dsp/services/emergency_fund_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Generate Mocks
@GenerateNiceMocks([
  MockSpec<TrustRepository>(),
  MockSpec<ProfileRepository>(),
  MockSpec<RelationshipRepository>(),
  MockSpec<PointsRepository>(),
  MockSpec<ReportRepository>(),
])
import 'trust_service_test.mocks.dart';

class FakeEmergencyFundService extends Fake implements EmergencyFundService {
  final Set<String> stakers = {};

  @override
  Future<bool> hasStaked(String userId) async => stakers.contains(userId);
}

class FakeChatRepository extends Fake implements ChatRepository {
  final Set<String> largeGroupAdmins = {};

  @override
  Future<bool> isAdminOfLargeGroupChat(
    String uid, {
    int minMembers = 100,
  }) async => largeGroupAdmins.contains(uid);
}

void main() {
  provideDummy<TrustRepository>(MockTrustRepository());
  provideDummy<RelationshipRepository>(MockRelationshipRepository());
  provideDummy<PointsRepository>(MockPointsRepository());

  late TrustService trustService;
  late MockTrustRepository mockTrustRepo;
  late MockProfileRepository mockProfileRepo;
  late MockRelationshipRepository mockRelRepo;
  late MockPointsRepository mockPointsRepo;
  late MockReportRepository mockReportRepo;
  late FakeChatRepository fakeChatRepo;
  late FakeEmergencyFundService fakeEmergencyFundService;
  late ProviderContainer container;

  setUp(() {
    mockTrustRepo = MockTrustRepository();
    mockProfileRepo = MockProfileRepository();
    mockRelRepo = MockRelationshipRepository();
    mockPointsRepo = MockPointsRepository();
    mockReportRepo = MockReportRepository();
    fakeChatRepo = FakeChatRepository();
    fakeEmergencyFundService = FakeEmergencyFundService();

    container = ProviderContainer(
      overrides: [
        trustRepositoryProvider.overrideWithValue(mockTrustRepo),
        profileRepositoryProvider.overrideWithValue(mockProfileRepo),
        relationshipRepositoryProvider.overrideWithValue(mockRelRepo),
        pointsRepositoryProvider.overrideWithValue(mockPointsRepo),
        reportRepositoryProvider.overrideWithValue(mockReportRepo),
        emergencyFundServiceProvider.overrideWithValue(
          fakeEmergencyFundService,
        ),
        chatRepositoryProvider.overrideWithValue(fakeChatRepo),
      ],
    );

    // The real PointsService calls getUserPoints via _addPoints when
    // milestone awards fire. Stub to return a valid UserPoints.
    when(mockPointsRepo.getUserPoints(any)).thenAnswer(
      (_) async => UserPoints(
        userId: 'stub',
        totalPoints: 0,
        availablePoints: 0,
        lastUpdated: DateTime.now(),
        signupDate: DateTime.now(),
        currentStreak: 0,
        dailyMessageCount: 0,
      ),
    );

    when(
      mockPointsRepo.getCompletedEconomicTransactionCount(any),
    ).thenAnswer((_) async => 0);

    trustService = container.read(trustServiceProvider);
  });

  group('TrustService - Council Eligibility', () {
    test('calculates council eligibility correctly', () async {
      final userId = 'user-1';
      fakeChatRepo.largeGroupAdmins.add(userId);
      fakeEmergencyFundService.stakers.add(userId);

      // 1. Mock Profile (Complete)
      final profile = ProfileData(
        uid: userId,
        firstName: 'Test',
        lastName: 'User',
        profileImage: 'url',
        bio: 'Bio',
        occupation: 'Dev',
        education: [
          Education(
            degree: 'Degree',
            institution: 'Uni',
            graduationYear: '2020',
          ),
        ],
        yearsInHostCountry: '5',
        industry: ['Tech'],
        profession: ['Coder'],
        languages: ['English'],
        meetingPreferences: ['Online'],
        availability: ['Weekends'],
        servicesOffered: ['Coding'],
        lookingFor: ['Networking'],
        interests: ['Technology'],
        homeLocation: const UserLocation(
          city: 'Home',
          country: 'Country',
          formattedAddress: 'Home Addr',
          placeId: 'home-id',
          countryCode: 'US',
        ),
        hostLocation: const UserLocation(
          city: 'Host',
          country: 'Country',
          formattedAddress: 'Host Addr',
          placeId: 'host-id',
          countryCode: 'US',
        ),
        currentLocation: CurrentLocation(
          formattedAddress: 'Host Addr',
          placeId: 'host-id',
          geometry: const UserLocationGeometry(
            location: UserLocationCoordinates(lat: 0, lng: 0),
          ),
          city: 'Host',
          countryCode: 'US',
          timestamp: 1,
        ),
        phone: '1234567890',
        showCurrentLocationName: true, // +10 PoCT transparency
        createdAt: DateTime.now().subtract(const Duration(days: 200)),
      );

      // 2. Mock Points
      final points = UserPoints(
        userId: userId,
        totalPoints: 100,
        availablePoints: 50,
        lastUpdated: DateTime.now(),
        signupDate: DateTime.now(),
        currentStreak: 0,
        dailyMessageCount: 0,
      );

      // 3. Mock Repositories
      // Relationships: 10 Family members + 10 Friends
      final relationships = [
        ...List.generate(
          10,
          (i) => Relationship(
            id: 'family-$i',
            type: 'Brother',
            name: 'Fam $i',
            createdAt: DateTime.now(),
            status: 'active',
          ),
        ),
        ...List.generate(
          10,
          (i) => Relationship(
            id: 'friend-$i',
            type: 'Friend',
            name: 'Friend $i',
            createdAt: DateTime.now(),
            status: 'active',
          ),
        ),
      ];
      when(
        mockRelRepo.getRelationships(userId),
      ).thenAnswer((_) => Stream.value(relationships));

      // QR Exchanges: 10 Non-Family users
      final qrIds = List.generate(
        10,
        (i) => 'qr-$i',
      ); // Distinct from family-$i
      when(
        mockTrustRepo.getQrExchangeUserIds(userId),
      ).thenAnswer((_) async => qrIds);

      // Vouches (Ratings): 10 Non-Family/Non-QR users with score 100
      final ratings = List.generate(
        10,
        (i) => {'fromUserId': 'vouch-$i', 'toUserId': userId, 'score': 100.0},
      );
      when(
        mockTrustRepo.getDetailedTrustRatingsForUser(userId),
      ).thenAnswer((_) async => ratings);
      when(
        mockTrustRepo.getVouchesForUser(userId),
      ).thenAnswer((_) async => []); // Regular vouches empty
      // Old trust data with 10 event check-ins (+10 PoCT participation)
      when(mockTrustRepo.getTrustData(userId)).thenAnswer(
        (_) async => TrustData(
          uid: userId,
          trustScore: 0,
          verifiedCheckInCount: 10,
          lastUpdated: DateTime.now(),
        ),
      );

      // Mock Report counts etc
      // ... (Stubbing other repo calls to avoid null errors)
      when(
        mockTrustRepo.getVouchesByVoucher(userId),
      ).thenAnswer((_) async => []);
      // 10 verifications (+10 PoCT verified milestone)
      when(mockTrustRepo.getAllVerificationsForUser(userId)).thenAnswer(
        (_) async => List.generate(
          10,
          (i) => {'fromUserId': 'verifier-$i', 'toUserId': userId},
        ),
      );

      // 4. Act
      await trustService.recalculateTrustScore(
        userId: userId,
        profile: profile,
        points: points,
      );

      // 5. Assert
      // Verify saveTrustData was called with isCouncilEligible = true
      final captured = verify(mockTrustRepo.saveTrustData(captureAny)).captured;
      final savedData = captured.first as TrustData;

      expect(savedData.uniqueFamilyCount, 10);
      expect(savedData.uniqueQrCount, 10);
      expect(savedData.uniqueVouchCount, 10);
      expect(savedData.isCouncilEligible, true);
    });

    test('fails eligibility if one condition not met', () async {
      final userId = 'user-2';
      // Profile Incomplete
      final profile = ProfileData(
        uid: userId,
        firstName: 'Incomplete',
        lastName: 'User',
        phone: '1234567890',
        profileImage:
            'url', // Added to satisfy required parameter, but incomplete fields below imply tests still valid for other missing fields?
        // Actually, failing eligibility requires ONE missing field or count.
        // Let's make it incomplete by missing Bio etc.
        homeLocation: const UserLocation(formattedAddress: 'A', placeId: 'B'),
        hostLocation: const UserLocation(formattedAddress: 'A', placeId: 'B'),
      );
      final points = UserPoints(
        userId: userId,
        totalPoints: 100,
        availablePoints: 50,
        lastUpdated: DateTime.now(),
        signupDate: DateTime.now(),
        currentStreak: 0,
        dailyMessageCount: 0,
      );

      when(
        mockRelRepo.getRelationships(userId),
      ).thenAnswer((_) => Stream.value([]));
      when(
        mockTrustRepo.getQrExchangeUserIds(userId),
      ).thenAnswer((_) async => []);
      when(
        mockTrustRepo.getDetailedTrustRatingsForUser(userId),
      ).thenAnswer((_) async => []);
      when(mockTrustRepo.getVouchesForUser(userId)).thenAnswer((_) async => []);
      when(mockTrustRepo.getTrustData(userId)).thenAnswer((_) async => null);
      when(
        mockTrustRepo.getVouchesByVoucher(userId),
      ).thenAnswer((_) async => []);
      when(
        mockTrustRepo.getAllVerificationsForUser(userId),
      ).thenAnswer((_) async => []);

      await trustService.recalculateTrustScore(
        userId: userId,
        profile: profile,
        points: points,
      );

      final captured = verify(mockTrustRepo.saveTrustData(captureAny)).captured;
      final savedData = captured.first as TrustData;

      expect(savedData.isCouncilEligible, false);
    });
  });
}
