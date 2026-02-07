// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'event_data.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Event _$EventFromJson(Map<String, dynamic> json) => Event(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      startDate: json['startDate'] as String,
      startTime: json['startTime'] as String,
      endDate: json['endDate'] as String?,
      endTime: json['endTime'] as String?,
      location: json['location'] as String,
      category: json['category'] as String,
      imageUrl: json['imageUrl'] as String?,
      creatorId: json['creatorId'] as String,
      attendees: (json['attendees'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      attendeeCount: (json['attendeeCount'] as num?)?.toInt(),
      confirmedAttendees: (json['confirmedAttendees'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      interested: (json['interested'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      invitedUserIds: (json['invitedUserIds'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      isPaid: json['isPaid'] as bool?,
      ticketPrice: (json['ticketPrice'] as num?)?.toDouble(),
      chatId: json['chatId'] as String?,
      homeCountry: json['homeCountry'] as String?,
      hostCountry: json['hostCountry'] as String?,
      hostCity: json['hostCity'] as String?,
      hostState: json['hostState'] as String?,
      homeCountryCode: json['homeCountryCode'] as String?,
      hostCountryCode: json['hostCountryCode'] as String?,
      attendingPermission: json['attendingPermission'] as String?,
      maxAttendees: (json['maxAttendees'] as num?)?.toInt(),
      createdAt: json['createdAt'] as String?,
      venueName: json['venueName'] as String?,
      venueAddress: json['venueAddress'] as String?,
      venueCity: json['venueCity'] as String?,
      venueState: json['venueState'] as String?,
      venueCountry: json['venueCountry'] as String?,
      status: json['status'] as String? ?? 'draft',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      organizationId: json['organizationId'] as String?,
      organizationName: json['organizationName'] as String?,
    );

Map<String, dynamic> _$EventToJson(Event instance) => <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'description': instance.description,
      'startDate': instance.startDate,
      'startTime': instance.startTime,
      'endDate': instance.endDate,
      'endTime': instance.endTime,
      'location': instance.location,
      'category': instance.category,
      'imageUrl': instance.imageUrl,
      'creatorId': instance.creatorId,
      'attendees': instance.attendees,
      'attendeeCount': instance.attendeeCount,
      'confirmedAttendees': instance.confirmedAttendees,
      'interested': instance.interested,
      'invitedUserIds': instance.invitedUserIds,
      'isPaid': instance.isPaid,
      'ticketPrice': instance.ticketPrice,
      'chatId': instance.chatId,
      'homeCountry': instance.homeCountry,
      'hostCountry': instance.hostCountry,
      'hostCity': instance.hostCity,
      'hostState': instance.hostState,
      'homeCountryCode': instance.homeCountryCode,
      'hostCountryCode': instance.hostCountryCode,
      'attendingPermission': instance.attendingPermission,
      'maxAttendees': instance.maxAttendees,
      'createdAt': instance.createdAt,
      'venueName': instance.venueName,
      'venueAddress': instance.venueAddress,
      'venueCity': instance.venueCity,
      'venueState': instance.venueState,
      'venueCountry': instance.venueCountry,
      'status': instance.status,
      'latitude': instance.latitude,
      'longitude': instance.longitude,
      'organizationId': instance.organizationId,
      'organizationName': instance.organizationName,
    };
