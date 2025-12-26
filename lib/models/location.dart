import 'package:json_annotation/json_annotation.dart';
part 'location.g.dart';

@JsonSerializable(explicitToJson: true)
class UserLocation {
  @JsonKey(name: 'formatted_address')
  final String formattedAddress;
  @JsonKey(name: 'place_id')
  final String placeId;

  final String? city;

  final String? state;

  final String? country;
  @JsonKey(name: 'country_code')
  final String? countryCode;

  final UserLocationGeometry? geometry;

  const UserLocation({
    required this.formattedAddress,
    required this.placeId,
    this.geometry,
    this.city,
    this.state,
    this.country,
    this.countryCode,
  });
  factory UserLocation.fromJson(Map<String, dynamic> json) =>
      _$UserLocationFromJson(json);
  Map<String, dynamic> toJson() => _$UserLocationToJson(this);
}

@JsonSerializable(explicitToJson: true)
class UserLocationGeometry {
  final UserLocationCoordinates location;

  const UserLocationGeometry({required this.location});
  factory UserLocationGeometry.fromJson(Map<String, dynamic> json) =>
      _$UserLocationGeometryFromJson(json);
  Map<String, dynamic> toJson() => _$UserLocationGeometryToJson(this);
}

@JsonSerializable()
class UserLocationCoordinates {
  final double lat;

  final double lng;

  const UserLocationCoordinates({required this.lat, required this.lng});
  factory UserLocationCoordinates.fromJson(Map<String, dynamic> json) =>
      _$UserLocationCoordinatesFromJson(json);
  Map<String, dynamic> toJson() => _$UserLocationCoordinatesToJson(this);
}

@JsonSerializable(explicitToJson: true)
class PastLocation {
  final UserLocation location;
  final String until;

  const PastLocation({
    required this.location,
    required this.until,
  });

  factory PastLocation.fromJson(Map<String, dynamic> json) => _$PastLocationFromJson(json);
  Map<String, dynamic> toJson() => _$PastLocationToJson(this);
}
