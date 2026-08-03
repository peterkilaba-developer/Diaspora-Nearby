import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diaspora_nearby/features/marketplace/utils/currency_helper.dart';
import 'package:diaspora_nearby/features/travel/services/amadeus_service.dart';

/// Unified model for peer-to-peer stay, car rental & hotel listings.
class PeerListing {
  final String id;
  final String type; // 'stay', 'car', or 'hotel'
  final bool isPeerHosting; // True if free community hosting, false if paid stay
  final String ownerId;
  final String ownerName;
  final String ownerPhoto;
  final String title;
  final String description;
  final List<String> photos;
  final double pricePerUnit; // per night (stay) or per day (car)
  final String currency;
  final String status; // 'active', 'paused'
  final String? city;
  final String? country;
  final String? countryCode;
  final double? lat;
  final double? lng;
  final String? address;

  // Structured location for community-based search
  final String? locality; // City (e.g. "Houston")
  final String? subLocality; // Neighborhood/area (e.g. "Midtown")
  final String? state; // State/province (e.g. "Texas")
  final String? localityLower; // Lowercase for Firestore queries
  final String? stateLower; // Lowercase for Firestore queries
  final DateTime createdAt;
  final DateTime? updatedAt;

  // Engagement counters
  final int viewCount;
  final int savedCount;

  // Stay-specific
  final String? propertyType; // apartment, house, room, villa
  final int? beds;
  final int? baths;
  final int? maxGuests;
  final List<String>? amenities;

  // Car-specific
  final String? make;
  final String? model;
  final int? year;
  final String? vin;
  final String? transmission; // automatic, manual
  final int? seats;
  final String? fuelType; // petrol, diesel, electric, hybrid
  final String? drivetrain; // FWD, RWD, AWD, 4WD
  final String? bodyType; // sedan, suv, etc.
  final String? trim;
  final String? series;
  final int? doors;
  final String? engineSize; // e.g. "2.5L 4-cyl (203 hp)"
  final String? engineHP;
  final String? engineLabel; // e.g. "2.5L I4"
  final int? mileage;
  final String? vehicleType;
  final String? abs;
  final String? airbagLocations;
  final String? gvwr;
  final String? electrificationType;
  final String? batteryKWh;
  final String? plantCountry;
  final String? plantCity;
  final List<String>? features; // GPS, AC, bluetooth, etc.

  // Hotel-specific
  final int? starRating; // 1–5 stars
  final String? hotelCategory; // boutique, resort, business, hostel, etc.
  final String? checkInTime; // e.g. "15:00"
  final String? checkOutTime; // e.g. "11:00"

  PeerListing({
    required this.id,
    required this.type,
    this.isPeerHosting = false,
    required this.ownerId,
    required this.ownerName,
    this.ownerPhoto = '',
    required this.title,
    required this.description,
    this.photos = const [],
    required this.pricePerUnit,
    this.currency = 'USD',
    this.status = 'active',
    this.city,
    this.country,
    this.countryCode,
    this.lat,
    this.lng,
    this.locality,
    this.subLocality,
    this.state,
    this.localityLower,
    this.stateLower,
    this.address,
    DateTime? createdAt,
    this.updatedAt,
    this.viewCount = 0,
    this.savedCount = 0,
    // Stay
    this.propertyType,
    this.beds,
    this.baths,
    this.maxGuests,
    this.amenities,
    // Car
    this.make,
    this.model,
    this.year,
    this.vin,
    this.transmission,
    this.seats,
    this.fuelType,
    this.drivetrain,
    this.bodyType,
    this.trim,
    this.series,
    this.doors,
    this.engineSize,
    this.engineHP,
    this.engineLabel,
    this.mileage,
    this.vehicleType,
    this.abs,
    this.airbagLocations,
    this.gvwr,
    this.electrificationType,
    this.batteryKWh,
    this.plantCountry,
    this.plantCity,
    this.features,
    // Hotel
    this.starRating,
    this.hotelCategory,
    this.checkInTime,
    this.checkOutTime,
  }) : createdAt = createdAt ?? DateTime.now();

  factory PeerListing.fromJson(Map<String, dynamic> json, String docId) {
    return PeerListing(
      id: docId,
      type: json['type'] ?? 'stay',
      isPeerHosting: json['isPeerHosting'] as bool? ?? false,
      ownerId: json['ownerId'] ?? '',
      ownerName: json['ownerName'] ?? '',
      ownerPhoto: json['ownerPhoto'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      photos: List<String>.from(json['photos'] ?? []),
      pricePerUnit: (json['pricePerUnit'] ?? 0).toDouble(),
      currency: json['currency'] ?? 'USD',
      status: json['status'] ?? 'active',
      city: json['city'],
      country: json['country'],
      countryCode: json['countryCode'],
      lat: json['lat']?.toDouble(),
      lng: json['lng']?.toDouble(),
      address: json['address'],
      locality: json['locality'],
      subLocality: json['subLocality'],
      state: json['state'],
      localityLower: json['localityLower'],
      stateLower: json['stateLower'],
      createdAt: json['createdAt'] is Timestamp
          ? (json['createdAt'] as Timestamp).toDate()
          : DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
                DateTime.now(),
      updatedAt: json['updatedAt'] is Timestamp
          ? (json['updatedAt'] as Timestamp).toDate()
          : null,
      viewCount: json['viewCount'] as int? ?? 0,
      savedCount: json['savedCount'] as int? ?? 0,
      // Stay
      propertyType: json['propertyType'],
      beds: json['beds'],
      baths: json['baths'],
      maxGuests: json['maxGuests'],
      amenities: json['amenities'] != null
          ? List<String>.from(json['amenities'])
          : null,
      // Car
      make: json['make'],
      model: json['model'],
      year: json['year'],
      vin: json['vin'],
      transmission: json['transmission'],
      seats: json['seats'],
      fuelType: json['fuelType'],
      drivetrain: json['drivetrain'],
      bodyType: json['bodyType'],
      trim: json['trim'],
      series: json['series'],
      doors: json['doors'],
      engineSize: json['engineSize'],
      engineHP: json['engineHP'],
      engineLabel: json['engineLabel'],
      mileage: json['mileage'],
      vehicleType: json['vehicleType'],
      abs: json['abs'],
      airbagLocations: json['airbagLocations'],
      gvwr: json['gvwr'],
      electrificationType: json['electrificationType'],
      batteryKWh: json['batteryKWh'],
      plantCountry: json['plantCountry'],
      plantCity: json['plantCity'],
      features: json['features'] != null
          ? List<String>.from(json['features'])
          : null,
      // Hotel
      starRating: json['starRating'],
      hotelCategory: json['hotelCategory'],
      checkInTime: json['checkInTime'],
      checkOutTime: json['checkOutTime'],
    );
  }

  /// Convert an Amadeus API hotel result into a [PeerListing] so the
  /// unified card & detail screen can render it.
  factory PeerListing.fromHotelOffer(
    HotelOfferResult hotel, {
    String? city,
    String? country,
    String? countryCode,
  }) {
    final cheapest = hotel.offers.isNotEmpty
        ? hotel.offers.reduce((a, b) => a.totalPrice <= b.totalPrice ? a : b)
        : null;

    // Format hotel name — Amadeus often returns ALL CAPS
    String formatName(String name) {
      if (name.isEmpty) return name;
      if (name == name.toUpperCase() && name.length > 3) {
        return name
            .split(' ')
            .map((w) {
              if (w.isEmpty || w.length <= 2) return w;
              return '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}';
            })
            .join(' ');
      }
      return name;
    }

    // Map chain codes to readable names
    const chainNames = {
      'HY': 'Hyatt',
      'HI': 'Holiday Inn',
      'BW': 'Best Western',
      'MC': 'Marriott',
      'HH': 'Hilton',
      'SI': 'Sheraton',
      'WI': 'Westin',
      'RT': 'Ritz-Carlton',
      'IC': 'InterContinental',
      'AK': 'Accor',
      'YX': 'IHG',
      'WH': 'Wyndham',
      'CW': 'Crowne Plaza',
      'EM': 'Embassy Suites',
      'HL': 'Hilton Garden Inn',
      'FN': 'Fairfield Inn',
      'CI': 'Comfort Inn',
      'RA': 'Ramada',
      'DI': 'Days Inn',
      'SB': 'Novotel',
      'PH': 'Park Hyatt',
    };

    final chainName = hotel.chainCode != null
        ? chainNames[hotel.chainCode] ?? hotel.chainCode
        : null;

    // Build a description from the cheapest offer details
    final descParts = <String>[];
    if (cheapest != null) {
      descParts.add(cheapest.bedInfo);
      descParts.add(cheapest.boardTypeDisplay);
      if (cheapest.roomDescription != null &&
          cheapest.roomDescription!.isNotEmpty) {
        descParts.add(cheapest.roomDescription!);
      }
    }

    // Build amenities from offer info
    final amenities = <String>[];
    if (cheapest != null) {
      amenities.add(cheapest.boardTypeDisplay);
      if (cheapest.cancellationDeadline != null) {
        amenities.add('Free Cancellation');
      }
      if (cheapest.paymentType == 'GUARANTEE') {
        amenities.add('Pay at Hotel');
      }
    }
    if (hotel.offers.length > 1) {
      amenities.add('${hotel.offers.length} Room Options');
    }

    return PeerListing(
      id: 'api_${hotel.hotelId}',
      type: 'hotel',
      isPeerHosting: false,
      ownerId: 'amadeus',
      ownerName: chainName ?? 'Partner Hotel',
      ownerPhoto: '',
      title: formatName(hotel.hotelName),
      description: descParts.where((s) => s.isNotEmpty).join(' • '),
      photos: const [
        'https://images.unsplash.com/photo-1566073771259-6a8506099945?w=600&h=400&fit=crop',
        'https://images.unsplash.com/photo-1551882547-ff40c63fe5fa?w=600&h=400&fit=crop',
      ],
      pricePerUnit: cheapest?.pricePerNight ?? hotel.cheapestPrice,
      currency: hotel.currency,
      lat: hotel.latitude,
      lng: hotel.longitude,
      city: city,
      country: country,
      countryCode: countryCode,
      // Hotel-specific: ensure all fields the card needs are populated
      hotelCategory: chainName ?? 'Hotel',
      beds: cheapest?.beds ?? 1,
      maxGuests: (cheapest?.beds ?? 1) * 2,
      amenities: amenities.isNotEmpty ? amenities : null,
      // Store dates as checkIn/checkOut (card will display them)
      checkInTime: cheapest?.checkInDate,
      checkOutTime: cheapest?.checkOutDate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'isPeerHosting': isPeerHosting,
      'ownerId': ownerId,
      'ownerName': ownerName,
      'ownerPhoto': ownerPhoto,
      'title': title,
      'description': description,
      'photos': photos,
      'pricePerUnit': pricePerUnit,
      'currency': currency,
      'status': status,
      'city': city,
      'country': country,
      'countryCode': countryCode,
      'lat': lat,
      'lng': lng,
      'address': address,
      'locality': locality,
      'subLocality': subLocality,
      'state': state,
      'localityLower': localityLower,
      'stateLower': stateLower,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'viewCount': viewCount,
      'savedCount': savedCount,
      // Stay
      if (propertyType != null) 'propertyType': propertyType,
      if (beds != null) 'beds': beds,
      if (baths != null) 'baths': baths,
      if (maxGuests != null) 'maxGuests': maxGuests,
      if (amenities != null) 'amenities': amenities,
      // Car
      if (make != null) 'make': make,
      if (model != null) 'model': model,
      if (year != null) 'year': year,
      if (vin != null) 'vin': vin,
      if (transmission != null) 'transmission': transmission,
      if (seats != null) 'seats': seats,
      if (fuelType != null) 'fuelType': fuelType,
      if (drivetrain != null) 'drivetrain': drivetrain,
      if (bodyType != null) 'bodyType': bodyType,
      if (trim != null) 'trim': trim,
      if (series != null) 'series': series,
      if (doors != null) 'doors': doors,
      if (engineSize != null) 'engineSize': engineSize,
      if (engineHP != null) 'engineHP': engineHP,
      if (engineLabel != null) 'engineLabel': engineLabel,
      if (mileage != null) 'mileage': mileage,
      if (vehicleType != null) 'vehicleType': vehicleType,
      if (abs != null) 'abs': abs,
      if (airbagLocations != null) 'airbagLocations': airbagLocations,
      if (gvwr != null) 'gvwr': gvwr,
      if (electrificationType != null)
        'electrificationType': electrificationType,
      if (batteryKWh != null) 'batteryKWh': batteryKWh,
      if (plantCountry != null) 'plantCountry': plantCountry,
      if (plantCity != null) 'plantCity': plantCity,
      if (features != null) 'features': features,
      // Hotel
      if (starRating != null) 'starRating': starRating,
      if (hotelCategory != null) 'hotelCategory': hotelCategory,
      if (checkInTime != null) 'checkInTime': checkInTime,
      if (checkOutTime != null) 'checkOutTime': checkOutTime,
    };
  }

  String get priceLabel {
    final unit = type == 'car' ? 'day' : 'night';
    final symbol = CurrencyHelper.currencySymbol(countryCode);
    return '$symbol${CurrencyHelper.formatCompact(pricePerUnit)}/$unit';
  }

  /// e.g. "Midtown, Houston" or "Houston, TX"
  String get locationLabel {
    final parts = <String>[];
    if (subLocality != null && subLocality!.isNotEmpty) parts.add(subLocality!);
    if (locality != null && locality!.isNotEmpty) {
      parts.add(locality!);
    } else if (city != null && city!.isNotEmpty) {
      parts.add(city!);
    }
    if (state != null && state!.isNotEmpty) parts.add(state!);
    return parts.join(', ');
  }

  String get subtitleLabel {
    if (type == 'hotel') {
      final parts = <String>[];
      if (starRating != null) parts.add('★' * starRating!);
      if (hotelCategory != null) parts.add(hotelCategory!);
      if (maxGuests != null) parts.add('Up to $maxGuests guests');
      if (beds != null) parts.add('$beds room${beds! > 1 ? 's' : ''}');
      return parts.join(' • ');
    } else if (type == 'stay') {
      final parts = <String>[];
      if (propertyType != null) parts.add(propertyType!);
      if (beds != null) parts.add('$beds Bed${beds! > 1 ? 's' : ''}');
      if (baths != null) parts.add('$baths Bath${baths! > 1 ? 's' : ''}');
      if (maxGuests != null) parts.add('Up to $maxGuests guests');
      return parts.join(' • ');
    } else {
      final parts = <String>[];
      if (make != null && model != null) parts.add('$make $model');
      if (year != null) parts.add('$year');
      if (transmission != null) parts.add(transmission!);
      if (drivetrain != null) parts.add(drivetrain!);
      if (seats != null) parts.add('$seats seats');
      return parts.join(' • ');
    }
  }
}

/// Booking for a peer listing.
class PeerBooking {
  final String id;
  final String listingId;
  final String listingType; // 'stay' or 'car'
  final String listingTitle;
  final String guestId;
  final String guestName;
  final String guestPhone;
  final String hostId;
  final String hostName;
  final DateTime startDate;
  final DateTime endDate;
  final int? guests;
  final double totalPrice;
  final String currency;
  final String status; // 'pending', 'confirmed', 'cancelled', 'completed'
  final String? notes;
  final DateTime createdAt;

  PeerBooking({
    required this.id,
    required this.listingId,
    required this.listingType,
    required this.listingTitle,
    required this.guestId,
    required this.guestName,
    this.guestPhone = '',
    required this.hostId,
    required this.hostName,
    required this.startDate,
    required this.endDate,
    this.guests,
    required this.totalPrice,
    this.currency = 'USD',
    this.status = 'pending',
    this.notes,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  int get nights {
    return endDate.difference(startDate).inDays;
  }

  factory PeerBooking.fromJson(Map<String, dynamic> json, String docId) {
    return PeerBooking(
      id: docId,
      listingId: json['listingId'] ?? '',
      listingType: json['listingType'] ?? 'stay',
      listingTitle: json['listingTitle'] ?? '',
      guestId: json['guestId'] ?? '',
      guestName: json['guestName'] ?? '',
      guestPhone: json['guestPhone'] ?? '',
      hostId: json['hostId'] ?? '',
      hostName: json['hostName'] ?? '',
      startDate: json['startDate'] is Timestamp
          ? (json['startDate'] as Timestamp).toDate()
          : DateTime.tryParse(json['startDate']?.toString() ?? '') ??
                DateTime.now(),
      endDate: json['endDate'] is Timestamp
          ? (json['endDate'] as Timestamp).toDate()
          : DateTime.tryParse(json['endDate']?.toString() ?? '') ??
                DateTime.now(),
      guests: json['guests'],
      totalPrice: (json['totalPrice'] ?? 0).toDouble(),
      currency: json['currency'] ?? 'USD',
      status: json['status'] ?? 'pending',
      notes: json['notes'],
      createdAt: json['createdAt'] is Timestamp
          ? (json['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'listingId': listingId,
      'listingType': listingType,
      'listingTitle': listingTitle,
      'guestId': guestId,
      'guestName': guestName,
      'guestPhone': guestPhone,
      'hostId': hostId,
      'hostName': hostName,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'guests': guests,
      'totalPrice': totalPrice,
      'currency': currency,
      'status': status,
      'notes': notes,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
