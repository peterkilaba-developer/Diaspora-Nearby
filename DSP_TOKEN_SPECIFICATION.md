# $DSP TOKEN: ARCHITECTURAL SPECIFICATION FOR AI BUILDERS

This document provides the high-level economic and technical specifications for the creation of the **$DSP Token**. It defines the "Flush and Reset" transition from off-chain social points (DSP) to on-chain liquid assets ($DSP) upon reaching critical mass.

---

## 1. THE VISION: SOCIAL CAPITAL LIQUIDITY
Diaspora Nearby is a **Reputation-to-Asset Engine**. It fulfills a two-fold mission: **Connecting Diaspora globally** and **helping them keep in touch with family and friends**. All value generation (minting) occurs off-chain through human activity (PoA) and verified trust (PoCT).

---

## 2. THE MILESONE: EPOCH TRANSITIONS
The Diaspora Nearby economy is structured into **10 Epochs**, each representing a 10x scale in community growth and supply.

### A. The Epoch 1 Milestone (Genesis)
- **Global Threshold**: When the total DSP distributed reaches **1,000,000 (1 Million)**.
- **Protocol Action**:
    1.  **Snapshot**: A full immutable snapshot of the Diaspora User Database is taken.
    2.  **TGE**: The smart contract executes the token minting and distribution based on the Snapshot data.
    3.  **Progression**: The economy enters **Epoch 2**. All future reward targets scale by 10x.

### C. National Treasury Tokenization: A Race for Heritage
- **Eligibility**: Communities participate in the TGE pro-rata based on their earned DSP.
- **The Mini-Milestones**: Every 10% of an Epoch's target (TGE Event) triggers a distribution to the system treasuries.

---

## 3. SMART CONTRACT ROLE: TGE DISTRIBUTION
The smart contract's primary role is to execute the **Token Generation Event (TGE)** distribution based on the state of the Diaspora economy at the moment of each milestone.

### A. Distribution Protocol
1.  **Supply Cap**: The absolute total supply of $DSP is capped at **1,000,000,000,000,000 (1 Quadrillion)**.
2.  **Snapshot Integration**: The contract accepts a batch list of wallet addresses and balances from the Firebase snapshot.
3.  **1:1 Swap Base**: Tokens are distributed at a **1:1 base ratio** to verified users, modulated by their Trust Score (PoCT).
4.  **Min Eligibility**: Only users with **>= 10,000 DSP** (Genesis Gate) at Epoch 1 are eligible for the initial TGE distribution.

### B. Utility Sinks & In-App Economy
$DSP powers the Diaspora ecosystem:
- **Remittance (Peer-to-Peer)**
- **Event Tickets**
- **Bereavement Funds**
- **Travel & Logistics (Air Tickets)**
- **Global Trade (Import/Export)**
- **Merchant Payments**

---

## 4. TOKENOMICS & SUPPLY DYNAMICS

### A. General Parameters
- **Token Name**: Diaspora Social Points
- **Ticker**: $DSP
- **Max Supply**: **1 Quadrillion (1QD)**
- **Initial Mint**: Distributed at Epoch 1 TGE.

### D. Token Allocation Table (50/50 Split)
To ensure long-term stability and reward the community, we use a balanced 50/50 split:

| Stakeholder | Allocation % | Purpose | Vesting / Lock-up |
| :--- | :--- | :--- | :--- |
| **Users (Proof of Activity)** | 50% | Earned via social activity and trust. | Immediate (Subject to TGE) |
| **Home Country Treasury** | 10% | Passive community wealth. | Multi-sig controlled |
| **Continent Treasury** | 10% | Regional infrastructure & growth. | Multi-sig controlled |
| **Ecosystem & Grants** | 10% | Future dev & partnerships. | 12-Month Lock-up |
| **Liquidity & Exchange** | 10% | DEX/CEX liquidity. | Immediate |
| **Team & Founders** | 10% | Core development. | 24-Month Linear Vesting |

### E. The Pro-Rata Minting Strategy

Since **User Activity** drives the entire economy (50% of the distribution), all system buckets (50%) are minted **pro-rata** whenever user tokens are minted.

**The Formula:**
`Total_Supply = User_DSP * 2`

**Example:**
If users have earned **500 Million DSP** at a TGE Snapshot:
1.  **Users (50%)**: 500 Million
2.  **System Shared (50%)**: 500 Million (100M each to Country, Continent, Ecosystem, Liquidity, Founders).
**Total Supply**: 1.0 Billion $DSP

---

## 5. TECHNICAL SPECIFICATIONS FOR BUILDERS

### A. Batch Minting
The contract must accept a **batch-list** from the Diaspora Backend.
- The backend validates the PoCT score (51+) and the point total (>=10,000) before sending instructions.

### B. Governance & Staking
- **Reputation Staking**: Enable special staking for users with a **High Trust Score (91+)** to participate in system governance.

---

## SUMMARY FOR THE AI BUILDER
Build the $DSP token as a **dynamic liquidity engine**. It has no fixed cap, but its issuance is gated by an increasingly aggressive halving schedule. Upon hitting the 1B point trigger, the contract "crystallizes" that activity into on-chain liquidity, rewarding those who reached the 100,000 DSP milestone first and have maintained community trust (67+). This anchors the token's value in the massive utility of global remittances, travel, and trade.
