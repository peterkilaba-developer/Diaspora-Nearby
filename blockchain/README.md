# blockchain

Hardhat workspace for the $DIASPORA token, TGE controller, smart wallet factory,
and related contracts on Base.

## Start here

- **[DEPLOYMENTS.md](./DEPLOYMENTS.md)** — canonical live contract address, deprecated
  contracts, deployer history, and Basescan operational notes. Read this before
  touching anything on-chain or referencing a $DIASPORA address in code.
- **[IMPROVEMENTS.md](./IMPROVEMENTS.md)** — security & quality roadmap from the
  2026-06-01 audit. Read this **before** opening the system to real users. The single
  biggest action item is moving admin roles off the deployer EOA onto a Gnosis Safe.
- **[/HANDOFF.md](../HANDOFF.md)** — step-by-step playbook for the three remaining
  hands-on tasks (Safe migration, backend secrets, Basescan verify). Start here.

## Common scripts

```bash
# Sign a message from the deployer (used for Basescan ownership verification, etc.)
node scripts/sign-message.js

# Generate a fresh deployer wallet (prints key once — save in password manager!)
node scripts/generate-wallet.js

# Audit current token supply / allocations
node scripts/audit-supply.js
```

See `scripts/` for read-only / setup tooling and `hardhat.config.js` for network configs.

### ⚠️ Dangerous admin scripts — `scripts/admin/`

Anything in `scripts/admin/` touches mainnet state (burning tokens, granting roles,
upgrading proxies, firing TGEs). Read the script source before running. Run only against
the network you intend to touch. **Never** run these against mainnet from a CI job or
from a script that doesn't prompt for confirmation.

## Environment

Copy `.env.example` → `.env` and fill in `PRIVATE_KEY` (deployer key) plus RPC URLs.
`.env` is gitignored — never commit it.
