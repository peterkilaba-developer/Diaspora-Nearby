import 'package:drift/drift.dart';

@DataClassName('ChatEntity')
class ChatsTable extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()();
  TextColumn get title => text().nullable()();
  TextColumn get image => text().nullable()();

  // Custom metadata encoded as JSON strings
  TextColumn get participants => text().nullable()();
  TextColumn get lastMessage => text().nullable()();
  TextColumn get metadata => text().nullable()();

  // Timestamps
  IntColumn get updatedAt => integer().nullable()();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();

  // UI states
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  BoolColumn get isPinnedBottom =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('MessageEntity')
class MessagesTable extends Table {
  TextColumn get id => text()();
  TextColumn get chatId => text()();

  // Sender mapping
  TextColumn get senderId => text()();
  TextColumn get senderName => text()();
  TextColumn get senderImage => text().nullable()();

  // Content
  TextColumn get content => text()();
  TextColumn get type => text()();
  TextColumn get status => text().nullable()();
  IntColumn get timestamp => integer()();

  // Embedded large objects (JSON)
  TextColumn get metadata => text().nullable()();
  TextColumn get mentions => text().nullable()();

  // Media properties directly on row for performance
  TextColumn get imageUrl => text().nullable()();
  TextColumn get documentUrl => text().nullable()();
  IntColumn get mediaWidth => integer().nullable()();
  IntColumn get mediaHeight => integer().nullable()();
  TextColumn get thumbnailData => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
