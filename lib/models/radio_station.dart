import 'package:json_annotation/json_annotation.dart';
part 'radio_station.g.dart';

@JsonSerializable()
class RadioStation {
  @JsonKey(name: 'stationuuid')
  final String stationuuid;

  final String name;

  final String url;
  @JsonKey(defaultValue: '')
  final String favicon;
  @JsonKey(defaultValue: '')
  final String country;
  @JsonKey(defaultValue: '')
  final String countrycode;
  @JsonKey(defaultValue: '')
  final String tags;
  @JsonKey(defaultValue: 0)
  final int votes;

  // Helper to handle potentially missing bitrate   @JsonKey(defaultValue: 0)
  final int bitrate;
  RadioStation({
    required this.stationuuid,
    required this.name,
    required this.url,
    this.favicon = '',
    this.country = '',
    this.countrycode = '',
    this.tags = '',
    this.votes = 0,
    this.bitrate = 0,
  });
  factory RadioStation.fromJson(Map<String, dynamic> json) =>
      _$RadioStationFromJson(json);
  Map<String, dynamic> toJson() => _$RadioStationToJson(this);
}

