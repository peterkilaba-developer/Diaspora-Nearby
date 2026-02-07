// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'community_data.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Community _$CommunityFromJson(Map<String, dynamic> json) => Community(
      id: json['id'] as String,
      name: json['name'] as String,
      homeCountryCode: json['homeCountryCode'] as String?,
      hostCountryCode: json['hostCountryCode'] as String?,
      type: json['type'] as String?,
      locationType: json['locationType'] as String?,
      images: (json['images'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      memberCount: (json['memberCount'] as num?)?.toInt() ?? 0,
      totalMembers: (json['totalMembers'] as num?)?.toInt(),
      isPrivate: json['isPrivate'] as bool? ?? false,
      location: json['location'] as Map<String, dynamic>?,
      profileImage: json['profileImage'] as String?,
      chatId: json['chatId'] as String?,
      flag: json['flag'] as String?,
      members: (json['members'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      admins: (json['admins'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      createdAt: (json['createdAt'] as num?)?.toInt(),
      updatedAt: (json['updatedAt'] as num?)?.toInt(),
      points: (json['points'] as num?)?.toInt() ?? 0,
      cumulativeEarnings: (json['cumulativeEarnings'] as num?)?.toInt() ?? 0,
      memberPoints: (json['memberPoints'] as num?)?.toInt() ?? 0,
      awardedBalance: (json['awardedBalance'] as num?)?.toDouble() ?? 0,
      averagePoCT: (json['averagePoCT'] as num?)?.toDouble() ?? 0,
      walletAddress: json['walletAddress'] as String?,
    );

Map<String, dynamic> _$CommunityToJson(Community instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'homeCountryCode': instance.homeCountryCode,
      'hostCountryCode': instance.hostCountryCode,
      'locationType': instance.locationType,
      'images': instance.images,
      'profileImage': instance.profileImage,
      'type': instance.type,
      'memberCount': instance.memberCount,
      'totalMembers': instance.totalMembers,
      'isPrivate': instance.isPrivate,
      'location': instance.location,
      'chatId': instance.chatId,
      'flag': instance.flag,
      'members': instance.members,
      'admins': instance.admins,
      'createdAt': instance.createdAt,
      'updatedAt': instance.updatedAt,
      'points': instance.points,
      'cumulativeEarnings': instance.cumulativeEarnings,
      'memberPoints': instance.memberPoints,
      'awardedBalance': instance.awardedBalance,
      'averagePoCT': instance.averagePoCT,
      'walletAddress': instance.walletAddress,
    };

CommunityData _$CommunityDataFromJson(Map<String, dynamic> json) =>
    CommunityData(
      id: json['id'] as String,
      name: json['name'] as String,
      profileImage: json['profileImage'] as String?,
    );

Map<String, dynamic> _$CommunityDataToJson(CommunityData instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'profileImage': instance.profileImage,
    };
