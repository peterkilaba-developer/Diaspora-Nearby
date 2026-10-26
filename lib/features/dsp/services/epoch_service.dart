import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

final epochServiceProvider = Provider((ref) => EpochService());

class EpochDefinition {
  final int epochNumber;

  const EpochDefinition({required this.epochNumber});
}

class EpochService {
  // Epoch Schedule (Epoch 1 to 10)
  // Each Epoch has 1 TGE and 10 TDE releases (10% supply each)
  // Epochs are identified by number only — labels deprecated.
  static const List<EpochDefinition> _epochSchedule = [
    EpochDefinition(epochNumber: 1),
    EpochDefinition(epochNumber: 2),
    EpochDefinition(epochNumber: 3),
    EpochDefinition(epochNumber: 4),
    EpochDefinition(epochNumber: 5),
    EpochDefinition(epochNumber: 6),
    EpochDefinition(epochNumber: 7),
    EpochDefinition(epochNumber: 8),
    EpochDefinition(epochNumber: 9),
    EpochDefinition(epochNumber: 10),
  ];

  static const double constantRewardMultiplier = 1.0;

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

  /// Returns true if the user has positive DSP for TGE/TDE conversion.
  /// Trust score is NOT a gate — it only affects swap efficiency via the
  /// PCT rule: <11 -> 0%, 11-90 -> exact %, 91+ -> 100% (see [calculateEfficiency]).
  bool isEligibleForTGE({
    required int epochNumber,
    required double userTotalDsp,
  }) {
    return userTotalDsp > 0;
  }

  /// Calculates the TGE/TDE distribution for a user
  /// Returns their eligible DSP balance * PCT Efficiency
  double calculateTGESwap({
    required int epochNumber,
    required double currentDspBalance,
    required int trustScore,
  }) {
    if (currentDspBalance <= 0) return 0.0;
    final double efficiency = calculateEfficiency(trustScore);
    return currentDspBalance * efficiency;
  }

  /// Calculates the unconverted DSP that carries over to the next TDE milestone.
  /// During TDE 1-9, unconverted DSP is kept in availablePoints so users can
  /// increase their PCT score and convert it in subsequent TDEs.
  /// At TDE 10 (The Great Reset), carried-over DSP is 0 (remaining DSP resets).
  double calculateCarriedOverDsp({
    required int tdeNumber,
    required double currentDspBalance,
    required int trustScore,
  }) {
    if (currentDspBalance <= 0 || tdeNumber >= 10) return 0.0;
    final converted = calculateTGESwap(
      epochNumber: 1,
      currentDspBalance: currentDspBalance,
      trustScore: trustScore,
    );
    return currentDspBalance - converted;
  }

  /// Calculates the unconverted DSP that is reset/burned at TDE 10 (The Great Reset).
  /// During TDE 1-9, 0 DSP is burned (unconverted balance carries over).
  double calculateGreatResetBurn({
    required int tdeNumber,
    required double currentDspBalance,
    required int trustScore,
  }) {
    if (currentDspBalance <= 0 || tdeNumber < 10) return 0.0;
    final converted = calculateTGESwap(
      epochNumber: 1,
      currentDspBalance: currentDspBalance,
      trustScore: trustScore,
    );
    return currentDspBalance - converted;
  }

  /// [NEW] Public Helper for Efficiency Calculation
  /// Supports both int and double inputs for Trust Score
  double calculateEfficiency(num trustScore) {
    if (trustScore < 11) return 0.0;
    if (trustScore >= 91) return 1.0;

    final cappedScore = trustScore.clamp(0, 100);
    return cappedScore / 100.0;
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

  // Community Epoch Scaling (10x User/Supply Growth: 10 users to 10B users)
  static const List<CommunityEpochDefinition> _communityEpochSchedule = [
    CommunityEpochDefinition(
      level: 1,
      dspTarget: 1000000,
      memberTarget: 10,
    ), // 1M / 10 users
    CommunityEpochDefinition(
      level: 2,
      dspTarget: 10000000,
      memberTarget: 100,
    ), // 10M / 100 users
    CommunityEpochDefinition(
      level: 3,
      dspTarget: 100000000,
      memberTarget: 1000,
    ), // 100M / 1k
    CommunityEpochDefinition(
      level: 4,
      dspTarget: 1000000000,
      memberTarget: 10000,
    ), // 1B / 10k
    CommunityEpochDefinition(
      level: 5,
      dspTarget: 10000000000,
      memberTarget: 100000,
    ), // 10B / 100k
    CommunityEpochDefinition(
      level: 6,
      dspTarget: 100000000000,
      memberTarget: 1000000,
    ), // 100B / 1M
    CommunityEpochDefinition(
      level: 7,
      dspTarget: 1000000000000,
      memberTarget: 10000000,
    ), // 1T / 10M
    CommunityEpochDefinition(
      level: 8,
      dspTarget: 10000000000000,
      memberTarget: 100000000,
    ), // 10T / 100M
    CommunityEpochDefinition(
      level: 9,
      dspTarget: 100000000000000,
      memberTarget: 1000000000,
    ), // 100T / 1B
    CommunityEpochDefinition(
      level: 10,
      dspTarget: 1000000000000000,
      memberTarget: 10000000000,
    ), // 1QD / 10B
  ];

  static const int absoluteSupplyCap = 1000000000000000; // 1 Quadrillion (1QD)

  /// Get the CURRENT epoch a community is working towards.
  /// Epoch advances when DSP target is reached (population is tracked but not gated).
  CommunityEpochDefinition getCurrentCommunityEpoch(
    int cumulativeEarnings,
    int memberCount,
  ) {
    for (var epoch in _communityEpochSchedule) {
      // TGE triggers on DSP target only — population is informational
      final bool reachedDsp = cumulativeEarnings >= epoch.dspTarget;

      if (!reachedDsp) {
        return epoch;
      }
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

  /// [NEW] Calculates the next TDE milestone (10% of epoch total)
  int getNextCommunityMilestone(int cumulativeEarnings, int memberCount) {
    final epoch = getCurrentCommunityEpoch(cumulativeEarnings, memberCount);
    // Milestone = 10% of dspTarget
    final int step = (epoch.dspTarget / 10).round();

    // TDE completion is determined by distributed DSP milestones.
    final int completedSteps = getCompletedTgeEvents(
      cumulativeEarnings,
      memberCount,
    );

    // Next milestone is the target for the NEXT step
    return (completedSteps + 1) * step;
  }

  /// Returns the number of fully completed TDE releases (0 to 10)
  /// TDE progression is based on DSP supply target only.
  /// Population is tracked for display but does not gate TDE releases.
  int getCompletedTgeEvents(int cumulativeEarnings, int memberCount) {
    final epoch = getCurrentCommunityEpoch(cumulativeEarnings, memberCount);
    final prevEpoch = getPreviousCommunityEpoch(epoch.level);

    final int prevDspTarget = prevEpoch?.dspTarget ?? 0;
    final int dspRange = (epoch.dspTarget - prevDspTarget).clamp(1, 1 << 31);
    final int dspStep = (dspRange / 10).round();

    int completedSteps = ((cumulativeEarnings - prevDspTarget) / dspStep)
        .floor();

    if (completedSteps > 10) completedSteps = 10;
    if (completedSteps < 0) completedSteps = 0;
    return completedSteps;
  }

  /// [NEW] Returns the current TDE number (1 to 10) within the current Epoch
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

  // TDE progress is based on distributed DSP. Member growth is informational.
  double calculateProgress(int currentDsp, int currentMembers) {
    return (currentDsp / dspTarget).clamp(0.0, 1.0);
  }
}
