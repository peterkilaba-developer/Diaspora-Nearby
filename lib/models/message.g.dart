// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MessageReaction _$MessageReactionFromJson(Map<String, dynamic> json) =>
    MessageReaction(
      emoji: json['emoji'] as String,
      userIds: (json['userIds'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$MessageReactionToJson(MessageReaction instance) =>
    <String, dynamic>{'emoji': instance.emoji, 'userIds': instance.userIds};

MessageLocation _$MessageLocationFromJson(Map<String, dynamic> json) =>
    MessageLocation(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      address: json['address'] as String,
      placeName: json['placeName'] as String?,
      placeType: json['placeType'] as String?,
    );

Map<String, dynamic> _$MessageLocationToJson(MessageLocation instance) =>
    <String, dynamic>{
      'lat': instance.lat,
      'lng': instance.lng,
      'address': instance.address,
      'placeName': instance.placeName,
      'placeType': instance.placeType,
    };

MoneyTransfer _$MoneyTransferFromJson(Map<String, dynamic> json) =>
    MoneyTransfer(
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'] as String,
      currencySymbol: json['currencySymbol'] as String,
      convertedAmount: (json['convertedAmount'] as num).toDouble(),
      convertedCurrency: json['convertedCurrency'] as String,
      convertedCurrencySymbol: json['convertedCurrencySymbol'] as String,
      exchangeRate: (json['exchangeRate'] as num).toDouble(),
      senderCountryCode: json['senderCountryCode'] as String,
      recipientCountryCode: json['recipientCountryCode'] as String,
      status: json['status'] as String,
    );

Map<String, dynamic> _$MoneyTransferToJson(MoneyTransfer instance) =>
    <String, dynamic>{
      'amount': instance.amount,
      'currency': instance.currency,
      'currencySymbol': instance.currencySymbol,
      'convertedAmount': instance.convertedAmount,
      'convertedCurrency': instance.convertedCurrency,
      'convertedCurrencySymbol': instance.convertedCurrencySymbol,
      'exchangeRate': instance.exchangeRate,
      'senderCountryCode': instance.senderCountryCode,
      'recipientCountryCode': instance.recipientCountryCode,
      'status': instance.status,
    };

Message _$MessageFromJson(Map<String, dynamic> json) => Message(
  id: json['id'] as String,
  chatId: json['chatId'] as String,
  senderId: json['senderId'] as String,
  senderName: json['senderName'] as String,
  senderImage: json['senderImage'] as String?,
  senderHostCountryCode: json['senderHostCountryCode'] as String?,
  senderHomeCountryCode: json['senderHomeCountryCode'] as String?,
  content: json['content'] as String,
  type: json['type'] as String,
  timestamp: (json['timestamp'] as num).toInt(),
  status: json['status'] as String?,
  moneyTransfer: json['moneyTransfer'] == null
      ? null
      : MoneyTransfer.fromJson(json['moneyTransfer'] as Map<String, dynamic>),
  edited: json['edited'] as bool?,
  editedAt: (json['editedAt'] as num?)?.toInt(),
  replyTo: json['replyTo'] as String?,
  mentions: (json['mentions'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  imageUrl: json['imageUrl'] as String?,
  location: json['location'] == null
      ? null
      : MessageLocation.fromJson(json['location'] as Map<String, dynamic>),
  documentUrl: json['documentUrl'] as String?,
  documentName: json['documentName'] as String?,
  documentSize: (json['documentSize'] as num?)?.toInt(),
  audioDuration: (json['audioDuration'] as num?)?.toInt(),
  reactions: (json['reactions'] as List<dynamic>?)
      ?.map((e) => MessageReaction.fromJson(e as Map<String, dynamic>))
      .toList(),
  starred: (json['starred'] as Map<String, dynamic>?)?.map(
    (k, e) => MapEntry(k, e as bool),
  ),
  deletedFor: (json['deletedFor'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  deletedForEveryone: json['deletedForEveryone'] as bool?,
  forwarded: json['forwarded'] as bool?,
  forwardCount: (json['forwardCount'] as num?)?.toInt(),
  originalSenderId: json['originalSenderId'] as String?,
  originalSenderName: json['originalSenderName'] as String?,
  originalSenderImage: json['originalSenderImage'] as String?,
  originalSenderHostCountryCode:
      json['originalSenderHostCountryCode'] as String?,
  originalSenderHomeCountryCode:
      json['originalSenderHomeCountryCode'] as String?,
  originalTimestamp: (json['originalTimestamp'] as num?)?.toInt(),
  pinned: (json['pinned'] as Map<String, dynamic>?)?.map(
    (k, e) => MapEntry(k, e as bool),
  ),
  adminId: json['adminId'] as String?,
  adminImage: json['adminImage'] as String?,
  richContent: json['richContent'] as String?,
);

Map<String, dynamic> _$MessageToJson(Message instance) => <String, dynamic>{
  'id': instance.id,
  'chatId': instance.chatId,
  'senderId': instance.senderId,
  'senderName': instance.senderName,
  'senderImage': instance.senderImage,
  'senderHostCountryCode': instance.senderHostCountryCode,
  'senderHomeCountryCode': instance.senderHomeCountryCode,
  'content': instance.content,
  'richContent': instance.richContent,
  'type': instance.type,
  'timestamp': instance.timestamp,
  'status': instance.status,
  'moneyTransfer': instance.moneyTransfer?.toJson(),
  'edited': instance.edited,
  'editedAt': instance.editedAt,
  'replyTo': instance.replyTo,
  'mentions': instance.mentions,
  'imageUrl': instance.imageUrl,
  'location': instance.location?.toJson(),
  'documentUrl': instance.documentUrl,
  'documentName': instance.documentName,
  'documentSize': instance.documentSize,
  'audioDuration': instance.audioDuration,
  'reactions': instance.reactions?.map((e) => e.toJson()).toList(),
  'starred': instance.starred,
  'deletedFor': instance.deletedFor,
  'deletedForEveryone': instance.deletedForEveryone,
  'forwarded': instance.forwarded,
  'forwardCount': instance.forwardCount,
  'originalSenderId': instance.originalSenderId,
  'originalSenderName': instance.originalSenderName,
  'originalSenderImage': instance.originalSenderImage,
  'originalSenderHostCountryCode': instance.originalSenderHostCountryCode,
  'originalSenderHomeCountryCode': instance.originalSenderHomeCountryCode,
  'originalTimestamp': instance.originalTimestamp,
  'pinned': instance.pinned,
  'adminId': instance.adminId,
  'adminImage': instance.adminImage,
};
