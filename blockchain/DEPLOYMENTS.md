# $DIASPORA Token — Canonical Deployment

## Live token (use this everywhere)

**`0x55d7e7d006938A15082752225ED44Fd130B87735`** — Base Mainnet

- Network: Base (chainId 8453)
- Standard: ERC-20 (upgradeable proxy)
- Implementation: `0x0578bBdc...ADDAaC0EA`
- Deployer / contract creator: `0xeef49F2a10f0EF143Cd8c710e013285F137F4dE6`
- Deployer private key: `blockchain/.env` → `PRIVATE_KEY`
- Backend wiring: `functions/.env.production` → `TOKEN_ADDRESS`
- Frontend wiring: `lib/features/dsp/screens/diaspora_crypto_screen.dart`
- Basescan: https://basescan.org/token/0x55d7e7d006938A15082752225ED44Fd130B87735

This is the only contract any new code, docs, marketing material, or UI should reference.

## Deprecated contracts — DO NOT USE

These exist on-chain (immutably) but are NOT the live token. Basescan has been asked
to label them "Deprecated" so users searching for $DIASPORA don't land on the wrong page.

| Address | Why it exists | Deployer |
|---|---|---|
| `0x453f81D3a4Bb142AE34C53798BE35e7600D1b25c` | Original launch deployment. Basescan token-info (logo, website) was registered against this contract, but the deployer key (`0xc479368a5c888f91db6ebc85a3f51c8dbc404c73`) was lost, forcing a re-deploy. | `0xc479...4c73` (lost) |
| `0x22e37662801ba7bE67Df7A593a5ad616C1DBb30B` | Test / interim deployment from the new deployer. Superseded. | `0xeef49...4dE6` |
| `0xa3F092357655C0Bc5fb2Ba4B61f25c5422F59FED` | Orphan TGE Controller for `0x453f81...`. Has **989,880 DIASPORA** pre-minted and **permanently locked**. | `0xc479...4c73` (lost) |

If anyone asks about these on Basescan, point them to `0x55d7e7d0...87735`.

### Why the locked supply can't be burned

The orphan TGE Controller `0xa3F092...` holds 989,880 DIASPORA of the deprecated token
`0x453f81...`. We checked on 2026-06-01: the current deployer `0xeef49...` holds **no
roles** on that controller (`TGE_ORACLE_ROLE: false`, `DEFAULT_ADMIN_ROLE: false`). All
admin/oracle rights were granted to the original deployer `0xc479...4c73`, whose private
key is lost. Therefore:

- We cannot call `distributeWelcomeBonus([BURN_ADDRESS], [amount])` to burn the locked supply
- We cannot upgrade the controller to add a burn path (`UPGRADER_ROLE` also lost)
- We cannot grant ourselves new roles (`DEFAULT_ADMIN_ROLE` lost)

The ~10,120 DIASPORA distributed to ~26 test holders on `0x453f81...` is similarly
unrecoverable from their wallets without their cooperation. **All of this is acceptable
because they were test users, not real customers, and the deprecated chain has no
real-world value.** Do not waste cycles trying to "fix" this — just keep pointing all
new users at `0x55d7e7d0...`.

## Deployer history

- **Old deployer (lost):** `0xc479368a5c888f91db6ebc85a3f51c8dbc404c73`
  - Deployed the original `0x453f81...` contract
  - Private key lost — cannot sign any future Basescan token-info updates for `0x453f81...`
- **Current deployer:** `0xeef49F2a10f0EF143Cd8c710e013285F137F4dE6`
  - Deployed the live `0x55d7e7d0...` contract (and the deprecated `0x22e37662...`)
  - Private key in `blockchain/.env` (gitignored)
  - Funded via Coinbase

## How Basescan token info / name tags work (operational notes)

- **Token logo / website / description** that appears on a token's page (and on every
  transaction involving the token) is registered per **contract address**, not per
  deployer. Changing deployers does NOT migrate this metadata to a new contract.
- **Updating** a token's metadata requires a signed message from the **on-chain
  contract creator** of that specific contract. There is no override.
- **Address name tags** (e.g. "Diaspora Nearby: Deployer") are a separate Basescan
  feature, submitted via the `/contactus?id=5` form and reviewed manually. No
  on-chain signature required.
- To verify ownership of a contract under your Basescan account (which gates the
  Token Update form), use https://basescan.org/verifyaddress and sign the displayed
  challenge with the contract creator's key. We did this for `0x55d7e7d0...` on
  2026-06-01 — the signing flow is in `scripts/sign-message.js`.

## What's currently in flight at Basescan

Submitted 2026-06-01 (typically 3-5 business days to review):

1. Token Info Update for `0x55d7e7d0...87735` (logo + name + website + description)
2. Name tag for `0xeef49...4dE6` → "Diaspora Nearby: Deployer"
3. Name tag for `0xc479...4c73` → "Diaspora Nearby: Old Deployer (Deprecated)"
4. Name tag for `0x453f81D3...1b25c` → "Diaspora: Old DIASPORA Token (Deprecated)"
5. Name tag for `0x22e37662...Bb30B` → "Diaspora: Test DIASPORA Token (Deprecated)"

Watch `peterkilaba@diasporanearby.com` for approval/follow-up emails.
