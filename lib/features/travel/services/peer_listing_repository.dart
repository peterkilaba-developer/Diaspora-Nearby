import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/travel/models/peer_listing.dart';

final peerListingRepositoryProvider = Provider<PeerListingRepository>((ref) {
  return PeerListingRepository(
    FirebaseFirestore.instance,
    FirebaseFunctions.instance,
  );
});

class PeerListingRepository {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  PeerListingRepository(this._firestore, this._functions);

  CollectionReference get _listings => _firestore.collection('peer_listings');
  CollectionReference get _bookings => _firestore.collection('peer_bookings');

  // ─── LISTINGS ─────────────────────────────────────────

  /// Create a new listing
  Future<String> createListing(PeerListing listing) async {
    final doc = _listings.doc();
    await doc.set(listing.toJson());
    return doc.id;
  }

  /// Update an existing listing
  Future<void> updateListing(String id, Map<String, dynamic> data) async {
    data['updatedAt'] = FieldValue.serverTimestamp();
    await _listings.doc(id).update(data);
  }

  /// Delete a listing
  Future<void> deleteListing(String id) async {
    await _listings.doc(id).delete();
  }

  /// Toggle listing status (active/paused)
  Future<void> toggleListingStatus(String id, String newStatus) async {
    await _listings.doc(id).update({
      'status': newStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Get listings by owner
  Future<List<PeerListing>> getMyListings(String uid) async {
    try {
      // Only filter by ownerId — sort client-side to avoid composite index
      final query = await _listings
          .where('ownerId', isEqualTo: uid)
          .limit(100)
          .get();
      debugPrint(
        '[getMyListings] Found ${query.docs.length} listings for uid=$uid',
      );
      final listings = query.docs
          .map(
            (d) => PeerListing.fromJson(d.data() as Map<String, dynamic>, d.id),
          )
          .toList();
      // Sort newest first client-side
      listings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return listings;
    } catch (e, st) {
      debugPrint('Error getting my listings: $e');
      debugPrint('Stack trace: $st');
      return [];
    }
  }

  /// Search listings by type with structured location and advanced filters.
  ///
  /// Firestore-level filters: type, status, localityLower, stateLower, countryCode.
  /// Client-side filters: price range, beds, guests, property type, transmission,
  /// seats, fuel type, amenities, features, and fallback city text match.
  Future<List<PeerListing>> searchListings({
    required String type,
    String? city, // free-text fallback
    String? locality, // structured city for Firestore query
    String? state, // structured state
    String? countryCode,
    // Stay filters
    String? propertyType,
    double? minPrice,
    double? maxPrice,
    int? minBeds,
    int? minGuests,
    List<String>? amenities,
    // Car filters
    String? transmission,
    int? minSeats,
    String? fuelType,
    List<String>? features,
    int limit = 50,
  }) async {
    try {
      // Keep Firestore query simple — only filter by type.
      // Avoid filtering on 'status' at Firestore level since older listings
      // may not have the status field set.
      Query query = _listings.where('type', isEqualTo: type);

      if (countryCode != null && countryCode.isNotEmpty) {
        query = query.where('countryCode', isEqualTo: countryCode);
      }

      query = query.limit(limit);

      final results = await query.get();
      debugPrint(
        '[SearchListings] Firestore returned ${results.docs.length} docs for type=$type',
      );
      var listings = results.docs
          .map(
            (d) => PeerListing.fromJson(d.data() as Map<String, dynamic>, d.id),
          )
          .toList();

      // Sort by newest first (client-side to avoid composite index)
      listings.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Filter out non-active listings client-side
      listings = listings.where((l) => l.status == 'active').toList();

      // Location filter — matches structured fields AND legacy city/address
      final locationQuery = locality ?? city;
      if (locationQuery != null && locationQuery.isNotEmpty) {
        final q = locationQuery.toLowerCase();
        listings = listings
            .where(
              (l) =>
                  (l.localityLower?.contains(q) ?? false) ||
                  (l.city?.toLowerCase().contains(q) ?? false) ||
                  (l.locality?.toLowerCase().contains(q) ?? false) ||
                  (l.subLocality?.toLowerCase().contains(q) ?? false) ||
                  (l.state?.toLowerCase().contains(q) ?? false) ||
                  (l.country?.toLowerCase().contains(q) ?? false) ||
                  (l.address?.toLowerCase().contains(q) ?? false),
            )
            .toList();
      }

      // --- Client-side filters ---

      // Price range
      if (minPrice != null) {
        listings = listings.where((l) => l.pricePerUnit >= minPrice).toList();
      }
      if (maxPrice != null) {
        listings = listings.where((l) => l.pricePerUnit <= maxPrice).toList();
      }

      // Stay-specific
      if (propertyType != null && propertyType.isNotEmpty) {
        listings = listings
            .where(
              (l) =>
                  l.propertyType?.toLowerCase() == propertyType.toLowerCase(),
            )
            .toList();
      }
      if (minBeds != null) {
        listings = listings.where((l) => (l.beds ?? 0) >= minBeds).toList();
      }
      if (minGuests != null) {
        listings = listings
            .where((l) => (l.maxGuests ?? 0) >= minGuests)
            .toList();
      }
      if (amenities != null && amenities.isNotEmpty) {
        listings = listings.where((l) {
          if (l.amenities == null) return false;
          final lAm = l.amenities!.map((a) => a.toLowerCase()).toSet();
          return amenities.every((a) => lAm.contains(a.toLowerCase()));
        }).toList();
      }

      // Car-specific
      if (transmission != null && transmission.isNotEmpty) {
        listings = listings
            .where(
              (l) =>
                  l.transmission?.toLowerCase() == transmission.toLowerCase(),
            )
            .toList();
      }
      if (minSeats != null) {
        listings = listings.where((l) => (l.seats ?? 0) >= minSeats).toList();
      }
      if (fuelType != null && fuelType.isNotEmpty) {
        listings = listings
            .where((l) => l.fuelType?.toLowerCase() == fuelType.toLowerCase())
            .toList();
      }
      if (features != null && features.isNotEmpty) {
        listings = listings.where((l) {
          if (l.features == null) return false;
          final lFt = l.features!.map((f) => f.toLowerCase()).toSet();
          return features.every((f) => lFt.contains(f.toLowerCase()));
        }).toList();
      }

      return listings;
    } catch (e, st) {
      debugPrint('Error searching listings: $e');
      debugPrint('Stack trace: $st');
      rethrow;
    }
  }

  /// Get a single listing
  Future<PeerListing?> getListing(String id) async {
    try {
      final doc = await _listings.doc(id).get();
      if (!doc.exists) return null;
      return PeerListing.fromJson(doc.data() as Map<String, dynamic>, doc.id);
    } catch (e) {
      debugPrint('Error getting listing: $e');
      return null;
    }
  }

  // ─── BOOKINGS ─────────────────────────────────────────

  /// Create a booking request
  Future<String> createBooking(PeerBooking booking) async {
    final result = await _functions
        .httpsCallable('createPeerBooking')
        .call<Map<String, dynamic>>({
          'listingId': booking.listingId,
          'startDate': booking.startDate.toUtc().toIso8601String(),
          'endDate': booking.endDate.toUtc().toIso8601String(),
          'guests': booking.guests,
          'notes': booking.notes,
        });
    return result.data['bookingId'] as String;
  }

  /// Update booking status
  Future<void> updateBookingStatus(String id, String status) async {
    await _functions.httpsCallable('updatePeerBookingStatus').call<void>({
      'bookingId': id,
      'status': status,
    });
  }

  /// Get bookings for a guest (my trips)
  Future<List<PeerBooking>> getGuestBookings(String uid) async {
    try {
      final query = await _bookings
          .where('guestId', isEqualTo: uid)
          .limit(100)
          .get();
      final bookings = query.docs
          .map(
            (d) => PeerBooking.fromJson(d.data() as Map<String, dynamic>, d.id),
          )
          .toList();
      bookings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return bookings;
    } catch (e, st) {
      debugPrint('Error getting guest bookings: $e');
      debugPrint('Stack trace: $st');
      return [];
    }
  }

  /// Get bookings for a host (incoming requests)
  Future<List<PeerBooking>> getHostBookings(String uid) async {
    try {
      final query = await _bookings
          .where('hostId', isEqualTo: uid)
          .limit(100)
          .get();
      final bookings = query.docs
          .map(
            (d) => PeerBooking.fromJson(d.data() as Map<String, dynamic>, d.id),
          )
          .toList();
      bookings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return bookings;
    } catch (e, st) {
      debugPrint('Error getting host bookings: $e');
      debugPrint('Stack trace: $st');
      return [];
    }
  }

  /// Get bookings for a specific listing
  Future<List<PeerBooking>> getListingBookings(String listingId) async {
    try {
      final query = await _bookings
          .where('listingId', isEqualTo: listingId)
          .limit(100)
          .get();
      final bookings = query.docs
          .map(
            (d) => PeerBooking.fromJson(d.data() as Map<String, dynamic>, d.id),
          )
          .toList();
      bookings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return bookings;
    } catch (e, st) {
      debugPrint('Error getting listing bookings: $e');
      debugPrint('Stack trace: $st');
      return [];
    }
  }

  // ─── ENGAGEMENT ───────────────────────────────────────

  /// Increment view count
  Future<void> incrementViewCount(String listingId) async {
    await _functions.httpsCallable('recordListingView').call({
      'listingType': 'peer',
      'listingId': listingId,
    });
  }

  /// Save (bookmark) a listing
  Future<void> saveListing(String listingId, String userId) async {
    await _functions.httpsCallable('setListingSaved').call({
      'listingType': 'peer',
      'listingId': listingId,
      'saved': true,
    });
  }

  /// Unsave (remove bookmark) a listing
  Future<void> unsaveListing(String listingId, String userId) async {
    await _functions.httpsCallable('setListingSaved').call({
      'listingType': 'peer',
      'listingId': listingId,
      'saved': false,
    });
  }

  /// Check if a listing is saved by the user
  Future<bool> isListingSaved(String listingId, String userId) async {
    final doc = await _listings
        .doc(listingId)
        .collection('saved_by')
        .doc(userId)
        .get();
    return doc.exists;
  }
}
