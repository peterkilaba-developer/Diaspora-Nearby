import 'package:cloud_firestore/cloud_firestore.dart' as cf;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart'; // [NEW]
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/core/utils/location_utils.dart'
    as location_utils;
import 'package:diaspora_nearby/core/data/countries.dart' as country_data;

import 'package:diaspora_nearby/features/community/models/community_data.dart';

final communityServiceProvider = Provider<CommunityService>((ref) {
  return CommunityService();
});

/// CommunityService handles community and chat creation during user registration.
class CommunityService {
  final cf.FirebaseFirestore _firestore = cf.FirebaseFirestore.instance;

  /// Searches for communities matching the query string (e.g., country name).
  Future<List<Community>> searchCommunities(String query) async {
    try {
      final snapshot = await _firestore
          .collection('communities')
          .where(
            'location.country',
            isEqualTo: query,
          ) // More precise than name if possible
          .get();

      // Fallback to name search if country search yields nothing?
      // User passes 'Nigeria', assume it's country name.
      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs
            .map((doc) => Community.fromJson(doc.data()..['id'] = doc.id))
            .toList();
      }

      // Try name search
      final nameSnapshot = await _firestore
          .collection('communities')
          .where('name', isGreaterThanOrEqualTo: query)
          .where('name', isLessThan: '${query}z')
          .get();

      return nameSnapshot.docs
          .map((doc) => Community.fromJson(doc.data()..['id'] = doc.id))
          .toList();
    } catch (e) {
      debugPrint('Error searching communities: $e');
      return [];
    }
  }

  /// Main entry point: creates all communities and chats for a new user.
  /// Mirrors React's `assignUserToCommunities()` function.
  Future<List<String>> createCommunitiesAndChats(
    ProfileData profile, {
    Function(String)? onFirstMember,
  }) async {
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
    final homeParsed = location_utils.LocationParsed(
      city: profile.homeLocation.city,
      state: profile.homeLocation.state,
      country: profile.homeCountry ?? profile.homeLocation.country ?? '',
      countryCode: homeCountryCode,
      placeId: profile.homeLocation.placeId,
    );

    final hostParsed = location_utils.LocationParsed(
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
    required location_utils.LocationParsed location,
    required String locationType,
    required String userId,
    required String homeCountryCode,
    String? hostCountryCode,
    bool syncToUserProfile = false, // [NEW] Option to auto-sync to profile
    Function(String)? onFirstMember,
    String? userName, // [NEW] For notification
  }) async {
    final List<String> ids = [];
    final countryCode = locationType == 'home'
        ? homeCountryCode
        : (hostCountryCode ?? location.countryCode);

    // Get continent
    final continent = location_utils.getContinentByCountryCode(countryCode);
    final continentName = location_utils.getContinentName(continent);

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
      if (location.city != null &&
          directControlled.any((c) => location.city!.contains(c))) {
        skipState = true;
      }
    }

    if (!skipState &&
        location.state != null &&
        location.state!.isNotEmpty &&
        country_data.hasStateLevelHierarchyFromData(countryCode)) {
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
        debugPrint(
          'CommunityService: Error syncing memberships to profile: $e',
        );
      }
    }

    return ids;
  }

  /// Ensures a community exists, creates if not. Returns community ID.
  Future<String> _ensureCommunity({
    required String type,
    required String locationType,
    required location_utils.LocationParsed location,
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
        final query = await _firestore
            .collection('communities')
            .where('location.placeId', isEqualTo: location.placeId)
            .where('type', isEqualTo: type)
            .where('locationType', isEqualTo: locationType)
            // Ensure we only match for this specific Diaspora (Home Country)
            // [FIX] Always use the actual homeCountryCode for PlaceID dedup.
            // Previously, home communities passed `null` which never matched
            // stored docs (they always have the real country code), breaking
            // PlaceID-based deduplication for home communities.
            .where('homeCountryCode', isEqualTo: homeCountryCode)
            .limit(1)
            .get();

        if (query.docs.isNotEmpty) {
          final doc = query.docs.first;
          existingCommunityId = doc.id;
          existingCommunityName = doc.data()['name'] as String?;
          debugPrint(
            'CommunityService: Found existing community by PlaceID: $existingCommunityId',
          );
        }
      } catch (e) {
        debugPrint(
          'CommunityService: Check by PlaceID failed, falling back to ID Gen: $e',
        );
      }
    }

    // 2. Determine Community ID and Name
    final communityId =
        existingCommunityId ??
        location_utils.generateCommunityId(
          locationType: locationType,
          type: type,
          location: location,
          continent: continent,
          homeCountryCode: (locationType == 'host' || locationType == 'past')
              ? homeCountryCode
              : null,
        );

    final communityName =
        existingCommunityName ??
        location_utils.generateCommunityName(
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
        'description': '', // Initialize with empty string
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
        'admins': [userId], // Initialize with creator
        'memberCount': 1,
        'totalMembers': 1,
        'isPrivate': false,
        'chatId': 'chat_$communityId',
        'walletAddress': null, // [UPDATED] Removed mock wallet generation
        'profileImage': '',
        'flag': '',
        'images': [],
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

      // Add chat to userChats index for the creator/joiner
      final chatId = 'chat_$communityId';
      final chatNow = DateTime.now().millisecondsSinceEpoch;
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('userChats')
          .doc(chatId)
          .set({
            'chatId': chatId,
            'lastRead': chatNow,
            'addedAt': chatNow,
          }, cf.SetOptions(merge: true));
    } else {
      // Add member to existing community
      final existingData = docSnapshot.data() as Map<String, dynamic>;
      final existingMemberIds = List<String>.from(
        existingData['members'] ?? existingData['memberIds'] ?? [],
      );

      if (!existingMemberIds.contains(userId)) {
        await docRef.update({
          'members': cf.FieldValue.arrayUnion([userId]),
          'memberCount': cf.FieldValue.increment(1),
          'updatedAt': cf.Timestamp.now(),
        });
      }

      // Get the chatId from the community
      final chatId = existingData['chatId'] as String? ?? 'chat_$communityId';
      final chatDoc = await _firestore.collection('chats').doc(chatId).get();

      if (chatDoc.exists) {
        // Chat exists, add user to participants if not already there
        final chatData = chatDoc.data() ?? {};
        final participants = List<String>.from(chatData['participants'] ?? []);

        if (!participants.contains(userId)) {
          // Use Firestore arrayUnion for atomic participant addition
          await _firestore.collection('chats').doc(chatId).update({
            'participants': cf.FieldValue.arrayUnion([userId]),
            'memberCount': cf.FieldValue.increment(1),
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
          });

          // Announce to Community (triggers Notification)
          if (userName != null && userName.isNotEmpty) {
            try {
              final now = DateTime.now().millisecondsSinceEpoch;
              final messageRef = _firestore
                  .collection('chats')
                  .doc(chatId)
                  .collection('messages')
                  .doc();

              final systemMessage = {
                'id': messageRef.id,
                'chatId': chatId,
                'senderId': userId,
                'senderName': userName,
                'content': 'joined the community',
                'type': 'system',
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
              await _firestore.collection('chats').doc(chatId).update({
                'lastMessage': lastMsg,
                'updatedAt': now,
              });

              // Fan-out to ALL participants' userChats
              final allTargetIds = List<String>.from(participants);
              allTargetIds.add(userId);

              final batch = _firestore.batch();
              for (final pid in allTargetIds) {
                final userChatRef = _firestore
                    .collection('users')
                    .doc(pid)
                    .collection('userChats')
                    .doc(chatId);
                batch.set(userChatRef, {
                  'lastMessage': lastMsg,
                  'updatedAt': now,
                }, cf.SetOptions(merge: true));
              }
              await batch.commit();

              debugPrint('Announced new member $userName to $chatId');
            } catch (e) {
              debugPrint('Error announcing new member: $e');
            }
          }
        }

        // Add chat to user's userChats index
        final nowTs = DateTime.now().millisecondsSinceEpoch;
        await _firestore
            .collection('users')
            .doc(userId)
            .collection('userChats')
            .doc(chatId)
            .set({
              'chatId': chatId,
              'lastRead': nowTs,
              'addedAt': nowTs,
            }, cf.SetOptions(merge: true));
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
        final batchWrite = _firestore.batch();
        final batchNow = DateTime.now().millisecondsSinceEpoch;
        for (final memberId in allMemberIds) {
          final userChatRef = _firestore
              .collection('users')
              .doc(memberId)
              .collection('userChats')
              .doc(chatId);
          batchWrite.set(userChatRef, {
            'chatId': chatId,
            'lastRead': batchNow,
            'addedAt': batchNow,
          }, cf.SetOptions(merge: true));
        }
        await batchWrite.commit();
      }
    }

    return communityId;
  }

  /// Creates a chat in Firestore for a community.
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
    final chatRef = _firestore.collection('chats').doc(chatId);

    final snapshot = await chatRef.get();
    if (snapshot.exists) {
      return; // Chat already exists
    }

    // Chat name is the same as community name
    final String chatName = communityName;
    final now = DateTime.now().millisecondsSinceEpoch;

    await chatRef.set({
      'id': chatId,
      'communityId': communityId,
      'type': 'community', // CRITICAL: must be 'community' not communityType
      'name': chatName,
      'locationType':
          locationType, // CRITICAL: Determines avatar color (home vs host)
      'homeCountryCode': homeCountryCode,
      'hostCountryCode': hostCountryCode,
      'participants': initialParticipants,
      'memberCount': initialParticipants.length,
      'admins': [],
      'createdBy': initialParticipants.isNotEmpty
          ? initialParticipants.first
          : 'system',
      'lastMessage': null,
      'createdAt': now,
      'updatedAt': now,
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
          await _firestore.collection('chats').doc(chatId).delete();
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
      await _firestore.collection('chats').doc('chat_home_country_GB').delete();
    }
  }

  /// HARD RESET DATABASE
  /// Deletes selected collections and services.
  /// [resetTargets] list of keys: 'users', 'communities', 'events', 'organizations', 'radio', 'chats', 'storage'
  /// Returns a report of { 'success': [], 'failed': [] } keys.
  Future<Map<String, List<String>>> hardResetDatabase({
    List<String> resetTargets = const [
      'users',
      'auth',
      'communities',
      'events',
      'organizations',
      'radio',
      'chats',
      'storage',
      'points',
    ],
    String? currentUserId,
  }) async {
    final List<String> succeeded = [];
    final List<String> failed = [];

    // [NEW] Call Cloud Function for Firestore collections
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable('hardResetDatabase');

      final result = await callable.call<Map<String, dynamic>>({
        'resetTargets': resetTargets,
        'currentUserId': currentUserId,
      });

      final data = result.data;
      if (data['success'] != null) {
        succeeded.addAll(List<String>.from(data['success']));
      }
      if (data['failed'] != null) {
        for (final failedItem in data['failed']) {
          failed.add('${failedItem['target']}: ${failedItem['error']}');
        }
      }
    } catch (e) {
      debugPrint('Error calling Cloud Function: $e');
      failed.add('Cloud Function Error: ${e.toString()}');
    }

    // Helper to track status for local operations
    Future<void> tryTarget(
      String target,
      Future<void> Function() action,
    ) async {
      try {
        await action();
        if (!succeeded.contains(target)) {
          succeeded.add(target);
        }
      } catch (e) {
        failed.add('$target: ${e.toString().split(']').last.trim()}');
      }
    }

    // [REMOVED] Client-side Firestore deletion - now handled by Cloud Function
    // [REMOVED] Client-side RTDB deletion - now handled by Cloud Function
    // [REMOVED] Client-side Storage deletion - now handled by Cloud Function

    // 4. Clear Local Preferences
    // Only verify preferences if explicitly requested or part of user cleanup
    if (resetTargets.any(
      (t) => ['proximity', 'onboarding', 'users', 'radio'].contains(t),
    )) {
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

    return {'success': succeeded, 'failed': failed};
  }

  // Obsolete helper _tryDeleteCollection removed in favor of tryTarget pattern above
  // Obsolete helper _deleteCollection removed - now handled by Cloud Function

  // Storage folder deletion now handled by Cloud Function

  /// Batch updates userChats index for all community chats (Firestore).
  Future<void> _batchUpdateUserChatsIndex(
    String userId,
    List<String> chatIds,
  ) async {
    if (chatIds.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = _firestore.batch();

    for (final chatId in chatIds) {
      final userChatRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('userChats')
          .doc(chatId);
      batch.set(userChatRef, {
        'chatId': chatId,
        'lastRead': now,
        'addedAt': now,
      }, cf.SetOptions(merge: true));
    }

    await batch.commit();
  }
  // ... existing methods ...

  /// Broadcasts a bereavement announcement to relevant community chats.
  /// Targets: Home Country Community and Host City Community.
  Future<void> broadcastBereavementAnnouncement({
    required String? userId,
    required String userName,
    required String deceasedName,
    required String relationship,
    required String homeCountryCode,
    String? hostCountryCode,
    String? hostCity,
  }) async {
    if (userId == null) return;

    final List<String> targetChatIds = [];

    // 1. Identify Home Country Community Chat
    // ID format from generateCommunityId: home_{code}_country
    final homeCommunityId = 'home_${homeCountryCode}_country';
    targetChatIds.add('chat_$homeCommunityId');

    // 2. Identify Host City Community Chat (if applicable)
    if (hostCountryCode != null && hostCity != null && hostCity.isNotEmpty) {
      // We need to resolve the Host City Community ID.
      // Since generateCommunityId uses normalized strings, we try to reconstruct it.
      // Or better, we query strictly for the "Host City" community this user is a member of.
      // For simplicity and speed, we'll try to construct the ID if we follow the naming convention strictness,
      // but querying is safer.

      try {
        // Find 'host' 'city' community for this user in this country/city
        final query = await _firestore
            .collection('communities')
            .where('locationType', isEqualTo: 'host')
            .where('type', isEqualTo: 'city')
            .where('hostCountryCode', isEqualTo: hostCountryCode)
            .where('members', arrayContains: userId)
            .limit(1)
            .get();

        if (query.docs.isNotEmpty) {
          final doc = query.docs.first;
          final chatId = doc.data()['chatId'] as String? ?? 'chat_${doc.id}';
          targetChatIds.add(chatId);
        }
      } catch (e) {
        debugPrint('Error finding host city community for broadcast: $e');
      }
    }

    if (targetChatIds.isEmpty) return;

    // 3. Send Message to each target
    final now = DateTime.now().millisecondsSinceEpoch;
    final content =
        'Ã°Å¸â€¢Â¯Ã¯Â¸Â Bereavement Announcement\n\nIt is with a heavy heart that I announce the passing of my $relationship, $deceasedName.\n\nWe appreciate the community\'s support during this difficult time.';

    for (final chatId in targetChatIds) {
      try {
        final messageRef = _firestore
            .collection('chats')
            .doc(chatId)
            .collection('messages')
            .doc();

        final messageData = {
          'id': messageRef.id,
          'chatId': chatId,
          'senderId': userId,
          'senderName': userName,
          'content': content,
          'type': 'text',
          'timestamp': now,
          'status': 'sent',
          'metadata': {
            'isBereavement': true,
            'deceasedName': deceasedName,
            'relationship': relationship,
          },
        };

        await messageRef.set(messageData);

        // Update Last Message
        final lastMsg = {
          'content': 'Bereavement Announcement: $deceasedName',
          'timestamp': now,
          'senderId': userId,
          'senderName': userName,
          'type': 'text',
          'status': 'sent',
        };

        await _firestore.collection('chats').doc(chatId).update({
          'lastMessage': lastMsg,
          'updatedAt': now,
        });

        // We rely on Cloud Functions or client-side fan-out if needed for unread counts.
        // For Community chats, usually the listener handles it.
        // But strict fan-out helper _batchUpdateUserChatsIndex is good if we want to force "unread".
        // We won't do full fan-out here as it's expensive for whole communities.
        // Community chats rely on 'updatedAt' sorting usually.
      } catch (e) {
        debugPrint('Error broadcasting to $chatId: $e');
      }
    }
  }
}
