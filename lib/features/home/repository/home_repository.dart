import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/core/providers/view_mode_provider.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/core/utils/location_utils.dart';

final homeRepositoryProvider = Provider((ref) {
  final auth = ref.watch(authRepositoryProvider);
  return HomeRepository(auth);
});

// ─── [PERF] Cached DM exclusion list ───
// Fetching all chats to build an exclusion set is expensive.
// Cache it for 10 minutes — only rebuild on explicit invalidation.
final _dmExclusionProvider = FutureProvider<Set<String>>((ref) async {
  final auth = ref.watch(authRepositoryProvider);
  final chatRepo = ref.watch(chatRepositoryProvider);
  final currentUser = auth.currentUser;
  if (currentUser == null) return {};

  final Set<String> dmUserIds = {};
  try {
    final cached = chatRepo.cachedChats;
    final chats = cached.isNotEmpty ? cached : await chatRepo.getUserChats();
    for (var chat in chats) {
      if (chat.type == 'direct') {
        for (var pid in chat.participants) {
          if (pid != currentUser.uid) dmUserIds.add(pid);
        }
      }
    }
  } catch (e) {
    debugPrint('[PERF] DM exclusion fetch failed: $e');
  }
  return dmUserIds;
});

// ─── [PERF] Cached Nearby Users Provider ───
// Replaces the raw FutureBuilder approach. Data is cached and only
// re-fetched when the view mode changes or the user explicitly refreshes.
final nearbyUsersProvider =
    AsyncNotifierProvider<NearbyUsersNotifier, List<ProfileData>>(
      NearbyUsersNotifier.new,
    );

class NearbyUsersNotifier extends AsyncNotifier<List<ProfileData>> {
  // [PERF] In-memory cache with TTL to avoid hammering Firestore
  static List<ProfileData>? _cachedUsers;
  static ViewMode? _cachedViewMode;
  static DateTime _lastFetch = DateTime(2000);
  static const _cacheTtl = Duration(minutes: 3);

  @override
  Future<List<ProfileData>> build() async {
    final viewMode = ref.watch(nearbyViewModeProvider);
    final isGlobal = viewMode == ViewMode.global;

    // Watch viewer's coordinates & homeCountryCode so distances/sorting update in real time
    ref.watch(
      userProfileProvider.select(
        (p) => (
          p.value?.currentLocation?.geometry.location.lat,
          p.value?.currentLocation?.geometry.location.lng,
          p.value?.hostLocation.geometry?.location.lat,
          p.value?.hostLocation.geometry?.location.lng,
          p.value?.homeCountryCode,
        ),
      ),
    );
    final viewer = ref.read(userProfileProvider).value;

    // [PERF] Serve from cache if still fresh, non-empty, and same view mode,
    // but recompute live distances and re-sort by proximity.
    final now = DateTime.now();
    if (_cachedUsers != null &&
        _cachedUsers!.isNotEmpty &&
        _cachedViewMode == viewMode &&
        now.difference(_lastFetch) < _cacheTtl) {
      debugPrint(
        '[PERF] nearbyUsersProvider CACHE HIT (${_cachedUsers!.length} users, ${now.difference(_lastFetch).inSeconds}s old)',
      );
      final updated = _cachedUsers!
          .map(
            (u) => u.copyWith(
              distance: calculateProfileDistanceKm(
                viewer,
                u,
                fallbackDistanceKm: u.distance,
              ),
            ),
          )
          .toList()
        ..sort((a, b) {
          final dA = a.distance ?? double.infinity;
          final dB = b.distance ?? double.infinity;
          return dA.compareTo(dB);
        });
      _cachedUsers = updated;
      return updated;
    }

    debugPrint('[PERF] nearbyUsersProvider FETCHING (isGlobal=$isGlobal)');
    final repo = ref.read(homeRepositoryProvider);
    // Nearby data must not be blocked by a full chat-history scan. On a slow
    // or reconnecting Firestore client that scan can take indefinitely.
    final dmExclusion = await ref
        .watch(_dmExclusionProvider.future)
        .timeout(const Duration(seconds: 2), onTimeout: () => <String>{});
    final users = await repo.getNearbyUsers(
      isGlobal: isGlobal,
      dmExclusionIds: dmExclusion,
      currentUserProfile: viewer,
    );

    final enriched = users
        .map(
          (u) => u.copyWith(
            distance: calculateProfileDistanceKm(
              viewer,
              u,
              fallbackDistanceKm: u.distance,
            ),
          ),
        )
        .toList()
      ..sort((a, b) {
        final dA = a.distance ?? double.infinity;
        final dB = b.distance ?? double.infinity;
        return dA.compareTo(dB);
      });

    // Cache result
    final profileRepo = ref.read(profileRepositoryProvider);
    for (final u in enriched) {
      if (u.uid != null && u.uid!.isNotEmpty) {
        profileRepo.cacheProfile(u.uid!, u);
      }
    }
    _cachedUsers = enriched;
    _cachedViewMode = viewMode;
    _lastFetch = DateTime.now();

    debugPrint('[PERF] nearbyUsersProvider FETCHED ${enriched.length} users');
    return enriched;
  }

  /// Background refresh if cache is older than TTL — keeps existing users
  /// visible on screen without flashing a loading state on tab switches.
  Future<void> refreshIfStale() async {
    final now = DateTime.now();
    if (_cachedUsers == null ||
        _cachedUsers!.isEmpty ||
        now.difference(_lastFetch) >= _cacheTtl) {
      ref.invalidateSelf();
    }
  }

  /// Force refresh — called by pull-to-refresh
  Future<void> refresh() async {
    _cachedUsers = null; // Bust cache
    _lastFetch = DateTime(2000);
    ref.invalidate(_dmExclusionProvider); // Also refresh DM exclusion
    ref.invalidateSelf();
  }
}

class HomeRepository {
  final AuthRepository _auth;

  HomeRepository(this._auth);

  /// [PERF] Accepts pre-cached DM exclusion set to avoid re-fetching chats
  Future<List<ProfileData>> getNearbyUsers({
    bool isGlobal = false,
    Set<String> dmExclusionIds = const {},
    ProfileData? currentUserProfile,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return [];
      final result = await FirebaseFunctions.instance
          .httpsCallable('findNearbyUsers')
          .call({
            'global': isGlobal,
            'radiusKm': 100,
            'limit': 50,
            'excludeUserIds': dmExclusionIds.take(100).toList(),
          });
      final payload = Map<String, dynamic>.from(result.data as Map);
      return (payload['users'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                ProfileData.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(growable: false);
    } catch (e) {
      debugPrint('[HomeRepository] getNearbyUsers error: $e');
      return [];
    }
  }

  Future<List<ProfileData>> searchUsers(String queryText) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null || queryText.isEmpty) return [];

      final result = await FirebaseFunctions.instance
          .httpsCallable('searchUsers')
          .call({'query': queryText});
      final payload = Map<String, dynamic>.from(result.data as Map);
      return (payload['users'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                ProfileData.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(growable: false);
    } catch (e) {
      debugPrint('[HomeRepository] searchUsers error: $e');
      return [];
    }
  }
}
