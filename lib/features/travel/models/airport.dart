import 'package:json_annotation/json_annotation.dart';

part 'airport.g.dart';

@JsonSerializable()
class Airport {
  final String id;
  final String ident;
  final String type;
  final String name;
  final double lat;
  final double lon;

  @JsonKey(name: 'iso_country')
  final String isoCountry;

  @JsonKey(name: 'iso_region')
  final String isoRegion;

  final String municipality;

  @JsonKey(name: 'iata_code')
  final String iataCode;

  @JsonKey(name: 'local_code')
  final String localCode;

  Airport({
    required this.id,
    required this.ident,
    required this.type,
    required this.name,
    required this.lat,
    required this.lon,
    required this.isoCountry,
    required this.isoRegion,
    required this.municipality,
    required this.iataCode,
    required this.localCode,
  });

  factory Airport.fromJson(Map<String, dynamic> json) =>
      _$AirportFromJson(json);
  Map<String, dynamic> toJson() => _$AirportToJson(this);
}
