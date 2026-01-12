// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ChatProfileImage _$ChatProfileImageFromJson(Map<String, dynamic> json) =>
    ChatProfileImage(
      type: json['type'] as String,
      value: json['value'] as String,
      backgroundColor: json['backgroundColor'] as String?,
      gradientFrom: json['gradientFrom'] as String?,
      gradientTo: json['gradientTo'] as String?,
    );

Map<String, dynamic> _$ChatProfileImageToJson(ChatProfileImage instance) =>
    <String, dynamic>{
      'type': instance.type,
      'value': instance.value,
      'backgroundColor': instance.backgroundColor,
      'gradientFrom': instance.gradientFrom,
      'gradientTo': instance.gradientTo,
    };

LastMessage _$LastMessageFromJson(Map<String, dynamic> json) => LastMessage(
      content: json['content'] as String,
      timestamp: json['timestamp'] as int,
      senderId: json['senderId'] as String,
      senderName: json['senderName'] as String,
      type: json['type'] as String,
      mentions: (json['mentions'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      forwarded: json['forwarded'] as bool?,
      status: json['status'] as String?,
      deletedForEveryone: json['deletedForEveryone'] as bool?,
    );

Map<String, dynamic> _$LastMessageToJson(LastMessage instance) =>
    <String, dynamic>{
      'content': instance.content,
      'timestamp': instance.timestamp,
      'senderId': instance.senderId,
      'senderName': instance.senderName,
      'type': instance.type,
      'mentions': instance.mentions,
      'forwarded': instance.forwarded,
      'status': instance.status,
      'deletedForEveryone': instance.deletedForEveryone,
    };

Chat _$ChatFromJson(Map<String, dynamic> json) => Chat(
      id: json['id'] as String,
      communityId: json['communityId'] as String?,
      homeCountryCode: json['homeCountryCode'] as String?,
      hostCountryCode: json['hostCountryCode'] as String?,
      locationType: json['locationType'] as String?,
      type: json['type'] as String,
      name: json['name'] as String,
      photoUrl: json['photoUrl'] as String?,
      profileImage: json['profileImage'] == null
          ? null
          : ChatProfileImage.fromJson(
              json['profileImage'] as Map<String, dynamic>),
      participants: (json['participants'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      admins:
          (json['admins'] as List<dynamic>?)?.map((e) => e as String).toList(),
      createdBy: json['createdBy'] as String?,
      lastMessage: json['lastMessage'] == null
          ? null
          : LastMessage.fromJson(json['lastMessage'] as Map<String, dynamic>),
      createdAt: json['createdAt'] as int,
      updatedAt: json['updatedAt'] as int,
      eventId: json['eventId'] as String?,
      memberCount: json['memberCount'] as int?,
      flag: json['flag'] as String?,
    );

Map<String, dynamic> _$ChatToJson(Chat instance) => <String, dynamic>{
      'id': instance.id,
      'communityId': instance.communityId,
      'homeCountryCode': instance.homeCountryCode,
      'hostCountryCode': instance.hostCountryCode,
      'locationType': instance.locationType,
      'type': instance.type,
      'name': instance.name,
      'photoUrl': instance.photoUrl,
      'profileImage': instance.profileImage?.toJson(),
      'participants': instance.participants,
      'admins': instance.admins,
      'createdBy': instance.createdBy,
      'lastMessage': instance.lastMessage?.toJson(),
      'createdAt': instance.createdAt,
      'updatedAt': instance.updatedAt,
      'eventId': instance.eventId,
      'memberCount': instance.memberCount,
      'flag': instance.flag,
    };
