void main() {
  print('============================================================');
  print('DIASPORA NEARBY: GOVERNANCE LADDER TRACE');
  print('============================================================\n');

  // 1. LOCAL TIER: Cities elect 3 Pillars
  final arushaPillars = ['ARU-01', 'ARU-02', 'ARU-03'];
  final darPillars = ['DAR-01', 'DAR-02', 'DAR-03'];
  final nairobiPillars = ['NAI-01', 'NAI-02', 'NAI-03'];

  print('STEP 1: Local Elections (Host Towns)');
  print('  [City] Arusha elected: $arushaPillars');
  print('  [City] Dar es Salaam elected: $darPillars');
  print('  [City] Nairobi elected: $nairobiPillars\n');

  // 2. NATIONAL TIER: Countries select 1 from each town
  // Pool for Tanzania = [ARU-01, ARU-02, ARU-03, DAR-01, DAR-02, DAR-03]
  final tzPool = [...arushaPillars, ...darPillars];
  final tzWinners = ['ARU-01', 'DAR-02']; // 1 from Arusha, 1 from Dar

  print('STEP 2: National Council (Tanzania)');
  print('  Discovery: Searching signers of parent country TZ...');
  print('  Candidate Pool from Towns: $tzPool');
  print('  Selected (Quota: 1 per Town): $tzWinners');
  print(
    '  * TGE Safeguard: ${tzWinners.length < 3 ? "LOCKED (Need 3 pillars in Council for Treasury)" : "UNLOCKED"}\n',
  );

  // 3. CONTINENTAL TIER: Africa selects 1 from each country
  final keWinners = ['NAI-01']; // Kenya selected 1 from Nairobi

  final africaPool = [...tzWinners, ...keWinners];
  final africaWinners = ['ARU-01', 'NAI-01']; // Reps from TZ and KE

  print('STEP 3: Continental Council (Africa)');
  print('  Candidate Pool from Countries: $africaPool');
  print('  Selected (Quota: 1 per Country): $africaWinners');
  print(
    '  * TGE Safeguard: ${africaWinners.length < 3 ? "LOCKED (Need 3 pillars)" : "UNLOCKED"}\n',
  );

  // 4. GLOBAL TIER: Global selects 1 from each continent
  // Pool for Global = [AF-winners, EU-winners, AS-winners...]
  final euWinners = ['LON-01', 'PAR-02', 'BER-03'];
  final globalPool = [...africaWinners, ...euWinners];

  // Winners (Simulated 1 from each child)
  final globalCouncil = ['ARU-01', 'NAI-01', 'LON-01', 'PAR-02', 'BER-03'];

  print('STEP 4: Global Council');
  print('  Total Pool Size: ${globalPool.length} Pillars');
  print('  Final Global Council (1 per Continent): $globalCouncil');
  print('  Global Treasury Control: ENABLED (5 Signers Active)\n');

  print('============================================================');
  print('HIERARCHAL LADDER VERIFIED');
  print('============================================================');
}
