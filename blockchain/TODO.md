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
  npx hardhat verify --network base-mainnet 0x453f81D3a4Bb142AE34C53798BE35e7600D1b25c
  npx hardhat verify --network base-mainnet 0xa3F092357655C0Bc5fb2Ba4B61f25c5422F59FED
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
- [ ] **Council approval flow** — elected council members review & approve in-app
  - Stored in `governance/{communityId}/ddi_loans/{loanId}`
  - `requiredSignatures: 3` (3 of 5 council members)
  - Approvals tracked per council member
- [ ] **Auto-disburse on quorum** — Cloud Function fires when approval threshold met
  - Transfers $DIASPORA from community smart wallet to applicant wallet
  - Records TX hash for audit
- [ ] **Cascading treasury logic** — if local treasury insufficient, escalate:
  - City → State → Country → Continent (each level needs its own council approval)
- [ ] **Repayment tracking** — schedule, payments received, status updates

### TGE Security
- [ ] **Admin role for executeTGE** — restrict manual trigger to admin custom claim
- [ ] **Test token cleanup** — options: burn 1,800 test tokens or redeploy for clean slate

## Deployed Contracts

### Base Mainnet (Production) — Current
| Contract | Address |
|----------|---------|
| DiasporaToken ($DIASPORA) | `0x453f81D3a4Bb142AE34C53798BE35e7600D1b25c` |
| TGEController | `0xa3F092357655C0Bc5fb2Ba4B61f25c5422F59FED` |
| DiasporaToken Implementation | `0xAB10Ed33d980B0DaA93eb9aE9786754492E38c5a` |
| TGEController Implementation | `0xadA512Ac521E4D2bd3D123D4Ba6fb3e875E3490a` |

### ~~Base Mainnet (Deprecated Test)~~
| Contract | Address | Status |
|----------|---------|--------|
| ~~DiasporaToken (test, 1,890 tokens)~~ | `0x22e37662801ba7bE67Df7A593a5ad616C1DBb30B` | ❌ Deprecated |
| ~~TGEController (test)~~ | `0xA8c06C62050D3C29acC43a0B4588a8a170049475` | ❌ Deprecated |

### Base Sepolia (Testing)
| Contract | Address |
|----------|---------|
| WalletFactory | `0xBd2721b01b5f29970e31407E0c281B53a5ae6B0f` |
| DiasporaToken (test) | *Deploy with `deploy-testnet.js`* |
| TGEController (test) | *Deploy with `deploy-testnet.js`* |
