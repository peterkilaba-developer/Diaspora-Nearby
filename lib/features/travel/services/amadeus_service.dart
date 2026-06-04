import 'package:cloud_functions/cloud_functions.dart';

/// Model representing a single flight offer from Amadeus API.
class FlightOffer {
  final String id;
  final String source;
  final int numberOfBookableSeats;
  final String currency;
  final double totalPrice;
  final List<FlightItinerary> itineraries;
  final List<TravelerPricing> travelerPricings;
  final String? validatingAirline;
  final bool instantTicketingRequired;
  final Map<String, dynamic>? rawJson;

  FlightOffer({
    required this.id,
    required this.source,
    required this.numberOfBookableSeats,
    required this.currency,
    required this.totalPrice,
    required this.itineraries,
    required this.travelerPricings,
    this.validatingAirline,
    this.instantTicketingRequired = false,
    this.rawJson,
  });

  factory FlightOffer.fromJson(Map<String, dynamic> json) {
    return FlightOffer(
      id: json['id'] ?? '',
      source: json['source'] ?? '',
      numberOfBookableSeats: json['numberOfBookableSeats'] ?? 0,
      currency: json['price']?['currency'] ?? 'USD',
      totalPrice: double.tryParse(json['price']?['grandTotal'] ?? '0') ?? 0,
      itineraries: (json['itineraries'] as List? ?? [])
          .map((i) => FlightItinerary.fromJson(i))
          .toList(),
      travelerPricings: (json['travelerPricings'] as List? ?? [])
          .map((t) => TravelerPricing.fromJson(t))
          .toList(),
      validatingAirline: json['validatingAirlineCodes']?.isNotEmpty == true
          ? json['validatingAirlineCodes'][0]
          : null,
      instantTicketingRequired: json['instantTicketingRequired'] ?? false,
      rawJson: json,
    );
  }

  /// Total number of stops across all segments of the first itinerary.
  int get totalStops {
    if (itineraries.isEmpty) return 0;
    return itineraries.first.segments.length - 1;
  }

  /// Total duration of the first itinerary as a human-readable string.
  String get durationFormatted {
    if (itineraries.isEmpty) return '';
    return _formatDuration(itineraries.first.duration);
  }

  /// Route summary like "JFK → LOS" from first itinerary.
  String get routeSummary {
    if (itineraries.isEmpty || itineraries.first.segments.isEmpty) return '';
    final segs = itineraries.first.segments;
    return '${segs.first.departureIata} → ${segs.last.arrivalIata}';
  }

  /// Stops description.
  String get stopsDescription {
    if (totalStops == 0) return 'Direct';
    if (totalStops == 1) {
      final layover = itineraries.first.segments.first.arrivalIata;
      return '1 Stop ($layover)';
    }
    return '$totalStops Stops';
  }

  static String _formatDuration(String isoDuration) {
    // Parse PT14H20M format
    final regex = RegExp(r'PT(?:(\d+)H)?(?:(\d+)M)?');
    final match = regex.firstMatch(isoDuration);
    if (match == null) return isoDuration;
    final hours = match.group(1) ?? '0';
    final minutes = match.group(2) ?? '0';
    return '${hours}h ${minutes}m';
  }
}

class FlightItinerary {
  final String duration;
  final List<FlightSegment> segments;

  FlightItinerary({required this.duration, required this.segments});

  factory FlightItinerary.fromJson(Map<String, dynamic> json) {
    return FlightItinerary(
      duration: json['duration'] ?? '',
      segments: (json['segments'] as List? ?? [])
          .map((s) => FlightSegment.fromJson(s))
          .toList(),
    );
  }
}

class FlightSegment {
  final String departureIata;
  final String arrivalIata;
  final String departureAt;
  final String arrivalAt;
  final String carrierCode;
  final String flightNumber;
  final String duration;
  final int numberOfStops;

  FlightSegment({
    required this.departureIata,
    required this.arrivalIata,
    required this.departureAt,
    required this.arrivalAt,
    required this.carrierCode,
    required this.flightNumber,
    required this.duration,
    required this.numberOfStops,
  });

  factory FlightSegment.fromJson(Map<String, dynamic> json) {
    return FlightSegment(
      departureIata: json['departure']?['iataCode'] ?? '',
      arrivalIata: json['arrival']?['iataCode'] ?? '',
      departureAt: json['departure']?['at'] ?? '',
      arrivalAt: json['arrival']?['at'] ?? '',
      carrierCode: json['carrierCode'] ?? '',
      flightNumber: json['number'] ?? '',
      duration: json['duration'] ?? '',
      numberOfStops: json['numberOfStops'] ?? 0,
    );
  }
}

class TravelerPricing {
  final String travelerId;
  final String fareOption;
  final String travelerType;
  final String totalPrice;
  final String currency;

  TravelerPricing({
    required this.travelerId,
    required this.fareOption,
    required this.travelerType,
    required this.totalPrice,
    required this.currency,
  });

  factory TravelerPricing.fromJson(Map<String, dynamic> json) {
    return TravelerPricing(
      travelerId: json['travelerId'] ?? '',
      fareOption: json['fareOption'] ?? '',
      travelerType: json['travelerType'] ?? 'ADULT',
      totalPrice: json['price']?['total'] ?? '0',
      currency: json['price']?['currency'] ?? 'USD',
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HOTEL MODELS
// ═══════════════════════════════════════════════════════════════════════════

/// A hotel entry from the Hotel List API (/v1/reference-data/locations/hotels).
class HotelListEntry {
  final String hotelId;
  final String name;
  final String? chainCode;
  final String? iataCode; // City IATA
  final double? latitude;
  final double? longitude;
  final String? countryCode;

  HotelListEntry({
    required this.hotelId,
    required this.name,
    this.chainCode,
    this.iataCode,
    this.latitude,
    this.longitude,
    this.countryCode,
  });

  factory HotelListEntry.fromJson(Map<String, dynamic> json) {
    return HotelListEntry(
      hotelId: json['hotelId'] ?? '',
      name: json['name'] ?? '',
      chainCode: json['chainCode'],
      iataCode: json['iataCode'],
      latitude: (json['geoCode']?['latitude'] as num?)?.toDouble(),
      longitude: (json['geoCode']?['longitude'] as num?)?.toDouble(),
      countryCode: json['address']?['countryCode'],
    );
  }
}

/// A hotel offer result from the Hotel Search API (/v3/shopping/hotel-offers).
class HotelOfferResult {
  final String type;
  final String hotelId;
  final String hotelName;
  final String? chainCode;
  final double? latitude;
  final double? longitude;
  final bool available;
  final List<RoomOffer> offers;

  HotelOfferResult({
    required this.type,
    required this.hotelId,
    required this.hotelName,
    this.chainCode,
    this.latitude,
    this.longitude,
    this.available = false,
    this.offers = const [],
  });

  factory HotelOfferResult.fromJson(Map<String, dynamic> json) {
    final hotel = json['hotel'] as Map<String, dynamic>? ?? {};
    return HotelOfferResult(
      type: json['type'] ?? 'hotel-offers',
      hotelId: hotel['hotelId'] ?? '',
      hotelName: hotel['name'] ?? '',
      chainCode: hotel['chainCode'],
      latitude: (hotel['latitude'] as num?)?.toDouble(),
      longitude: (hotel['longitude'] as num?)?.toDouble(),
      available: json['available'] == true,
      offers: (json['offers'] as List? ?? [])
          .map((o) => RoomOffer.fromJson(o))
          .toList(),
    );
  }

  /// Cheapest offer price.
  double get cheapestPrice {
    if (offers.isEmpty) return 0;
    return offers.map((o) => o.totalPrice).reduce((a, b) => a < b ? a : b);
  }

  /// Currency from first offer.
  String get currency => offers.isNotEmpty ? offers.first.currency : 'USD';

  /// Board type from cheapest offer.
  String? get boardType {
    if (offers.isEmpty) return null;
    final cheapest = offers.reduce(
      (a, b) => a.totalPrice <= b.totalPrice ? a : b,
    );
    return cheapest.boardType;
  }
}

/// A single room offer within a hotel.
class RoomOffer {
  final String id;
  final String? checkInDate;
  final String? checkOutDate;
  final String? rateCode;
  final String? roomType;
  final String? roomCategory;
  final int? beds;
  final String? bedType;
  final String? roomDescription;
  final String currency;
  final double basePrice;
  final double totalPrice;
  final String? boardType; // e.g. ROOM_ONLY, BREAKFAST
  final String? paymentType;
  final String? cancellationDeadline;
  final String? cancellationDescription;

  RoomOffer({
    required this.id,
    this.checkInDate,
    this.checkOutDate,
    this.rateCode,
    this.roomType,
    this.roomCategory,
    this.beds,
    this.bedType,
    this.roomDescription,
    required this.currency,
    required this.basePrice,
    required this.totalPrice,
    this.boardType,
    this.paymentType,
    this.cancellationDeadline,
    this.cancellationDescription,
  });

  factory RoomOffer.fromJson(Map<String, dynamic> json) {
    final price = json['price'] as Map<String, dynamic>? ?? {};
    final room = json['room'] as Map<String, dynamic>? ?? {};
    final typeEstimated = room['typeEstimated'] as Map<String, dynamic>? ?? {};
    final policies = json['policies'] as Map<String, dynamic>? ?? {};
    final cancellation =
        policies['cancellation'] as Map<String, dynamic>? ?? {};
    final descObj = room['description'] as Map<String, dynamic>?;

    return RoomOffer(
      id: json['id'] ?? '',
      checkInDate: json['checkInDate'],
      checkOutDate: json['checkOutDate'],
      rateCode: json['rateCode'],
      roomType: room['type'],
      roomCategory: typeEstimated['category'],
      beds: typeEstimated['beds'] as int?,
      bedType: typeEstimated['bedType'],
      roomDescription: descObj?['text'],
      currency: price['currency'] ?? 'USD',
      basePrice: double.tryParse(price['base']?.toString() ?? '0') ?? 0,
      totalPrice: double.tryParse(price['total']?.toString() ?? '0') ?? 0,
      boardType: json['boardType'],
      paymentType: policies['paymentType'],
      cancellationDeadline: cancellation['deadline'],
      cancellationDescription: cancellation['description']?['text'],
    );
  }

  /// Number of nights between check-in and check-out.
  int get nights {
    if (checkInDate == null || checkOutDate == null) return 1;
    try {
      final checkIn = DateTime.parse(checkInDate!);
      final checkOut = DateTime.parse(checkOutDate!);
      final diff = checkOut.difference(checkIn).inDays;
      return diff > 0 ? diff : 1;
    } catch (_) {
      return 1;
    }
  }

  /// Price per night.
  double get pricePerNight => totalPrice / nights;

  /// Human-readable board type.
  String get boardTypeDisplay {
    switch (boardType) {
      case 'ROOM_ONLY':
        return 'Room Only';
      case 'BREAKFAST':
        return 'Breakfast Included';
      case 'HALF_BOARD':
        return 'Half Board';
      case 'FULL_BOARD':
        return 'Full Board';
      case 'ALL_INCLUSIVE':
        return 'All Inclusive';
      default:
        return boardType ?? 'Room Only';
    }
  }

  /// Human-readable bed info.
  String get bedInfo {
    final count = beds ?? 1;
    final type = bedType ?? 'BED';
    final typeName = type == 'DOUBLE'
        ? 'Double'
        : type == 'SINGLE'
        ? 'Single'
        : type == 'KING'
        ? 'King'
        : type == 'QUEEN'
        ? 'Queen'
        : type == 'TWIN'
        ? 'Twin'
        : type == 'BED'
        ? ''
        : type;
    final label = typeName.isEmpty
        ? 'Bed${count > 1 ? 's' : ''}'
        : '$typeName Bed${count > 1 ? 's' : ''}';
    return '$count $label';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AMADEUS SERVICE (Cloud Function Proxy)
// ═══════════════════════════════════════════════════════════════════════════

/// Service for interacting with the Amadeus Self-Service API via a
/// server-side Cloud Function proxy. API credentials never touch the client.
class AmadeusService {
  /// Recursively converts all nested maps from `Map<Object?, Object?>` to
  /// `Map<String, dynamic>` and lists from `List<Object?>` to `List<dynamic>`.
  /// Firebase callable functions return untyped maps that need deep casting.
  static dynamic _deepCast(dynamic value) {
    if (value is Map) {
      return value.map<String, dynamic>(
        (key, val) => MapEntry(key.toString(), _deepCast(val)),
      );
    } else if (value is List) {
      return value.map(_deepCast).toList();
    }
    return value;
  }

  /// Calls the `amadeusProxy` Cloud Function with the given action + params.
  Future<Map<String, dynamic>> _call(
    String action,
    Map<String, dynamic> params,
  ) async {
    final callable = FirebaseFunctions.instance.httpsCallable(
      'amadeusProxy',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 55)),
    );

    final result = await callable.call<dynamic>({
      'action': action,
      'params': params,
    });

    // Deep-cast the entire response tree so nested maps/lists are properly typed
    return _deepCast(result.data) as Map<String, dynamic>;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FLIGHT SEARCH
  // ─────────────────────────────────────────────────────────────────────────

  /// Search for flight offers.
  ///
  /// [originIata] - Origin airport IATA code (e.g., "JFK")
  /// [destinationIata] - Destination airport IATA code (e.g., "LOS")
  /// [departureDate] - Departure date in YYYY-MM-DD format
  /// [returnDate] - Optional return date for round trips
  /// [adults] - Number of adult travelers (default 1)
  /// [maxResults] - Maximum number of results (default 10)
  Future<List<FlightOffer>> searchFlights({
    required String originIata,
    required String destinationIata,
    required String departureDate,
    String? returnDate,
    int adults = 1,
    int maxResults = 10,
    String currencyCode = 'USD',
  }) async {
    final params = <String, dynamic>{
      'originIata': originIata,
      'destinationIata': destinationIata,
      'departureDate': departureDate,
      'adults': adults,
      'maxResults': maxResults,
      'currencyCode': currencyCode,
    };
    if (returnDate != null && returnDate.isNotEmpty) {
      params['returnDate'] = returnDate;
    }

    final data = await _call('searchFlights', params);
    final offers = (data['data'] as List? ?? [])
        .map((o) => FlightOffer.fromJson(Map<String, dynamic>.from(o)))
        .toList();
    return offers;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FLIGHT BOOKING
  // ─────────────────────────────────────────────────────────────────────────

  /// Confirm the current price of a flight offer before booking.
  ///
  /// Returns the confirmed flight offer with up-to-date pricing.
  Future<Map<String, dynamic>> confirmFlightPrice(
    Map<String, dynamic> rawOfferJson,
  ) async {
    final data = await _call('confirmFlightPrice', {
      'rawOfferJson': rawOfferJson,
    });

    final confirmedOffers = data['data']?['flightOffers'] as List? ?? [];
    if (confirmedOffers.isEmpty) {
      throw AmadeusException('No confirmed pricing returned');
    }
    return Map<String, dynamic>.from(confirmedOffers.first);
  }

  /// Create a flight order (booking) with traveler details.
  ///
  /// Returns a [FlightOrder] with the PNR reference and booking details.
  /// [payment] — Optional credit card payment details.
  Future<FlightOrder> createFlightOrder({
    required Map<String, dynamic> confirmedOfferJson,
    required List<Map<String, dynamic>> travelers,
    required Map<String, dynamic> contact,
    Map<String, dynamic>? payment,
    String? remarks,
  }) async {
    final offerId = confirmedOfferJson['id'] ?? '1';

    final orderData = <String, dynamic>{
      'type': 'flight-order',
      'flightOffers': [confirmedOfferJson],
      'travelers': travelers,
      'contacts': [contact],
      'ticketingAgreement': {
        'option': 'DELAY_TO_QUEUE',
        'dateTime': DateTime.now()
            .add(const Duration(days: 1))
            .toIso8601String()
            .split('.')
            .first,
      },
    };

    // Add payment if provided
    if (payment != null) {
      orderData['formOfPayment'] = {
        'other': {
          'method': 'CASH',
          'flightOfferIds': [offerId],
        },
      };
    }

    if (remarks != null) {
      orderData['remarks'] = {
        'general': [
          {'subType': 'GENERAL_MISCELLANEOUS', 'text': remarks},
        ],
      };
    }

    final data = await _call('createFlightOrder', {'orderData': orderData});

    final respData = data['data'] ?? data;
    return FlightOrder.fromJson(Map<String, dynamic>.from(respData));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HOTEL SEARCH
  // ─────────────────────────────────────────────────────────────────────────

  /// Step 1: Get a list of hotel IDs for a city.
  ///
  /// [cityCode] — IATA city code (e.g. "NYC", "PAR", "LON")
  /// [radius] — Search radius in KM (default 5)
  /// [maxResults] — Max hotels to return (API max ~400, default 20)
  Future<List<HotelListEntry>> searchHotelsByCity({
    required String cityCode,
    int radius = 5,
    int maxResults = 20,
  }) async {
    final data = await _call('searchHotelsByCity', {
      'cityCode': cityCode.toUpperCase(),
      'radius': radius,
    });

    final hotels = (data['data'] as List? ?? [])
        .map((h) => HotelListEntry.fromJson(Map<String, dynamic>.from(h)))
        .take(maxResults)
        .toList();
    return hotels;
  }

  /// Step 1b: Get a list of hotel IDs near a geographic coordinate.
  ///
  /// [latitude] — Latitude of the search center
  /// [longitude] — Longitude of the search center
  /// [radius] — Search radius in KM (default 5)
  /// [maxResults] — Max hotels to return (default 20)
  Future<List<HotelListEntry>> searchHotelsByGeocode({
    required double latitude,
    required double longitude,
    int radius = 5,
    int maxResults = 20,
  }) async {
    final data = await _call('searchHotelsByGeocode', {
      'latitude': latitude,
      'longitude': longitude,
      'radius': radius,
    });

    final hotels = (data['data'] as List? ?? [])
        .map((h) => HotelListEntry.fromJson(Map<String, dynamic>.from(h)))
        .take(maxResults)
        .toList();
    return hotels;
  }

  /// Step 2: Get pricing & room offers for specific hotel IDs.
  ///
  /// [hotelIds] — List of Amadeus hotel IDs (from searchHotelsByCity)
  /// [checkInDate] — Check-in date in YYYY-MM-DD format
  /// [checkOutDate] — Check-out date in YYYY-MM-DD format
  /// [adults] — Number of adult guests (default 1)
  /// [rooms] — Number of rooms (default 1)
  Future<List<HotelOfferResult>> getHotelOffers({
    required List<String> hotelIds,
    required String checkInDate,
    required String checkOutDate,
    int adults = 1,
    int rooms = 1,
    String currencyCode = 'USD',
  }) async {
    // API accepts up to ~50 hotel IDs at a time
    final ids = hotelIds.take(50).toList();

    final data = await _call('getHotelOffers', {
      'hotelIds': ids,
      'checkInDate': checkInDate,
      'checkOutDate': checkOutDate,
      'adults': adults,
      'rooms': rooms,
      'currencyCode': currencyCode,
    });

    final results = (data['data'] as List? ?? [])
        .map((h) => HotelOfferResult.fromJson(Map<String, dynamic>.from(h)))
        .where((h) => h.available && h.offers.isNotEmpty)
        .toList();
    // Sort by cheapest first
    results.sort((a, b) => a.cheapestPrice.compareTo(b.cheapestPrice));
    return results;
  }

  /// Convenience: Search hotels in one call (list → offers).
  ///
  /// Combines searchHotelsByCity + getHotelOffers into a single call
  /// for simpler usage from the UI layer.
  Future<List<HotelOfferResult>> searchHotels({
    required String cityCode,
    required String checkInDate,
    required String checkOutDate,
    int adults = 1,
    int rooms = 1,
    int maxResults = 15,
    String currencyCode = 'USD',
  }) async {
    // Step 1 — list hotels in the city
    final hotelList = await searchHotelsByCity(
      cityCode: cityCode,
      maxResults: maxResults * 2, // Fetch extra since not all will have offers
    );

    if (hotelList.isEmpty) return [];

    // Step 2 — get offers for those hotels
    final hotelIds = hotelList.map((h) => h.hotelId).toList();
    final offers = await getHotelOffers(
      hotelIds: hotelIds,
      checkInDate: checkInDate,
      checkOutDate: checkOutDate,
      adults: adults,
      rooms: rooms,
      currencyCode: currencyCode,
    );

    return offers.take(maxResults).toList();
  }

  /// Convenience: Search hotels by geographic location (lat/lng → offers).
  ///
  /// Uses geocode-based hotel search for sub-locality / precise location.
  Future<List<HotelOfferResult>> searchHotelsByLocation({
    required double latitude,
    required double longitude,
    required String checkInDate,
    required String checkOutDate,
    int adults = 1,
    int rooms = 1,
    int radius = 5,
    int maxResults = 15,
    String currencyCode = 'USD',
  }) async {
    // Step 1 — list hotels by geocode
    final hotelList = await searchHotelsByGeocode(
      latitude: latitude,
      longitude: longitude,
      radius: radius,
      maxResults: maxResults * 2,
    );

    if (hotelList.isEmpty) return [];

    // Step 2 — get offers for those hotels
    final hotelIds = hotelList.map((h) => h.hotelId).toList();
    final offers = await getHotelOffers(
      hotelIds: hotelIds,
      checkInDate: checkInDate,
      checkOutDate: checkOutDate,
      adults: adults,
      rooms: rooms,
      currencyCode: currencyCode,
    );

    return offers.take(maxResults).toList();
  }
}

/// A confirmed flight booking order from Create Flight Orders API.
class FlightOrder {
  final String id;
  final String? pnrReference; // The actual booking reference (PNR)
  final String? creationDate;
  final List<Map<String, dynamic>> travelers;
  final FlightOffer? flightOffer;

  FlightOrder({
    required this.id,
    this.pnrReference,
    this.creationDate,
    this.travelers = const [],
    this.flightOffer,
  });

  factory FlightOrder.fromJson(Map<String, dynamic> json) {
    // Extract the PNR from associatedRecords
    String? pnr;
    final records = json['associatedRecords'] as List?;
    if (records != null && records.isNotEmpty) {
      pnr = records.first['reference'];
    }

    // Parse the first flight offer in the order
    FlightOffer? offer;
    final offers = json['flightOffers'] as List?;
    if (offers != null && offers.isNotEmpty) {
      offer = FlightOffer.fromJson(offers.first);
    }

    return FlightOrder(
      id: json['id'] ?? '',
      pnrReference: pnr,
      creationDate: json['creationDate'],
      travelers: (json['travelers'] as List? ?? [])
          .map((t) => Map<String, dynamic>.from(t))
          .toList(),
      flightOffer: offer,
    );
  }
}

class AmadeusException implements Exception {
  final String message;
  final String? responseBody;

  AmadeusException(this.message, [this.responseBody]);

  @override
  String toString() => 'AmadeusException: $message';
}
