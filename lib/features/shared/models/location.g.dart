// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'location.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UserLocation _$UserLocationFromJson(Map<String, dynamic> json) => UserLocation(
  formattedAddress: json['formatted_address'] as String,
  placeId: json['place_id'] as String? ?? '',
  geometry: json['geometry'] == null
      ? null
      : UserLocationGeometry.fromJson(json['geometry'] as Map<String, dynamic>),
  city: json['city'] as String?,
  state: json['state'] as String?,
  country: json['country'] as String?,
  countryCode: json['country_code'] as String?,
);

Map<String, dynamic> _$UserLocationToJson(UserLocation instance) =>
    <String, dynamic>{
      'formatted_address': instance.formattedAddress,
      'place_id': instance.placeId,
      'city': instance.city,
      'state': instance.state,
      'country': instance.country,
      'country_code': instance.countryCode,
      'geometry': instance.geometry?.toJson(),
    };

UserLocationGeometry _$UserLocationGeometryFromJson(
  Map<String, dynamic> json,
) => UserLocationGeometry(
  location: UserLocationCoordinates.fromJson(
    json['location'] as Map<String, dynamic>,
  ),
);

Map<String, dynamic> _$UserLocationGeometryToJson(
  UserLocationGeometry instance,
) => <String, dynamic>{'location': instance.location.toJson()};

UserLocationCoordinates _$UserLocationCoordinatesFromJson(
  Map<String, dynamic> json,
) => UserLocationCoordinates(
  lat: (json['lat'] as num).toDouble(),
  lng: (json['lng'] as num).toDouble(),
);

Map<String, dynamic> _$UserLocationCoordinatesToJson(
  UserLocationCoordinates instance,
) => <String, dynamic>{'lat': instance.lat, 'lng': instance.lng};

PastLocation _$PastLocationFromJson(Map<String, dynamic> json) => PastLocation(
  location: UserLocation.fromJson(json['location'] as Map<String, dynamic>),
  until: json['until'] as String,
);

Map<String, dynamic> _$PastLocationToJson(PastLocation instance) =>
    <String, dynamic>{
      'location': instance.location.toJson(),
      'until': instance.until,
    };
