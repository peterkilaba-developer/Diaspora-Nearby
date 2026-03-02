
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mockito/mockito.dart';

import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/trust/repository/trust_repository.dart';
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/auth/services/session_service.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/trust/models/trust_data.dart';
import 'package:diaspora_nearby/features/shared/models/location.dart';

// Mock Session Service
class MockSessionService extends Mock implements SessionService {
  @override
  Future<void> setUserCached(String uid) async {
    return;
  }
}

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late MockSessionService mockSessionService;
  late ProviderContainer container;

  late PointsRepository pointsRepository;
  late TrustRepository trustRepository;
  late ProfileRepository profileRepository;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    mockSessionService = MockSessionService();

    // Instantiate manually with fake deps
    pointsRepository = PointsRepository(fakeFirestore);
    trustRepository = TrustRepository(fakeFirestore);
    profileRepository = ProfileRepository(fakeFirestore, mockSessionService);

    container = ProviderContainer(
      overrides: [
        pointsRepositoryProvider.overrideWithValue(pointsRepository),
        trustRepositoryProvider.overrideWithValue(trustRepository),
        profileRepositoryProvider.overrideWithValue(profileRepository),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('Epoch 1 Simulation (Target: 10,000 DSP, 50 PoCT)', () {
    test('UserA earns 12,000 DSP -> Triggers Treasury Distribution', () async {
      // 1. Setup UserA (Tanzania)
      final userId = 'user_a';
      final countryCode = 'TZ';
      await profileRepository.saveUserProfile(
        userId,
        ProfileData(
            uid: userId,
            firstName: 'User',
            lastName: 'A',
            phone: '+1234567890',
            profileImage: 'https://example.com/avatar.jpg',
            homeCountryCode: countryCode, 
            hostCountryCode: 'US',
            homeLocation: const UserLocation(formattedAddress: 'Dar es Salaam, Tanzania', placeId: 'tz_1', countryCode: 'TZ'),
            hostLocation: const UserLocation(formattedAddress: 'New York, USA', placeId: 'us_1', countryCode: 'US'),
        ),
      );

      // 2. Simulate UserA Activity: 10 Referrals (1000 each + bonuses likely)
      final pointsService = container.read(pointsServiceProvider);
      
      for (int i = 0; i < 10; i++) {
         await pointsService.awardManualPoints(userId, 1000, 'Referral Bonus');
      }
      // Add check-in for good measure (100)
      await pointsService.awardManualPoints(userId, 100, 'Daily Check-in');
      
      // 3. Verify User Balance
      final userPoints = await pointsRepository.getUserPoints(userId);
      print('UserA Total Points: ${userPoints?.totalPoints}');
      expect(userPoints?.totalPoints, greaterThanOrEqualTo(10000));

      // 4. Trigger Sync 
      await pointsRepository.syncTreasuryBalances();

      // Check Tanzania Treasury
      final countryTreasury = await fakeFirestore.collection('communities').doc('home_country_tz').get();
      final countryPoints = countryTreasury.data()?['points'] ?? 0;
      final countryCumulative = countryTreasury.data()?['cumulativeEarnings'] ?? 0;
      
      print('Tanzania Treasury Points initial: $countryPoints');
      print('Tanzania Cumulative initial: $countryCumulative');

      // 5. Earn MORE to hit milestone
      // We need cumulative distribution of 10,000 to hit 1 milestone.
      // If distribution is (UserTotal / 5), then to get 10,000 distribution, User needs 50,000 Total.
      await pointsService.awardManualPoints(userId, 40000, 'Mega Bonus');
      
      await pointsRepository.syncTreasuryBalances();
      
      final countryTreasury2 = await fakeFirestore.collection('communities').doc('home_country_tz').get();
      final countryPoints2 = countryTreasury2.data()?['points'] ?? 0;
      final countryCumulative2 = countryTreasury2.data()?['cumulativeEarnings'] ?? 0;
      
      print('Tanzania Treasury Points (After 50k): $countryPoints2');
      print('Tanzania Cumulative (After 50k): $countryCumulative2');
      
      // Expectation: 10,000 points visible
      expect(countryPoints2, 10000); 
    });

    test('TGE Eligibility: Standard User', () async {
       final userId = 'user_tge';

       await profileRepository.saveUserProfile(
        userId,
        ProfileData(
            uid: userId,
            firstName: 'TGE',
            lastName: 'User',
            phone: '+1234567890',
            profileImage: 'https://example.com/avatar.jpg',
            homeCountryCode: 'TZ', 
            hostCountryCode: 'US',
            homeLocation: const UserLocation(formattedAddress: 'Dar es Salaam, Tanzania', placeId: 'tz_1', countryCode: 'TZ'),
            hostLocation: const UserLocation(formattedAddress: 'New York, USA', placeId: 'us_1', countryCode: 'US'),
        ),
      );
       
       final pointsService = container.read(pointsServiceProvider);
       await pointsService.awardManualPoints(userId, 10000, 'TGE Grant');
       
       await trustRepository.saveTrustData(TrustData(uid: userId, trustScore: 50.0, lastUpdated: DateTime.now()));
       
       final trustService = container.read(trustServiceProvider);
       final isEligible = await trustService.checkUserTgeEligibility(userId, 1);
       
       print('User is Eligible for Epoch 1: $isEligible');
       expect(isEligible, true);
       
       final isEligible2 = await trustService.checkUserTgeEligibility(userId, 2);
       print('User is Eligible for Epoch 2: $isEligible2');
       expect(isEligible2, false);
    });
  });

  group('Epoch 2-7 Simulations (Escalating Thresholds)', () {
    const userId = 'user_sim_growth';

    setUp(() async {
      // Create a fresh user for this group
       await profileRepository.saveUserProfile(
        userId,
        ProfileData(
            uid: userId,
            firstName: 'Growth',
            lastName: 'User',
            phone: '+1999999999',
            profileImage: 'https://example.com/avatar.jpg',
            homeCountryCode: 'TZ', 
            hostCountryCode: 'US',
            homeLocation: const UserLocation(formattedAddress: 'Dar es Salaam, Tanzania', placeId: 'tz_1', countryCode: 'TZ'),
            hostLocation: const UserLocation(formattedAddress: 'New York, USA', placeId: 'us_1', countryCode: 'US'),
        ),
      );
    });

    test('Epoch 2 Verification (100k DSP, 60 PoCT)', () async {
       final pointsService = container.read(pointsServiceProvider);
       final trustService = container.read(trustServiceProvider);
       
       // Case 1: Insufficient DSP (50k), Sufficient PoCT (60)
       await pointsService.awardManualPoints(userId, 50000, 'Epoch 1 Earnings');
       await trustRepository.saveTrustData(TrustData(uid: userId, trustScore: 60.0, lastUpdated: DateTime.now()));
       
       expect(await trustService.checkUserTgeEligibility(userId, 2), false);
       
       // Case 2: Sufficient DSP (100k), Insufficient PoCT (50)
       await pointsService.awardManualPoints(userId, 50000, 'Epoch 2 Earnings'); // Total 100k
       await trustRepository.saveTrustData(TrustData(uid: userId, trustScore: 50.0, lastUpdated: DateTime.now()));
       
       expect(await trustService.checkUserTgeEligibility(userId, 2), false);

       // Case 3: Sufficient Both
       await trustRepository.saveTrustData(TrustData(uid: userId, trustScore: 60.0, lastUpdated: DateTime.now()));
       expect(await trustService.checkUserTgeEligibility(userId, 2), true);
    });

    test('Epoch 3 Verification (100k DSP, 70 PoCT)', () async {
       final pointsService = container.read(pointsServiceProvider);
       final trustService = container.read(trustServiceProvider);
       
       await pointsService.awardManualPoints(userId, 100000, 'Life Savings');
       await trustRepository.saveTrustData(TrustData(uid: userId, trustScore: 69.0, lastUpdated: DateTime.now()));
       
       expect(await trustService.checkUserTgeEligibility(userId, 3), false);
       
       await trustRepository.saveTrustData(TrustData(uid: userId, trustScore: 70.0, lastUpdated: DateTime.now()));
       expect(await trustService.checkUserTgeEligibility(userId, 3), true);
    });

    test('Epoch 4 Verification (100k DSP, 80 PoCT)', () async {
       final pointsService = container.read(pointsServiceProvider);
       final trustService = container.read(trustServiceProvider);
       
       await pointsService.awardManualPoints(userId, 100000, 'Life Savings');
       await trustRepository.saveTrustData(TrustData(uid: userId, trustScore: 79.9, lastUpdated: DateTime.now()));
       
       expect(await trustService.checkUserTgeEligibility(userId, 4), false);
       
       await trustRepository.saveTrustData(TrustData(uid: userId, trustScore: 80.0, lastUpdated: DateTime.now()));
       expect(await trustService.checkUserTgeEligibility(userId, 4), true);
    });

    test('Epoch 5 Verification (100k DSP, 90 PoCT)', () async {
       final pointsService = container.read(pointsServiceProvider);
       final trustService = container.read(trustServiceProvider);
       
       await pointsService.awardManualPoints(userId, 100000, 'Life Savings');
       await trustRepository.saveTrustData(TrustData(uid: userId, trustScore: 89.9, lastUpdated: DateTime.now()));
       
       expect(await trustService.checkUserTgeEligibility(userId, 5), false);
       
       await trustRepository.saveTrustData(TrustData(uid: userId, trustScore: 90.0, lastUpdated: DateTime.now()));
       expect(await trustService.checkUserTgeEligibility(userId, 5), true);
    });
    
    test('Epoch 6 Verification (100k DSP, 95 PoCT)', () async {
       final pointsService = container.read(pointsServiceProvider);
       final trustService = container.read(trustServiceProvider);
       
       await pointsService.awardManualPoints(userId, 100000, 'Life Savings');
       await trustRepository.saveTrustData(TrustData(uid: userId, trustScore: 94.9, lastUpdated: DateTime.now()));
       
       expect(await trustService.checkUserTgeEligibility(userId, 6), false);
       
       await trustRepository.saveTrustData(TrustData(uid: userId, trustScore: 95.0, lastUpdated: DateTime.now()));
       expect(await trustService.checkUserTgeEligibility(userId, 6), true);
    });

    test('Epoch 7 Verification (100k DSP, 100 PoCT - Pillar Status)', () async {
       final pointsService = container.read(pointsServiceProvider);
       final trustService = container.read(trustServiceProvider);
       
       await pointsService.awardManualPoints(userId, 100000, 'Life Savings');
       
       // Max Trust Score is 100
       await trustRepository.saveTrustData(TrustData(uid: userId, trustScore: 99.0, lastUpdated: DateTime.now()));
       expect(await trustService.checkUserTgeEligibility(userId, 7), false);
       
       await trustRepository.saveTrustData(TrustData(uid: userId, trustScore: 100.0, lastUpdated: DateTime.now()));
       expect(await trustService.checkUserTgeEligibility(userId, 7), true);
    });
  });
}
