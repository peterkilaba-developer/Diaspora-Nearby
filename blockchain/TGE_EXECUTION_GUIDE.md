# TGE Execution Guide: Diaspora Token

This guide explains how to use the implemented blockchain infrastructure to launch the **Diaspora Token**.

## 1. Prerequisites
- **Node.js** installed.
- **Hardhat** environment set up (run `npm install` in `blockchain/` directory).
- **Multi-sig Wallet** (e.g., Gnosis Safe) addresses for **Admin** and **Minter** roles.

## 2. Step 1: Contract Deployment
Deploy the `DiasporaToken.sol` contract using the deployment script.

```bash
# Set your environment variables
export SEPOLIA_RPC_URL="your_rpc_url"
export PRIVATE_KEY="your_deployer_key"
export ADMIN_ADDRESS="your_multisig_admin"
export MINTER_ADDRESS="your_multisig_minter"

# Deploy to Testnet
npm run deploy:sepolia
```

## 3. Step 2: Epoch Snapshot
When the **Epoch 1 Milestone** (1k Users / 1M DSP) is hit:
1.  Query your Firebase Firestore for all users with `totalDsp >= 100,000` and `trustScore >= 67`.
2.  Export them into a JSON format: `[{"address": "0x...", "amount": "1000..."}]`.
3.  Save this as `blockchain/scripts/snapshot_epoch1.json`.

## 4. Step 3: Merkle Root Generation
Run the Merkle generator to create the distribution proof.

```bash
node blockchain/scripts/generate_merkle.js
```
- This will output a **Merkle Root**.
- It will generate `blockchain/scripts/merkle_proofs.json` containing the proofs for each user.

## 5. Step 4: On-Chain Initialization
1.  **Minter Multi-sig**: Call the `mint` function on the contract to mint the **Stakeholder Allocation** (50% of the snapshot's total value) to the Treasury wallets.
2.  **Merkle Distribution**: (Optional implementation) You would ideally deploy a `MerkleDistributor` contract with the generated root to allow users to pull their tokens.

## 6. Security Checks
- [ ] Verify that the **Hard Cap** of 1 Trillion is correctly reported by `getHardCapProgress()`.
- [ ] Ensure the **DEFAULT_ADMIN_ROLE** is transferred to the community multi-sig.
- [ ] Ensure the **MINTER_ROLE** is only held by the authorized automated claim logic or multi-sig.
