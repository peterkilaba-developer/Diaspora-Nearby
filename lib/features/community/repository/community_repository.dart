import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/community/models/community_data.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:rxdart/rxdart.dart';

final communityRepositoryProvider = Provider((ref) => CommunityRepository());

final communityProvider = StreamProvider.family<Community?, String>((
  ref,
  communityId,
) {
  return ref.watch(communityRepositoryProvider).watchCommunity(communityId);
});

final userCommunitiesStreamProvider =
    StreamProvider.family<List<Community>, String>((ref, uid) {
      return ref.watch(communityRepositoryProvider).watchUserCommunities(uid);
    });

final homeCountryCommunityProvider = StreamProvider.family<Community?, String>((
  ref,
  countryCode,
) {
  return ref
      .watch(communityRepositoryProvider)
      .watchHomeCountryCommunity(countryCode);
});

final homeContinentCommunityProvider =
    StreamProvider.family<Community?, String>((ref, continentName) {
      return ref
          .watch(communityRepositoryProvider)
          .watchHomeContinentCommunity(continentName);
    });

class CommunityRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final Map<String, Community> _communityCache = {};
  static final Map<String, List<Community>> _userCommunitiesCache = {};
  static List<Community>? _allCommunitiesCache;
  static final Map<String, List<ProfileData>> _communityMembersCache = {};

  Community? getCachedCommunity(String communityId) =>
      _communityCache[communityId];

  void cacheCommunity(Community community) {
    _communityCache[community.id] = community;
  }

  List<Community>? getCachedUserCommunities(String uid) =>
      _userCommunitiesCache[uid];

  List<Community>? getCachedAllCommunities() => _allCommunitiesCache;

  List<ProfileData>? getCachedCommunityMembers(String communityId) =>
      _communityMembersCache[communityId];

  void cacheCommunityMembers(String communityId, List<ProfileData> members) {
    _communityMembersCache[communityId] = members;
  }

  // ===========================================================================
  // OFFLINE-FIRST METHODS (Firestore Offline Persistence)
  // ===========================================================================

  Stream<List<Community>> watchUserCommunities(String uid) {
    unawaited(syncUserCommunities(uid));
    return Stream<List<Community>>.multi((controller) {
      controller.addSync(_userCommunitiesCache[uid] ?? const <Community>[]);
      final sub = _firestore
          .collection('communities')
          .where('members', arrayContains: uid)
          .limit(100)
          .snapshots()
          .listen(
            (snapshot) {
              final list = snapshot.docs
                  .map((doc) {
                    final data = doc.data();
                    try {
                      final comm = Community.fromJson({...data, 'id': doc.id});
                      _communityCache[doc.id] = comm;
                      return comm;
                    } catch (e) {
                      debugPrint('Error parsing community ${doc.id}: $e');
                      return null;
                    }
                  })
                  .whereType<Community>()
                  .toList();
              _userCommunitiesCache[uid] = list;
              if (!controller.isClosed) {
                controller.add(list);
              }
            },
            onError: (_) {
              if (!controller.isClosed) {
                controller.add(_userCommunitiesCache[uid] ?? const <Community>[]);
              }
            },
          );
      controller.onCancel = sub.cancel;
    });
  }

  Stream<Community?> watchCommunity(String communityId) {
    final communityDoc = _firestore.collection('communities').doc(communityId);
    final metadataStream = communityDoc.snapshots();
    final treasuryStream = communityDoc
        .collection('treasury')
        .doc('current')
        .snapshots()
        .cast<DocumentSnapshot<Map<String, dynamic>>?>()
        .startWith(null);

    final combinedStream = Rx.combineLatest2<
      DocumentSnapshot<Map<String, dynamic>>,
      DocumentSnapshot<Map<String, dynamic>>?,
      Community?
    >(
      metadataStream,
      treasuryStream,
      (metaDoc, treasuryDoc) {
        if (!metaDoc.exists) return null;
        try {
          final metaData = metaDoc.data() ?? <String, dynamic>{};
          final treasuryData = (treasuryDoc != null && treasuryDoc.exists)
              ? (treasuryDoc.data() ?? <String, dynamic>{})
              : <String, dynamic>{};

          final comm = Community.fromJson({
            ...metaData,
            ...treasuryData,
            'id': metaDoc.id,
          });
          _communityCache[communityId] = comm;
          return comm;
        } catch (e) {
          debugPrint('Error parsing community $communityId: $e');
          return _communityCache[communityId];
        }
      },
    ).onErrorReturn(_communityCache[communityId]);

    return Stream<Community?>.multi((controller) {
      controller.addSync(_communityCache[communityId]);
      final sub = combinedStream.listen(
        (comm) {
          if (!controller.isClosed) {
            controller.add(comm);
          }
        },
        onError: (_) {
          if (!controller.isClosed) {
            controller.add(_communityCache[communityId]);
          }
        },
      );
      controller.onCancel = sub.cancel;
    }, isBroadcast: true);
  }

  Stream<Community?> watchHomeCountryCommunity(String countryCode) {
    return _firestore
        .collection('communities')
        .where('locationType', isEqualTo: 'home')
        .where('homeCountryCode', isEqualTo: countryCode)
        .where('type', isEqualTo: 'country')
        .limit(1)
        .snapshots()
        .switchMap((snapshot) {
          if (snapshot.docs.isEmpty) return Stream.value(null);

          final communityDoc = snapshot.docs.first.reference;
          final metadataStream = snapshot.docs.first.reference.snapshots();
          final treasuryStream = communityDoc
              .collection('treasury')
              .doc('current')
              .snapshots()
              .cast<DocumentSnapshot<Map<String, dynamic>>?>()
              .startWith(null);

          return Rx.combineLatest2<
            DocumentSnapshot<Map<String, dynamic>>,
            DocumentSnapshot<Map<String, dynamic>>?,
            Community?
          >(metadataStream, treasuryStream, (metaDoc, treasuryDoc) {
            if (!metaDoc.exists) return null;
            final metaData = metaDoc.data() ?? <String, dynamic>{};
            final treasuryData = (treasuryDoc != null && treasuryDoc.exists)
                ? (treasuryDoc.data() ?? <String, dynamic>{})
                : <String, dynamic>{};

            final comm = Community.fromJson({
              ...metaData,
              ...treasuryData,
              'id': metaDoc.id,
            });
            _communityCache[metaDoc.id] = comm;
            return comm;
          });
        });
  }

  Stream<Community?> watchHomeContinentCommunity(String continentName) {
    return _firestore
        .collection('communities')
        .where('locationType', isEqualTo: 'home')
        .where('type', isEqualTo: 'continent')
        .where('continent', isEqualTo: continentName)
        .limit(1)
        .snapshots()
        .switchMap((snapshot) {
          if (snapshot.docs.isEmpty) return Stream.value(null);

          final communityDoc = snapshot.docs.first.reference;
          final metadataStream = snapshot.docs.first.reference.snapshots();
          final treasuryStream = communityDoc
              .collection('treasury')
              .doc('current')
              .snapshots()
              .cast<DocumentSnapshot<Map<String, dynamic>>?>()
              .startWith(null);

          return Rx.combineLatest2<
            DocumentSnapshot<Map<String, dynamic>>,
            DocumentSnapshot<Map<String, dynamic>>?,
            Community?
          >(metadataStream, treasuryStream, (metaDoc, treasuryDoc) {
            if (!metaDoc.exists) return null;
            final metaData = metaDoc.data() ?? <String, dynamic>{};
            final treasuryData = (treasuryDoc != null && treasuryDoc.exists)
                ? (treasuryDoc.data() ?? <String, dynamic>{})
                : <String, dynamic>{};

            final comm = Community.fromJson({
              ...metaData,
              ...treasuryData,
              'id': metaDoc.id,
            });
            _communityCache[metaDoc.id] = comm;
            return comm;
          });
        });
  }

  /// Get communities (direct Firestore query)
  Future<List<Community>> getLocalUserCommunities(String uid) async {
    final cached = _userCommunitiesCache[uid];
    if (cached != null && cached.isNotEmpty) {
      unawaited(syncUserCommunities(uid));
      return cached;
    }
    try {
      final snapshot = await _firestore
          .collection('communities')
          .where('members', arrayContains: uid)
          .limit(100)
          .get();
      final list = snapshot.docs.map((doc) {
        final comm = Community.fromJson({...doc.data(), 'id': doc.id});
        _communityCache[doc.id] = comm;
        return comm;
      }).toList();
      _userCommunitiesCache[uid] = list;
      return list;
    } catch (e) {
      debugPrint('Error getting user communities: $e');
      return _userCommunitiesCache[uid] ?? [];
    }
  }

  /// Sync User Communities (Remote -> Local)
  /// Call this when the app starts, or on pull-to-refresh.
  Future<void> syncUserCommunities(String uid) async {
    try {
      final membersQuery = await _firestore
          .collection('communities')
          .where('members', arrayContains: uid)
          .limit(100)
          .get();

      final communities = membersQuery.docs.map((doc) {
        final data = doc.data();
        final comm = Community.fromJson({...data, 'id': doc.id});
        _communityCache[doc.id] = comm;
        return comm;
      }).toList();

      _userCommunitiesCache[uid] = communities;

      debugPrint('✅ Synced ${communities.length} communities to local DB');
    } catch (e) {
      debugPrint('❌ Error syncing communities: $e');
    }
  }

  // ===========================================================================
  // HYBRID METHODS (Legacy Support / Migration)
  // ===========================================================================

  /// Get Community (In-memory cache + Firestore with offline persistence)
  Future<Community?> getCommunity(String communityId) async {
    final cached = _communityCache[communityId];
    if (cached != null) {
      unawaited(_fetchAndSaveCommunity(communityId));
      return cached;
    }
    return await _fetchAndSaveCommunity(communityId);
  }

  Future<Community?> getHomeCountryCommunity(String countryCode) async {
    try {
      final snapshot = await _firestore
          .collection('communities')
          .where('locationType', isEqualTo: 'home')
          .where('homeCountryCode', isEqualTo: countryCode)
          .where('type', isEqualTo: 'country')
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        final comm = Community.fromJson({...doc.data(), 'id': doc.id});
        _communityCache[doc.id] = comm;
        return comm;
      }
    } catch (e) {
      debugPrint('Error getting home country community: $e');
    }
    return null;
  }

  Future<Community?> _fetchAndSaveCommunity(String communityId) async {
    try {
      final doc = await _firestore
          .collection('communities')
          .doc(communityId)
          .get();
      if (doc.exists) {
        final community = Community.fromJson({
          ...doc.data() as Map<String, dynamic>,
          'id': doc.id,
        });
        _communityCache[communityId] = community;
        return community;
      }
    } catch (e) {
      debugPrint('Error fetching community: $e');
      return _communityCache[communityId];
    }
    return null;
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  // Backwards compatibility for existing FutureProvider calls
  Future<List<Community>> getUserCommunities(String uid) async {
    final cached = _userCommunitiesCache[uid];
    if (cached != null && cached.isNotEmpty) {
      unawaited(syncUserCommunities(uid));
      return cached;
    }
    unawaited(syncUserCommunities(uid));
    return getLocalUserCommunities(uid);
  }

  Future<List<Community>> getAllCommunities() async {
    if (_allCommunitiesCache != null && _allCommunitiesCache!.isNotEmpty) {
      unawaited(_refreshAllCommunitiesInBackground());
      return _allCommunitiesCache!;
    }
    return _refreshAllCommunitiesInBackground();
  }

  Future<List<Community>> _refreshAllCommunitiesInBackground() async {
    try {
      final snapshot = await _firestore
          .collection('communities')
          .limit(500)
          .get();
      final list = snapshot.docs.map((doc) {
        final comm = Community.fromJson({...doc.data(), 'id': doc.id});
        _communityCache[doc.id] = comm;
        return comm;
      }).toList();
      _allCommunitiesCache = list;
      return list;
    } catch (e) {
      return _allCommunitiesCache ?? [];
    }
  }

  /// [NEW] Gets all child communities of a given parent community for hierarchical governance.
  Future<List<Community>> getChildCommunities(Community parent) async {
    Query query = _firestore.collection('communities');

    if (parent.id == 'global_community') {
      query = query.where('type', isEqualTo: 'continent');
    } else if (parent.type == 'continent') {
      final snapshot = await query
          .where('type', isEqualTo: 'country')
          .limit(200)
          .get();
      return snapshot.docs
          .map(
            (doc) => Community.fromJson({
              ...doc.data() as Map<String, dynamic>,
              'id': doc.id,
            }),
          )
          .toList();
    } else if (parent.type == 'country') {
      final snapshot = await query
          .where('homeCountryCode', isEqualTo: parent.homeCountryCode)
          .where('type', whereIn: ['state', 'city'])
          .limit(200)
          .get();

      final results = snapshot.docs
          .map(
            (doc) => Community.fromJson({
              ...doc.data() as Map<String, dynamic>,
              'id': doc.id,
            }),
          )
          .toList();

      final states = results.where((c) => c.type == 'state').toList();
      if (states.isNotEmpty) return states;

      return results.where((c) => c.type == 'city').toList();
    } else if (parent.type == 'state') {
      final snapshot = await query
          .where('homeCountryCode', isEqualTo: parent.homeCountryCode)
          .where('type', isEqualTo: 'city')
          .limit(200)
          .get();

      final results = snapshot.docs
          .map(
            (doc) => Community.fromJson({
              ...doc.data() as Map<String, dynamic>,
              'id': doc.id,
            }),
          )
          .toList();

      final parentState = (parent.location?['state'] as String?)?.toLowerCase();
      return results.where((c) {
        final cityState = (c.location?['state'] as String?)?.toLowerCase();
        return cityState == parentState;
      }).toList();
    }

    return [];
  }

  /// [NEW] Search for communities by name or description
  Future<List<Community>> searchCommunities(String query) async {
    final queryLower = query.toLowerCase();
    final cached = _allCommunitiesCache ?? _communityCache.values.toList();
    if (cached.isNotEmpty) {
      unawaited(_refreshAllCommunitiesInBackground());
      return cached.where((community) {
        if (query.isEmpty) return true;
        return community.name.toLowerCase().contains(queryLower);
      }).toList();
    }
    try {
      final snapshot = await _firestore
          .collection('communities')
          .limit(50)
          .get();

      return snapshot.docs
          .map((doc) {
            final data = doc.data();
            final comm = Community.fromJson({...data, 'id': doc.id});
            _communityCache[doc.id] = comm;
            return comm;
          })
          .where((community) {
            if (query.isEmpty) return true;
            return community.name.toLowerCase().contains(queryLower);
          })
          .toList();
    } catch (e) {
      debugPrint('Error searching communities: $e');
      return [];
    }
  }
}
