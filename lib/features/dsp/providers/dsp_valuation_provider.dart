import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import 'package:diaspora_nearby/features/dsp/services/epoch_service.dart';
import 'package:diaspora_nearby/features/dsp/services/valuation_service.dart';

/// Provides a real-time [DspValuation] by combining existing Firestore streams.
///
/// Reactively recalculates whenever any of the underlying metrics change:
/// - Total minted supply (from `dsp_supply`)
/// - System treasury data (burned points from `system_stats/treasury`)
/// - Global member count (from `communities/global_community`)
/// - Fiat GDP in USD (from `system_stats/treasury`)
final dspValuationProvider = Provider<DspValuation>((ref) {
  final valuationService = ref.read(valuationServiceProvider);
  final epochService = ref.read(epochServiceProvider);

  // --- Pull latest values from existing streams ---
  final totalMinted = ref.watch(globalSupplyProvider).value ?? 0;
  final treasuryData = ref.watch(systemTreasuryProvider).value ?? {};
  final totalUsers = ref.watch(globalMemberCountProvider).value ?? 0;
  final fiatGdpUsd = ref.watch(fiatGdpProvider).value ?? 0.0;

  // Burn data combines in-app utility burns + 10% protocol burn pool + TDE PCT penalty burns
  final int totalBurned =
      ((treasuryData['totalBurnedUtility'] as num?)?.toInt() ?? 0) +
      ((treasuryData['burnedPoints'] as num?)?.toInt() ?? 0) +
      ((treasuryData['totalBurnedTde'] as num?)?.toInt() ?? 0);

  // Derive current epoch from canonical EpochService using global supply and member count
  final int currentEpoch = epochService
      .getCurrentCommunityEpoch(totalMinted, totalUsers)
      .level;

  return valuationService.calculateImpliedValue(
    totalUsers: totalUsers,
    totalMinted: totalMinted,
    totalBurned: totalBurned,
    currentEpoch: currentEpoch,
    fiatGdpUsd: fiatGdpUsd,
  );
});
