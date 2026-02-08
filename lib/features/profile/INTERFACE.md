# Profile - Interface Documentation

## Overview

The Profile feature manages user data, including basic information, relationships, and profile verification status.

## Public Interface

### Services

#### `ProfileService`
**Location:** `lib/features/profile/services/profile_service.dart`

Primary service for profile operations.

**Key Methods:**
```dart
// Get user profile
Future<ProfileData?> getProfile(String userId)

// Update profile
Future<void> updateProfile(ProfileData profile)

// Update profile fields
Future<void> updateProfileField(String userId, String field, dynamic value)
```

### Repository

#### `ProfileRepository`
**Location:** `lib/features/profile/repository/profile_repository.dart`

Data access layer for profiles.

**Key Methods:**
```dart
// CRUD operations
Future<ProfileData?> getProfileById(String userId)
Future<void> createProfile(ProfileData profile)
Future<void> updateProfile(ProfileData profile)

// Relationships
Future<List<Relationship>> getRelationships(String userId)
Future<void> addRelationship(Relationship relationship)
```

### Providers

```dart
// Current user's profile
final currentUserProfileProvider = StreamProvider<ProfileData?>((ref) => ...);

// Specific user profile
final userProfileProvider = FutureProvider.family<ProfileData?, String>((ref, userId) => ...);

// User relationships
final relationshipsProvider = FutureProvider.family<List<Relationship>, String>((ref, userId) => ...);
```

## Dependencies

### Required From Other Features

- **Auth** (`lib/features/auth/`)
  - Current user authentication state
  - User ID
  
- **Community** (`lib/features/community/`)
  - User's community memberships

- **Shared** (`lib/features/shared/`)
  - Location models

### Required From Core

- **Firebase** (`lib/core/services/`)
  - Firestore for persistence
  - Storage for profile images

## Integration Points

### How Other Features Use Profile

**DSP Feature:**
```dart
// Award points for profile completion
final profile = await ref.read(profileServiceProvider).getProfile(userId);
if (profile?.isComplete ?? false) {
  // Award points
}
```

**Chat Feature:**
```dart
// Get profile for chat display
final profile = await ref.read(profileServiceProvider).getProfile(userId);
```

**Trust Feature:**
```dart
// Get profile for trust verification
final profile = await ref.read(profileServiceProvider).getProfile(userId);
```

## Data Models

### `ProfileData`
**Location:** `lib/features/profile/models/profile_data.dart`

```dart
class ProfileData {
  final String userId;
  final String displayName;
  final String? bio;
  final String? photoUrl;
  final Location? location;
  final List<String> interests;
  final bool isVerified;
  final DateTime createdAt;
  final DateTime? updatedAt;
}
```

### `Relationship`
**Location:** `lib/features/profile/models/relationship.dart`

```dart
class Relationship {
  final String id;
  final String userId1;
  final String userId2;
  final RelationshipType type;
  final DateTime createdAt;
}

enum RelationshipType {
  friend,
  family,
  colleague,
  other,
}
```

## Profile Completion

A profile is considered complete when:
- Display name is set
- Profile photo is uploaded
- Bio is filled (min 20 characters)
- Location is set
- At least 3 interests selected

Complete profiles receive bonus DSP points.

## Notes

- Profile photos are stored in Firebase Storage
- Relationships are bidirectional (stored once, queried both ways)
- Profile verification happens through Trust feature
- Profile updates trigger real-time listeners
