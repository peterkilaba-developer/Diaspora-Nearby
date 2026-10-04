# Enterprise Readiness

This document tracks the operating standards Diaspora Nearby should meet before production promotion. It is intentionally practical: every item should map to code, CI, GitHub settings, an owner action, or a release decision.

## 2026-08-17 Production Audit

The repository-level critical authorization and value-integrity findings have
been remediated. Production promotion is still blocked until the deployment
runbook is executed because existing production data, Firebase projects,
secrets, App Check enforcement, and deployed immutable contracts cannot be
changed by a source-code patch alone.

Implemented controls:

- Firebase authorization trusts custom claims and canonical parent documents,
  not client-editable profile or inbox fields.
- Financial, governance, trust, wallet, membership, and treasury writes are
  server-owned; legacy client reward endpoints require an admin claim.
- Exact location, phone, date of birth, notification tokens, block lists, and
  tax identifiers are stored in owner-only `user_private` documents. Nearby
  search returns an explicit allowlist and computes distance server-side.
- Callable APIs require authentication and App Check, with persistent quotas on
  abuse/cost-sensitive paths. OTPs use CSPRNG values, keyed hashes, attempt
  limits, expiry, and constant-time comparison.
- Stripe webhooks fail closed on signature, amount, currency, product, and
  replay checks. Checkout creation is serialized per user and contributor
  status is one-time. Transfers are validated, rate-limited, and idempotent.
- Chat membership and inbox fan-out are canonical and server-authored. Storage
  media is limited by participant, type, and size; account erasure anonymizes
  messages and deletes owned media references.
- Entity chats, geographic communities, organization/chamber membership, and
  peer bookings are created through canonical backend transactions. Booking
  state transitions reserve deterministic daily slots and reject overlaps;
  private group additions use explicit invitations.
- QR connections and hosted event check-ins use short-lived, single-use server
  challenges. Client-authored physical-presence and sybil-farmable rating
  rewards are disabled pending invariant-safe server reward policy.
- Hosting arrangements use canonical server-created records, host-issued
  one-time QR challenges, and two-party checkout. Abuse reports and listing
  engagement counters are rate-limited/idempotent backend operations and do
  not directly mint value or alter trust.
- Nearby queries use geohash bounds; organization/chat discovery uses bounded,
  indexed queries; Flutter paints its bootstrap shell immediately, schedules
  optional subsystems after first-paint readiness, and has no runtime web-font
  fetch.
- Chat write triggers avoid all-participant index rewrites for ordinary message
  updates, and deterministic community bootstrap removes the former lookup plus
  multi-document client fan-out path.
- Dev/staging Firebase configuration fails closed against the production
  project. Hosting sends HSTS, CSP, MIME-sniffing, referrer, and permissions
  headers. CI actions are commit-pinned and release web builds are gated.
- Smart-contract V2 initialization is admin-only. Wallet signer rotation is
  bounded, auditable, and constrained to the factory's active signer.
- Public landing intake is server-validated and rate-limited; browser fallbacks
  cannot write protected collections or claim false success. Places and radio
  proxies are route-bounded, quota-controlled, size-limited, and timed out.
- Referral redemption, governance voting, and chat-solution verification are
  authenticated idempotent server workflows. Generic client-selected rewards
  and penalties remain disabled until each product event has server-verifiable
  proof and an approved supply-accounting policy.
- Relationship acceptance, reciprocal projections, blocking, and direct-chat
  pair indexes are server-authored and idempotent. Message rules enforce blocks
  in both directions, and the bounded migration reports legacy conflicts before
  these rules are promoted.
- The Dart lockfile is current within existing constraints. Remaining
  constraint/major upgrades are staged work, not silently mixed into this
  security release.

Required external gates are documented in
`docs/runbooks/security-hardening-deploy.md`. Until every gate is signed off,
the accurate status is **staging-ready, production deployment pending**.
The detailed audit and verification matrix is in
`docs/audits/enterprise-production-readiness-2026-08-17.md`.

## Current Baseline

- Default integration branch: `dev`.
- Promotion branches: `staging` and `production`.
- Required CI on `dev`: Flutter format/analyze/test/release build, Firebase
  Functions lint/load/callable-control/full high-threshold audit, Firestore rules tests and
  tooling audit, blockchain compile/test/full high-threshold audit, admin-tool
  audit, index validation, and repository hygiene.
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
- Upgrade the 26 direct Dart constraints that are behind resolvable versions in
  staged compatibility batches, with platform smoke tests after each FlutterFire,
  payments, media, and permissions migration.
- Replace the current 100-recipient push TGE with an independently audited
  claim-based Merkle distributor before the eligible population reaches that
  boundary.
- Move the smart-wallet backend signer and all privileged contract roles to a
  reviewed multisig/HSM policy; the present wallet model is intentionally
  custodial.
- Add SLO dashboards and alerts for p95 callable latency, error rate, Stripe
  webhook retries, notification failures, Firestore read volume, RPC failures,
  and pending on-chain reconciliation states.
- Run independent smart-contract and penetration-test reviews before mainnet
  promotion. Repository tests are not a substitute for independent assurance.
