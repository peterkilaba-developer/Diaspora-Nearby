# Diaspora Nearby: The Economy Blueprint (PoA, PoCT, & DSP)

This document serves as the master source of truth for the **Diaspora Nearby** economic engine. It defines the relationship between activity, reputation, and digital currency, providing a roadmap for developers to implement this system in any environment.

---

## 1. Core Philosophy: Tokenized Social Capital
The system aims to solve three problems in digital social networks:
1.  **Spam/Bot Resistance**: Making malicious behavior economically expensive.
2.  **Proof of Humanity**: Validating that users are real people via decentralized vetting.
3.  **Early Adopter Exhaustion**: Preventing early users from extracting all value without contributing continued trust (via the Decay mechanism).

---

## 2. DSP (Diaspora Social Points)
**DSP** is the internal unit of account. It is earned through activity (PoA) and preserved through trust (PoCT).

### Lifecycle of the Points (DSP)
- **Phase 1 (Epoch 1)**: Initial supply of points is calculated in-app.
- **Trigger**: System-wide total distributed reaches **1,000,000 DSP (1 Million)**.
- **TGE (Token Generation Event)**:
    - Smart contract mints liquid **$DIASPORA tokens**.
    - Points are swapped for tokens at **tiered efficiency rates** based on Trust Score (PoCT).
    - **Personal Eligibility**: Only users with **>= 10,000 DSP** (Genesis Gate) and **Trust Score >= 51.0** are included.
    - **Treasury Tokenization**: Home Country Community Treasuries launch their liquid tokens upon reaching their milestone.
    - **No Halving**: Rewards remain constant to encourage long-term participation.

---

## 3. Proof of Activity (PoA)
Users earn points for verifiable actions that benefit the network.

### A. Reward Schedule
Rewards are defined by three parameters: **Base**, **Decay Rate**, and **Min Cap**.

| Activity | Base Reward | Description |
| :--- | :--- | :--- |
| **New User Signup** | 1,000 | Initial Welcome Bonus |
| **Referral (Both)** | 1,000 | Viral Growth Reward |
| **Profile Complete** | 1,000 | Proof of Identity |
| **Family Accepted** | 1,000 | Social Graph Validation |
| **New DM Start** | 100 | First message to unique user |
| **Submit Org/Biz** | 1,000 | Contribution to Directory |
| **Create Event** | 1,000 | Community Organization |
| **Verifier Reward** | 100 | Bonus for validating peers |
| **10-Day Streak** | 1,000 | Loyalty Bonus (Share daily) |
| **100-Day Streak** | 10,000 | Long-term Commitment |
| **Daily Share (In/Out)**| 100 | Main Daily Engagement |
| **Community Post** | 100 | Contribution to Groups |
| **In-app Message** | 10 | Micro-utility reward |

### B. Penalty Schedule
Penalties are flat and intended to discourage malicious behavior.

| Action | Penalty | Compensation | Logic |
| :--- | :--- | :--- | :--- |
| **Relationship Rejected** | -1,000 (Sender) | +1,000 (Receiver) | Prevents DM/Connection Spam |
| **Fake Verification** | -2,000 (Submitter) | N/A | Punishing incorrect vetting |
| **Reported for Fraud** | -5,000 (Subject) | N/A | Community Security |
| **Vouching Bad Actor** | -1,000 (Voucher) | N/A | Stake risk for trust |
| **Reported Spam** | -100 (Sender) | N/A | Immediate fine for toxicity |
| **Event No-Show** | -100 (Attendee) | N/A | Resource waste penalty |

---

## 4. Proof of Community Trust (PoCT)
A user's **Trust Score (0-100)** represents the community's collective confidence in their authenticity.

### A. Scoring Components
1.  **Identity (30%)**: Profile completeness (Photo, Bio, Occupation) and Account Age.
2.  **Activity (20%)**: Streaks, Group participation, and Total Earned DSP.
3.  **Reputation (50%)**: Vouches (20%), Active Relationships (20%), and DSP Balance Weight (10% / Ratings).

### B. Trust Levels
- **Not Enough Data (0-50)**
- **Low Trust (51-60)**: 20% Efficiency
- **Basic Trust (61-70)**: 40% Efficiency
- **Medium Trust (71-80)**: 60% Efficiency
- **Standard Trust (81-90)**: 80% Efficiency
- **High Trust (91-100)**: 100% (1:1 Swap)

---

## 5. The Marriage: Trust-Anchored Decay
Points are earned via human activity but governed by time and reputation.

**Rewards Policy:**
- **Constant Earning**: Rewards do not decay over time.
- **TGE Efficiency**: Your Trust Score (PoCT) modulates your swap rate at TGE (e.g. 91+ = 1:1, <51 = No Swap).

---

### The 10% Collective Tribute Logic (Collective PoCT)
The Home Country Tribute is the primary engine for **Collective Proof of Community Trust (CPoCT)**. 
- **Trigger**: Every **TGE Event (10% of Epoch target)** collectively earned by a Home Country's member base.
- **Action**: The **Home Country Treasury** (and 4 other system treasuries) each receive a **10% share** of the total supply minted.
- **Nature**: Pro-rata minting, fostering "All for One" community momentum and national pride.
- **Competition**: The **Country Leaderboard** ranks nations based on their Treasury’s DSP balance.

---

## 7. Tokenomics Allocation (50/50 Split)
Total Supply is minted based on the following split:
1. **User Share**: 50%
2. **System Share**: 50% (Distributed across 5 buckets)
    - **Home Country Treasury**: 10%
    - **Continent Treasury**: 10%
    - **Ecosystem Treasury**: 10%
    - **Liquidity Pool**: 10%
    - **Founders & Team**: 10%

---

## 8. Implementation Checklist for Developers
To build this system from scratch:
1.  [ ] **Repository Layer**: Store `SignupDate`, `TotalDSP`, `DailyCounters`, and `VouchRecords`.
2.  [ ] **Trust Service**: Implement a periodic or trigger-based `recalculateTrustScore` function using the weighting described in Section 4.
3.  [ ] **Points Service**: Use the `Trust-Anchored Decay` formula in every `addPoints` call.
4.  [ ] **Cooldown Scheduler**: Enforce 24-hour windows for high-impact rewards (Verifications, Daily Opens).
5.  [ ] **Validation Middleware**: Check for "Conflict of Interest" before allowing Vouching or Verification.
