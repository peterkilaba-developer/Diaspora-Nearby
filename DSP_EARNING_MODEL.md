# DSP Earning Model: Proof of Identity, Activity & Trust

This document defines the **Proof of Identity (PoI)**, **Proof of Activity (PoA)**, and **Proof of Community Trust (PoCT)** protocols that drive the **Diaspora Nearby Platform economy**.

---

## 1. The Core Philosophy
The Diaspora Nearby Platform economy serves a **two-fold mission**:
1.  **Discover & Connect Abroad:** Enabling users to find and connect with fellow Diaspora members from their home country and other nations abroad.
2.  **Connect with Family & Friends (Home & Abroad):** Keeping users in touch with family and friends wherever they are.

The model is designed to tokenize social capital through three distinct pillars (in priority order):

### 1. Mechanism 1: Proof of Identity (PoI)
The entry point. You prove who you are through a sequence of digital and physical validations. Without PoI, access is throttled to prevent bad actors and Sybil attacks.

### 2. Mechanism 2: Proof of Activity (PoA)
The engine. You generate value by participating in the social and economic graph. Every interaction (sharing, messaging, connecting) is a quantifiable contribution to the network.

### 3. Mechanism 3: Proof of Community Trust (PoCT)
The filter. Your reputation score (0-100) determining the efficiency of your earned points conversion. It is composed of 5 factors (adding up to 100 total points).

---

## 2. Mechanism 1: Proof of Identity (PoI)
**Identity Score (Max 20 pts in PoCT):**

1.  **Level 0: Unverified**
    - Mandatory Signup Fields: Home Loc, Host Loc, Photo, Name.
    - **Status:** Newcomer | **Action:** Full platform utility available (no special gatekeeping).
    - **Reward:** 0 DSP | 0 PoCT.

2.  **Level 1: Profile Completion**
    - **Requirement**: Fill *every* field in profile (Bio, Education, Profession, Years in Host, Industry, Interests).
    - **Reward:** +1,000 DSP | **+5 PoCT**.

3.  **Level 2: Peer Verification (The Vouch)**
    - **The Vouch**: Standing verifications are consolidated into field-based peer reviews. A verifier confirms a specific field and provides a **Trust Score (1-5 levels)** via a slider.
    - **Constraint**: A user can only verify **ONE field** of another user (e.g., confirming their Education).
    - **Rewards**:
        - **Verified User**: +1,000 DSP | +5 PoCT.
        - **Verifier**: +100 DSP (Contribution to the trust graph).
    - **Logic**: Prevents collusive sybil accounts by requiring multiple unique peers to validate different facets of one identity.

4.  **Level 3: Physical (QR) Verification**
    - **Requirement**: Physical QR Code scan with another user during an in-person meetup.
    - **Reward**: +10,000 DSP | **+10 PoCT**.
    - **Logic**: Confirms physical presence and completes the Identity pillar (20/20).

### [Behind the Logic: Mechanism 1]
> [!NOTE]
> **Trust as a Scarcity Entry Point**: In a global diaspora network, fake profiles (Sybils) are the primary threat to security and economy. 
> 
> *   **The Multi-User Barrier**: the "One field per user" constraint for Level 2 means a single bot-farm cannot auto-verify an account. It requires a diverse set of real users (at least 7 unique peers) to look at different aspects of your life (Education, Bio, Profession). This enforces "Social Entropy"—a human-verified messiness that algorithms cannot fake.
> *   **Cryptographic Presence (QR)**: Level 3 (QR) is our "Gold Standard." It uses an in-person, time-bounded handshake. This anchors the digital economy to the physical world, ensuring that "High Trust Members" have actually engaged with the community in person.
> *   **The Verifier Reward**: By awarding 100 DSP to the verifier, we turn the community into an "Active immune system." Users are economically incentivized to keep the network clean by performing these field validations.

---

## 3. Mechanism 2: Proof of Activity (PoA)
**Decay Rule:** REMOVED. Rewards are constant (1.0x). Scarcity is driven by the **TGE Efficiency Gates**.

### A. Connectivity & Social Graph
| Activity | Reward (DSP) | Frequency | Max | Description |
| :--- | :--- | :--- | :--- | :--- |
| **Signup** | **1,000** | One-time | 1,000 | Baseline for initial entry. |
| **Referral Bonus** | **1,000** | One-time | 1,000 | Reward for joining via link. |
| **Referrer Reward** | **1,000** | Per User | N/A | Reward for bringing in new users. |
| **Verify Peer (Verifier)**| **100** | Per User | N/A | Reward for verifying another user's field. |
| **Family Connection** | **1,000** | Per User | N/A | Connecting with verified family. |
| **New DM Start** | **100** | Per User | N/A | Initiating contact with a new user. |
| **In-app Msg Send** | **10** | Per Message| N/A | Base engagement reward. |
| **Community Post** | **100** | Per Day/Comm| N/A | Value contribution to groups.|

### B. Content & Contribution (Cross-Platform)
| Activity | Reward (DSP) | Frequency | Description |
| :--- | :--- | :--- | :--- |
| **Share Invite Code** | **100** | No Max | Outbound growth signaling. |
| **Invite Code Used** | **1,000** | Per Signup | Success in expanding the network. |
| **Submit Managed Org** | **1,000** | Per Org | Listing an organization you manage. |
| **Submit Owned Biz** | **1,000** | Per Biz | Listing a business you own. |
| **Share (Inbound)** | **100** | No Max | Importing value from other apps to Diaspora. |
| **Share (Outbound)** | **100** | No Max | Exporting Diaspora content to other platforms. |

### C. Loyalty & Physical Presence
| Activity | Reward (DSP) | Frequency | Description |
| :--- | :--- | :--- | :--- |
| **10-Day Streak** | **1,000** | Every 10 Days| Requires 1 Inbound or Outbound share daily. |
| **100-Day Streak** | **10,000** | Every 100 Days| High-level commitment reward. |
| **Host-a-Traveler** | **1,000** | Per Guest | Verified physical hospitality. |
| **Verify Check-in** | **1,000** | Per Event | Verified by QR at the event venue. |
| **Create Event** | **1,000** | Per Event | Community organization and leadership. |

### [Behind the Logic: Mechanism 2]
> [!TIP]
> **Why Constant Rewards?** Traditional "decay" or "halving" models punish latecomers. In a social app, we want the millionth user to be just as motivated as the first. We move the "scarcity pressure" to the TGE Efficiency gate, where high-trust behavior is the only way to realize 100% of the value. The inclusion of **Cross-Platform Sharing** rewards inbound/outbound flow, making Diaspora the central hub for your diaspora life.

---

## 4. Mechanism 3: Proof of Community Trust (PoCT) & Justice
The PoCT score (0-100) is the sum of five balanced factors (Max 20 pts each):

1.  **Identity (20 pts)**: Verified presence (L1: 5, L2: 5, L3: 10). 
2.  **Activity (20 pts)**: Consistency across DMs, Posts, and Shares.
3.  **Reliability (20 pts)**: Successful event attendance and liaison responses.
4.  **Helpfulness (20 pts)**: Peer-verified solutions and organization vetting.
5.  **Reputation (20 pts)**: Longevity and absence of unique blocks/flags.

### The Justice System (Standardized Penalties)
All major breaches incur a standardized penalty of **-10 PoCT**.

| Action | DSP Penalty | PoCT Penalty | Logic |
| :--- | :--- | :--- | :--- |
| **Family Conn. Rejected**| **-1,000** | **-10** | Prevents connection spam. |
| **10 Unique Blocks** | **-10,000** | **-10** | Community consensus of bad behavior. |
| **10 Unique Flags** | **-10,000** | **-10** | Community flagging of inappropriate content. |
| **Reported for Fraud** | **-10,000** | **-10** | Direct breach of integrity. |
| **Fake Verification** | **-1,000** | **-10** | Attempting to sybil or lie about identity. |
| **Vouching Risk** | **-1,000** | **-10** | Stake lost if the user you vouched is banned. |
| **Event No-Show** | **-1,000** | **-10** | Reliability and social courtesy failure. |
| **Unresponsive Liaison** | **-100/ea** | **-1** | Repeated failure to respond as emergency contact. |

### [Behind the Logic: Mechanism 3]
> [!IMPORTANT]
> **Diversification of Trust**: The 20-point cap on each factor is the ultimate "Anti-Bot" measure. It is easy for a bot to automate "Activity" (20 pts), but it cannot fake "Reliability" (Physical events) or "Identity" (QR scans) easily. To get a perfect 100 score, a user must be a multi-dimensional citizen of the platform.
> 
> *   **Justice as an Economic Deterrent**: The -10 penalty is intentionally high. Because PoCT determines your TGE swap rate, losing 10 points can represent a 10-20% loss in your lifetime earnings value. This forces users to self-police and respect social norms (like connections and event attendance).
> *   **Unique-User Thresholds**: Penalties for Blocks and Flags only trigger after **10 unique individuals** report you. This protects against "targeted harassment" by single individuals or small groups, ensuring that punishment only follows a broad community consensus.

---

## 5. TGE Epochs: Scaling & Supply
**Absolute Supply Cap:** 1 Quadrillion (1QD) DSP.

### Epoch Schedule (10 TGE Events per Epoch)
Scarcity is maintained by 10x scaling. Each Epoch consists of **10 TGE Events**, where each event distributes exactly **10%** of that Epoch's target.

| Epoch | TGE Events (10% each) | DSP Target | Member Target | Label |
| :--- | :--- | :--- | :--- | :--- |
| **1** | 10 x 100k | **1,000,000** | 100 | Genesis |
| **2** | 10 x 1M | **10,000,000** | 1,000 | Growth |
| **3** | 10 x 10M | **100,000,000** | 10,000 | Expansion |
| **4** | 10 x 100M | **1,000,000,000** | 100,000 | Maturity |
| **5** | 10 x 1B | **10,000,000,000** | 1,000,000 | Scaling |
| **6** | 10 x 10B | **100,000,000,000** | 10,000,000 | Established |
| **7** | 10 x 100B | **1,000,000,000,000** | 100,000,000 | Sovereignty |
| **8** | 10 x 1T | **10,000,000,000,000** | 1,000,000,000 | AI Frontier |
| **9** | 10 x 10T | **100,000,000,000,000**| 10,000,000,000 | Machine Economy |
| **10**| 10 x 100T | **1,000,000,000,000,000**| 100,000,000,000 | Agentic Scale |

### Member TGE Swap Efficiency
Efficiency is determined purely by PoCT score and DSP balance.

| PoCT Score | Swap Rate | Member Status | Requirements |
| :--- | :--- | :--- | :--- |
| **91 - 100** | **1 : 1** | **High Trust Member**| 10,000+ DSP Balance |
| **81 - 90** | **-20%** | **Standard Trust Member** | 10,000+ DSP Balance |
| **71 - 80** | **-40%** | **Medium Trust Member** | 10,000+ DSP Balance |
| **61 - 70** | **-60%** | **Basic Trust Member** | 10,000+ DSP Balance |
| **51 - 60** | **-80%** | **Low Trust Member** | **Exit Only** conversion. |
| **< 51** | **0** | **Not Enough Trust Data**| No TGE conversion. |

---

## 6. Community Governance & Treasury (50/50 Split)
The ecosystem uses a balanced split where users earn 50% and the system (Country, Continent, Ecosystem, Liquidity, Founders) receives the other 50% pro-rata.

| Target Share | Percentage | Recipient |
| :--- | :--- | :--- |
| **Mining Pool** | 50% | Users / Community Members |
| **System Pool** | 50% | 5 x 10% (Country, Continent, etc.) |

---
### "Build the wealth that justifies the token. Connect, Earn, and Change your world."
