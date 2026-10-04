# $DIASPORA (Diaspora Social Points) - Interface Documentation

## Overview

The $DIASPORA feature manages the app's token economy system, including reward awards, treasury management, epoch tracking, value sinks, and Token Generation Events (TGE). The token is always referred to as **$DIASPORA**.

## Public Interface

### Services

#### `PointsService`
**Location:** `lib/features/dsp/services/points_service.dart`

Primary service for $DIASPORA operations.

**Key Methods:**
```dart
// Award points to a user
Future<void> awardPoints({
  required String userId,
  required int amount,
  required String reason,
})

// Deduct points from a user (fees/penalties)
Future<void> deductPoints({
  required String userId,
  required int amount,
  required String reason,
})

// Transfer $DIASPORA between users
Future<void> transferAsset({
  required String fromUserId,
  required String toUserId,
  required int amount,
  required String assetType,
})
```

#### `EpochService`
**Location:** `lib/features/dsp/services/epoch_service.dart`

Manages epoch cycles and community progress.

**Key Methods:**
```dart
// Get current epoch definition
EpochDefinition getEpoch(int epochNumber)

// Check TGE/TDE eligibility
bool isEligibleForTGE(int dspBalance, int trustScore, int epochNumber)

// Calculate TGE swap amount with efficiency
double calculateTGESwapAmount(int dspBalance, int trustScore)
```

#### `TreasuryService`
**Location:** `lib/features/dsp/services/treasury_service.dart`

Handles community treasury distribution.

**Key Methods:**
```dart
// Distribute points to treasuries
Future<void> distributeTreasuryPoints({
  required String userId,
  required int amount,
})

// Sync treasury balances
Future<void> syncTreasuryBalances()
```

## Dependencies

### Required From Other Features

- **Auth** (`lib/features/auth/`)
  - Current user ID via `authRepositoryProvider`
  
- **Community** (`lib/features/community/`)
  - User's community memberships
  - Community hierarchy data

- **Profile** (`lib/features/profile/`)
  - User profile data for point awards

- **Trust** (`lib/features/trust/`)
  - Trust score calculation and PCT milestones

### Required From Core

- **Firebase** (`lib/core/services/`)
  - Firestore for persistence
  - Cloud Functions for TGE triggers

## Integration Points

### How Other Features Use $DIASPORA

**Travel Feature (Reward):**
```dart
// Award 1,000 $DIASPORA for booking
await ref.read(pointsServiceProvider).trackTravelBooking(userId, 'flight');
```

**Chat Feature (Reward):**
```dart
// Award 10 $DIASPORA per message
await ref.read(pointsServiceProvider).trackMessageSent(userId);
```

**Community Feature:**
```dart
// Check community epoch status
final epoch = await ref.read(epochServiceProvider).getEpoch(epochNumber);
```

## Activity Types

$DIASPORA is awarded for these activities:

| Activity | $DIASPORA | Description |
|----------|-----------|-------------|
| `signup` | 1,000 | New user registration |
| `referral_reward` | 1,000 | Referral (both parties) |
| `relationship_accepted` | 1,000 | Relationship acceptance |
| `identity_qr_exchange` | 1,000 | In-person QR verification |
| `travel_booking` | 1,000 | Travel booking (flight/stay/car) |
| `new_dm_conversation` | 100 | Starting a new DM |
| `community_post` | 100 | Community post (max 1/day) |
| `daily_check_in` | 100 | Daily app check-in |
| `daily_share` | 100 | Sharing diaspora content |
| `travel_review` | 100 | Travel review |
| `message_sent` | 10 | Sending a chat message |
| `travel_save` | 10 | Saving travel item to wishlist |
| `explore_feature` | 10 | Exploring a new app feature |
| `feedback_reward` | 10 | Submitting feedback |

## Value Sinks (Penalties Only)

All economic activity fees have been removed. $DIASPORA is only deducted through **community-driven penalties**:

| Penalty | $DIASPORA | Description |
|---------|-----------|-------------|
| `spam_report` | -100 | Per spam report |
| `chat_ad_penalty` | -1,000 | 10 unique spam reports |
| `relationship_rejection` | -1,000 | Rejected request |
| `event_no_show` | -1,000 | Confirmed absence |
| `fake_verification` | -1,000 | False identity claim |
| `vouching_bad_actor` | -1,000 | Backed a fraudster |
| `misinformation` | -1,000 | Community flagged |
| `unresponsive_liaison` | -100 | Failed community duties |
| `deceptive_org` | -10,000 | Fraudulent business |
| `confirmed_fraud` | -10,000 | Proven fraud |

## Data Models

### `PointRecord`
**Location:** `lib/features/dsp/models/point_record.dart`

```dart
class PointRecord {
  final String id;
  final String userId;
  final String activityType;
  final int points;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;
}
```

### `EpochDefinition`
**Location:** `lib/features/dsp/services/epoch_service.dart`

```dart
class EpochDefinition {
  final int epochNumber;
}
```

### `TreasuryData`
**Location:** `lib/features/dsp/models/treasury_data.dart`

```dart
class TreasuryData {
  final String communityId;
  final int balance;
  final int cumulativeEarnings;
  final int memberPoints;
}
```

## Notes

- Treasury distribution follows the 1:1 Expansion + 10-Slot Rule
- Epochs trigger when cumulative distributed DSP crosses the next supply milestone; population targets are informational
- TDE milestones follow the 10x exponential growth pattern after each epoch TGE.
- User TGE/TDE gates: Current Location Transparency must be enabled at every participation check. The first TGE additionally requires a complete profile and 10 unique in-person Identity QR exchanges.
- Community TGE gate: 1,000,000 $DIASPORA minimum
- **All economic activities are fee-free** — only penalties and protocol burns remove $DIASPORA from circulation
