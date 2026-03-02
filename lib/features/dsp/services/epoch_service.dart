import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

final epochServiceProvider = Provider((ref) => EpochService());

class EpochDefinition {
  final int epochNumber;
  final int minDspRequired;
  final int minTrustScore;

  const EpochDefinition({
    required this.epochNumber,
    required this.minDspRequired,
    required this.minTrustScore,
  });
}

class EpochService {
  // Epoch Schedule (Epoch 1 to 10)
  // Each Epoch has 10 TGE Events (10% supply each)
  // Epochs are identified by number only — labels deprecated.
  static const List<EpochDefinition> _epochSchedule = [
    EpochDefinition(epochNumber: 1, minDspRequired: 10000, minTrustScore: 51),
    EpochDefinition(epochNumber: 2, minDspRequired: 10000, minTrustScore: 51),
    EpochDefinition(epochNumber: 3, minDspRequired: 10000, minTrustScore: 51),
    EpochDefinition(epochNumber: 4, minDspRequired: 10000, minTrustScore: 51),
    EpochDefinition(epochNumber: 5, minDspRequired: 10000, minTrustScore: 51),
    EpochDefinition(epochNumber: 6, minDspRequired: 10000, minTrustScore: 51),
    EpochDefinition(epochNumber: 7, minDspRequired: 10000, minTrustScore: 51),
    EpochDefinition(epochNumber: 8, minDspRequired: 10000, minTrustScore: 51),
    EpochDefinition(epochNumber: 9, minDspRequired: 10000, minTrustScore: 51),
    EpochDefinition(epochNumber: 10, minDspRequired: 10000, minTrustScore: 51),
  ];

  static const double CONSTANT_REWARD_MULTIPLIER = 1.0;

  EpochDefinition getEpoch(int epochNumber) {
    if (epochNumber < 0) return _epochSchedule.first;
    if (epochNumber >= _epochSchedule.length) {
      return _epochSchedule.last;
    }
    return _epochSchedule.firstWhere(
      (e) => e.epochNumber == epochNumber,
      orElse: () => _epochSchedule.last,
    );
  }

  /// Returns true if the user meets the requirements for the given epoch's TGE
  bool isEligibleForTGE({
    required int epochNumber,
    required double userTotalDsp, // User's total earned DSP
    required int userTrustScore,
  }) {
    final epoch = getEpoch(epochNumber);
    // Trust score requirement is now handled by efficiency sliding scale (0-100)
    // We only gate by Minimum DSP requirement
    return userTotalDsp >= epoch.minDspRequired;
  }

  /// Calculates the TGE distribution for a user
  /// If eligible: Returns their full DSP balance * Efficiency
  /// If ineligible (low DSP): Returns 0
  double calculateTGESwap({
    required int epochNumber,
    required double currentDspBalance,
    required int trustScore,
  }) {
    // 1. Check Gated Eligibility (Min DSP only)
    if (!isEligibleForTGE(
      epochNumber: epochNumber,
      userTotalDsp: currentDspBalance,
      userTrustScore: trustScore,
    )) {
      return 0.0;
    }

    final double efficiency = calculateEfficiency(trustScore);
    return currentDspBalance * efficiency;
  }

  /// [NEW] Public Helper for Efficiency Calculation (Decile Scale)
  /// Supports both int and double inputs for Trust Score
  double calculateEfficiency(num trustScore) {
    if (trustScore <= 0) return 0.0;

    // Logic: (Score / 10).ceil() * 0.10
    // Example: 91 / 10 = 9.1 -> ceil 10 -> 1.0 (100%)
    // Example: 85 / 10 = 8.5 -> ceil 9 -> 0.9 (90%)
    double efficiency = (trustScore / 10).ceil() / 10.0;

    // Cap at 1.0
    if (efficiency > 1.0) efficiency = 1.0;

    return efficiency;
  }

  /// [NEW] Returns the trust-slider color for a given trust score (0–100).
  /// Mirrors the 5-band color scale used in TrustSliderWidget._getColor().
  static Color getEfficiencyColor(num trustScore) {
    if (trustScore >= 81) return AppTheme.accent; // High Trust
    if (trustScore >= 61) return Colors.lightGreen; // Standard Trust
    if (trustScore >= 41) return Colors.amber; // Medium Trust
    if (trustScore >= 21) return Colors.deepOrange; // Basic Trust
    if (trustScore > 0) return AppTheme.error; // Low Trust
    return Colors.grey; // No score
  }

  List<EpochDefinition> getAllEpochs() => _epochSchedule;

  // ------------------------------------------------------------------------
  // Community Epoch Logic (10-Base Scaling)
  // ------------------------------------------------------------------------

  // Community Epoch Scaling (10x User/Supply Growth)
  static const List<CommunityEpochDefinition> _communityEpochSchedule = [
    CommunityEpochDefinition(
      level: 1,
      dspTarget: 1000000,
      memberTarget: 100,
    ), // 1M / 100 users
    CommunityEpochDefinition(
      level: 2,
      dspTarget: 10000000,
      memberTarget: 1000,
    ), // 10M / 1k users
    CommunityEpochDefinition(
      level: 3,
      dspTarget: 100000000,
      memberTarget: 10000,
    ), // 100M / 10k
    CommunityEpochDefinition(
      level: 4,
      dspTarget: 1000000000,
      memberTarget: 100000,
    ), // 1B / 100k
    CommunityEpochDefinition(
      level: 5,
      dspTarget: 10000000000,
      memberTarget: 1000000,
    ), // 10B / 1M
    CommunityEpochDefinition(
      level: 6,
      dspTarget: 100000000000,
      memberTarget: 10000000,
    ), // 100B / 10M
    CommunityEpochDefinition(
      level: 7,
      dspTarget: 1000000000000,
      memberTarget: 100000000,
    ), // 1T / 100M
    CommunityEpochDefinition(
      level: 8,
      dspTarget: 10000000000000,
      memberTarget: 1000000000,
    ), // 10T / 1B
    CommunityEpochDefinition(
      level: 9,
      dspTarget: 100000000000000,
      memberTarget: 10000000000,
    ), // 100T / 10B
    CommunityEpochDefinition(
      level: 10,
      dspTarget: 1000000000000000,
      memberTarget: 100000000000,
    ), // 1QD / 100B
  ];

  static const int ABSOLUTE_SUPPLY_CAP =
      1000000000000000; // 1 Quadrillion (1QD)

  /// Get the CURRENT epoch a community is working towards.
  /// If they have surpassed Epoch 1 targets, they are in Epoch 2, etc.
  CommunityEpochDefinition getCurrentCommunityEpoch(
    int cumulativeEarnings,
    int memberCount,
  ) {
    for (var epoch in _communityEpochSchedule) {
      // If we haven't reached BOTH targets for this epoch, then THIS is our current target epoch.
      final bool reachedDsp = cumulativeEarnings >= epoch.dspTarget;
      final bool reachedMembers = memberCount >= epoch.memberTarget;

      if (!reachedDsp || !reachedMembers) {
        return epoch;
      }
      // If we reached BOTH of them, we completed this epoch, so check the next one.
    }
    return _communityEpochSchedule.last; // Cap at max defined epoch
  }

  /// [NEW] Gets the previous epoch's targets for range-based calculations
  CommunityEpochDefinition? getPreviousCommunityEpoch(int currentLevel) {
    if (currentLevel <= 1) return null;
    return _communityEpochSchedule.firstWhere(
      (e) => e.level == currentLevel - 1,
    );
  }

  /// [NEW] Calculates the next TGE event milestone (10% of epoch total)
  int getNextCommunityMilestone(int cumulativeEarnings, int memberCount) {
    final epoch = getCurrentCommunityEpoch(cumulativeEarnings, memberCount);
    // Milestone = 10% of dspTarget
    final int step = (epoch.dspTarget / 10).round();

    // Use dual logic to determine how many we have completed
    final int completedSteps = getCompletedTgeEvents(
      cumulativeEarnings,
      memberCount,
    );

    // Next milestone is the target for the NEXT step
    return (completedSteps + 1) * step;
  }

  /// [NEW] Returns the number of fully completed TGE events (0 to 10)
  /// Enforces DUAL LOGIC: Requires set % of DSP AND set % of Members
  /// Now uses range-based scaling for consistent progression.
  int getCompletedTgeEvents(int cumulativeEarnings, int memberCount) {
    final epoch = getCurrentCommunityEpoch(cumulativeEarnings, memberCount);
    final prevEpoch = getPreviousCommunityEpoch(epoch.level);

    final int prevDspTarget = prevEpoch?.dspTarget ?? 0;
    final int prevMemberTarget = prevEpoch?.memberTarget ?? 0;

    final int dspRange = (epoch.dspTarget - prevDspTarget).clamp(1, 1 << 31);
    final int memberRange = (epoch.memberTarget - prevMemberTarget).clamp(
      1,
      1 << 31,
    );

    final int dspStep = (dspRange / 10).round();
    final int memberStep = (memberRange / 10).round();
    final int effectiveMemberStep = memberStep > 0 ? memberStep : 1;

    final int dspStepsCompleted =
        ((cumulativeEarnings - prevDspTarget) / dspStep).floor();
    final int memberStepsCompleted =
        ((memberCount - prevMemberTarget) / effectiveMemberStep).floor();

    // The constraining factor determines the completed steps (Dual Logic)
    int completedSteps = dspStepsCompleted < memberStepsCompleted
        ? dspStepsCompleted
        : memberStepsCompleted;

    if (completedSteps > 10) completedSteps = 10;
    if (completedSteps < 0) completedSteps = 0;
    return completedSteps;
  }

  /// [NEW] Returns the current TGE Event number (1 to 10) within the current Epoch
  int getCurrentTgeEventNumber(int cumulativeEarnings, int memberCount) {
    final int completedSteps = getCompletedTgeEvents(
      cumulativeEarnings,
      memberCount,
    );

    // If we have completed 10, stay at 10 (or handle as finished elsewhere)
    if (completedSteps >= 10) return 10;

    return completedSteps + 1;
  }
}

class CommunityEpochDefinition {
  final int level;
  final int dspTarget;
  final int memberTarget;

  const CommunityEpochDefinition({
    required this.level,
    required this.dspTarget,
    required this.memberTarget,
  });

  // Helper to calculate progress (0.0 to 1.0)
  // Progress is MAX of DSP progress or Member progress
  double calculateProgress(int currentDsp, int currentMembers) {
    final dspProgress = (currentDsp / dspTarget).clamp(0.0, 1.0);
    final memberProgress = (currentMembers / memberTarget).clamp(0.0, 1.0);
    return (dspProgress > memberProgress) ? dspProgress : memberProgress;
  }
}
