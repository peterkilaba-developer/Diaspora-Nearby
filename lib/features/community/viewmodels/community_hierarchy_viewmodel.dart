import 'dart:async';
import 'package:diaspora_nearby/features/chat/utils/community_chat_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diaspora_nearby/features/community/models/community_data.dart';
import 'package:diaspora_nearby/features/community/repository/community_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/community/models/hierarchy_item.dart';
import 'package:diaspora_nearby/core/data/countries.dart' as country_data;
import 'package:diaspora_nearby/core/providers/view_mode_provider.dart';
import 'package:diaspora_nearby/core/providers/global_feature_provider.dart';
import 'package:diaspora_nearby/features/discovery/providers/global_search_provider.dart';
import 'package:diaspora_nearby/features/chat/models/chat.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';

// Utils
String getCountryName(String? code) {
  if (code == null) return '';
  final country = country_data.getCountryByCode(code);
  return country?.name ?? code;
}

/// Provider for the hierarchy logic
final communityHierarchyProvider =
    AsyncNotifierProvider<CommunityHierarchyViewModel, List<HierarchyItem>>(() {
      return CommunityHierarchyViewModel();
    });

class CommunityHierarchyViewModel extends AsyncNotifier<List<HierarchyItem>> {
  // [PERF] In-memory cache of built community hierarchies by (mode, countryCode)
  static final Map<String, ({List<HierarchyItem> items, DateTime fetchedAt})>
  _hierarchyCache = {};
  static final Map<String, ({List<Community> communities, DateTime fetchedAt})>
  _rawCommunitiesCache = {};
  static const _cacheTtl = Duration(minutes: 5);

  /// Synchronous lookup for cached hierarchy items to avoid frame-0 loading spinners.
  static List<HierarchyItem>? getCachedHierarchy(
    ViewMode mode,
    String? userHomeCountryCode,
  ) {
    final effectiveCode =
        (userHomeCountryCode != null && userHomeCountryCode.isNotEmpty)
        ? userHomeCountryCode
        : 'US';
    final exact = _hierarchyCache['${mode.name}_$effectiveCode'];
    if (exact != null && exact.items.isNotEmpty) {
      return exact.items;
    }
    for (final entry in _hierarchyCache.entries) {
      if (entry.key.startsWith('${mode.name}_') &&
          entry.value.items.isNotEmpty) {
        return entry.value.items;
      }
    }
    return null;
  }

  @override
  Future<List<HierarchyItem>> build() async {
    final mode = ref.watch(communitiesViewModeProvider);
    final user = ref.read(authStateProvider).value;
    final searchQuery = ref.watch(globalSearchProvider);

    // Watch search
    if (user == null) {
      return [];
    }

    // [PERF] Read user's Home Country Code from in-memory userProfileProvider
    // or ProfileRepository cache before hitting Firestore.
    try {
      final cachedProfile =
          ref.watch(userProfileProvider.select((p) => p.value)) ??
          ref.read(profileRepositoryProvider).getCachedProfile(user.uid);
      String? userHomeCountryCode = cachedProfile?.homeCountryCode;

      if (searchQuery.isEmpty) {
        final preloadCached = getCachedHierarchy(mode, userHomeCountryCode);
        if (preloadCached != null && preloadCached.isNotEmpty) {
          state = AsyncData(preloadCached);
        }
      }

      if (userHomeCountryCode == null || userHomeCountryCode.isEmpty) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final userData = userDoc.data();
        userHomeCountryCode = userData != null
            ? (userData['homeCountryCode'] as String? ??
                  userData['countryCode'] as String? ??
                  userData['homeCountry'] as String? ??
                  userData['country'] as String?)
            : null;
      }

      // Search Interception
      if (searchQuery.isNotEmpty && searchQuery.length >= 2) {
        return _performSearch(
          searchQuery,
          userHomeCountryCode,
          mode == ViewMode.global,
        );
      }

      final effectiveCountryCode =
          (userHomeCountryCode != null && userHomeCountryCode.isNotEmpty)
          ? userHomeCountryCode
          : 'US';
      final cacheKey = '${mode.name}_$effectiveCountryCode';
      final cachedEntry = _hierarchyCache[cacheKey];
      if (cachedEntry != null &&
          cachedEntry.items.isNotEmpty &&
          DateTime.now().difference(cachedEntry.fetchedAt) < _cacheTtl) {
        return cachedEntry.items;
      }

      // Normal View Logic
      final List<HierarchyItem> built;
      if (mode == ViewMode.global) {
        built = await _buildGlobalHierarchy(effectiveCountryCode);
      } else {
        built = await _buildMyCommunityHierarchy(effectiveCountryCode);
      }
      if (built.isNotEmpty) {
        _hierarchyCache[cacheKey] = (items: built, fetchedAt: DateTime.now());
      }
      return built;
    } catch (e) {
      rethrow;
    }
  }

  // ===========================================================================
  // SEARCH LOGIC
  // ===========================================================================
  Future<List<HierarchyItem>> _performSearch(
    String query,
    String? userHomeCode,
    bool isGlobal,
  ) async {
    final firestore = FirebaseFirestore.instance;
    final normalizedQuery = query.toLowerCase().trim();
    List<Community> communities = [];

    final isGlobalUnlocked = ref.read(isGlobalUnlockedSyncProvider);
    if (isGlobal && !isGlobalUnlocked) {
      return [];
    }

    final rawCacheKey = isGlobal ? 'global' : 'home_${userHomeCode ?? 'US'}';
    final cachedRaw = _rawCommunitiesCache[rawCacheKey];
    if (cachedRaw != null && cachedRaw.communities.isNotEmpty) {
      communities = cachedRaw.communities;
      if (DateTime.now().difference(cachedRaw.fetchedAt) >= _cacheTtl) {
        unawaited(_refreshRawCommunitiesCache(isGlobal, userHomeCode));
      }
    } else if (isGlobal) {
      final snapshot = await firestore
          .collection('communities')
          .limit(100)
          .get();
      communities = snapshot.docs
          .map(
            (d) =>
                _safeParseCommunity(d.id, d.data(), userHomeCode: userHomeCode),
          )
          .whereType<Community>()
          .toList();
      _rawCommunitiesCache[rawCacheKey] = (
        communities: communities,
        fetchedAt: DateTime.now(),
      );
    } else {
      // Home View: Search home and host communities matching home country code
      if (userHomeCode == null) return [];

      final snapshot = await firestore
          .collection('communities')
          .where('homeCountryCode', isEqualTo: userHomeCode)
          .limit(200)
          .get();
      communities = snapshot.docs
          .map(
            (d) =>
                _safeParseCommunity(d.id, d.data(), userHomeCode: userHomeCode),
          )
          .whereType<Community>()
          .toList();
      _rawCommunitiesCache[rawCacheKey] = (
        communities: communities,
        fetchedAt: DateTime.now(),
      );
    }

    // Filter by broad match (name, type, location fields)
    final matchedCommunities = communities.where((c) {
      final name = c.name.toLowerCase();
      final type = (c.type ?? '').toLowerCase();
      final locType = (c.locationType ?? '').toLowerCase();

      final city = (c.location?['city'] as String? ?? '').toLowerCase();
      final state = (c.location?['state'] as String? ?? '').toLowerCase();
      final country = (c.location?['country'] as String? ?? '').toLowerCase();
      final countryCode = (c.location?['countryCode'] as String? ?? '')
          .toLowerCase();

      return (name.contains(normalizedQuery) ||
              type.contains(normalizedQuery) ||
              locType.contains(normalizedQuery) ||
              city.contains(normalizedQuery) ||
              state.contains(normalizedQuery) ||
              country.contains(normalizedQuery) ||
              countryCode.contains(normalizedQuery)) &&
          (c.totalMembers ?? c.memberCount) > 0;
    }).toList();

    // Sort Results
    matchedCommunities.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

    // Convert to Flat Hierarchy Items
    return matchedCommunities
        .map(
          (c) => HierarchyItem(
            id: c.id,
            name: c.name,
            type: c.type ?? 'unknown',
            locationType: c.locationType ?? 'unknown',
            homeCountryCode: c.homeCountryCode,
            hostCountryCode: c.hostCountryCode,
            flag: c.flag,
            location: c.location,
            profileImage: c.profileImage != null
                ? const ChatProfileImage(
                    type: 'icon',
                    value: 'users',
                  ) // Placeholder conversion
                : null,
            totalMembers: c.totalMembers ?? c.memberCount,
            isExpandable: false,
            // Search results usually flat/leaf nodes or navigate to detail
            children: [],
          ),
        )
        .toList();
  }

  Future<void> _refreshRawCommunitiesCache(
    bool isGlobal,
    String? userHomeCode,
  ) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final rawCacheKey = isGlobal ? 'global' : 'home_${userHomeCode ?? 'US'}';
      if (isGlobal) {
        final snapshot = await firestore
            .collection('communities')
            .limit(100)
            .get();
        final list = snapshot.docs
            .map(
              (d) => _safeParseCommunity(
                d.id,
                d.data(),
                userHomeCode: userHomeCode,
              ),
            )
            .whereType<Community>()
            .toList();
        _rawCommunitiesCache[rawCacheKey] = (
          communities: list,
          fetchedAt: DateTime.now(),
        );
      } else if (userHomeCode != null) {
        final snapshot = await firestore
            .collection('communities')
            .where('homeCountryCode', isEqualTo: userHomeCode)
            .limit(200)
            .get();
        final list = snapshot.docs
            .map(
              (d) => _safeParseCommunity(
                d.id,
                d.data(),
                userHomeCode: userHomeCode,
              ),
            )
            .whereType<Community>()
            .toList();
        _rawCommunitiesCache[rawCacheKey] = (
          communities: list,
          fetchedAt: DateTime.now(),
        );
      }
    } catch (_) {}
  }

  // ===========================================================================
  // MODE 1: MY COMMUNITY (Default)
  // Logic: Show HOST communities where homeCountry == User.HomeCountry
  // Hierarchy: Global -> Continent (Host) -> Country (Host) -> State -> City
  // ===========================================================================
  Future<List<HierarchyItem>> _buildMyCommunityHierarchy(
    String userHomeCode,
  ) async {
    final firestore = FirebaseFirestore.instance;

    final uppercaseHomeCode = userHomeCode.trim().toUpperCase();
    final lowercaseHomeCode = userHomeCode.trim().toLowerCase();

    // [PERF] Run Query A (homeCountryCode) and Query B (global/continent) in parallel
    final results = await Future.wait([
      firestore
          .collection('communities')
          .where('homeCountryCode', isEqualTo: uppercaseHomeCode)
          .limit(200)
          .get(),
      firestore
          .collection('communities')
          .where('type', whereIn: ['global', 'continent'])
          .limit(20)
          .get(),
    ]);
    var homeCountrySnapshot = results[0];
    final globalSnapshot = results[1];

    if (homeCountrySnapshot.docs.isEmpty &&
        uppercaseHomeCode != lowercaseHomeCode) {
      homeCountrySnapshot = await firestore
          .collection('communities')
          .where('homeCountryCode', isEqualTo: lowercaseHomeCode)
          .limit(200)
          .get();
    }

    if (homeCountrySnapshot.docs.isEmpty) {
      homeCountrySnapshot = await firestore
          .collection('communities')
          .limit(100)
          .get();
    }

    final relevantCommunities = <Community>[];
    final commRepo = ref.read(communityRepositoryProvider);

    // Add User's Home-Related Communities (Host nodes)
    for (var doc in homeCountrySnapshot.docs) {
      final data = doc.data();
      final locType = data['locationType'] as String? ?? 'host';

      if (locType == 'host' || locType == 'past' || locType == 'home') {
        final community = _safeParseCommunity(
          doc.id,
          data,
          userHomeCode: userHomeCode,
        );
        if (community != null) {
          commRepo.cacheCommunity(community);
          relevantCommunities.add(community);
        }
      }
    }

    // Add Global & Continents
    for (var doc in globalSnapshot.docs) {
      if (!relevantCommunities.any((c) => c.id == doc.id)) {
        final community = _safeParseCommunity(
          doc.id,
          doc.data(),
          userHomeCode: userHomeCode,
        );
        if (community != null) {
          commRepo.cacheCommunity(community);
          relevantCommunities.add(community);
        }
      }
    }

    _rawCommunitiesCache['home_$userHomeCode'] = (
      communities: relevantCommunities,
      fetchedAt: DateTime.now(),
    );

    // 2. Separate by type and location relation
    final globalCommunity = relevantCommunities.firstWhere(
      (c) => c.type == 'global',
      orElse: () => Community(
        id: 'global_community',
        name: 'Global Community',
        type: 'global',
        homeCountryCode: '',
        hostCountryCode: '',
        memberCount: 0,
        images: [],
        isPrivate: false,
      ),
    );

    final homeContinents = relevantCommunities
        .where((c) => c.type == 'continent' && c.locationType == 'home')
        .toList();

    final myHomeCountries = relevantCommunities
        .where(
          (c) =>
              c.type == 'country' &&
              c.locationType == 'home' &&
              c.homeCountryCode == userHomeCode,
        )
        .toList();

    final hostCountries = relevantCommunities
        .where(
          (c) =>
              c.type == 'country' &&
              (c.locationType == 'host' || c.locationType == 'past'),
        )
        .toList();

    final hostStates = relevantCommunities
        .where(
          (c) =>
              c.type == 'state' &&
              (c.locationType == 'host' || c.locationType == 'past'),
        )
        .toList();
    final hostCities = relevantCommunities
        .where(
          (c) =>
              c.type == 'city' &&
              (c.locationType == 'host' || c.locationType == 'past'),
        )
        .toList();

    final hostContinentCommunities = relevantCommunities
        .where(
          (c) =>
              c.type == 'continent' &&
              (c.locationType == 'host' || c.locationType == 'past') &&
              c.homeCountryCode == userHomeCode,
        )
        .toList();

    // 3. Build Host Tree (Countries -> States -> Cities)
    final flatHostCountryItems = _buildHostCountryTree(
      hostCountries,
      hostStates,
      hostCities,
    );

    // 4. Group Host Countries by Continent (Enum-based)
    final hostContinentMap = <country_data.Continent, List<HierarchyItem>>{};
    final processedHostCountryIds = <String>{};

    for (var hostItem in flatHostCountryItems) {
      final hCode = hostItem.hostCountryCode;
      if (hCode != null) {
        final cont = country_data.getContinentByCountryCode(hCode);
        if (cont != null) {
          hostContinentMap.putIfAbsent(cont, () => []).add(hostItem);
          processedHostCountryIds.add(hostItem.id);
        }
      }
    }

    final hostContinentItems = <HierarchyItem>[];
    hostContinentMap.forEach((continent, countries) {
      countries.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      final totalMembers = countries.fold(0, (acc, c) => acc + c.totalMembers);

      final dbHostContinent = hostContinentCommunities
          .cast<Community?>()
          .firstWhere(
            (c) =>
                _normalizeContinentName(c?.name ?? '') ==
                _normalizeContinentName(continent.displayName),
            orElse: () => null,
          );

      final continentSlug = continent.name.replaceAllMapped(
        RegExp(r'[A-Z]'),
        (m) => '-${m[0]!.toLowerCase()}',
      );
      final continentId = dbHostContinent?.id ?? 'my_host_cont_$continentSlug';

      hostContinentItems.add(
        HierarchyItem(
          id: continentId,
          name: CommunityChatUtils.generateCommunityNameFromParts(
            name: continent.displayName,
            locationType: 'host',
            id: 'chat_$continentId',
          ),
          type: 'continent',
          locationType: 'host',
          homeCountryCode: userHomeCode,
          flag: null,
          profileImage: null,
          totalMembers: totalMembers,
          isExpandable: countries.isNotEmpty,
          initiallyExpanded: true,
          children: countries,
        ),
      );
    });

    final orphanHostCountries = flatHostCountryItems
        .where((c) => !processedHostCountryIds.contains(c.id))
        .toList();

    final finalHostChildren = [...hostContinentItems, ...orphanHostCountries];
    finalHostChildren.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

    // 5. Build Home Country items containing the Host Continent hierarchy
    final homeCountryItems = <HierarchyItem>[];
    for (var homeCountry in myHomeCountries) {
      final hostMembers = finalHostChildren.fold(
        0,
        (acc, c) => acc + c.totalMembers,
      );

      homeCountryItems.add(
        HierarchyItem(
          id: homeCountry.id,
          name: CommunityChatUtils.generateCommunityNameFromParts(
            name: homeCountry.name,
            locationType: 'home',
            id: homeCountry.id,
          ),
          type: 'country',
          locationType: 'home',
          homeCountryCode: homeCountry.homeCountryCode,
          flag: homeCountry.flag,
          profileImage: homeCountry.profileImage != null
              ? ChatProfileImage(
                  type: 'network',
                  value: homeCountry.profileImage!,
                )
              : null,
          location: homeCountry.location,
          totalMembers: hostMembers,
          isExpandable: finalHostChildren.isNotEmpty,
          initiallyExpanded: true,
          children: finalHostChildren,
        ),
      );
    }

    // 6. Group Home Countries under Home Continents
    if (homeCountryItems.isEmpty && finalHostChildren.isNotEmpty) {
      final countryName = getCountryName(userHomeCode);
      final syntheticId = 'synthetic_home_$userHomeCode';

      homeCountryItems.add(
        HierarchyItem(
          id: syntheticId,
          name: CommunityChatUtils.generateCommunityNameFromParts(
            name: countryName,
            locationType: 'home',
            id: syntheticId,
          ),
          type: 'country',
          locationType: 'home',
          homeCountryCode: userHomeCode,
          flag: country_data.getCountryByCode(userHomeCode)?.flag ?? '',
          totalMembers: finalHostChildren.fold(
            0,
            (acc, c) => acc + c.totalMembers,
          ),
          isExpandable: true,
          initiallyExpanded: true,
          children: finalHostChildren,
        ),
      );
    }

    final continentHierarchy = <HierarchyItem>[];
    final processedHomeCountryIds = <String>{};

    for (var continent in homeContinents) {
      final continentDisplayName = _normalizeContinentName(continent.name);

      final continentCountries = <HierarchyItem>[];
      for (var countryItem in homeCountryItems) {
        final cCode = countryItem.homeCountryCode;
        if (cCode != null) {
          final cont = country_data.getContinentByCountryCode(cCode);
          if (cont != null &&
              _normalizeContinentName(cont.displayName) ==
                  continentDisplayName) {
            continentCountries.add(countryItem);
            processedHomeCountryIds.add(countryItem.id);
          }
        }
      }

      if (continentCountries.isNotEmpty) {
        continentCountries.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        final totalMembers = continentCountries.fold(
          0,
          (acc, c) => acc + c.totalMembers,
        );

        continentHierarchy.add(
          HierarchyItem(
            id: continent.id,
            name: CommunityChatUtils.generateCommunityNameFromParts(
              name: continent.name,
              locationType: 'home',
              id: continent.id,
            ),
            totalMembers: totalMembers,
            type: 'continent',
            locationType: 'home',
            homeCountryCode: continent.homeCountryCode,
            flag: null,
            profileImage: null,
            isExpandable: true,
            initiallyExpanded: true,
            children: continentCountries,
          ),
        );
      }
    }

    final orphanHomeCountries = homeCountryItems
        .where((c) => !processedHomeCountryIds.contains(c.id))
        .toList();

    // 7. Stats Calculation
    final hostCountrySet = <String>{};
    int totalHostCities = 0;

    for (var hostItem in flatHostCountryItems) {
      if (hostItem.hostCountryCode != null) {
        hostCountrySet.add(hostItem.hostCountryCode!);
      }

      void countCities(HierarchyItem item) {
        if (item.type == 'city') totalHostCities++;
        for (var child in item.children) {
          countCities(child);
        }
      }

      for (var child in hostItem.children) {
        countCities(child);
      }
    }

    int totalMembers = finalHostChildren.fold(
      0,
      (acc, c) => acc + c.totalMembers,
    );

    orphanHomeCountries.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

    final hierarchyChildren = [...continentHierarchy, ...orphanHomeCountries];

    final isGlobalUnlocked = ref.read(isGlobalUnlockedSyncProvider);
    if (!isGlobalUnlocked) {
      return hierarchyChildren;
    }

    return [
      HierarchyItem(
        id: globalCommunity.id,
        name: CommunityChatUtils.generateCommunityNameFromParts(
          name: 'Global Community',
          locationType: 'global',
          id: globalCommunity.id,
        ),
        type: 'global',
        locationType: 'global',
        homeCountryCode: userHomeCode,
        totalMembers: totalMembers,
        isExpandable: hierarchyChildren.isNotEmpty,
        initiallyExpanded: true,
        children: hierarchyChildren,
        globalStats: GlobalStats(
          totalMembers: totalMembers,
          continents: hostContinentItems.length,
          countries: hostCountrySet.length,
          cities: totalHostCities,
        ),
      ),
    ];
  }

  // Helper to build Host Country -> State -> City tree
  List<HierarchyItem> _buildHostCountryTree(
    List<Community> countries,
    List<Community> states,
    List<Community> cities,
  ) {
    final items = <HierarchyItem>[];
    for (var country in countries) {
      final countryCode = country.location?['countryCode'];
      final countryLocationType = country.locationType ?? 'host';

      final myStates = states
          .where(
            (s) =>
                s.location?['countryCode'] == countryCode &&
                (s.locationType ?? 'host') == countryLocationType,
          )
          .toList();

      final myCities = cities
          .where(
            (c) =>
                c.location?['countryCode'] == countryCode &&
                (c.locationType ?? 'host') == countryLocationType,
          )
          .toList();

      myStates.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      myCities.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

      final itemChildren = <HierarchyItem>[];
      int countryTotalMembers = country.totalMembers ?? country.memberCount;

      for (var state in myStates) {
        final stateName = state.location?['state'];

        final stateCities = myCities
            .where(
              (c) =>
                  c.location?['state'] == stateName &&
                  (c.locationType ?? 'host') == countryLocationType,
            )
            .toList();

        stateCities.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        int stateTotalMembers = state.totalMembers ?? state.memberCount;

        if (stateTotalMembers == 0) {
          stateTotalMembers = stateCities.fold(
            0,
            (acc, c) => acc + (c.totalMembers ?? c.memberCount),
          );
        }

        itemChildren.add(
          HierarchyItem(
            id: state.id,
            name: CommunityChatUtils.generateCommunityNameFromParts(
              name: state.name,
              locationType: state.locationType ?? 'host',
              id: state.id,
            ),
            type: 'state',
            locationType: state.locationType ?? 'host',
            homeCountryCode: state.homeCountryCode,
            hostCountryCode: state.location?['countryCode'],
            flag: state.flag,
            profileImage: state.profileImage != null
                ? ChatProfileImage(type: 'network', value: state.profileImage!)
                : null,
            location: state.location,
            totalMembers: stateTotalMembers,
            isExpandable: stateCities.isNotEmpty,
            children: stateCities
                .map(
                  (city) => HierarchyItem(
                    id: city.id,
                    name: CommunityChatUtils.generateCommunityNameFromParts(
                      name: city.name,
                      locationType: city.locationType ?? 'host',
                      id: city.id,
                    ),
                    type: 'city',
                    locationType: city.locationType ?? 'host',
                    homeCountryCode: city.homeCountryCode,
                    hostCountryCode: city.location?['countryCode'],
                    flag: city.flag,
                    profileImage: city.profileImage != null
                        ? ChatProfileImage(
                            type: 'network',
                            value: city.profileImage!,
                          )
                        : null,
                    totalMembers: city.totalMembers ?? city.memberCount,
                  ),
                )
                .toList(),
          ),
        );
      }

      // Direct Cities (orphans)
      for (var city in myCities) {
        final cityState = city.location?['state'];

        final belongsToState =
            cityState != null &&
            myStates.any((s) => s.location?['state'] == cityState);
        if (!belongsToState) {
          itemChildren.add(
            HierarchyItem(
              id: city.id,
              name: CommunityChatUtils.generateCommunityNameFromParts(
                name: city.name,
                locationType: city.locationType ?? 'host',
                id: city.id,
              ),
              type: 'city',
              locationType: city.locationType ?? 'host',
              homeCountryCode: city.homeCountryCode,
              hostCountryCode: city.location?['countryCode'],
              totalMembers: city.totalMembers ?? city.memberCount,
            ),
          );
        }
      }

      itemChildren.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

      if (countryTotalMembers == 0) {
        countryTotalMembers = itemChildren.fold(
          0,
          (acc, child) => acc + child.totalMembers,
        );
      }
      items.add(
        HierarchyItem(
          id: country.id,
          name: CommunityChatUtils.generateCommunityNameFromParts(
            name: country.name,
            locationType: country.locationType ?? 'host',
            id: country.id,
          ),
          type: 'country',
          locationType: country.locationType ?? 'host',
          homeCountryCode: country.homeCountryCode,
          hostCountryCode: countryCode,
          flag: country.flag,
          profileImage: country.profileImage != null
              ? ChatProfileImage(type: 'network', value: country.profileImage!)
              : null,
          location: country.location,
          totalMembers: countryTotalMembers,
          isExpandable: true,
          children: itemChildren,
        ),
      );
    }

    return items;
  }

  // ===========================================================================
  // MODE 2: GLOBAL (Toggle)
  // Logic: Show ALL communities, grouped by HOME Location
  // Hierarchy: Global -> Continent (Home) -> Country (Home) -> Country (Host) -> State -> City
  // ===========================================================================
  Future<List<HierarchyItem>> _buildGlobalHierarchy(String userHomeCode) async {
    final firestore = FirebaseFirestore.instance;
    final commRepo = ref.read(communityRepositoryProvider);

    // Fetch all communities
    final snapshot = await firestore.collection('communities').limit(500).get();

    // Parse
    final allCommunities = snapshot.docs
        .map((d) {
          final c = _safeParseCommunity(
            d.id,
            d.data(),
            userHomeCode: userHomeCode,
          );
          if (c != null) commRepo.cacheCommunity(c);
          return c;
        })
        .whereType<Community>()
        .toList();

    _rawCommunitiesCache['global'] = (
      communities: allCommunities,
      fetchedAt: DateTime.now(),
    );

    final homeCommunities = allCommunities
        .where((c) => c.locationType == 'home')
        .toList();

    final hostCommunities = allCommunities
        .where((c) => c.locationType == 'host')
        .toList();

    final globalCommunity = allCommunities.firstWhere(
      (c) => c.type == 'global',
      orElse: () => Community(
        id: 'global_community',
        name: 'Global Community',
        type: 'global',
        homeCountryCode: '',
        hostCountryCode: '',
        memberCount: 0,
        images: [],
        isPrivate: false,
      ),
    );

    final homeContinents = homeCommunities
        .where((c) => c.type == 'continent')
        .toList();

    final homeCountries = homeCommunities
        .where((c) => c.type == 'country')
        .toList();

    final hostCountries = hostCommunities
        .where((c) => c.type == 'country')
        .toList();

    final hostStates = hostCommunities.where((c) => c.type == 'state').toList();

    final hostCities = hostCommunities.where((c) => c.type == 'city').toList();

    homeContinents.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    homeCountries.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

    final homeCountryItems = <HierarchyItem>[];
    for (var homeCountry in homeCountries) {
      final hCode = homeCountry.homeCountryCode;
      if (hCode == null) continue;

      final myHostCountries = hostCountries
          .where((c) => c.homeCountryCode == hCode)
          .toList();
      myHostCountries.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

      final processedHostIdsInHome = <String>{};

      final flatHostCountryItems = <HierarchyItem>[];
      for (var hostCountry in myHostCountries) {
        final hostCountryCode = hostCountry.location?['countryCode'];

        final myHostStates = hostStates
            .where(
              (s) =>
                  s.homeCountryCode == hCode &&
                  s.location?['countryCode'] == hostCountryCode,
            )
            .toList();

        final myHostCities = hostCities
            .where(
              (c) =>
                  c.homeCountryCode == hCode &&
                  c.location?['countryCode'] == hostCountryCode,
            )
            .toList();

        final hostStateChildren = <HierarchyItem>[];

        for (var hostState in myHostStates) {
          final stateName = hostState.location?['state'];

          final stateCities = myHostCities
              .where((c) => c.location?['state'] == stateName)
              .toList();

          int stateTotal = (hostState.totalMembers ?? hostState.memberCount);
          if (stateTotal == 0) {
            stateTotal = stateCities.fold(
              0,
              (acc, c) => acc + (c.totalMembers ?? c.memberCount),
            );
          }
          hostStateChildren.add(
            HierarchyItem(
              id: hostState.id,
              name: CommunityChatUtils.generateCommunityNameFromParts(
                name: hostState.name,
                locationType: 'host',
                id: hostState.id,
              ),
              type: 'state',
              locationType: 'host',
              homeCountryCode: hostState.homeCountryCode,
              hostCountryCode: hostCountryCode,
              location: hostState.location,
              profileImage: hostState.profileImage != null
                  ? const ChatProfileImage(type: 'icon', value: 'users')
                  : null,
              totalMembers: stateTotal,
              isExpandable: stateCities.isNotEmpty,
              children: stateCities
                  .map(
                    (city) => HierarchyItem(
                      id: city.id,
                      name: CommunityChatUtils.generateCommunityNameFromParts(
                        name: city.name,
                        locationType: 'host',
                        id: city.id,
                      ),
                      type: 'city',
                      locationType: 'host',
                      homeCountryCode: city.homeCountryCode,
                      hostCountryCode: hostCountryCode,
                      location: city.location,
                      profileImage: city.profileImage != null
                          ? const ChatProfileImage(type: 'icon', value: 'users')
                          : null,
                      totalMembers: city.totalMembers ?? city.memberCount,
                    ),
                  )
                  .toList(),
            ),
          );
        }

        for (var city in myHostCities) {
          final cityState = city.location?['state'];

          final belongsToState =
              cityState != null &&
              myHostStates.any((s) => s.location?['state'] == cityState);
          if (!belongsToState) {
            hostStateChildren.add(
              HierarchyItem(
                id: city.id,
                name: CommunityChatUtils.generateCommunityNameFromParts(
                  name: city.name,
                  locationType: 'host',
                  id: city.id,
                ),
                type: 'city',
                locationType: 'host',
                homeCountryCode: city.homeCountryCode,
                hostCountryCode: hostCountryCode,
                location: city.location,
                profileImage: city.profileImage != null
                    ? const ChatProfileImage(type: 'icon', value: 'users')
                    : null,
                totalMembers: city.totalMembers ?? city.memberCount,
              ),
            );
          }
        }

        int hostCountryTotal =
            hostCountry.totalMembers ?? hostCountry.memberCount;
        if (hostCountryTotal == 0) {
          hostCountryTotal = hostStateChildren.fold(
            0,
            (acc, child) => acc + child.totalMembers,
          );
        }
        flatHostCountryItems.add(
          HierarchyItem(
            id: hostCountry.id,
            name: CommunityChatUtils.generateCommunityNameFromParts(
              name: hostCountry.name,
              locationType: 'host',
              id: hostCountry.id,
            ),
            type: 'country',
            locationType: 'host',
            homeCountryCode: hostCountry.homeCountryCode,
            hostCountryCode: hostCountryCode,
            flag: hostCountry.flag,
            location: hostCountry.location,
            profileImage: hostCountry.profileImage != null
                ? const ChatProfileImage(type: 'icon', value: 'users')
                : null,
            totalMembers: hostCountryTotal,
            isExpandable: true,
            children: hostStateChildren,
          ),
        );
        processedHostIdsInHome.add(hostCountry.id);
      }

      // 2. Group Host Countries by Continent
      final hostContinentChildren = <HierarchyItem>[];
      final processedCountryIds = <String>{};
      final continentMap = <country_data.Continent, List<HierarchyItem>>{};

      for (var countryItem in flatHostCountryItems) {
        final cCode = countryItem.hostCountryCode;
        if (cCode != null) {
          final cont = country_data.getContinentByCountryCode(cCode);
          if (cont != null) {
            continentMap.putIfAbsent(cont, () => []).add(countryItem);
            processedCountryIds.add(countryItem.id);
          }
        }
      }

      final myHostContinentCommunities = hostCommunities
          .where((c) => c.type == 'continent' && c.homeCountryCode == hCode)
          .toList();

      continentMap.forEach((continent, countries) {
        countries.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );

        final totalMembers = countries.fold(
          0,
          (acc, c) => acc + c.totalMembers,
        );

        final dbHostContinent = myHostContinentCommunities
            .cast<Community?>()
            .firstWhere(
              (c) =>
                  _normalizeContinentName(c?.name ?? '') ==
                  _normalizeContinentName(continent.displayName),
              orElse: () => null,
            );

        final continentSlug = continent.name.replaceAllMapped(
          RegExp(r'[A-Z]'),
          (Match m) => '-${m[0]!.toLowerCase()}',
        );
        final continentId =
            dbHostContinent?.id ?? '${homeCountry.id}_host_cont_$continentSlug';

        hostContinentChildren.add(
          HierarchyItem(
            id: continentId,
            name: CommunityChatUtils.generateCommunityNameFromParts(
              name: continent.displayName,
              locationType: 'host',
              id: 'chat_$continentId',
            ),
            type: 'continent',
            locationType: 'host',
            homeCountryCode: hCode,
            hostCountryCode: null,
            totalMembers: totalMembers,
            isExpandable: countries.isNotEmpty,
            children: countries,
          ),
        );
      });

      final orphanHostCountries = flatHostCountryItems
          .where((c) => !processedCountryIds.contains(c.id))
          .toList();

      final finalHostChildren = [
        ...hostContinentChildren,
        ...orphanHostCountries,
      ];
      finalHostChildren.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

      final hasHost = finalHostChildren.any((c) => c.totalMembers > 0);
      final isMyHome = hCode == userHomeCode;
      final hasDirect =
          (homeCountry.totalMembers ?? homeCountry.memberCount) > 0;

      if (hasDirect || hasHost || isMyHome) {
        int homeTotal = homeCountry.totalMembers ?? homeCountry.memberCount;

        final hostTotal = flatHostCountryItems.fold(
          0,
          (acc, child) => acc + child.totalMembers,
        );

        if (homeTotal < hostTotal) homeTotal = hostTotal;

        homeCountryItems.add(
          HierarchyItem(
            id: homeCountry.id,
            name: CommunityChatUtils.generateCommunityNameFromParts(
              name: homeCountry.name,
              locationType: 'home',
              id: homeCountry.id,
            ),
            type: 'country',
            locationType: 'home',
            homeCountryCode: hCode,
            location: homeCountry.location,
            totalMembers: homeTotal,
            flag: homeCountry.flag,
            profileImage: homeCountry.profileImage != null
                ? ChatProfileImage(
                    type: 'network',
                    value: homeCountry.profileImage!,
                  )
                : null,
            isExpandable: true,
            initiallyExpanded: true,
            children: finalHostChildren,
          ),
        );
      }
    }

    final homeCountryCodes = homeCountries
        .map((c) => c.homeCountryCode)
        .where((c) => c != null)
        .toSet();

    final orphanedHostCountries = hostCountries
        .where((c) => !homeCountryCodes.contains(c.homeCountryCode))
        .toList();

    if (orphanedHostCountries.isNotEmpty) {
      final orphansByHomeCode = <String, List<Community>>{};
      for (var orphan in orphanedHostCountries) {
        final hCode = orphan.homeCountryCode;
        if (hCode != null) {
          orphansByHomeCode.putIfAbsent(hCode, () => []).add(orphan);
        }
      }

      orphansByHomeCode.forEach((hCode, myOrphans) {
        final countryName = getCountryName(hCode);
        final syntheticId = 'synthetic_global_home_$hCode';

        final myHostStates = hostStates
            .where((s) => s.homeCountryCode == hCode)
            .toList();
        final myHostCities = hostCities
            .where((c) => c.homeCountryCode == hCode)
            .toList();

        final flatHostCountryItems = _buildHostCountryTree(
          myOrphans,
          myHostStates,
          myHostCities,
        );

        final totalMembers = flatHostCountryItems.fold(
          0,
          (acc, c) => acc + c.totalMembers,
        );

        homeCountryItems.add(
          HierarchyItem(
            id: syntheticId,
            name: CommunityChatUtils.generateCommunityNameFromParts(
              name: countryName,
              locationType: 'home',
              id: syntheticId,
            ),
            type: 'country',
            locationType: 'home',
            homeCountryCode: hCode,
            flag: country_data.getCountryByCode(hCode)?.flag,
            totalMembers: totalMembers,
            isExpandable: true,
            initiallyExpanded: true,
            children: flatHostCountryItems,
          ),
        );
      });

      homeCountryItems.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    }

    final continentMap = <country_data.Continent, List<HierarchyItem>>{};
    final processedHomeCountryIds = <String>{};

    for (var countryItem in homeCountryItems) {
      final cCode = countryItem.homeCountryCode;
      if (cCode != null) {
        final cont = country_data.getContinentByCountryCode(cCode);
        if (cont != null) {
          continentMap.putIfAbsent(cont, () => []).add(countryItem);
          processedHomeCountryIds.add(countryItem.id);
        }
      }
    }

    final continentHierarchy = <HierarchyItem>[];
    continentMap.forEach((continent, countries) {
      countries.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

      final childrenTotal = countries.fold(
        0,
        (acc, country) => acc + country.totalMembers,
      );

      final dbContinent = homeContinents.cast<Community?>().firstWhere(
        (c) =>
            _normalizeContinentName(c?.name ?? '') ==
            _normalizeContinentName(continent.displayName),
        orElse: () => null,
      );

      final continentName = CommunityChatUtils.generateCommunityNameFromParts(
        name: dbContinent?.name ?? continent.displayName,
        locationType: 'home',
        id: dbContinent?.id ?? 'synthetic_cont_${continent.name.toLowerCase()}',
      );

      continentHierarchy.add(
        HierarchyItem(
          id:
              dbContinent?.id ??
              'synthetic_cont_${continent.name.toLowerCase()}',
          name: continentName,
          type: 'continent',
          locationType: 'home',
          homeCountryCode: dbContinent?.homeCountryCode,
          location: dbContinent?.location,
          profileImage: dbContinent?.profileImage != null
              ? ChatProfileImage(
                  type: 'network',
                  value: dbContinent!.profileImage!,
                )
              : null,
          flag: dbContinent?.flag,
          totalMembers: childrenTotal,
          isExpandable: true,
          initiallyExpanded: true,
          children: countries,
        ),
      );
    });

    continentHierarchy.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

    final orphanCountries = homeCountryItems
        .where((country) => !processedHomeCountryIds.contains(country.id))
        .toList();
    orphanCountries.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

    final hierarchy = <HierarchyItem>[];
    final globalChildren = [...continentHierarchy, ...orphanCountries];

    final isGlobalUnlocked = ref.read(isGlobalUnlockedSyncProvider);
    if (!isGlobalUnlocked) {
      return globalChildren;
    }

    if (globalCommunity.type == 'global') {
      final childrenTotalMembers = globalChildren.fold(
        0,
        (acc, child) => acc + child.totalMembers,
      );
      int totalGlobalMembers = globalCommunity.totalMembers ?? 0;
      if (totalGlobalMembers < childrenTotalMembers) {
        totalGlobalMembers = childrenTotalMembers;
      }

      final hostCountrySet = <String>{};
      int totalHostCities = 0;

      for (var homeCountry in homeCountryItems) {
        void processHostCountry(HierarchyItem hostCountry) {
          if (hostCountry.hostCountryCode != null) {
            hostCountrySet.add(hostCountry.hostCountryCode!);
          }

          for (var child in hostCountry.children) {
            if (child.type == 'city') {
              totalHostCities++;
            } else if (child.type == 'state') {
              totalHostCities += child.children.length;
            }
          }
        }

        for (var child in homeCountry.children) {
          if (child.type == 'continent') {
            for (var hostCountry in child.children) {
              processHostCountry(hostCountry);
            }
          } else {
            processHostCountry(child);
          }
        }
      }

      hierarchy.add(
        HierarchyItem(
          id: globalCommunity.id,
          name: CommunityChatUtils.generateCommunityNameFromParts(
            name: 'Global Community',
            locationType: 'global',
            id: globalCommunity.id,
          ),
          type: 'global',
          locationType: 'global',
          homeCountryCode: globalCommunity.homeCountryCode,
          location: globalCommunity.location,
          totalMembers: totalGlobalMembers,
          isExpandable: false,
          children: globalChildren,
          globalStats: GlobalStats(
            totalMembers: totalGlobalMembers,
            continents: continentHierarchy.length,
            countries: hostCountrySet.length,
            cities: totalHostCities,
          ),
        ),
      );
    } else {
      hierarchy.addAll(globalChildren);
    }

    return hierarchy;
  }

  /// Normalizes continent names for comparison, handling both noun and
  /// adjective forms and any community/treasury suffixes via [CommunityChatUtils].
  String _normalizeContinentName(String name) {
    return CommunityChatUtils.normalizeContinentName(name);
  }

  Community? _safeParseCommunity(
    String id,
    Map<String, dynamic> data, {
    String? userHomeCode,
  }) {
    try {
      final type = data['type'] as String?;
      final hCode = data['homeCountryCode'] as String?;
      final hostCode = data['hostCountryCode'] as String?;

      String defLocType = 'host';
      if (type == 'global' || type == 'continent') {
        defLocType = 'home';
      } else if (userHomeCode != null &&
          hCode == userHomeCode &&
          (hostCode == null || hostCode.isEmpty)) {
        defLocType = 'home';
      }

      return Community(
        id: id,
        name: data['name'] as String? ?? 'Unknown Community',
        homeCountryCode: hCode,
        hostCountryCode: hostCode,
        type: type,
        locationType: data['locationType'] as String? ?? defLocType,
        images:
            (data['images'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        memberCount: (data['memberCount'] as num?)?.toInt() ?? 0,
        totalMembers: (data['totalMembers'] as num?)?.toInt(),
        isPrivate: data['isPrivate'] as bool? ?? false,
        location: data['location'] as Map<String, dynamic>?,
        profileImage:
            (data['profileImage'] as String?)?.isEmpty == true ||
                data['profileImage'] == 'users'
            ? null
            : data['profileImage'] as String?,
        chatId: data['chatId'] as String?,
        flag: (data['flag'] as String?)?.isEmpty == true
            ? null
            : data['flag'] as String?,
      );
    } catch (e) {
      return null;
    }
  }
}
