# Enterprise Readiness

This document tracks the operating standards Diaspora Nearby should meet before production promotion. It is intentionally practical: every item should map to code, CI, GitHub settings, an owner action, or a release decision.

## Current Baseline

- Default integration branch: `dev`.
- Promotion branches: `staging` and `production`.
- Required CI on `dev`: Flutter format/analyze/test, Firebase Functions lint and production audit, Firestore rules tests, blockchain compile/test and production audit, repository hygiene.
- Dependabot alerts: expected to be zero open alerts. Development-only alerts without a patched version may be dismissed only with a written rationale.
- Branch protections and rulesets: desired, but currently blocked by GitHub plan/settings for this private repository.

## Release Gates

Before promoting `dev` to `staging`:

- CI is green on the exact `dev` commit being promoted.
- Product owner confirms the release scope.
- Firebase rules, Functions, and blockchain changes have targeted validation.
- App version/build number is ready for store or internal distribution.
- Any new environment variables are documented in the relevant `.env.example` file.

Before promoting `staging` to `production`:

- Acceptance testing is complete on the staging build.
- Crash/error monitoring is checked for the staging build.
- Rollback plan is known and documented in the release notes.
- Security-sensitive changes have a second review.
- No open high, critical, or production-scope dependency alerts remain.

## CTO Backlog

These are not optional forever, but they are too large to hide inside a small repo-governance branch.

- Enable GitHub branch protection or repository rulesets after upgrading the repo/account plan or making the repository public.
- Enable GitHub secret scanning and code scanning when available for this repository.
- Rotate any previously committed Firebase service-account key and coordinate git history purging if a real secret was exposed.
- Migrate blockchain tooling from Hardhat 2 / ethers v5 to the current Hardhat/OpenZeppelin stack to remove development-only transitive crypto alerts without overrides.
- Replace the pinned Flutter SDK workaround after migrating away from packages affected by Flutter `IconData` changes.
- Add monitored staging and production release runbooks once deployment targets and owners are finalized.
