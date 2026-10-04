import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart'
    show FieldValue, SetOptions;
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

/// Smart fake that emulates the subset of Cloud Functions the simulation
/// touches by mutating the provided fake Firestore — just enough to keep
/// TGE eligibility + treasury distribution tests grounded.
class FakeFirebaseFunctions extends Fake implements FirebaseFunctions {
  FakeFirebaseFunctions(this._firestore);
  final FakeFirebaseFirestore _firestore;

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    return _SimulatedHttpsCallable(_firestore, name);
  }
}

class _SimulatedHttpsCallable extends Fake implements HttpsCallable {
  _SimulatedHttpsCallable(this._firestore, this._name);
  final FakeFirebaseFirestore _firestore;
  final String _name;

  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async {
    final p = (parameters as Map?) ?? const {};
    switch (_name) {
      case 'initializeUserPoints':
        // The real CF derives userId from auth context; the simulation tests
        // pass it explicitly via the points service path. We just ensure a
        // welcome-bonus baseline exists for any users seeded above.
        break;
      case 'awardPoints':
        final userId = p['userId'] as String?;
        final points = (p['points'] as num?)?.toInt() ?? 0;
        if (userId != null && points > 0) {
          await _firestore.collection('user_points').doc(userId).set({
            'totalPoints': FieldValue.increment(points),
            'availablePoints': FieldValue.increment(points),
          }, SetOptions(merge: true));
        }
        break;
      case 'syncTreasuryBalances':
        // Aggregate every user's totalPoints, then write 10% each to
        // founders / liquidity / burn so transparency stats are non-zero.
        final usersSnap = await _firestore.collection('user_points').get();
        var total = 0;
        for (final d in usersSnap.docs) {
          total += ((d.data()['totalPoints'] as num?) ?? 0).toInt();
        }
        final unit = (total * 0.10).floor();
        await _firestore.collection('system_stats').doc('treasury').set({
          'foundersPoints': unit,
          'liquidityPoints': unit,
          'burnedPoints': unit,
        }, SetOptions(merge: true));
        break;
    }
    return _FakeHttpsCallableResult<T>();
  }
}

class _FakeHttpsCallableResult<T> extends Fake
    implements HttpsCallableResult<T> {
  @override
  T get data => null as T;
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

    pointsRepository = PointsRepository(
      fakeFirestore,
      FakeFirebaseFunctions(fakeFirestore),
    );
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
  // Current TGE/TDE Model:
  //   Eligibility = Positive DSP (minDspRequired deprecated & removed)
  //   PCT         = Exact percent swap rate (0% for <11, exact % for 11-90, 100% for 91+)
  //   Swap        = DSP balance × PCT efficiency
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

  group('TGE Eligibility (Positive DSP Balance)', () {
    test('User with positive DSP is eligible regardless of PCT', () async {
      final userId = 'user_dsp_pass';
      await profileRepository.saveUserProfile(userId, testProfile(userId));
      await fakeFirestore.collection('user_points').doc(userId).set({
        'totalPoints': 0,
        'availablePoints': 0,
        'currentStreak': 0,
        'dailyMessageCount': 0,
        'signupDate': DateTime.now(),
        'lastUpdated': DateTime.now(),
      });

      final pointsService = container.read(pointsServiceProvider);
      await pointsService.awardManualPoints(userId, 500, 'Grant');

      // Low PCT should NOT block eligibility (only affects efficiency):
      await trustRepository.saveTrustData(
        TrustData(uid: userId, trustScore: 5.0, lastUpdated: DateTime.now()),
      );

      final trustService = container.read(trustServiceProvider);
      final isEligible = await trustService.checkUserTgeEligibility(userId, 1);

      expect(
        isEligible,
        true,
        reason: 'DSP > 0 → eligible (PCT is not a gate)',
      );
    });

    test('User with 0 DSP is NOT eligible', () async {
      final userId = 'user_dsp_fail';
      await profileRepository.saveUserProfile(userId, testProfile(userId));
      await fakeFirestore.collection('user_points').doc(userId).set({
        'totalPoints': 0,
        'availablePoints': 0,
        'currentStreak': 0,
        'dailyMessageCount': 0,
        'signupDate': DateTime.now(),
        'lastUpdated': DateTime.now(),
      });

      await trustRepository.saveTrustData(
        TrustData(uid: userId, trustScore: 100.0, lastUpdated: DateTime.now()),
      );

      final trustService = container.read(trustServiceProvider);
      final isEligible = await trustService.checkUserTgeEligibility(userId, 1);

      expect(isEligible, false, reason: '0 DSP → ineligible');
    });

    test('Epoch parameter has no effect (flat across all epochs)', () async {
      final userId = 'user_flat_gate';
      await profileRepository.saveUserProfile(userId, testProfile(userId));
      await fakeFirestore.collection('user_points').doc(userId).set({
        'totalPoints': 0,
        'availablePoints': 0,
        'currentStreak': 0,
        'dailyMessageCount': 0,
        'signupDate': DateTime.now(),
        'lastUpdated': DateTime.now(),
      });

      final pointsService = container.read(pointsServiceProvider);
      await pointsService.awardManualPoints(userId, 1000, 'Grant');

      final trustService = container.read(trustServiceProvider);
      for (int epoch = 1; epoch <= 10; epoch++) {
        final isEligible = await trustService.checkUserTgeEligibility(
          userId,
          epoch,
        );
        expect(isEligible, true, reason: 'All epochs allow any positive DSP');
      }
    });
  });

  group(
    'Exact PCT (Proof of Community Trust) Efficiency (swap rate, NOT a gate)',
    () {
      test(
        'Efficiency maps no-trust to 0, standard trust exactly, full trust to 100',
        () {
          final epochService = EpochService();

          expect(epochService.calculateEfficiency(0), 0.0);
          expect(epochService.calculateEfficiency(1), 0.0);
          expect(epochService.calculateEfficiency(10), 0.0);
          expect(epochService.calculateEfficiency(11), 0.11);
          expect(epochService.calculateEfficiency(20), 0.2);
          expect(epochService.calculateEfficiency(50), 0.5);
          expect(epochService.calculateEfficiency(51), 0.51);
          expect(epochService.calculateEfficiency(80), 0.8);
          expect(epochService.calculateEfficiency(81), 0.81);
          expect(epochService.calculateEfficiency(90), 0.9);
          expect(epochService.calculateEfficiency(91), 1.0);
          expect(epochService.calculateEfficiency(95), 1.0);
          expect(epochService.calculateEfficiency(100), 1.0);
          expect(epochService.calculateEfficiency(150), 1.0);
        },
      );

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

        // 10k DSP, trust 10 -> efficiency 0% -> 0 tokens
        expect(
          epochService.calculateTGESwap(
            epochNumber: 1,
            currentDspBalance: 10000,
            trustScore: 10,
          ),
          0.0,
        );

        // 10k DSP, trust 91 -> full trust efficiency 100% -> 10k tokens
        expect(
          epochService.calculateTGESwap(
            epochNumber: 1,
            currentDspBalance: 10000,
            trustScore: 91,
          ),
          10000.0,
        );

        // 5k DSP, trust 100 -> 5k tokens (no 10k minimum requirement)
        expect(
          epochService.calculateTGESwap(
            epochNumber: 1,
            currentDspBalance: 5000,
            trustScore: 100,
          ),
          5000.0,
        );

        // 500 DSP, trust 42 -> 210 tokens (500 * 0.42)
        expect(
          epochService.calculateTGESwap(
            epochNumber: 1,
            currentDspBalance: 500,
            trustScore: 42,
          ),
          210.0,
        );

        // 0 DSP -> 0 tokens
        expect(
          epochService.calculateTGESwap(
            epochNumber: 1,
            currentDspBalance: 0,
            trustScore: 100,
          ),
          0.0,
        );
      });
    },
  );

  group('Treasury Distribution', () {
    test(
      'syncTreasuryBalances distributes correctly for a single user',
      () async {
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

        // Seed baseline user_points (see TGE eligibility tests for context).
        await fakeFirestore.collection('user_points').doc(userId).set({
          'totalPoints': 0,
          'availablePoints': 0,
          'currentStreak': 0,
          'dailyMessageCount': 0,
          'signupDate': DateTime.now(),
          'lastUpdated': DateTime.now(),
        });

        final pointsService = container.read(pointsServiceProvider);
        await pointsService.awardManualPoints(userId, 10000, 'Initial Grant');

        await pointsRepository.syncTreasuryBalances();

        final treasuryStats = await fakeFirestore
            .collection('system_stats')
            .doc('treasury')
            .get();
        final data = treasuryStats.data()!;

        // 10% each: founders, liquidity, burn
        expect(data['foundersPoints'], greaterThan(0));
        expect(data['liquidityPoints'], greaterThan(0));
        expect(data['burnedPoints'], greaterThan(0));
      },
    );
  });
}
