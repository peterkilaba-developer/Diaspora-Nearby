# Cloud Functions Safety Pattern

After the 2026-06-02 silent-skip incident (the Philippines user got DSP but
no $DIASPORA because `initializeUserPoints` was missing a `secrets:` binding
and the conditional `if (BACKEND_SIGNER_KEY && ...)` silently bypassed the
on-chain block), the on-chain side effects in this codebase follow three
rules.

## Rule 1 — Fail-loud config

**Never** read on-chain config via `process.env.X || null` at module level.
Always assert it inside the handler:

```javascript
const { assertOnChainConfig } = require('./on_chain_config');

exports.myFunction = functions
  .runWith({ secrets: ['BACKEND_SIGNER_PRIVATE_KEY'] }) // ← required if signer needed
  .https.onCall(async (data, context) => {
    const { backendSignerKey, tokenAddress, tgeControllerAddress } =
      assertOnChainConfig('myFunction', [
        'backendSignerKey',
        'tokenAddress',
        'tgeControllerAddress',
      ]);
    // ... use the named locals; no conditional gate ...
  });
```

If a secret/env is missing, the function throws a clear named error.
**No conditional `if (key && addr) { ... }` gates** — those silently skip.

Read-only functions that only need public addresses (`tokenAddress`,
`rpcUrl`, `walletFactoryAddress`) don't need the `secrets:` binding —
public addresses live in `functions/.env` and are bundled with the deploy.

## Rule 2 — Observable failure state

When an on-chain side effect can't complete, **write the pending state to
Firestore** rather than logging and returning success. This makes the
failure recoverable and visible.

Convention: the entity that should have received the side effect gets
three fields:

| Field | Type | Meaning |
|---|---|---|
| `<thing>Pending` | bool | `true` while the on-chain step is unfinished |
| `<thing>Error` | string | machine-readable reason (one of a small set) |
| `<thing>ErrorAt` | timestamp | when the failure was recorded |

Examples currently in use:

- `users/<uid>.tokenWelcomeBonusPending` + `tokenWelcomeBonusError` (welcome bonus didn't land)
- `users/<uid>.walletDeploymentPending` + `walletDeploymentError` (smart wallet didn't deploy)
- `communities/<cid>.walletDeploymentPending` + `walletDeploymentError`
- `tge_events/<id>.status === "tx_complete_dsp_pending"` (TGE succeeded on-chain but DSP wasn't deducted)

Set the field via `batch.set(..., { merge: true })` so concurrent writes
don't clobber other state.

## Rule 3 — Healing function per pending field

For each `<thing>Pending` flag, there's an admin-only callable that scans
for it and retries. They're idempotent — safe to run repeatedly, double-pay
prevented by on-chain dedupe (V2 contract's `welcomeBonusReceived[user]`)
or by the factory's `getWallet(salt)` check.

| Pending flag | Healing function |
|---|---|
| `users/<uid>.tokenWelcomeBonusPending` | `retryPendingWelcomeBonuses` |
| `users/<uid>.walletDeploymentPending` | `retryPendingWalletDeployments({ scope: 'users' })` |
| `communities/<cid>.walletDeploymentPending` | `retryPendingWalletDeployments({ scope: 'communities' })` |
| `tge_events/<id>.status === "tx_complete_dsp_pending"` | `retryPendingTGEDeductions` |

All require `admin: true` custom claim on the caller. Standard invocation
from a privileged client:

```javascript
const fn = firebase.functions().httpsCallable('retryPendingWelcomeBonuses');
const dryRun = await fn({ dryRun: true, limit: 50 });
console.log(dryRun.data); // see what would be retried
const result = await fn({ limit: 50 });
```

You can also wire any of these to a `pubsub.schedule(...)` trigger if you
want background healing — for now they're manual, which is fine while user
count is small enough to inspect each pending case by hand.

## What this pattern doesn't cover

- **Read-only RPC failures** (e.g., Basescan API down). Those return errors
  to the caller; the client retries.
- **On-chain transaction reverts** from contract logic (e.g., user already
  received welcome bonus per the V2 dedupe). Those bubble up as exceptions
  and land in the same pending state — the healing function then sees them
  and skips with `status: "already_sent"`.
- **DSP-points-only operations** (`awardPoints`, `deductPoints`, etc.). Those
  don't touch the chain. Their failure mode is "the API call throws" which
  the client surfaces directly.

## When you add a new on-chain side effect

1. Declare the secret: `.runWith({ secrets: ['BACKEND_SIGNER_PRIVATE_KEY'] })`
2. Call `assertOnChainConfig(scope, [...])` at the top of the handler
3. Wrap the side effect in try/catch — on catch, write a `<thing>Pending`
   field to the affected entity's doc
4. Add a healing branch to the relevant `retryPending<Thing>` function,
   OR create a new healing function next to it
5. Update `functions/SAFETY.md` with the new field name + healing function
6. Add a smoke test that simulates the failure (e.g., RPC unreachable) and
   verifies the pending state lands in Firestore
