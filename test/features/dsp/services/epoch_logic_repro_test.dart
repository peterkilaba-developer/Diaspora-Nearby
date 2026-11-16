// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:diaspora_nearby/features/dsp/services/epoch_service.dart';

void main() {
  group('EpochService 10x Progressive Scaling', () {
    final service = EpochService();

    test('Epoch 1 requires 1M DSP with 100K DSP per 10% TDE', () {
      expect(service.getCurrentCommunityEpoch(2200, 2).level, 1);
      expect(service.getCompletedTgeEvents(2200, 2), 0);
      expect(service.getCurrentTgeEventNumber(2200, 2), 1);
      expect(service.getNextCommunityMilestone(2200, 2), 100000);

      expect(service.getCurrentCommunityEpoch(999999, 34).level, 1);
      expect(service.getCompletedTgeEvents(999999, 34), 9);
      expect(service.getCurrentTgeEventNumber(999999, 34), 10);
      expect(service.getNextCommunityMilestone(999999, 34), 1000000);
    });

    test('Epoch 2 requires 10M new DSP (cumulative 1M -> 11M) with 1M DSP per 10% TDE', () {
      // Exact Epoch 1 -> Epoch 2 transition at 1,000,000 cumulative DSP
      final ep2AtStart = service.getCurrentCommunityEpoch(1000000, 34);
      expect(ep2AtStart.level, 2);
      expect(ep2AtStart.dspTarget, 10000000);
      expect(ep2AtStart.cumulativeDspStart, 1000000);
      expect(ep2AtStart.cumulativeDspTarget, 11000000);
      expect(ep2AtStart.epochEarnedDsp(1000000), 0);
      expect(ep2AtStart.calculateProgress(1000000, 34), 0.0);
      expect(service.getCompletedTgeEvents(1000000, 34), 0);
      expect(service.getCurrentTgeEventNumber(1000000, 34), 1);
      expect(service.getNextCommunityMilestone(1000000, 34), 2000000);

      // Live snapshot: 1,043,600 cumulative DSP -> 43,600 earned in Epoch 2 (0 completed Epoch 2 TDEs)
      final ep2Live = service.getCurrentCommunityEpoch(1043600, 34);
      expect(ep2Live.level, 2);
      expect(ep2Live.epochEarnedDsp(1043600), 43600);
      expect(ep2Live.calculateProgress(1043600, 34), closeTo(0.00436, 1e-6));
      expect(service.getCompletedTgeEvents(1043600, 34), 0);
      expect(service.getCurrentTgeEventNumber(1043600, 34), 1);
      expect(service.getNextCommunityMilestone(1043600, 34), 2000000);

      // Epoch 2 TDE 1 reached at 2,000,000 cumulative (1,000,000 earned in Epoch 2)
      expect(service.getCurrentCommunityEpoch(2000000, 34).level, 2);
      expect(service.getCompletedTgeEvents(2000000, 34), 1);
      expect(service.getCurrentTgeEventNumber(2000000, 34), 2);
      expect(service.getNextCommunityMilestone(2000000, 34), 3000000);

      // Just before Epoch 2 completion (10,999,999 cumulative = 9,999,999 earned in Epoch 2)
      expect(service.getCurrentCommunityEpoch(10999999, 99).level, 2);
      expect(service.getCompletedTgeEvents(10999999, 99), 9);
      expect(service.getCurrentTgeEventNumber(10999999, 99), 10);
      expect(service.getNextCommunityMilestone(10999999, 99), 11000000);
    });

    test('Epoch 3 unlocks at 11M cumulative DSP and requires 100M new DSP (10M per TDE)', () {
      final ep3 = service.getCurrentCommunityEpoch(11000000, 100);
      expect(ep3.level, 3);
      expect(ep3.dspTarget, 100000000);
      expect(ep3.cumulativeDspStart, 11000000);
      expect(ep3.cumulativeDspTarget, 111000000);
      expect(service.getCompletedTgeEvents(11000000, 100), 0);
      expect(service.getNextCommunityMilestone(11000000, 100), 21000000);
    });
  });
}
