import 'package:flutter/foundation.dart';

// No Isar imports here!

class DatabaseService {
  // Return type 'dynamic' or a dummy class if needed, but since repositories
  // will also be split, they won't even call .isar on web ideally.
  // But to keep API surface matching:
  get isar => null; 

  static final DatabaseService _instance = DatabaseService._internal();

  factory DatabaseService() => _instance;

  DatabaseService._internal();

  Future<void> init() async {
    debugPrint('⚠️ DatabaseService: Isar is NOT supported on Web. Running in stateless mode.');
  }

  Future<void> close() async {}

  Future<void> clean() async {}
}
