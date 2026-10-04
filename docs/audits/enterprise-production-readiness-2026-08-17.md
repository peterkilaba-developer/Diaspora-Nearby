# Enterprise Production Readiness Audit — 2026-08-17

## Decision

**Repository disposition: staging-ready after the ordered migration; production
promotion remains blocked by external and operational gates.**

The source tree no longer exposes the critical repository-level authorization,
PII, payment replay, or client-side value-mint paths found during this review.
That does not prove a deployed system is secure: production data must be
migrated, App Check and quotas must be enforced, old clients must be blocked,
credentials must be rotated, deployed contracts must be migrated, and the
release must pass independent security and load testing.

## Scope

- Flutter/Dart clients, startup, caching, query patterns, and environment split
- Firestore and Cloud Storage rules plus emulator tests
- Firebase callable/HTTP Functions, Auth/OTP, account erasure, notifications,
  proximity, chat, governance, payments, transfers, and wallet operations
- Solidity contracts, upgrade initialization, signer rotation, and test suite
- Hosting headers, CI supply-chain controls, dependency manifests, and runbooks
- Secret-pattern, repository-hygiene, and privileged-client-write review

## Remediated critical/high findings

1. **Privilege escalation:** platform administration now depends on Firebase
   custom claims. Client-editable profile fields cannot grant admin access.
2. **Value and governance integrity:** balances, ledgers, treasury state,
   governance outcomes, wallet provisioning, broad reward endpoints, and
   derived trust state are server-owned. Sybil-farmable first-rating rewards
   were removed.
3. **Chat authorization:** canonical chat participants control message access;
   per-user inbox documents cannot grant access. Membership, metadata,
   reactions, fan-out, event attendance, and community membership use
   authenticated/App Check–protected backend transactions.
4. **Physical-presence fraud:** profile URLs no longer count as QR proof. QR
   connections and hosted event check-ins use short-lived, random, single-use
   server challenges. Unverifiable geofence rewards are paused.
5. **PII exposure:** precise location, phone, date of birth, work/past
   locations, notification tokens, block lists, full hosting locations, and tax
   identifiers move to owner-only `user_private` documents. Search responses
   use explicit public-field allowlists.
6. **OTP/auth abuse:** WhatsApp OTPs use cryptographic randomness, normalized
   phone numbers, peppered hashes, hashed document IDs, quotas, expiry,
   attempt limits, transactions, and constant-time comparisons.
7. **Payments:** Stripe webhooks fail closed and validate signature, product,
   amount, and currency. Event/payment replay markers and per-user checkout
   locks prevent duplicate processing. Emergency-contributor trust is a
   one-time fact rather than an incrementable score.
   Emergency-fund disbursement cooldown and annual-cap checks also fail closed;
   the annual calculation uses a server aggregate instead of downloading an
   unbounded beneficiary ledger.
8. **Transfers/wallets:** transfer amounts, recipients, idempotency keys, rate
   limits, user existence, wallet formats, and pending states are validated.
   Wallet identifiers use keyed hashes; provisioning is privileged.
9. **Storage and erasure:** media access is participant-scoped with type/size
   limits. Account erasure requires recent authentication, removes Auth and
   private data, anonymizes retained ledgers/messages, and deletes owned media.
10. **Contracts:** V2 initialization is admin-only and one-time. Factory signer
    rotation is bounded and constrained to the current factory signer.
11. **Hosting and moderation:** hosting requests/sessions are created from
    canonical server data. Host-issued check-in codes are random, short-lived,
    single-use, and traveler-bound; checkout requires the other participant.
    Reports are rate-limited, idempotent, server-validated, and cannot directly
    change trust or award DSP.
12. **Listings and travel:** listing views, saves, and report counters are
    idempotent server operations. Mere listing contact is no longer recorded as
    GDP. Flight-order creation and paid-event creation fail closed until their
    reviewed payment/fulfillment workflows are available; synthetic travel
    fallback requires an explicit non-production flag.
13. **TGE execution:** the backend ABI now matches the four-argument V2
    contract, commits the Merkle root, reserves a deterministic event record
    before broadcast, and marks uncertain submissions for reconciliation
    instead of blind replay. Push distribution is capped at 100 recipients.
    Larger populations require the claim-based contract migration below.
14. **Public intake and outbound APIs:** feedback, app requests, tester signup,
    and liquidity-interest records are server-authored, validated,
    rate-limited, and deterministic where appropriate. Landing pages no longer
    fall back to direct database writes or show success after failed storage.
    Radio and Places proxies use fixed allowlisted routes, authenticated
    per-user quotas where applicable, parameter encoding, timeouts, and
    response-size limits; Places requires both Auth and App Check.
15. **Referral and voting integrity:** referral codes are derived from the
    authenticated profile and redemption is one idempotent server transaction
    that prevents self-referral and keeps the promotional supply ledger in
    sync. Governance votes derive the voter from Auth, verify community
    membership and candidate registration, are immutable, and use aggregate
    counts. Chat-solution verification is tied to an existing participant and
    message; client-selected group and verification rewards were removed.
16. **Relationships, blocks, and direct messages:** relationship requests and
    reciprocal relationship projections are now canonical, authenticated
    server transactions with reciprocal-type and unique-family-slot checks.
    Blocking is idempotent, updates the private block list and trust counter
    atomically, cancels pending requests, and is enforced by message rules in
    either direction. Direct chats use one server-owned pair index and
    deterministic IDs, while preserving bounded compatibility with legacy
    chats. Client-created direct chats and relationship state are denied.
17. **Daily activity and false reward paths:** daily check-in now uses server
    time, a deterministic daily ledger ID, and one atomic supply/treasury
    transaction. Unverifiable external/import share actions cannot manufacture
    balances, and the unfinished share-destination UI no longer reports a
    reward or successful delivery.
18. **Canonical entity creation:** clients can no longer mint chat authority,
    geographic communities, organization/chamber membership, or peer bookings.
    Authenticated/App Check-protected callables derive owners, admins, members,
    prices, dates, locations, and entity links from canonical documents. Group
    additions are invitations rather than forced membership, and blocks are
    enforced before an invitation is issued or accepted. The first user to
    materialize a geographic community no longer becomes its moderator;
    presentation administration remains platform/governance-controlled.
19. **Booking concurrency:** peer-booking creation is idempotent and derives the
    host, price, currency, and free-hosting eligibility on the server. Explicit
    transition rules limit who may confirm, reject, cancel, or complete a
    booking. Confirmed date ranges reserve deterministic daily slot documents
    in the same transaction, so concurrent confirmations cannot double-book a
    listing.

## Performance and scale changes

- Flutter paints a retryable bootstrap shell immediately while Firebase and
  preferences initialize. Audio, local database warm-up, notifications,
  Stripe settings, exchange rates, and other optional services do not hold the
  initial frame. Runtime Google Fonts were removed, eliminating that cold-start
  network dependency.
- Nearby search and proximity alerts use geohash bounds, deduplication, exact
  distance filtering, explicit result limits, and short client caching.
- Organization discovery combines indexed bounded streams rather than scanning
  the full organization collection.
- Public/discoverable chat metadata is materialized server-side to eliminate
  per-result chat reads. Chat inbox startup is cache-first and bounded to the
  latest 100 entries; broader discovery membership checks are capped.
- Chat trigger fan-out now writes indexes only for added/removed members or
  when projection fields change. Ordinary last-message updates no longer
  rewrite every participant inbox or the discoverable-chat projection.
- Direct-chat discovery is constant-time after the pair index is populated,
  with one bounded legacy query on the first unresolved lookup instead of an
  unbounded inbox read followed by one chat read per result. Chat clearing is
  processed in 400-entry pages with bounded read concurrency.
- Community hierarchy, event search, chat search, user search, and maintenance
  reads have explicit bounds or aggregation queries on user-facing paths.
- Geographic community bootstrap is one deterministic server transaction
  derived from the canonical profile. It replaces the former pre-query plus
  client-created community/chat/index fan-out and prevents namespace squatting.
- User notification feeds are participant-scoped and bounded. The former
  platform-wide hosting-session listener was replaced by indexed traveler and
  host queries. Admin dashboard totals use aggregation queries instead of live
  full-collection downloads.
- Country/corridor leaderboards are bounded and indexed; global internal GDP is
  read from the backend-maintained aggregate instead of summing every chamber
  on each client.
- Message fan-out is idempotent and concurrency-bounded. Media inbox previews
  are generated once by the backend instead of client-side cross-user writes.
- Account erasure processes matching records in bounded 400-document pages,
  avoiding unbounded memory use for long-lived accounts.
- Treasury balance Multicall reads are limited to fixed system reserves and
  the authenticated user's community treasuries instead of scanning every
  governance unit. Community-wallet and lifetime-earnings maintenance jobs
  return bounded continuation cursors rather than loading whole collections.
- The legacy client trust refresh no longer fans out across ratings,
  relationships, chats, and communities only to hit denied writes. Clients
  subscribe to the server-authored trust projection; reward-bearing trust
  recalculation remains disabled pending the policy gate below.

These controls improve cold-start behavior and bound database work; they do
not justify a literal "instant at any scale" claim. Production latency and
capacity require representative load tests and measured SLOs.

## Verification evidence

| Gate | Result |
| --- | --- |
| Flutter full static analysis | Clean, no issues |
| Flutter unit/widget tests | 81 passed |
| Production web release build | Passed |
| Functions ESLint | Passed |
| Callable security regression audit | 90 endpoints passed |
| Functions full npm audit | 0 vulnerabilities |
| Firestore + Storage emulator tests | 74 passed |
| Solidity tests | 81 passed |
| Functions/blockchain/admin production dependency audits | 0 high/critical production vulnerabilities |
| Repository hygiene | Passed; unexpected tracked credential patterns absent |
| Firebase/index JSON parse and diff whitespace check | Passed |

The existing integration-test target is not counted as passing evidence. The
installed Flutter runner rejects Chrome for `integration_test`, and the local
Windows run cannot initialize Firebase because this repository intentionally
has no Windows Firebase options. Exercise the production Android, iOS, and web
targets against staging as part of the operational gate below.

The Firebase-rules tooling tree now audits clean. The blockchain
**development-only** tree retains 13 low-severity transitive `elliptic`
findings in the OpenZeppelin Hardhat upgrade/verification toolchain; npm offers
only a breaking downgrade, not a patched compatible graph. It is not shipped
with the app or Functions runtime and must stay isolated from untrusted input.
The Dart lockfile was upgraded to the newest versions permitted by the current
constraints and generated test doubles were refreshed; analysis, 81 tests, and
the release web build pass on that graph. The inventory still has 26 direct
constraints behind resolvable versions. Those major/constraint changes require
staged platform compatibility work; `pub outdated` is not a vulnerability
scanner and is not evidence of exploitable advisories.

## Production blockers requiring external action

1. Execute and sample the public/private user-data migration, then dry-run and
   apply `migrate-relationship-security.js` and
   `migrate-canonical-entities.js`; block legacy
   clients before enforcing the new schema. Quarantine or validate legacy
   client-authored relationships, pending relationship requests, hosting
   sessions, listing interactions/counters, reports, trust stakes, event
   attendance, and flight confirmations before trusting historical records.
   Resolve every reported slot, duplicate-chat-pair, request, parent/chat,
   chamber-identity, booking-overlap, or truncation conflict before rules
   enforcement. The canonical-entity migration also backfills availability
   slots for confirmed legacy peer bookings.
2. Use separate Firebase/GCP projects and identities; rotate/restrict formerly
   embedded credentials—including the legacy Firebase CLI OAuth client—and
   verify no real service-account secret exists in history. Legacy admin
   scripts now use short-lived Application Default Credentials.
3. Enforce App Check for Functions, Firestore, Storage, and Auth; configure
   quotas/WAF or CAPTCHA for unauthenticated landing-page forms.
4. Move contract roles and the custodial backend signer to the approved
   multisig/HSM, migrate the immutable wallet factory, and obtain independent
   contract and application penetration-test reports.
5. Run restore drills, representative load/soak tests, and establish dashboards
   and alerts for latency, errors, denials, reads, webhook retries, and on-chain
   reconciliation.
6. Complete and independently review a server-side trust/reward policy for
   relationship, profile-verification, group-invitation, check-in, and other
   legacy generic-award call sites. Those client assertions are not adequate
   proof of scarce events; their rewards remain fail-closed and must not be
   restored as client-authored writes. Backfill the resulting trust projection
   before using eligibility fields for real credit or governance decisions.
7. Enable protected promotion branches, required reviews, secret scanning, and
   code scanning in the repository host.
8. Keep `ENABLE_FLIGHT_BOOKING=false`, `ALLOW_TRAVEL_MOCKS=false`, and paid
   event creation disabled until live fulfillment, refund, support, and
   PCI-reviewed payment flows pass staging and independent review.
9. Replace the capped push TGE with an independently audited claim-based Merkle
   distribution before an eligible population can exceed 100 recipients. Any
   `submission_uncertain` event must be reconciled with chain state before an
   operator clears its lock.
10. Keep `ENABLE_LEGACY_FULL_RECONCILIATION=false` in production. Replace the
    legacy whole-dataset treasury rebuild with an idempotent resumable repair
    job (or controlled data pipeline) before production-scale reconciliation
    is required; normal online operations already maintain materialized totals.

Follow `docs/runbooks/security-hardening-deploy.md` for the required order and
rollback constraints.
