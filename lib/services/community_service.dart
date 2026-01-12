import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:firebase_database/firebase_database.dart' as rtdb;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart'; // [NEW]
import 'package:flutter/foundation.dart';
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
  Future<List<String>> createCommunitiesAndChats(ProfileData profile, {Function(String)? onFirstMember}) async {
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
    // [NEW] Extract User Name for Notifications
    final userName = profile.fullName;

    // Parse locations
    final homeParsed = LocationParsed(
      city: profile.homeLocation.city,
      state: profile.homeLocation.state,
      country: profile.homeCountry ?? profile.homeLocation.country ?? '',
      countryCode: homeCountryCode,
      placeId: profile.homeLocation.placeId,
    );
    
    final hostParsed = LocationParsed(
      city: profile.hostLocation.city,
      state: profile.hostLocation.state,
      country: profile.hostCountry ?? profile.hostLocation.country ?? '',
      countryCode: hostCountryCode,
      placeId: profile.hostLocation.placeId,
    );

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
      onFirstMember: onFirstMember,
      userName: userName,
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
      onFirstMember: onFirstMember,
      userName: userName,
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
      onFirstMember: onFirstMember,
      userName: userName,
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
    bool syncToUserProfile = false, // [NEW] Option to auto-sync to profile
    Function(String)? onFirstMember,
    String? userName, // [NEW] For notification
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
      onFirstMember: onFirstMember,
      userName: userName,
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
      onFirstMember: onFirstMember,
      userName: userName,
    );
    ids.add(countryId);

    // 3. State (only for 3-level countries)
    // [FIX] China Direct-Controlled Municipalities Logic: Skip State level to avoid "Shanghai, Shanghai, China"
    bool skipState = false;
    if (countryCode == 'CN') {
      const directControlled = ['Beijing', 'Shanghai', 'Tianjin', 'Chongqing'];
      if (location.city != null && directControlled.any((c) => location.city!.contains(c))) {
        skipState = true;
      }
    }

    if (!skipState && location.state != null && location.state!.isNotEmpty && country_data.hasStateLevelHierarchyFromData(countryCode)) {
      final stateId = await _ensureCommunity(
        type: 'state',
        locationType: locationType,
        location: location,
        userId: userId,
        homeCountryCode: homeCountryCode,
        hostCountryCode: hostCountryCode,
        onFirstMember: onFirstMember,
        userName: userName,
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
        onFirstMember: onFirstMember,
        userName: userName,
      );
      ids.add(cityId);
    }

    // 5. Sync to Profile if requested (Robustness)
    if (syncToUserProfile && ids.isNotEmpty) {
       try {
         await _firestore.collection('users').doc(userId).update({
           'communityMemberships': cf.FieldValue.arrayUnion(ids),
         });
       } catch (e) {
         // Log but don't fail the whole flow if sync fails, though it's critical
         debugPrint('CommunityService: Error syncing memberships to profile: $e');
       }
    }

    return ids;
  }



  /// Ensures a community exists, creates if not. Returns community ID.
  /// Ensures a community exists, creates if not. Returns community ID.
  Future<String> _ensureCommunity({
    required String type,
    required String locationType,
    required LocationParsed location,
    String? continent,
    required String userId,
    required String homeCountryCode,
    String? hostCountryCode,
    Function(String)? onFirstMember,
    String? userName, // [NEW] For notification
  }) async {
    String? existingCommunityId;
    String? existingCommunityName;

    // 1. [NEW] Check if community exists by Google Place ID (Priority)
    // This allows multiple names for the same physical place to resolve to one community.
    if (location.placeId != null && location.placeId!.isNotEmpty) {
       try {
         final query = await _firestore.collection('communities')
            .where('location.placeId', isEqualTo: location.placeId)
            .where('type', isEqualTo: type)
            .where('locationType', isEqualTo: locationType)
            // Ensure we only match for this specific Diaspora (Home Country)
            .where('homeCountryCode', isEqualTo: (locationType == 'host' || locationType == 'past') ? homeCountryCode : null) 
            .limit(1)
            .get();

         if (query.docs.isNotEmpty) {
           final doc = query.docs.first;
           existingCommunityId = doc.id;
           existingCommunityName = doc.data()['name'] as String?;
           debugPrint('CommunityService: Found existing community by PlaceID: $existingCommunityId');
         }
       } catch (e) {
         debugPrint('CommunityService: Check by PlaceID failed, falling back to ID Gen: $e');
       }
    }

    // 2. Determine Community ID and Name
    final communityId = existingCommunityId ?? generateCommunityId(
      locationType: locationType,
      type: type,
      location: location,
      continent: continent,
      homeCountryCode: (locationType == 'host' || locationType == 'past') ? homeCountryCode : null,
    );
    
    final communityName = existingCommunityName ?? generateCommunityName(
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
          'placeId': location.placeId, // [NEW] Save canonical Place ID
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

      // Notify caller if this is the first member
      if (onFirstMember != null) {
         onFirstMember(communityName);
      }
      
      // [FIX] Add chat to userChats index for the creator/joiner
      final chatId = 'chat_$communityId';
      await _rtdb.ref('userChats/$userId/$chatId').set({
        'chatId': chatId,
        'lastRead': rtdb.ServerValue.timestamp,
        'addedAt': rtdb.ServerValue.timestamp,
      });
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
              data = Map<String, dynamic>.from(mutableData);
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

          // [NEW] Announce to Community (triggers Notification)
          // Only if strictly NEW to the chat
          if (userName != null && userName.isNotEmpty) {
             try {
                final now = DateTime.now().millisecondsSinceEpoch;
                final messageRef = chatRef.child('messages').push();
                
                final systemMessage = {
                  'id': messageRef.key,
                  'chatId': chatId,
                  'senderId': userId,
                  'senderName': userName,
                  'content': 'joined the community',
                  'type': 'system', // or 'join_event'
                  'timestamp': now,
                  'status': 'sent',
                };
                
                await messageRef.set(systemMessage);
                
                // Update Last Message on Chat
                final lastMsg = {
                    'content': '$userName joined the community',
                    'timestamp': now,
                    'senderId': userId,
                    'senderName': userName,
                    'type': 'system',
                    'status': 'sent',
                };
                await chatRef.child('lastMessage').set(lastMsg);
                await chatRef.child('updatedAt').set(now);
                
                // Fan-out to ALL participants (including self, though self logic handles below)
                final allTargetIds = List<String>.from(participants); // Use snapshot participants (others)
                allTargetIds.add(userId); // Add self to be sure
                
                final Map<String, dynamic> updates = {};
                for (final pid in allTargetIds) {
                   updates['userChats/$pid/$chatId/lastMessage'] = lastMsg;
                   updates['userChats/$pid/$chatId/updatedAt'] = now;
                   // Don't overwrite other fields like addedAt/lastRead
                }
                await _rtdb.ref().update(updates);
                
                debugPrint('🔔 Announced new member $userName to $chatId');
             } catch (e) {
                debugPrint('Error announcing new member: $e');
             }
          }
        }
        
        // Add chat to user's userChats index (Backup if fan-out missed or logic above skipped)
        await _rtdb.ref('userChats/$userId/$chatId').update({ // Use update to not wipe lastMessage if fan-out wrote it
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
          
          debugPrint('Pruned empty community: ${doc.id}');
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
  /// Returns a report of { 'success': [], 'failed': [] } keys.
  Future<Map<String, List<String>>> hardResetDatabase({List<String> resetTargets = const ['users', 'communities', 'events', 'organizations', 'radio', 'chats', 'storage', 'points']}) async {
    final List<String> succeeded = [];
    final List<String> failed = [];

    // Helper to track status
    Future<void> tryTarget(String target, Future<void> Function() action) async {
      try {
        await action();
        succeeded.add(target);
      } catch (e) {
        // debugPrint('Error resetting $target: $e');
        failed.add('$target: ${e.toString().split(']').last.trim()}'); // Clean error slightly
      }
    }

    // 1. Delete Collections (Remote)
    if (resetTargets.contains('communities')) await tryTarget('communities', () => _deleteCollection('communities'));
    if (resetTargets.contains('users')) await tryTarget('users', () => _deleteCollection('users')); 
    if (resetTargets.contains('events')) await tryTarget('events', () => _deleteCollection('events'));
    if (resetTargets.contains('organizations')) await tryTarget('organizations', () => _deleteCollection('organizations'));
    if (resetTargets.contains('radio')) await tryTarget('radio', () => _deleteCollection('radio_station_health'));

    if (resetTargets.contains('points')) {
      await tryTarget('points', () async {
        await _deleteCollection('user_points');
        await _deleteCollection('points_transactions');
        await _deleteCollection('referral_codes');
      });
    }
    
    if (resetTargets.contains('feedback')) {
       await tryTarget('feedback', () => _deleteCollection('feedback'));
    }

    // 2. Delete RTDB Paths
    if (resetTargets.contains('chats')) {
       await tryTarget('chats', () async {
         await _rtdb.ref('chats').remove();
         await _rtdb.ref('userChats').remove();
       });
    }
    
    // 3. Delete Storage Folders
    if (resetTargets.contains('storage')) {
      await tryTarget('storage', () async {
        await _deleteStorageFolder('profile_photos');
        await _deleteStorageFolder('community_headers');
      });
    }

    // 4. Clear Local Preferences
    // Only verify preferences if explicitly requested or part of user cleanup
    if (resetTargets.any((t) => ['proximity', 'onboarding', 'users', 'radio'].contains(t))) {
       await tryTarget('local_storage', () async {
         final prefs = await SharedPreferences.getInstance();
         
         if (resetTargets.contains('proximity')) {
            await prefs.remove('last_proximity_notification_time');
         }
         
         if (resetTargets.contains('onboarding')) {
            await prefs.clear(); 
         }
         
         // Original behavior: Full clear safeguard
         if (resetTargets.contains('users') || resetTargets.contains('radio')) {
            await prefs.clear();
         }
       });
    }
    
    return {
      'success': succeeded,
      'failed': failed,
    };
  }

  // Obsolete helper _tryDeleteCollection removed in favor of tryTarget pattern above


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

