
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
import 'package:flutter_riverpod/flutter_riverpod.dart';

@GenerateMocks([
  TrustRepository,
  PointsService,
  RelationshipRepository,
  ProfileRepository,
  PointsRepository,
])
import 'hts_ledger_test.mocks.dart';

void main() {
  late TrustService trustService;
  late MockTrustRepository mockTrustRepo;
  late MockPointsService mockPointsService;
  late MockRelationshipRepository mockRelRepo;
  late ProviderContainer container;

  setUp(() {
    mockTrustRepo = MockTrustRepository();
    mockPointsService = MockPointsService();
    mockRelRepo = MockRelationshipRepository();

    container = ProviderContainer(
      overrides: [
        trustRepositoryProvider.overrideWithValue(mockTrustRepo),
        pointsServiceProvider.overrideWithValue(mockPointsService),
        relationshipRepositoryProvider.overrideWithValue(mockRelRepo),
        profileRepositoryProvider.overrideWithValue(MockProfileRepository()),
        pointsRepositoryProvider.overrideWithValue(MockPointsRepository()),
      ],
    );

    trustService = container.read(trustServiceProvider);
  });

  group('HTS Engine - 1-per-10 Logic', () {
    test('awards 1 PoCT and 10k DSP when count reaches 10', () async {
      final userId = 'user-1';
      final profile = ProfileData(
        uid: userId, 
        firstName: 'A', 
        lastName: 'B', 
        phone: '1', 
        profileImage: '', 
        homeLocation: const UserLocation(formattedAddress: 'A', placeId: 'B'), 
        hostLocation: const UserLocation(formattedAddress: 'A', placeId: 'B'),
        // Ensure profile is complete to avoid exclusion (though syncMetric is called regardless in HTS section)
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
        education: [Education(institution: 'Uni', degree: 'CS', graduationYear: '2020')],
      );
      final points = UserPoints(userId: userId, totalPoints: 0, availablePoints: 0, lastUpdated: DateTime.now(), signupDate: DateTime.now(), currentStreak: 0, dailyMessageCount: 0);

      final trustDataOld = TrustData(
        uid: userId, 
        lastUpdated: DateTime.now(),
        referralCount: 10,
        awardedHtsTracking: {},
      );

      when(mockTrustRepo.getTrustData(any)).thenAnswer((_) async => trustDataOld);
      when(mockRelRepo.getRelationships(any)).thenAnswer((_) => Stream.value([]));
      when(mockTrustRepo.getQrExchangeUserIds(any)).thenAnswer((_) async => []);
      when(mockTrustRepo.getVouchesForUser(any)).thenAnswer((_) async => []);
      when(mockTrustRepo.getDetailedTrustRatingsForUser(any)).thenAnswer((_) async => []);
      when(mockTrustRepo.getAllVerificationsForUser(any)).thenAnswer((_) async => []);

      await trustService.recalculateTrustScore(userId: userId, profile: profile, points: points);

      // Verify DSP award was called once for 10k
      verify(mockPointsService.awardManualPoints(userId, 10000, any)).called(1);

      final captured = verify(mockTrustRepo.saveTrustData(captureAny)).captured;
      final savedData = captured.first as TrustData;

      expect(savedData.awardedHtsTracking['referrals'], 1);
    });

    test('is idempotent: secondary recalculation does not double award', () async {
       final userId = 'user-1';
       final profile = ProfileData(
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
         education: [Education(institution: 'Uni', degree: 'CS', graduationYear: '2020')],
       );
       final points = UserPoints(userId: userId, totalPoints: 10000, availablePoints: 0, lastUpdated: DateTime.now(), signupDate: DateTime.now(), currentStreak: 0, dailyMessageCount: 0);

       final trustDataOld = TrustData(
         uid: userId, 
         lastUpdated: DateTime.now(),
         referralCount: 10,
         awardedHtsTracking: {'referrals': 1},
         trustScore: 1.0,
       );

       when(mockTrustRepo.getTrustData(any)).thenAnswer((_) async => trustDataOld);
       when(mockRelRepo.getRelationships(any)).thenAnswer((_) => Stream.value([]));
       when(mockTrustRepo.getQrExchangeUserIds(any)).thenAnswer((_) async => []);
       when(mockTrustRepo.getVouchesForUser(any)).thenAnswer((_) async => []);
       when(mockTrustRepo.getDetailedTrustRatingsForUser(any)).thenAnswer((_) async => []);
       when(mockTrustRepo.getAllVerificationsForUser(any)).thenAnswer((_) async => []);

       await trustService.recalculateTrustScore(userId: userId, profile: profile, points: points);

       verifyNever(mockPointsService.awardManualPoints(userId, any, any));
    });

    test('awards multiple points if count jumps (e.g. from 0 to 25)', () async {
       final userId = 'user-1';
       final profile = ProfileData(
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
         education: [Education(institution: 'Uni', degree: 'CS', graduationYear: '2020')],
       );
       final points = UserPoints(userId: userId, totalPoints: 0, availablePoints: 0, lastUpdated: DateTime.now(), signupDate: DateTime.now(), currentStreak: 0, dailyMessageCount: 0);

       final trustDataOld = TrustData(
         uid: userId, 
         lastUpdated: DateTime.now(),
         referralCount: 25,
         awardedHtsTracking: {},
       );

       when(mockTrustRepo.getTrustData(any)).thenAnswer((_) async => trustDataOld);
       when(mockRelRepo.getRelationships(any)).thenAnswer((_) => Stream.value([]));
       when(mockTrustRepo.getQrExchangeUserIds(any)).thenAnswer((_) async => []);
       when(mockTrustRepo.getVouchesForUser(any)).thenAnswer((_) async => []);
       when(mockTrustRepo.getDetailedTrustRatingsForUser(any)).thenAnswer((_) async => []);
       when(mockTrustRepo.getAllVerificationsForUser(any)).thenAnswer((_) async => []);

       await trustService.recalculateTrustScore(userId: userId, profile: profile, points: points);

       // Jump from 0 to 25 means 2 units (20 referrals).
       // 2 * 10k = 20k.
       verify(mockPointsService.awardManualPoints(userId, 20000, any)).called(1);

       final captured = verify(mockTrustRepo.saveTrustData(captureAny)).captured;
       final savedData = captured.first as TrustData;
       expect(savedData.awardedHtsTracking['referrals'], 2);
    });
  });
}
