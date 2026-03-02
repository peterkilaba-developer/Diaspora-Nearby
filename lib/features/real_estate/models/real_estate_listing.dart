import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diaspora_nearby/config/env.dart';
import 'package:diaspora_nearby/features/marketplace/utils/currency_helper.dart';

/// Model for real estate listings: plots, farms, and houses.
class RealEstateListing {
  final String id;
  final String category; // 'plot', 'farm', 'house'
  final String ownerId;
  final String ownerName;
  final String ownerPhoto;
  final String title;
  final String description;
  final List<String> photos;
  final double price;
  final String currency;
  final String status; // 'active', 'paused', 'sold'
  final String? city;
  final String? country;
  final String? countryCode;
  final double? lat;
  final double? lng;
  final String? address;

  // Structured location
  final String? locality;
  final String? subLocality;
  final String? state;
  final String? localityLower;
  final String? stateLower;
  final DateTime createdAt;
  final DateTime? updatedAt;

  // Engagement counters
  final int viewCount;
  final int savedCount;

  // Common real estate fields
  final double? size;           // in square meters (m²)
  final String? sizeUnit;       // 'm²' (always)
  final String? listingType;    // 'sale', 'rent', 'lease'
  final bool? hasTitle;         // has title deed
  final String? zoning;         // residential, commercial, agricultural, mixed

  // Plot-specific
  final bool? isFenced;
  final bool? hasWater;
  final bool? hasElectricity;
  final bool? hasRoad;
  final String? terrainType;    // flat, hilly, sloped, waterfront

  // Farm-specific
  final double? farmableArea;
  final String? soilType;       // loam, clay, sandy, etc.
  final List<String>? crops;    // current or potential crops
  final bool? hasIrrigation;
  final bool? hasStorage;
  final int? workers;

  // House-specific
  final int? bedrooms;
  final int? bathrooms;
  final int? floors;
  final String? propertyCondition; // new, renovated, needs-work, etc.
  final int? yearBuilt;
  final double? livingArea;
  final String? livingAreaUnit;
  final List<String>? amenities;
  final bool? hasGarage;
  final bool? hasGarden;

  // GPS Land Survey data
  final List<Map<String, double>>? boundaryPoints; // [{lat, lng}, ...]
  final double? centerLat;
  final double? centerLng;
  final double? calculatedAreaSqm;
  final bool? locationVerified; // GPS-verified location

  RealEstateListing({
    required this.id,
    required this.category,
    required this.ownerId,
    required this.ownerName,
    this.ownerPhoto = '',
    required this.title,
    required this.description,
    this.photos = const [],
    required this.price,
    this.currency = 'USD',
    this.status = 'active',
    this.city,
    this.country,
    this.countryCode,
    this.lat,
    this.lng,
    this.address,
    this.locality,
    this.subLocality,
    this.state,
    this.localityLower,
    this.stateLower,
    DateTime? createdAt,
    this.updatedAt,
    this.viewCount = 0,
    this.savedCount = 0,
    // Common
    this.size,
    this.sizeUnit,
    this.listingType,
    this.hasTitle,
    this.zoning,
    // Plot
    this.isFenced,
    this.hasWater,
    this.hasElectricity,
    this.hasRoad,
    this.terrainType,
    // Farm
    this.farmableArea,
    this.soilType,
    this.crops,
    this.hasIrrigation,
    this.hasStorage,
    this.workers,
    // House
    this.bedrooms,
    this.bathrooms,
    this.floors,
    this.propertyCondition,
    this.yearBuilt,
    this.livingArea,
    this.livingAreaUnit,
    this.amenities,
    this.hasGarage,
    this.hasGarden,
    // GPS Survey
    this.boundaryPoints,
    this.centerLat,
    this.centerLng,
    this.calculatedAreaSqm,
    this.locationVerified,
  }) : createdAt = createdAt ?? DateTime.now();

  factory RealEstateListing.fromJson(Map<String, dynamic> json, String docId) {
    return RealEstateListing(
      id: docId,
      category: json['category'] ?? 'plot',
      ownerId: json['ownerId'] ?? '',
      ownerName: json['ownerName'] ?? '',
      ownerPhoto: json['ownerPhoto'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      photos: List<String>.from(json['photos'] ?? []),
      price: (json['price'] ?? 0).toDouble(),
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
          : DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: json['updatedAt'] is Timestamp
          ? (json['updatedAt'] as Timestamp).toDate()
          : null,
      viewCount: json['viewCount'] as int? ?? 0,
      savedCount: json['savedCount'] as int? ?? 0,
      // Common
      size: json['size']?.toDouble(),
      sizeUnit: json['sizeUnit'],
      listingType: json['listingType'],
      hasTitle: json['hasTitle'],
      zoning: json['zoning'],
      // Plot
      isFenced: json['isFenced'],
      hasWater: json['hasWater'],
      hasElectricity: json['hasElectricity'],
      hasRoad: json['hasRoad'],
      terrainType: json['terrainType'],
      // Farm
      farmableArea: json['farmableArea']?.toDouble(),
      soilType: json['soilType'],
      crops: json['crops'] != null ? List<String>.from(json['crops']) : null,
      hasIrrigation: json['hasIrrigation'],
      hasStorage: json['hasStorage'],
      workers: json['workers'],
      // House
      bedrooms: json['bedrooms'],
      bathrooms: json['bathrooms'],
      floors: json['floors'],
      propertyCondition: json['propertyCondition'],
      yearBuilt: json['yearBuilt'],
      livingArea: json['livingArea']?.toDouble(),
      livingAreaUnit: json['livingAreaUnit'],
      amenities: json['amenities'] != null
          ? List<String>.from(json['amenities'])
          : null,
      hasGarage: json['hasGarage'],
      hasGarden: json['hasGarden'],
      // GPS Survey
      boundaryPoints: json['boundaryPoints'] != null
          ? List<Map<String, double>>.from(
              (json['boundaryPoints'] as List).map((p) => {
                    'lat': (p['lat'] as num).toDouble(),
                    'lng': (p['lng'] as num).toDouble(),
                  }))
          : null,
      centerLat: json['centerLat']?.toDouble(),
      centerLng: json['centerLng']?.toDouble(),
      calculatedAreaSqm: json['calculatedAreaSqm']?.toDouble(),
      locationVerified: json['locationVerified'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'category': category,
      'ownerId': ownerId,
      'ownerName': ownerName,
      'ownerPhoto': ownerPhoto,
      'title': title,
      'description': description,
      'photos': photos,
      'price': price,
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
      // Common
      if (size != null) 'size': size,
      if (sizeUnit != null) 'sizeUnit': sizeUnit,
      if (listingType != null) 'listingType': listingType,
      if (hasTitle != null) 'hasTitle': hasTitle,
      if (zoning != null) 'zoning': zoning,
      // Plot
      if (isFenced != null) 'isFenced': isFenced,
      if (hasWater != null) 'hasWater': hasWater,
      if (hasElectricity != null) 'hasElectricity': hasElectricity,
      if (hasRoad != null) 'hasRoad': hasRoad,
      if (terrainType != null) 'terrainType': terrainType,
      // Farm
      if (farmableArea != null) 'farmableArea': farmableArea,
      if (soilType != null) 'soilType': soilType,
      if (crops != null) 'crops': crops,
      if (hasIrrigation != null) 'hasIrrigation': hasIrrigation,
      if (hasStorage != null) 'hasStorage': hasStorage,
      if (workers != null) 'workers': workers,
      // House
      if (bedrooms != null) 'bedrooms': bedrooms,
      if (bathrooms != null) 'bathrooms': bathrooms,
      if (floors != null) 'floors': floors,
      if (propertyCondition != null) 'propertyCondition': propertyCondition,
      if (yearBuilt != null) 'yearBuilt': yearBuilt,
      if (livingArea != null) 'livingArea': livingArea,
      if (livingAreaUnit != null) 'livingAreaUnit': livingAreaUnit,
      if (amenities != null) 'amenities': amenities,
      if (hasGarage != null) 'hasGarage': hasGarage,
      if (hasGarden != null) 'hasGarden': hasGarden,
      // GPS Survey
      if (boundaryPoints != null) 'boundaryPoints': boundaryPoints,
      if (centerLat != null) 'centerLat': centerLat,
      if (centerLng != null) 'centerLng': centerLng,
      if (calculatedAreaSqm != null) 'calculatedAreaSqm': calculatedAreaSqm,
      if (locationVerified != null) 'locationVerified': locationVerified,
    };
  }

  String get priceLabel {
    final symbol = CurrencyHelper.currencySymbol(countryCode);
    return '$symbol${CurrencyHelper.formatCompact(price)}';
  }

  String get sizeLabel {
    if (size == null) return '';
    final sqm = size!;
    final sqft = sqm * 10.7639;
    return '${sqm.toStringAsFixed(0)} m² / ${sqft.toStringAsFixed(0)} ft²';
  }

  /// Size label in short form for card chips.
  String get sizeLabelShort {
    if (size == null) return '';
    return '${size!.toStringAsFixed(0)} m²';
  }

  /// Google Maps Static API satellite image URL.
  /// Returns null if no boundary points are available.
  String? get satelliteImageUrl {
    if (boundaryPoints == null || boundaryPoints!.isEmpty) return null;
    if (centerLat == null || centerLng == null) return null;

    final pathPoints = boundaryPoints!
        .map((p) => '${p['lat']!.toStringAsFixed(6)},${p['lng']!.toStringAsFixed(6)}')
        .join('|');
    final first = boundaryPoints!.first;
    final closedPath =
        '$pathPoints|${first['lat']!.toStringAsFixed(6)},${first['lng']!.toStringAsFixed(6)}';
    final center = '${centerLat!.toStringAsFixed(6)},${centerLng!.toStringAsFixed(6)}';

    return 'https://maps.googleapis.com/maps/api/staticmap'
        '?center=$center'
        '&zoom=18'
        '&size=600x400'
        '&scale=2'
        '&maptype=satellite'
        '&path=color:0xFFFF6B35|weight:3|fillcolor:0x40FF6B35|$closedPath'
        '&markers=size:small|color:red|$center'
        '&key=${Env.googleMapsApiKey}';
  }

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
    final parts = <String>[];
    if (listingType != null) {
      parts.add('For ${listingType!.substring(0, 1).toUpperCase()}${listingType!.substring(1)}');
    }
    if (size != null) parts.add(sizeLabelShort);

    if (category == 'house') {
      if (bedrooms != null) parts.add('$bedrooms bed${bedrooms! > 1 ? 's' : ''}');
      if (bathrooms != null) parts.add('$bathrooms bath${bathrooms! > 1 ? 's' : ''}');
    } else if (category == 'farm') {
      if (farmableArea != null) parts.add('${farmableArea!.toStringAsFixed(0)} m² farmable');
      if (crops != null && crops!.isNotEmpty) parts.add(crops!.take(2).join(', '));
    } else {
      // Plot
      if (zoning != null) parts.add(zoning!);
      if (terrainType != null) parts.add(terrainType!);
    }
    return parts.join(' • ');
  }

  String get categoryLabel {
    switch (category) {
      case 'plot': return 'Plot';
      case 'farm': return 'Farm';
      case 'house': return 'House';
      default: return category;
    }
  }
}
