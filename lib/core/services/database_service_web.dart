import 'package:flutter/foundation.dart';

/// Database service for web platforms.
///
/// Firestore's IndexedDB persistence is NOT automatic on web — it is
/// enabled explicitly in AppBootstrap via Settings(persistenceEnabled: true).
/// No additional local database setup is needed here.
class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();

  factory DatabaseService() => _instance;

  DatabaseService._internal();

  Future<void> init() async {
    debugPrint(
      '✅ DatabaseService (Web): Firestore IndexedDB persistence enabled via AppBootstrap.',
    );
  }

  Future<void> close() async {}

  Future<void> clean() async {}
}
