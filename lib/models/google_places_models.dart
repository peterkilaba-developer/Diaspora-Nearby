/// Independent data models for Google Places
/// Replaces dependnecy on flutter_google_places_sdk

class AutocompletePrediction {
  final String placeId;
  final String primaryText;
  final String secondaryText;
  final String fullText;
  final int? distanceMeters;
  final List<String>? placeTypes;

  AutocompletePrediction({
    required this.placeId,
    required this.primaryText,
    required this.secondaryText,
    required this.fullText,
    this.distanceMeters,
    this.placeTypes,
  });
}

class FetchPlaceResponse {
  final Place place;

  FetchPlaceResponse(this.place);
}

class Place {
  final String? id;
  final String? name;
  final String? address;
  final LatLng? latLng;
  final List<AddressComponent>? addressComponents;
  final List<String>? types;
  
  // Extra fields to match previous API usage if needed, though likely unused
  final List<String>? attributions;
  final String? businessStatus;
  final String? nameLanguageCode;
  final dynamic openingHours; // Keep dynamic or simpler if not used
  final String? phoneNumber;
  final List<dynamic>? photoMetadatas;
  final dynamic plusCode;
  final int? priceLevel;
  final double? rating;
  final int? userRatingsTotal;
  final int? utcOffsetMinutes;
  final dynamic viewport;
  final Uri? websiteUri;
  final List<dynamic>? reviews;
  final String? editorialSummary;

  Place({
    this.id,
    this.name,
    this.address,
    this.latLng,
    this.addressComponents,
    this.types,
    this.attributions,
    this.businessStatus,
    this.nameLanguageCode,
    this.openingHours,
    this.phoneNumber,
    this.photoMetadatas,
    this.plusCode,
    this.priceLevel,
    this.rating,
    this.userRatingsTotal,
    this.utcOffsetMinutes,
    this.viewport,
    this.websiteUri,
    this.reviews,
    this.editorialSummary,
  });
}

class LatLng {
  final double lat;
  final double lng;

  const LatLng({required this.lat, required this.lng});
}

class AddressComponent {
  final String name;
  final String shortName;
  final List<String> types;

  AddressComponent({
    required this.name,
    required this.shortName,
    required this.types,
  });
}

enum PlaceTypeFilter {
  GEOCODE,
  ADDRESS,
  ESTABLISHMENT,
  REGIONS,
  CITIES,
  VENUES, // Custom filter: Allow establishment OR address, but BLOCK generic regions
}

class PlaceType {
  static const String RESTAURANT = 'restaurant';
  static const String STORE = 'store';
  static const String CAFE = 'cafe';
  static const String BANK = 'bank';
  static const String POST_OFFICE = 'post_office';
  static const String CHURCH = 'church';
  static const String HINDU_TEMPLE = 'hindu_temple';
  static const String MOSQUE = 'mosque';
  static const String SYNAGOGUE = 'synagogue';
  static const String CITY_HALL = 'city_hall';
  static const String LOCAL_GOVERNMENT_OFFICE = 'local_government_office';
  static const String COURTHOUSE = 'courthouse';
}
