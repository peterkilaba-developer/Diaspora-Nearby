# $DIASPORA: Sovereign Currency Roadmap

> **Vision**: $DIASPORA becomes the exclusive medium of exchange within the Diaspora Nearby economy, with local-currency on-ramps and off-ramps making it a truly sovereign digital currency for the global diaspora.

---

## 🧩 DSP vs $DIASPORA: THE CRITICAL DISTINCTION

DSP and $DIASPORA are **NOT the same thing**. They represent fundamentally different states:

| | **DSP** (Pre-Token Points) | **$DIASPORA** (On-Chain Token) |
|:--|:--------------------------|:-------------------------------|
| **What** | Off-chain social points | ERC-20 token on Base blockchain |
| **Where** | Firebase only | Base blockchain only |
| **Exists on chain?** | ❌ No | ✅ Yes |
| **Tradeable?** | ❌ No | ✅ Yes |
| **Has real value?** | ❌ Not yet — it's a claim ticket | ✅ Yes — backed by Fiat GDP |
| **Lifecycle** | Earned → Snapshot → **Burned at TGE** | Minted at TGE → Held/Traded/Spent |

### The Lifecycle

```
PRE-TGE (Each Epoch):
  User Activity → +DSP (off-chain, Firebase)
  DSP accumulates toward 10,000 DSP Gate

AT TGE:
  1. Snapshot all DSP balances
  2. Apply decile scaling efficiency (51-100 Trust → 60-100% conversion)
  3. Mint $DIASPORA on Base at adjusted 1:1 ratio
  4. Distribute $DIASPORA to user wallets
  5. ALL DSP is BURNED (reset to 0)
  6. DSP ceases to exist until next epoch begins

POST-TGE:
  User holds $DIASPORA (on-chain, real, tradeable)
  NO DSP exists — it was burned
  Next epoch: DSP accumulation cycle begins again
```

> [!IMPORTANT]
> **Calling DSP "$DIASPORA" before TGE is misleading.** DSP does not exist on the blockchain. It has no market value. It is a **claim ticket** — earned through Proof of Activity — that converts into real $DIASPORA at the Token Generation Event. The codebase correctly calls it DSP.

---

## 💡 THE CORE THESIS

> **$DIASPORA's value is NOT speculative. It is anchored to real economic activity that the Diaspora community performs every day — sending money home, booking flights, buying goods, renting cars, hiring professionals, and hosting travelers.**

The token's base value at TGE is determined by:

```
Floor Price = Total Fiat GDP Processed / Total $DIASPORA in Circulation
```

This means: if the Diaspora economy processes **$190,000 USD** in real fiat-equivalent transactions, and there are **850,000 $DIASPORA** in circulation — then **1 $DIASPORA ≈ $0.23 floor**.

---

## 📐 THE THREE-PHASE TRANSITION

```
┌──────────────────────────────────────────────────────────────────────┐
│                                                                      │
│  PHASE 1                 PHASE 2                  PHASE 3            │
│  Pre-TGE                Post-TGE                  Epoch 3+           │
│  ───────                ────────                  ───────            │
│  DSP = claim ticket     DSP burned.               $DIASPORA only.    │
│  (not a token)          $DIASPORA is real.         Sovereign currency.│
│                         Next epoch: DSP cycle                        │
│                         restarts for new supply.                     │
│                                                                      │
│  Prices in:             Prices in:                Prices in:         │
│  Local Fiat             $DIASPORA + Fiat ref      $DIASPORA only     │
│                                                                      │
│  GDP tracking:          GDP tracking:             GDP tracking:      │
│  Background             Active + displayed        Core metric        │
│                                                                      │
│  On-ramp: None          On-ramp: Buy $DIASPORA    On-ramp: DEX/Bank  │
│  Off-ramp: None         Off-ramp: Sell $DIASPORA  Off-ramp: DEX/Bank │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

---

### Phase 1: THE ACCUMULATION ERA (Now → Epoch 1 TGE)

**Status**: Current state. Users earn DSP, can't extract yet. No token exists.

```
USER ACTION                    WHAT HAPPENS
─────────────                  ────────────
Book a £400 flight    →    +1,000 DSP awarded (trackTravelBooking in PointsService)
                           +$508 USD recorded to Fiat GDP (£400 ÷ 0.79)

Buy KES 5,000 product →    -100 DSP qualifying fee deducted (trackMarketplaceBuyFee)
                           +$32 USD recorded to Fiat GDP (KES 5,000 ÷ 155)

Send a message        →    +10 DSP (social activity, no fiat value tracked)
```

> Note: The +1,000 DSP for travel bookings comes from `trackTravelBooking()` in `PointsService` — this is the existing code reward for a completed booking (flight, stay, or car rental).

**What's tracked during Phase 1**:
- Every DSP amount earned/spent (Firebase)
- Every fiat value behind real transactions, normalized to USD
- Corridor data (which host-country → home-country pair)

**What users see**:
- "DSP balance: 12,450" (their off-chain points)
- "Marketplace prices in KES/GBP/USD" (local currency)
- "Your progress toward the 10,000 DSP Gate"
- Floor price indicator (based on accumulated Fiat GDP)

**At TGE (Epoch 1 triggers when BOTH conditions are met)**:
1. Cumulative DSP supply reaches 1,000,000
2. 100 Verified Humans reached
3. Snapshot all DSP balances from Firebase
4. Apply **decile scaling efficiency** (Trust Score → conversion rate)
5. Mint $DIASPORA on Base at adjusted ratio
6. Distribute to wallets
7. **ALL DSP is burned** — balances reset to 0
8. Announce: **"Floor price: $X.XX based on $Y Fiat GDP"**
9. New DSP accumulation cycle begins for Epoch 2

---

### Phase 2: THE HYBRID ERA (Post-Epoch 1 → Epoch 3)

**Critical change**: After Epoch 1 TGE, users hold **real $DIASPORA tokens** on Base. DSP was burned. For subsequent epochs, a new DSP accumulation cycle runs alongside existing $DIASPORA holdings.

```
USER'S WALLET STATE POST-TGE:
├── $DIASPORA balance: 8,500 (on-chain, Base) ← minted at TGE
├── DSP balance: 0 (burned at TGE)
└── DSP starts accumulating again for Epoch 2

ON-RAMP (Fiat → $DIASPORA):
├── User buys $DIASPORA via DEX (Uniswap on Base)
├── User buys $DIASPORA via mobile money partner (Mpesa, MTN)
├── User tops up via Stripe/PayStack (credit card → $DIASPORA)
└── $DIASPORA goes directly to user's Base wallet

OFF-RAMP ($DIASPORA → Fiat):
├── User sells $DIASPORA on DEX → receives fiat stablecoin
├── Converts via mobile money partner ($DIASPORA → Mpesa)
└── $DIASPORA leaves user's wallet
```

**Pricing transition**:
```
BEFORE (Phase 1):           AFTER (Phase 2):
─────────────────           ─────────────────
"TSh 85,000"                "Ð 1,000 (~TSh 85,000)"
                            ↑ $DIASPORA price  ↑ local fiat reference
```

**Why keep dual pricing during Phase 2?**
- Users need familiar fiat context to understand value
- Sellers need to know their real-world revenue
- Local reference builds trust during the transition period

---

### Phase 3: THE SOVEREIGN ERA (Epoch 3+)

**Goal**: $DIASPORA becomes the exclusive medium of exchange.

```
ALL PRICES IN $DIASPORA:
─────────────────────────
"Ð 1,000 per night"     (peer stay)
"Ð 100 to apply"        (marketplace)
"Ð 5,000 for this item" (goods)

LOCAL FIAT = Reference only:
────────────────────────────
"≈ TSh 85,000" shown in small text below
```

**The flywheel is complete**:
1. Users EARN $DIASPORA through activity (or buy via on-ramp)
2. Users SPEND $DIASPORA in marketplace/travel/events
3. Sellers RECEIVE $DIASPORA as payment
4. Sellers OFF-RAMP to local fiat when needed (or hold $DIASPORA)
5. Buyers ON-RAMP from local fiat to top up
6. Every transaction adds to Fiat GDP → floor price strengthens
7. Floor price rising → holding $DIASPORA becomes attractive
8. More holding → lower velocity → higher price → repeat

---

## 📊 THE THREE TIERS OF ECONOMIC ACTIVITY

### Tier 1: Real Fiat-Tracked Activity (GDP Contributors)
These activities involve **actual money or goods with real fiat value**. We track the exact fiat amount in local currency, normalize to USD.

| Activity | Example | Fiat Value Tracked | DSP Reward/Fee |
|:---------|:--------|:-------------------|:---------------|
| ✈️ **Flight Booking** | London → Dar es Salaam ($600) | $600 USD | +1,000 DSP (trackTravelBooking) |
| 🏨 **Hotel Booking** | 3 nights × $80/night ($240) | $240 USD | +1,000 DSP (trackTravelBooking) |
| 🏠 **Peer Stay Booking** | 5 nights × $45/night ($225) | $225 USD | +1,000 DSP (trackTravelBooking) |
| 🚗 **Car Rental** | 3 days × $55/day ($165) | $165 USD | +1,000 DSP (trackTravelBooking) |
| 🛒 **Marketplace Purchase** | Traditional clothing (TSh 85K) | ~$31 USD | Fiat GDP tracked |
| 💼 **Service Hire** | Consultant (KES 30K) | ~$194 USD | Fiat GDP tracked |
| 📄 **Job Application** | Driver position | Salary tracked | Fiat GDP tracked |
| 💸 **Remittance** | Send $300 to Tanzania | $300 USD | Fiat GDP tracked |
| 🎟️ **Event Ticket** | Diaspora Gala ($25) | $25 USD | Fiat GDP tracked |
| 🏪 **Business Listing** | Restaurant registration | Business valued | Free (no DSP fee) |

### Tier 2: Productive Value (Estimated Fiat Equivalent)
Activities that create economic utility but don't involve direct fiat exchange.

| Activity | Real-World Equivalent | Estimated Fiat Value | DSP Reward |
|:---------|:---------------------|:--------------------|:-----------|
| ⭐ **Travel Review** | TripAdvisor review (ad value) | ~$2-5 | +100 DSP (trackTravelReview) |
| 🏠 **Hosting Traveler** | Airbnb hosting value | Host-set price/day | Free (no DSP fee) |
| 🤝 **QR Identity Exchange** | Notary verification cost | ~$10-25 | +1,000 DSP |

### Tier 3: Social Value (Network Effect)
These activities build the network. No fiat tracking — pure DSP reward.

| Activity | DSP Reward | Source Method |
|:---------|:-----------|:-------------|
| 📱 **Signup** | +1,000 | trackSignup |
| 🔗 **Referral** | +1,000 | trackReferralReward |
| 🤝 **Relationship** | +1,000 | trackRelationshipAccepted |
| 💬 **Message Sent** | +10 | trackMessageSent |
| 📰 **Community Post** | +100 | trackCommunityPost |
| ✅ **Daily Check-in** | +100 | trackDailyCheckIn |
| 📤 **Daily Share** | +100 | trackDailyShare |
| 🔍 **Explore Feature** | +10 | trackExplorationReward |
| 👤 **Profile Completion** | +10,000 | trackProfileCompletion |

---

## 🔢 THE BASE-10 DENOMINATION SYSTEM

Every DSP reward follows a strict **powers-of-10** pattern. This maps to economic significance:

```
10      = Micro-action      (1 message, 1 feature explored, 1 wishlist save)
100     = Daily-action       (1 check-in, 1 share, 1 review)
1,000   = Significant-action (1 booking, 1 connection, 1 referral)
10,000  = Major-milestone    (profile genesis)
```

### Why Base-10 Matters for Valuation
At maturity, the base-10 DSP values should **converge on their real-world fiat equivalents**:

```
If 1 $DIASPORA = $0.10 (ten cents at maturity):
  10 DSP action    → $1.00   (cost of sending an international text)
  100 DSP action   → $10.00  (cost of a daily meal)
  1,000 DSP action → $100.00 (cost of a budget flight subsidy / cashback)
  10,000 DSP action → $1,000  (cost of a business registration)
```

The denomination isn't arbitrary — it's designed so that at scale, the rewards naturally approximate the real-world cost of the equivalent action.

---

## 💹 FIAT GDP: HOW WE ESTABLISH FLOOR VALUE

### Current State (What Exists in Code)
```
Internal GDP = Sum of all DSP penalties + protocol burns
Stored at: system_stats/global → totalInternalGdp
```
This only tracks **DSP volume**, not the **real-world fiat value** behind transactions.

### Proposed Enhancement: Fiat GDP Tracking

Every real transaction that flows through the app has a fiat value. We normalize ALL fiat values to USD using the existing `CurrencyHelper` exchange rates.

> **Note**: `CurrencyHelper` currently uses **static exchange rates** hardcoded in the `_currencyMap` (200+ countries mapped to USD). These are NOT real-time API rates. They are static snapshots (e.g., TSh 2,700 = $1, KES 155 = $1, £0.79 = $1). For Phase 1 this is acceptable. For Phase 2+, live rates from an API (e.g., Open Exchange Rates) should replace the static values.

### USD Normalization (Using Existing CurrencyHelper)

```dart
// CurrencyHelper._currencyMap already has:
//   'TZ': _CurrencyInfo('TZS', 'TSh', 2700)  → 2700 TSh = 1 USD
//   'KE': _CurrencyInfo('KES', 'KSh', 155)   → 155 KSh = 1 USD
//   'GB': _CurrencyInfo('GBP', '£', 0.79)    → 0.79 GBP = 1 USD

// New public method needed:
static double toUsd(double localAmount, String countryCode) {
  final rate = _currencyMap[countryCode.toUpperCase()]?.usdRate ?? 1.0;
  return localAmount / rate;
}

// Examples:
// TSh 85,000 marketplace item → 85000 / 2700 = $31.48 USD
// KES 5,000 service hire      → 5000 / 155   = $32.26 USD  
// £400 flight booking         → 400 / 0.79   = $506.33 USD
```

### What Gets Tracked Per GDP Transaction

```dart
{
  'type': 'flight_booking',           // Activity type
  'dspAmount': 1000,                  // DSP reward/fee
  'fiatAmount': 400.00,               // Original local currency amount
  'fiatCurrency': 'GBP',             // Local currency code
  'fiatAmountUsd': 506.33,           // Normalized to USD
  'corridor': 'GB-TZ',               // Bilateral corridor
  'timestamp': Timestamp.now(),
  'userId': 'abc123',
}
```

### GDP Sources (What's Already in the Codebase)

| GDP Category | Fiat Source | How We Get Fiat Value | Already in Code? |
|:-------------|:-----------|:---------------------|:-----------------|
| **Travel: Flights** | Amadeus API price | `FlightOffer.totalPrice` | ✅ Yes |
| **Travel: Hotels** | Amadeus API price | `HotelOffer.totalPrice` | ✅ Yes |
| **Travel: Peer Stays** | Host-set price | `PeerListing.pricePerUnit × nights` | ✅ Yes |
| **Travel: Car Rentals** | Host-set price | `PeerListing.pricePerUnit × days` | ✅ Yes |
| **Marketplace: Goods** | Seller-set local price | `Listing.priceAmount` ÷ `CurrencyHelper.usdRate` | ✅ Yes |
| **Marketplace: Services** | Provider-set rate | `Listing.priceAmount` ÷ `CurrencyHelper.usdRate` | ✅ Yes |
| **Events: Tickets** | Host-set price | `Event.ticketPrice` | ✅ Yes |
| **Remittances** | User-entered amount | Transfer amount in sender's currency | ✅ Yes |

### Firestore Schema for Fiat GDP

```
/system_stats/global
├── totalDspEarned: 500,000         // Total DSP ever awarded
├── totalDspBurned: 45,000          // Total DSP penalties/burns
├── totalInternalGdp: 45,000        // Current: DSP volume only
│
├── totalFiatGdpUsd: 190,000.00     // NEW: Real USD value of all transactions
├── corridorFiatGdp: {              // NEW: Per bilateral corridor
│     'GB-TZ': 45,000.00,
│     'US-NG': 28,000.00,
│     'CA-KE': 12,000.00,
│   }
├── fiatGdpByCategory: {            // NEW: By activity type
│     'travel_flights': 80,000.00,
│     'travel_stays': 15,000.00,
│     'marketplace_goods': 12,000.00,
│     'marketplace_services': 8,000.00,
│     'remittances': 60,000.00,
│     'events': 5,000.00,
│   }
└── lastUpdated: Timestamp
```

---

## ⚖️ THE VALUATION MODEL AT TGE

### Step 1: Calculate Fiat GDP
```
Total Fiat GDP = Σ(all fiat-tracked transactions normalized to USD)
```

### Step 2: Calculate Circulating Supply
```
Circulating Supply = Total $DIASPORA minted at TGE (user rewards + treasury match - burns)
```

### Step 3: Calculate Floor Price
```
Floor Price = Total Fiat GDP / Circulating Supply
```

### Step 4: Apply Velocity Adjustment
```
Velocity = Period Transaction Volume / Supply
Adjusted Price = Floor Price / max(Velocity, 1.0)
```
Lower velocity (people holding, not spending) = higher price.

### Step 5: Public Projection
```
Public Price = Adjusted Price × 3.5 (Network Effect Multiplier)
```

### Example Scenario for Epoch 1

| Metric | Value |
|:-------|:------|
| **Verified Users** | 100 |
| **Avg flights booked per user** | 2 × $400 avg = $80,000 total |
| **Avg stays booked per user** | 1 × $150 avg = $15,000 total |
| **Avg marketplace txns per user** | 5 × $40 avg = $20,000 total |
| **Avg remittances per user** | 4 × $200 avg = $80,000 total |
| **Avg event tickets per user** | 3 × $20 avg = $6,000 total |
| **Total Fiat GDP** | **$201,000** |
| **Circulating $DIASPORA (after burns)** | ~850,000 |
| **Floor Price** | $201,000 / 850,000 = **$0.24** |
| **Public Projection (3.5x)** | **$0.83** |
| **Floor Market Cap** | 850,000 × $0.24 = **$204,000** |
| **Projected Market Cap** | 850,000 × $0.83 = **$705,500** |

> **Yes — the market cap is `Floor Price × Circulating Supply`.** At projected value, the Epoch 1 market cap would be ~$705,500. This grows 10x per epoch as both supply and GDP scale.

### Market Cap Growth Across Epochs

| Epoch | Supply Target | Est. Fiat GDP | Floor Price | Floor Market Cap |
|:------|:-------------|:-------------|:------------|:----------------|
| 1 | 1,000,000 | $201,000 | $0.24 | $204,000 |
| 2 | 10,000,000 | $5,000,000 | $0.59 | $5,000,000 |
| 3 | 100,000,000 | $80,000,000 | $0.94 | $80,000,000 |
| 4 | 1,000,000,000 | $1,500,000,000 | $1.76 | $1,500,000,000 |

> These are projections. The key insight: **as GDP grows faster than supply (because each user generates more fiat activity over time), the floor price naturally appreciates.**

---

## 🔄 THE ECONOMIC LOOP

```
┌──────────────────────────────────────────────────────────────────┐
│                                                                  │
│    EARN (Supply Expansion)          SPEND (Value Sinks)          │
│    ──────────────────────           ───────────────────          │
│                                                                  │
│  [ Social Activity ]──→ +DSP       [ Marketplace Fees ] → -DSP  │
│       (no fiat GDP)                   (+fiat GDP recorded)      │
│                                                                  │
│  [ Travel Booking ]──→ +DSP        [ Event Fees ] → -DSP        │
│       (+fiat GDP recorded)            (+fiat GDP recorded)      │
│                                                                  │
│  [ Remittance ]──→ -1% fee         [ Business Fees ] → -DSP    │
│       (+fiat GDP recorded)            (+fiat GDP recorded)      │
│                                                                  │
│              ┌───────────────────────────────────┐               │
│              │  FLOOR PRICE = Fiat GDP / Supply  │               │
│              │                                   │               │
│              │  More real transactions → GDP ↑   │               │
│              │  More burns & sinks → Supply ↓    │               │
│              │  Both → $DIASPORA appreciates    │               │
│              └───────────────────────────────────┘               │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

---

## 🔧 IMPLEMENTATION STATUS

### ✅ Already Built (Ready to Use)
| Component | Location | Status |
|:----------|:---------|:-------|
| CurrencyHelper (200+ country → USD static rates) | `marketplace/utils/currency_helper.dart` | ✅ Complete |
| ValuationService (price formula: GDP/Supply/Velocity) | `dsp/services/valuation_service.dart` | ✅ Complete |
| PointsService (earn/spend/transfer with 1% fee) | `dsp/services/points_service.dart` | ✅ Complete |
| EpochService (10 epochs, dual-trigger TGE) | `dsp/services/epoch_service.dart` | ✅ Complete |
| TreasuryService (1:1 allocation, 10-slot model) | `dsp/services/treasury_service.dart` | ✅ Complete |
| Marketplace `priceAmount` in local currency | `marketplace/models/listing_data.dart` | ✅ Complete |
| Travel `pricePerUnit` in USD | `travel/models/peer_listing.dart` | ✅ Complete |
| Amadeus `totalPrice` for flights/hotels | `travel/services/amadeus_service.dart` | ✅ Complete |
| Event `ticketPrice` field | `events/models/event_data.dart` | ✅ Complete |
| P2P transfer with 1% fee | `dsp/services/points_service.dart` | ✅ Complete |
| DSP-to-local currency display | `CurrencyHelper.formatLocalEquivalent()` | ✅ Complete |
| Pre-TGE base rate placeholder | `_baseDspToUsd = 0.001` | ✅ Placeholder |

### 🔨 Needs Building
| Component | What It Does | Priority |
|:----------|:-------------|:---------|
| **`CurrencyHelper.toUsd()` public method** | Normalizes local price → USD | 🔴 Phase 1 |
| **Fiat GDP Aggregator** | Records `fiatAmountUsd` on every GDP-contributing transaction | 🔴 Phase 1 |
| **Firestore `totalFiatGdpUsd` field** | Cumulative USD GDP counter in system_stats | 🔴 Phase 1 |
| **Corridor GDP Tracker** | Groups fiat GDP by `hostCountry-homeCountry` pair | 🟡 Phase 1 |
| **Floor Price Oracle** | Replaces `_baseDspToUsd` with live `Fiat GDP ÷ Supply` | 🟡 Phase 1 |
| **Fiat GDP on Tokenomics page** | Show real GDP alongside DSP volume | 🟡 Phase 1 |
| **Live exchange rate API** | Replace static CurrencyHelper rates with real-time data | 🟢 Phase 2 |
| **On-Ramp: Mpesa/PayStack** | Fiat → $DIASPORA purchase flow | 🟢 Phase 2 |
| **Off-Ramp: DEX/Mpesa** | $DIASPORA → Fiat withdrawal flow | 🟢 Phase 2 |
| **Dual-Price Display** | "Ð 1,000 (~TSh 85K)" format | 🟢 Phase 2 |

---

## 🎯 KEY DECISIONS

### Decision 1: Floor price visibility
**Option A**: Show floor price from Day 1 (even starting at $0.001 → grows with GDP)
**Option B**: Only reveal at TGE announcement

**Recommendation**: Option A — creates a live "stock ticker" effect. Even $0.001 → $0.01 is 10x.

### Decision 2: Social activity fiat value
Should messages, check-ins, etc. carry an estimated fiat value (e.g., $0.01/message)?

**Recommendation**: No — keep GDP backed by **real transactions only**. Social activity earns DSP (supply expansion) but doesn't inflate GDP. This makes the floor price genuinely trustworthy and honest.

### Decision 3: Static vs live exchange rates
CurrencyHelper currently uses **static hardcoded rates**, NOT real-time.

**Recommendation**: Static for Phase 1 (acceptable for pre-TGE). Upgrade to live API rates for Phase 2 when real money flows — accuracy matters when on-ramp/off-ramp are live.

---

## 🏛️ THE ENDGAME TIMELINE

```
2027: Phase 1 Complete
      └── 100 verified humans
      └── ~$200K Fiat GDP tracked
      └── Epoch 1 TGE: Floor price ~$0.24
      └── $DIASPORA minted on Base
      └── DSP burned, next epoch cycle begins

2028: Phase 2 Active
      └── 1,000 verified humans (Epoch 2)
      └── $5M+ Fiat GDP
      └── Mpesa/PayStack on-ramp live
      └── Marketplace prices dual-denominated
      └── Live exchange rates integrated

2029: Phase 2→3 Transition
      └── 10,000 verified humans (Epoch 3)
      └── $80M+ Fiat GDP
      └── Multiple on-ramp/off-ramp partners
      └── Some sellers price exclusively in $DIASPORA

2030+: Phase 3 Sovereign
      └── 100,000+ verified humans (Epoch 4)
      └── $1B+ Fiat GDP
      └── $DIASPORA = primary unit of account
      └── Diaspora economy is self-sustaining
      └── Local fiat = reference only
```

**The Diaspora Nearby app becomes the Central Bank of the global diaspora.**
