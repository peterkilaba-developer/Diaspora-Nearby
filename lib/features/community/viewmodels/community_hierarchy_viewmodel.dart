import 'package:diaspora_nearby/features/chat/utils/community_chat_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diaspora_nearby/models/community_data.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/community/models/hierarchy_item.dart';
import 'package:diaspora_nearby/data/countries.dart' as country_data;
import 'package:diaspora_nearby/providers/view_mode_provider.dart';
import 'package:diaspora_nearby/providers/global_search_provider.dart';
import 'package:diaspora_nearby/models/chat.dart';

// Utils 
String getCountryName(String? code) {
  if (code == null) return '';
  final country = country_data.getCountryByCode(code);
  return country?.name ?? code;
}

/// Provider for the hierarchy logic 
final communityHierarchyProvider = AsyncNotifierProvider<CommunityHierarchyViewModel, List<HierarchyItem>>(() {
  return CommunityHierarchyViewModel();
});

class CommunityHierarchyViewModel extends AsyncNotifier<List<HierarchyItem>> {
  @override
  Future<List<HierarchyItem>> build() async {
    print('CommunityHierarchyViewModel: Build started');
    final mode = ref.watch(communitiesViewModeProvider);
    final user = ref.read(authStateProvider).value;
    final searchQuery = ref.watch(globalSearchProvider);

    // Watch search      
    if (user == null) {
      print('CommunityHierarchyViewModel: User is null');
      return [];
    }

    // Fetch user profile for Home Country Code     
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userData = userDoc.data();
      final userHomeCountryCode = userData != null ? userData['homeCountryCode'] as String? : null;
      print('CommunityHierarchyViewModel: User home code: $userHomeCountryCode');

      // Search Interception     
      if (searchQuery.isNotEmpty && searchQuery.length >= 3) {
        return _performSearch(searchQuery, userHomeCountryCode, mode == ViewMode.global);
      }

      // Normal View Logic     
      if (mode == ViewMode.global) {
        return _buildGlobalHierarchy(userHomeCountryCode ?? 'US');
        // Fallback if null for global build     
      } else {
        if (userHomeCountryCode == null) {
          print('CommunityHierarchyViewModel: Home code null, returning empty');
          return [];
        }
        return _buildMyCommunityHierarchy(userHomeCountryCode);
      }
    } catch (e, st) {
      print('CommunityHierarchyViewModel Error: $e\n$st');
      throw e;
    }
  }

  // ===========================================================================   
  // SEARCH LOGIC   
  // ===========================================================================   
  Future<List<HierarchyItem>> _performSearch(String query, String? userHomeCode, bool isGlobal) async {
    final firestore = FirebaseFirestore.instance;
    final normalizedQuery = query.toLowerCase().trim();
    List<Community> communities = [];
    
    if (isGlobal) {
      // Global View: Search ALL communities       
      final snapshot = await firestore.collection('communities').get();
      communities = snapshot.docs.map((d) => Community.fromJson({...d.data(), 'id': d.id})).toList();
    } else {
      // Home View: Search home and host communities matching home country code       
      if (userHomeCode == null) return [];

      final snapshot = await firestore.collection('communities')
          .where('homeCountryCode', isEqualTo: userHomeCode)
          .get();
      communities = snapshot.docs.map((d) => Community.fromJson({...d.data(), 'id': d.id})).toList();
    }

    // Filter by name match     
    final matchedCommunities = communities.where((c) {
      final name = c.name.toLowerCase();
      // "Match community name that match at least three characters" AND not empty       
      return name.contains(normalizedQuery) && (c.totalMembers ?? c.memberCount) > 0;
    }).toList();

    // Sort Results     
    matchedCommunities.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // Convert to Flat Hierarchy Items     
    return matchedCommunities.map((c) => HierarchyItem(
        id: c.id,
        name: c.name,
        type: c.type ?? 'unknown',
        locationType: c.locationType ?? 'unknown',
        homeCountryCode: c.homeCountryCode,
        hostCountryCode: c.hostCountryCode,
        flag: c.flag,
        location: c.location,
        profileImage: c.profileImage != null 
            ? ChatProfileImage(type: 'icon', value: 'users') // Placeholder conversion
            : null,
        totalMembers: c.totalMembers ?? c.memberCount,
        isExpandable: false,
        // Search results usually flat/leaf nodes or navigate to detail         
        children: []
    )).toList();
  }

  // ===========================================================================   
  // MODE 1: MY COMMUNITY (Default)   
  // Logic: Show HOST communities where homeCountry == User.HomeCountry   
  // Hierarchy: Global -> Continent (Host) -> Country (Host) -> State -> City   
  // ===========================================================================   
  // ===========================================================================   
  // MODE 1: MY COMMUNITY (Default)   
  // Logic: Show HOST communities where homeCountry == User.HomeCountry   
  // Hierarchy: Global -> Continent (Host) -> Country (Host) -> State -> City   
  // ===========================================================================   
  Future<List<HierarchyItem>> _buildMyCommunityHierarchy(String userHomeCode) async {
    print('CommunityHierarchyViewModel: Building hierarchy for $userHomeCode');
    final firestore = FirebaseFirestore.instance;

    // 1. Fetch relevant communities       
    // REVERT: Fetch ALL communities for this home code, then filter in memory.
    // This avoids "Missing Index" errors and handles missing/null locationType fields gracefully.
    print('CommunityHierarchyViewModel: Fetching related communities...');
    
    // Query A: All communities belonging to this Home Country
    final homeCountrySnapshot = await firestore.collection('communities')
        .where('homeCountryCode', isEqualTo: userHomeCode)
        .get();
        
    // Query B: Global/Home Continent structure (Pre-defined nodes)
    // We fetch strict types here as these are usually static/admin defined
    final globalSnapshot = await firestore.collection('communities')
        .where('type', isEqualTo: 'global')
        .get();

    final continentsSnapshot = await firestore.collection('communities')
        .where('type', isEqualTo: 'continent')
        .where('locationType', isEqualTo: 'home')
        .get();

    // 2. Merge & In-Memory Filter
    // We want: 
    // - Host Communities (locationType == 'host') matching homeCode
    // - The Global Community
    // - Home Continents (for grouping)
    
    final relevantCommunities = <Community>[];
    
    // Add User's Home-Related Communities (Host nodes)
    for (var doc in homeCountrySnapshot.docs) {
       final data = doc.data();
       final locType = data['locationType'] as String? ?? 'host'; 
       
       if (locType == 'host') {
          final community = _safeParseCommunity(doc.id, data);
          if (community != null) relevantCommunities.add(community);
       }
    }

    // Add Global & Continents
    for (var doc in globalSnapshot.docs) {
      if (!relevantCommunities.any((c) => c.id == doc.id)) {
        final community = _safeParseCommunity(doc.id, doc.data());
        if (community != null) relevantCommunities.add(community);
      }
    }
    for (var doc in continentsSnapshot.docs) {
      if (!relevantCommunities.any((c) => c.id == doc.id)) {
        final community = _safeParseCommunity(doc.id, doc.data());
        if (community != null) relevantCommunities.add(community);
      }
    }
    
    print('CommunityHierarchyViewModel: Filtered to ${relevantCommunities.length} relevant items');



    // Hierarchy Building       
    final hierarchy = <HierarchyItem>[];

    final globalCommunity = relevantCommunities.firstWhere(
        (c) => c.type == 'global',
        orElse: () => Community(
            id: 'dummy', 
            name: '', 
            type: 'dummy',
            description: '',
            homeCountryCode: '',
            hostCountryCode: '',
            memberCount: 0,
            images: [],
            isPrivate: false,
        )
    );

    // Filter lists - NOTE: Continents are HOME type (geographic), not HOST       
    // However, we need ALL continents to group Host Countries correctly (e.g. need North America to group USA)       
    final continents = relevantCommunities.where((c) => c.type == 'continent').toList();

    final countries = relevantCommunities.where((c) => c.type == 'country' && c.locationType == 'host').toList();

    final states = relevantCommunities.where((c) => c.type == 'state' && c.locationType == 'host').toList();

    final cities = relevantCommunities.where((c) => c.type == 'city' && c.locationType == 'host').toList();

    // (B) Build Continent → Country → State → City Hierarchy       
    // Sort lists       
    continents.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    countries.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // Build country items with state/city children       
    final countryItems = _buildHostCountryTree(countries, states, cities);

    // Group countries by continent       
    final continentHierarchy = <HierarchyItem>[];

    // Helper to normalize continent names for comparison       
    String normalizeName(String name) => name.toLowerCase().replaceAll(' community', '').trim();
    
    for (var continent in continents) {
      // Ensure Noun using ChatUtils logic            
      final continentName = CommunityChatUtils.generateCommunityNameFromParts(
          name: continent.name,
          locationType: 'host',
          // Force Host Noun form for My Diaspora view              
          id: continent.id
      );

      final continentIdentifier = normalizeName(continent.name);

      // Find countries belonging to this continent            
      final continentCountries = <HierarchyItem>[];
      for (var countryItem in countryItems) {
        final hostCode = countryItem.hostCountryCode;

        // This is the HOST country code                
        final countryContinent = hostCode != null
            ? (country_data.continentDisplayNames[country_data.getContinentByCountryCode(hostCode)] ?? '')
            : '';

        // Check if country matches this continent                
        if (normalizeName(countryContinent) == continentIdentifier) {
          continentCountries.add(countryItem);
        }
      }

      // Only add continent if it has countries            
      if (continentCountries.isNotEmpty) {
        continentCountries.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

        // AGGREGATE MEMBER COUNTS: Sum all children countries                
        final totalMembers = continentCountries.fold(
            0,
            (sum, country) => sum + country.totalMembers
        );
        
        continentHierarchy.add(HierarchyItem(
            id: continent.id,
            name: continentName,
            type: 'continent',
            locationType: 'host',
            homeCountryCode: continent.homeCountryCode,
            location: continent.location,
            profileImage: continent.profileImage != null ? ChatProfileImage(type: 'icon', value: 'users') : null,
            // [NEW]                  
            totalMembers: totalMembers,
            // Correct aggregated count                  
            isExpandable: false,
            // Continents always show countries                  
            children: continentCountries
        ));
      }
    }

    // Find orphan countries (not assigned to any continent)       
    final assignedCountryIds = continentHierarchy
        .expand((continent) => continent.children ?? [])
        .map((country) => country.id)
        .toSet();

    final orphanCountries = countryItems
        .where((country) => !assignedCountryIds.contains(country.id))
        .map((country) => HierarchyItem(
            id: country.id,
            name: country.name,
            type: country.type,
            locationType: country.locationType,
            homeCountryCode: country.homeCountryCode,
            hostCountryCode: country.hostCountryCode,
            flag: country.flag,
            location: country.location,
            profileImage: country.profileImage != null ? ChatProfileImage(type: 'icon', value: 'users') : null,
            // [NEW]               
            totalMembers: country.totalMembers,
            isExpandable: country.children!.isNotEmpty,
            children: country.children!
        ))
        .toList();
    orphanCountries.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final globalChildren = [...continentHierarchy, ...orphanCountries];

    // (A) Global Item - Now calculated AFTER hierarchy is built to aggregate counts       
    if (globalCommunity.type == 'global') {
      // Calculate Stats from built hierarchy           
      int totalMembers = 0;

      final hostCountries = <String>{};
      int hostCitiesCount = 0;

      // Aggregation from built items           
      for (var child in globalChildren) {
        totalMembers += child.totalMembers;

        // Sum continents/orphans                            
        // Recursively count stats (simplified for depth 2)              
        if (child.type == 'continent') {
          for (var co in child.children ?? []) {
            if (co.hostCountryCode != null) hostCountries.add(co.hostCountryCode!);
            // Check cities inside country                     
            // ... (deeper recursion if needed for precise stats)                  
          }
        } else if (child.type == 'country') {
          if (child.hostCountryCode != null) hostCountries.add(child.hostCountryCode!);
        }
      }

      // Re-calculate precise stats from raw lists for accuracy if needed,            
      // or trust hierarchy sum. For Members, trusting sum is best for consistency.                      
      // Recalculate distinct counts from raw lists for stats           
      for (var c in relevantCommunities) {
        if (c.locationType == 'host' && c.homeCountryCode == userHomeCode) {
          if (c.location != null && c.location!['countryCode'] != null) {
            hostCountries.add(c.location!['countryCode']);
          }
          if (c.type == 'city') hostCitiesCount++;
        }
      }
      
      hierarchy.add(HierarchyItem(
          id: globalCommunity.id,
          name: 'Global Community',
          type: 'global',
          locationType: 'global',
          homeCountryCode: userHomeCode,
          location: globalCommunity.location,
          profileImage: globalCommunity.profileImage != null ? ChatProfileImage(type: 'icon', value: 'users') : null,
          // [NEW] Pass profileImage              
          totalMembers: totalMembers,
          // AGGREGATED COUNT              
          isExpandable: false,
          children: globalChildren,
          // Nest continents under global              
          globalStats: GlobalStats(
            totalMembers: totalMembers,
            continents: continentHierarchy.length,
            countries: hostCountries.length,
            cities: hostCitiesCount,
          )
      ));
    } else {
      // Fallback if no global node         
      hierarchy.addAll(globalChildren);
    }

    return hierarchy;
  }

  // Helper to build Host Country -> State -> City tree   
  List<HierarchyItem> _buildHostCountryTree(
      List<Community> countries,
      List<Community> states,
      List<Community> cities
      ) {
    final items = <HierarchyItem>[];
    for (var country in countries) {
      final countryCode = country.location?['countryCode'];

      // Filter states/cities for THIS country           
      final myStates = states.where((s) => s.location?['countryCode'] == countryCode).toList();

      final myCities = cities.where((c) => c.location?['countryCode'] == countryCode).toList();

      // Sort states and cities           
      myStates.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      myCities.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      final children = <HierarchyItem>[];
      int countryTotalMembers = country.totalMembers ?? country.memberCount;

      // Start with base count                      
      // States                      
      for (var state in myStates) {
        final stateName = state.location?['state'];

        final stateCities = myCities.where((c) => c.location?['state'] == stateName).toList();
        stateCities.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        int stateTotalMembers = state.totalMembers ?? state.memberCount;

        // Aggregate state members from cities if needed               
        if (stateTotalMembers == 0) {
          stateTotalMembers = stateCities.fold(0, (sum, c) => sum + (c.totalMembers ?? c.memberCount));
        }
        
        children.add(HierarchyItem(
            id: state.id,
            name: CommunityChatUtils.generateCommunityNameFromParts(
                name: state.name,
                locationType: 'host',
                id: state.id
            ),
            type: 'state',
            locationType: 'host',
            homeCountryCode: state.homeCountryCode,
            hostCountryCode: state.location?['countryCode'],
            location: state.location,
            totalMembers: stateTotalMembers,
            isExpandable: stateCities.isNotEmpty,
            children: stateCities.map((city) => HierarchyItem(
                id: city.id,
                name: CommunityChatUtils.generateCommunityNameFromParts(
                    name: city.name,
                    locationType: 'host',
                    id: city.id
                ),
                type: 'city',
                locationType: 'host',
                homeCountryCode: city.homeCountryCode,
                hostCountryCode: city.location?['countryCode'],
                totalMembers: city.totalMembers ?? city.memberCount,
            )).toList()
        ));
      }

      // Direct Cities (orphans)           
      for (var city in myCities) {
        final cityState = city.location?['state'];

        final belongsToState = cityState != null && myStates.any((s) => s.location?['state'] == cityState);
        if (!belongsToState) {
          children.add(HierarchyItem(
              id: city.id,
              name: CommunityChatUtils.generateCommunityNameFromParts(
                  name: city.name,
                  locationType: 'host',
                  id: city.id
              ),
              type: 'city',
              locationType: 'host',
              homeCountryCode: city.homeCountryCode,
              hostCountryCode: city.location?['countryCode'],
              totalMembers: city.totalMembers ?? city.memberCount,
          ));
        }
      }

      // Sort children (States + Cities)           
      children.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      // Aggregate Country count (States + Direct Cities + Base)           
      if (countryTotalMembers == 0) {
        countryTotalMembers = children.fold(0, (sum, child) => sum + child.totalMembers);
      }
      items.add(HierarchyItem(
          id: country.id,
          name: CommunityChatUtils.generateCommunityNameFromParts(
              name: country.name,
              locationType: 'host',
              id: country.id
          ),
          type: 'country',
          locationType: 'host',
          homeCountryCode: country.homeCountryCode,
          hostCountryCode: countryCode,
          flag: country.flag,
          location: country.location,
          totalMembers: countryTotalMembers,
          isExpandable: true,
          children: children
      ));
    }

    return items;
  }

  // ===========================================================================   
  // MODE 2: GLOBAL (Toggle)   
  // Logic: Show ALL communities, grouped by HOME Location   
  // Hierarchy: Global -> Continent (Home) -> Country (Home) -> Country (Host) -> State -> City   
  // ===========================================================================   
  Future<List<HierarchyItem>> _buildGlobalHierarchy(String userHomeCode) async {
    // Helper        
    String normalizeName(String name) => name.toLowerCase().replaceAll('community', '').trim();

    final firestore = FirebaseFirestore.instance;

    // Fetch all communities        
    final snapshot = await firestore.collection('communities').get();

    // Parse        
    final allCommunities = snapshot.docs.map((d) => Community.fromJson({...d.data(), 'id': d.id})).toList();

    // Separate by location type        
    final homeCommunities = allCommunities.where((c) => c.locationType == 'home').toList();

    final hostCommunities = allCommunities.where((c) => c.locationType == 'host').toList();

    final globalCommunity = allCommunities.firstWhere(
            (c) => c.type == 'global',
        orElse: () => Community(
            id: 'dummy', 
            name: '', 
            type: 'dummy',
            description: '',
            homeCountryCode: '',
            hostCountryCode: '',
            memberCount: 0,
            images: [],
            isPrivate: false,
        )
    );

    // Group by type        
    final homeContinents = homeCommunities.where((c) => c.type == 'continent').toList();

    final homeCountries = homeCommunities.where((c) => c.type == 'country').toList();

    final hostCountries = hostCommunities.where((c) => c.type == 'country').toList();

    final hostStates = hostCommunities.where((c) => c.type == 'state').toList();

    final hostCities = hostCommunities.where((c) => c.type == 'city').toList();

    // Sort        
    homeContinents.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    homeCountries.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // Build Home Country items with Host locations as children        
    final homeCountryItems = <HierarchyItem>[];
    for (var homeCountry in homeCountries) {
      final hCode = homeCountry.homeCountryCode;
      if (hCode == null) continue;

      // Find all HOST countries where people from this home country live             
      final myHostCountries = hostCountries.where((c) => c.homeCountryCode == hCode).toList();
      myHostCountries.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      // 1. Build host country hierarchy items (flat list of countries first)             
      final flatHostCountryItems = <HierarchyItem>[];
      for (var hostCountry in myHostCountries) {
        final hostCountryCode = hostCountry.location?['countryCode'];

        // Find states and cities in this host country for this home country                 
        final myHostStates = hostStates.where((s) =>
        s.homeCountryCode == hCode && s.location?['countryCode'] == hostCountryCode
        ).toList();

        final myHostCities = hostCities.where((c) =>
        c.homeCountryCode == hCode && c.location?['countryCode'] == hostCountryCode
        ).toList();

        final hostStateChildren = <HierarchyItem>[];

        // Build state → city hierarchy                 
        for (var hostState in myHostStates) {
          final stateName = hostState.location?['state'];

          final stateCities = myHostCities.where(
                  (c) => c.location?['state'] == stateName
          ).toList();

          int stateTotal = (hostState.totalMembers ?? hostState.memberCount);
          if (stateTotal == 0) {
            stateTotal = stateCities.fold(0, (sum, c) => sum + (c.totalMembers ?? c.memberCount));
          }
          hostStateChildren.add(HierarchyItem(
              id: hostState.id,
              name: CommunityChatUtils.generateCommunityNameFromParts(
                  name: hostState.name,
                  locationType: 'host',
                  id: hostState.id
              ),
              type: 'state',
              locationType: 'host',
              homeCountryCode: hostState.homeCountryCode,
              hostCountryCode: hostCountryCode,
              location: hostState.location,
              profileImage: hostState.profileImage != null ? ChatProfileImage(type: 'icon', value: 'users') : null,
              totalMembers: stateTotal,
              isExpandable: stateCities.isNotEmpty,
              children: stateCities.map((city) => HierarchyItem(
                  id: city.id,
                  name: CommunityChatUtils.generateCommunityNameFromParts(
                      name: city.name,
                      locationType: 'host',
                      id: city.id
                  ),
                  type: 'city',
                  locationType: 'host',
                  homeCountryCode: city.homeCountryCode,
                  hostCountryCode: hostCountryCode,
                  location: city.location,
                  profileImage: city.profileImage != null ? ChatProfileImage(type: 'icon', value: 'users') : null,
                  totalMembers: city.totalMembers ?? city.memberCount,
              )).toList()
          ));
        }

        // Add direct cities (orphans)                 
        for (var city in myHostCities) {
          final cityState = city.location?['state'];

          final belongsToState = cityState != null &&
              myHostStates.any((s) => s.location?['state'] == cityState);
          if (!belongsToState) {
            hostStateChildren.add(HierarchyItem(
                id: city.id,
                name: CommunityChatUtils.generateCommunityNameFromParts(
                    name: city.name,
                    locationType: 'host',
                    id: city.id
                ),
                type: 'city',
                locationType: 'host',
                homeCountryCode: city.homeCountryCode,
                hostCountryCode: hostCountryCode,
                location: city.location,
                profileImage: city.profileImage != null ? ChatProfileImage(type: 'icon', value: 'users') : null,
                totalMembers: city.totalMembers ?? city.memberCount,
            ));
          }
        }

        // Add host country                 
        int hostCountryTotal = hostCountry.totalMembers ?? hostCountry.memberCount;
        if (hostCountryTotal == 0) {
          hostCountryTotal = hostStateChildren.fold(0, (sum, child) => sum + child.totalMembers);
        }
        flatHostCountryItems.add(HierarchyItem(
            id: hostCountry.id,
            name: CommunityChatUtils.generateCommunityNameFromParts(
                name: hostCountry.name,
                locationType: 'host',
                id: hostCountry.id
            ),
            type: 'country',
            locationType: 'host',
            homeCountryCode: hostCountry.homeCountryCode,
            hostCountryCode: hostCountryCode,
            flag: hostCountry.flag,
            location: hostCountry.location,
            profileImage: hostCountry.profileImage != null ? ChatProfileImage(type: 'icon', value: 'users') : null,
            totalMembers: hostCountryTotal,
            isExpandable: true,
            children: hostStateChildren
        ));
      }

      // 2. Group Host Countries by Continent             
      final hostContinentChildren = <HierarchyItem>[];

      final processedCountryIds = <String>{};

      // Get all possible continents from these countries             
      final continentMap = <String, List<HierarchyItem>>{};

      for (var countryItem in flatHostCountryItems) {
        final cCode = countryItem.hostCountryCode;
        if (cCode != null) {
          final cont = country_data.getContinentByCountryCode(cCode);
          if (cont != null) {
            final key = country_data.continentDisplayNames[cont] ?? '';
            // [FIX] Use displayName ("North America") not name ("northAmerica")                        
            continentMap.putIfAbsent(key, () => []).add(countryItem);
            processedCountryIds.add(countryItem.id);
          }
        }
      }

      // Create Continent Items             
      continentMap.forEach((continentName, countries) {
        countries.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

        final totalMembers = countries.fold(0, (sum, c) => sum + c.totalMembers);

        // Generate a synthetic ID                  
        final syntheticId = '${homeCountry.id}_host_cont_${continentName.replaceAll(" ", "")}';
        
        hostContinentChildren.add(HierarchyItem(
            id: syntheticId,
            name: '$continentName Community',
            // Naming convention                       
            type: 'continent',
            // It acts as a continent folder                       
            locationType: 'host',
            homeCountryCode: hCode,
            // It belongs to this home diaspora                       
            hostCountryCode: null,
            // It's a continent                       
            totalMembers: totalMembers,
            isExpandable: false,
            children: countries
        ));
      });

      // Retrieve Orphans (Host countries with no continent mapping? Unlikely but safe)             
      final orphanHostCountries = flatHostCountryItems
          .where((c) => !processedCountryIds.contains(c.id))
          .toList();

      // Combine: Continents + Orphans             
      final finalHostChildren = [...hostContinentChildren, ...orphanHostCountries];
      finalHostChildren.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      // Only add home country if relevant             
      final hasHost = finalHostChildren.any((c) => c.totalMembers > 0);

      final isMyHome = hCode == userHomeCode;

      final hasDirect = (homeCountry.totalMembers ?? homeCountry.memberCount) > 0;

      if (hasDirect || hasHost || isMyHome) {
        int homeTotal = homeCountry.totalMembers ?? homeCountry.memberCount;

        final hostTotal = flatHostCountryItems.fold(0, (sum, child) => sum + child.totalMembers);

        if (homeTotal < hostTotal) homeTotal = hostTotal;

        // logic from before                   
        homeCountryItems.add(HierarchyItem(
            id: homeCountry.id,
            name: CommunityChatUtils.generateCommunityNameFromParts(
                name: homeCountry.name,
                locationType: 'home',
                id: homeCountry.id
            ),
            type: 'country',
            locationType: 'home',
            homeCountryCode: hCode,
            location: homeCountry.location,
            totalMembers: homeTotal,
            flag: homeCountry.flag,
            profileImage: homeCountry.profileImage != null ? ChatProfileImage(type: 'icon', value: 'users') : null,
            isExpandable: true,
            children: finalHostChildren
            // Grouped by continent!                  
        ));
      }
    }

    // Build Continent → Home Country hierarchy        
    final continentHierarchy = <HierarchyItem>[];
    for (var continent in homeContinents) {
      final continentIdentifier = continent.name.replaceAll(' Community', '').trim();

      // Find home countries in this continent            
      final continentCountries = <HierarchyItem>[];
      for (var homeCountryItem in homeCountryItems) {
        // Robust Lookup: Use Country Data to find continent of this home country code                
        final hCode = homeCountryItem.homeCountryCode;
        if (hCode != null) {
          final continentData = country_data.getContinentByCountryCode(hCode);

          final continentName = continentData?.name ?? '';

          final continentDisplay = continentData != null ? (country_data.continentDisplayNames[continentData] ?? '') : '';

          // Check matches (Compare against Continent Identifier e.g. "Africa" or full name "Africa Community")                    
          // The 'continentIdentifier' string is already normalized (e.g. "Africa")                    
          if (normalizeName(continentName) == normalizeName(continentIdentifier) ||
              normalizeName(continentDisplay) == normalizeName(continentIdentifier) ||
              normalizeName(continentName) == normalizeName(continent.name)) {
            continentCountries.add(homeCountryItem);
          }
        }
      }

      // Only add continent if it has countries with members            
      if (continentCountries.isNotEmpty) {
        continentCountries.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

        // AGGREGATE Continent Members: Sum of countries                
        int continentTotal = continent.totalMembers ?? continent.memberCount;

        final childrenTotal = continentCountries.fold(
            0,
            (sum, country) => sum + country.totalMembers
        );
        if (continentTotal < childrenTotal) continentTotal = childrenTotal;

        final continentName = CommunityChatUtils.generateCommunityNameFromParts(
            name: continent.name,
            locationType: 'home',
            id: continent.id
        );

        continentHierarchy.add(HierarchyItem(
            id: continent.id,
            name: continentName,
            type: 'continent',
            locationType: 'home',
            homeCountryCode: continent.homeCountryCode,
            location: continent.location,
            profileImage: continent.profileImage != null ? ChatProfileImage(type: 'icon', value: 'users') : null,
            // [NEW]                    
            totalMembers: continentTotal,
            isExpandable: false,
            // Continents always show countries                    
            children: continentCountries
        ));
      }
    }

    // Find orphan home countries (not in any continent)        
    final assignedCountryIds = continentHierarchy
        .expand((continent) => continent.children ?? [])
        .map((country) => country.id)
        .toSet();

    final orphanCountries = homeCountryItems
        .where((country) => !assignedCountryIds.contains(country.id))
        .toList();
    orphanCountries.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // Also sort the continent Hierarchy explicitly to be safe        
    continentHierarchy.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // Build 
    final hierarchy = <HierarchyItem>[];

    final globalChildren = [...continentHierarchy, ...orphanCountries];

    // Add Global Community if it exists        
    if (globalCommunity.type == 'global') {
      // AGGREGATE Global Members            
      int totalGlobalMembers = globalCommunity.totalMembers ?? 0;

      final childrenTotal = globalChildren.fold(
          0,
          (sum, child) => sum + child.totalMembers
      );
      if (totalGlobalMembers < childrenTotal) totalGlobalMembers = childrenTotal;

      // Calculate global stats            
      final hostCountrySet = <String>{};
      int totalHostCities = 0;

      for (var homeCountry in homeCountryItems) {
        // Helper function to process a host country node
        void processHostCountry(HierarchyItem hostCountry) {
          if (hostCountry.hostCountryCode != null) {
            hostCountrySet.add(hostCountry.hostCountryCode!);
          }

          // Count cities
          for (var child in hostCountry.children ?? []) {
            if (child.type == 'city') {
              totalHostCities++;
            } else if (child.type == 'state') {
              totalHostCities += (child.children?.length ?? 0) as int;
            }
          }
        }

        for (var child in homeCountry.children ?? []) {
          if (child.type == 'continent') {
            // This is a Host Continent, iterate its children (Host Countries)
            for (var hostCountry in child.children) {
              processHostCountry(hostCountry);
            }
          } else {
            // This is likely a direct Host Country (orphan)
            processHostCountry(child);
          }
        }
      }

      hierarchy.add(HierarchyItem(
          id: globalCommunity.id,
          name: CommunityChatUtils.generateCommunityNameFromParts(
              name: 'Global Community',
              // Or globalCommunity.name if reliable                    
              locationType: 'global',
              id: globalCommunity.id
          ),
          type: 'global',
          locationType: 'global',
          homeCountryCode: globalCommunity.homeCountryCode,
          location: globalCommunity.location,
          totalMembers: totalGlobalMembers,
          isExpandable: false,
          // Always show continents                
          children: globalChildren,
          globalStats: GlobalStats(
            totalMembers: totalGlobalMembers,
            continents: continentHierarchy.length,
            countries: hostCountrySet.length,
            cities: totalHostCities,
          )
      ));
    } else {
      // No global community, add continents and orphans directly            
      hierarchy.addAll(globalChildren);
    }


    return hierarchy;
  }

  Community? _safeParseCommunity(String id, Map<String, dynamic> data) {
    try {
      return Community(
        id: id,
        name: data['name'] as String? ?? 'Unknown Community',
        description: data['description'] as String?,
        homeCountryCode: data['homeCountryCode'] as String?,
        hostCountryCode: data['hostCountryCode'] as String?,
        type: data['type'] as String?,
        locationType: data['locationType'] as String?,
        images: (data['images'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
        memberCount: (data['memberCount'] as num?)?.toInt() ?? 0,
        totalMembers: (data['totalMembers'] as num?)?.toInt(),
        isPrivate: data['isPrivate'] as bool? ?? false,
        location: data['location'] as Map<String, dynamic>?,
        profileImage: data['profileImage'] as String?,
        chatId: data['chatId'] as String?,
        flag: data['flag'] as String?,
      );
    } catch (e) {
      print('Error parsing community $id: $e');
      return null;
    }
  }
}



