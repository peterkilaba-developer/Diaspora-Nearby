import 'package:flutter_test/flutter_test.dart';
import 'package:diaspora_nearby/features/dsp/services/epoch_service.dart';

void main() {
  test('EpochService Logic Repro', () {
    final service = EpochService();

    // Scenario 1: User Experience (2200 DSP, 2 Members)
    // Expected: 0 Steps (0% Unlock)
    int steps = service.getCompletedTgeEvents(2200, 2);
    print('\n--- REPRO OUTPUT START ---');
    print('Scenario 1 (2200 DSP, 2 Members): $steps Steps');

    // Scenario 2: Target Met
    steps = service.getCompletedTgeEvents(1000000, 100);
    print('Scenario 2 (1M DSP, 100 Members): $steps Steps');

    // Scenario 3: Small
    steps = service.getCompletedTgeEvents(1000, 1);
    print('Scenario 3 (1000 DSP, 1 Members): $steps Steps');
    print('--- REPRO OUTPUT END ---\n');
  });
}
