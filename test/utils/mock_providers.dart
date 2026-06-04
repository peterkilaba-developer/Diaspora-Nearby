import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/community/repository/community_repository.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';
import 'mocks.mocks.dart';

/// Mock providers for testing with Riverpod
/// 
/// Use these to override real providers in tests:

// Mock Auth Repository
final mockAuthRepository = MockAuthRepository();

// Mock Profile Repository
final mockProfileRepository = MockProfileRepository();

// Mock Community Repository
final mockCommunityRepository = MockCommunityRepository();

// Mock Points Service
final mockPointsService = MockPointsService();

// Mock Trust Service
final mockTrustService = MockTrustService();

/// Helper to create test container with common overrides
ProviderContainer createTestContainer({
  AuthRepository? authRepository,
  ProfileRepository? profileRepository,
  CommunityRepository? communityRepository,
  PointsService? pointsService,
  TrustService? trustService,
}) {
  return ProviderContainer(
    overrides: [
      if (authRepository != null)
        authRepositoryProvider.overrideWithValue(authRepository),
      if (profileRepository != null)
        profileRepositoryProvider.overrideWithValue(profileRepository),
      if (communityRepository != null)
        communityRepositoryProvider.overrideWithValue(communityRepository),
      if (pointsService != null)
        pointsServiceProvider.overrideWithValue(pointsService),
      if (trustService != null)
        trustServiceProvider.overrideWithValue(trustService),
    ],
  );
}
