import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:diaspora_nearby/features/shared/data/local/entities/community_entity.dart';
import 'package:diaspora_nearby/features/shared/data/local/entities/chat_entity.dart';
import 'package:diaspora_nearby/features/shared/data/local/entities/event_entity.dart';

class DatabaseService {
  Isar? _isar;

  static final DatabaseService _instance = DatabaseService._internal();

  factory DatabaseService() => _instance;

  DatabaseService._internal();

  Isar? get isar => _isar;

  Future<void> init() async {
    if (Isar.instanceNames.isNotEmpty) {
      _isar = Isar.getInstance()!;
      return;
    }

    String path = '';
    if (!kIsWeb) {
      final dir = await getApplicationDocumentsDirectory();
      path = dir.path;
    } else {
      // Isar 3.x stable does not support web yet. 
      // Returning early to avoid runtime crash.
      debugPrint('⚠️ Isar is skipped on Web (Unsupported in 3.x stable)');
      return;
    }

    _isar = await Isar.open(
      [
        CommunityEntitySchema,
        ChatEntitySchema,
        EventEntitySchema,
      ],
      directory: path,
      inspector: !kIsWeb, // Disable Isar Inspector on web
    );
    debugPrint('✅ Isar Database Initialized');
  }

  /// Close database instance
  Future<void> close() async {
    await _isar?.close();
  }

  /// Clean all data (Useful for logout or debug)
  Future<void> clean() async {
    if (_isar == null) return;
    await _isar!.writeTxn(() async {
      await _isar!.clear();
    });
    debugPrint('🧹 Isar Database Cleaned');
  }
}
