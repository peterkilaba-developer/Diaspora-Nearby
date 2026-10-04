# Security Hardening Deployment Runbook

This release changes authorization boundaries and the user-data schema. Do not
deploy it as an ordinary client-only release. Use a maintenance window or a
forced minimum client version so old clients cannot write the legacy schema
after the migration.

## Preconditions

- Create distinct Firebase/GCP projects and service identities for dev,
  staging, and production. Confirm dev/staging builds reject the production
  project ID.
- Export Firestore and Auth, record the Storage bucket generation/versioning
  state, and test restore procedures.
- Set and independently verify `BACKEND_SIGNER_PRIVATE_KEY`, `OTP_PEPPER`,
  `WALLET_ID_PEPPER`, `WHATSAPP_ACCESS_TOKEN`,
  `WHATSAPP_PHONE_NUMBER_ID`, `GOOGLE_PLACES_API_KEY`, `STRIPE_SECRET_KEY`,
  `STRIPE_WEBHOOK_SECRET`, `AMADEUS_API_KEY`, and `AMADEUS_API_SECRET` in
  Secret Manager. Use different values per environment.
- Restrict Firebase, Maps, Places, Stripe, and RPC credentials by application,
  origin, API, service identity, and quota. Rotate the formerly embedded Maps
  key after the restricted replacement is deployed. Revoke/rotate the legacy
  Firebase CLI OAuth client credential removed from admin scripts and use
  short-lived Application Default Credentials for operator access.
- Ensure the production project never has `ENABLE_HARD_RESET=true`. Production
  code also rejects the known production project ID as defense in depth.
- Set `ALLOW_TRAVEL_MOCKS=false` and `ENABLE_FLIGHT_BOOKING=false` in every
  production revision. Do not enable flight booking until the live Amadeus,
  payment, refund, privacy, support, and PCI controls have separate approval.
- Set `ENABLE_LEGACY_FULL_RECONCILIATION=false`. The legacy callable downloads
  the full user and balance sets and is intentionally blocked in production;
  use only bounded repair jobs or an approved data pipeline.

## Staging rehearsal

1. Deploy Firestore indexes/TTL configuration and Functions. Confirm TTL is
   enabled for OTP, rate-limit, QR, event check-in, and hosting check-in expiry
   fields.
2. Run `node functions/scripts/migrate-private-user-data.js` with staging
   credentials. Review the dry-run counts and a sample of public/private docs.
3. Run again with `--apply`. The migration marker suppresses mass proximity
   notifications when private documents are created.
4. Dry-run `node functions/scripts/migrate-relationship-security.js`, retain
   its aggregate output, and investigate any nonzero conflict/truncation
   counters. After cleanup, rerun with `--apply` and then dry-run once more to
   prove convergence. This materializes existing blocks, direct-chat pair
   indexes, deterministic pending requests, and unique family slots.
5. Dry-run `node functions/scripts/migrate-canonical-entities.js`. Resolve every
   invalid owner/chat ID, participant overflow, chamber organization mismatch,
   invalid booking, and booking-slot collision. Rerun with `--apply`, then
   dry-run once more to prove convergence. This creates only missing canonical
   entity chats, backfills parent links, and reserves daily slots for confirmed
   legacy peer bookings; it never chooses a winner for overlapping bookings.
6. Verify public `users` documents contain no phone, date of birth, exact
   geometry, FCM token, blocked-user list, work/past location, or tax ID.
   Validate or quarantine legacy client-authored hosting sessions, attendance,
   reports, listing interactions/counters, trust stakes, and flight bookings.
7. Deploy Firestore and Storage rules, then the new clients. Confirm old clients
   are rejected or blocked by minimum-version policy.
8. Enable App Check enforcement for callable Functions, Firestore, Storage, and
   Auth after debug/test tokens are removed.
9. Exercise sign-in/OTP, profile save, nearby search, direct/group/community
   chat and media, secure QR handshakes, hosted event and mutual-consent hosting
   check-ins, two-party hosting checkout, idempotent reports/listing counters,
   transfers, checkout lock/webhook replay, account deletion, and backup
   restore. Exercise referral creation/redemption twice (the second call must
   be idempotent), governance duplicate-vote rejection, verified-solution
   duplicate rejection, landing-form failure behavior, and authenticated
   Places quotas. Confirm paid events, flight ordering, marketplace-contact GDP,
   unverifiable geofence rewards, and client-authored trust rewards remain
   disabled. Observe logs and quotas for at least one staging soak period.

## Production order

1. Announce and enter the maintenance window; freeze background admin scripts.
2. Capture backups and record the exact git commit and deployed revisions.
3. Deploy indexes and Functions.
4. Dry-run, sample, then apply the private-user-data migration.
5. Dry-run, reconcile, apply, and re-audit the relationship-security migration.
6. Dry-run, reconcile, apply, and re-audit the canonical-entity migration.
7. Run the public-data verification query and retain only aggregate evidence.
8. Deploy Firestore/Storage rules and Hosting configuration.
9. Publish/enable the new client and minimum-version gate.
10. Enable App Check enforcement and production quotas.
11. Send a signed Stripe test event and replay the same event ID; verify one
   membership update. Perform one low-value end-to-end transfer and reconcile
   Firestore with the on-chain receipt.
12. Monitor errors, latency, denials, reads, webhook retries, and pending
    on-chain states throughout the rollback window.

Run maintenance callables page by page using their returned `nextCursor` until
`hasMore` is false. Preserve the cursor and aggregate output in the change
record; never raise page limits to recreate a whole-collection scan.

## Contract migration gate

`DiasporaWalletFactory` is immutable. Source changes do not upgrade the already
deployed factory or existing clones. Before relying on signer rotation, deploy
and independently audit the new factory, rotate/migrate existing wallet owners
in bounded batches, reconcile every wallet, and move privileged roles to the
approved multisig/HSM. Upgrade the TGE proxy with `initializeV2` in the same
governance transaction and verify storage layout before execution.

The current backend push TGE is deliberately limited to 100 recipients. Before
the eligible population can exceed that threshold, deploy and independently
audit a claim-based Merkle distributor. Confirm the four-argument V2 ABI and
Merkle root on a fork/staging chain. Reconcile every `submission_uncertain`
record against the chain before clearing its lock; never blindly resubmit.

## Rollback

- Do not roll rules back to the permissive version. Roll Functions/client code
  forward with a compatibility fix while keeping the private schema and secure
  rules.
- If migration stops, leave maintenance mode enabled, rerun the idempotent
  script, and compare aggregate counts before proceeding.
- If a payment or on-chain side effect is uncertain, stop retries, inspect the
  idempotency/pending record and chain receipt, then use the documented healing
  callable. Never manually credit both ledgers.
