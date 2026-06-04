# Community - Interface Documentation

## Overview

The Community feature manages the hierarchical structure of communities (continent → country → state → city) and member relationships within those communities.

## Public Interface

### Services

#### `CommunityService`
**Location:** `lib/features/community/services/community_service.dart`

Primary service for community operations.

**Key Methods:**
```dart
// Get community by ID
Future<CommunityData?> getCommunity(String communityId)

// Get user's communities
Future<List<CommunityData>> getUserCommunities(String userId)

// Get child communities
Future<List<CommunityData>> getChildCommunities(String parentId)

// Get community members
Future<List<String>> getCommunityMembers(String communityId)
```

#### `CommunityHierarchyService`
**Location:** `lib/features/community/services/community_hierarchy_service.dart`

Manages hierarchical relationships.

**Key Methods:**
```dart
// Get full hierarchy path
Future<List<CommunityData>> getHierarchyPath(String communityId)

// Get communities by type
Future<List<CommunityData>> getCommunitiesByType(CommunityType type)
```

### Repository

#### `CommunityRepository`
**Location:** `lib/features/community/repository/community_repository.dart`

Data access layer for communities.

**Key Methods:**
```dart
// CRUD operations
Future<CommunityData?> getCommunityById(String id)
Future<void> createCommunity(CommunityData community)
Future<void> updateCommunity(CommunityData community)

// Membership
Future<void> addMember(String communityId, String userId)
Future<void> removeMember(String communityId, String userId)
```

### Providers

```dart
// User's primary communities
final userCommunitiesProvider = FutureProvider<List<CommunityData>>((ref) => ...);

// Specific community
final communityProvider = FutureProvider.family<CommunityData?, String>((ref, id) => ...);

// Child communities
final childCommunitiesProvider = FutureProvider.family<List<CommunityData>, String>((ref, parentId) => ...);
```

## Dependencies

### Required From Other Features

- **Auth** (`lib/features/auth/`)
  - Current user ID
  
- **Profile** (`lib/features/profile/`)
  - User profile for membership data

- **Shared** (`lib/features/shared/`)
  - Location models

### Required From Core

- **Firebase** (`lib/core/services/`)
  - Firestore for persistence

## Integration Points

### How Other Features Use Community

**DSP Feature:**
```dart
// Get community for epoch tracking
final community = await ref.read(communityServiceProvider).getCommunity(communityId);
```

**Events Feature:**
```dart
// Get community members for event invitations
final members = await ref.read(communityServiceProvider).getCommunityMembers(communityId);
```

**Profile Feature:**
```dart
// Get user's communities for profile display
final communities = await ref.read(communityServiceProvider).getUserCommunities(userId);
```

## Data Models

### `CommunityData`
**Location:** `lib/features/community/models/community_data.dart`

```dart
class CommunityData {
  final String id;
  final String name;
  final CommunityType type;
  final String? parentId;
  final List<String> childIds;
  final int memberCount;
  final Location? location;
  final DateTime createdAt;
}
```

### `CommunityType`
**Location:** `lib/features/community/models/community_data.dart`

```dart
enum CommunityType {
  continent,
  country,
  state,
  city,
}
```

## Hierarchy Structure

```
Continent (e.g., "Africa")
  └── Country (e.g., "Kenya")
      └── State (e.g., "Nairobi County")
          └── City (e.g., "Nairobi")
```

### Hierarchy Rules

- Each community has exactly one parent (except continents)
- Communities can have multiple children
- Users can be members of multiple communities at different levels
- Community IDs follow Firebase document references

## Notes

- Membership is tracked at the lowest level (city)
- Parent memberships are inferred from child memberships
- Community hierarchy is immutable once created
- Use `CommunityHierarchyService` for traversing relationships
