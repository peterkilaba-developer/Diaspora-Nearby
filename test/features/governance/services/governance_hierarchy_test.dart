import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/governance/services/governance_service.dart';
import 'package:diaspora_nearby/features/governance/repository/governance_repository.dart';
import 'package:diaspora_nearby/features/community/repository/community_repository.dart';
import 'package:diaspora_nearby/features/governance/models/governance_unit.dart';
import 'package:diaspora_nearby/features/community/models/community_data.dart'; // [FIX] Updated import

// --- Fakes ---

class FakeGovernanceRepository implements GovernanceRepository {
  final Map<String, List<GovernanceUnit>> userMemberships = {};
  
  void setUserMemberships(String userId, List<GovernanceUnit> units) {
    userMemberships[userId] = units;
  }

  @override
  Future<List<GovernanceUnit>> getGovernanceUnitsForUser(String userId) async {
    return userMemberships[userId] ?? [];
  }

  @override
  Future<GovernanceUnit?> getGovernanceUnit(String id) async => null; // Stub

  // Stubs for other members to satisfy interface
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCommunityRepository implements CommunityRepository {
  final Map<String, Community> communities = {};

  void setCommunity(Community community) {
    communities[community.id] = community;
  }

  @override
  Future<Community?> getCommunity(String id) async {
    return communities[id];
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// --- Test ---

void main() {
  late FakeGovernanceRepository mockGovRepo;
  late FakeCommunityRepository mockCommRepo;
  late ProviderContainer container;
  late GovernanceService service;

  setUp(() {
    mockGovRepo = FakeGovernanceRepository();
    mockCommRepo = FakeCommunityRepository();
    
    container = ProviderContainer(
      overrides: [
        governanceRepositoryProvider.overrideWithValue(mockGovRepo),
        communityRepositoryProvider.overrideWithValue(mockCommRepo),
        // We might need to override trustRepo/pointsRepo if service init reads them eagerly?
        // GovernanceService constructs with Ref, but doesn't read until method call.
      ],
    );
    
    service = container.read(governanceServiceProvider);
  });

  tearDown(() {
    container.dispose();
  });

  group('shouldPromoteToHigherCouncil', () {
    const userId = 'user_123';

    test('returns true for Local level target immediately', () async {
      final target = GovernanceUnit(
        id: 'local_unit',
        name: 'Local Unit',
        level: GovernanceLevel.local,
        type: GovernanceType.local,
      );

      final result = await service.shouldPromoteToHigherCouncil(userId, target);
      expect(result, isTrue);
    });

    test('returns false if user has no memberships for State target', () async {
       final target = GovernanceUnit(
        id: 'state_unit',
        name: 'State Unit',
        level: GovernanceLevel.state,
        type: GovernanceType.state,
      );
      
      final result = await service.shouldPromoteToHigherCouncil(userId, target);
      expect(result, isFalse);
    });

    test('returns true if user is Local Council member in same State', () async {
      // 1. Setup Communities
      final stateId = 'state_comm_id';
      final localId = 'local_comm_id';

      // Target (State) Community
      mockCommRepo.setCommunity(Community(
        id: stateId,
        name: 'State Community',
        type: 'state',
        location: {'state': 'California', 'countryCode': 'US'},
      ));

      // User's Local Community
      mockCommRepo.setCommunity(Community(
        id: localId,
        name: 'Local Community',
        type: 'local',
        location: {'state': 'California', 'countryCode': 'US'},
      ));

      // 2. Setup Governance Units
      final targetUnit = GovernanceUnit(
        id: 'state_gov',
        name: 'State Council',
        level: GovernanceLevel.state,
        type: GovernanceType.state,
        communityId: stateId,
      );

      final userLocalUnit = GovernanceUnit(
        id: 'local_gov',
        name: 'Local Council',
        level: GovernanceLevel.local,
        type: GovernanceType.local,
        communityId: localId,
        councilMembers: [userId],
      );

      // 3. Setup Repo
      mockGovRepo.setUserMemberships(userId, [userLocalUnit]);

      // 4. Test
      final result = await service.shouldPromoteToHigherCouncil(userId, targetUnit);
      expect(result, isTrue);
    });

    test('returns false if user is Local Council member in DIFFERENT State', () async {
      // 1. Setup Communities
      final stateId = 'state_comm_id';
      final localId = 'local_comm_id_diff';

      // Target (State) Community
      mockCommRepo.setCommunity(Community(
        id: stateId,
        name: 'State Community',
        type: 'state',
        location: {'state': 'California', 'countryCode': 'US'},
      ));

      // User's Local Community (New York)
      mockCommRepo.setCommunity(Community(
        id: localId,
        name: 'Local Community NY',
        type: 'local',
        location: {'state': 'New York', 'countryCode': 'US'},
      ));

      // 2. Setup Governance Units
      final targetUnit = GovernanceUnit(
        id: 'state_gov',
        name: 'State Council',
        level: GovernanceLevel.state,
        type: GovernanceType.state,
        communityId: stateId,
      );

      final userLocalUnit = GovernanceUnit(
        id: 'local_gov_ny',
        name: 'Local Council NY',
        level: GovernanceLevel.local,
        type: GovernanceType.local,
        communityId: localId,
        councilMembers: [userId],
      );

      // 3. Setup Repo
      mockGovRepo.setUserMemberships(userId, [userLocalUnit]);

      // 4. Test
      final result = await service.shouldPromoteToHigherCouncil(userId, targetUnit);
      expect(result, isFalse);
    });
    
    test('returns true for Continent target if user is Country Council member', () async {
       // 1. Setup Communities
       final continentId = 'africa_id';
       final countryId = 'kenya_id';
       
       // Target (Continent)
       // Note: Continent Communities don't have standard location map usually, but let's assume structure
       mockCommRepo.setCommunity(Community(
         id: continentId,
         name: 'Africa Community',
         type: 'continent',
         // No specific location map for continent usually, but targetUnit check is loose for Continent level if global
       ));

       // User's Country Community
       mockCommRepo.setCommunity(Community(
         id: countryId,
         name: 'Kenya Community',
         type: 'country',
         homeCountryCode: 'KE',
         location: {'countryCode': 'KE'},
       ));

       // 2. Setup Gov Units
       final targetUnit = GovernanceUnit(
         id: 'africa_gov',
         name: 'Africa Council',
         level: GovernanceLevel.continent,
         type: GovernanceType.continent,
         communityId: continentId,
       );

       final userCountryUnit = GovernanceUnit(
         id: 'kenya_gov',
         name: 'Kenya Council',
         level: GovernanceLevel.country,
         type: GovernanceType.country,
         communityId: countryId,
         councilMembers: [userId],
       );

       mockGovRepo.setUserMemberships(userId, [userCountryUnit]);

       // 3. Test
       // Note: Current logic for Continent is `isContained = true` (loose check)
       // This test mainly verifies the Level check works and it falls through to true.
       final result = await service.shouldPromoteToHigherCouncil(userId, targetUnit);
       expect(result, isTrue);
    });

    test('returns false if user is Local Council member trying for Country (Skipping State)', () async {
        // User is Local Council. Target is Country.
        // Requires State Council membership.
        // Should fail because Level mismatch.

        final targetUnit = GovernanceUnit(
          id: 'country_gov',
          name: 'Country Council',
          level: GovernanceLevel.country,
          type: GovernanceType.country,
          communityId: 'country_comm',
        );

        final userLocalUnit = GovernanceUnit(
          id: 'local_gov',
          name: 'Local Council', // [FIX] Added name
          level: GovernanceLevel.local,
          type: GovernanceType.local,
          communityId: 'local_comm', // [FIX] Fixed param name
          councilMembers: [userId],
        );

        mockGovRepo.setUserMemberships(userId, [userLocalUnit]);

        final result = await service.shouldPromoteToHigherCouncil(userId, targetUnit);
        
        // Target=Country requires Lower=State.
        // User has Lower=Local.
        // result should be False.
        expect(result, isFalse);
    });

  });
}
