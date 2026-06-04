# Investors → Liquidity rename — deploy runbook

**Status:** code merged 2026-06-04, **migration script + backend deploy still pending in production**.

## Context

Pre-2026-06-04 the system treasury slot now called "Liquidity (DEX)" was historically called "Investors & Partners". The on-chain side was migrated earlier the same day (the Liquidity Safe holds the actual $DIASPORA), but two streams of off-chain DSP-point data still flowed to the legacy `investors` names:

- `governance/investors.treasuryBalance` (e.g. 200 DSP at audit time)
- `system_stats/treasury.investorsPoints`

The user-visible symptom: the "Liquidity Treasury" card on the crypto screen showed `200 DSP` instead of the `500 $DIASPORA` actually held in the Safe — because the card was wired to `unitId: 'investors'` and falling back to the Firestore DSP balance when on-chain returned 0.

## What the rename PR contains

- `functions/lib/dsp.js` — all writes redirected from `investorsPoints`/`governance/investors` to `liquidityPoints`/`governance/liquidity`. The legacy `investors` system-slot is removed from the TGE distribution loop.
- `functions/lib/wallet.js` — `ensureSystemWallets` no longer creates an investors smart wallet or writes `governance/investors`. Liquidity is now Safe-managed.
- `functions/scripts/migrate-investors-to-liquidity.js` — one-shot Firestore migration that sums the legacy balances into the canonical ones and zeros the legacy fields.
- `lib/features/dsp/screens/diaspora_crypto_screen.dart` — Liquidity card switched to `unitId: 'liquidity'`; `isSystemReserve` check updated.
- `lib/features/dsp/screens/points_system_screen.dart` — sums `liquidityPoints + investorsPoints` so the screen renders correctly both before and after migration.
- Tests in `test/dsp_distribution_test.dart`, `test/simulation/epoch_simulation_test.dart`, `test/features/dsp/repository/hierarchy_distribution_test.dart` updated.

## Deploy order — DO NOT SKIP STEPS

The order matters because new awards in the window between any two steps could land in the wrong slot. The safe sequence:

### Step 1 — Deploy the new backend FIRST

```bash
cd functions
firebase deploy --only functions --project diaspora-nearby-a3dac
```

After this, all new `awardPoints` / tribute writes go to `governance/liquidity` and `liquidityPoints`. The legacy fields stop receiving new data.

**Verify:** in Firebase logs, after one new user signup or DSP award, check that `governance/liquidity.treasuryBalance` increments and `governance/investors.treasuryBalance` does NOT.

### Step 2 — Dry-run the data migration

```powershell
$env:GOOGLE_APPLICATION_CREDENTIALS = "C:\Users\Nemo CLAW\.gcloud\diaspora-nearby-sa.json"
$env:DRY_RUN = "1"
node functions/scripts/migrate-investors-to-liquidity.js
```

Confirm the printed numbers match what you expect (legacy investors balance moves into liquidity, zeros out).

### Step 3 — Live migration

```powershell
Remove-Item Env:\DRY_RUN -ErrorAction SilentlyContinue
node functions/scripts/migrate-investors-to-liquidity.js
```

The script is idempotent — re-running on already-migrated data is a no-op.

**Verify in Firestore console:**
- `governance/liquidity.treasuryBalance` == sum (was-liquidity + was-investors)
- `governance/investors.treasuryBalance` == 0, with audit fields `migratedToLiquidityAt` and `migratedAmount` set
- `system_stats/treasury.liquidityPoints` == sum
- `system_stats/treasury.investorsPoints` == 0

### Step 4 — Deploy the updated Flutter app

```bash
flutter build apk --release    # or your release pipeline
# then publish via your normal channel
```

The app already handles the transition gracefully (sums both fields), so older app versions continue to work pre- and post-migration. New app version uses the canonical `unitId: 'liquidity'` for the card.

## Post-deploy verification

In the app, on the $DIASPORA Token Ecosystem screen → Treasuries tab → "Liquidity Treasury" card:

- Should display **on-chain $DIASPORA balance** (e.g. 500), not "DSP".
- Tapping it should open the Liquidity Safe address `0xF0f15Cf38Ef463E0fF46DC0540489F466E222edB` (post-migration).

If the card still shows "DSP" units, pull down to refresh, or kill and reopen the app (`tokenBalanceProvider` is Riverpod-cached — see [the refresh fix](../../lib/features/dsp/screens/diaspora_crypto_screen.dart) added the same day).

## Rollback plan

If something goes wrong mid-deploy:

- **After Step 1 only** (backend deployed, no migration yet): revert the backend deploy. New writes land back in `investors`. Legacy + canonical fields diverge by however many awards happened during the window — accept it or run migration anyway.
- **After Step 3** (migration ran): there's no clean rollback because the legacy field is now 0. You can re-revert the backend, but the migration is one-way for the balance. If you absolutely must undo: read `governance/investors.migratedAmount` (preserved as audit field), add it back to `treasuryBalance` and subtract from `governance/liquidity.treasuryBalance`. Then revert backend.

## Files to clean up later (low priority)

These still reference `investors` but are not on the hot write path. Safe to leave for now; remove in a follow-up PR if you want a fully clean codebase:

- `functions/scripts/register-treasury-wallets.js` (one-shot setup script, run once historically)
- `functions/scripts/backfill-wallets.js` (admin-only, references the old salt)
- `functions/scripts/wipe-test-treasury-residue.js` (test-data cleanup; references legacy doc on purpose)
- `functions/scripts/audit-governance-tge-readiness.js` (audit script that knows about the legacy slot — intentional)
- `blockchain/scripts/create-treasury-wallets.js` (historical CREATE2 generator)
- `blockchain/scripts/admin/manual-welcome-bonus.js` (admin script with legacy comment)
- `blockchain/scripts/admin/corrective-mint-tge1-treasuries.js` (one-off corrective; superseded)
- `MASTER_SOURCE_OF_TRUTH.md`, `DSP_TOKEN_BUILDER_INTEGRATION.md`, `landing/*.html`, `web/project/index.html` (docs / marketing copy, semantic rather than code)
- `blockchain/contracts/DiasporaTGEController.sol` comments mention "investors" — Solidity comments, no behavior change

## See also

- [project-system-treasuries](../../../Users/Nemo%20CLAW/.claude/projects/C--Projects-DiasporaNearby/memory/project_system_treasuries.md) — canonical treasury list
- [project-treasury-safe-addresses](../../../Users/Nemo%20CLAW/.claude/projects/C--Projects-DiasporaNearby/memory/project_treasury_safe_addresses.md) — live Safe addresses
- [project-treasury-spend-rules](../../../Users/Nemo%20CLAW/.claude/projects/C--Projects-DiasporaNearby/memory/project_treasury_spend_rules.md) — DDI + FDDI as only legitimate community-treasury outflow
