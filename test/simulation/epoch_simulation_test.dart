
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:mockito/mockito.dart';

import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/dsp/services/epoch_service.dart';
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

class FakeFirebaseFunctions extends Fake implements FirebaseFunctions {}

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

    pointsRepository = PointsRepository(fakeFirestore, FakeFirebaseFunctions());
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

  // ──────────────────────────────────────────────────────────────────────────
  // Current TGE Model:
  //   Gate  = DSP-only (minDspRequired = 10,000)
  //   PoCT  = Affects efficiency via decile scale, NOT a gate
  //           efficiency = ceil(trustScore / 10) / 10
  //   Swap  = DSP balance × efficiency
  // ──────────────────────────────────────────────────────────────────────────

  ProfileData testProfile(String userId) => ProfileData(
    uid: userId,
    firstName: 'Test',
    lastName: 'User',
    phone: '+1234567890',
    profileImage: 'https://example.com/avatar.jpg',
    homeCountryCode: 'TZ',
    hostCountryCode: 'US',
    homeLocation: const UserLocation(
      formattedAddress: 'Dar es Salaam, Tanzania',
      placeId: 'tz_1',
      countryCode: 'TZ',
    ),
    hostLocation: const UserLocation(
      formattedAddress: 'New York, USA',
      placeId: 'us_1',
      countryCode: 'US',
    ),
  );

  group('TGE Eligibility (DSP-Only Gate, 10k minimum)', () {
    test('User with >= 10k DSP is eligible regardless of PoCT', () async {
      final userId = 'user_dsp_pass';
      await profileRepository.saveUserProfile(userId, testProfile(userId));

      final pointsService = container.read(pointsServiceProvider);
      await pointsService.awardManualPoints(userId, 10000, 'Grant');

      // Low PoCT should NOT block eligibility:
      await trustRepository.saveTrustData(
        TrustData(uid: userId, trustScore: 5.0, lastUpdated: DateTime.now()),
      );

      final trustService = container.read(trustServiceProvider);
      final isEligible = await trustService.checkUserTgeEligibility(userId, 1);

      expect(isEligible, true, reason: 'DSP >= 10k → eligible (PoCT is not a gate)');
    });

    test('User with < 10k DSP is NOT eligible even with max PoCT', () async {
      final userId = 'user_dsp_fail';
      await profileRepository.saveUserProfile(userId, testProfile(userId));

      final pointsService = container.read(pointsServiceProvider);
      await pointsService.awardManualPoints(userId, 1000, 'Small Grant');

      await trustRepository.saveTrustData(
        TrustData(uid: userId, trustScore: 100.0, lastUpdated: DateTime.now()),
      );

      final trustService = container.read(trustServiceProvider);
      final isEligible = await trustService.checkUserTgeEligibility(userId, 1);

      expect(isEligible, false, reason: '1k DSP < 10k → ineligible');
    });

    test('Epoch parameter has no effect (flat gate across all epochs)', () async {
      final userId = 'user_flat_gate';
      await profileRepository.saveUserProfile(userId, testProfile(userId));

      final pointsService = container.read(pointsServiceProvider);
      await pointsService.awardManualPoints(userId, 10000, 'Grant');

      final trustService = container.read(trustServiceProvider);
      for (int epoch = 1; epoch <= 10; epoch++) {
        final isEligible = await trustService.checkUserTgeEligibility(userId, epoch);
        expect(isEligible, true, reason: 'All epochs use same 10k gate');
      }
    });
  });

  group('Decile PoCT Efficiency (swap rate, NOT a gate)', () {
    test('Efficiency scales with trust score decile', () {
      final epochService = EpochService();

      // Decile table: ceil(score/10) / 10
      expect(epochService.calculateEfficiency(0), 0.0);   // D0: 0%
      expect(epochService.calculateEfficiency(1), 0.1);   // D1: 10%
      expect(epochService.calculateEfficiency(10), 0.1);  // D1: 10%
      expect(epochService.calculateEfficiency(11), 0.2);  // D2: 20%
      expect(epochService.calculateEfficiency(20), 0.2);  // D2: 20%
      expect(epochService.calculateEfficiency(50), 0.5);  // D5: 50%
      expect(epochService.calculateEfficiency(51), 0.6);  // D6: 60%
      expect(epochService.calculateEfficiency(80), 0.8);  // D8: 80%
      expect(epochService.calculateEfficiency(81), 0.9);  // D9: 90%
      expect(epochService.calculateEfficiency(91), 1.0);  // D10: 100%
      expect(epochService.calculateEfficiency(100), 1.0); // D10: 100%
    });

    test('TGE swap = DSP × efficiency', () {
      final epochService = EpochService();

      // 10k DSP, trust 50 → efficiency 50% → 5k tokens
      expect(
        epochService.calculateTGESwap(
          epochNumber: 1,
          currentDspBalance: 10000,
          trustScore: 50,
        ),
        5000.0,
      );

      // 10k DSP, trust 91 → efficiency 100% → 10k tokens
      expect(
        epochService.calculateTGESwap(
          epochNumber: 1,
          currentDspBalance: 10000,
          trustScore: 91,
        ),
        10000.0,
      );

      // 5k DSP → below gate → 0 tokens
      expect(
        epochService.calculateTGESwap(
          epochNumber: 1,
          currentDspBalance: 5000,
          trustScore: 100,
        ),
        0.0,
      );
    });
  });

  group('Treasury Distribution', () {
    test('syncTreasuryBalances distributes correctly for a single user', () async {
      final userId = 'user_treasury';

      await fakeFirestore.collection('users').doc(userId).set({
        'communityMemberships': [
          'global_community',
          'home_continent_africa',
          'home_country_tz',
          'home_city_dar',
          'host_continent_namerica',
          'host_country_us',
          'host_city_nyc',
        ],
      });

      await pointsRepository.initializeUserPoints(userId);
      
      final pointsService = container.read(pointsServiceProvider);
      await pointsService.awardManualPoints(userId, 10000, 'Initial Grant');

      await pointsRepository.syncTreasuryBalances();

      final treasuryStats = await fakeFirestore.collection('system_stats').doc('treasury').get();
      final data = treasuryStats.data()!;

      // 10% each: founders, investors, burn
      expect(data['foundersPoints'], greaterThan(0));
      expect(data['investorsPoints'], greaterThan(0));
      expect(data['burnedPoints'], greaterThan(0));
    });
  });
}
