import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/real_estate/models/real_estate_listing.dart';

final realEstateRepositoryProvider = Provider<RealEstateRepository>((ref) {
  return RealEstateRepository(
    FirebaseFirestore.instance,
    FirebaseFunctions.instance,
  );
});

class RealEstateRepository {
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  static const _collection = 'real_estate_listings';

  RealEstateRepository(this._db, this._functions);

  CollectionReference get _col => _db.collection(_collection);

  /// Create a new real estate listing
  Future<String> createListing(RealEstateListing listing) async {
    final doc = await _col.add(listing.toJson());
    return doc.id;
  }

  /// Update an existing listing
  Future<void> updateListing(String id, Map<String, dynamic> data) async {
    data['updatedAt'] = FieldValue.serverTimestamp();
    await _col.doc(id).update(data);
  }

  /// Delete a listing
  Future<void> deleteListing(String id) async {
    await _col.doc(id).delete();
  }

  /// Toggle listing status
  Future<void> toggleListingStatus(String id, String newStatus) async {
    await _col.doc(id).update({
      'status': newStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Get listings by owner
  Future<List<RealEstateListing>> getMyListings(
    String uid, {
    String? category,
  }) async {
    try {
      // Query by ownerId only, filter category client-side
      Query q = _col.where('ownerId', isEqualTo: uid);
      q = q.orderBy('createdAt', descending: true).limit(100);
      final snap = await q.get();
      var list = snap.docs
          .map(
            (d) => RealEstateListing.fromJson(
              d.data() as Map<String, dynamic>,
              d.id,
            ),
          )
          .toList();
      if (category != null) {
        list = list.where((l) => l.category == category).toList();
      }
      return list;
    } catch (e) {
      debugPrint('getMyListings error: $e');
      // Fallback without orderBy (missing index)
      try {
        final snap = await _col
            .where('ownerId', isEqualTo: uid)
            .limit(100)
            .get();
        var list = snap.docs
            .map(
              (d) => RealEstateListing.fromJson(
                d.data() as Map<String, dynamic>,
                d.id,
              ),
            )
            .toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        if (category != null) {
          list = list.where((l) => l.category == category).toList();
        }
        return list;
      } catch (e2) {
        debugPrint('getMyListings fallback error: $e2');
        return [];
      }
    }
  }

  /// Search listings with filters
  Future<List<RealEstateListing>> searchListings({
    String? category,
    String? countryCode,
    String? locality,
    String? state,
    String? listingType,
    double? minPrice,
    double? maxPrice,
    double? minSize,
    String? zoning,
    int limit = 50,
  }) async {
    try {
      // Simple query: fetch active listings, sorted by newest first
      // Category and other filters are applied client-side to avoid
      // needing composite Firestore indexes.
      Query q = _col.where('status', isEqualTo: 'active');
      q = q.orderBy('createdAt', descending: true).limit(limit);
      final snap = await q.get();
      var list = snap.docs
          .map(
            (d) => RealEstateListing.fromJson(
              d.data() as Map<String, dynamic>,
              d.id,
            ),
          )
          .toList();

      // Client-side filters
      if (category != null) {
        list = list.where((l) => l.category == category).toList();
      }
      if (countryCode != null) {
        list = list
            .where(
              (l) => l.countryCode?.toLowerCase() == countryCode.toLowerCase(),
            )
            .toList();
      }
      if (locality != null && locality.isNotEmpty) {
        list = list
            .where((l) => l.localityLower == locality.toLowerCase())
            .toList();
      }
      if (listingType != null) {
        list = list.where((l) => l.listingType == listingType).toList();
      }
      if (minPrice != null) {
        list = list.where((l) => l.price >= minPrice).toList();
      }
      if (maxPrice != null) {
        list = list.where((l) => l.price <= maxPrice).toList();
      }
      if (minSize != null) {
        list = list.where((l) => (l.size ?? 0) >= minSize).toList();
      }
      if (zoning != null) {
        list = list
            .where((l) => l.zoning?.toLowerCase() == zoning.toLowerCase())
            .toList();
      }
      if (state != null && state.isNotEmpty) {
        list = list
            .where(
              (l) =>
                  l.stateLower == state.toLowerCase() ||
                  l.state?.toLowerCase() == state.toLowerCase(),
            )
            .toList();
      }

      return list;
    } catch (e) {
      debugPrint('searchListings error: $e');
      // Fallback without orderBy (missing index for status+createdAt)
      try {
        final snap = await _col
            .where('status', isEqualTo: 'active')
            .limit(limit)
            .get();
        var list = snap.docs
            .map(
              (d) => RealEstateListing.fromJson(
                d.data() as Map<String, dynamic>,
                d.id,
              ),
            )
            .toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        if (category != null) {
          list = list.where((l) => l.category == category).toList();
        }
        return list;
      } catch (e2) {
        debugPrint('searchListings fallback error: $e2');
        // Last resort: fetch everything
        final snap = await _col.limit(limit).get();
        var list = snap.docs
            .map(
              (d) => RealEstateListing.fromJson(
                d.data() as Map<String, dynamic>,
                d.id,
              ),
            )
            .toList();
        list = list.where((l) => l.status == 'active').toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        if (category != null) {
          list = list.where((l) => l.category == category).toList();
        }
        return list;
      }
    }
  }

  /// Get a single listing
  Future<RealEstateListing?> getListing(String id) async {
    final doc = await _col.doc(id).get();
    if (!doc.exists) return null;
    return RealEstateListing.fromJson(
      doc.data() as Map<String, dynamic>,
      doc.id,
    );
  }

  // ─── ENGAGEMENT ───────────────────────────────────────

  /// Increment view count
  Future<void> incrementViewCount(
    String listingId, {
    String? country,
    String? countryCode,
  }) async {
    await _functions.httpsCallable('recordListingView').call({
      'listingType': 'real_estate',
      'listingId': listingId,
      'country': ?country,
      'countryCode': ?countryCode,
    });
  }

  /// Save (bookmark) a listing
  Future<void> saveListing(String listingId, String userId) async {
    await _functions.httpsCallable('setListingSaved').call({
      'listingType': 'real_estate',
      'listingId': listingId,
      'saved': true,
    });
  }

  /// Unsave (remove bookmark) a listing
  Future<void> unsaveListing(String listingId, String userId) async {
    await _functions.httpsCallable('setListingSaved').call({
      'listingType': 'real_estate',
      'listingId': listingId,
      'saved': false,
    });
  }

  /// Check if a listing is saved by the user
  Future<bool> isListingSaved(String listingId, String userId) async {
    final doc = await _col
        .doc(listingId)
        .collection('saved_by')
        .doc(userId)
        .get();
    return doc.exists;
  }
}
