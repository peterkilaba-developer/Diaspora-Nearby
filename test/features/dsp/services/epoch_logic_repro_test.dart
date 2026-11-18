// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:diaspora_nearby/features/dsp/services/epoch_service.dart';

void main() {
  group('EpochService Strict 10x Epoch Max Supply (1M -> 1QD)', () {
    final service = EpochService();

    test('Epoch 1 has strict 1,000,000 Max Supply with 100K DSP per 10% TDE', () {
      expect(service.getCurrentCommunityEpoch(2200, 2).level, 1);
      expect(service.getCompletedTgeEvents(2200, 2), 0);
      expect(service.getCurrentTgeEventNumber(2200, 2), 1);
      expect(service.getNextCommunityMilestone(2200, 2), 100000);

      expect(service.getCurrentCommunityEpoch(999999, 34).level, 1);
      expect(service.getCompletedTgeEvents(999999, 34), 9);
      expect(service.getCurrentTgeEventNumber(999999, 34), 10);
      expect(service.getNextCommunityMilestone(999999, 34), 1000000);
    });

    test('Epoch 2 has strict 10,000,000 Max Supply (1M -> 10M, 900K DSP per 10% TDE)', () {
      // Exact Epoch 1 -> Epoch 2 transition at 1,000,000 cumulative DSP
      final ep2AtStart = service.getCurrentCommunityEpoch(1000000, 34);
      expect(ep2AtStart.level, 2);
      expect(ep2AtStart.dspTarget, 10000000);
      expect(ep2AtStart.cumulativeDspStart, 1000000);
      expect(ep2AtStart.cumulativeDspTarget, 10000000);
      expect(ep2AtStart.epochDspRange, 9000000);
      expect(ep2AtStart.epochEarnedDsp(1000000), 0);
      expect(ep2AtStart.calculateProgress(1000000, 34), 0.0);
      expect(service.getCompletedTgeEvents(1000000, 34), 0);
      expect(service.getCurrentTgeEventNumber(1000000, 34), 1);
      expect(service.getNextCommunityMilestone(1000000, 34), 1900000);

      // Live snapshot: 1,081,497 cumulative DSP -> 81,497 earned in Epoch 2 (0 completed Epoch 2 TDEs)
      final ep2Live = service.getCurrentCommunityEpoch(1081497, 34);
      expect(ep2Live.level, 2);
      expect(ep2Live.epochEarnedDsp(1081497), 81497);
      expect(
        ep2Live.calculateProgress(1081497, 34),
        closeTo(81497 / 9000000, 1e-6),
      );
      expect(service.getCompletedTgeEvents(1081497, 34), 0);
      expect(service.getCurrentTgeEventNumber(1081497, 34), 1);
      expect(service.getNextCommunityMilestone(1081497, 34), 1900000);

      // Epoch 2 TDE 1 reached at 1,900,000 cumulative (+900,000 in Epoch 2)
      expect(service.getCurrentCommunityEpoch(1900000, 34).level, 2);
      expect(service.getCompletedTgeEvents(1900000, 34), 1);
      expect(service.getCurrentTgeEventNumber(1900000, 34), 2);
      expect(service.getNextCommunityMilestone(1900000, 34), 2800000);

      // Just before Epoch 2 completion (9,999,999 cumulative)
      expect(service.getCurrentCommunityEpoch(9999999, 99).level, 2);
      expect(service.getCompletedTgeEvents(9999999, 99), 9);
      expect(service.getCurrentTgeEventNumber(9999999, 99), 10);
      expect(service.getNextCommunityMilestone(9999999, 99), 10000000);
    });

    test('Epoch 3 unlocks at exact 10,000,000 cumulative DSP and Epoch 10 caps at exact 1QD', () {
      final ep3 = service.getCurrentCommunityEpoch(10000000, 100);
      expect(ep3.level, 3);
      expect(ep3.dspTarget, 100000000);
      expect(ep3.cumulativeDspStart, 10000000);
      expect(ep3.cumulativeDspTarget, 100000000);
      expect(ep3.epochDspRange, 90000000);
      expect(service.getCompletedTgeEvents(10000000, 100), 0);
      expect(service.getNextCommunityMilestone(10000000, 100), 19000000);

      final ep10 = service.getCurrentCommunityEpoch(100000000000000, 1000000000);
      expect(ep10.level, 10);
      expect(ep10.dspTarget, EpochService.absoluteSupplyCap);
      expect(ep10.cumulativeDspTarget, 1000000000000000);
    });
  });
}
