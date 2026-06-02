// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $LocalChatsTable extends LocalChats
    with TableInfo<$LocalChatsTable, LocalChat> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalChatsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _coverImageMeta = const VerificationMeta(
    'coverImage',
  );
  @override
  late final GeneratedColumn<String> coverImage = GeneratedColumn<String>(
    'cover_image',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _participantsJsonMeta = const VerificationMeta(
    'participantsJson',
  );
  @override
  late final GeneratedColumn<String> participantsJson = GeneratedColumn<String>(
    'participants_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastMessageJsonMeta = const VerificationMeta(
    'lastMessageJson',
  );
  @override
  late final GeneratedColumn<String> lastMessageJson = GeneratedColumn<String>(
    'last_message_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastMessageAtMeta = const VerificationMeta(
    'lastMessageAt',
  );
  @override
  late final GeneratedColumn<int> lastMessageAt = GeneratedColumn<int>(
    'last_message_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _unreadCountMeta = const VerificationMeta(
    'unreadCount',
  );
  @override
  late final GeneratedColumn<int> unreadCount = GeneratedColumn<int>(
    'unread_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _clearedAtMeta = const VerificationMeta(
    'clearedAt',
  );
  @override
  late final GeneratedColumn<int> clearedAt = GeneratedColumn<int>(
    'cleared_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _metadataJsonMeta = const VerificationMeta(
    'metadataJson',
  );
  @override
  late final GeneratedColumn<String> metadataJson = GeneratedColumn<String>(
    'metadata_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    coverImage,
    type,
    participantsJson,
    lastMessageJson,
    lastMessageAt,
    unreadCount,
    clearedAt,
    metadataJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_chats';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalChat> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('cover_image')) {
      context.handle(
        _coverImageMeta,
        coverImage.isAcceptableOrUnknown(data['cover_image']!, _coverImageMeta),
      );
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('participants_json')) {
      context.handle(
        _participantsJsonMeta,
        participantsJson.isAcceptableOrUnknown(
          data['participants_json']!,
          _participantsJsonMeta,
        ),
      );
    }
    if (data.containsKey('last_message_json')) {
      context.handle(
        _lastMessageJsonMeta,
        lastMessageJson.isAcceptableOrUnknown(
          data['last_message_json']!,
          _lastMessageJsonMeta,
        ),
      );
    }
    if (data.containsKey('last_message_at')) {
      context.handle(
        _lastMessageAtMeta,
        lastMessageAt.isAcceptableOrUnknown(
          data['last_message_at']!,
          _lastMessageAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastMessageAtMeta);
    }
    if (data.containsKey('unread_count')) {
      context.handle(
        _unreadCountMeta,
        unreadCount.isAcceptableOrUnknown(
          data['unread_count']!,
          _unreadCountMeta,
        ),
      );
    }
    if (data.containsKey('cleared_at')) {
      context.handle(
        _clearedAtMeta,
        clearedAt.isAcceptableOrUnknown(data['cleared_at']!, _clearedAtMeta),
      );
    }
    if (data.containsKey('metadata_json')) {
      context.handle(
        _metadataJsonMeta,
        metadataJson.isAcceptableOrUnknown(
          data['metadata_json']!,
          _metadataJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalChat map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalChat(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      coverImage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_image'],
      ),
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      participantsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}participants_json'],
      ),
      lastMessageJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_message_json'],
      ),
      lastMessageAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_message_at'],
      )!,
      unreadCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unread_count'],
      )!,
      clearedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cleared_at'],
      )!,
      metadataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metadata_json'],
      ),
    );
  }

  @override
  $LocalChatsTable createAlias(String alias) {
    return $LocalChatsTable(attachedDatabase, alias);
  }
}

class LocalChat extends DataClass implements Insertable<LocalChat> {
  final String id;
  final String? title;
  final String? coverImage;
  final String type;
  final String? participantsJson;
  final String? lastMessageJson;
  final int lastMessageAt;
  final int unreadCount;
  final int clearedAt;
  final String? metadataJson;
  const LocalChat({
    required this.id,
    this.title,
    this.coverImage,
    required this.type,
    this.participantsJson,
    this.lastMessageJson,
    required this.lastMessageAt,
    required this.unreadCount,
    required this.clearedAt,
    this.metadataJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    if (!nullToAbsent || coverImage != null) {
      map['cover_image'] = Variable<String>(coverImage);
    }
    map['type'] = Variable<String>(type);
    if (!nullToAbsent || participantsJson != null) {
      map['participants_json'] = Variable<String>(participantsJson);
    }
    if (!nullToAbsent || lastMessageJson != null) {
      map['last_message_json'] = Variable<String>(lastMessageJson);
    }
    map['last_message_at'] = Variable<int>(lastMessageAt);
    map['unread_count'] = Variable<int>(unreadCount);
    map['cleared_at'] = Variable<int>(clearedAt);
    if (!nullToAbsent || metadataJson != null) {
      map['metadata_json'] = Variable<String>(metadataJson);
    }
    return map;
  }

  LocalChatsCompanion toCompanion(bool nullToAbsent) {
    return LocalChatsCompanion(
      id: Value(id),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
      coverImage: coverImage == null && nullToAbsent
          ? const Value.absent()
          : Value(coverImage),
      type: Value(type),
      participantsJson: participantsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(participantsJson),
      lastMessageJson: lastMessageJson == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessageJson),
      lastMessageAt: Value(lastMessageAt),
      unreadCount: Value(unreadCount),
      clearedAt: Value(clearedAt),
      metadataJson: metadataJson == null && nullToAbsent
          ? const Value.absent()
          : Value(metadataJson),
    );
  }

  factory LocalChat.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalChat(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String?>(json['title']),
      coverImage: serializer.fromJson<String?>(json['coverImage']),
      type: serializer.fromJson<String>(json['type']),
      participantsJson: serializer.fromJson<String?>(json['participantsJson']),
      lastMessageJson: serializer.fromJson<String?>(json['lastMessageJson']),
      lastMessageAt: serializer.fromJson<int>(json['lastMessageAt']),
      unreadCount: serializer.fromJson<int>(json['unreadCount']),
      clearedAt: serializer.fromJson<int>(json['clearedAt']),
      metadataJson: serializer.fromJson<String?>(json['metadataJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String?>(title),
      'coverImage': serializer.toJson<String?>(coverImage),
      'type': serializer.toJson<String>(type),
      'participantsJson': serializer.toJson<String?>(participantsJson),
      'lastMessageJson': serializer.toJson<String?>(lastMessageJson),
      'lastMessageAt': serializer.toJson<int>(lastMessageAt),
      'unreadCount': serializer.toJson<int>(unreadCount),
      'clearedAt': serializer.toJson<int>(clearedAt),
      'metadataJson': serializer.toJson<String?>(metadataJson),
    };
  }

  LocalChat copyWith({
    String? id,
    Value<String?> title = const Value.absent(),
    Value<String?> coverImage = const Value.absent(),
    String? type,
    Value<String?> participantsJson = const Value.absent(),
    Value<String?> lastMessageJson = const Value.absent(),
    int? lastMessageAt,
    int? unreadCount,
    int? clearedAt,
    Value<String?> metadataJson = const Value.absent(),
  }) => LocalChat(
    id: id ?? this.id,
    title: title.present ? title.value : this.title,
    coverImage: coverImage.present ? coverImage.value : this.coverImage,
    type: type ?? this.type,
    participantsJson: participantsJson.present
        ? participantsJson.value
        : this.participantsJson,
    lastMessageJson: lastMessageJson.present
        ? lastMessageJson.value
        : this.lastMessageJson,
    lastMessageAt: lastMessageAt ?? this.lastMessageAt,
    unreadCount: unreadCount ?? this.unreadCount,
    clearedAt: clearedAt ?? this.clearedAt,
    metadataJson: metadataJson.present ? metadataJson.value : this.metadataJson,
  );
  LocalChat copyWithCompanion(LocalChatsCompanion data) {
    return LocalChat(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      coverImage: data.coverImage.present
          ? data.coverImage.value
          : this.coverImage,
      type: data.type.present ? data.type.value : this.type,
      participantsJson: data.participantsJson.present
          ? data.participantsJson.value
          : this.participantsJson,
      lastMessageJson: data.lastMessageJson.present
          ? data.lastMessageJson.value
          : this.lastMessageJson,
      lastMessageAt: data.lastMessageAt.present
          ? data.lastMessageAt.value
          : this.lastMessageAt,
      unreadCount: data.unreadCount.present
          ? data.unreadCount.value
          : this.unreadCount,
      clearedAt: data.clearedAt.present ? data.clearedAt.value : this.clearedAt,
      metadataJson: data.metadataJson.present
          ? data.metadataJson.value
          : this.metadataJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalChat(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('coverImage: $coverImage, ')
          ..write('type: $type, ')
          ..write('participantsJson: $participantsJson, ')
          ..write('lastMessageJson: $lastMessageJson, ')
          ..write('lastMessageAt: $lastMessageAt, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('clearedAt: $clearedAt, ')
          ..write('metadataJson: $metadataJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    coverImage,
    type,
    participantsJson,
    lastMessageJson,
    lastMessageAt,
    unreadCount,
    clearedAt,
    metadataJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalChat &&
          other.id == this.id &&
          other.title == this.title &&
          other.coverImage == this.coverImage &&
          other.type == this.type &&
          other.participantsJson == this.participantsJson &&
          other.lastMessageJson == this.lastMessageJson &&
          other.lastMessageAt == this.lastMessageAt &&
          other.unreadCount == this.unreadCount &&
          other.clearedAt == this.clearedAt &&
          other.metadataJson == this.metadataJson);
}

class LocalChatsCompanion extends UpdateCompanion<LocalChat> {
  final Value<String> id;
  final Value<String?> title;
  final Value<String?> coverImage;
  final Value<String> type;
  final Value<String?> participantsJson;
  final Value<String?> lastMessageJson;
  final Value<int> lastMessageAt;
  final Value<int> unreadCount;
  final Value<int> clearedAt;
  final Value<String?> metadataJson;
  final Value<int> rowid;
  const LocalChatsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.coverImage = const Value.absent(),
    this.type = const Value.absent(),
    this.participantsJson = const Value.absent(),
    this.lastMessageJson = const Value.absent(),
    this.lastMessageAt = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.clearedAt = const Value.absent(),
    this.metadataJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalChatsCompanion.insert({
    required String id,
    this.title = const Value.absent(),
    this.coverImage = const Value.absent(),
    required String type,
    this.participantsJson = const Value.absent(),
    this.lastMessageJson = const Value.absent(),
    required int lastMessageAt,
    this.unreadCount = const Value.absent(),
    this.clearedAt = const Value.absent(),
    this.metadataJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       type = Value(type),
       lastMessageAt = Value(lastMessageAt);
  static Insertable<LocalChat> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? coverImage,
    Expression<String>? type,
    Expression<String>? participantsJson,
    Expression<String>? lastMessageJson,
    Expression<int>? lastMessageAt,
    Expression<int>? unreadCount,
    Expression<int>? clearedAt,
    Expression<String>? metadataJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (coverImage != null) 'cover_image': coverImage,
      if (type != null) 'type': type,
      if (participantsJson != null) 'participants_json': participantsJson,
      if (lastMessageJson != null) 'last_message_json': lastMessageJson,
      if (lastMessageAt != null) 'last_message_at': lastMessageAt,
      if (unreadCount != null) 'unread_count': unreadCount,
      if (clearedAt != null) 'cleared_at': clearedAt,
      if (metadataJson != null) 'metadata_json': metadataJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalChatsCompanion copyWith({
    Value<String>? id,
    Value<String?>? title,
    Value<String?>? coverImage,
    Value<String>? type,
    Value<String?>? participantsJson,
    Value<String?>? lastMessageJson,
    Value<int>? lastMessageAt,
    Value<int>? unreadCount,
    Value<int>? clearedAt,
    Value<String?>? metadataJson,
    Value<int>? rowid,
  }) {
    return LocalChatsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      coverImage: coverImage ?? this.coverImage,
      type: type ?? this.type,
      participantsJson: participantsJson ?? this.participantsJson,
      lastMessageJson: lastMessageJson ?? this.lastMessageJson,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
      clearedAt: clearedAt ?? this.clearedAt,
      metadataJson: metadataJson ?? this.metadataJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (coverImage.present) {
      map['cover_image'] = Variable<String>(coverImage.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (participantsJson.present) {
      map['participants_json'] = Variable<String>(participantsJson.value);
    }
    if (lastMessageJson.present) {
      map['last_message_json'] = Variable<String>(lastMessageJson.value);
    }
    if (lastMessageAt.present) {
      map['last_message_at'] = Variable<int>(lastMessageAt.value);
    }
    if (unreadCount.present) {
      map['unread_count'] = Variable<int>(unreadCount.value);
    }
    if (clearedAt.present) {
      map['cleared_at'] = Variable<int>(clearedAt.value);
    }
    if (metadataJson.present) {
      map['metadata_json'] = Variable<String>(metadataJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalChatsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('coverImage: $coverImage, ')
          ..write('type: $type, ')
          ..write('participantsJson: $participantsJson, ')
          ..write('lastMessageJson: $lastMessageJson, ')
          ..write('lastMessageAt: $lastMessageAt, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('clearedAt: $clearedAt, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalMessagesTable extends LocalMessages
    with TableInfo<$LocalMessagesTable, LocalMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chatIdMeta = const VerificationMeta('chatId');
  @override
  late final GeneratedColumn<String> chatId = GeneratedColumn<String>(
    'chat_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES local_chats (id)',
    ),
  );
  static const VerificationMeta _senderIdMeta = const VerificationMeta(
    'senderId',
  );
  @override
  late final GeneratedColumn<String> senderId = GeneratedColumn<String>(
    'sender_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _senderNameMeta = const VerificationMeta(
    'senderName',
  );
  @override
  late final GeneratedColumn<String> senderName = GeneratedColumn<String>(
    'sender_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _senderImageMeta = const VerificationMeta(
    'senderImage',
  );
  @override
  late final GeneratedColumn<String> senderImage = GeneratedColumn<String>(
    'sender_image',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<int> timestamp = GeneratedColumn<int>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _imageUrlMeta = const VerificationMeta(
    'imageUrl',
  );
  @override
  late final GeneratedColumn<String> imageUrl = GeneratedColumn<String>(
    'image_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _documentUrlMeta = const VerificationMeta(
    'documentUrl',
  );
  @override
  late final GeneratedColumn<String> documentUrl = GeneratedColumn<String>(
    'document_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mediaWidthMeta = const VerificationMeta(
    'mediaWidth',
  );
  @override
  late final GeneratedColumn<int> mediaWidth = GeneratedColumn<int>(
    'media_width',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mediaHeightMeta = const VerificationMeta(
    'mediaHeight',
  );
  @override
  late final GeneratedColumn<int> mediaHeight = GeneratedColumn<int>(
    'media_height',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _thumbnailDataMeta = const VerificationMeta(
    'thumbnailData',
  );
  @override
  late final GeneratedColumn<String> thumbnailData = GeneratedColumn<String>(
    'thumbnail_data',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    chatId,
    senderId,
    senderName,
    senderImage,
    content,
    type,
    timestamp,
    status,
    imageUrl,
    documentUrl,
    mediaWidth,
    mediaHeight,
    thumbnailData,
    payloadJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalMessage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('chat_id')) {
      context.handle(
        _chatIdMeta,
        chatId.isAcceptableOrUnknown(data['chat_id']!, _chatIdMeta),
      );
    } else if (isInserting) {
      context.missing(_chatIdMeta);
    }
    if (data.containsKey('sender_id')) {
      context.handle(
        _senderIdMeta,
        senderId.isAcceptableOrUnknown(data['sender_id']!, _senderIdMeta),
      );
    } else if (isInserting) {
      context.missing(_senderIdMeta);
    }
    if (data.containsKey('sender_name')) {
      context.handle(
        _senderNameMeta,
        senderName.isAcceptableOrUnknown(data['sender_name']!, _senderNameMeta),
      );
    } else if (isInserting) {
      context.missing(_senderNameMeta);
    }
    if (data.containsKey('sender_image')) {
      context.handle(
        _senderImageMeta,
        senderImage.isAcceptableOrUnknown(
          data['sender_image']!,
          _senderImageMeta,
        ),
      );
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('image_url')) {
      context.handle(
        _imageUrlMeta,
        imageUrl.isAcceptableOrUnknown(data['image_url']!, _imageUrlMeta),
      );
    }
    if (data.containsKey('document_url')) {
      context.handle(
        _documentUrlMeta,
        documentUrl.isAcceptableOrUnknown(
          data['document_url']!,
          _documentUrlMeta,
        ),
      );
    }
    if (data.containsKey('media_width')) {
      context.handle(
        _mediaWidthMeta,
        mediaWidth.isAcceptableOrUnknown(data['media_width']!, _mediaWidthMeta),
      );
    }
    if (data.containsKey('media_height')) {
      context.handle(
        _mediaHeightMeta,
        mediaHeight.isAcceptableOrUnknown(
          data['media_height']!,
          _mediaHeightMeta,
        ),
      );
    }
    if (data.containsKey('thumbnail_data')) {
      context.handle(
        _thumbnailDataMeta,
        thumbnailData.isAcceptableOrUnknown(
          data['thumbnail_data']!,
          _thumbnailDataMeta,
        ),
      );
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalMessage(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      chatId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chat_id'],
      )!,
      senderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender_id'],
      )!,
      senderName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender_name'],
      )!,
      senderImage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender_image'],
      ),
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}timestamp'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      ),
      imageUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_url'],
      ),
      documentUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}document_url'],
      ),
      mediaWidth: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}media_width'],
      ),
      mediaHeight: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}media_height'],
      ),
      thumbnailData: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumbnail_data'],
      ),
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      ),
    );
  }

  @override
  $LocalMessagesTable createAlias(String alias) {
    return $LocalMessagesTable(attachedDatabase, alias);
  }
}

class LocalMessage extends DataClass implements Insertable<LocalMessage> {
  final String id;
  final String chatId;
  final String senderId;
  final String senderName;
  final String? senderImage;
  final String content;
  final String type;
  final int timestamp;
  final String? status;
  final String? imageUrl;
  final String? documentUrl;
  final int? mediaWidth;
  final int? mediaHeight;
  final String? thumbnailData;
  final String? payloadJson;
  const LocalMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.senderName,
    this.senderImage,
    required this.content,
    required this.type,
    required this.timestamp,
    this.status,
    this.imageUrl,
    this.documentUrl,
    this.mediaWidth,
    this.mediaHeight,
    this.thumbnailData,
    this.payloadJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['chat_id'] = Variable<String>(chatId);
    map['sender_id'] = Variable<String>(senderId);
    map['sender_name'] = Variable<String>(senderName);
    if (!nullToAbsent || senderImage != null) {
      map['sender_image'] = Variable<String>(senderImage);
    }
    map['content'] = Variable<String>(content);
    map['type'] = Variable<String>(type);
    map['timestamp'] = Variable<int>(timestamp);
    if (!nullToAbsent || status != null) {
      map['status'] = Variable<String>(status);
    }
    if (!nullToAbsent || imageUrl != null) {
      map['image_url'] = Variable<String>(imageUrl);
    }
    if (!nullToAbsent || documentUrl != null) {
      map['document_url'] = Variable<String>(documentUrl);
    }
    if (!nullToAbsent || mediaWidth != null) {
      map['media_width'] = Variable<int>(mediaWidth);
    }
    if (!nullToAbsent || mediaHeight != null) {
      map['media_height'] = Variable<int>(mediaHeight);
    }
    if (!nullToAbsent || thumbnailData != null) {
      map['thumbnail_data'] = Variable<String>(thumbnailData);
    }
    if (!nullToAbsent || payloadJson != null) {
      map['payload_json'] = Variable<String>(payloadJson);
    }
    return map;
  }

  LocalMessagesCompanion toCompanion(bool nullToAbsent) {
    return LocalMessagesCompanion(
      id: Value(id),
      chatId: Value(chatId),
      senderId: Value(senderId),
      senderName: Value(senderName),
      senderImage: senderImage == null && nullToAbsent
          ? const Value.absent()
          : Value(senderImage),
      content: Value(content),
      type: Value(type),
      timestamp: Value(timestamp),
      status: status == null && nullToAbsent
          ? const Value.absent()
          : Value(status),
      imageUrl: imageUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(imageUrl),
      documentUrl: documentUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(documentUrl),
      mediaWidth: mediaWidth == null && nullToAbsent
          ? const Value.absent()
          : Value(mediaWidth),
      mediaHeight: mediaHeight == null && nullToAbsent
          ? const Value.absent()
          : Value(mediaHeight),
      thumbnailData: thumbnailData == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnailData),
      payloadJson: payloadJson == null && nullToAbsent
          ? const Value.absent()
          : Value(payloadJson),
    );
  }

  factory LocalMessage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalMessage(
      id: serializer.fromJson<String>(json['id']),
      chatId: serializer.fromJson<String>(json['chatId']),
      senderId: serializer.fromJson<String>(json['senderId']),
      senderName: serializer.fromJson<String>(json['senderName']),
      senderImage: serializer.fromJson<String?>(json['senderImage']),
      content: serializer.fromJson<String>(json['content']),
      type: serializer.fromJson<String>(json['type']),
      timestamp: serializer.fromJson<int>(json['timestamp']),
      status: serializer.fromJson<String?>(json['status']),
      imageUrl: serializer.fromJson<String?>(json['imageUrl']),
      documentUrl: serializer.fromJson<String?>(json['documentUrl']),
      mediaWidth: serializer.fromJson<int?>(json['mediaWidth']),
      mediaHeight: serializer.fromJson<int?>(json['mediaHeight']),
      thumbnailData: serializer.fromJson<String?>(json['thumbnailData']),
      payloadJson: serializer.fromJson<String?>(json['payloadJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'chatId': serializer.toJson<String>(chatId),
      'senderId': serializer.toJson<String>(senderId),
      'senderName': serializer.toJson<String>(senderName),
      'senderImage': serializer.toJson<String?>(senderImage),
      'content': serializer.toJson<String>(content),
      'type': serializer.toJson<String>(type),
      'timestamp': serializer.toJson<int>(timestamp),
      'status': serializer.toJson<String?>(status),
      'imageUrl': serializer.toJson<String?>(imageUrl),
      'documentUrl': serializer.toJson<String?>(documentUrl),
      'mediaWidth': serializer.toJson<int?>(mediaWidth),
      'mediaHeight': serializer.toJson<int?>(mediaHeight),
      'thumbnailData': serializer.toJson<String?>(thumbnailData),
      'payloadJson': serializer.toJson<String?>(payloadJson),
    };
  }

  LocalMessage copyWith({
    String? id,
    String? chatId,
    String? senderId,
    String? senderName,
    Value<String?> senderImage = const Value.absent(),
    String? content,
    String? type,
    int? timestamp,
    Value<String?> status = const Value.absent(),
    Value<String?> imageUrl = const Value.absent(),
    Value<String?> documentUrl = const Value.absent(),
    Value<int?> mediaWidth = const Value.absent(),
    Value<int?> mediaHeight = const Value.absent(),
    Value<String?> thumbnailData = const Value.absent(),
    Value<String?> payloadJson = const Value.absent(),
  }) => LocalMessage(
    id: id ?? this.id,
    chatId: chatId ?? this.chatId,
    senderId: senderId ?? this.senderId,
    senderName: senderName ?? this.senderName,
    senderImage: senderImage.present ? senderImage.value : this.senderImage,
    content: content ?? this.content,
    type: type ?? this.type,
    timestamp: timestamp ?? this.timestamp,
    status: status.present ? status.value : this.status,
    imageUrl: imageUrl.present ? imageUrl.value : this.imageUrl,
    documentUrl: documentUrl.present ? documentUrl.value : this.documentUrl,
    mediaWidth: mediaWidth.present ? mediaWidth.value : this.mediaWidth,
    mediaHeight: mediaHeight.present ? mediaHeight.value : this.mediaHeight,
    thumbnailData: thumbnailData.present
        ? thumbnailData.value
        : this.thumbnailData,
    payloadJson: payloadJson.present ? payloadJson.value : this.payloadJson,
  );
  LocalMessage copyWithCompanion(LocalMessagesCompanion data) {
    return LocalMessage(
      id: data.id.present ? data.id.value : this.id,
      chatId: data.chatId.present ? data.chatId.value : this.chatId,
      senderId: data.senderId.present ? data.senderId.value : this.senderId,
      senderName: data.senderName.present
          ? data.senderName.value
          : this.senderName,
      senderImage: data.senderImage.present
          ? data.senderImage.value
          : this.senderImage,
      content: data.content.present ? data.content.value : this.content,
      type: data.type.present ? data.type.value : this.type,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      status: data.status.present ? data.status.value : this.status,
      imageUrl: data.imageUrl.present ? data.imageUrl.value : this.imageUrl,
      documentUrl: data.documentUrl.present
          ? data.documentUrl.value
          : this.documentUrl,
      mediaWidth: data.mediaWidth.present
          ? data.mediaWidth.value
          : this.mediaWidth,
      mediaHeight: data.mediaHeight.present
          ? data.mediaHeight.value
          : this.mediaHeight,
      thumbnailData: data.thumbnailData.present
          ? data.thumbnailData.value
          : this.thumbnailData,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalMessage(')
          ..write('id: $id, ')
          ..write('chatId: $chatId, ')
          ..write('senderId: $senderId, ')
          ..write('senderName: $senderName, ')
          ..write('senderImage: $senderImage, ')
          ..write('content: $content, ')
          ..write('type: $type, ')
          ..write('timestamp: $timestamp, ')
          ..write('status: $status, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('documentUrl: $documentUrl, ')
          ..write('mediaWidth: $mediaWidth, ')
          ..write('mediaHeight: $mediaHeight, ')
          ..write('thumbnailData: $thumbnailData, ')
          ..write('payloadJson: $payloadJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    chatId,
    senderId,
    senderName,
    senderImage,
    content,
    type,
    timestamp,
    status,
    imageUrl,
    documentUrl,
    mediaWidth,
    mediaHeight,
    thumbnailData,
    payloadJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalMessage &&
          other.id == this.id &&
          other.chatId == this.chatId &&
          other.senderId == this.senderId &&
          other.senderName == this.senderName &&
          other.senderImage == this.senderImage &&
          other.content == this.content &&
          other.type == this.type &&
          other.timestamp == this.timestamp &&
          other.status == this.status &&
          other.imageUrl == this.imageUrl &&
          other.documentUrl == this.documentUrl &&
          other.mediaWidth == this.mediaWidth &&
          other.mediaHeight == this.mediaHeight &&
          other.thumbnailData == this.thumbnailData &&
          other.payloadJson == this.payloadJson);
}

class LocalMessagesCompanion extends UpdateCompanion<LocalMessage> {
  final Value<String> id;
  final Value<String> chatId;
  final Value<String> senderId;
  final Value<String> senderName;
  final Value<String?> senderImage;
  final Value<String> content;
  final Value<String> type;
  final Value<int> timestamp;
  final Value<String?> status;
  final Value<String?> imageUrl;
  final Value<String?> documentUrl;
  final Value<int?> mediaWidth;
  final Value<int?> mediaHeight;
  final Value<String?> thumbnailData;
  final Value<String?> payloadJson;
  final Value<int> rowid;
  const LocalMessagesCompanion({
    this.id = const Value.absent(),
    this.chatId = const Value.absent(),
    this.senderId = const Value.absent(),
    this.senderName = const Value.absent(),
    this.senderImage = const Value.absent(),
    this.content = const Value.absent(),
    this.type = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.status = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.documentUrl = const Value.absent(),
    this.mediaWidth = const Value.absent(),
    this.mediaHeight = const Value.absent(),
    this.thumbnailData = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalMessagesCompanion.insert({
    required String id,
    required String chatId,
    required String senderId,
    required String senderName,
    this.senderImage = const Value.absent(),
    required String content,
    required String type,
    required int timestamp,
    this.status = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.documentUrl = const Value.absent(),
    this.mediaWidth = const Value.absent(),
    this.mediaHeight = const Value.absent(),
    this.thumbnailData = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       chatId = Value(chatId),
       senderId = Value(senderId),
       senderName = Value(senderName),
       content = Value(content),
       type = Value(type),
       timestamp = Value(timestamp);
  static Insertable<LocalMessage> custom({
    Expression<String>? id,
    Expression<String>? chatId,
    Expression<String>? senderId,
    Expression<String>? senderName,
    Expression<String>? senderImage,
    Expression<String>? content,
    Expression<String>? type,
    Expression<int>? timestamp,
    Expression<String>? status,
    Expression<String>? imageUrl,
    Expression<String>? documentUrl,
    Expression<int>? mediaWidth,
    Expression<int>? mediaHeight,
    Expression<String>? thumbnailData,
    Expression<String>? payloadJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (chatId != null) 'chat_id': chatId,
      if (senderId != null) 'sender_id': senderId,
      if (senderName != null) 'sender_name': senderName,
      if (senderImage != null) 'sender_image': senderImage,
      if (content != null) 'content': content,
      if (type != null) 'type': type,
      if (timestamp != null) 'timestamp': timestamp,
      if (status != null) 'status': status,
      if (imageUrl != null) 'image_url': imageUrl,
      if (documentUrl != null) 'document_url': documentUrl,
      if (mediaWidth != null) 'media_width': mediaWidth,
      if (mediaHeight != null) 'media_height': mediaHeight,
      if (thumbnailData != null) 'thumbnail_data': thumbnailData,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalMessagesCompanion copyWith({
    Value<String>? id,
    Value<String>? chatId,
    Value<String>? senderId,
    Value<String>? senderName,
    Value<String?>? senderImage,
    Value<String>? content,
    Value<String>? type,
    Value<int>? timestamp,
    Value<String?>? status,
    Value<String?>? imageUrl,
    Value<String?>? documentUrl,
    Value<int?>? mediaWidth,
    Value<int?>? mediaHeight,
    Value<String?>? thumbnailData,
    Value<String?>? payloadJson,
    Value<int>? rowid,
  }) {
    return LocalMessagesCompanion(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      senderImage: senderImage ?? this.senderImage,
      content: content ?? this.content,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      imageUrl: imageUrl ?? this.imageUrl,
      documentUrl: documentUrl ?? this.documentUrl,
      mediaWidth: mediaWidth ?? this.mediaWidth,
      mediaHeight: mediaHeight ?? this.mediaHeight,
      thumbnailData: thumbnailData ?? this.thumbnailData,
      payloadJson: payloadJson ?? this.payloadJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (chatId.present) {
      map['chat_id'] = Variable<String>(chatId.value);
    }
    if (senderId.present) {
      map['sender_id'] = Variable<String>(senderId.value);
    }
    if (senderName.present) {
      map['sender_name'] = Variable<String>(senderName.value);
    }
    if (senderImage.present) {
      map['sender_image'] = Variable<String>(senderImage.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<int>(timestamp.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (imageUrl.present) {
      map['image_url'] = Variable<String>(imageUrl.value);
    }
    if (documentUrl.present) {
      map['document_url'] = Variable<String>(documentUrl.value);
    }
    if (mediaWidth.present) {
      map['media_width'] = Variable<int>(mediaWidth.value);
    }
    if (mediaHeight.present) {
      map['media_height'] = Variable<int>(mediaHeight.value);
    }
    if (thumbnailData.present) {
      map['thumbnail_data'] = Variable<String>(thumbnailData.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalMessagesCompanion(')
          ..write('id: $id, ')
          ..write('chatId: $chatId, ')
          ..write('senderId: $senderId, ')
          ..write('senderName: $senderName, ')
          ..write('senderImage: $senderImage, ')
          ..write('content: $content, ')
          ..write('type: $type, ')
          ..write('timestamp: $timestamp, ')
          ..write('status: $status, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('documentUrl: $documentUrl, ')
          ..write('mediaWidth: $mediaWidth, ')
          ..write('mediaHeight: $mediaHeight, ')
          ..write('thumbnailData: $thumbnailData, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $LocalChatsTable localChats = $LocalChatsTable(this);
  late final $LocalMessagesTable localMessages = $LocalMessagesTable(this);
  late final Index idxChatsLastmessageat = Index(
    'idx_chats_lastmessageat',
    'CREATE INDEX idx_chats_lastmessageat ON local_chats (last_message_at)',
  );
  late final Index idxMessagesChatTimestamp = Index(
    'idx_messages_chat_timestamp',
    'CREATE INDEX idx_messages_chat_timestamp ON local_messages (chat_id, timestamp)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    localChats,
    localMessages,
    idxChatsLastmessageat,
    idxMessagesChatTimestamp,
  ];
}

typedef $$LocalChatsTableCreateCompanionBuilder =
    LocalChatsCompanion Function({
      required String id,
      Value<String?> title,
      Value<String?> coverImage,
      required String type,
      Value<String?> participantsJson,
      Value<String?> lastMessageJson,
      required int lastMessageAt,
      Value<int> unreadCount,
      Value<int> clearedAt,
      Value<String?> metadataJson,
      Value<int> rowid,
    });
typedef $$LocalChatsTableUpdateCompanionBuilder =
    LocalChatsCompanion Function({
      Value<String> id,
      Value<String?> title,
      Value<String?> coverImage,
      Value<String> type,
      Value<String?> participantsJson,
      Value<String?> lastMessageJson,
      Value<int> lastMessageAt,
      Value<int> unreadCount,
      Value<int> clearedAt,
      Value<String?> metadataJson,
      Value<int> rowid,
    });

final class $$LocalChatsTableReferences
    extends BaseReferences<_$AppDatabase, $LocalChatsTable, LocalChat> {
  $$LocalChatsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$LocalMessagesTable, List<LocalMessage>>
  _localMessagesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.localMessages,
    aliasName: $_aliasNameGenerator(db.localChats.id, db.localMessages.chatId),
  );

  $$LocalMessagesTableProcessedTableManager get localMessagesRefs {
    final manager = $$LocalMessagesTableTableManager(
      $_db,
      $_db.localMessages,
    ).filter((f) => f.chatId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_localMessagesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$LocalChatsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalChatsTable> {
  $$LocalChatsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverImage => $composableBuilder(
    column: $table.coverImage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get participantsJson => $composableBuilder(
    column: $table.participantsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastMessageJson => $composableBuilder(
    column: $table.lastMessageJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastMessageAt => $composableBuilder(
    column: $table.lastMessageAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get clearedAt => $composableBuilder(
    column: $table.clearedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> localMessagesRefs(
    Expression<bool> Function($$LocalMessagesTableFilterComposer f) f,
  ) {
    final $$LocalMessagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.localMessages,
      getReferencedColumn: (t) => t.chatId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalMessagesTableFilterComposer(
            $db: $db,
            $table: $db.localMessages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LocalChatsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalChatsTable> {
  $$LocalChatsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverImage => $composableBuilder(
    column: $table.coverImage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get participantsJson => $composableBuilder(
    column: $table.participantsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastMessageJson => $composableBuilder(
    column: $table.lastMessageJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastMessageAt => $composableBuilder(
    column: $table.lastMessageAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get clearedAt => $composableBuilder(
    column: $table.clearedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalChatsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalChatsTable> {
  $$LocalChatsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get coverImage => $composableBuilder(
    column: $table.coverImage,
    builder: (column) => column,
  );

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get participantsJson => $composableBuilder(
    column: $table.participantsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastMessageJson => $composableBuilder(
    column: $table.lastMessageJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastMessageAt => $composableBuilder(
    column: $table.lastMessageAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get clearedAt =>
      $composableBuilder(column: $table.clearedAt, builder: (column) => column);

  GeneratedColumn<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => column,
  );

  Expression<T> localMessagesRefs<T extends Object>(
    Expression<T> Function($$LocalMessagesTableAnnotationComposer a) f,
  ) {
    final $$LocalMessagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.localMessages,
      getReferencedColumn: (t) => t.chatId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalMessagesTableAnnotationComposer(
            $db: $db,
            $table: $db.localMessages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LocalChatsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalChatsTable,
          LocalChat,
          $$LocalChatsTableFilterComposer,
          $$LocalChatsTableOrderingComposer,
          $$LocalChatsTableAnnotationComposer,
          $$LocalChatsTableCreateCompanionBuilder,
          $$LocalChatsTableUpdateCompanionBuilder,
          (LocalChat, $$LocalChatsTableReferences),
          LocalChat,
          PrefetchHooks Function({bool localMessagesRefs})
        > {
  $$LocalChatsTableTableManager(_$AppDatabase db, $LocalChatsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalChatsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalChatsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalChatsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String?> coverImage = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String?> participantsJson = const Value.absent(),
                Value<String?> lastMessageJson = const Value.absent(),
                Value<int> lastMessageAt = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<int> clearedAt = const Value.absent(),
                Value<String?> metadataJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalChatsCompanion(
                id: id,
                title: title,
                coverImage: coverImage,
                type: type,
                participantsJson: participantsJson,
                lastMessageJson: lastMessageJson,
                lastMessageAt: lastMessageAt,
                unreadCount: unreadCount,
                clearedAt: clearedAt,
                metadataJson: metadataJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> title = const Value.absent(),
                Value<String?> coverImage = const Value.absent(),
                required String type,
                Value<String?> participantsJson = const Value.absent(),
                Value<String?> lastMessageJson = const Value.absent(),
                required int lastMessageAt,
                Value<int> unreadCount = const Value.absent(),
                Value<int> clearedAt = const Value.absent(),
                Value<String?> metadataJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalChatsCompanion.insert(
                id: id,
                title: title,
                coverImage: coverImage,
                type: type,
                participantsJson: participantsJson,
                lastMessageJson: lastMessageJson,
                lastMessageAt: lastMessageAt,
                unreadCount: unreadCount,
                clearedAt: clearedAt,
                metadataJson: metadataJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$LocalChatsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({localMessagesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (localMessagesRefs) db.localMessages,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (localMessagesRefs)
                    await $_getPrefetchedData<
                      LocalChat,
                      $LocalChatsTable,
                      LocalMessage
                    >(
                      currentTable: table,
                      referencedTable: $$LocalChatsTableReferences
                          ._localMessagesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$LocalChatsTableReferences(
                            db,
                            table,
                            p0,
                          ).localMessagesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.chatId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$LocalChatsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalChatsTable,
      LocalChat,
      $$LocalChatsTableFilterComposer,
      $$LocalChatsTableOrderingComposer,
      $$LocalChatsTableAnnotationComposer,
      $$LocalChatsTableCreateCompanionBuilder,
      $$LocalChatsTableUpdateCompanionBuilder,
      (LocalChat, $$LocalChatsTableReferences),
      LocalChat,
      PrefetchHooks Function({bool localMessagesRefs})
    >;
typedef $$LocalMessagesTableCreateCompanionBuilder =
    LocalMessagesCompanion Function({
      required String id,
      required String chatId,
      required String senderId,
      required String senderName,
      Value<String?> senderImage,
      required String content,
      required String type,
      required int timestamp,
      Value<String?> status,
      Value<String?> imageUrl,
      Value<String?> documentUrl,
      Value<int?> mediaWidth,
      Value<int?> mediaHeight,
      Value<String?> thumbnailData,
      Value<String?> payloadJson,
      Value<int> rowid,
    });
typedef $$LocalMessagesTableUpdateCompanionBuilder =
    LocalMessagesCompanion Function({
      Value<String> id,
      Value<String> chatId,
      Value<String> senderId,
      Value<String> senderName,
      Value<String?> senderImage,
      Value<String> content,
      Value<String> type,
      Value<int> timestamp,
      Value<String?> status,
      Value<String?> imageUrl,
      Value<String?> documentUrl,
      Value<int?> mediaWidth,
      Value<int?> mediaHeight,
      Value<String?> thumbnailData,
      Value<String?> payloadJson,
      Value<int> rowid,
    });

final class $$LocalMessagesTableReferences
    extends BaseReferences<_$AppDatabase, $LocalMessagesTable, LocalMessage> {
  $$LocalMessagesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LocalChatsTable _chatIdTable(_$AppDatabase db) =>
      db.localChats.createAlias(
        $_aliasNameGenerator(db.localMessages.chatId, db.localChats.id),
      );

  $$LocalChatsTableProcessedTableManager get chatId {
    final $_column = $_itemColumn<String>('chat_id')!;

    final manager = $$LocalChatsTableTableManager(
      $_db,
      $_db.localChats,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_chatIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$LocalMessagesTableFilterComposer
    extends Composer<_$AppDatabase, $LocalMessagesTable> {
  $$LocalMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get senderId => $composableBuilder(
    column: $table.senderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get senderName => $composableBuilder(
    column: $table.senderName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get senderImage => $composableBuilder(
    column: $table.senderImage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imageUrl => $composableBuilder(
    column: $table.imageUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get documentUrl => $composableBuilder(
    column: $table.documentUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get mediaWidth => $composableBuilder(
    column: $table.mediaWidth,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get mediaHeight => $composableBuilder(
    column: $table.mediaHeight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbnailData => $composableBuilder(
    column: $table.thumbnailData,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  $$LocalChatsTableFilterComposer get chatId {
    final $$LocalChatsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.chatId,
      referencedTable: $db.localChats,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalChatsTableFilterComposer(
            $db: $db,
            $table: $db.localChats,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LocalMessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalMessagesTable> {
  $$LocalMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get senderId => $composableBuilder(
    column: $table.senderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get senderName => $composableBuilder(
    column: $table.senderName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get senderImage => $composableBuilder(
    column: $table.senderImage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imageUrl => $composableBuilder(
    column: $table.imageUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get documentUrl => $composableBuilder(
    column: $table.documentUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get mediaWidth => $composableBuilder(
    column: $table.mediaWidth,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get mediaHeight => $composableBuilder(
    column: $table.mediaHeight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbnailData => $composableBuilder(
    column: $table.thumbnailData,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  $$LocalChatsTableOrderingComposer get chatId {
    final $$LocalChatsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.chatId,
      referencedTable: $db.localChats,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalChatsTableOrderingComposer(
            $db: $db,
            $table: $db.localChats,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LocalMessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalMessagesTable> {
  $$LocalMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get senderId =>
      $composableBuilder(column: $table.senderId, builder: (column) => column);

  GeneratedColumn<String> get senderName => $composableBuilder(
    column: $table.senderName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get senderImage => $composableBuilder(
    column: $table.senderImage,
    builder: (column) => column,
  );

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get imageUrl =>
      $composableBuilder(column: $table.imageUrl, builder: (column) => column);

  GeneratedColumn<String> get documentUrl => $composableBuilder(
    column: $table.documentUrl,
    builder: (column) => column,
  );

  GeneratedColumn<int> get mediaWidth => $composableBuilder(
    column: $table.mediaWidth,
    builder: (column) => column,
  );

  GeneratedColumn<int> get mediaHeight => $composableBuilder(
    column: $table.mediaHeight,
    builder: (column) => column,
  );

  GeneratedColumn<String> get thumbnailData => $composableBuilder(
    column: $table.thumbnailData,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  $$LocalChatsTableAnnotationComposer get chatId {
    final $$LocalChatsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.chatId,
      referencedTable: $db.localChats,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalChatsTableAnnotationComposer(
            $db: $db,
            $table: $db.localChats,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LocalMessagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalMessagesTable,
          LocalMessage,
          $$LocalMessagesTableFilterComposer,
          $$LocalMessagesTableOrderingComposer,
          $$LocalMessagesTableAnnotationComposer,
          $$LocalMessagesTableCreateCompanionBuilder,
          $$LocalMessagesTableUpdateCompanionBuilder,
          (LocalMessage, $$LocalMessagesTableReferences),
          LocalMessage,
          PrefetchHooks Function({bool chatId})
        > {
  $$LocalMessagesTableTableManager(_$AppDatabase db, $LocalMessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalMessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> chatId = const Value.absent(),
                Value<String> senderId = const Value.absent(),
                Value<String> senderName = const Value.absent(),
                Value<String?> senderImage = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<int> timestamp = const Value.absent(),
                Value<String?> status = const Value.absent(),
                Value<String?> imageUrl = const Value.absent(),
                Value<String?> documentUrl = const Value.absent(),
                Value<int?> mediaWidth = const Value.absent(),
                Value<int?> mediaHeight = const Value.absent(),
                Value<String?> thumbnailData = const Value.absent(),
                Value<String?> payloadJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalMessagesCompanion(
                id: id,
                chatId: chatId,
                senderId: senderId,
                senderName: senderName,
                senderImage: senderImage,
                content: content,
                type: type,
                timestamp: timestamp,
                status: status,
                imageUrl: imageUrl,
                documentUrl: documentUrl,
                mediaWidth: mediaWidth,
                mediaHeight: mediaHeight,
                thumbnailData: thumbnailData,
                payloadJson: payloadJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String chatId,
                required String senderId,
                required String senderName,
                Value<String?> senderImage = const Value.absent(),
                required String content,
                required String type,
                required int timestamp,
                Value<String?> status = const Value.absent(),
                Value<String?> imageUrl = const Value.absent(),
                Value<String?> documentUrl = const Value.absent(),
                Value<int?> mediaWidth = const Value.absent(),
                Value<int?> mediaHeight = const Value.absent(),
                Value<String?> thumbnailData = const Value.absent(),
                Value<String?> payloadJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalMessagesCompanion.insert(
                id: id,
                chatId: chatId,
                senderId: senderId,
                senderName: senderName,
                senderImage: senderImage,
                content: content,
                type: type,
                timestamp: timestamp,
                status: status,
                imageUrl: imageUrl,
                documentUrl: documentUrl,
                mediaWidth: mediaWidth,
                mediaHeight: mediaHeight,
                thumbnailData: thumbnailData,
                payloadJson: payloadJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$LocalMessagesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({chatId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (chatId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.chatId,
                                referencedTable: $$LocalMessagesTableReferences
                                    ._chatIdTable(db),
                                referencedColumn: $$LocalMessagesTableReferences
                                    ._chatIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$LocalMessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalMessagesTable,
      LocalMessage,
      $$LocalMessagesTableFilterComposer,
      $$LocalMessagesTableOrderingComposer,
      $$LocalMessagesTableAnnotationComposer,
      $$LocalMessagesTableCreateCompanionBuilder,
      $$LocalMessagesTableUpdateCompanionBuilder,
      (LocalMessage, $$LocalMessagesTableReferences),
      LocalMessage,
      PrefetchHooks Function({bool chatId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$LocalChatsTableTableManager get localChats =>
      $$LocalChatsTableTableManager(_db, _db.localChats);
  $$LocalMessagesTableTableManager get localMessages =>
      $$LocalMessagesTableTableManager(_db, _db.localMessages);
}
