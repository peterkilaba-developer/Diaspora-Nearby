// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'radio_station.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RadioStation _$RadioStationFromJson(Map<String, dynamic> json) => RadioStation(
      stationuuid: json['stationuuid'] as String,
      name: json['name'] as String,
      url: json['url'] as String,
      favicon: json['favicon'] as String? ?? '',
      country: json['country'] as String? ?? '',
      countrycode: json['countrycode'] as String? ?? '',
      tags: json['tags'] as String? ?? '',
      votes: json['votes'] as int? ?? 0,
      bitrate: json['bitrate'] as int? ?? 0,
    );

Map<String, dynamic> _$RadioStationToJson(RadioStation instance) =>
    <String, dynamic>{
      'stationuuid': instance.stationuuid,
      'name': instance.name,
      'url': instance.url,
      'favicon': instance.favicon,
      'country': instance.country,
      'countrycode': instance.countrycode,
      'tags': instance.tags,
      'votes': instance.votes,
      'bitrate': instance.bitrate,
    };
