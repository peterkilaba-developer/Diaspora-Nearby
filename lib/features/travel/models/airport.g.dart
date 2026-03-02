// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'airport.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Airport _$AirportFromJson(Map<String, dynamic> json) => Airport(
      id: json['id'] as String,
      ident: json['ident'] as String,
      type: json['type'] as String,
      name: json['name'] as String,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      isoCountry: json['iso_country'] as String,
      isoRegion: json['iso_region'] as String,
      municipality: json['municipality'] as String,
      iataCode: json['iata_code'] as String,
      localCode: json['local_code'] as String,
    );

Map<String, dynamic> _$AirportToJson(Airport instance) => <String, dynamic>{
      'id': instance.id,
      'ident': instance.ident,
      'type': instance.type,
      'name': instance.name,
      'lat': instance.lat,
      'lon': instance.lon,
      'iso_country': instance.isoCountry,
      'iso_region': instance.isoRegion,
      'municipality': instance.municipality,
      'iata_code': instance.iataCode,
      'local_code': instance.localCode,
    };
