import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import 'package:diaspora_nearby/features/dsp/services/valuation_service.dart';

/// Provides a real-time [DspValuation] by combining existing Firestore streams.
///
/// Reactively recalculates whenever any of the underlying metrics change:
/// - Total minted supply (from `dsp_supply`)
/// - System treasury data (burned points from `system_stats/treasury`)
/// - Global member count (from `communities/global_community`)
/// - Fiat GDP in USD (from `system_stats/treasury`)
///
/// Uses Epoch 1 as the current epoch (hardcoded until epoch progression logic
/// is implemented).
final dspValuationProvider = Provider<DspValuation>((ref) {
  final valuationService = ref.read(valuationServiceProvider);

  // --- Pull latest values from existing streams ---
  final totalMinted = ref.watch(globalSupplyProvider).value ?? 0;
  final treasuryData = ref.watch(systemTreasuryProvider).value ?? {};
  final totalUsers = ref.watch(globalMemberCountProvider).value ?? 0;
  final fiatGdpUsd = ref.watch(fiatGdpProvider).value ?? 0.0;

  // Burn data lives in system_stats/treasury as totalBurnedUtility
  final int totalBurned =
      (treasuryData['totalBurnedUtility'] as num?)?.toInt() ?? 0;

  // Current epoch — hardcoded to 1 for now.
  // When epoch progression is automated, this will come from a Firestore field.
  const int currentEpoch = 1;

  return valuationService.calculateImpliedValue(
    totalUsers: totalUsers,
    totalMinted: totalMinted,
    totalBurned: totalBurned,
    currentEpoch: currentEpoch,
    fiatGdpUsd: fiatGdpUsd,
  );
});
