# Diaspora Blockchain TODO

## Pre-Production Checklist

- [ ] **Deploy WalletFactory to Base Mainnet**  
  When done testing with test users, run:  
  ```bash
  npx hardhat run scripts/deploy-wallet-factory.js --network base-mainnet
  ```
  Then update `functions/.env` with the new `WALLET_FACTORY_ADDRESS`.

- [ ] **Verify contracts on Basescan**  
  ```bash
  npx hardhat verify --network base-mainnet 0x55d7e7d006938A15082752225ED44Fd130B87735
  npx hardhat verify --network base-mainnet 0xb6C049D47A2FaE5413c331760C22E715D0bF4d45
  ```

- [ ] **Upload $DIASPORA token logo to Basescan**  
  Go to basescan.org → Token → Update Token Info

- [ ] **Submit Basescan Public Name Tags for treasury addresses**  
  Go to [basescan.org/contactus](https://basescan.org/contactus) → "Update Name Tag"  
  Provide address, label, and proof of ownership (signed message) for each treasury:  
  - DiasporaToken Proxy → `Diaspora: $DIASPORA Token`  
  - TGEController Proxy → `Diaspora: TGE Controller`  
  - Founders Treasury → `Diaspora: Founders & Core Team Treasury`  
  - Investors Treasury → `Diaspora: Liquidity Treasury`  
  - Community treasuries → `Diaspora: {Community Name} Treasury`  
  - Deployer Wallet → `Diaspora: Deployer`

- [ ] **Redeploy Cloud Functions** after updating `.env` for mainnet

## Phase 2 — Post WalletFactory Mainnet Deploy

### Treasury Wallet Provisioning
- [ ] **Deploy WalletFactory to Base Mainnet** (prerequisite for all below)
- [ ] **Create community treasury wallets** — deterministic via WalletFactory using `community:{communityId}` salt
- [ ] **Create system treasury wallets** — founders, investors, global using WalletFactory
- [ ] **Store wallet addresses** in `governance/{id}.walletAddress` for TGE distribution

### DDI Loan System (Multisig)
- [ ] **DDI loan application form** — regular member submits loan request (amount, purpose, collateral)
  - Enforces 10% token collateral locking based on borrower balance (`collateralAmount = requestedAmount * 0.10`)
- [ ] **Council approval flow** — elected council members review & approve in-app
  - Stored in `governance/{communityId}/ddi_loans/{loanId}`
  - `requiredSignatures: 3` (3 of 5 council members)
  - Approvals tracked per council member
- [ ] **Auto-disburse on quorum** — Cloud Function fires when approval threshold met
  - Transfers $DIASPORA from community smart wallet to applicant wallet
  - Records TX hash for audit
- [ ] **Cascading treasury logic** — if local treasury insufficient, escalate:
  - City → State → Country → Continent (each level needs its own council approval)
- [ ] **Option A Repayment tracking** — Open-market DEX buyback deposited to Community Treasury (Host Town or Home Country) with schedule, payments received, and status updates

### TGE Security
- [ ] **Admin role for executeTGE** — restrict manual trigger to admin custom claim
- [ ] **Test token cleanup** — options: burn 1,800 test tokens or redeploy for clean slate

## Deployed Contracts

### Base Mainnet (Production) — Current
| Contract | Address |
|----------|---------|
| DiasporaToken ($DIASPORA) — proxy | `0x55d7e7d006938A15082752225ED44Fd130B87735` |
| DiasporaToken Implementation | `0x0578bBdc97087365bA4D974bb82bB98AddAac0EA` |
| TGEController — proxy | `0xb6C049D47A2FaE5413c331760C22E715D0bF4d45` |
| WalletFactory | `0x9cF797cf332595c00410fc4ee9FdEe5C59501945` |
| Deployer wallet | `0xeef49F2a10f0EF143Cd8c710e013285F137F4dE6` |

### ~~Base Mainnet (Deprecated / Abandoned)~~
| Contract | Address | Status |
|----------|---------|--------|
| ~~DiasporaToken (original launch, ~26 test holders)~~ | `0x453f81D3a4Bb142AE34C53798BE35e7600D1b25c` | ❌ Abandoned — admin key lost |
| ~~DiasporaToken (interim test, 1,890 tokens)~~ | `0x22e37662801ba7bE67Df7A593a5ad616C1DBb30B` | ❌ Deprecated |
| ~~TGEController for `0x453f81...`~~ | `0xa3F092357655C0Bc5fb2Ba4B61f25c5422F59FED` | ❌ Orphaned — 989,880 DIASPORA permanently locked |
| ~~TGEController for `0x22e37662...`~~ | `0xA8c06C62050D3C29acC43a0B4588a8a170049475` | ❌ Deprecated |
| ~~Original deployer (key lost)~~ | `0xc479368a5c888f91db6ebc85a3f51c8dbc404c73` | ❌ Inaccessible |

> The original `0x453f81...` token was deployed by `0xc479...4c73` (deployer key lost).
> Its TGE controller has 989,880 DIASPORA pre-minted and locked — irrecoverable.
> ~10,120 DIASPORA was distributed to ~26 test users on that chain and is unrecoverable
> from their wallets. None of these tokens are the canonical $DIASPORA.
> See `DEPLOYMENTS.md` for the full timeline.

### Base Sepolia (Testing)
| Contract | Address |
|----------|---------|
| WalletFactory | `0xBd2721b01b5f29970e31407E0c281B53a5ae6B0f` |
| DiasporaToken (test) | *Deploy with `deploy-testnet.js`* |
| TGEController (test) | *Deploy with `deploy-testnet.js`* |
