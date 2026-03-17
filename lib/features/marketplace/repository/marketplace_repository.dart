import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/marketplace/models/marketplace_listing.dart';

final marketplaceRepositoryProvider = Provider<MarketplaceRepository>((ref) {
  return MarketplaceRepository();
});

class MarketplaceRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference get _listingsRef =>
      _firestore.collection('marketplace_listings');

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

    return query.snapshots().map((snapshot) {
      final listings = snapshot.docs
          .map(
            (doc) => MarketplaceListing.fromMap(
              doc.data() as Map<String, dynamic>,
              doc.id,
            ),
          )
          .toList();

      // Filter by community visibility on client side
      if (communityIds != null && communityIds.isNotEmpty) {
        return listings.where((listing) {
          // If listing has no communityIds, it's visible to everyone
          if (listing.communityIds == null || listing.communityIds!.isEmpty) {
            return true;
          }
          // Otherwise, user must share at least one community
          return listing.communityIds!.any((cid) => communityIds.contains(cid));
        }).toList();
      }

      return listings;
    });
  }

  /// Get a single listing by ID
  Future<MarketplaceListing?> getListingById(String listingId) async {
    try {
      final doc = await _listingsRef.doc(listingId).get();
      if (!doc.exists) return null;
      return MarketplaceListing.fromMap(
        doc.data() as Map<String, dynamic>,
        doc.id,
      );
    } catch (e) {
      debugPrint('Error fetching listing: $e');
      return null;
    }
  }

  /// Stream current user's own listings
  Stream<List<MarketplaceListing>> getMyListings(String userId) {
    return _listingsRef
        .where('sellerId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (doc) => MarketplaceListing.fromMap(
                  doc.data() as Map<String, dynamic>,
                  doc.id,
                ),
              )
              .toList(),
        );
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
    return snapshot.docs
        .map(
          (doc) => MarketplaceListing.fromMap(
            doc.data() as Map<String, dynamic>,
            doc.id,
          ),
        )
        .toList();
  }

  // ─── VEHICLE ↔ PARTS MATCHING ─────────────────────────────────────────

  /// Find car-parts listings that fit a given vehicle (make + model)
  Future<List<MarketplaceListing>> getPartsForVehicle({
    required String make,
    String? model,
    int limit = 50,
  }) async {
    try {
      // Query parts that match the vehicle's make
      Query query = _listingsRef
          .where('status', isEqualTo: ListingStatus.active)
          .where('category', isEqualTo: MarketplaceCategory.carParts)
          .where('carPartsDetails.carMake', isEqualTo: make);

      final snapshot = await query.limit(limit).get();
      final results = snapshot.docs
          .map(
            (doc) => MarketplaceListing.fromMap(
              doc.data() as Map<String, dynamic>,
              doc.id,
            ),
          )
          .toList();

      // Client-side filter by model if provided
      if (model != null && model.isNotEmpty) {
        final exact = results
            .where(
              (l) =>
                  l.carPartsDetails?['carModel']?.toString().toLowerCase() ==
                  model.toLowerCase(),
            )
            .toList();
        // Return exact matches, or all make-matches if no model matches
        return exact.isNotEmpty ? exact : results;
      }
      return results;
    } catch (e) {
      debugPrint('Error fetching parts for vehicle: $e');
      return [];
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
      final results = snapshot.docs
          .map(
            (doc) => MarketplaceListing.fromMap(
              doc.data() as Map<String, dynamic>,
              doc.id,
            ),
          )
          .toList();

      // Client-side filter by model if provided
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
      return [];
    }
  }

  // ─── WRITE ──────────────────────────────────────────────────────────────

  /// Create a new listing
  Future<String> createListing(MarketplaceListing listing) async {
    final docRef = _listingsRef.doc();
    final data = listing.copyWith(id: docRef.id).toMap();
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
    await _listingsRef.doc(listingId).delete();
  }

  /// Update listing status (active, sold, paused, etc.)
  Future<void> updateListingStatus(String listingId, String status) async {
    await _listingsRef.doc(listingId).update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ─── INTERACTIONS ───────────────────────────────────────────────────────

  /// Increment view count
  Future<void> incrementViewCount(String listingId) async {
    await _listingsRef.doc(listingId).update({
      'viewCount': FieldValue.increment(1),
    });
  }

  /// Save (bookmark) a listing
  Future<void> saveListing(String listingId, String userId) async {
    final batch = _firestore.batch();
    batch.set(_listingsRef.doc(listingId).collection('saved_by').doc(userId), {
      'savedAt': FieldValue.serverTimestamp(),
    });
    batch.update(_listingsRef.doc(listingId), {
      'savedCount': FieldValue.increment(1),
    });
    await batch.commit();
  }

  /// Unsave a listing
  Future<void> unsaveListing(String listingId, String userId) async {
    final batch = _firestore.batch();
    batch.delete(
      _listingsRef.doc(listingId).collection('saved_by').doc(userId),
    );
    batch.update(_listingsRef.doc(listingId), {
      'savedCount': FieldValue.increment(-1),
    });
    await batch.commit();
  }

  /// Check if a listing is saved by the user
  Future<bool> isListingSaved(String listingId, String userId) async {
    final doc = await _listingsRef
        .doc(listingId)
        .collection('saved_by')
        .doc(userId)
        .get();
    return doc.exists;
  }

  /// Get all saved listing IDs for a user (for showing save state in lists)
  Future<Set<String>> getSavedListingIds(String userId) async {
    // Query across all listings where this user saved
    // This is expensive — consider a denormalized user-side collection
    // For now: use a user-side sub-collection
    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('saved_listings')
        .limit(200)
        .get();
    return snapshot.docs.map((doc) => doc.id).toSet();
  }

  /// Save listing reference to user's saved_listings subcollection
  Future<void> saveListingToUser(String listingId, String userId) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('saved_listings')
        .doc(listingId)
        .set({'savedAt': FieldValue.serverTimestamp()});
  }

  /// Remove listing reference from user's saved_listings subcollection
  Future<void> unsaveListingFromUser(String listingId, String userId) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('saved_listings')
        .doc(listingId)
        .delete();
  }

  /// Stream saved listings for a user
  Stream<List<MarketplaceListing>> getSavedListings(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('saved_listings')
        .orderBy('savedAt', descending: true)
        .limit(100)
        .snapshots()
        .asyncMap((snapshot) async {
          final ids = snapshot.docs.map((doc) => doc.id).toList();
          if (ids.isEmpty) return <MarketplaceListing>[];

          // Fetch in batches of 10 (Firestore whereIn limit)
          final listings = <MarketplaceListing>[];
          for (var i = 0; i < ids.length; i += 10) {
            final batch = ids.sublist(
              i,
              i + 10 > ids.length ? ids.length : i + 10,
            );
            final snap = await _listingsRef
                .where(FieldPath.documentId, whereIn: batch)
                .get();
            listings.addAll(
              snap.docs.map(
                (doc) => MarketplaceListing.fromMap(
                  doc.data() as Map<String, dynamic>,
                  doc.id,
                ),
              ),
            );
          }
          return listings;
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
    String reason,
  ) async {
    final batch = _firestore.batch();
    batch.set(
      _listingsRef.doc(listingId).collection('reports').doc(reporterId),
      {'reason': reason, 'reportedAt': FieldValue.serverTimestamp()},
    );
    batch.update(_listingsRef.doc(listingId), {
      'reportCount': FieldValue.increment(1),
    });
    await batch.commit();
  }
}
