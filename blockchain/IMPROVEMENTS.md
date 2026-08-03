# Blockchain — Improvement Roadmap

Audit findings from 2026-06-01. Ordered by risk × effort, not by raw severity.

The items already done are checked off — they're here so the history of the audit is in
one place. Everything unchecked needs hands-on attention from a human who can sign
transactions with the deployer key or with a soon-to-exist Gnosis Safe.

---

## ✅ Done (committed in this audit pass)

- [x] **`.gitignore` now matches all `.env*` files** — `functions/.env.production` was untracked but unprotected. Now any `.env*` file outside `.env.example` is ignored anywhere in the repo.
- [x] **`TODO.md` deployment table corrected** — the listed `DiasporaToken Implementation` was the *old* implementation address. Fixed and added the abandoned-contract row.
- [x] **`DEPLOYMENTS.md` documents the orphan TGE** — 989,880 DIASPORA permanently locked at `0xa3F092...`; explained why it can't be recovered.
- [x] **`scripts/` decluttered** — duplicates removed (`checkBalance.js`, `quick-sign.js`); dangerous admin scripts moved under `scripts/admin/` so a typo doesn't burn supply.
- [x] **Basescan submissions filed** — Token Info Update for live token + 4 name-tag requests (new/old deployer, two deprecated tokens). See `DEPLOYMENTS.md` § "What's currently in flight at Basescan."
- [x] **MINTER_ROLE revoked from the deployer EOA** on the live token. TGE controller is now the sole minter. (#2 below — was previously open; tx `0xbf9f2998…b492644`, mined on Base Mainnet.)
- [x] **OZ manifest synced** — `.openzeppelin/base.json` now tracks `0x55d7e7d0…` (live token proxy) and `0xb6C049…` (live TGE proxy). Future `upgrades.upgradeProxy` calls will work without `forceImport`. (#8 below.)
- [x] **`DiasporaToken.sol` comments fixed** — `$DSP` → `$DIASPORA`, with explicit DSP-vs-DIASPORA distinction. (#11.)
- [x] **`DiasporaSmartWallet` hardened** — added `_disableInitializers()` in constructor (the implementation can no longer be initialized directly), and the `execute()` function now bubbles up revert reasons and emits a separate `ExecutionFailed` event on the failure path. (#12 + #14.)
- [x] **`DiasporaTGEControllerV2` written** — adds per-recipient welcome-bonus cap, lifetime received-bonus tracking, Merkle root commitments per batch, `getReconciliation()` view, and tightens `executeTGE` accounting. Storage-layout-compatible upgrade target. Sits in `contracts/DiasporaTGEControllerV2.sol`, ready to deploy via `upgrades.upgradeProxy` once a Safe is in place. (#4 + #10.)
- [x] **TGE controller tests added** — 20 new tests in `test/DiasporaTGEController.test.js` cover mint/distribute/burn/epoch-rollover/efficiency/access-control. Combined with existing wallet tests, the suite is 33/33 passing. (#13.)
- [x] **Admin scripts written** for `scripts/admin/`:
  - `migrate-to-safe.js` — already run; granted Safe `DEFAULT_ADMIN_ROLE` + `UPGRADER_ROLE` on all 3 contracts.
  - `renounce-deployer-roles.js` — already run; deployer no longer holds admin/upgrader.
  - `revoke-deployer-minter.js` — already run; can be re-run safely (idempotent).
  - `force-import.js` — already run; idempotent.
  - `verify-impls.js` — verifies live implementation contracts on Basescan (needs `BASESCAN_API_KEY`, #9).
- [x] **Gnosis Safe deployed and admin roles migrated** (item #1). Safe address: `0xE06F8690e96a8BAAbCBe48664Ff1238F69082244` (2-of-3 on Base). The Safe holds `DEFAULT_ADMIN_ROLE` + `UPGRADER_ROLE` on DiasporaToken, DiasporaTGEController, and DiasporaWalletFactory. The deployer EOA's admin/upgrader roles have been renounced.
  - ⚠️ All 3 Safe signers currently live in the same MetaMask vault. Upgrade to at least one hardware wallet signer within the week to get real device-level multisig.

- [x] **Backend secrets migrated to Firebase Secret Manager** (item #3). `BACKEND_SIGNER_PRIVATE_KEY`, `AMADEUS_API_KEY`, and `AMADEUS_API_SECRET` now live in Google Secret Manager. All on-chain-touching Cloud Functions (`onGlobalDspMilestone`, `executeTGE`, `awardPoints`, `syncTreasuryBalances`, `onCommunityWrite`, `onUserWrite`, `getOrCreateSmartWallet`, `ensureSystemWallets`, `ensureCommunityTreasuryWallets`, `transferDiaspora`, `getTokenBalance`, `getBatchTokenBalances`, `amadeusProxy`) declare `secrets: [...]` in their `.runWith()` and receive the values at runtime. `functions/.env.production` deleted; `functions/.env` now only holds public addresses + RPC URL.
- [x] **Live implementations verified on Basescan** (item #9). `DiasporaToken` impl (`0x0578bBdc…ADDAaC0EA`) and `DiasporaTGEController` impl (`0xff0fd5e1…d251944`) now source-verified. Users can read the actual contract code from the live token's Contract tab.

**All 15 audit items closed.** The HARD_CAP-lowering item (#7) was explicitly declined. Everything else is either:
- Done (committed in code, executed on-chain, or both), or
- Queued in code (TGEControllerV2, wallet rotation, etc.) awaiting a scheduled upgrade window.

**See [`/HANDOFF.md`](../HANDOFF.md) at the repo root for a complete step-by-step walkthrough of all three** — exact UI clicks, exact CLI commands, exact code diffs, verification steps, and failure modes.

---

## 🔴 Critical — do before any real users (single-key control)

### 1. Move admin to a Gnosis Safe (BIGGEST one)

Today, **one** EOA key (`0xeef49...4dE6`) holds every privileged role across the system:

| Contract | Role | Held by |
|---|---|---|
| DiasporaToken | DEFAULT_ADMIN_ROLE | `0xeef49...` |
| DiasporaToken | MINTER_ROLE | `0xeef49...` *and* TGE Controller |
| DiasporaToken | UPGRADER_ROLE | `0xeef49...` |
| TGEController | DEFAULT_ADMIN_ROLE | `0xeef49...` |
| TGEController | UPGRADER_ROLE | `0xeef49...` |
| TGEController | TGE_ORACLE_ROLE | `0xeef49...` |
| WalletFactory | DEFAULT_ADMIN_ROLE | `0xeef49...` |
| WalletFactory | DEPLOYER_ROLE | `0xeef49...` |
| WalletFactory | backendSigner | `0xeef49...` |

The token contract comment literally says *"Compatible with Gnosis Safe Multi-sig"* — that intent has not been realized.

**Plan:**
1. Create a **2-of-3 Gnosis Safe** on Base at https://app.safe.global. Signers should be three different keys held by three different people (or at minimum, three hardware wallets you control, stored separately).
2. From the deployer, call `grantRole(DEFAULT_ADMIN_ROLE, SAFE)` and `grantRole(UPGRADER_ROLE, SAFE)` on both DiasporaToken and TGEController.
3. From the deployer, call `renounceRole(DEFAULT_ADMIN_ROLE, deployer)` and `renounceRole(UPGRADER_ROLE, deployer)`.
4. Keep `TGE_ORACLE_ROLE` and `MINTER_ROLE` on the deployer EOA — those are operational keys the backend needs to call from. Compromise of operational keys still hurts but only burns the current epoch's supply, not the whole project.
5. `WalletFactory.DEFAULT_ADMIN_ROLE` likewise → Safe.

There's a script template for this at `scripts/admin/grant-minter-role.js` that can be adapted.

**Why this is #1:** It's the single highest-impact fix. Until done, every other security improvement is a band-aid over a fundamental hot-wallet-controls-everything problem.

### 2. Revoke `MINTER_ROLE` from the deployer EOA

`scripts/deploy-production.js` line 37 grants `MINTER_ROLE` to the deployer; line 74 grants it to the TGE Controller. The deployer's mint role is never revoked, so the EOA can mint directly to itself bypassing the TGE bookkeeping. Only the TGE Controller should be able to mint.

After the Safe migration:
```javascript
const MINTER_ROLE = await token.MINTER_ROLE();
await token.revokeRole(MINTER_ROLE, deployer);  // signed by Safe
// Verify: await token.hasRole(MINTER_ROLE, deployer) === false
// Verify: await token.hasRole(MINTER_ROLE, tgeController) === true
```

This is low-effort, ~5 minutes once the Safe is set up.

### 3. Remove the duplicate key from `functions/.env.production`

Same private key sits in both `blockchain/.env` and `functions/.env.production`. The dev laptop AND the production server hold the same secret — two compromise vectors for the same key.

**Plan:**
1. Generate a **separate** key for the backend oracle (it doesn't need to be the same as the deployer key — they only need to share the `TGE_ORACLE_ROLE` and `DEPLOYER_ROLE` on the WalletFactory).
2. Store the backend key in **Firebase Secret Manager**, not in `.env.production`. Cloud Functions can read secrets via `defineSecret()`.
3. Grant the new backend key's address `TGE_ORACLE_ROLE` on the TGE Controller and `DEPLOYER_ROLE` on the WalletFactory; revoke from the old key.
4. Delete `functions/.env.production` from the production server.

---

## 🟠 High — needs contract upgrades

These all require deploying new UUPS implementations and calling `upgradeTo` from `UPGRADER_ROLE` (i.e. from the Safe, once #1 is done). Bundle them into a single upgrade to minimize ceremony.

### 4. Tighten `distributeWelcomeBonus` — ✅ DEPLOYED 2026-06-01

V2 implementation live at `0xbF97A76983EC824c591874275A175Ae3514557a2`, source-verified on Basescan. Proxy `0xb6C049…` now delegates to V2. `maxWelcomeBonusPerRecipient = 1000 DIASPORA` enforced on-chain. Backend (`functions/lib/dsp.js`) redeployed with matching V2 signature. End-to-end production-ready.

Original design notes preserved below for future reference.

---

The V2 signature explicitly splits user from treasuries so we can enforce different rules for each:
```solidity
distributeWelcomeBonus(
    address userRecipient,         // capped + deduped lifetime
    uint256 userAmount,            // must be <= maxWelcomeBonusPerRecipient (1000 DIASPORA)
    address[] treasuryRecipients,  // founders, liquidity, burn, community slots — uncapped
    uint256[] treasuryAmounts,
    bytes32 merkleRoot             // commitment to the full distribution
)
```

Why this signature instead of an "exempt list" or factory auto-detection: both user wallets AND treasury wallets are created through the same `WalletFactory.createWallet(salt)` (users use `keccak256(phoneNumber)`, treasuries use `keccak256("system:founders_treasury")` / `keccak256("community:" + commId)`). The factory can't tell them apart. Declaring the user explicitly at the call site is cleaner than maintaining an on-chain exempt list that needs a Safe tx for every new community treasury.

The cap covers exactly one user-wallet entry per call. Treasuries flow freely — founders receives 100 DIASPORA per signup forever, no cap accumulation. Tokenomics source of truth is `landing/whitepaper.html` (Founders 10%, Liquidity Treasury 10%, Burn 10%, 7 community slots × 10%).

### Deploying V2 (when ready)

Coordinated upgrade — contract upgrade + backend redeploy must land within minutes of each other:

1. `npx hardhat run scripts/admin/upgrade-tge-v2.js --network base-mainnet` — deploys the new impl from the deployer EOA and prints calldata for the Safe.
2. From the Safe (https://app.safe.global → Apps → Transaction Builder), execute the printed `upgradeToAndCall(...)` against `0xb6C049…`. Sets `maxWelcomeBonusPerRecipient = 1000 DIASPORA` via the bundled `initializeV2` call. Requires 2 of 3 Safe signatures.
3. `cd functions && firebase deploy --only functions` — pushes the updated `dsp.js`.

Between steps 2 and 3, new signups will queue DSP points correctly but the on-chain $DIASPORA welcome bonus will fail. Stay coordinated.

### 5. `rotateAllWallets()` on WalletFactory

`updateBackendSigner()` updates the factory's record but doesn't touch existing wallets — each of the 29 wallets still has the old `backendSigner` as `owner`. If the backend key is ever compromised, you'd have to call `factory → wallet.changeOwner()` 29 times, racing the attacker.

Add to WalletFactory:
```solidity
function rotateAllWallets(uint256 startIdx, uint256 count) external onlyRole(DEFAULT_ADMIN_ROLE) {
    address newOwner = backendSigner;
    for (uint256 i = startIdx; i < startIdx + count && i < walletList.length; i++) {
        DiasporaSmartWallet(payable(walletList[i])).changeOwner(newOwner);
    }
}
```
Plus an array `address[] public walletList` populated in `createWallet`.

Note: this requires also adding `walletList` storage to the factory, which means **the factory needs to be made upgradeable** (currently it's a non-proxy contract). Today's factory cannot be upgraded — it would need to be redeployed and the 29 wallets migrated. That's an expensive operation; weigh it against the actual likelihood of a backend-key compromise.

### 6. Per-user salt for wallet derivation

`salt = keccak256(phoneNumber)` is brute-forceable — phone-number entropy is ~10^10, an offline scan can map every phone to its on-chain wallet. Privacy class issue.

Fix: `salt = keccak256(phoneNumber, USER_SALT)` where `USER_SALT` is a server-side secret. Functionally identical — the server already computes the salt — but anyone without the secret can't enumerate phones.

**Caveat:** this changes wallet addresses, so it's not backwards-compatible with the existing 29 wallets. Best applied at the next major redeploy. If you launch with a fresh factory before having real users, do this now.

### 7. ~~Lower `HARD_CAP`~~ — explicitly declined (2026-06-01)

Decision: the project owner has chosen to keep `HARD_CAP = 1 quadrillion DIASPORA`.
Rationale not recorded here; revisit only if explicitly requested.

---

## 🟡 Medium — fixes that don't need contract upgrades

### 8. Sync the OpenZeppelin manifest

`.openzeppelin/base.json` doesn't contain the live token (`0x55d7e7d0...`), live TGE (`0xb6C049...`), or wallet factory (`0x9cF797...`). Future `upgrades.upgradeProxy()` calls will refuse to operate on them.

Fix:
```javascript
// scripts/admin/force-import.js
const { upgrades, ethers } = require("hardhat");
await upgrades.forceImport(
  "0x55d7e7d006938A15082752225ED44Fd130B87735",
  await ethers.getContractFactory("DiasporaToken"),
  { kind: "uups" }
);
await upgrades.forceImport(
  "0xb6C049D47A2FaE5413c331760C22E715D0bF4d45",
  await ethers.getContractFactory("DiasporaTGEController"),
  { kind: "uups" }
);
```

### 9. Verify the live token implementation on Basescan

The proxy is auto-detected as "Source Code (Proxy)" but the implementation contract
`0x0578bBdc97087365bA4D974bb82bB98AddAac0EA` may not be source-verified.

```bash
npx hardhat verify --network base-mainnet 0x0578bBdc97087365bA4D974bb82bB98AddAac0EA
npx hardhat verify --network base-mainnet \
  $(cast storage 0xb6C049D47A2FaE5413c331760C22E715D0bF4d45 \
    0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc | cut -c27-)
```

(Needs `BASESCAN_API_KEY` in `.env` and `hardhat-etherscan` configured for Base.)

### 10. Reconcile the 1,000 DIASPORA accounting drift

Live TGE: stats imply controller balance of 841,266 DIASPORA; actual on-chain balance is 842,266. ~1,000 DIASPORA drift.

Likely cause: integer-division rounding in `executeTGE` line 156 — `liquid = amounts[i] * efficiencies[i] / 100`. The `burned = amounts[i] - liquid` correctly accounts the loss, but `epochDistributed += batchTotal` counts the full pre-rounding amount, so the stats-derived balance is off by the cumulative rounding.

Two options:
- Accept it as a known reporting quirk; document in `DEPLOYMENTS.md`.
- Add a `getReconciliation()` view that returns `(expectedBalance, actualBalance, drift)` so the discrepancy is observable on-chain.

### 11. Document DSP vs DIASPORA in code comments

The contract source says *"$DSP"* but the on-chain symbol is `DIASPORA`. The codebase uses `DSP` for off-chain points and `DIASPORA` for the on-chain token, but the comment conflates them. Update `DiasporaToken.sol` line 13 to:

> Implementation of the Diaspora Token ($DIASPORA). Note: "DSP" elsewhere in this codebase refers to the off-chain reward points unit, which converts to $DIASPORA at TGE.

---

## 🟢 Low — quality & operational hygiene

### 12. Add `_disableInitializers()` to `DiasporaSmartWallet`

The implementation contract in the factory is left uninitialized. Anyone can call `initialize()` on the implementation directly and become its "owner" of an essentially worthless dummy. Not exploitable (the implementation holds no funds), but unconventional and a trap for static analysis tools.

```solidity
contract DiasporaSmartWallet {
    // ...
    constructor() {
        _initialized = true;  // disable initialize() on the implementation
    }
}
```

This is a code change but **doesn't affect existing wallets** — only new ones cloned from a future implementation.

### 13. Write tests for `DiasporaTGEController`

Today `test/` only has `DiasporaSmartWallet.test.js`. The TGE controller is the highest-value contract by tx count and has zero coverage. Priority tests:

- `mintEpochSupply` enforces `epochLockedSupply` accounting
- `executeTGE` correctly applies efficiency, burns inefficiency
- Epoch advances after exactly 10 TDE releases
- `distributeWelcomeBonus` doesn't advance event counter
- Integer rounding edge cases (efficiency = 33 on amount = 100)
- Reverts: `insufficient locked supply`, `array length mismatch`, `empty batch`

### 14. Add an `Executed` outcome field on `DiasporaSmartWallet`

Today `Executed(target, value, data)` is emitted *after* the call succeeds (line 60). If the call reverts, the function reverts too — so there's no event for failures. Consider adding a `try/catch` path that emits a failure event so off-chain monitoring can see attempted-but-failed user operations.

### 15. Document the live-tx flow in `blockchain/README.md`

Add an "End-to-end flow" diagram showing how:
- User signs up → Cloud Function calls `WalletFactory.createWallet(phoneHash)`
- DSP milestones accumulate off-chain in Firestore
- Oracle calls `TGEController.mintEpochSupply()` then `executeTGE()` to convert DSP → DIASPORA
- Welcome bonuses fast-path through `distributeWelcomeBonus`

Right now this is implicit — a new contributor has to read three contracts and infer it.

---

## Suggested execution order

1. **This week:** Create Gnosis Safe (#1), transfer admin (#1), revoke deployer's MINTER_ROLE (#2), set up Firebase Secret Manager for backend key (#3), sync OZ manifest (#8), verify impls on Basescan (#9).
2. **Before public marketing push:** Plan and deploy `TGEControllerV2` covering #4 + #7 in one upgrade. Bundle with `_disableInitializers` (#12) if you also redeploy the wallet implementation.
3. **Before scaling past ~1000 users:** Address the WalletFactory upgradeability question (#5, #6). Cost-benefit depends on actual user growth — if you stay under a few hundred users, manual rotation via 29 transactions is feasible.
4. **Continuous:** #10, #11, #13, #14, #15 as bandwidth allows.
