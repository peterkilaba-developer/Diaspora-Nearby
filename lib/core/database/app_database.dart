import 'package:drift/drift.dart';
import 'connection_stub.dart'
    if (dart.library.io) 'connection_mobile.dart'
    if (dart.library.html) 'connection_web.dart';

part 'app_database.g.dart';

// ===================================
// TABLES
// ===================================

@DataClassName('LocalChat')
@TableIndex(name: 'idx_chats_lastmessageat', columns: {#lastMessageAt})
class LocalChats extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().nullable()();
  TextColumn get coverImage => text().nullable()();
  TextColumn get type => text()(); // 'direct', 'group', 'community'
  TextColumn get participantsJson => text().nullable()(); // List of string IDs
  TextColumn get lastMessageJson =>
      text().nullable()(); // Snippet of last message
  IntColumn get lastMessageAt => integer()();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();
  IntColumn get clearedAt => integer().withDefault(const Constant(0))();
  TextColumn get metadataJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('LocalMessage')
@TableIndex(name: 'idx_messages_chat_timestamp', columns: {#chatId, #timestamp})
class LocalMessages extends Table {
  TextColumn get id => text()();
  TextColumn get chatId => text().references(LocalChats, #id)();
  TextColumn get senderId => text()();
  TextColumn get senderName => text()();
  TextColumn get senderImage => text().nullable()();
  TextColumn get content => text()();
  TextColumn get type => text()(); // 'text', 'image', 'video', etc.
  IntColumn get timestamp => integer()();
  TextColumn get status => text().nullable()(); // 'sent', 'delivered', 'read'

  // Flattened Media
  TextColumn get imageUrl => text().nullable()();
  TextColumn get documentUrl => text().nullable()();
  IntColumn get mediaWidth => integer().nullable()();
  IntColumn get mediaHeight => integer().nullable()();
  TextColumn get thumbnailData => text().nullable()();

  // Generic Payload (JSON encoded string for nested fields like moneyTransfer, reactions, location, mentions)
  TextColumn get payloadJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ===================================
// DATABASE
// ===================================

@DriftDatabase(tables: [LocalChats, LocalMessages])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openConnection());

  @override
  int get schemaVersion => 3; // Incremented for ClearedAt support

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 3) {
          // Non-critical localized cache flush
          await m.issueCustomQuery('DROP TABLE IF EXISTS local_messages;');
          await m.issueCustomQuery('DROP TABLE IF EXISTS local_chats;');
          await m.createAll();
        }
      },
    );
  }

  // Singletons & Queries

  /// Fetches a sliding window of messages specifically for infinite scrolling pagination
  Future<List<LocalMessage>> getPaginatedMessages(
    String requestedChatId,
    int limit, {
    int? olderThanTimestamp,
  }) {
    final query = select(localMessages)
      ..where((m) => m.chatId.equals(requestedChatId));

    if (olderThanTimestamp != null) {
      query.where((m) => m.timestamp.isSmallerThanValue(olderThanTimestamp));
    }

    query.orderBy([
      (m) => OrderingTerm(expression: m.timestamp, mode: OrderingMode.desc),
    ]);
    query.limit(limit);

    return query.get();
  }

  /// [NEW] WATCH: Reactive stream for the chat list (WhatsApp-style instant updates)
  Stream<List<LocalChat>> watchChats() {
    return (select(localChats)..orderBy([
          (c) => OrderingTerm(
            expression: c.lastMessageAt,
            mode: OrderingMode.desc,
          ),
        ]))
        .watch();
  }

  /// [NEW] WATCH: Reactive stream for messages in a specific chat
  Stream<List<LocalMessage>> watchMessages(String requestedChatId) {
    return (select(localMessages)
          ..where((m) => m.chatId.equals(requestedChatId))
          ..orderBy([
            (m) =>
                OrderingTerm(expression: m.timestamp, mode: OrderingMode.desc),
          ]))
        .watch();
  }
}

// Platform-independent connection handled via connection_stub/mobile/web.dart
