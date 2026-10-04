import 'dart:math';
import 'package:diaspora_nearby/features/dsp/services/epoch_service.dart';

// Mock User Class for Simulation
class SimulatedUser {
  final String id;
  double dspBalance;
  int trustScore;
  double totalTokensMinted; // Cumulative TGE tokens received
  final String activityLevel; // "High", "Medium", "Low"

  SimulatedUser({
    required this.id,
    this.dspBalance = 0,
    this.trustScore = 0,
    this.totalTokensMinted = 0,
    required this.activityLevel,
  });
}

void main() {
  print('=============================================');
  print('       TGE EPOCH SIMULATION (1-7)            ');
  print('   Model: Constant Rewards + Rising Gates    ');
  print('=============================================');

  final epochService = EpochService();
  final random = Random();

  // 1. Initialize Population
  // We'll simulate a small cohort to keep logs readable but representative
  final int populationSize = 50;
  final List<SimulatedUser> users = [];

  for (int i = 0; i < populationSize; i++) {
    String level;
    int rand = random.nextInt(100);
    if (rand < 20) {
      level = "High"; // 20% Power Users
    } else if (rand < 70)
      level = "Medium"; // 50% Average Users
    else
      level = "Low"; // 30% Casual Users

    // Initial Trust Score (varies by activity level)
    int trust = 0;
    if (level == "High") {
      trust = 40 + random.nextInt(30); // 40-70
    } else if (level == "Medium")
      trust = 20 + random.nextInt(40); // 20-60
    else
      trust = 10 + random.nextInt(30); // 10-40

    users.add(
      SimulatedUser(id: 'User_$i', activityLevel: level, trustScore: trust),
    );
  }

  print('Initialized $populationSize users.');

  // 2. Simulation Loop (Epochs 1-7)
  // We simulate "time" passing as activity cycles.
  // Each Epoch will have a fixed duration of "Activity Cycles" (e.g., Days)

  // Assumption: 1 Cycle = 1 Day approx
  // High User: ~1500 DSP/day
  // Medium User: ~500 DSP/day
  // Low User: ~100 DSP/day

  // To reach Epoch 1 Gate (10k), High user needs ~7 days. Low user needs ~100 days.
  // Let's set a standard "Epoch Duration" in days to see who makes it.
  // ignore: unused_local_variable
  const int daysPerEpoch = 30; // Monthly TGE checks? Or maybe longer?
  // Let's assume TGE happens every quarter (90 days) for realism in this simulation context
  // allowing accumulation.
  const int simulatedDaysPerEpoch = 90;

  double totalProtocolMinted = 0;

  for (final epochDef in epochService.getAllEpochs()) {
    print('\n-----------------------------------------------------------');
    print(
      '[EPOCH ${epochDef.epochNumber}: Epoch ${epochDef.epochNumber}] START',
    );
    print(
      '  Model: Positive DSP  |  Efficiency: Exact PCT (Proof of Community Trust) Percent',
    );
    print('-----------------------------------------------------------');

    // --- A. Simulate Activity (Earning Phase) ---
    print('  Simulating $simulatedDaysPerEpoch days of activity...');
    for (var user in users) {
      // Simulate Daily Earnings
      double dailyRate = 0;
      if (user.activityLevel == "High") {
        dailyRate = 1200 + random.nextDouble() * 500; // 1200-1700
      } else if (user.activityLevel == "Medium")
        dailyRate = 400 + random.nextDouble() * 400; // 400-800
      else
        dailyRate = 50 + random.nextDouble() * 150; // 50-200

      double totalEarnedThisEpoch = dailyRate * simulatedDaysPerEpoch;
      user.dspBalance += totalEarnedThisEpoch;

      // Simulate Trust Growth (Slow steady increase)
      if (user.activityLevel == "High") user.trustScore += 5;
      if (user.activityLevel == "Medium") user.trustScore += 2;
      if (user.activityLevel == "Low") user.trustScore += 0; // Stagnant

      // Cap trust at 100
      if (user.trustScore > 100) user.trustScore = 100;
    }

    // --- B. TDE Release (Gate Check) ---
    int qualifiedCount = 0;
    double mintedThisEpoch = 0;
    double rolloverThisEpoch = 0;

    for (var user in users) {
      bool eligible = epochService.isEligibleForTGE(
        epochNumber: epochDef.epochNumber,
        userTotalDsp: user.dspBalance,
      );

      if (eligible) {
        qualifiedCount++;
        double swapAmount = user.dspBalance;

        // MINT TOKENS
        user.totalTokensMinted += swapAmount;
        mintedThisEpoch += swapAmount;

        // RESET POINTS (Burn/Swap)
        user.dspBalance = 0;
      } else {
        // ROLLOVER
        rolloverThisEpoch += user.dspBalance;
      }
    }

    totalProtocolMinted += mintedThisEpoch;

    // --- C. Reporting ---
    print('  TGE Results:');
    print(
      '   - Qualified Users: $qualifiedCount / $populationSize (${((qualifiedCount / populationSize) * 100).toStringAsFixed(1)}%)',
    );
    print('   - Minted (Tokens): ${mintedThisEpoch.toStringAsFixed(0)}');
    print('   - Rollover (DSP):  ${rolloverThisEpoch.toStringAsFixed(0)}');
    print('   - Cumulative Minted: ${totalProtocolMinted.toStringAsFixed(0)}');

    // Sample User Check
    var sampleHigh = users.firstWhere((u) => u.activityLevel == "High");
    var sampleLow = users.firstWhere((u) => u.activityLevel == "Low");
    print('  Sample Stats:');
    print(
      '   [HIGH User] Trust: ${sampleHigh.trustScore}, DSP: ${sampleHigh.dspBalance.toStringAsFixed(0)}, Tokens: ${sampleHigh.totalTokensMinted.toStringAsFixed(0)}',
    );
    print(
      '   [LOW User]  Trust: ${sampleLow.trustScore},  DSP: ${sampleLow.dspBalance.toStringAsFixed(0)}, Tokens: ${sampleLow.totalTokensMinted.toStringAsFixed(0)}',
    );
  }

  print('\n=============================================');
  print('SIMULATION COMPLETE');
  print('=============================================');
}
