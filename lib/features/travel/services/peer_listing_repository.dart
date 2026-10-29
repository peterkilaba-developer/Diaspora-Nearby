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

  static final Map<String, List<PeerListing>> _listingsByTypeCache = {};
  static final Map<String, PeerListing> _listingsByIdCache = {};
  static final Map<String, List<PeerListing>> _myListingsCache = {};
  static final Map<String, List<PeerBooking>> _guestBookingsCache = {};
  static final Map<String, List<PeerBooking>> _hostBookingsCache = {};
  static final Map<String, List<PeerBooking>> _listingBookingsCache = {};
  static final Set<String> _savedListingIdsCache = {};

  CollectionReference get _listings => _firestore.collection('peer_listings');
  CollectionReference get _bookings => _firestore.collection('peer_bookings');

  String generateListingId() => _listings.doc().id;
  String generateBookingId() => _bookings.doc().id;

  PeerListing? getCachedListing(String id) => _listingsByIdCache[id];

  List<PeerListing> getCachedListings({required String type}) =>
      List.unmodifiable(_listingsByTypeCache[type] ?? const []);

  List<PeerListing> getCachedMyListings(String uid, {String? type}) {
    final list =
        _myListingsCache[uid] ??
        _listingsByIdCache.values.where((l) => l.ownerId == uid).toList();
    if (type == null) return List.unmodifiable(list);
    return list.where((l) => l.type == type).toList();
  }

  List<PeerBooking> getCachedGuestBookings(String uid) =>
      List.unmodifiable(_guestBookingsCache[uid] ?? const []);

  List<PeerBooking> getCachedHostBookings(String uid) =>
      List.unmodifiable(_hostBookingsCache[uid] ?? const []);

  List<PeerBooking> getCachedListingBookings(String listingId) =>
      List.unmodifiable(_listingBookingsCache[listingId] ?? const []);

  bool isListingSavedSync(String listingId) =>
      _savedListingIdsCache.contains(listingId);

  void cacheListing(PeerListing listing) {
    if (listing.id.isEmpty) return;
    _listingsByIdCache[listing.id] = listing;

    final typeList = _listingsByTypeCache[listing.type] ?? <PeerListing>[];
    final typeIdx = typeList.indexWhere((l) => l.id == listing.id);
    if (listing.status == 'active') {
      if (typeIdx >= 0) {
        typeList[typeIdx] = listing;
      } else {
        _listingsByTypeCache[listing.type] = [listing, ...typeList];
      }
    } else if (typeIdx >= 0) {
      typeList.removeAt(typeIdx);
    }

    final myList = _myListingsCache[listing.ownerId];
    if (myList != null) {
      final myIdx = myList.indexWhere((l) => l.id == listing.id);
      if (myIdx >= 0) {
        myList[myIdx] = listing;
      } else {
        _myListingsCache[listing.ownerId] = [listing, ...myList];
      }
    }
  }

  void removeCachedListing(String id) {
    final removed = _listingsByIdCache.remove(id);
    _savedListingIdsCache.remove(id);
    for (final list in _listingsByTypeCache.values) {
      list.removeWhere((l) => l.id == id);
    }
    if (removed != null) {
      _myListingsCache[removed.ownerId]?.removeWhere((l) => l.id == id);
    }
  }

  void cacheBooking(PeerBooking booking) {
    if (booking.id.isEmpty) return;
    final guestList = _guestBookingsCache[booking.guestId] ?? <PeerBooking>[];
    final gIdx = guestList.indexWhere((b) => b.id == booking.id);
    if (gIdx >= 0) {
      guestList[gIdx] = booking;
    } else {
      _guestBookingsCache[booking.guestId] = [booking, ...guestList];
    }

    final hostList = _hostBookingsCache[booking.hostId] ?? <PeerBooking>[];
    final hIdx = hostList.indexWhere((b) => b.id == booking.id);
    if (hIdx >= 0) {
      hostList[hIdx] = booking;
    } else {
      _hostBookingsCache[booking.hostId] = [booking, ...hostList];
    }

    final listingList =
        _listingBookingsCache[booking.listingId] ?? <PeerBooking>[];
    final lIdx = listingList.indexWhere((b) => b.id == booking.id);
    if (lIdx >= 0) {
      listingList[lIdx] = booking;
    } else {
      _listingBookingsCache[booking.listingId] = [booking, ...listingList];
    }
  }

  void updateCachedBookingStatus(String bookingId, String status) {
    for (final list in _guestBookingsCache.values) {
      final idx = list.indexWhere((b) => b.id == bookingId);
      if (idx >= 0) list[idx] = list[idx].copyWith(status: status);
    }
    for (final list in _hostBookingsCache.values) {
      final idx = list.indexWhere((b) => b.id == bookingId);
      if (idx >= 0) list[idx] = list[idx].copyWith(status: status);
    }
    for (final list in _listingBookingsCache.values) {
      final idx = list.indexWhere((b) => b.id == bookingId);
      if (idx >= 0) list[idx] = list[idx].copyWith(status: status);
    }
  }

  // ─── LISTINGS ─────────────────────────────────────────

  /// Create a new listing
  Future<String> createListing(PeerListing listing) async {
    final doc = listing.id.isNotEmpty
        ? _listings.doc(listing.id)
        : _listings.doc();
    final withId = listing.copyWith(id: doc.id);
    cacheListing(withId);
    await doc.set(withId.toJson());
    return doc.id;
  }

  /// Update an existing listing
  Future<void> updateListing(String id, Map<String, dynamic> data) async {
    data['updatedAt'] = FieldValue.serverTimestamp();
    await _listings.doc(id).update(data);
  }

  /// Delete a listing
  Future<void> deleteListing(String id) async {
    removeCachedListing(id);
    await _listings.doc(id).delete();
  }

  /// Toggle listing status (active/paused)
  Future<void> toggleListingStatus(String id, String newStatus) async {
    final existing = _listingsByIdCache[id];
    if (existing != null) {
      cacheListing(existing.copyWith(status: newStatus));
    }
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
      for (final l in listings) {
        _listingsByIdCache[l.id] = l;
      }
      _myListingsCache[uid] = List.from(listings);
      return listings;
    } catch (e, st) {
      debugPrint('Error getting my listings: $e');
      debugPrint('Stack trace: $st');
      return getCachedMyListings(uid);
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

      for (final l in listings) {
        _listingsByIdCache[l.id] = l;
      }
      if (countryCode == null || countryCode.isEmpty) {
        _listingsByTypeCache[type] = List.from(listings);
      }

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
      if (!doc.exists) return _listingsByIdCache[id];
      final listing = PeerListing.fromJson(
        doc.data() as Map<String, dynamic>,
        doc.id,
      );
      cacheListing(listing);
      return listing;
    } catch (e) {
      debugPrint('Error getting listing: $e');
      return _listingsByIdCache[id];
    }
  }

  // ─── BOOKINGS ─────────────────────────────────────────

  /// Create a booking request
  Future<String> createBooking(PeerBooking booking) async {
    if (booking.id.isNotEmpty) {
      cacheBooking(booking);
    }
    final result = await _functions
        .httpsCallable('createPeerBooking')
        .call<Map<String, dynamic>>({
          'listingId': booking.listingId,
          'startDate': booking.startDate.toUtc().toIso8601String(),
          'endDate': booking.endDate.toUtc().toIso8601String(),
          'guests': booking.guests,
          'notes': booking.notes,
        });
    final bookingId = result.data['bookingId'] as String;
    cacheBooking(booking.copyWith(id: bookingId));
    return bookingId;
  }

  /// Update booking status
  Future<void> updateBookingStatus(String id, String status) async {
    updateCachedBookingStatus(id, status);
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
      _guestBookingsCache[uid] = List.from(bookings);
      return bookings;
    } catch (e, st) {
      debugPrint('Error getting guest bookings: $e');
      debugPrint('Stack trace: $st');
      return getCachedGuestBookings(uid);
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
      _hostBookingsCache[uid] = List.from(bookings);
      return bookings;
    } catch (e, st) {
      debugPrint('Error getting host bookings: $e');
      debugPrint('Stack trace: $st');
      return getCachedHostBookings(uid);
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
      _listingBookingsCache[listingId] = List.from(bookings);
      return bookings;
    } catch (e, st) {
      debugPrint('Error getting listing bookings: $e');
      debugPrint('Stack trace: $st');
      return getCachedListingBookings(listingId);
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
    _savedListingIdsCache.add(listingId);
    await _functions.httpsCallable('setListingSaved').call({
      'listingType': 'peer',
      'listingId': listingId,
      'saved': true,
    });
  }

  /// Unsave (remove bookmark) a listing
  Future<void> unsaveListing(String listingId, String userId) async {
    _savedListingIdsCache.remove(listingId);
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
    if (doc.exists) {
      _savedListingIdsCache.add(listingId);
    } else {
      _savedListingIdsCache.remove(listingId);
    }
    return doc.exists;
  }
}
