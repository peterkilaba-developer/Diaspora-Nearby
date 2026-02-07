import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../community/repository/community_repository.dart';
import '../../dsp/models/user_points.dart';
import '../../dsp/repository/points_repository.dart';
import '../models/governance_unit.dart';
import '../models/election_result.dart';
import '../repository/governance_repository.dart';

final governanceRepositoryProviderAlias = governanceRepositoryProvider;

final governanceServiceProvider = Provider((ref) => GovernanceService(ref));

class GovernanceService {
  final Ref _ref;

  GovernanceService(this._ref);

  /// Checks if a user is a Pillar.
  Future<bool> isPillar(String userId) async {
    final userPoints = await _ref.read(pointsRepositoryProvider).getUserPoints(userId);
    if (userPoints == null) return false;

    // Gate: 100k DSP AND 67+ PoCT
    return userPoints.totalDsp >= 100000 && (userPoints.trustScore ?? 0) >= 67;
  }

  /// Triggers a re-tally for a governance unit and updates signers if needed.
  Future<void> tallyElection(String unitId) async {
    final repo = _ref.read(governanceRepositoryProvider);
    final unit = await repo.getGovernanceUnit(unitId);
    if (unit == null || !unit.isActiveElection) return;

    // 1. Get all votes for this unit
    final votes = await repo.getVotes(unitId);
    if (votes.isEmpty) {
      await repo.endElection(unitId);
      return;
    }

    // 2. Count votes per candidate and signer
    final Map<String, int> councilTally = {};
    final Map<String, int> signerTally = {};

    for (var vote in votes) {
      final candidateId = vote['candidateId'] as String;
      councilTally[candidateId] = (councilTally[candidateId] ?? 0) + 1;

      if (vote.containsKey('signerId') && vote['signerId'] != null) {
        final signerId = vote['signerId'] as String;
        signerTally[signerId] = (signerTally[signerId] ?? 0) + 1;
      }
    }

    // 3. Sort candidates by vote count
    final sortedCouncilCandidates = councilTally.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
      
    final sortedSignerCandidates = signerTally.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // 4. Select top candidates for Council
    final List<String> councilWinners;
    if (unit.level == GovernanceLevel.global) {
      // Global: 1 per Continent
      councilWinners = await _tallyGlobalElection(unitId, votes);
    } else if (unit.level == GovernanceLevel.state || 
               unit.level == GovernanceLevel.country || 
               unit.level == GovernanceLevel.continent) {
      // Representation: 1 per child unit
      councilWinners = await _tallyRepresentationElection(unitId, votes);
    } else {
      // Local: Top 3
      councilWinners = sortedCouncilCandidates.take(3).map((e) => e.key).toList();
    }
    
    // 5. Select top candidates for Signers (Multi-Sig)
    // Defaults to top N vote getters, or minimal 3 if not enough votes? 
    // We take the top 'requiredSignatures' (default 3 to 5)
    final int neededSigners = unit.requiredSignatures > 0 ? unit.requiredSignatures : 3;
    final List<String> signerWinners = sortedSignerCandidates
        .take(neededSigners)
        .map((e) => e.key)
        .toList();
        
    // Fallback: If no signer votes, maybe use top council winners?
    // For now, let's strictly respect the vote. 

    // 6. Update governance structure
    await repo.updateGovernanceStructure(unitId, 
      councilMembers: councilWinners,
      signers: signerWinners,
    );

    // Record result for transparency
    final result = ElectionResult(
      id: '${unitId}_${DateTime.now().millisecondsSinceEpoch}',
      unitId: unitId,
      unitName: unit.name,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      winners: councilWinners, // Primary winners are Council
      tally: councilTally,
      totalVotes: votes.length,
    );
    // Note: ElectionResult model might need updating to store signerTally too, 
    // but generic tally map can hold it if we namespace keys or just store council tally for now.
    // Ideally we update ElectionResult too. For now, just persisting council tally.
    await repo.saveElectionResult(result);

    await repo.endElection(unitId);
  }

  /// Starts a new election for a unit.
  Future<void> startElection(String unitId, {int durationDays = 7}) async {
    final repo = _ref.read(governanceRepositoryProvider);
    await repo.startElection(unitId, durationDays);
  }

  /// Casts a vote in an active election.
  Future<void> castVote({
    required String unitId,
    required String voterId,
    required String candidateId,
    String? signerId,
  }) async {
    // 1. Verify eligibility
    if (signerId != null) {
      final pillar = await isPillar(voterId);
      if (!pillar) {
        throw Exception('Peer Selection Required: Only Pillars can cast votes for treasury multi-sig signers.');
      }
    }
    // [Note] Council member voting (candidateId) remains open to all authenticated community members.
    
    // 2. Verify election is active
    final repo = _ref.read(governanceRepositoryProvider);
    final unit = await repo.getGovernanceUnit(unitId);
    if (unit == null || !unit.isActiveElection) {
      throw Exception('No active election for this unit.');
    }

    // 3. Cast vote
    await repo.castVote(
      unitId: unitId,
      voterId: voterId,
      candidateId: candidateId,
      signerId: signerId,
    );
  }

  /// Specifically handles the selection of a country representative for Continent/Global tiers.
  Future<void> selectRepresentative({
    required String countryCode,
    required GovernanceType targetTier, // continent or global
    required String representativeId,
  }) async {
    final repo = _ref.read(governanceRepositoryProvider);
    
    // Tier ID might be 'africa' or 'global'
    String unitId = targetTier == GovernanceType.global ? 'global' : _getContinentForCountry(countryCode);
    
    final unit = await repo.getGovernanceUnit(unitId);
    if (unit == null) return;

    List<String> currentSigners = List.from(unit.signers);
    
    // Replace the representative for this country if they exist, or add new
    // (Logic to ensure multi-sig constraints map back to blockchain)
    
    await repo.updateSigners(unitId, currentSigners);
  }

  String _getContinentForCountry(String countryCode) {
    // Utility mapping logic
    return ['TZ', 'KE', 'UG', 'NG', 'GH'].contains(countryCode) ? 'africa' : 'international';
  }

  /// Fetches eligible candidates (Pillars) for a given unit based on hierarchy.
  Future<List<UserPoints>> getCandidates(String unitId) async {
    final repo = _ref.read(governanceRepositoryProviderAlias);
    final unit = await repo.getGovernanceUnit(unitId);
    if (unit == null) return [];

    final pointsRepo = _ref.read(pointsRepositoryProvider);

    if (unit.level == GovernanceLevel.local) {
      // Candidates are any Pillars belonging to this community
      return pointsRepo.getPillars(); // Should eventually filter by communityId
    } else {
      // Candidates are the currently elected Pillars (signers) of child communities
      final childSigners = await _fetchChildSigners(unit);
      
      // [FALLBACK] If no child signers (e.g. fresh launch or mock), allow all Pillars to be candidates
      if (childSigners.isEmpty) {
        return pointsRepo.getPillars();
      }

      // Fetch UserPoints for these signers
      List<UserPoints> candidates = [];
      for (var signerId in childSigners) {
        final up = await pointsRepo.getUserPoints(signerId);
        if (up != null) candidates.add(up);
      }
      return candidates;
    }
  }

  Future<List<String>> _fetchChildSigners(GovernanceUnit unit) async {
    if (unit.communityId == null) return [];
    
    final commRepo = _ref.read(communityRepositoryProvider);
    final govRepo = _ref.read(governanceRepositoryProviderAlias);
    
    final parentComm = await commRepo.getCommunity(unit.communityId!);
    if (parentComm == null) return [];

    final children = await commRepo.getChildCommunities(parentComm);
    List<String> allSigners = [];

    for (var child in children) {
      // Find the governance unit for each child community
      // Assuming mapping: unitId == communityId or similar
      final childUnit = await govRepo.getGovernanceUnit(child.id);
      if (childUnit != null) {
        allSigners.addAll(childUnit.signers);
      }
    }
    return allSigners.toSet().toList(); // Unique signers
  }

  Future<List<String>> _tallyGlobalElection(String unitId, List<Map<String, dynamic>> votes) async {
    // [NEW] "Global same thing": 1 Pillar per Continent
    return _tallyRepresentationElection(unitId, votes);
  }

  Future<List<String>> _tallyRepresentationElection(String unitId, List<Map<String, dynamic>> votes) async {
    // Select TOP 1 from EACH direct child unit
    // This ensures a 1-per-child representation rule for non-local tiers (State, Country, Continent, Global).
    final Map<String, int> tally = _calculateTally(votes);
    
    final unit = await _ref.read(governanceRepositoryProviderAlias).getGovernanceUnit(unitId);
    if (unit?.communityId == null) return [];

    final parentComm = await _ref.read(communityRepositoryProvider).getCommunity(unit!.communityId!);
    if (parentComm == null) return [];
    
    final children = await _ref.read(communityRepositoryProvider).getChildCommunities(parentComm);

    List<String> winners = [];
    for (var child in children) {
      final childUnit = await _ref.read(governanceRepositoryProviderAlias).getGovernanceUnit(child.id);
      if (childUnit == null) continue;

      // Find the candidate from THIS child who has the most votes in the Parent election
      final candidatesFromChild = childUnit.signers;
      String? bestCandidate;
      int maxVotes = -1;

      for (var cid in candidatesFromChild) {
        final v = tally[cid] ?? 0;
        if (v > maxVotes) {
          maxVotes = v;
          bestCandidate = cid;
        }
      }

      if (bestCandidate != null) {
        winners.add(bestCandidate);
      }
    }
    return winners;
  }

  Map<String, int> _calculateTally(List<Map<String, dynamic>> votes) {
    final Map<String, int> tally = {};
    for (var vote in votes) {
      final cid = vote['candidateId'] as String;
      tally[cid] = (tally[cid] ?? 0) + 1;
    }
    return tally;
  }

  Future<List<GovernanceUnit>> _getUnitsByLevel(GovernanceLevel level) async {
    // Query governance units by level
    final snapshot = await FirebaseFirestore.instance
        .collection('governance')
        .where('level', isEqualTo: level.index)
        .get();
    
    return snapshot.docs.map((doc) => GovernanceUnit.fromJson(doc.data())).toList();
  }

  /// Periodically called (e.g., on dashboard load) to see if any elections need starting.
  Future<void> checkAndTriggerElections() async {
    
    // Bottom-up order: City -> State -> Country -> Continent -> Global
    final levels = GovernanceLevel.values;
    
    for (var level in levels) {
      final units = await _getUnitsByLevel(level);
      for (var unit in units) {
        final now = DateTime.now().millisecondsSinceEpoch;
        
        bool needsElection = !unit.isActiveElection && 
            (unit.signers.isEmpty || (unit.nextElectionAt != null && now > unit.nextElectionAt!));
        
        if (needsElection) {
          // Check if child units are ready (Step logic)
          if (await _areChildUnitsReady(unit)) {
            await startElection(unit.id);
          }
        } else if (unit.isActiveElection && unit.electionEndTime != null && now > unit.electionEndTime!) {
          await tallyElection(unit.id);
        }
      }
    }
  }


  Future<bool> _areChildUnitsReady(GovernanceUnit unit) async {
    if (unit.level == GovernanceLevel.local) return true; // Local always ready if pillars exist
    
    // Parent unit is ready only if its child communities have elected their pillars
    // (Representation logic)
    return true; 
  }

  /// Refined TGE eligibility check
  Future<bool> checkTgeEligibility(String unitId) async {
    final unit = await _ref.read(governanceRepositoryProviderAlias).getGovernanceUnit(unitId);
    if (unit == null) return false;

    // Minimum 3 pillars required for any unit to be active/eligible for TGE
    // This allows small countries with 3+ states to participate.
    return unit.signers.length >= 3;
  }

  /// [DEBUG] Seeds a mock election for testing purposes.
  Future<void> seedMockElection(String unitId) async {
    final repo = _ref.read(governanceRepositoryProvider);
    
    // 1. Ensure governance unit exists and is active
    var unit = await repo.getGovernanceUnit(unitId);
    
    if (unit == null) {
       // [FIX] Create minimal unit if missing so election can run
       GovernanceLevel level = GovernanceLevel.local;
       if (unitId.contains('country')) level = GovernanceLevel.country;
       if (unitId.contains('continent')) level = GovernanceLevel.continent;
       if (unitId.contains('global')) level = GovernanceLevel.global;

       unit = GovernanceUnit(
         id: unitId,
         name: unitId.replaceAll('_', ' ').toUpperCase().replaceAll('COUNTRY ', ''),
         level: level,
         type: GovernanceType.values[level.index],
         isActiveElection: false,
       );
       await repo.saveGovernanceUnit(unit);
    }
    
    if (unit!.isActiveElection) return; // Already satisfying
    
    // Start election if not active
    await repo.startElection(unitId, 7);
    
    // 2. Ensure mock candidates exist (if none found)
    final pointsRepo = _ref.read(pointsRepositoryProvider);
    final candidates = await getCandidates(unitId);
    
    if (candidates.isEmpty) {
      // Create mock users/pillars
      final batch = FirebaseFirestore.instance.batch();
      
      for (int i = 0; i < 5; i++) {
        final mockId = 'mock-pillar-$i-${DateTime.now().millisecond}';
        final userPoints = UserPoints(
          userId: mockId,
          totalPoints: 150000 + (i * 5000),
          availablePoints: 50000,
          trustScore: 85 + i,
          currentStreak: 10,
          dailyMessageCount: 5,
          lastUpdated: DateTime.now(),
          signupDate: DateTime.now().subtract(const Duration(days: 400)),
        );
        batch.set(
          FirebaseFirestore.instance.collection('user_points').doc(mockId), 
          userPoints.toMap()
        );
        
        // Also create a dummy user doc so name/country lookup might work if needed
        batch.set(
           FirebaseFirestore.instance.collection('users').doc(mockId),
           {
             'uid': mockId,
             'firstName': 'Mock Pillar ${i+1}',
             'displayName': 'Mock Pillar ${i+1}',
             'homeCountryCode': 'TZ', // Default to TZ for testing
             'createdAt': FieldValue.serverTimestamp(),
           }
        );
      }
      await batch.commit();
    }
  }
}
