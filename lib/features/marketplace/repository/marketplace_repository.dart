import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/marketplace/models/marketplace_listing.dart';

final marketplaceRepositoryProvider = Provider<MarketplaceRepository>((ref) {
  return MarketplaceRepository(
    FirebaseFirestore.instance,
    FirebaseFunctions.instance,
  );
});

class MarketplaceRepository {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  MarketplaceRepository(this._firestore, this._functions);

  CollectionReference get _listingsRef =>
      _firestore.collection('marketplace_listings');

  // ─── IN-MEMORY CACHES (0ms synchronous access) ──────────────────────────

  static final Map<String, MarketplaceListing> _listingsByIdCache = {};
  static List<MarketplaceListing> _activeListingsCache = [];
  static final Map<String, List<MarketplaceListing>> _userListingsCache = {};
  static final Set<String> _savedListingIdsCache = {};
  static List<MarketplaceListing> _savedListingsCache = [];

  List<MarketplaceListing> get cachedListings => _activeListingsCache;

  MarketplaceListing? getCachedListing(String id) => _listingsByIdCache[id];

  bool isListingSavedSync(String listingId) =>
      _savedListingIdsCache.contains(listingId);

  List<MarketplaceListing> getCachedSavedListings() => _savedListingsCache;

  List<MarketplaceListing> getCachedUserListings(String userId) {
    final direct = _userListingsCache[userId];
    if (direct != null && direct.isNotEmpty) return direct;
    return _activeListingsCache.where((l) => l.sellerId == userId).toList();
  }

  List<MarketplaceListing> getCachedListings({
    List<String>? communityIds,
    String? category,
    String? scope,
    String? listingType,
  }) {
    Iterable<MarketplaceListing> results = _activeListingsCache.where(
      (l) => l.status == ListingStatus.active,
    );
    if (category != null) {
      results = results.where((l) => l.category == category);
    }
    if (scope != null) {
      results = results.where((l) => l.scope == scope);
    }
    if (listingType != null) {
      results = results.where((l) => l.listingType == listingType);
    }
    if (communityIds != null && communityIds.isNotEmpty) {
      results = results.where((listing) {
        if (listing.communityIds == null || listing.communityIds!.isEmpty) {
          return true;
        }
        return listing.communityIds!.any((cid) => communityIds.contains(cid));
      });
    }
    return results.toList();
  }

  List<MarketplaceListing> searchCachedListings(
    String query, {
    String? category,
    String? scope,
  }) {
    final q = query.trim().toLowerCase();
    return _activeListingsCache.where((l) {
      if (l.status != ListingStatus.active) return false;
      if (category != null && l.category != category) return false;
      if (scope != null && l.scope != scope) return false;
      if (q.isEmpty) return true;
      return l.title.toLowerCase().contains(q) ||
          l.description.toLowerCase().contains(q) ||
          l.category.toLowerCase().contains(q) ||
          (l.subcategory?.toLowerCase().contains(q) ?? false) ||
          (l.sellerCity?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  List<MarketplaceListing> getCachedPartsForVehicle({
    required String make,
    String? model,
  }) {
    final lowerMake = make.toLowerCase();
    final results = _activeListingsCache.where((l) {
      if (l.status != ListingStatus.active) return false;
      if (l.category != MarketplaceCategory.carParts) return false;
      return l.carPartsDetails?['carMake']?.toString().toLowerCase() ==
          lowerMake;
    }).toList();

    if (model != null && model.isNotEmpty) {
      final lowerModel = model.toLowerCase();
      final exact = results
          .where(
            (l) =>
                l.carPartsDetails?['carModel']?.toString().toLowerCase() ==
                lowerModel,
          )
          .toList();
      return exact.isNotEmpty ? exact : results;
    }
    return results;
  }

  List<MarketplaceListing> getCachedVehiclesForPart({
    required String make,
    String? model,
  }) {
    final lowerMake = make.toLowerCase();
    final results = _activeListingsCache.where((l) {
      if (l.status != ListingStatus.active) return false;
      if (l.category != MarketplaceCategory.vehicles) return false;
      return l.vehicleDetails?['make']?.toString().toLowerCase() == lowerMake;
    }).toList();

    if (model != null && model.isNotEmpty) {
      final lowerModel = model.toLowerCase();
      final exact = results
          .where(
            (l) =>
                l.vehicleDetails?['model']?.toString().toLowerCase() ==
                lowerModel,
          )
          .toList();
      return exact.isNotEmpty ? exact : results;
    }
    return results;
  }

  String generateListingId() => _listingsRef.doc().id;

  void cacheListing(MarketplaceListing listing) {
    if (listing.id.isEmpty) return;
    _listingsByIdCache[listing.id] = listing;
    final activeIdx = _activeListingsCache.indexWhere(
      (l) => l.id == listing.id,
    );
    if (listing.status == ListingStatus.active) {
      if (activeIdx >= 0) {
        _activeListingsCache = List<MarketplaceListing>.from(
          _activeListingsCache,
        )..[activeIdx] = listing;
      } else {
        _activeListingsCache = [listing, ..._activeListingsCache];
      }
    } else if (activeIdx >= 0) {
      _activeListingsCache = List<MarketplaceListing>.from(_activeListingsCache)
        ..removeAt(activeIdx);
    }

    final userList = _userListingsCache[listing.sellerId];
    if (userList != null) {
      final uIdx = userList.indexWhere((l) => l.id == listing.id);
      if (uIdx >= 0) {
        _userListingsCache[listing.sellerId] = List<MarketplaceListing>.from(
          userList,
        )..[uIdx] = listing;
      } else {
        _userListingsCache[listing.sellerId] = [listing, ...userList];
      }
    }

    final savedIdx = _savedListingsCache.indexWhere((l) => l.id == listing.id);
    if (savedIdx >= 0) {
      _savedListingsCache = List<MarketplaceListing>.from(_savedListingsCache)
        ..[savedIdx] = listing;
    }
  }

  void removeCachedListing(String listingId) {
    final removed = _listingsByIdCache.remove(listingId);
    _activeListingsCache = _activeListingsCache
        .where((l) => l.id != listingId)
        .toList();
    _savedListingIdsCache.remove(listingId);
    _savedListingsCache = _savedListingsCache
        .where((l) => l.id != listingId)
        .toList();
    if (removed != null && _userListingsCache.containsKey(removed.sellerId)) {
      _userListingsCache[removed.sellerId] =
          _userListingsCache[removed.sellerId]!
              .where((l) => l.id != listingId)
              .toList();
    }
  }

  // ─── READ ───────────────────────────────────────────────────────────────

  /// Stream listings visible to the user's communities
  Stream<List<MarketplaceListing>> getListings({
    List<String>? communityIds,
    String? category,
    String? scope,
    String? listingType,
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) {
    Query query = _listingsRef
        .where('status', isEqualTo: ListingStatus.active)
        .orderBy('createdAt', descending: true);

    if (category != null) {
      query = query.where('category', isEqualTo: category);
    }

    if (scope != null) {
      query = query.where('scope', isEqualTo: scope);
    }

    if (listingType != null) {
      query = query.where('listingType', isEqualTo: listingType);
    }

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    query = query.limit(limit);

    final firestoreStream = query.snapshots().map((snapshot) {
      final listings = snapshot.docs.map((doc) {
        final item = MarketplaceListing.fromMap(
          doc.data() as Map<String, dynamic>,
          doc.id,
        );
        _listingsByIdCache[item.id] = item;
        return item;
      }).toList();

      if (category == null &&
          scope == null &&
          listingType == null &&
          startAfter == null) {
        _activeListingsCache = listings;
      } else {
        final merged = <String, MarketplaceListing>{
          for (final l in _activeListingsCache) l.id: l,
          for (final l in listings) l.id: l,
        };
        _activeListingsCache = merged.values.toList();
      }

      // Filter by community visibility on client side
      if (communityIds != null && communityIds.isNotEmpty) {
        return listings.where((listing) {
          if (listing.communityIds == null || listing.communityIds!.isEmpty) {
            return true;
          }
          return listing.communityIds!.any((cid) => communityIds.contains(cid));
        }).toList();
      }

      return listings;
    });

    return Stream.multi((controller) {
      final cached = getCachedListings(
        communityIds: communityIds,
        category: category,
        scope: scope,
        listingType: listingType,
      );
      if (cached.isNotEmpty) {
        controller.add(cached);
      }
      final sub = firestoreStream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = sub.cancel;
    });
  }

  /// Get a single listing by ID
  Future<MarketplaceListing?> getListingById(String listingId) async {
    try {
      final doc = await _listingsRef.doc(listingId).get();
      if (!doc.exists) return _listingsByIdCache[listingId];
      final listing = MarketplaceListing.fromMap(
        doc.data() as Map<String, dynamic>,
        doc.id,
      );
      cacheListing(listing);
      return listing;
    } catch (e) {
      debugPrint('Error fetching listing: $e');
      return _listingsByIdCache[listingId];
    }
  }

  /// Stream current user's own listings
  Stream<List<MarketplaceListing>> getMyListings(String userId) {
    final firestoreStream = _listingsRef
        .where('sellerId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs.map((doc) {
            final item = MarketplaceListing.fromMap(
              doc.data() as Map<String, dynamic>,
              doc.id,
            );
            _listingsByIdCache[item.id] = item;
            return item;
          }).toList();
          _userListingsCache[userId] = list;
          return list;
        });

    return Stream.multi((controller) {
      final cached = getCachedUserListings(userId);
      if (cached.isNotEmpty) {
        controller.add(cached);
      }
      final sub = firestoreStream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = sub.cancel;
    });
  }

  /// Search listings by title
  Future<List<MarketplaceListing>> searchListings(
    String query, {
    String? category,
    String? scope,
    int limit = 30,
  }) async {
    final lowerQuery = query.toLowerCase();

    Query firestoreQuery = _listingsRef
        .where('status', isEqualTo: ListingStatus.active)
        .where('titleLower', isGreaterThanOrEqualTo: lowerQuery)
        .where('titleLower', isLessThanOrEqualTo: '$lowerQuery\uf8ff')
        .limit(limit);

    final snapshot = await firestoreQuery.get();
    final results = snapshot.docs.map((doc) {
      final item = MarketplaceListing.fromMap(
        doc.data() as Map<String, dynamic>,
        doc.id,
      );
      _listingsByIdCache[item.id] = item;
      return item;
    }).toList();
    return results;
  }

  // ─── VEHICLE ↔ PARTS MATCHING ─────────────────────────────────────────

  /// Find car-parts listings that fit a given vehicle (make + model)
  Future<List<MarketplaceListing>> getPartsForVehicle({
    required String make,
    String? model,
    int limit = 50,
  }) async {
    try {
      Query query = _listingsRef
          .where('status', isEqualTo: ListingStatus.active)
          .where('category', isEqualTo: MarketplaceCategory.carParts)
          .where('carPartsDetails.carMake', isEqualTo: make);

      final snapshot = await query.limit(limit).get();
      final results = snapshot.docs.map((doc) {
        final item = MarketplaceListing.fromMap(
          doc.data() as Map<String, dynamic>,
          doc.id,
        );
        _listingsByIdCache[item.id] = item;
        return item;
      }).toList();

      if (model != null && model.isNotEmpty) {
        final exact = results
            .where(
              (l) =>
                  l.carPartsDetails?['carModel']?.toString().toLowerCase() ==
                  model.toLowerCase(),
            )
            .toList();
        return exact.isNotEmpty ? exact : results;
      }
      return results;
    } catch (e) {
      debugPrint('Error fetching parts for vehicle: $e');
      return getCachedPartsForVehicle(make: make, model: model);
    }
  }

  /// Find vehicle listings that a particular part fits (make + model)
  Future<List<MarketplaceListing>> getVehiclesForPart({
    required String make,
    String? model,
    int limit = 50,
  }) async {
    try {
      Query query = _listingsRef
          .where('status', isEqualTo: ListingStatus.active)
          .where('category', isEqualTo: MarketplaceCategory.vehicles)
          .where('vehicleDetails.make', isEqualTo: make);

      final snapshot = await query.limit(limit).get();
      final results = snapshot.docs.map((doc) {
        final item = MarketplaceListing.fromMap(
          doc.data() as Map<String, dynamic>,
          doc.id,
        );
        _listingsByIdCache[item.id] = item;
        return item;
      }).toList();

      if (model != null && model.isNotEmpty) {
        final exact = results
            .where(
              (l) =>
                  l.vehicleDetails?['model']?.toString().toLowerCase() ==
                  model.toLowerCase(),
            )
            .toList();
        return exact.isNotEmpty ? exact : results;
      }
      return results;
    } catch (e) {
      debugPrint('Error fetching vehicles for part: $e');
      return getCachedVehiclesForPart(make: make, model: model);
    }
  }

  // ─── WRITE ──────────────────────────────────────────────────────────────

  /// Create a new listing
  Future<String> createListing(MarketplaceListing listing) async {
    final docRef = listing.id.isNotEmpty
        ? _listingsRef.doc(listing.id)
        : _listingsRef.doc();
    final withId = listing.copyWith(
      id: docRef.id,
      createdAt: listing.createdAt ?? DateTime.now(),
    );
    cacheListing(withId);
    final data = withId.toMap();
    await docRef.set(data);
    return docRef.id;
  }

  /// Update an existing listing
  Future<void> updateListing(
    String listingId,
    Map<String, dynamic> updates,
  ) async {
    updates['updatedAt'] = FieldValue.serverTimestamp();
    await _listingsRef.doc(listingId).update(updates);
  }

  /// Delete a listing
  Future<void> deleteListing(String listingId) async {
    removeCachedListing(listingId);
    await _listingsRef.doc(listingId).delete();
  }

  /// Update listing status (active, sold, paused, etc.)
  Future<void> updateListingStatus(String listingId, String status) async {
    final existing = _listingsByIdCache[listingId];
    if (existing != null) {
      cacheListing(existing.copyWith(status: status));
    }
    await _listingsRef.doc(listingId).update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ─── INTERACTIONS ───────────────────────────────────────────────────────

  /// Increment view count
  Future<void> incrementViewCount(String listingId) async {
    await _functions.httpsCallable('recordListingView').call({
      'listingType': 'marketplace',
      'listingId': listingId,
    });
  }

  /// Save (bookmark) a listing
  Future<void> saveListing(String listingId, String userId) async {
    _savedListingIdsCache.add(listingId);
    final cached = _listingsByIdCache[listingId];
    if (cached != null &&
        !_savedListingsCache.any((l) => l.id == listingId)) {
      _savedListingsCache = [cached, ..._savedListingsCache];
    }
    await _functions.httpsCallable('setListingSaved').call({
      'listingType': 'marketplace',
      'listingId': listingId,
      'saved': true,
    });
  }

  /// Unsave a listing
  Future<void> unsaveListing(String listingId, String userId) async {
    _savedListingIdsCache.remove(listingId);
    _savedListingsCache = _savedListingsCache
        .where((l) => l.id != listingId)
        .toList();
    await _functions.httpsCallable('setListingSaved').call({
      'listingType': 'marketplace',
      'listingId': listingId,
      'saved': false,
    });
  }

  /// Check if a listing is saved by the user
  Future<bool> isListingSaved(String listingId, String userId) async {
    if (_savedListingIdsCache.contains(listingId)) return true;
    final doc = await _listingsRef
        .doc(listingId)
        .collection('saved_by')
        .doc(userId)
        .get();
    if (doc.exists) {
      _savedListingIdsCache.add(listingId);
    }
    return doc.exists;
  }

  /// Get all saved listing IDs for a user (for showing save state in lists)
  Future<Set<String>> getSavedListingIds(String userId) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('saved_listings')
        .limit(200)
        .get();
    final ids = snapshot.docs.map((doc) => doc.id).toSet();
    _savedListingIdsCache
      ..clear()
      ..addAll(ids);
    return ids;
  }

  /// Save listing reference to user's saved_listings subcollection
  Future<void> saveListingToUser(String listingId, String userId) async {
    _savedListingIdsCache.add(listingId);
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('saved_listings')
        .doc(listingId)
        .set({'savedAt': FieldValue.serverTimestamp()});
  }

  /// Remove listing reference from user's saved_listings subcollection
  Future<void> unsaveListingFromUser(String listingId, String userId) async {
    _savedListingIdsCache.remove(listingId);
    _savedListingsCache = _savedListingsCache
        .where((l) => l.id != listingId)
        .toList();
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('saved_listings')
        .doc(listingId)
        .delete();
  }

  /// Stream saved listings for a user
  Stream<List<MarketplaceListing>> getSavedListings(String userId) {
    final firestoreStream = _firestore
        .collection('users')
        .doc(userId)
        .collection('saved_listings')
        .orderBy('savedAt', descending: true)
        .limit(100)
        .snapshots()
        .asyncMap((snapshot) async {
          final ids = snapshot.docs.map((doc) => doc.id).toList();
          _savedListingIdsCache
            ..clear()
            ..addAll(ids);
          if (ids.isEmpty) {
            _savedListingsCache = [];
            return <MarketplaceListing>[];
          }

          // Resolve any IDs already in memory cache and fetch only uncached IDs in parallel batches of 10
          final missingIds = ids
              .where((id) => !_listingsByIdCache.containsKey(id))
              .toList();

          if (missingIds.isNotEmpty) {
            final batchFutures = <Future<QuerySnapshot>>[];
            for (var i = 0; i < missingIds.length; i += 10) {
              final batch = missingIds.sublist(
                i,
                i + 10 > missingIds.length ? missingIds.length : i + 10,
              );
              batchFutures.add(
                _listingsRef.where(FieldPath.documentId, whereIn: batch).get(),
              );
            }
            final snaps = await Future.wait(batchFutures);
            for (final snap in snaps) {
              for (final doc in snap.docs) {
                final item = MarketplaceListing.fromMap(
                  doc.data() as Map<String, dynamic>,
                  doc.id,
                );
                _listingsByIdCache[item.id] = item;
              }
            }
          }

          final listings = ids
              .map((id) => _listingsByIdCache[id])
              .whereType<MarketplaceListing>()
              .toList();
          _savedListingsCache = listings;
          return listings;
        });

    return Stream.multi((controller) {
      if (_savedListingsCache.isNotEmpty) {
        controller.add(_savedListingsCache);
      }
      final sub = firestoreStream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = sub.cancel;
    });
  }

  /// Check if a user has already interacted (paid DSP) with a listing
  Future<bool> hasInteractedWithListing(String listingId, String userId) async {
    try {
      final doc = await _listingsRef
          .doc(listingId)
          .collection('interactions')
          .doc(userId)
          .get();
      return doc.exists;
    } catch (e) {
      debugPrint('Error checking listing interaction: $e');
      return false;
    }
  }

  /// Record a first-time interaction with a listing (DSP was deducted)
  Future<void> recordListingInteraction(
    String listingId,
    String userId, {
    String? interactionType,
  }) async {
    await _listingsRef
        .doc(listingId)
        .collection('interactions')
        .doc(userId)
        .set({
          'interactedAt': FieldValue.serverTimestamp(),
          'type': interactionType ?? 'contact_seller',
        });
  }

  /// Report a listing
  Future<void> reportListing(
    String listingId,
    String reporterId,
    String reason, {
    String? sellerId,
  }) async {
    var resolvedSellerId = sellerId ?? _listingsByIdCache[listingId]?.sellerId;
    if (resolvedSellerId == null || resolvedSellerId.isEmpty) {
      final listing = await _listingsRef.doc(listingId).get();
      final data = listing.data() as Map<String, dynamic>?;
      resolvedSellerId = data?['sellerId'] as String?;
    }
    if (resolvedSellerId == null || resolvedSellerId.isEmpty) {
      throw StateError('The listing owner could not be verified.');
    }
    await _functions.httpsCallable('submitReport').call<void>({
      'type': 'marketplace_listing',
      'listingId': listingId,
      'reportedUserId': resolvedSellerId,
      'reporterId': reporterId,
      'reason': reason,
    });
  }
}
