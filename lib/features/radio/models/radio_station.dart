import 'package:json_annotation/json_annotation.dart';
part 'radio_station.g.dart';

@JsonSerializable()
class RadioStation {
  @JsonKey(name: 'stationuuid')
  final String stationuuid;

  final String name;

  final String url;

  /// Pre-resolved direct stream URL from Radio Browser API.
  /// Skips playlist (.m3u/.pls) resolution and HTTP redirects.
  @JsonKey(name: 'url_resolved', defaultValue: '')
  final String urlResolved;

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

  @JsonKey(defaultValue: 0)
  final int bitrate;

  /// Returns the best URL for streaming: prefers the pre-resolved direct
  /// stream URL (skips playlist/redirect resolution), falls back to raw url.
  String get streamUrl =>
      urlResolved.isNotEmpty ? urlResolved : url;

  RadioStation({
    required this.stationuuid,
    required this.name,
    required this.url,
    this.urlResolved = '',
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
