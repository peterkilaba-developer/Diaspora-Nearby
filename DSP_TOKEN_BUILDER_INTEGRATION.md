# $DSP Token: ERC-20 Integration Specification (The Diaspora Protocol)

This document provides the definitive technical specification for the Diaspora $DSP ERC-20 token, intended for integration by the Token Builder.

## 1. Token Parameters
| Field | Value |
| :--- | :--- |
| **Token Name** | Diaspora Social Points |
| **Ticker** | $DSP |
| **Decimals** | 18 |
| **Blockchain** | Ethereum (ERC-20 Standard) |
| **Max Supply** | Dynamic (Unlimited, gated by Infinite Halving) |

## 2. Supply Allocation (The 60/10/10/10/10 Model)
The total global supply is minted based on human activity validation (Proof of Activity). The following buckets are minted **pro-rata** based on user earnings.

| Bucket | Allocation % | Role |
| :--- | :--- | :--- |
| **Community (Users)** | 60% | Liquid tokens for PoA/PoCT participants. |
| **Home Country Treasuries** | 10% | Passive community wealth for national communities. |
| **Ecosystem & Grants** | 10% | Foundation treasury for development/partnerships. |
| **Liquidity & Exchange** | 10% | Managed reserves for market making. |
| **Team & Founders** | 10% | Core architect and developer incentives. |

## 3. TGE Minting: The 1-Billion Event
The smart contract's primary action is the one-time minting and distribution of the initial supply based on the Diaspora Protocol's transition to a liquid economy.

- **Initial Mint**: **1,000,000,000 $DSP** tokens (One Billion).
- **Distribution Mechanism**: Batch distribution to wallet addresses based on the final Firebase snapshot.
- **Burn Mechanism**: Any tokens from the 1,000,000,000 initial mint that are **unclaimed** (e.g., users below the 100,000 DSP gate or communities below the 1,000,000 DSP floor) MUST BE **BURNED** by the contract.

## 4. TGE "Great Reset" Prerequisites
Before executing the TGE, the following system-wide actions occur:
1. **Global Trigger**: Cumulative awarded points in the application reach 1,000,000,000 DSP.
2. **Snapshot Generation**: A final immutable snapshot of Firebase is captured, providing a list of:
   - **Eligible Users**: Users with **>= 100,000 DSP** balance (Filtered in Firebase).
   - **Communities**: National Home Country community treasure balances (**>= 1,000,000 DSP** gate).
   - **System Wallets**: Ecosystem, Liquidity, and Founders/Team addresses.
3. **Distribution**: The smart contract accepts this batch data (List of `Address : Balance`) and distributes $DSP at a **1:1 ratio**.
4. **Cleanup**: All off-chain DSP balances in the application are reset to **0**.

## 5. Economic Governance: Infinite Halving
The protocol enters a new Epoch every 1 Billion $DSP minted. The $DSP token has no hard cap, but issuance difficulty doubles reaching an asymptotic limit.

- **Epoch 1**: Initial 1 Billion $DSP.
- **Epoch 2**: Halving Triggered. All PoA reward rates drop by 50%.
- **Epoch N**: Halving continues until rewards < 1 DSP.

## 6. Token Utility Sinks
- **Remittance**: Peer-to-peer cross-border transfer.
- **Bereavement**: Participation in community resilience funds.
- **Merchant Payments**: Booking travel and paying for directory services.
- **Staking**: Reputation staking for governance rights.
