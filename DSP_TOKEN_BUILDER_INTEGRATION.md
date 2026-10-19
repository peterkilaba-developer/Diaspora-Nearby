# $DIASPORA Token: ERC-20 Integration Specification (The Diaspora Protocol)

This document provides the definitive technical specification for the **$DIASPORA** ERC-20 token, intended for integration by the Token Builder. The token is always referred to as **$DIASPORA** (not $DSP).

## 1. Token Parameters
| Field | Value |
| :--- | :--- |
| **Token Name** | Diaspora |
| **Ticker** | $DIASPORA |
| **Decimals** | 18 |
| **Blockchain** | Ethereum Base Blockchain by Coinbase (ERC-20 Standard) |
| **Smart Contract** | UUPS Upgradeable Proxy |
| **Hard Cap** | 1 Quadrillion (1,000,000,000,000,000 $DIASPORA) |
| **Max Supply** | Dynamic (gated by 10 Epochs, each 10x the previous) |

## 2. Supply Allocation (The 7+3 Model)
The total global supply is minted based on human activity validation (Proof of Social Activities). The following buckets are minted based on the **1:1 Expansion Rule** (For every 1 token a user earns, 1 token is matched for the system).

| Bucket | Allocation | Role |
| :--- | :--- | :--- |
| **User Reward** | 50% of Total Mint | Direct liquidity for the contributor (1.0 $DIASPORA). |
| **Community Sovereignty** | 35% of Total Mint (7 Slots) | 70% of System Match, distributed across 7 community levels. |
| **Founders & Core Team** | 5% of Total Mint (1 Slot) | 10% of System Match, fixed core commitment. |
| **Liquidity Treasury (Aerodrome DEX)** | 5% of Total Mint (1 Slot) | 10% of System Match, strategic on-chain liquidity. |
| **Fixed Burn** | 5% of Total Mint (1 Slot) | 10% of System Match, immediate deflation. |

## 3. TGE Premint + TDE Distribution: The Epoch System
The smart contract pre-mints epoch supply at TGE and distributes it through TDE releases based on the Diaspora Protocol's 10-Epoch growth model.

- **Epoch 1 Supply Target**: **1,000,000 $DIASPORA** (One Million).
- **Each Epoch**: 10x the previous Epoch's supply target, up to 1 Quadrillion at Epoch 10.
- **TDE Releases Per Epoch**: 10 Token Distribution Events, each triggered at a 10% distributed-DSP milestone inside the epoch and distributing that decile of the epoch supply target.
- **Burn Mechanism**: Inefficiency resulting from PCT scores below 91% is automatically burned to the burn address by the smart contract.

## 4. TGE "Great Reset" Prerequisites
Before executing a TGE, the following system-wide actions occur:
1. **DSP Supply Trigger**: The TGE happens once per epoch. TDEs then distribute supply as cumulative distributed DSP crosses each 10% decile milestone. For a 1,000,000 DSP epoch, TDEs occur at 100,000, 200,000, and every additional 100,000 DSP through 1,000,000. Population targets are informational and do not gate execution.
2. **Snapshot Generation**: A final immutable snapshot of Firebase is captured, providing a list of:
   - **Eligible Users**: Users who have completed the base Proof of Humanity milestones with positive DSP balance.
   - **Communities**: Community treasury balances.
   - **System Wallets**: Founders & Core Team, Liquidity Treasury, and Burn addresses.
3. **Distribution**: Users claim their allocation via individual pull claims ("Claim $DIASPORA" button) using cryptographic on-chain verification (Merkle pull claim). $DIASPORA is released adjusted by the user's PCT efficiency: scores 0-10 convert at 0%; scores 11-90 convert at the exact PCT percentage; scores 91-100 convert at 100%. Unconverted amounts are automatically burned to `0x000...dEaD`.
4. **Cleanup**: All claimed off-chain DSP balances are reset to **0** for the next cycle.

## 5. Economic Governance: 10-Epoch Scaling
The protocol scales through 10 Epochs. Each Epoch represents a 10x increase in the distributed-DSP supply target. Population targets are retained as informational network-growth benchmarks.

| Epoch | Informational Population Benchmark | Distributed DSP Trigger |
| :--- | :--- | :--- |
| **1** | 10 | 1,000,000 |
| **2** | 100 | 10,000,000 |
| **3** | 1,000 | 100,000,000 |
| **4** | 10,000 | 1,000,000,000 |
| **5** | 100,000 | 10,000,000,000 |
| **6** | 1,000,000 | 100,000,000,000 |
| **7** | 10,000,000 | 1,000,000,000,000 |
| **8** | 100,000,000 | 10,000,000,000,000 |
| **9** | 1,000,000,000 | 100,000,000,000,000 |
| **10** | 10,000,000,000 (10 Billion) | 1,000,000,000,000,000 |

## 6. Token Utility Sinks
- **Community Penalties**: Spam, fraud, no-shows, and other bad behaviors result in DSP deductions.
- **Protocol Burns**: 10% fixed expansion burn, PCT efficiency burn (unconverted portion). Members can claim earned tokens anytime.
- **PCT Efficiency**: Low trust scores reduce TDE distribution rates, automatically burning unconverted DSP to the dead address. Scores 1-10 convert at 0%.

> **Note:** The economy is frictionless — DSP is only removed through community-driven penalties and protocol-level burns.

