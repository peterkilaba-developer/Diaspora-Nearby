# Trust - Interface Documentation

## Overview

The Trust feature manages user verification through QR code scanning and tracks trust levels between users.

## Public Interface

### Services

#### `TrustService`
**Location:** `lib/features/trust/services/trust_service.dart`

Primary service for trust operations.

**Key Methods:**
```dart
// Get trust level between users
Future<TrustLevel> getTrustLevel(String userId1, String userId2)

// Update trust level
Future<void> updateTrustLevel({
  required String userId1,
  required String userId2,
  required TrustLevel level,
})

// Get all trust relationships for a user
Future<List<TrustData>> getUserTrustRelationships(String userId)
```

#### `QRVerificationService`
**Location:** `lib/features/trust/services/qr_verification_service.dart`

Handles QR code verification.

**Key Methods:**
```dart
// Generate QR code for user
Future<String> generateUserQRCode(String userId)

// Verify QR code scan
Future<bool> verifyQRCode(String scannerId, String qrCode)

// Award trust points
Future<void> awardTrustPoints(String scannerId, String scannedUserId)
```

### Repository

#### `TrustRepository`
**Location:** `lib/features/trust/repository/trust_repository.dart`

Data access layer for trust data.

**Key Methods:**
```dart
// CRUD operations
Future<TrustData?> getTrustData(String userId1, String userId2)
Future<void> createTrustData(TrustData trustData)
Future<void> updateTrustData(TrustData trustData)
```

### Providers

```dart
// Trust relationships for current user
final userTrustProvider = FutureProvider<List<TrustData>>((ref) => ...);

// Trust level between two users
final trustLevelProvider = FutureProvider.family<TrustLevel, TrustQuery>((ref, query) => ...);
```

## Dependencies

### Required From Other Features

- **Auth** (`lib/features/auth/`)
  - Current user ID
  
- **Profile** (`lib/features/profile/`)
  - User profiles for verification
  
- **DSP** (`lib/features/dsp/`)
  - Point awards for verification

### Required From Core

- **Firebase** (`lib/core/services/`)
  - Firestore for persistence

## Integration Points

### How Other Features Use Trust

**Profile Feature:**
```dart
// Check if profile is verified
final trustLevel = await ref.read(trustServiceProvider).getTrustLevel(userId, currentUserId);
```

**Events Feature:**
```dart
// Verify event attendees
final isVerified = trustLevel == TrustLevel.verified;
```

## Data Models

### `TrustData`
**Location:** `lib/features/trust/models/trust_data.dart`

```dart
class TrustData {
  final String id;
  final String userId1;
  final String userId2;
  final TrustLevel level;
  final DateTime createdAt;
  final DateTime? verifiedAt;
}
```

### `TrustLevel`
**Location:** `lib/features/trust/models/trust_data.dart`

```dart
enum TrustLevel {
  unverified,    // No verification
  known,         // Met in person
  trusted,       // Multiple interactions
  verified,      // QR code verified
}
```

## Trust Level Display Names

- `unverified` → "Unverified"
- `known` → "Known"
- `trusted` → "Trusted"
- `verified` → "Verified"

Use `TrustLevel.displayName` extension for UI display.

## QR Verification Flow

1. User A generates QR code
2. User B scans QR code
3. System verifies scan authenticity
4. Trust level updated to `verified`
5. Both users awarded DSP points (20 each)

## Notes

- Trust relationships are bidirectional
- QR verification is one-time per pair
- Trust levels can be manually adjusted
- Verification awards 20 DSP to both parties
