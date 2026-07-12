# Contributing to Diaspora Nearby

Thank you for helping improve Diaspora Nearby. This repository uses a staged promotion workflow so features can be integrated, validated, and released deliberately.

## Source of Truth

Before changing product behavior, review the `conductor/` directory:

- [CONDUCTOR.md](conductor/CONDUCTOR.md)
- [product.md](conductor/product.md)
- [tech-stack.md](conductor/tech-stack.md)
- [tracks.md](conductor/tracks.md)
- [workflow.md](conductor/workflow.md)

When markdown files disagree, treat the codebase, tests, and conductor files as authoritative.

## Branch Flow

Long-lived branches:

- `dev`: integration branch and default branch.
- `staging`: release-candidate validation branch.
- `production`: production-ready branch.
- `main`: legacy branch retained for history.

Short-lived branches:

- `feature/<name>` targets `dev`.
- `bugfix/<name>` targets `dev`.
- `release/<version>` targets `staging`.
- `hotfix/<name>` targets `staging` or `production`, depending on urgency.

Example:

```bash
git fetch origin
git switch dev
git pull --ff-only origin dev
git switch -c feature/your-feature-name
```

## Commit Convention

Use clear conventional prefixes:

- `feat:` new feature
- `fix:` bug fix
- `docs:` documentation
- `refactor:` code restructuring
- `test:` tests
- `ci:` CI or workflow changes
- `chore:` build, tooling, or maintenance

## Pull Requests

Before opening a PR:

- Confirm the branch target follows the branch flow above.
- Run the checks relevant to your change.
- Add or update tests for changed behavior.
- Update `.env.example` files when adding environment variables.
- Do not commit secrets, signing material, package directories, generated caches, or local diagnostic dumps.

## Validation

Common checks:

```bash
dart format --set-exit-if-changed lib test integration_test scripts
flutter analyze
flutter test
node scripts/check-repo-hygiene.js
```

Area-specific checks:

```bash
cd functions && npm run lint && npm audit --omit=dev --audit-level=high
cd firestore-rules-test && npm test
cd blockchain && npm run compile && npm test && npm audit --omit=dev --audit-level=high
```

## Release Promotions

- Promote `dev` to `staging` only after CI is green and the release scope is approved.
- Promote `staging` to `production` only after acceptance testing and rollback planning.
- Back-merge production hotfixes into `dev`.

See [docs/enterprise-readiness.md](docs/enterprise-readiness.md) for the release gate checklist.
