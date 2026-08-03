# Changelog

All notable changes to Diaspora Nearby are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning: [SemVer](https://semver.org/).

## [1.2.0] — 2026-06-04

### Added

- **Chamber leadership flow.** Users can request appointment to a corridor chamber leadership seat; platform admins approve via `/admin/chamber-requests`. Approval triggers the `onChamberLeadershipRequestApproved` Cloud Function which performs the appointment server-side. New `appoint-chamber-leader.js` script for emergency manual appointments and `backfill-corridor-chambers.js` for pre-existing corridors.
- **Community Emergency Fund — `$DIASPORA` flow.** End-to-end contribution path: quote → pay → stats → claim trigger → fraud-slashing handler. New transparency screen at `/dsp/emergency-fund/transparency` exposes balance, recent claims, and slashing events. Ledger entries (`emergency_fund_ledger`) are authenticated-read, server-only write.
- **Corridor activity module.** Shared `corridor_activity.js` helper computes activity scores used by distribution and the GVI corridor list view.
- **Phone E.164 normalizer.** Pure-Dart normalization via `phone_numbers_parser` strips national trunk prefixes during onboarding; `device_region` provides SIM/network country ISO for auto-detection. `audit-phone-trunk-prefix.js` flags existing user docs that still carry trunk prefixes.
- **Organization chat overhaul.** Refreshed chat surface — header, more-menu sheet, message input affordances, location preview, media flow. Chamber leadership hooks visible directly from chat.
- **Firestore rules unit tests.** New `firestore-rules-test/` workspace with `@firebase/rules-unit-testing` covering chamber chat posting (members vs followers), leadership-request lifecycle, emergency-fund-ledger access, and corridor-chamber organization-update gating.

### Changed

- **Investors → Liquidity treasury rename.** "Investors" treasury is deprecated. `migrate-investors-to-liquidity.js` performs the Firestore-pointer + label change; `repoint-treasury-wallet.js` updates the on-chain pointer. See `docs/runbooks/investors-to-liquidity-rename.md`.
- **Slimmer account section.** Stripped ~336 lines of dead UI paths in `account_section.dart` and deleted the unreachable `storage_settings_screen`.
- **DSP refactor.** Tightened distribution logic in `functions/lib/dsp.js`; simplified client-side `points_service` / `points_repository`; refreshed Diaspora Crypto and Points System screens.
- **Corridor list now reads from chamber docs.** `streamCorridors` and `streamInternalGdp` now derive from `organizations` where `kind == 'corridor_chamber'` — single source of truth, no more drift between treasury totals and per-corridor rollups.
- **Trust score model v3.** Council eligibility now requires `daysActive >= 100 AND isAdminOfLargeGroup AND finalScore >= 91`, with separate Vouch and Verified milestones and +10 PCT each.

### Security

- **Chamber chat posting gated on accessLevel.** In `chats` where `subtype == 'corridor_chamber'`, posting requires `accessLevel == 'member'` on the user's `userChats` entry. Followers remain read participants but cannot post.
- **Corridor-chamber organizations system-managed.** Non-admins can only touch `members` / `followers` / `memberCount` / `updatedAt` on `kind == 'corridor_chamber'` docs. Substantive edits (name, admins, leadership) require platform admin.
- **`/leadershipRequests` collection** introduced with strict create/update/delete rules — users can only create their own pending request and self-withdraw while pending; only admins can approve.
- **Safe-controlled system treasuries.** `migrate-treasury-balance-to-safe.js` and `check-burn-wallet-residue.js` admin scripts for the 2026-06 Safe migration. Backend signer can no longer move Founders / Liquidity / Global Fund Reserve.

### Fixed

- **Proximity / transfer / wallet hardening.** Restructured corridor matching to share helpers with the corridor activity module; tightened error handling around on-chain calls in `transfer.js` and `wallet.js`.

### Tests

- 67/67 Flutter tests pass. Failing tests realigned with the cloud-function-mediated points path; trust service tests stub `emergencyFundServiceProvider` and `chatRepositoryProvider` to avoid `Firebase.instance`. Treasury distribution math is exercised by `test/dsp_distribution_test.dart`; rewritten repository tests now assert the right callables are invoked.

### Ops — still your call

- Deploy `firestore.rules` to prod: `firebase deploy --only firestore:rules`.
- Run staged ops scripts in this order (dry-run first): `migrate-investors-to-liquidity.js` → `backfill-corridor-chambers.js` → `audit-phone-trunk-prefix.js`.
- Coordinate `migrate-treasury-balance-to-safe.js` via multisig.
