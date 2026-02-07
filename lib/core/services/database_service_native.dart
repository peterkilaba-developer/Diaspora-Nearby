import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:diaspora_nearby/features/shared/data/local/entities/community_entity.dart';
import 'package:diaspora_nearby/features/shared/data/local/entities/chat_entity.dart';
import 'package:diaspora_nearby/features/shared/data/local/entities/event_entity.dart';
import 'package:diaspora_nearby/features/shared/data/local/entities/organization_entity.dart';

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

    final dir = await getApplicationDocumentsDirectory();
    final path = dir.path;

    _isar = await Isar.open(
      [
        CommunityEntitySchema,
        ChatEntitySchema,
        EventEntitySchema,
        OrganizationEntitySchema
      ],
      directory: path,
      inspector: true, 
    );
    debugPrint('✅ Isar Database Initialized (Native)');
  }

  Future<void> close() async {
    await _isar?.close();
  }

  Future<void> clean() async {
    if (_isar == null) {
      debugPrint('⚠️ DatabaseService: Cannot clean, Isar is null');
      return;
    }
    try {
      await _isar!.writeTxn(() async {
        await _isar!.clear();
      });
      debugPrint('🧹 Isar Database: All collections cleared successfully');
    } catch (e) {
      debugPrint('❌ DatabaseService: Error during clean(): $e');
      rethrow;
    }
  }
}
