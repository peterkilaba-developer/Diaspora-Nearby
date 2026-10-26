import 'package:flutter_test/flutter_test.dart';
import 'package:diaspora_nearby/features/dsp/models/user_points.dart';
import 'package:diaspora_nearby/features/chat/utils/community_chat_utils.dart';

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
      'tdeHistory': [
        {
          'epoch': 1,
          'tdeNumber': 1,
          'amount': 100.0,
          'efficiency': 1.0,
          'date': now.toIso8601String(),
        },
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
      expect(userPoints.tdeHistory.length, 1);
      expect(userPoints.tdeHistory.first.amount, 100.0);
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
      expect(map['tdeHistory'].length, 1);
    });

    test('copyWith should update specified fields', () {
      final userPoints = UserPoints.fromMap(userPointsMap);
      final updated = userPoints.copyWith(totalPoints: 1200, currentStreak: 6);

      expect(updated.totalPoints, 1200);
      expect(updated.currentStreak, 6);
      expect(updated.userId, userPoints.userId); // Unchanged
    });

    test(
      'fromMap should fallback to legacy tgeHistory and 0-indexed tgeNumber',
      () {
        final legacyMap = {
          ...userPointsMap,
          'tdeHistory': null,
          'tgeHistory': [
            {
              'epoch': 1,
              'tgeNumber': 0,
              'amount': 250.0,
              'efficiency': 0.85,
              'date': now.toIso8601String(),
            },
          ],
        };
        final parsed = UserPoints.fromMap(legacyMap);
        expect(parsed.tdeHistory.length, 1);
        expect(parsed.tdeHistory.first.epoch, 1);
        expect(parsed.tdeHistory.first.tdeNumber, 1);
        expect(parsed.tdeHistory.first.amount, 250.0);
        expect(parsed.tdeHistory.first.efficiency, 0.85);
      },
    );
  });

  group('CommunityChatUtils Unified Naming Source of Truth', () {
    test('cleanBasePlaceName strips all community and treasury suffixes', () {
      expect(
        CommunityChatUtils.cleanBasePlaceName(
          'African Sovereign Bond Treasury',
        ),
        'African',
      );
      expect(
        CommunityChatUtils.cleanBasePlaceName('Africa Continental Treasury'),
        'Africa',
      );
      expect(
        CommunityChatUtils.cleanBasePlaceName(
          'Iowa Community Reserve Treasury',
        ),
        'Iowa',
      );
      expect(
        CommunityChatUtils.cleanBasePlaceName(
          'Tanzania Community DDI Treasury',
        ),
        'Tanzania',
      );
    });

    test('generateTreasuryTitle produces unified names across all tiers', () {
      // Home Continent -> Adjective Sovereign Bond Treasury
      expect(
        CommunityChatUtils.generateTreasuryTitle(
          name: 'African Sovereign Bond Treasury',
          type: 'continent',
          locationType: 'home',
          id: 'home_continent_africa',
        ),
        'African Sovereign Bond Treasury',
      );

      // Host Continent -> Noun Sovereign Bond Treasury
      expect(
        CommunityChatUtils.generateTreasuryTitle(
          name: 'North America Community',
          type: 'continent',
          locationType: 'host',
          id: 'host_continent_north-america_tz',
        ),
        'North America Sovereign Bond Treasury',
      );

      // State -> Reserve Treasury without duplicate "Community"
      expect(
        CommunityChatUtils.generateTreasuryTitle(
          name: 'Iowa Community',
          type: 'state',
          locationType: 'host',
          id: 'host_state_us_iowa_tz',
        ),
        'Iowa Reserve Treasury',
      );

      // Country & City -> DDI Treasury without duplicate "Community"
      expect(
        CommunityChatUtils.generateTreasuryTitle(
          name: 'Tanzania Community',
          type: 'country',
          locationType: 'home',
          id: 'home_country_tz',
        ),
        'Tanzania DDI Treasury',
      );
      expect(
        CommunityChatUtils.generateTreasuryTitle(
          name: 'Dar es Salaam Community',
          type: 'city',
          locationType: 'home',
          id: 'home_city_tz_no-state_dar-es-salaam',
        ),
        'Dar es Salaam DDI Treasury',
      );

      // System Treasuries
      expect(
        CommunityChatUtils.generateTreasuryTitle(unitId: 'global_community'),
        'Global Reserve',
      );
      expect(
        CommunityChatUtils.generateTreasuryTitle(unitId: 'founders'),
        'Founders & Core Team',
      );
      expect(
        CommunityChatUtils.generateTreasuryTitle(unitId: 'liquidity'),
        'Liquidity Treasury',
      );
      expect(
        CommunityChatUtils.generateTreasuryTitle(unitId: 'burn'),
        'Natural Burn Pool',
      );
    });

    test('normalizeContinentName handles treasury suffixes and adjectives', () {
      expect(
        CommunityChatUtils.normalizeContinentName(
          'African Sovereign Bond Treasury',
        ),
        'africa',
      );
      expect(
        CommunityChatUtils.normalizeContinentName('North American Community'),
        'north america',
      );
    });

    test(
      'generateTreasurySubtitle and generateTreasuryRoleLabel use Funding Sovereign Bond Engine for continents',
      () {
        expect(
          CommunityChatUtils.generateTreasuryRoleLabel(
            type: 'continent',
            id: 'home_continent_africa',
          ),
          'Funding Sovereign Bond Engine',
        );
        expect(
          CommunityChatUtils.generateTreasurySubtitle(
            type: 'continent',
            id: 'host_continent_north-america_tz',
          ),
          'Funding Sovereign Bond Engine · 10% Ubuntu community match',
        );
        expect(
          CommunityChatUtils.generateTreasuryRoleLabel(
            type: 'state',
            id: 'host_state_us_iowa_tz',
          ),
          'State liquidity reserve & loan backstop',
        );
      },
    );
  });
}
