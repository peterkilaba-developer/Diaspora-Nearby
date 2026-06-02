# Hand-off: the 3 things only you can do

Everything in `blockchain/IMPROVEMENTS.md` is done except three items that need
you at a keyboard, signing transactions, or logged into someone else's account.
Each one is a single focused session of ~10–30 minutes. Do them in this order.

---

## 1) Move admin to a Gnosis Safe (highest priority)

### Why
Your deployer EOA (`0xeef49…F4dE6`) still holds `DEFAULT_ADMIN_ROLE` and
`UPGRADER_ROLE` on the live token and TGE controller, plus admin on the wallet
factory. One key compromise = total project loss. Moving these to a multi-sig
Safe is the single biggest risk reduction left.

### Steps

**1.1 Create the Safe** (10 min, in a browser):

1. Go to https://app.safe.global and connect your deployer wallet.
2. Click **Create new Safe** → **Base** network.
3. Name it `Diaspora Nearby Admin Safe`.
4. **Add 3 signers**. Recommended: your deployer key + two other keys you (or
   trusted co-founders) control on **different devices**. Hardware wallets
   (Ledger / Trezor) are strongly preferred for at least 2 of the 3.
5. **Threshold: 2 of 3.** This means any 2 signers can execute, so losing 1
   key is recoverable.
6. Pay the deployment gas (~$0.50 on Base).
7. Once deployed, copy the Safe address — you'll need it in 1.2.

**1.2 Transfer admin roles to the Safe** (1 min, from your terminal):

```bash
cd blockchain
SAFE_ADDRESS=0xYourSafeAddressHere \
  npx hardhat run scripts/admin/migrate-to-safe.js --network base-mainnet
```

This grants the Safe `DEFAULT_ADMIN_ROLE` + `UPGRADER_ROLE` on the token,
TGE controller, and wallet factory. The deployer's roles aren't removed yet
— step 1.3 does that.

**1.3 Renounce deployer's admin roles** (5 min, from the Safe UI):

Go to https://app.safe.global → your Safe → **Apps** → **Transaction Builder**.
Build a single multi-call batch with these 5 transactions:

| To | Function | Argument |
|---|---|---|
| `0x55d7e7d006938A15082752225ED44Fd130B87735` (Token) | `renounceRole(bytes32,address)` | `(DEFAULT_ADMIN_ROLE, 0xeef49F2a10f0EF143Cd8c710e013285F137F4dE6)` |
| `0x55d7e7d006938A15082752225ED44Fd130B87735` | `renounceRole(bytes32,address)` | `(UPGRADER_ROLE, 0xeef49F2a10f0EF143Cd8c710e013285F137F4dE6)` |
| `0xb6C049D47A2FaE5413c331760C22E715D0bF4d45` (TGE) | `renounceRole(bytes32,address)` | `(DEFAULT_ADMIN_ROLE, 0xeef49F2a10f0EF143Cd8c710e013285F137F4dE6)` |
| `0xb6C049D47A2FaE5413c331760C22E715D0bF4d45` | `renounceRole(bytes32,address)` | `(UPGRADER_ROLE, 0xeef49F2a10f0EF143Cd8c710e013285F137F4dE6)` |
| `0x9cF797cf332595c00410fc4ee9FdEe5C59501945` (Factory) | `renounceRole(bytes32,address)` | `(DEFAULT_ADMIN_ROLE, 0xeef49F2a10f0EF143Cd8c710e013285F137F4dE6)` |

Role hashes:
- `DEFAULT_ADMIN_ROLE` = `0x0000000000000000000000000000000000000000000000000000000000000000`
- `UPGRADER_ROLE` = keccak256("UPGRADER_ROLE") = `0x189ab7a9244df0848122154315af71fe140f3db0fe014031783b0946b8c9d2e3`

Submit the batch from the Safe. 2 of 3 signers must approve.

**1.4 Verify** (1 min):

```bash
cd blockchain
node -e "
const {ethers}=require('ethers');
const p=new ethers.JsonRpcProvider('https://mainnet.base.org');
const t=new ethers.Contract('0x55d7e7d006938A15082752225ED44Fd130B87735',
  ['function hasRole(bytes32,address) view returns (bool)',
   'function UPGRADER_ROLE() view returns (bytes32)',
   'function DEFAULT_ADMIN_ROLE() view returns (bytes32)'], p);
(async()=>{
  const u=await t.UPGRADER_ROLE();
  const a=await t.DEFAULT_ADMIN_ROLE();
  const d='0xeef49F2a10f0EF143Cd8c710e013285F137F4dE6';
  console.log('Deployer DEFAULT_ADMIN:', await t.hasRole(a,d), '(want false)');
  console.log('Deployer UPGRADER:',      await t.hasRole(u,d), '(want false)');
})()"
```

Both must print `false`.

---

## 2) Move backend signer key to Firebase Secret Manager

### Why
Today `BACKEND_SIGNER_PRIVATE_KEY`, `STRIPE_SECRET_KEY`, `AMADEUS_API_KEY`, and
`AMADEUS_API_SECRET` all sit in plaintext in `functions/.env.production`.
That file is now gitignored (good) but still lives on whichever machine deploys
to Firebase. Secret Manager keeps the key encrypted at rest and rotates it
into `process.env` only when the function runs.

### Steps

**2.1 Set secrets in Firebase** (5 min, interactive prompts):

```bash
cd functions
firebase functions:secrets:set BACKEND_SIGNER_PRIVATE_KEY
# paste 2bb4728d55bb2de1c9cf9b70172aa6cad3ab250f37c8ceaba0d16a4f02ee6196 when prompted

firebase functions:secrets:set STRIPE_SECRET_KEY
# paste your real Stripe secret key (not in any file — get from Stripe dashboard)

firebase functions:secrets:set AMADEUS_API_KEY
# paste 9bEWVotcoglPEtIGQGdCqANdvednTrdw

firebase functions:secrets:set AMADEUS_API_SECRET
# paste 21Y28mDyckeJfxQB
```

Verify:
```bash
firebase functions:secrets:access BACKEND_SIGNER_PRIVATE_KEY
# should print the value
```

**2.2 Apply the code diff** (5 min, with this repo open):

For each function in `functions/lib/{dsp,wallet,transfer,travel,payments}.js`
that reads one of those env vars, add the secret binding to the function
declaration. Two patterns depending on the trigger type:

**Pattern A — `.https.onCall(...)` becomes:**
```javascript
// BEFORE
exports.awardPoints = functions.https.onCall(async (data, context) => { ... });

// AFTER
exports.awardPoints = functions
  .runWith({ secrets: ["BACKEND_SIGNER_PRIVATE_KEY"] })
  .https.onCall(async (data, context) => { ... });
```

**Pattern B — already has `.runWith({...})`, just add `secrets`:**
```javascript
// BEFORE
exports.executeTGE = functions
  .runWith({ timeoutSeconds: 300, memory: "512MB" })
  .https.onCall(...);

// AFTER
exports.executeTGE = functions
  .runWith({
    timeoutSeconds: 300,
    memory: "512MB",
    secrets: ["BACKEND_SIGNER_PRIVATE_KEY", "TOKEN_ADDRESS", "TGE_CONTROLLER_ADDRESS"]
  })
  .https.onCall(...);
```

**Map of which secrets each module needs:**

| File | Secrets to add |
|---|---|
| `functions/lib/dsp.js` | `BACKEND_SIGNER_PRIVATE_KEY` (all exports that touch on-chain) |
| `functions/lib/wallet.js` | `BACKEND_SIGNER_PRIVATE_KEY` |
| `functions/lib/transfer.js` | `BACKEND_SIGNER_PRIVATE_KEY` |
| `functions/lib/travel.js` | `AMADEUS_API_KEY`, `AMADEUS_API_SECRET` |
| `functions/lib/payments.js` | `STRIPE_SECRET_KEY` |

`TOKEN_ADDRESS`, `WALLET_FACTORY_ADDRESS`, `TGE_CONTROLLER_ADDRESS`, `RPC_URL`
do NOT need to be secrets — they're public information. Keep them in
`functions/.env` (the dev one, not `.env.production`).

**2.3 Deploy** (5 min):

```bash
firebase deploy --only functions
```

The deploy will fail loudly if any function references a secret that isn't
set yet — that's intentional, you'll know immediately what to fix.

**2.4 Remove the production env file** (1 min):

```bash
rm functions/.env.production
```

The file is already gitignored, so this is just deleting the local copy. The
secrets now live exclusively in Google Secret Manager.

---

## 3) Verify implementation contracts on Basescan

### Why
The proxy contracts (`0x55d7e7d0…`, `0xb6C049…`) are auto-detected as
"Source Code (Proxy)" but the implementation contracts they delegate to are
unverified. Users opening the live token's Contract tab can't read the actual
code. Verification is one-time and free.

### Steps

**3.1 Get a Basescan API key** (3 min):

1. Go to https://basescan.org/myapikey (sign in with your peterkilaba@diasporanearby.com account).
2. Click **+ Add** → give it a name like `diaspora-deploy`.
3. Copy the key.

**3.2 Add it to `blockchain/.env`**:

```bash
# Edit blockchain/.env, replace
BASESCAN_API_KEY=your_basescan_api_key_here
# with your real key
BASESCAN_API_KEY=ABC123…
```

**3.3 Run the verifier**:

```bash
cd blockchain
npx hardhat run scripts/admin/verify-impls.js --network base-mainnet
```

It'll verify both implementations (DiasporaToken impl `0x0578bBdc…` and
TGEController impl). Skips anything already verified.

**3.4 Confirm**:

Open https://basescan.org/address/0x0578bBdc97087365bA4D974bb82bB98AddAac0EA#code
— you should see the source of `DiasporaToken.sol` rendered, plus a green
checkmark next to "Contract Source Code Verified".

---

## When you're done with all three

Update the checked-off list in `blockchain/IMPROVEMENTS.md` and the audit chapter
of this project is closed. The remaining items in that doc are all "nice to
have, schedule when ready" — TGEControllerV2 deploy (the contract code is
already written and tested), wallet factory v2 (only matters past a few hundred
users), end-to-end flow docs, etc.

If anything goes sideways during these three steps, the failure modes are all
loud and reversible:

- Safe migration: `migrate-to-safe.js` is idempotent; re-run anytime.
- Secrets: a missed secret = deploy fails with an explicit error naming the
  missing secret.
- Basescan verify: fails on bad source/constructor args; the contract just
  stays unverified (no on-chain effect).
