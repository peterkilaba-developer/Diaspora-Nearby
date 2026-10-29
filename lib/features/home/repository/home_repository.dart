import 'dart:async';
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

// ─── [PERF] Cached Nearby Users Provider ───
// Replaces the raw FutureBuilder approach. Data is cached per ViewMode and only
// refreshed in the background when stale or when the user explicitly refreshes.
final nearbyUsersProvider =
    AsyncNotifierProvider<NearbyUsersNotifier, List<ProfileData>>(
      NearbyUsersNotifier.new,
    );

class NearbyUsersNotifier extends AsyncNotifier<List<ProfileData>> {
  // [PERF] In-memory cache per ViewMode (Local & Global) for 0ms mode switching
  static final Map<ViewMode, List<ProfileData>> _cachedUsersByMode = {};
  static final Map<ViewMode, DateTime> _lastFetchByMode = {};
  static const _cacheTtl = Duration(minutes: 3);

  /// Synchronously read cached users for a given [ViewMode]
  static List<ProfileData>? getCachedForMode(ViewMode mode) =>
      _cachedUsersByMode[mode];

  /// Synchronously read all unique cached users across all modes
  static List<ProfileData> getAllCachedUsers() {
    final map = <String, ProfileData>{};
    for (final list in _cachedUsersByMode.values) {
      for (final u in list) {
        final key = u.uid ?? '${u.firstName}_${u.lastName}';
        map[key] = u;
      }
    }
    return map.values.toList();
  }

  Set<String> _getSyncDmExclusionIds() {
    final auth = ref.read(authRepositoryProvider);
    final chatRepo = ref.read(chatRepositoryProvider);
    final currentUser = auth.currentUser;
    if (currentUser == null) return const {};

    final cached = chatRepo.cachedChats;
    if (cached.isEmpty) {
      // Trigger non-blocking background warm-up instead of awaiting
      unawaited(chatRepo.getUserChats().then<void>((_) {}).catchError((_) {}));
      return const {};
    }

    final dmUserIds = <String>{};
    for (final chat in cached) {
      if (chat.type == 'direct') {
        for (final pid in chat.participants) {
          if (pid != currentUser.uid) dmUserIds.add(pid);
        }
      }
    }
    return dmUserIds;
  }

  List<ProfileData> _enrichAndSort(
    List<ProfileData> users,
    ProfileData? viewer,
  ) {
    final enriched =
        users
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

    final profileRepo = ref.read(profileRepositoryProvider);
    for (final u in enriched) {
      if (u.uid != null && u.uid!.isNotEmpty) {
        profileRepo.cacheProfile(u.uid!, u);
      }
    }
    return enriched;
  }

  Future<void> _prewarmOtherMode(ViewMode otherMode, ProfileData? viewer) async {
    if (_cachedUsersByMode.containsKey(otherMode)) return;
    try {
      final repo = ref.read(homeRepositoryProvider);
      final dmExclusion = _getSyncDmExclusionIds();
      final users = await repo.getNearbyUsers(
        isGlobal: otherMode == ViewMode.global,
        dmExclusionIds: dmExclusion,
        currentUserProfile: viewer,
      );
      final enriched = _enrichAndSort(users, viewer);
      _cachedUsersByMode[otherMode] = enriched;
      _lastFetchByMode[otherMode] = DateTime.now();
    } catch (_) {}
  }

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
    final currentUserId = ref.read(authRepositoryProvider).currentUser?.uid;
    final viewer =
        ref.read(userProfileProvider).value ??
        (currentUserId != null
            ? ref.read(profileRepositoryProvider).getCachedProfile(currentUserId)
            : null);

    final now = DateTime.now();
    final cachedForMode = _cachedUsersByMode[viewMode];
    final lastFetch = _lastFetchByMode[viewMode] ?? DateTime(2000);

    // [PERF] Serve from cache immediately if present
    if (cachedForMode != null && cachedForMode.isNotEmpty) {
      final updated = _enrichAndSort(cachedForMode, viewer);
      _cachedUsersByMode[viewMode] = updated;

      if (now.difference(lastFetch) >= _cacheTtl) {
        // Refresh in background without flashing loading state
        unawaited(_refreshModeInBackground(viewMode, viewer));
      }
      return updated;
    }

    final repo = ref.read(homeRepositoryProvider);
    final dmExclusion = _getSyncDmExclusionIds();
    final users = await repo.getNearbyUsers(
      isGlobal: isGlobal,
      dmExclusionIds: dmExclusion,
      currentUserProfile: viewer,
    );

    final enriched = _enrichAndSort(users, viewer);
    _cachedUsersByMode[viewMode] = enriched;
    _lastFetchByMode[viewMode] = DateTime.now();

    // Speculatively pre-warm the opposite mode so toggling Local <-> Global is 0ms
    final otherMode = isGlobal ? ViewMode.home : ViewMode.global;
    unawaited(_prewarmOtherMode(otherMode, viewer));

    return enriched;
  }

  Future<void> _refreshModeInBackground(
    ViewMode mode,
    ProfileData? viewer,
  ) async {
    try {
      final repo = ref.read(homeRepositoryProvider);
      final dmExclusion = _getSyncDmExclusionIds();
      final users = await repo.getNearbyUsers(
        isGlobal: mode == ViewMode.global,
        dmExclusionIds: dmExclusion,
        currentUserProfile: viewer,
      );
      final enriched = _enrichAndSort(users, viewer);
      _cachedUsersByMode[mode] = enriched;
      _lastFetchByMode[mode] = DateTime.now();
      if (ref.read(nearbyViewModeProvider) == mode) {
        state = AsyncData(enriched);
      }
    } catch (_) {}
  }

  /// Background refresh if cache is older than TTL — keeps existing users
  /// visible on screen without flashing a loading state on tab switches.
  Future<void> refreshIfStale() async {
    final viewMode = ref.read(nearbyViewModeProvider);
    final now = DateTime.now();
    final cached = _cachedUsersByMode[viewMode];
    final lastFetch = _lastFetchByMode[viewMode] ?? DateTime(2000);
    if (cached == null || cached.isEmpty) {
      ref.invalidateSelf();
    } else if (now.difference(lastFetch) >= _cacheTtl) {
      final currentUserId = ref.read(authRepositoryProvider).currentUser?.uid;
      final viewer =
          ref.read(userProfileProvider).value ??
          (currentUserId != null
              ? ref
                    .read(profileRepositoryProvider)
                    .getCachedProfile(currentUserId)
              : null);
      await _refreshModeInBackground(viewMode, viewer);
    }
  }

  /// Force refresh — called by pull-to-refresh
  Future<void> refresh() async {
    final viewMode = ref.read(nearbyViewModeProvider);
    final currentUserId = ref.read(authRepositoryProvider).currentUser?.uid;
    final viewer =
        ref.read(userProfileProvider).value ??
        (currentUserId != null
            ? ref.read(profileRepositoryProvider).getCachedProfile(currentUserId)
            : null);
    await _refreshModeInBackground(viewMode, viewer);
  }
}

class HomeRepository {
  final AuthRepository _auth;
  static final Map<String, List<ProfileData>> _searchCache = {};

  HomeRepository(this._auth);

  /// [PERF] Synchronously filter cached nearby & searched users for 0ms instant search
  List<ProfileData> searchCachedUsers(String queryText) {
    final q = queryText.trim().toLowerCase();
    if (q.isEmpty) return const [];

    if (_searchCache.containsKey(q)) {
      return _searchCache[q]!;
    }

    final currentUid = _auth.currentUser?.uid;
    final allCached = NearbyUsersNotifier.getAllCachedUsers();
    return allCached.where((u) {
      if (u.uid == currentUid) return false;
      final fullName = '${u.firstName} ${u.lastName}'.toLowerCase();
      final bio = (u.bio ?? '').toLowerCase();
      final city = (u.hostLocation.city ?? '').toLowerCase();
      final country = (u.homeCountry ?? '').toLowerCase();
      return fullName.contains(q) ||
          bio.contains(q) ||
          city.contains(q) ||
          country.contains(q);
    }).toList();
  }

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
    final q = queryText.trim().toLowerCase();
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null || q.isEmpty) return [];

      final result = await FirebaseFunctions.instance
          .httpsCallable('searchUsers')
          .call({'query': queryText});
      final payload = Map<String, dynamic>.from(result.data as Map);
      final users = (payload['users'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                ProfileData.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(growable: false);
      _searchCache[q] = users;
      return users;
    } catch (e) {
      debugPrint('[HomeRepository] searchUsers error: $e');
      return searchCachedUsers(queryText);
    }
  }
}
