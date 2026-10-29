import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/core/utils/location_utils.dart'
    as location_utils;
import 'package:diaspora_nearby/core/data/countries.dart' as country_data;
import 'package:diaspora_nearby/features/community/models/community_data.dart';

final communityServiceProvider = Provider<CommunityService>((ref) {
  return CommunityService(ref);
});

/// CommunityService handles community and chat creation during user registration.
class CommunityService {
  final cf.FirebaseFirestore _firestore = cf.FirebaseFirestore.instance;
  final Ref? _ref;

  CommunityService([this._ref]);

  /// Searches for communities matching the query string (e.g., country name).
  Future<List<Community>> searchCommunities(String query) async {
    try {
      final snapshot = await _firestore
          .collection('communities')
          .where('location.country', isEqualTo: query)
          .limit(50)
          .get();

      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs
            .map((doc) => Community.fromJson(doc.data()..['id'] = doc.id))
            .toList();
      }

      final nameSnapshot = await _firestore
          .collection('communities')
          .where('name', isGreaterThanOrEqualTo: query)
          .where('name', isLessThan: '${query}z')
          .limit(50)
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
    if (profile.uid == null || profile.uid!.isEmpty) {
      return [];
    }

    if (profile.homeCountryCode == null || profile.homeCountryCode!.isEmpty) {
      return [];
    }

    final userId = profile.uid!;
    final homeCountryCode = profile.homeCountryCode!.trim().toUpperCase();
    final hostCountryCode = (profile.hostCountryCode ?? 'XX')
        .trim()
        .toUpperCase();
    final userName = profile.fullName;

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

    final List<String> communityIds = [];
    final List<String> chatIds = [];

    // =========================================================================
    // FAST PATH: Parallel Server-Side Batch Provisioning + Corridor Chamber
    // =========================================================================
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final provisionFuture = functions
          .httpsCallable('provisionSignupCommunities')
          .call<Map<String, dynamic>>({
            'homeLocation': {
              'city': homeParsed.city,
              'state': homeParsed.state,
              'country': homeParsed.country,
              'countryCode': homeCountryCode,
              'placeId': homeParsed.placeId,
            },
            'hostLocation': {
              'city': hostParsed.city,
              'state': hostParsed.state,
              'country': hostParsed.country,
              'countryCode': hostCountryCode,
              'placeId': hostParsed.placeId,
            },
            'homeCountryCode': homeCountryCode,
            'hostCountryCode': hostCountryCode,
          });

      final Future<HttpsCallableResult<Map<String, dynamic>>?> chamberFuture =
          (_ref != null &&
              hostCountryCode != 'XX' &&
              homeCountryCode != hostCountryCode)
          ? functions
                .httpsCallable('ensureSignupChamber')
                .call<Map<String, dynamic>>()
                .then<HttpsCallableResult<Map<String, dynamic>>?>((r) => r)
                .catchError((e) {
                  debugPrint('⚠️ ensureCorridorChamber failed: $e');
                  return null;
                })
          : Future<HttpsCallableResult<Map<String, dynamic>>?>.value(null);

      final results = await Future.wait([provisionFuture, chamberFuture]);
      final result = results[0]!;
      final chamberResult = results[1];

      final commIds = List<String>.from(result.data['communityIds'] ?? []);
      final cIds = List<String>.from(result.data['chatIds'] ?? []);
      if (commIds.isNotEmpty) {
        communityIds.addAll(commIds);
        chatIds.addAll(cIds);

        final chamberChatId = chamberResult?.data['chatId'] as String?;
        if (chamberChatId != null) {
          chatIds.add(chamberChatId);
        }

        await _batchUpdateUserChatsIndex(userId, chatIds);
        return communityIds;
      }
    } catch (e) {
      debugPrint(
        '⚠️ Fast batch provisioning failed, falling back to parallel tier provisioning: $e',
      );
    }

    // =========================================================================
    // RESILIENT FALLBACK: Parallel Tier Provisioning
    // =========================================================================
    final globalFuture = () async {
      try {
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
        return <String>[globalId];
      } catch (e) {
        debugPrint('⚠️ ensure global community failed: $e');
        return <String>['global_community'];
      }
    }();

    final homeFuture = ensureCommunitiesForLocationHierarchy(
      location: homeParsed,
      locationType: 'home',
      userId: userId,
      homeCountryCode: homeCountryCode,
      hostCountryCode: null,
      onFirstMember: onFirstMember,
      userName: userName,
    );

    final hostFuture = ensureCommunitiesForLocationHierarchy(
      location: hostParsed,
      locationType: 'host',
      userId: userId,
      homeCountryCode: homeCountryCode,
      hostCountryCode: hostCountryCode,
      onFirstMember: onFirstMember,
      userName: userName,
    );

    final chamberFallbackFuture = () async {
      if (_ref != null &&
          hostCountryCode != 'XX' &&
          homeCountryCode != hostCountryCode) {
        try {
          final result = await FirebaseFunctions.instanceFor(
            region: 'us-central1',
          ).httpsCallable('ensureSignupChamber').call<Map<String, dynamic>>();
          return result.data['chatId'] as String?;
        } catch (e) {
          debugPrint('⚠️ ensureCorridorChamber failed: $e');
        }
      }
      return null;
    }();

    final fallbackResults = await Future.wait([
      globalFuture,
      homeFuture,
      hostFuture,
      chamberFallbackFuture,
    ]);

    for (final list in [
      fallbackResults[0] as List<String>,
      fallbackResults[1] as List<String>,
      fallbackResults[2] as List<String>,
    ]) {
      for (final id in list) {
        if (!communityIds.contains(id)) {
          communityIds.add(id);
          chatIds.add('chat_$id');
        }
      }
    }

    final chamberChatId = fallbackResults[3] as String?;
    if (chamberChatId != null && !chatIds.contains(chamberChatId)) {
      chatIds.add(chamberChatId);
    }

    try {
      await _batchUpdateUserChatsIndex(userId, chatIds);
    } catch (e) {
      debugPrint('⚠️ _batchUpdateUserChatsIndex warning: $e');
    }

    return communityIds;
  }

  /// Ensures communities exist for a full location hierarchy (Continent -> Country -> State -> City) in parallel.
  Future<List<String>> ensureCommunitiesForLocationHierarchy({
    required location_utils.LocationParsed location,
    required String locationType,
    required String userId,
    required String homeCountryCode,
    String? hostCountryCode,
    bool syncToUserProfile = false,
    Function(String)? onFirstMember,
    String? userName,
  }) async {
    final countryCode = locationType == 'home'
        ? homeCountryCode
        : (hostCountryCode ?? location.countryCode);

    final continent = location_utils.getContinentByCountryCode(countryCode);
    final continentName = location_utils.getContinentName(continent);

    final List<Future<String?>> tierFutures = [];

    // 1. Continent
    tierFutures.add(
      _ensureCommunity(
        type: 'continent',
        locationType: locationType,
        location: location,
        continent: continentName,
        userId: userId,
        homeCountryCode: homeCountryCode,
        hostCountryCode: hostCountryCode,
        onFirstMember: onFirstMember,
        userName: userName,
      ).then<String?>((v) => v).catchError((e) {
        debugPrint('⚠️ ensureCommunity continent failed: $e');
        return null;
      }),
    );

    // 2. Country
    tierFutures.add(
      _ensureCommunity(
        type: 'country',
        locationType: locationType,
        location: location,
        userId: userId,
        homeCountryCode: homeCountryCode,
        hostCountryCode: hostCountryCode,
        onFirstMember: onFirstMember,
        userName: userName,
      ).then<String?>((v) => v).catchError((e) {
        debugPrint('⚠️ ensureCommunity country failed: $e');
        return null;
      }),
    );

    // 3. State (only for 3-level countries)
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
      tierFutures.add(
        _ensureCommunity(
          type: 'state',
          locationType: locationType,
          location: location,
          userId: userId,
          homeCountryCode: homeCountryCode,
          hostCountryCode: hostCountryCode,
          onFirstMember: onFirstMember,
          userName: userName,
        ).then<String?>((v) => v).catchError((e) {
          debugPrint('⚠️ ensureCommunity state failed: $e');
          return null;
        }),
      );
    }

    // 4. City
    if (location.city != null && location.city!.isNotEmpty) {
      tierFutures.add(
        _ensureCommunity(
          type: 'city',
          locationType: locationType,
          location: location,
          userId: userId,
          homeCountryCode: homeCountryCode,
          hostCountryCode: hostCountryCode,
          onFirstMember: onFirstMember,
          userName: userName,
        ).then<String?>((v) => v).catchError((e) {
          debugPrint('⚠️ ensureCommunity city failed: $e');
          return null;
        }),
      );
    }

    // 5. Bilateral Country Community
    if (locationType != 'home' &&
        countryCode.isNotEmpty &&
        countryCode != 'XX' &&
        homeCountryCode.isNotEmpty &&
        homeCountryCode != 'XX' &&
        countryCode.toUpperCase() != homeCountryCode.toUpperCase()) {
      tierFutures.add(
        _ensureCommunity(
          type: 'country',
          locationType: 'bilateral',
          location: location,
          userId: userId,
          homeCountryCode: homeCountryCode,
          hostCountryCode: countryCode,
          onFirstMember: onFirstMember,
          userName: userName,
        ).then<String?>((v) => v).catchError((e) {
          debugPrint('⚠️ ensureCommunity bilateral failed: $e');
          return null;
        }),
      );
    }

    final resolved = await Future.wait(tierFutures);
    final ids = resolved.whereType<String>().toList();

    if (syncToUserProfile && ids.isNotEmpty) {
      try {
        await Future.wait([
          _firestore.collection('users').doc(userId).set({
            'communityMemberships': cf.FieldValue.arrayUnion(ids),
          }, cf.SetOptions(merge: true)),
          _batchUpdateUserChatsIndex(
            userId,
            ids.map((id) => 'chat_$id').toList(),
          ),
        ]);
      } catch (e) {
        debugPrint('⚠️ Error syncing community memberships to profile: $e');
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
    String? userName,
  }) async {
    final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('ensureCommunity')
        .call<Map<String, dynamic>>({
          'type': type,
          'locationType': locationType,
          'location': {
            'city': location.city,
            'state': location.state,
            'country': location.country,
            'countryCode': location.countryCode,
            'placeId': location.placeId,
          },
          'homeCountryCode': homeCountryCode,
          'hostCountryCode': hostCountryCode,
        });
    final communityId = result.data['communityId'] as String;
    if (result.data['created'] == true && onFirstMember != null) {
      onFirstMember(result.data['name'] as String? ?? communityId);
    }
    return communityId;
  }

  /// internal cleanup: Removes communities with 0 members using a WriteBatch.
  Future<void> pruneEmptyCommunities() async {
    final snapshot = await _firestore
        .collection('communities')
        .limit(500)
        .get();

    final batch = _firestore.batch();
    var opCount = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final memberCount = data['memberCount'] as int? ?? 0;
      final memberIds = List.from(data['members'] ?? data['memberIds'] ?? []);

      if (memberCount == 0 || memberIds.isEmpty) {
        batch.delete(doc.reference);
        opCount++;

        final chatId = data['chatId'] as String?;
        if (chatId != null) {
          batch.delete(_firestore.collection('chats').doc(chatId));
          opCount++;
        }

        debugPrint('Pruned empty community: ${doc.id}');
      }
    }

    final gbRef = _firestore.collection('communities').doc('home_country_GB');
    batch.delete(gbRef);
    batch.delete(_firestore.collection('chats').doc('chat_home_country_GB'));
    opCount += 2;

    if (opCount > 0) {
      await batch.commit();
    }
  }

  /// HARD RESET DATABASE
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

        if (resetTargets.contains('users') || resetTargets.contains('radio')) {
          await prefs.clear();
        }
      });
    }

    return {'success': succeeded, 'failed': failed};
  }

  /// Batch updates userChats index for all community chats (Firestore).
  Future<void> _batchUpdateUserChatsIndex(
    String userId,
    List<String> chatIds,
  ) async {
    if (chatIds.isEmpty) return;

    final batch = _firestore.batch();

    for (final chatId in chatIds) {
      final userChatRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('userChats')
          .doc(chatId);
      batch.set(userChatRef, {
        'chatId': chatId,
        'isDeleted': false,
      }, cf.SetOptions(merge: true));
    }

    await batch.commit();
  }

  /// Broadcasts a bereavement announcement to relevant community chats using a single WriteBatch.
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

    final homeCommunityId = 'home_${homeCountryCode}_country';
    targetChatIds.add('chat_$homeCommunityId');

    if (hostCountryCode != null && hostCity != null && hostCity.isNotEmpty) {
      try {
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

    final now = DateTime.now().millisecondsSinceEpoch;
    final content =
        '🕯️ Bereavement Announcement\n\nIt is with a heavy heart that I announce the passing of my $relationship, $deceasedName.\n\nWe appreciate the community\'s support during this difficult time.';

    try {
      final batch = _firestore.batch();
      for (final chatId in targetChatIds) {
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

        batch.set(messageRef, messageData);

        final lastMsg = {
          'content': 'Bereavement Announcement: $deceasedName',
          'timestamp': now,
          'senderId': userId,
          'senderName': userName,
          'type': 'text',
          'status': 'sent',
        };

        batch.update(_firestore.collection('chats').doc(chatId), {
          'lastMessage': lastMsg,
          'updatedAt': now,
        });
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Error broadcasting bereavement announcement: $e');
    }
  }
}
