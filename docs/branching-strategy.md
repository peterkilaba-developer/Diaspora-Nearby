# Branching Strategy

Diaspora Nearby uses a staged promotion model.

## Long-Lived Branches

- `dev`: integration branch for feature and bugfix work.
- `staging`: release-candidate branch for validation before production.
- `production`: production-ready branch.
- `main`: legacy/default branch until the repository default branch is intentionally changed.

## Short-Lived Branches

- `feature/<name>` targets `dev`.
- `bugfix/<name>` targets `dev`.
- `release/<version>` targets `staging`.
- `hotfix/<name>` targets `staging` or `production`, depending on urgency.

## Promotion Flow

1. Merge feature and bugfix branches into `dev`.
2. Promote `dev` into `staging` after CI passes and the release candidate is ready.
3. Promote `staging` into `production` after acceptance testing.
4. Back-merge production hotfixes into `dev` so future releases keep the fix.

## Required Gates

- CI must pass before merge.
- Branch names must follow the patterns above.
- No secrets, generated caches, or local signing artifacts may be committed.
- Security-sensitive changes should be reviewed before promotion.
