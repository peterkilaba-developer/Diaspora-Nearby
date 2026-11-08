import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diaspora_nearby/config/env.dart';
import 'package:diaspora_nearby/features/marketplace/utils/currency_helper.dart';
import 'package:diaspora_nearby/core/utils/location_utils.dart';

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
  final double? size; // in square meters (m²)
  final String? sizeUnit; // 'm²' (always)
  final String? listingType; // 'sale', 'rent', 'lease'
  final bool? hasTitle; // has title deed
  final String? zoning; // residential, commercial, agricultural, mixed

  // Plot-specific
  final bool? isFenced;
  final bool? hasWater;
  final bool? hasElectricity;
  final bool? hasRoad;
  final String? terrainType; // flat, hilly, sloped, waterfront

  // Farm-specific
  final double? farmableArea;
  final String? soilType; // loam, clay, sandy, etc.
  final List<String>? crops; // current or potential crops
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
    final specs = json['specs'] is Map
        ? Map<String, dynamic>.from(json['specs'] as Map)
        : const <String, dynamic>{};
    final rawPhotos = json['photos'] ?? json['photoUrls'];
    final rawSize = json['size'] ?? json['sizeSqm'] ?? specs['sizeSqm'];
    final rawSizeUnit = (json['sizeUnit'] ?? 'm²').toString();
    final normalizedSizeUnit = rawSizeUnit.toLowerCase() == 'sqm'
        ? 'm²'
        : rawSizeUnit;
    final rawCity = (json['city'] ?? json['locality']) as String?;
    final rawLocality = (json['locality'] ?? json['city']) as String?;
    final rawCountry = json['country'] as String?;
    final rawCountryCode = json['countryCode'] as String?;
    final rawState = json['state'] as String?;
    final cleanState = sanitizeStateForCountry(
      state: rawState,
      city: rawLocality ?? rawCity,
      countryCode: rawCountryCode,
      countryName: rawCountry,
    );
    var cleanTitle = (json['title'] ?? '').toString();
    if (cleanState == null &&
        rawState != null &&
        rawState.trim().isNotEmpty &&
        cleanTitle.endsWith(', ${rawState.trim()}')) {
      cleanTitle = cleanTitle
          .substring(0, cleanTitle.length - (rawState.trim().length + 2))
          .trim();
    }

    return RealEstateListing(
      id: docId,
      category: json['category'] ?? 'plot',
      ownerId: json['ownerId'] ?? '',
      ownerName: json['ownerName'] ?? '',
      ownerPhoto: (json['ownerPhoto'] ?? json['ownerPhotoUrl'] ?? '')
          .toString(),
      title: cleanTitle,
      description: json['description'] ?? '',
      photos: rawPhotos is List
          ? rawPhotos.whereType<String>().toList()
          : const <String>[],
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] ?? 'USD',
      status: json['status'] ?? 'active',
      city: rawCity,
      country: rawCountry,
      countryCode: rawCountryCode,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      address: json['address'],
      locality: rawLocality,
      subLocality: json['subLocality'],
      state: cleanState,
      localityLower:
          json['localityLower'] as String? ?? rawLocality?.toLowerCase(),
      stateLower: cleanState?.toLowerCase(),
      createdAt: json['createdAt'] is Timestamp
          ? (json['createdAt'] as Timestamp).toDate()
          : DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
                DateTime.now(),
      updatedAt: json['updatedAt'] is Timestamp
          ? (json['updatedAt'] as Timestamp).toDate()
          : DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      viewCount: (json['viewCount'] as num?)?.toInt() ?? 0,
      savedCount: (json['savedCount'] as num?)?.toInt() ?? 0,
      // Common
      size: (rawSize as num?)?.toDouble(),
      sizeUnit: normalizedSizeUnit,
      listingType: json['listingType'],
      hasTitle: (json['hasTitle'] ?? json['hasTitleDeed']) as bool?,
      zoning: (json['zoning'] ?? specs['zoning']) as String?,
      // Plot
      isFenced: (json['isFenced'] ?? specs['isFenced']) as bool?,
      hasWater: (json['hasWater'] ?? specs['hasWater']) as bool?,
      hasElectricity:
          (json['hasElectricity'] ?? specs['hasElectricity']) as bool?,
      hasRoad: (json['hasRoad'] ?? specs['hasRoad']) as bool?,
      terrainType: (json['terrainType'] ?? specs['terrainType']) as String?,
      // Farm
      farmableArea: ((json['farmableArea'] ?? specs['farmableArea']) as num?)
          ?.toDouble(),
      soilType: (json['soilType'] ?? specs['soilType']) as String?,
      crops: json['crops'] is List
          ? (json['crops'] as List).whereType<String>().toList()
          : null,
      hasIrrigation: (json['hasIrrigation'] ?? specs['hasIrrigation']) as bool?,
      hasStorage: (json['hasStorage'] ?? specs['hasStorage']) as bool?,
      workers: ((json['workers'] ?? specs['workers']) as num?)?.toInt(),
      // House
      bedrooms: ((json['bedrooms'] ?? specs['bedrooms']) as num?)?.toInt(),
      bathrooms: ((json['bathrooms'] ?? specs['bathrooms']) as num?)?.toInt(),
      floors: ((json['floors'] ?? specs['floors']) as num?)?.toInt(),
      propertyCondition:
          (json['propertyCondition'] ?? specs['propertyCondition']) as String?,
      yearBuilt: ((json['yearBuilt'] ?? specs['yearBuilt']) as num?)?.toInt(),
      livingArea: ((json['livingArea'] ?? specs['livingArea']) as num?)
          ?.toDouble(),
      livingAreaUnit:
          (json['livingAreaUnit'] ?? specs['livingAreaUnit']) as String?,
      amenities: json['amenities'] is List
          ? (json['amenities'] as List).whereType<String>().toList()
          : null,
      hasGarage: (json['hasGarage'] ?? specs['hasGarage']) as bool?,
      hasGarden: (json['hasGarden'] ?? specs['hasGarden']) as bool?,
      // GPS Survey
      boundaryPoints: json['boundaryPoints'] != null
          ? List<Map<String, double>>.from(
              (json['boundaryPoints'] as List).map(
                (p) => {
                  'lat': (p['lat'] as num).toDouble(),
                  'lng': (p['lng'] as num).toDouble(),
                },
              ),
            )
          : null,
      centerLat: (json['centerLat'] as num?)?.toDouble(),
      centerLng: (json['centerLng'] as num?)?.toDouble(),
      calculatedAreaSqm: (json['calculatedAreaSqm'] as num?)?.toDouble(),
      locationVerified:
          (json['locationVerified'] ?? json['isVerified']) as bool?,
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
        .map(
          (p) =>
              '${p['lat']!.toStringAsFixed(6)},${p['lng']!.toStringAsFixed(6)}',
        )
        .join('|');
    final first = boundaryPoints!.first;
    final closedPath =
        '$pathPoints|${first['lat']!.toStringAsFixed(6)},${first['lng']!.toStringAsFixed(6)}';
    final center =
        '${centerLat!.toStringAsFixed(6)},${centerLng!.toStringAsFixed(6)}';

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

  /// Google Maps Static API road-map (location map) URL with boundary overlay.
  /// Returns null if no boundary points are available.
  String? get mapImageUrl {
    if (boundaryPoints == null || boundaryPoints!.isEmpty) return null;
    if (centerLat == null || centerLng == null) return null;

    final pathPoints = boundaryPoints!
        .map(
          (p) =>
              '${p['lat']!.toStringAsFixed(6)},${p['lng']!.toStringAsFixed(6)}',
        )
        .join('|');
    final first = boundaryPoints!.first;
    final closedPath =
        '$pathPoints|${first['lat']!.toStringAsFixed(6)},${first['lng']!.toStringAsFixed(6)}';
    final center =
        '${centerLat!.toStringAsFixed(6)},${centerLng!.toStringAsFixed(6)}';

    return 'https://maps.googleapis.com/maps/api/staticmap'
        '?center=$center'
        '&zoom=16'
        '&size=600x400'
        '&scale=2'
        '&maptype=roadmap'
        '&path=color:0xFFFF6B35|weight:3|fillcolor:0x30FF6B35|$closedPath'
        '&markers=size:small|color:red|$center'
        '&key=${Env.googleMapsApiKey}';
  }

  String get locationLabel {
    return formatTieredLocation(
      subLocality: subLocality,
      city: (locality != null && locality!.isNotEmpty) ? locality : city,
      state: state,
      country: country,
      countryCode: countryCode,
      includeSubLocality: true,
      includeCountry: false,
    );
  }

  String get subtitleLabel {
    final parts = <String>[];
    if (listingType != null) {
      parts.add(
        'For ${listingType!.substring(0, 1).toUpperCase()}${listingType!.substring(1)}',
      );
    }
    if (size != null) parts.add(sizeLabelShort);

    if (category == 'house') {
      if (bedrooms != null) {
        parts.add('$bedrooms bed${bedrooms! > 1 ? 's' : ''}');
      }
      if (bathrooms != null) {
        parts.add('$bathrooms bath${bathrooms! > 1 ? 's' : ''}');
      }
    } else if (category == 'farm') {
      if (farmableArea != null) {
        parts.add('${farmableArea!.toStringAsFixed(0)} m² farmable');
      }
      if (crops != null && crops!.isNotEmpty) {
        parts.add(crops!.take(2).join(', '));
      }
    } else {
      // Plot
      if (zoning != null) parts.add(zoning!);
      if (terrainType != null) parts.add(terrainType!);
    }
    return parts.join(' • ');
  }

  String get categoryLabel {
    switch (category) {
      case 'plot':
        return 'Plot';
      case 'farm':
        return 'Farm';
      case 'house':
        return 'House';
      default:
        return category;
    }
  }

  RealEstateListing copyWith({
    String? id,
    String? category,
    String? ownerId,
    String? ownerName,
    String? ownerPhoto,
    String? title,
    String? description,
    List<String>? photos,
    double? price,
    String? currency,
    String? status,
    String? city,
    String? country,
    String? countryCode,
    double? lat,
    double? lng,
    String? address,
    String? locality,
    String? subLocality,
    String? state,
    String? localityLower,
    String? stateLower,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? viewCount,
    int? savedCount,
    double? size,
    String? sizeUnit,
    String? listingType,
    bool? hasTitle,
    String? zoning,
    bool? isFenced,
    bool? hasWater,
    bool? hasElectricity,
    bool? hasRoad,
    String? terrainType,
    double? farmableArea,
    String? soilType,
    List<String>? crops,
    bool? hasIrrigation,
    bool? hasStorage,
    int? workers,
    int? bedrooms,
    int? bathrooms,
    int? floors,
    String? propertyCondition,
    int? yearBuilt,
    double? livingArea,
    String? livingAreaUnit,
    List<String>? amenities,
    bool? hasGarage,
    bool? hasGarden,
    List<Map<String, double>>? boundaryPoints,
    double? centerLat,
    double? centerLng,
    double? calculatedAreaSqm,
    bool? locationVerified,
  }) {
    return RealEstateListing(
      id: id ?? this.id,
      category: category ?? this.category,
      ownerId: ownerId ?? this.ownerId,
      ownerName: ownerName ?? this.ownerName,
      ownerPhoto: ownerPhoto ?? this.ownerPhoto,
      title: title ?? this.title,
      description: description ?? this.description,
      photos: photos ?? this.photos,
      price: price ?? this.price,
      currency: currency ?? this.currency,
      status: status ?? this.status,
      city: city ?? this.city,
      country: country ?? this.country,
      countryCode: countryCode ?? this.countryCode,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      address: address ?? this.address,
      locality: locality ?? this.locality,
      subLocality: subLocality ?? this.subLocality,
      state: state ?? this.state,
      localityLower: localityLower ?? this.localityLower,
      stateLower: stateLower ?? this.stateLower,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      viewCount: viewCount ?? this.viewCount,
      savedCount: savedCount ?? this.savedCount,
      size: size ?? this.size,
      sizeUnit: sizeUnit ?? this.sizeUnit,
      listingType: listingType ?? this.listingType,
      hasTitle: hasTitle ?? this.hasTitle,
      zoning: zoning ?? this.zoning,
      isFenced: isFenced ?? this.isFenced,
      hasWater: hasWater ?? this.hasWater,
      hasElectricity: hasElectricity ?? this.hasElectricity,
      hasRoad: hasRoad ?? this.hasRoad,
      terrainType: terrainType ?? this.terrainType,
      farmableArea: farmableArea ?? this.farmableArea,
      soilType: soilType ?? this.soilType,
      crops: crops ?? this.crops,
      hasIrrigation: hasIrrigation ?? this.hasIrrigation,
      hasStorage: hasStorage ?? this.hasStorage,
      workers: workers ?? this.workers,
      bedrooms: bedrooms ?? this.bedrooms,
      bathrooms: bathrooms ?? this.bathrooms,
      floors: floors ?? this.floors,
      propertyCondition: propertyCondition ?? this.propertyCondition,
      yearBuilt: yearBuilt ?? this.yearBuilt,
      livingArea: livingArea ?? this.livingArea,
      livingAreaUnit: livingAreaUnit ?? this.livingAreaUnit,
      amenities: amenities ?? this.amenities,
      hasGarage: hasGarage ?? this.hasGarage,
      hasGarden: hasGarden ?? this.hasGarden,
      boundaryPoints: boundaryPoints ?? this.boundaryPoints,
      centerLat: centerLat ?? this.centerLat,
      centerLng: centerLng ?? this.centerLng,
      calculatedAreaSqm: calculatedAreaSqm ?? this.calculatedAreaSqm,
      locationVerified: locationVerified ?? this.locationVerified,
    );
  }
}
