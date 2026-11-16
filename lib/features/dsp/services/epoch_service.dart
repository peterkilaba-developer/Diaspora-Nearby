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
    final roundedScore = trustScore.round();
    if (roundedScore < 11) return 0.0;
    if (roundedScore >= 91) return 1.0;

    final cappedScore = roundedScore.clamp(0, 100);
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
  // Each Epoch requires 10x more new DSP distributed within that Epoch
  // (e.g., Epoch 1 = 1M DSP [100K/TDE], Epoch 2 = 10M new DSP [1M/TDE, cumulative 1M->11M]).
  static const List<CommunityEpochDefinition> _communityEpochSchedule = [
    CommunityEpochDefinition(
      level: 1,
      dspTarget: 1000000,
      cumulativeDspStart: 0,
      memberTarget: 10,
    ), // 1M / 10 users (cum: 0 -> 1M)
    CommunityEpochDefinition(
      level: 2,
      dspTarget: 10000000,
      cumulativeDspStart: 1000000,
      memberTarget: 100,
    ), // 10M / 100 users (cum: 1M -> 11M)
    CommunityEpochDefinition(
      level: 3,
      dspTarget: 100000000,
      cumulativeDspStart: 11000000,
      memberTarget: 1000,
    ), // 100M / 1k (cum: 11M -> 111M)
    CommunityEpochDefinition(
      level: 4,
      dspTarget: 1000000000,
      cumulativeDspStart: 111000000,
      memberTarget: 10000,
    ), // 1B / 10k (cum: 111M -> 1.111B)
    CommunityEpochDefinition(
      level: 5,
      dspTarget: 10000000000,
      cumulativeDspStart: 1111000000,
      memberTarget: 100000,
    ), // 10B / 100k
    CommunityEpochDefinition(
      level: 6,
      dspTarget: 100000000000,
      cumulativeDspStart: 11111000000,
      memberTarget: 1000000,
    ), // 100B / 1M
    CommunityEpochDefinition(
      level: 7,
      dspTarget: 1000000000000,
      cumulativeDspStart: 111111000000,
      memberTarget: 10000000,
    ), // 1T / 10M
    CommunityEpochDefinition(
      level: 8,
      dspTarget: 10000000000000,
      cumulativeDspStart: 1111111000000,
      memberTarget: 100000000,
    ), // 10T / 100M
    CommunityEpochDefinition(
      level: 9,
      dspTarget: 100000000000000,
      cumulativeDspStart: 11111111000000,
      memberTarget: 1000000000,
    ), // 100T / 1B
    CommunityEpochDefinition(
      level: 10,
      dspTarget: 1000000000000000,
      cumulativeDspStart: 111111111000000,
      memberTarget: 10000000000,
    ), // 1QD / 10B
  ];

  static const int absoluteSupplyCap = 1000000000000000; // 1 Quadrillion (1QD)

  /// Get the CURRENT epoch a community is working towards.
  /// Epoch advances when cumulative DSP reaches cumulativeDspTarget
  /// (population is tracked as an informational benchmark, not a gate).
  CommunityEpochDefinition getCurrentCommunityEpoch(
    int cumulativeEarnings,
    int memberCount,
  ) {
    for (final epoch in _communityEpochSchedule) {
      if (cumulativeEarnings < epoch.cumulativeDspTarget) {
        return epoch;
      }
    }
    return _communityEpochSchedule.last; // Cap at max defined epoch
  }

  /// Gets the previous epoch's definition if level > 1.
  CommunityEpochDefinition? getPreviousCommunityEpoch(int currentLevel) {
    if (currentLevel <= 1) return null;
    return _communityEpochSchedule.firstWhere(
      (e) => e.level == currentLevel - 1,
    );
  }

  /// Calculates the cumulative DSP threshold for the next TDE milestone (10% of current epoch target).
  int getNextCommunityMilestone(int cumulativeEarnings, int memberCount) {
    final epoch = getCurrentCommunityEpoch(cumulativeEarnings, memberCount);
    final int step = (epoch.dspTarget / 10).round();

    final int completedSteps = getCompletedTgeEvents(
      cumulativeEarnings,
      memberCount,
    );

    final int nextStepIndex = (completedSteps + 1).clamp(1, 10);
    return epoch.cumulativeDspStart + (nextStepIndex * step);
  }

  /// Returns the number of fully completed TDE releases (0 to 10) within the current Epoch.
  /// TDE progression is based on 10% deciles of the current epoch's dspTarget.
  int getCompletedTgeEvents(int cumulativeEarnings, int memberCount) {
    final epoch = getCurrentCommunityEpoch(cumulativeEarnings, memberCount);
    final int dspStep = (epoch.dspTarget / 10).round();
    if (dspStep <= 0) return 0;

    int completedSteps =
        ((cumulativeEarnings - epoch.cumulativeDspStart) / dspStep).floor();

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
  final int cumulativeDspStart;
  final int memberTarget;

  const CommunityEpochDefinition({
    required this.level,
    required this.dspTarget,
    this.cumulativeDspStart = 0,
    required this.memberTarget,
  });

  int get cumulativeDspTarget => cumulativeDspStart + dspTarget;

  /// Returns DSP distributed strictly within this epoch (0 .. dspTarget).
  int epochEarnedDsp(int cumulativeDsp) {
    return (cumulativeDsp - cumulativeDspStart).clamp(0, dspTarget);
  }

  // TDE progress is based on distributed DSP within this epoch. Member growth is informational.
  double calculateProgress(int currentDsp, int currentMembers) {
    if (dspTarget <= 0) return 0.0;
    return ((currentDsp - cumulativeDspStart) / dspTarget).clamp(0.0, 1.0);
  }
}
