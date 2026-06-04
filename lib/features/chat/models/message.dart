import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:json_annotation/json_annotation.dart';

part 'message.g.dart';

/// Message reaction with emoji and list of user IDs
@JsonSerializable()
class MessageReaction {
  final String emoji;
  final List<String> userIds;

  const MessageReaction({required this.emoji, required this.userIds});

  factory MessageReaction.fromJson(Map<String, dynamic> json) =>
      _$MessageReactionFromJson(json);
  Map<String, dynamic> toJson() => _$MessageReactionToJson(this);

  /// Create from Firestore map
  factory MessageReaction.fromFirestore(Map<String, dynamic> data) {
    return MessageReaction(
      emoji: data['emoji'] as String? ?? '',
      userIds: (data['userIds'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }

  /// Convert to Firestore-compatible map
  Map<String, dynamic> toFirestore() => {'emoji': emoji, 'userIds': userIds};
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

  /// Create from Firestore data
  factory MessageLocation.fromFirestore(Map<String, dynamic> data) {
    return MessageLocation(
      lat: (data['lat'] as num?)?.toDouble() ??
          (data['latitude'] as num?)?.toDouble() ??
          0.0,
      lng: (data['lng'] as num?)?.toDouble() ??
          (data['longitude'] as num?)?.toDouble() ??
          0.0,
      address: data['address'] as String? ?? '',
      placeName: data['placeName'] as String?,
      placeType: data['placeType'] as String?,
    );
  }

  /// Convert to Firestore-compatible map
  Map<String, dynamic> toFirestore() => {
    'lat': lat,
    'lng': lng,
    'address': address,
    if (placeName != null) 'placeName': placeName,
    if (placeType != null) 'placeType': placeType,
  };

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

  /// Create from Firestore data
  factory MoneyTransfer.fromFirestore(Map<String, dynamic> data) {
    return MoneyTransfer(
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      currency: data['currency'] as String? ?? '',
      currencySymbol: data['currencySymbol'] as String? ?? '',
      convertedAmount: (data['convertedAmount'] as num?)?.toDouble() ?? 0.0,
      convertedCurrency: data['convertedCurrency'] as String? ?? '',
      convertedCurrencySymbol: data['convertedCurrencySymbol'] as String? ?? '',
      exchangeRate: (data['exchangeRate'] as num?)?.toDouble() ?? 0.0,
      senderCountryCode: data['senderCountryCode'] as String? ?? '',
      recipientCountryCode: data['recipientCountryCode'] as String? ?? '',
      status: data['status'] as String? ?? 'pending',
    );
  }

  /// Convert to Firestore-compatible map
  Map<String, dynamic> toFirestore() => {
    'amount': amount,
    'currency': currency,
    'currencySymbol': currencySymbol,
    'convertedAmount': convertedAmount,
    'convertedCurrency': convertedCurrency,
    'convertedCurrencySymbol': convertedCurrencySymbol,
    'exchangeRate': exchangeRate,
    'senderCountryCode': senderCountryCode,
    'recipientCountryCode': recipientCountryCode,
    'status': status,
  };

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
  final String?
  richContent; // [NEW] Stores @{uid:name} format if content is stripped
  final String
  type; // 'text' | 'image' | 'video' | 'audio' | 'location' | 'document' | 'system' | 'money-transfer'
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
    this.richContent, // [NEW] Optional field for rich text content (with mention codes)
    this.metadata, // [NEW] Generic metadata for extensibility
  });

  /// Generic metadata
  final Map<String, dynamic>? metadata;

  factory Message.fromJson(Map<String, dynamic> json) =>
      _$MessageFromJson(json);
  Map<String, dynamic> toJson() => _$MessageToJson(this);

  /// Create from Firestore document snapshot (messages subcollection)
  factory Message.fromFirestore(String chatId, DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Message.fromFirestoreData(doc.id, chatId, data);
  }

  /// Create from Firestore data map
  factory Message.fromFirestoreData(
    String id,
    String chatId,
    Map<String, dynamic> data,
  ) {
    // Parse timestamp safely
    int? parseTimestamp(dynamic value) {
      if (value == null) return null;
      if (value is Timestamp) return value.millisecondsSinceEpoch;
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value);
      return null;
    }

    // Parse reactions from Firestore array-of-maps format
    List<MessageReaction>? reactions;
    if (data['reactions'] != null && data['reactions'] is List) {
      reactions = (data['reactions'] as List<dynamic>)
          .map(
            (r) => MessageReaction.fromFirestore(
              Map<String, dynamic>.from(r as Map),
            ),
          )
          .toList();
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
      timestamp: parseTimestamp(data['timestamp']) ?? 0,
      status: data['status'] as String?,
      moneyTransfer: data['moneyTransfer'] != null
          ? MoneyTransfer.fromFirestore(
              Map<String, dynamic>.from(data['moneyTransfer'] as Map),
            )
          : null,
      edited: data['edited'] as bool?,
      editedAt: parseTimestamp(data['editedAt']),
      replyTo: data['replyTo'] as String?,
      mentions: (data['mentions'] as List<dynamic>?)?.cast<String>(),
      imageUrl: data['imageUrl'] as String?,
      location: data['location'] != null
          ? MessageLocation.fromFirestore(
              Map<String, dynamic>.from(data['location'] as Map),
            )
          : null,
      documentUrl: data['documentUrl'] as String?,
      documentName: data['documentName'] as String?,
      documentSize: (data['documentSize'] as num?)?.toInt(),
      audioDuration: (data['audioDuration'] as num?)?.toInt(),
      reactions: reactions,
      starred: (data['starred'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, v as bool),
      ),
      deletedFor: (data['deletedFor'] as List<dynamic>?)?.cast<String>(),
      deletedForEveryone: data['deletedForEveryone'] as bool?,
      forwarded: data['forwarded'] as bool?,
      forwardCount: (data['forwardCount'] as num?)?.toInt(),
      originalSenderId: data['originalSenderId'] as String?,
      originalSenderName: data['originalSenderName'] as String?,
      originalSenderImage: data['originalSenderImage'] as String?,
      originalSenderHostCountryCode:
          data['originalSenderHostCountryCode'] as String?,
      originalSenderHomeCountryCode:
          data['originalSenderHomeCountryCode'] as String?,
      originalTimestamp: parseTimestamp(data['originalTimestamp']),
      pinned: (data['pinned'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, v as bool),
      ),
      adminId: data['adminId'] as String?,
      adminImage: data['adminImage'] as String?,
      richContent: data['richContent'] as String?,
      metadata: (data['metadata'] is Map)
          ? Map<String, dynamic>.from(data['metadata'] as Map)
          : null,
    );
  }

  /// Convert to Firestore-compatible map (for messages subcollection)
  Map<String, dynamic> toFirestore() => {
    'senderId': senderId,
    'senderName': senderName,
    if (senderImage != null) 'senderImage': senderImage,
    if (senderHostCountryCode != null)
      'senderHostCountryCode': senderHostCountryCode,
    if (senderHomeCountryCode != null)
      'senderHomeCountryCode': senderHomeCountryCode,
    'content': content,
    'type': type,
    'timestamp': timestamp,
    if (status != null) 'status': status,
    if (moneyTransfer != null) 'moneyTransfer': moneyTransfer!.toFirestore(),
    if (edited != null) 'edited': edited,
    if (editedAt != null) 'editedAt': editedAt,
    if (replyTo != null) 'replyTo': replyTo,
    if (mentions != null) 'mentions': mentions,
    if (imageUrl != null) 'imageUrl': imageUrl,
    if (location != null) 'location': location!.toFirestore(),
    if (documentUrl != null) 'documentUrl': documentUrl,
    if (documentName != null) 'documentName': documentName,
    if (documentSize != null) 'documentSize': documentSize,
    if (audioDuration != null) 'audioDuration': audioDuration,
    if (reactions != null)
      'reactions': reactions!.map((r) => r.toFirestore()).toList(),
    if (starred != null) 'starred': starred,
    if (deletedFor != null) 'deletedFor': deletedFor,
    if (deletedForEveryone != null) 'deletedForEveryone': deletedForEveryone,
    if (forwarded != null) 'forwarded': forwarded,
    if (forwardCount != null) 'forwardCount': forwardCount,
    if (originalSenderId != null) 'originalSenderId': originalSenderId,
    if (originalSenderName != null) 'originalSenderName': originalSenderName,
    if (originalSenderImage != null) 'originalSenderImage': originalSenderImage,
    if (originalSenderHostCountryCode != null)
      'originalSenderHostCountryCode': originalSenderHostCountryCode,
    if (originalSenderHomeCountryCode != null)
      'originalSenderHomeCountryCode': originalSenderHomeCountryCode,
    if (originalTimestamp != null) 'originalTimestamp': originalTimestamp,
    if (pinned != null) 'pinned': pinned,
    if (adminId != null) 'adminId': adminId,
    if (adminImage != null) 'adminImage': adminImage,
    if (richContent != null) 'richContent': richContent,
    if (metadata != null) 'metadata': metadata,
  };

  /// Create Message from RTDB snapshot
  factory Message.fromRTDB(
    String id,
    String chatId,
    Map<String, dynamic> data,
  ) {
    // Helper to safely parse int values
    int? parseInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value);
      return null;
    }

    // Helper to safely parse List<String> from either a List or a Map (keys)
    List<String>? parseListOrMapKeys(dynamic value) {
      if (value == null) return null;
      if (value is List) {
        return value.map((e) => e.toString()).toList();
      }
      if (value is Map) {
        return value.keys.map((e) => e.toString()).toList();
      }
      return null;
    }

    // Parse reactions from RTDB format (handles both uid->emoji and emoji->[uids] formats)
    List<MessageReaction>? reactions;
    if (data['reactions'] != null) {
      final reactionsData = Map<dynamic, dynamic>.from(
        data['reactions'] as Map,
      );
      final groupedReactions = <String, List<String>>{};

      reactionsData.forEach((key, value) {
        final keyStr = key.toString();

        if (value is List) {
          // Format: emoji -> [uids]
          final emoji = keyStr;
          final uids = value.map((u) => u.toString()).toList();
          if (!groupedReactions.containsKey(emoji)) {
            groupedReactions[emoji] = [];
          }
          groupedReactions[emoji]!.addAll(uids);
        } else {
          // Format: uid -> emoji (value is string) OR possibly legacy emoji -> uid
          final valStr = value.toString();

          String emoji;
          String userId;

          // Heuristic: UIDs (28 chars) are much longer than emojis (usually 1-4 chars)
          if (keyStr.length > 10) {
            // key is UID, val is Emoji
            emoji = valStr;
            userId = keyStr;
          } else {
            // key is Emoji, val is UID
            emoji = keyStr;
            userId = valStr;
          }

          // Final sanity check: if we somehow got a long string as an emoji, swap it.
          // This handles cases where the heuristic might fail due to unexpected data.
          if (emoji.length > 10 && userId.length < 10) {
            final temp = emoji;
            emoji = userId;
            userId = temp;
          }

          if (emoji.isNotEmpty && emoji.length <= 10) {
            if (!groupedReactions.containsKey(emoji)) {
              groupedReactions[emoji] = [];
            }
            groupedReactions[emoji]!.add(userId);
          }
        }
      });

      reactions = groupedReactions.entries.map((e) {
        return MessageReaction(emoji: e.key, userIds: e.value);
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
      timestamp: parseInt(data['timestamp']) ?? 0,
      status: data['status'] as String?,
      moneyTransfer: data['moneyTransfer'] != null
          ? MoneyTransfer.fromRTDB(
              data['moneyTransfer'] as Map<String, dynamic>,
            )
          : null,
      edited: data['edited'] as bool?,
      editedAt: parseInt(data['editedAt']),
      replyTo: data['replyTo'] as String?,
      mentions: parseListOrMapKeys(data['mentions']),
      imageUrl: data['imageUrl'] as String?,
      location: data['location'] != null
          ? MessageLocation.fromRTDB(
              Map<String, dynamic>.from(data['location'] as Map),
            )
          : null,
      documentUrl: data['documentUrl'] as String?,
      documentName: data['documentName'] as String?,
      documentSize: parseInt(data['documentSize']),
      audioDuration: parseInt(data['audioDuration']),
      reactions: reactions,
      starred: (data['starred'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, v as bool),
      ),
      deletedFor: (data['deletedFor'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      deletedForEveryone: data['deletedForEveryone'] as bool?,
      forwarded: data['forwarded'] as bool?,
      forwardCount: parseInt(data['forwardCount']),
      originalSenderId: data['originalSenderId'] as String?,
      originalSenderName: data['originalSenderName'] as String?,
      originalSenderImage: data['originalSenderImage'] as String?,
      originalSenderHostCountryCode:
          data['originalSenderHostCountryCode'] as String?,
      originalSenderHomeCountryCode:
          data['originalSenderHomeCountryCode'] as String?,
      originalTimestamp: parseInt(data['originalTimestamp']),
      pinned: (data['pinned'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, v as bool),
      ),
      adminId: data['adminId'] as String?,
      adminImage: data['adminImage'] as String?,
      richContent: data['richContent'] as String?, // [NEW] Parse from RTDB
      metadata: (data['metadata'] is Map)
          ? Map<String, dynamic>.from(data['metadata'] as Map)
          : null,
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
  bool get isAudio => type == 'audio' || type == 'audio_file';

  /// Check if message is audio file type
  bool get isAudioFile => type == 'audio_file';

  /// Check if message is location type
  bool get isLocation => type == 'location';

  /// Check if message is document type
  bool get isDocument => type == 'document';

  /// Check if message is system type
  bool get isSystem => type == 'system';

  /// Check if message is money transfer type
  bool get isMoneyTransfer => type == 'money-transfer';

  /// Check if message is deleted for everyone
  bool get isDeletedForEveryone =>
      deletedForEveryone == true || type == 'deleted';

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
    String? richContent,
    Map<String, dynamic>? metadata,
  }) {
    return Message(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      senderImage: senderImage ?? this.senderImage,
      senderHostCountryCode:
          senderHostCountryCode ?? this.senderHostCountryCode,
      senderHomeCountryCode:
          senderHomeCountryCode ?? this.senderHomeCountryCode,
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
      originalSenderHostCountryCode:
          originalSenderHostCountryCode ?? this.originalSenderHostCountryCode,
      originalSenderHomeCountryCode:
          originalSenderHomeCountryCode ?? this.originalSenderHomeCountryCode,
      originalTimestamp: originalTimestamp ?? this.originalTimestamp,
      pinned: pinned ?? this.pinned,
      adminId: adminId ?? this.adminId,
      adminImage: adminImage ?? this.adminImage,
      richContent: richContent ?? this.richContent,
      metadata: metadata ?? this.metadata,
    );
  }
}
