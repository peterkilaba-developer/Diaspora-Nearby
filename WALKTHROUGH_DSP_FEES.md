# Walkthrough: Diaspora Nearby — Frictionless Economy

> **All DSP fees for economic activities have been removed.** The Diaspora economy is now entirely frictionless — users can list businesses, create events, post marketplace listings, and participate in all activities without any DSP costs.

## Design Philosophy

The guiding principle is: **spending money to spend more money is not appealing**. Charging DSP for listing, buying, selling, and participating creates friction that discourages economic activity. Instead, the app's value and deflationary pressure come from natural mechanisms:

## Remaining DSP Burns (Non-Fee Mechanisms)

### 1. Community-Driven Penalties
| Penalty | Amount | Trigger |
|---------|--------|---------|
| Chat Ad Penalty | −1,000 DSP | 10 unique spam reports |
| Spam Report | −100 DSP | Per-report deduction |
| Relationship Rejection | −1,000 DSP | Rejected request |
| Event No-Show | −1,000 DSP | Confirmed absence |

| Vouching Bad Actor | −1,000 DSP | Vouched for a fraudster |
| Misinformation | −1,000 DSP | Community-flagged content |
| Deceptive Org | −10,000 DSP | Fraudulent business |
| Confirmed Fraud | −10,000 DSP | Proven fraud |
| Unresponsive Liaison | −100 DSP | Failed community duties |

### 2. Protocol-Level Burns
- **10% fixed expansion burn** (on new DSP minted)
- **Unassigned slot burn** (treasury burn for unallocated slots)
- **Unclaimed TGE burn** (post-TGE unclaimed allocations)
- **PCT efficiency** (trust-weighted distribution)

## What Was Removed

All of the following fees were previously charged and have been **permanently eliminated**:

| Former Fee | Amount | Where |
|-----------|--------|-------|
| Transfer Fee | 1% (min 1 DSP) | Peer-to-peer transfers |
| Marketplace Seller Gate | 10,000 DSP | First-time seller unlock |
| Per-Listing Fee | 100 DSP | Each marketplace listing |
| Marketplace Buy Fee | 100 DSP | Purchasing items |
| Marketplace Apply Fee | 100 DSP | Applying for jobs |
| Marketplace Hire Fee | 100 DSP | Hiring services |
| Event Listing Fee | 1,000 DSP | Creating events |
| Event Attendee Fee | 100 DSP | Attending events |
| Business Creation Fee | 10,000 DSP | Registering a business |
| Product Page Fee | 1,000 DSP | Enabling product listings |
| Per-Product Item Fee | 100 DSP | Adding each product |
| Traveler Hosting Fee | 10 DSP/day | Hosting sessions |

## Fiat GDP Tracking

Instead of DSP sinks, the economy's health is now measured by **Fiat GDP** — the total USD value of real economic transactions:

- **Marketplace**: Listing fiat prices recorded as GDP on first interaction
- **Events**: Ticket prices for paid events recorded as GDP on purchase
- **Travel**: Booking fiat amounts recorded as GDP on completion

The **floor price** formula is now:
```
Floor Price = Total Fiat GDP (USD) ÷ Total DSP Supply
```

---
**"A frictionless economy that grows through activity, not taxation."**
