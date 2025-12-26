import 'package:json_annotation/json_annotation.dart';

part 'message.g.dart';

/// Message reaction with emoji and list of user IDs
@JsonSerializable()
class MessageReaction {
  final String emoji;
  final List<String> userIds;

  const MessageReaction({
    required this.emoji,
    required this.userIds,
  });

  factory MessageReaction.fromJson(Map<String, dynamic> json) =>
      _$MessageReactionFromJson(json);
  Map<String, dynamic> toJson() => _$MessageReactionToJson(this);
}

/// Location data for location messages
@JsonSerializable()
class MessageLocation {
  final double lat;
  final double lng;
  final String address;
  final String? placeName;
  final String? placeType;

  const MessageLocation({
    required this.lat,
    required this.lng,
    required this.address,
    this.placeName,
    this.placeType,
  });

  factory MessageLocation.fromJson(Map<String, dynamic> json) =>
      _$MessageLocationFromJson(json);
  Map<String, dynamic> toJson() => _$MessageLocationToJson(this);

  /// Create from RTDB with null-safe parsing
  factory MessageLocation.fromRTDB(Map<String, dynamic> data) {
    double parseDouble(dynamic value, [double defaultValue = 0.0]) {
      if (value == null) return defaultValue;
      if (value is double) return value;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? defaultValue;
      return defaultValue;
    }

    return MessageLocation(
      lat: parseDouble(data['lat'] ?? data['latitude']),
      lng: parseDouble(data['lng'] ?? data['longitude']),
      address: data['address'] as String? ?? '',
      placeName: data['placeName'] as String?,
      placeType: data['placeType'] as String?,
    );
  }
}

/// Money transfer data for money-transfer messages
@JsonSerializable()
class MoneyTransfer {
  final double amount;
  final String currency;
  final String currencySymbol;
  final double convertedAmount;
  final String convertedCurrency;
  final String convertedCurrencySymbol;
  final double exchangeRate;
  final String senderCountryCode;
  final String recipientCountryCode;
  final String status; // 'pending' | 'completed' | 'failed'

  const MoneyTransfer({
    required this.amount,
    required this.currency,
    required this.currencySymbol,
    required this.convertedAmount,
    required this.convertedCurrency,
    required this.convertedCurrencySymbol,
    required this.exchangeRate,
    required this.senderCountryCode,
    required this.recipientCountryCode,
    required this.status,
  });

  factory MoneyTransfer.fromJson(Map<String, dynamic> json) =>
      _$MoneyTransferFromJson(json);
  Map<String, dynamic> toJson() => _$MoneyTransferToJson(this);

  /// Create from RTDB with null-safe parsing
  factory MoneyTransfer.fromRTDB(Map<String, dynamic> data) {
    double parseDouble(dynamic value, [double defaultValue = 0.0]) {
      if (value == null) return defaultValue;
      if (value is double) return value;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? defaultValue;
      return defaultValue;
    }

    return MoneyTransfer(
      amount: parseDouble(data['amount']),
      currency: data['currency'] as String? ?? '',
      currencySymbol: data['currencySymbol'] as String? ?? '',
      convertedAmount: parseDouble(data['convertedAmount']),
      convertedCurrency: data['convertedCurrency'] as String? ?? '',
      convertedCurrencySymbol: data['convertedCurrencySymbol'] as String? ?? '',
      exchangeRate: parseDouble(data['exchangeRate']),
      senderCountryCode: data['senderCountryCode'] as String? ?? '',
      recipientCountryCode: data['recipientCountryCode'] as String? ?? '',
      status: data['status'] as String? ?? 'pending',
    );
  }
}

/// Chat message model
/// Supports all message types: text, image, video, audio, location, document, system, money-transfer
@JsonSerializable(explicitToJson: true)
class Message {
  final String id;
  final String chatId;
  final String senderId;
  final String senderName;
  final String? senderImage;
  final String? senderHostCountryCode;
  final String? senderHomeCountryCode;
  final String content;
  final String type; // 'text' | 'image' | 'video' | 'audio' | 'location' | 'document' | 'system' | 'money-transfer'
  final int timestamp;
  final String? status; // 'sent' | 'delivered' | 'read'
  // Money transfer
  final MoneyTransfer? moneyTransfer;
  // Editing
  final bool? edited;
  final int? editedAt;
  // Reply
  final String? replyTo;
  // Mentions
  final List<String>? mentions;
  // Media
  final String? imageUrl;
  final MessageLocation? location;
  final String? documentUrl;
  final String? documentName;
  final int? documentSize;
  // Audio specific
  final int? audioDuration;
  // Reactions
  final List<MessageReaction>? reactions;
  // Actions
  final Map<String, bool>? starred;
  final List<String>? deletedFor;
  final bool? deletedForEveryone;
  final bool? forwarded;
  final int? forwardCount;
  // Original sender (for forwarded messages)
  final String? originalSenderId;
  final String? originalSenderName;
  final String? originalSenderImage;
  final String? originalSenderHostCountryCode;
  final String? originalSenderHomeCountryCode;
  final int? originalTimestamp;
  // Pinned
  final Map<String, bool>? pinned;
  // Admin Identity (when sending as Organization)
  final String? adminId;
  final String? adminImage;

  const Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.senderName,
    this.senderImage,
    this.senderHostCountryCode,
    this.senderHomeCountryCode,
    required this.content,
    required this.type,
    required this.timestamp,
    this.status,
    this.moneyTransfer,
    this.edited,
    this.editedAt,
    this.replyTo,
    this.mentions,
    this.imageUrl,
    this.location,
    this.documentUrl,
    this.documentName,
    this.documentSize,
    this.audioDuration,
    this.reactions,
    this.starred,
    this.deletedFor,
    this.deletedForEveryone,
    this.forwarded,
    this.forwardCount,
    this.originalSenderId,
    this.originalSenderName,
    this.originalSenderImage,
    this.originalSenderHostCountryCode,
    this.originalSenderHomeCountryCode,
    this.originalTimestamp,
    this.pinned,
    this.adminId,
    this.adminImage,
  });

  factory Message.fromJson(Map<String, dynamic> json) =>
      _$MessageFromJson(json);
  Map<String, dynamic> toJson() => _$MessageToJson(this);

  /// Create Message from RTDB snapshot
  factory Message.fromRTDB(String id, String chatId, Map<String, dynamic> data) {
    // Helper to safely parse int values
    int? _parseInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value);
      return null;
    }

    // Parse reactions from RTDB format
    List<MessageReaction>? reactions;
    if (data['reactions'] != null) {
      final reactionsData = data['reactions'] as Map<String, dynamic>;
      reactions = reactionsData.entries.map((e) {
        final userIds = e.value is List
            ? (e.value as List).map((u) => u.toString()).toList()
            : <String>[];
        return MessageReaction(emoji: e.key, userIds: userIds);
      }).toList();
    }

    return Message(
      id: id,
      chatId: chatId,
      senderId: data['senderId'] as String? ?? '',
      senderName: data['senderName'] as String? ?? 'Unknown',
      senderImage: data['senderImage'] as String?,
      senderHostCountryCode: data['senderHostCountryCode'] as String?,
      senderHomeCountryCode: data['senderHomeCountryCode'] as String?,
      content: data['content'] as String? ?? '',
      type: data['type'] as String? ?? 'text',
      timestamp: _parseInt(data['timestamp']) ?? 0,
      status: data['status'] as String?,
      moneyTransfer: data['moneyTransfer'] != null
          ? MoneyTransfer.fromRTDB(data['moneyTransfer'] as Map<String, dynamic>)
          : null,
      edited: data['edited'] as bool?,
      editedAt: _parseInt(data['editedAt']),
      replyTo: data['replyTo'] as String?,
      mentions: (data['mentions'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      imageUrl: data['imageUrl'] as String?,
      location: data['location'] != null
          ? MessageLocation.fromRTDB(data['location'] as Map<String, dynamic>)
          : null,
      documentUrl: data['documentUrl'] as String?,
      documentName: data['documentName'] as String?,
      documentSize: _parseInt(data['documentSize']),
      audioDuration: _parseInt(data['audioDuration']),
      reactions: reactions,
      starred: (data['starred'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, v as bool)),
      deletedFor: (data['deletedFor'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      deletedForEveryone: data['deletedForEveryone'] as bool?,
      forwarded: data['forwarded'] as bool?,
      forwardCount: _parseInt(data['forwardCount']),
      originalSenderId: data['originalSenderId'] as String?,
      originalSenderName: data['originalSenderName'] as String?,
      originalSenderImage: data['originalSenderImage'] as String?,
      originalSenderHostCountryCode: data['originalSenderHostCountryCode'] as String?,
      originalSenderHomeCountryCode: data['originalSenderHomeCountryCode'] as String?,
      originalTimestamp: _parseInt(data['originalTimestamp']),
      pinned: (data['pinned'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, v as bool)),
      adminId: data['adminId'] as String?,
      adminImage: data['adminImage'] as String?,
    );
  }

  /// Check if message is from current user
  bool isOwnMessage(String currentUserId) => senderId == currentUserId;

  /// Check if message is text type
  bool get isText => type == 'text';
  
  /// Check if message is image type
  bool get isImage => type == 'image';
  
  /// Check if message is video type
  bool get isVideo => type == 'video';
  
  /// Check if message is audio type
  bool get isAudio => type == 'audio';
  
  /// Check if message is location type
  bool get isLocation => type == 'location';
  
  /// Check if message is document type
  bool get isDocument => type == 'document';
  
  /// Check if message is system type
  bool get isSystem => type == 'system';
  
  /// Check if message is money transfer type
  bool get isMoneyTransfer => type == 'money-transfer';

  /// Check if message is deleted for everyone
  bool get isDeletedForEveryone => deletedForEveryone == true;

  /// Check if message is deleted for a specific user
  bool isDeletedFor(String userId) => deletedFor?.contains(userId) ?? false;

  /// Check if message is starred by a specific user
  bool isStarredBy(String userId) => starred?[userId] == true;

  /// Check if message is pinned by a specific user
  bool isPinnedBy(String userId) => pinned?[userId] == true;
  /// Copy with implementation
  Message copyWith({
    String? id,
    String? chatId,
    String? senderId,
    String? senderName,
    String? senderImage,
    String? senderHostCountryCode,
    String? senderHomeCountryCode,
    String? content,
    String? type,
    int? timestamp,
    String? status,
    MoneyTransfer? moneyTransfer,
    bool? edited,
    int? editedAt,
    String? replyTo,
    List<String>? mentions,
    String? imageUrl,
    MessageLocation? location,
    String? documentUrl,
    String? documentName,
    int? documentSize,
    int? audioDuration,
    List<MessageReaction>? reactions,
    Map<String, bool>? starred,
    List<String>? deletedFor,
    bool? deletedForEveryone,
    bool? forwarded,
    int? forwardCount,
    String? originalSenderId,
    String? originalSenderName,
    String? originalSenderImage,
    String? originalSenderHostCountryCode,
    String? originalSenderHomeCountryCode,
    int? originalTimestamp,
    Map<String, bool>? pinned,
    String? adminId,
    String? adminImage,
  }) {
    return Message(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      senderImage: senderImage ?? this.senderImage,
      senderHostCountryCode: senderHostCountryCode ?? this.senderHostCountryCode,
      senderHomeCountryCode: senderHomeCountryCode ?? this.senderHomeCountryCode,
      content: content ?? this.content,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      moneyTransfer: moneyTransfer ?? this.moneyTransfer,
      edited: edited ?? this.edited,
      editedAt: editedAt ?? this.editedAt,
      replyTo: replyTo ?? this.replyTo,
      mentions: mentions ?? this.mentions,
      imageUrl: imageUrl ?? this.imageUrl,
      location: location ?? this.location,
      documentUrl: documentUrl ?? this.documentUrl,
      documentName: documentName ?? this.documentName,
      documentSize: documentSize ?? this.documentSize,
      audioDuration: audioDuration ?? this.audioDuration,
      reactions: reactions ?? this.reactions,
      starred: starred ?? this.starred,
      deletedFor: deletedFor ?? this.deletedFor,
      deletedForEveryone: deletedForEveryone ?? this.deletedForEveryone,
      forwarded: forwarded ?? this.forwarded,
      forwardCount: forwardCount ?? this.forwardCount,
      originalSenderId: originalSenderId ?? this.originalSenderId,
      originalSenderName: originalSenderName ?? this.originalSenderName,
      originalSenderImage: originalSenderImage ?? this.originalSenderImage,
      originalSenderHostCountryCode: originalSenderHostCountryCode ?? this.originalSenderHostCountryCode,
      originalSenderHomeCountryCode: originalSenderHomeCountryCode ?? this.originalSenderHomeCountryCode,
      originalTimestamp: originalTimestamp ?? this.originalTimestamp,
      pinned: pinned ?? this.pinned,
      adminId: adminId ?? this.adminId,
      adminImage: adminImage ?? this.adminImage,
    );
  }
}
