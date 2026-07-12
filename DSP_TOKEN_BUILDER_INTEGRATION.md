# $DIASPORA Token: ERC-20 Integration Specification (The Diaspora Protocol)

This document provides the definitive technical specification for the **$DIASPORA** ERC-20 token, intended for integration by the Token Builder. The token is always referred to as **$DIASPORA** (not $DSP).

## 1. Token Parameters
| Field | Value |
| :--- | :--- |
| **Token Name** | Diaspora |
| **Ticker** | $DIASPORA |
| **Decimals** | 18 |
| **Blockchain** | Base (Coinbase Layer 2, ERC-20 Standard) |
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
| **Investors & Partners** | 5% of Total Mint (1 Slot) | 10% of System Match, strategic liquidity. |
| **Fixed Burn** | 5% of Total Mint (1 Slot) | 10% of System Match, immediate deflation. |

## 3. TGE Minting: The Epoch System
The smart contract mints and distributes supply based on the Diaspora Protocol's 10-Epoch growth model.

- **Epoch 1 Supply Target**: **1,000,000 $DIASPORA** (One Million).
- **Each Epoch**: 10x the previous Epoch's supply target, up to 1 Quadrillion at Epoch 10.
- **TGE Events Per Epoch**: 10 events, each distributing 10% of the Epoch's supply target.
- **Distribution Mechanism**: Batch distribution to wallet addresses based on the final Firebase snapshot.
- **Burn Mechanism**: Any tokens from the TGE mint that are **unclaimed** (e.g., users below the 10,000 $DIASPORA gate or communities below the 1,000,000 $DIASPORA floor) MUST BE **BURNED** by the contract.

## 4. TGE "Great Reset" Prerequisites
Before executing a TGE, the following system-wide actions occur:
1. **DSP Supply Trigger**: The TGE fires when cumulative distributed DSP crosses the next supply milestone. Population targets are informational and do not gate execution.
2. **Snapshot Generation**: A final immutable snapshot of Firebase is captured, providing a list of:
   - **Eligible Users**: Users with **>= 10,000 $DIASPORA** balance.
   - **Communities**: Community treasury balances (**>= 1,000,000 $DIASPORA** gate).
   - **System Wallets**: Founders/Team, Investors/Partners, and Burn addresses.
3. **Distribution**: The smart contract accepts this batch data (List of `Address : Balance`) and distributes $DIASPORA at a **1:1 ratio**, adjusted by the user's P.o.C.T Decile Efficiency.
4. **Cleanup**: All off-chain $DIASPORA balances in the application are reset to **0**.

## 5. Economic Governance: 10-Epoch Scaling
The protocol scales through 10 Epochs. Each Epoch represents a 10x increase in the distributed-DSP supply target. Population targets are retained as informational network-growth benchmarks.

| Epoch | Informational Population Benchmark | Distributed DSP Trigger |
| :--- | :--- | :--- |
| **1** | 100 | 1,000,000 |
| **2** | 1,000 | 10,000,000 |
| **3** | 10,000 | 100,000,000 |
| **4** | 100,000 | 1,000,000,000 |
| **5** | 1,000,000 | 10,000,000,000 |
| **6** | 10,000,000 | 100,000,000,000 |
| **7** | 100,000,000 | 1,000,000,000,000 |
| **8** | 1,000,000,000 | 10,000,000,000,000 |
| **9** | 10,000,000,000 | 100,000,000,000,000 |
| **10** | 100,000,000,000 | 1,000,000,000,000,000 |

## 6. Token Utility Sinks
- **Community Penalties**: Spam, fraud, no-shows, and other bad behaviors result in DSP deductions.
- **Protocol Burns**: 10% fixed expansion burn, unassigned slot burn, unclaimed TGE burn.
- **P.o.C.T Efficiency**: Low trust scores reduce TGE conversion rates, effectively burning unconverted DSP.

> **Note:** All economic activity fees (marketplace, events, travel, business) have been permanently removed. The economy is frictionless — DSP is only removed through penalties and protocol-level burns.

