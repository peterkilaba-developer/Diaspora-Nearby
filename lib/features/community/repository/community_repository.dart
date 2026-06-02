import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/community/models/community_data.dart';
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

  // ===========================================================================
  // OFFLINE-FIRST METHODS (Firestore Offline Persistence)
  // ===========================================================================

  Stream<List<Community>> watchUserCommunities(String uid) {
    // Direct Firestore watch (works on all platforms)
    // Previously used local Isar cache on native, but that's been removed.
    // Firestore's built-in offline persistence handles local caching.
    syncUserCommunities(uid); // Background sync for any side-effects
    return _firestore
        .collection('communities')
        .where('members', arrayContains: uid)
        .limit(100)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) {
                final data = doc.data();
                try {
                  return Community.fromJson({...data, 'id': doc.id});
                } catch (e) {
                  debugPrint('Error parsing community ${doc.id}: $e');
                  return null;
                }
              })
              .whereType<Community>()
              .toList(),
        );
  }

  Stream<Community?> watchCommunity(String communityId) {
    final communityDoc = _firestore.collection('communities').doc(communityId);
    final metadataStream = communityDoc.snapshots();
    final treasuryStream = communityDoc
        .collection('treasury')
        .doc('current')
        .snapshots();

    return Rx.combineLatest2<DocumentSnapshot, DocumentSnapshot, Community?>(
      metadataStream,
      treasuryStream,
      (metaDoc, treasuryDoc) {
        if (!metaDoc.exists) return null;
        try {
          final metaData = metaDoc.data() as Map<String, dynamic>;
          final treasuryData = treasuryDoc.exists
              ? treasuryDoc.data() as Map<String, dynamic>
              : <String, dynamic>{};

          return Community.fromJson({
            ...metaData,
            ...treasuryData,
            'id': metaDoc.id,
          });
        } catch (e) {
          debugPrint('Error parsing community $communityId: $e');
          return null;
        }
      },
    ).asBroadcastStream();
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
              .snapshots();

          return Rx.combineLatest2<
            DocumentSnapshot,
            DocumentSnapshot,
            Community?
          >(metadataStream, treasuryStream, (metaDoc, treasuryDoc) {
            if (!metaDoc.exists) return null;
            final metaData = metaDoc.data() as Map<String, dynamic>;
            final treasuryData = treasuryDoc.exists
                ? treasuryDoc.data() as Map<String, dynamic>
                : <String, dynamic>{};

            return Community.fromJson({
              ...metaData,
              ...treasuryData,
              'id': metaDoc.id,
            });
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
              .snapshots();

          return Rx.combineLatest2<
            DocumentSnapshot,
            DocumentSnapshot,
            Community?
          >(metadataStream, treasuryStream, (metaDoc, treasuryDoc) {
            if (!metaDoc.exists) return null;
            final metaData = metaDoc.data() as Map<String, dynamic>;
            final treasuryData = treasuryDoc.exists
                ? treasuryDoc.data() as Map<String, dynamic>
                : <String, dynamic>{};

            return Community.fromJson({
              ...metaData,
              ...treasuryData,
              'id': metaDoc.id,
            });
          });
        });
  }

  /// Get communities (direct Firestore query)
  Future<List<Community>> getLocalUserCommunities(String uid) async {
    try {
      final snapshot = await _firestore
          .collection('communities')
          .where('members', arrayContains: uid)
          .limit(100)
          .get();
      return snapshot.docs
          .map((doc) => Community.fromJson({...doc.data(), 'id': doc.id}))
          .toList();
    } catch (e) {
      debugPrint('Error getting user communities: $e');
      return [];
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
        return Community.fromJson({...data, 'id': doc.id});
      }).toList();

      // No-op: Firestore offline persistence handles local caching automatically

      debugPrint('✅ Synced ${communities.length} communities to local DB');
    } catch (e) {
      debugPrint('❌ Error syncing communities: $e');
    }
  }

  // ===========================================================================
  // HYBRID METHODS (Legacy Support / Migration)
  // ===========================================================================

  /// Get Community (Firestore with offline persistence)
  Future<Community?> getCommunity(String communityId) async {
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
        return Community.fromJson({...doc.data(), 'id': doc.id});
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
        // No-op: Firestore offline persistence handles caching
        return community;
      }
    } catch (e) {
      debugPrint('Error fetching community: $e');
    }
    return null;
  }

  // ===========================================================================
  // WRITE METHODS (Ideally invalidates cache or optimistic updates)
  // ===========================================================================

  // [REMOVED] joinOrCreateCommunity - Use CommunityService for hierarchy-based creation

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  // Backwards compatibility for existing FutureProvider calls
  Future<List<Community>> getUserCommunities(String uid) async {
    // Trigger sync
    syncUserCommunities(uid);
    // Return local immediately (stale but fast)
    return getLocalUserCommunities(uid);
  }

  Future<List<Community>> getAllCommunities() async {
    // This might be heavy, but let's just fetch from firestore for now as it's rarely used
    // Or implement syncAllCommunities()
    try {
      final snapshot = await _firestore
          .collection('communities')
          .limit(500)
          .get();
      final list = snapshot.docs
          .map((doc) => Community.fromJson({...doc.data(), 'id': doc.id}))
          .toList();
      // No-op: Firestore offline persistence handles caching
      return list;
    } catch (e) {
      return [];
    }
  }

  /// [NEW] Gets all child communities of a given parent community for hierarchical governance.
  Future<List<Community>> getChildCommunities(Community parent) async {
    Query query = _firestore.collection('communities');

    if (parent.id == 'global_community') {
      // Children of Global are Continents
      query = query.where('type', isEqualTo: 'continent');
    } else if (parent.type == 'continent') {
      // Children of Continent are Countries
      // Note: We'd need to filter by continent in Firestore which requires a field
      // For now, fetch all countries and filter in Dart if continent mapping is available
      final snapshot = await query
          .where('type', isEqualTo: 'country')
          .limit(200)
          .get();
      // Filter by continent (Logic would use LocationUtils mapping)
      return snapshot.docs
          .map(
            (doc) => Community.fromJson({
              ...doc.data() as Map<String, dynamic>,
              'id': doc.id,
            }),
          )
          .toList();
    } else if (parent.type == 'country') {
      // Children of Country are States or Cities
      // If 3-tier: States. If 2-tier: Cities.
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

      // If any states exist, they are the direct children.
      final states = results.where((c) => c.type == 'state').toList();
      if (states.isNotEmpty) return states;

      // Otherwise cities are direct children
      return results.where((c) => c.type == 'city').toList();
    } else if (parent.type == 'state') {
      // Children of State are Cities
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

      // Filter by state field in location map
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
    try {
      // Basic search: Fetch recent/active ones.
      // Ideally we'd have a 'searchable' index, but for now fetch all or a subset.
      final snapshot = await _firestore
          .collection('communities')
          .limit(50)
          .get();

      return snapshot.docs
          .map((doc) {
            final data = doc.data();
            return Community.fromJson({...data, 'id': doc.id});
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
