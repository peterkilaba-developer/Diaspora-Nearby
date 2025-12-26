import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:firebase_database/firebase_database.dart' as rtdb;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:diaspora_nearby/models/profile_data.dart';
import 'package:diaspora_nearby/utils/location_utils.dart';
import 'package:diaspora_nearby/data/countries.dart' as country_data;

/// CommunityService handles community and chat creation during user registration.
/// This implementation matches the React app's `communityLocationUtils.ts` logic.
class CommunityService {
  final cf.FirebaseFirestore _firestore = cf.FirebaseFirestore.instance;
  final rtdb.FirebaseDatabase _rtdb = rtdb.FirebaseDatabase.instance;

  /// Main entry point: creates all communities and chats for a new user.
  /// Mirrors React's `assignUserToCommunities()` function.
  Future<List<String>> createCommunitiesAndChats(ProfileData profile) async {
    // Validate required data
    if (profile.uid == null || profile.uid!.isEmpty) {
      return [];
    }
    
    if (profile.homeCountryCode == null || profile.homeCountryCode!.isEmpty) {
      return [];
    }

    final userId = profile.uid!;
    final homeCountryCode = profile.homeCountryCode!;
    final hostCountryCode = profile.hostCountryCode ?? 'XX';

    // Parse locations
    final homeParsed = LocationParsed(
      city: profile.homeLocation.city,
      state: profile.homeLocation.state,
      country: profile.homeCountry ?? profile.homeLocation.country ?? '',
      countryCode: homeCountryCode,
    );
    
    final hostParsed = LocationParsed(
      city: profile.hostLocation.city,
      state: profile.hostLocation.state,
      country: profile.hostCountry ?? profile.hostLocation.country ?? '',
      countryCode: hostCountryCode,
    );

    // Get continents
    final homeContinent = getContinentByCountryCode(homeCountryCode);
    final hostContinent = getContinentByCountryCode(hostCountryCode);
    final homeContinentName = getContinentName(homeContinent);
    final hostContinentName = getContinentName(hostContinent);

    // Collect all community IDs and chat IDs for batch operations
    final List<String> communityIds = [];
    final List<String> chatIds = [];

    // ========================================
    // 1. GLOBAL COMMUNITY
    // ========================================
    final globalId = await _ensureCommunity(
      type: 'global',
      locationType: 'global',
      location: homeParsed,
      userId: userId,
      homeCountryCode: homeCountryCode,
      hostCountryCode: null,
    );
    communityIds.add(globalId);
    chatIds.add('chat_$globalId');

    // ========================================
    // 2. HOME COMMUNITIES
    // ========================================
    final homeCommunityIds = await ensureCommunitiesForLocationHierarchy(
      location: homeParsed,
      locationType: 'home',
      userId: userId,
      homeCountryCode: homeCountryCode,
      hostCountryCode: null,
    );
    communityIds.addAll(homeCommunityIds);
    chatIds.addAll(homeCommunityIds.map((id) => 'chat_$id'));

    // ========================================
    // 3. HOST COMMUNITIES (with homeCountryCode suffix)
    // ========================================
    final hostCommunityIds = await ensureCommunitiesForLocationHierarchy(
      location: hostParsed,
      locationType: 'host',
      userId: userId,
      homeCountryCode: homeCountryCode,
      hostCountryCode: hostCountryCode,
    );
    communityIds.addAll(hostCommunityIds);
    chatIds.addAll(hostCommunityIds.map((id) => 'chat_$id'));

    // ========================================
    // 4. BATCH UPDATE userChats INDEX + PROFILE
    // ========================================
    await _batchUpdateUserChatsIndex(userId, chatIds);
    await _firestore.collection('users').doc(userId).update({
      'communityMemberships': cf.FieldValue.arrayUnion(communityIds),
    });

    return communityIds;
  }

  /// Ensures communities exist for a full location hierarchy (Continent -> Country -> State -> City).
  /// Returns a list of created/joined community IDs.
  /// This extracts the logic from profile creation so it can be reused for updates (e.g. Past Locations).
  Future<List<String>> ensureCommunitiesForLocationHierarchy({
    required LocationParsed location,
    required String locationType,
    required String userId,
    required String homeCountryCode,
    String? hostCountryCode,
  }) async {
    final List<String> ids = [];
    final countryCode = locationType == 'home' ? homeCountryCode : (hostCountryCode ?? location.countryCode);
    
    // Get continent
    final continent = getContinentByCountryCode(countryCode);
    final continentName = getContinentName(continent);

    // 1. Continent
    final continentId = await _ensureCommunity(
      type: 'continent',
      locationType: locationType,
      location: location,
      continent: continentName,
      userId: userId,
      homeCountryCode: homeCountryCode,
      hostCountryCode: hostCountryCode,
    );
    ids.add(continentId);

    // 2. Country
    final countryId = await _ensureCommunity(
      type: 'country',
      locationType: locationType,
      location: location,
      userId: userId,
      homeCountryCode: homeCountryCode,
      hostCountryCode: hostCountryCode,
    );
    ids.add(countryId);

    // 3. State (only for 3-level countries)
    if (location.state != null && location.state!.isNotEmpty && country_data.hasStateLevelHierarchyFromData(countryCode)) {
      final stateId = await _ensureCommunity(
        type: 'state',
        locationType: locationType,
        location: location,
        userId: userId,
        homeCountryCode: homeCountryCode,
        hostCountryCode: hostCountryCode,
      );
      ids.add(stateId);
    }

    // 4. City
    if (location.city != null && location.city!.isNotEmpty) {
      final cityId = await _ensureCommunity(
        type: 'city',
        locationType: locationType,
        location: location,
        userId: userId,
        homeCountryCode: homeCountryCode,
        hostCountryCode: hostCountryCode,
      );
      ids.add(cityId);
    }

    return ids;
  }

  /// Ensures a community exists, creates if not. Returns community ID.
  Future<String> _ensureCommunity({
    required String type,
    required String locationType,
    required LocationParsed location,
    String? continent,
    required String userId,
    required String homeCountryCode,
    String? hostCountryCode,
  }) async {
    // Generate community ID (matches React's generateCommunityId)
    final communityId = generateCommunityId(
      locationType: locationType,
      type: type,
      location: location,
      continent: continent,
      homeCountryCode: locationType == 'host' ? homeCountryCode : null,
    );
    
    // Generate community name
    final communityName = generateCommunityName(
      type: type,
      location: location,
      continent: continent,
      locationType: locationType,
    );

    final docRef = _firestore.collection('communities').doc(communityId);
    final docSnapshot = await docRef.get();

    if (!docSnapshot.exists) {
      // Create new community in Firestore
      await docRef.set({
        'id': communityId,
        'name': communityName,
        'type': type,
        'locationType': locationType,
        'location': {
          'city': location.city,
          'state': location.state,
          'country': location.country,
          'countryCode': location.countryCode,
        },
        'homeCountryCode': homeCountryCode,
        'hostCountryCode': hostCountryCode,
        'continent': continent,
        'members': [userId],
        'memberCount': 1,
        'chatId': 'chat_$communityId',
        'createdAt': cf.Timestamp.now(),
        'updatedAt': cf.Timestamp.now(),
      });

      // Create chat in RTDB
      await _createChat(
        communityId: communityId,
        communityName: communityName,
        communityType: type,
        locationType: locationType,
        homeCountryCode: homeCountryCode,
        hostCountryCode: hostCountryCode,
        initialParticipants: [userId],
        continent: continent,
      );
    } else {
      // Add member to existing community
      final existingData = docSnapshot.data() as Map<String, dynamic>;
      final existingMemberIds = List<String>.from(existingData['members'] ?? existingData['memberIds'] ?? []);
      
      if (!existingMemberIds.contains(userId)) {
        await docRef.update({
          'members': cf.FieldValue.arrayUnion([userId]),
          'memberCount': cf.FieldValue.increment(1),
          'updatedAt': cf.Timestamp.now(),
        });
      }

      // Get the chatId from the community
      final chatId = existingData['chatId'] as String? ?? 'chat_$communityId';
      final chatRef = _rtdb.ref('chats/$chatId');
      final chatSnapshot = await chatRef.get();
      
      if (chatSnapshot.exists) {
        // Chat exists, add user to participants if not already there
        final chatData = chatSnapshot.value as Map<dynamic, dynamic>;
        final participants = List<String>.from(chatData['participants'] ?? []);
        
        if (!participants.contains(userId)) {
          // Transaction to update participants and increment count safely
          await chatRef.runTransaction((mutableData) {
            if (mutableData == null) return rtdb.Transaction.success(null);
            
            Map<String, dynamic> data;
            if (mutableData is Map) {
              data = Map<String, dynamic>.from(mutableData as Map);
            } else {
              return rtdb.Transaction.success(mutableData);
            }

            // Update participants
            List<String> currentParticipants = [];
            if (data['participants'] is List) {
              currentParticipants = List<String>.from(data['participants']);
            }
            
            if (!currentParticipants.contains(userId)) {
               currentParticipants.add(userId);
               data['participants'] = currentParticipants;
               
               // Increment member count
               int currentCount = data['memberCount'] is int ? data['memberCount'] : currentParticipants.length;
               data['memberCount'] = currentCount; // The list length is the truth
            }
            
            data['updatedAt'] = rtdb.ServerValue.timestamp;
            return rtdb.Transaction.success(data);
          });
        }
        
        // Add chat to user's userChats index
        await _rtdb.ref('userChats/$userId/$chatId').set({
          'chatId': chatId,
          'lastRead': rtdb.ServerValue.timestamp,
          'addedAt': rtdb.ServerValue.timestamp,
        });
      } else {
        // Chat doesn't exist - create it now
        await _createChat(
          communityId: communityId,
          communityName: communityName,
          communityType: type,
          locationType: locationType,
          homeCountryCode: homeCountryCode,
          hostCountryCode: hostCountryCode,
          initialParticipants: [userId, ...existingMemberIds],
          continent: continent,
        );
        
        // Add chat to userChats index for ALL members
        final allMemberIds = [userId, ...existingMemberIds];
        for (final memberId in allMemberIds) {
          await _rtdb.ref('userChats/$memberId/$chatId').set({
            'chatId': chatId,
            'lastRead': rtdb.ServerValue.timestamp,
            'addedAt': rtdb.ServerValue.timestamp,
          });
        }
      }
    }

    return communityId;
  }

  /// Creates a chat in RTDB for a community.
  /// Matches React's `createCommunityChat()` function.
  Future<void> _createChat({
    required String communityId,
    required String communityName,
    required String communityType,
    required String locationType,
    required String homeCountryCode,
    String? hostCountryCode,
    required List<String> initialParticipants,
    String? continent,
  }) async {
    final chatId = 'chat_$communityId';
    final chatRef = _rtdb.ref('chats/$chatId');
    
    final snapshot = await chatRef.get();
    if (snapshot.exists) {
      return; // Chat already exists
    }

    // Chat name is the same as community name (with Community suffix)
    final String chatName = communityName;

    await chatRef.set({
      'id': chatId,
      'communityId': communityId,
      'type': 'community', // CRITICAL: must be 'community' not communityType
      'name': chatName,
      'locationType': locationType, // CRITICAL: Determines avatar color (home vs host)
      'homeCountryCode': homeCountryCode,
      'hostCountryCode': hostCountryCode,
      'participants': initialParticipants,
      'memberCount': initialParticipants.length,
      'admins': [],
      'createdBy': initialParticipants.isNotEmpty ? initialParticipants.first : 'system',
      'lastMessage': null,
      'createdAt': rtdb.ServerValue.timestamp,
      'updatedAt': rtdb.ServerValue.timestamp,
    });
  }

  /// internal cleanup: Removes communities with 0 members.
  /// This ensures "community and community chats are only created from locations of the user".
  Future<void> pruneEmptyCommunities() async {
    // 1. Query for communities with 0 members
    // Note: This relies on memberCount being accurately 0 for empty ones.
    // We also check memberIds to be safe.
    final snapshot = await _firestore.collection('communities').get();
    
    for (final doc in snapshot.docs) {
       final data = doc.data();
       final memberCount = data['memberCount'] as int? ?? 0;
       final memberIds = List.from(data['members'] ?? data['memberIds'] ?? []);
       
       if (memberCount == 0 || memberIds.isEmpty) {
          // Delete Community
          await doc.reference.delete();
          
          // Delete Chat
          final chatId = data['chatId'] as String?;
          if (chatId != null) {
            await _rtdb.ref('chats/$chatId').remove();
          }
          
          print('Pruned empty community: ${doc.id}');
       }
    }

    // 2. Remove Deprecated "United Kingdom" (GB) specifically
    final gbRef = _firestore.collection('communities').doc('home_country_GB');
    final gbDoc = await gbRef.get();
    if (gbDoc.exists) {
       await gbRef.delete();
       // And its chat
       await _rtdb.ref('chats/chat_home_country_GB').remove();
    }
  }

  /// HARD RESET DATABASE
  /// Deletes selected collections and services.
  /// [resetTargets] list of keys: 'users', 'communities', 'events', 'organizations', 'radio', 'chats', 'storage'
  Future<void> hardResetDatabase({List<String> resetTargets = const ['users', 'communities', 'events', 'organizations', 'radio', 'chats', 'storage']}) async {
    
    // 1. Delete Collections
    if (resetTargets.contains('communities')) await _deleteCollection('communities');
    if (resetTargets.contains('users')) await _deleteCollection('users'); 
    if (resetTargets.contains('events')) await _deleteCollection('events');
    if (resetTargets.contains('organizations')) await _deleteCollection('organizations');
    if (resetTargets.contains('radio')) {
      await _deleteCollection('radio_station_health'); // Corrected Name
      // Note: Add other radio collections if consistent with your architecture, e.g. radio_reviews
    }

    // 2. Delete RTDB Paths
    if (resetTargets.contains('chats')) {
       await _rtdb.ref('chats').remove();
       await _rtdb.ref('userChats').remove();
    }
    
    // 3. Delete Storage Folders
    if (resetTargets.contains('storage')) {
      await _deleteStorageFolder('profile_photos');
      await _deleteStorageFolder('community_headers');
      // Add other folders as needed
    }

    // Re-seed logic removed as per on-demand requirement
  }

  Future<void> _deleteCollection(String collectionPath) async {
    final collection = _firestore.collection(collectionPath);
    final snapshots = await collection.get();
    
    if (snapshots.docs.isEmpty) {
      return;
    }

    for (final doc in snapshots.docs) {
      try {
        await doc.reference.delete();
      } catch (e) {
        // Continue on error
      }
    }
  }
  
  Future<void> _deleteStorageFolder(String path) async {
    try {
       final ref = FirebaseStorage.instance.ref(path);
       final list = await ref.listAll();
       
       // Delete files
       for (final item in list.items) {
         await item.delete();
       }
       
       // Recurse directories
       for (final prefix in list.prefixes) {
         await _deleteStorageFolder(prefix.fullPath);
       }
    } catch (e) {
       // Often errors if folder doesn't exist, ignore
    }
  }

  /// Batch updates userChats index for all community chats.
  /// Matches React's `batchUpdateUserChatsIndex()` function.
  Future<void> _batchUpdateUserChatsIndex(String userId, List<String> chatIds) async {
    if (chatIds.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final Map<String, dynamic> updates = {};

    for (final chatId in chatIds) {
      updates['userChats/$userId/$chatId'] = {
        'chatId': chatId,
        'lastRead': now,
        'addedAt': now,
      };
    }

    // Atomic multi-path update
    await _rtdb.ref().update(updates);
  }
}

