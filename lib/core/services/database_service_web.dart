import 'package:flutter/foundation.dart';

/// Database service for web platforms.
///
/// Web uses Firestore's built-in IndexedDB persistence automatically.
/// No additional local database setup is needed.
class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();

  factory DatabaseService() => _instance;

  DatabaseService._internal();

  Future<void> init() async {
    debugPrint(
      '✅ DatabaseService (Web): Firestore IndexedDB persistence active.',
    );
  }

  Future<void> close() async {}

  Future<void> clean() async {}
}
