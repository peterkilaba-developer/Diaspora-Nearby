import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

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
  final Map<String, dynamic>? rawJson; // Preserved for booking pipeline

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
  final String? iataCode;   // City IATA
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
    return offers
        .map((o) => o.totalPrice)
        .reduce((a, b) => a < b ? a : b);
  }

  /// Currency from first offer.
  String get currency =>
      offers.isNotEmpty ? offers.first.currency : 'USD';

  /// Board type from cheapest offer.
  String? get boardType {
    if (offers.isEmpty) return null;
    final cheapest = offers.reduce((a, b) =>
        a.totalPrice <= b.totalPrice ? a : b);
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
  final String? boardType;      // e.g. ROOM_ONLY, BREAKFAST
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
    final cancellation = policies['cancellation'] as Map<String, dynamic>? ?? {};
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
      case 'ROOM_ONLY': return 'Room Only';
      case 'BREAKFAST': return 'Breakfast Included';
      case 'HALF_BOARD': return 'Half Board';
      case 'FULL_BOARD': return 'Full Board';
      case 'ALL_INCLUSIVE': return 'All Inclusive';
      default: return boardType ?? 'Room Only';
    }
  }

  /// Human-readable bed info.
  String get bedInfo {
    final count = beds ?? 1;
    final type = bedType ?? 'BED';
    final typeName = type == 'DOUBLE' ? 'Double' :
        type == 'SINGLE' ? 'Single' :
        type == 'KING' ? 'King' :
        type == 'QUEEN' ? 'Queen' :
        type == 'TWIN' ? 'Twin' :
        type == 'BED' ? '' : type;
    final label = typeName.isEmpty
        ? 'Bed${count > 1 ? 's' : ''}'
        : '$typeName Bed${count > 1 ? 's' : ''}';
    return '$count $label';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AMADEUS SERVICE
// ═══════════════════════════════════════════════════════════════════════════

/// Service for interacting with the Amadeus Self-Service API.
/// Handles OAuth2 authentication, flight search, and hotel search.
class AmadeusService {
  static const String _baseUrl = 'https://test.api.amadeus.com';
  static const String _tokenUrl = '$_baseUrl/v1/security/oauth2/token';
  static const String _flightOffersUrl = '$_baseUrl/v2/shopping/flight-offers';
  static const String _flightPricingUrl = '$_baseUrl/v1/shopping/flight-offers/pricing';
  static const String _flightOrdersUrl = '$_baseUrl/v1/booking/flight-orders';
  static const String _hotelListUrl = '$_baseUrl/v1/reference-data/locations/hotels/by-city';
  static const String _hotelListByGeoUrl = '$_baseUrl/v1/reference-data/locations/hotels/by-geocode';
  static const String _hotelOffersUrl = '$_baseUrl/v3/shopping/hotel-offers';

  String? _accessToken;
  DateTime? _tokenExpiry;

  String get _apiKey => dotenv.env['AMADEUS_API_KEY'] ?? '';
  String get _apiSecret => dotenv.env['AMADEUS_API_SECRET'] ?? '';

  /// Authenticate and obtain an access token via client_credentials grant.
  Future<void> _authenticate() async {
    // Reuse valid token
    if (_accessToken != null &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!)) {
      return;
    }

    final response = await http.post(
      Uri.parse(_tokenUrl),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'client_credentials',
        'client_id': _apiKey,
        'client_secret': _apiSecret,
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      _accessToken = data['access_token'];
      final expiresIn = data['expires_in'] as int? ?? 1799;
      _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn - 60));
    } else {
      throw AmadeusException(
        'Authentication failed: ${response.statusCode}',
        response.body,
      );
    }
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
    await _authenticate();

    final queryParams = {
      'originLocationCode': originIata,
      'destinationLocationCode': destinationIata,
      'departureDate': departureDate,
      'adults': adults.toString(),
      'max': maxResults.toString(),
      'currencyCode': currencyCode,
    };

    if (returnDate != null && returnDate.isNotEmpty) {
      queryParams['returnDate'] = returnDate;
    }

    final uri = Uri.parse(_flightOffersUrl).replace(queryParameters: queryParams);

    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final offers = (data['data'] as List? ?? [])
          .map((o) => FlightOffer.fromJson(o))
          .toList();
      return offers;
    } else {
      throw AmadeusException(
        'Flight search failed: ${response.statusCode}',
        response.body,
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FLIGHT BOOKING
  // ─────────────────────────────────────────────────────────────────────────

  /// Confirm the current price of a flight offer before booking.
  ///
  /// Returns the confirmed flight offer with up-to-date pricing.
  Future<Map<String, dynamic>> confirmFlightPrice(Map<String, dynamic> rawOfferJson) async {
    await _authenticate();

    final body = json.encode({
      'data': {
        'type': 'flight-offers-pricing',
        'flightOffers': [rawOfferJson],
      }
    });

    final response = await http.post(
      Uri.parse(_flightPricingUrl),
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: body,
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final confirmedOffers = data['data']?['flightOffers'] as List? ?? [];
      if (confirmedOffers.isEmpty) {
        throw AmadeusException('No confirmed pricing returned');
      }
      return Map<String, dynamic>.from(confirmedOffers.first);
    } else {
      throw AmadeusException(
        'Flight pricing failed: ${response.statusCode}',
        response.body,
      );
    }
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
    await _authenticate();

    final offerId = confirmedOfferJson['id'] ?? '1';

    final data = <String, dynamic>{
      'type': 'flight-order',
      'flightOffers': [confirmedOfferJson],
      'travelers': travelers,
      'contacts': [contact],
      'ticketingAgreement': {
        'option': 'DELAY_TO_QUEUE',
        'dateTime': DateTime.now().add(const Duration(days: 1)).toIso8601String().split('.').first,
      },
    };

    // Add payment if provided
    if (payment != null) {
      data['formOfPayment'] = {
        'other': {
          'method': 'CASH',
          'flightOfferIds': [offerId],
        }
      };
    }

    if (remarks != null) {
      data['remarks'] = {
        'general': [
          {'subType': 'GENERAL_MISCELLANEOUS', 'text': remarks}
        ],
      };
    }

    final body = json.encode({'data': data});

    final response = await http.post(
      Uri.parse(_flightOrdersUrl),
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: body,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final respData = json.decode(response.body);
      return FlightOrder.fromJson(respData['data'] ?? respData);
    } else {
      throw AmadeusException(
        'Flight booking failed: ${response.statusCode}',
        response.body,
      );
    }
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
    await _authenticate();

    final queryParams = {
      'cityCode': cityCode.toUpperCase(),
      'radius': radius.toString(),
      'radiusUnit': 'KM',
      'hotelSource': 'ALL',
    };

    final uri = Uri.parse(_hotelListUrl).replace(queryParameters: queryParams);

    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final hotels = (data['data'] as List? ?? [])
          .map((h) => HotelListEntry.fromJson(h))
          .take(maxResults)
          .toList();
      return hotels;
    } else {
      throw AmadeusException(
        'Hotel list search failed: ${response.statusCode}',
        response.body,
      );
    }
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
    await _authenticate();

    final queryParams = {
      'latitude': latitude.toStringAsFixed(5),
      'longitude': longitude.toStringAsFixed(5),
      'radius': radius.toString(),
      'radiusUnit': 'KM',
      'hotelSource': 'ALL',
    };

    final uri = Uri.parse(_hotelListByGeoUrl).replace(queryParameters: queryParams);

    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final hotels = (data['data'] as List? ?? [])
          .map((h) => HotelListEntry.fromJson(h))
          .take(maxResults)
          .toList();
      return hotels;
    } else {
      throw AmadeusException(
        'Hotel geocode search failed: ${response.statusCode}',
        response.body,
      );
    }
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
    await _authenticate();

    // API accepts up to ~50 hotel IDs at a time
    final ids = hotelIds.take(50).toList();

    final queryParams = {
      'hotelIds': ids.join(','),
      'checkInDate': checkInDate,
      'checkOutDate': checkOutDate,
      'adults': adults.toString(),
      'roomQuantity': rooms.toString(),
      'currency': currencyCode,
      'bestRateOnly': 'true',
    };

    final uri = Uri.parse(_hotelOffersUrl).replace(queryParameters: queryParams);

    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final results = (data['data'] as List? ?? [])
          .map((h) => HotelOfferResult.fromJson(h))
          .where((h) => h.available && h.offers.isNotEmpty)
          .toList();
      // Sort by cheapest first
      results.sort((a, b) => a.cheapestPrice.compareTo(b.cheapestPrice));
      return results;
    } else {
      throw AmadeusException(
        'Hotel offers search failed: ${response.statusCode}',
        response.body,
      );
    }
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
    // Step 1 — list hotels near the coordinates
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
