# DSP (Diaspora Social Points) - Interface Documentation

## Overview

The DSP feature manages the app's point economy system, including point awards, treasury management, epoch tracking, and Token Generation Events (TGE).

## Public Interface

### Services

#### `PointsService`
**Location:** `lib/features/dsp/services/points_service.dart`

Primary service for DSP operations.

**Key Methods:**
```dart
// Award points to a user
Future<void> awardPoints({
  required String userId,
  required String activityType,
  required int points,
  Map<String, dynamic>? metadata,
})

// Get user's current balance
Future<int> getUserBalance(String userId)

// Get user's points history
Future<List<PointRecord>> getPointsHistory(String userId)
```

#### `EpochService`
**Location:** `lib/features/dsp/services/epoch_service.dart`

Manages epoch cycles and community progress.

**Key Methods:**
```dart
// Get current epoch for a community
Future<EpochDefinition?> getCurrentEpoch(String communityId)

// Get next epoch for a community
Future<EpochDefinition?> getNextCommunityEpoch(String communityId)

// Check if TGE should trigger
Future<bool> shouldTriggerTGE(String communityId)
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

### Providers

```dart
// Current user's DSP balance
final userPointsProvider = StreamProvider<int>((ref) => ...);

// Points history
final pointsHistoryProvider = FutureProvider<List<PointRecord>>((ref) => ...);

// Current epoch
final currentEpochProvider = FutureProvider<EpochDefinition?>((ref) => ...);
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

### Required From Core

- **Firebase** (`lib/core/services/`)
  - Firestore for persistence
  - Cloud Functions for TGE triggers

## Integration Points

### How Other Features Use DSP

**Events Feature:**
```dart
// Award points for event creation
await ref.read(pointsServiceProvider).awardPoints(
  userId: userId,
  activityType: 'event_created',
  points: 10,
);
```

**Chat Feature:**
```dart
// Award points for messaging
await ref.read(pointsServiceProvider).awardPoints(
  userId: userId,
  activityType: 'message_sent',
  points: 1,
);
```

**Community Feature:**
```dart
// Check community epoch status
final epoch = await ref.read(epochServiceProvider).getCurrentEpoch(communityId);
```

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
**Location:** `lib/features/dsp/models/epoch_definition.dart`

```dart
class EpochDefinition {
  final int epochNumber;
  final int targetDSP;
  final int targetPopulation;
  final double treasuryPercentage;
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

## Activity Types

Points are awarded for these activities:

| Activity | Points | Description |
|----------|--------|-------------|
| `message_sent` | 1 | Sending a chat message |
| `event_created` | 10 | Creating a new event |
| `event_attended` | 5 | Attending an event |
| `profile_completed` | 10 | Completing profile |
| `qr_verification` | 20 | Verifying via QR code |
| `daily_share` | 3 | Daily content sharing |

## Notes

- Treasury distribution is 10% of member earnings
- Epochs trigger when BOTH DSP and population targets are met
- TGE milestones follow exponential growth pattern
