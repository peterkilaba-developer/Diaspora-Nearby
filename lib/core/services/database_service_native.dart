import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Database service for native platforms.
///
/// Previously initialized Isar for local caching. Now configures Firestore's
/// built-in offline persistence, which provides the same functionality
/// (offline reads, write queuing) with zero maintenance burden.
class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();

  factory DatabaseService() => _instance;

  DatabaseService._internal();

  Future<void> init() async {
    // Enable Firestore offline persistence with generous cache
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: 100 * 1024 * 1024, // 100MB
    );
    debugPrint('✅ Firestore Offline Persistence Configured (100MB cache)');
  }

  Future<void> close() async {
    // No-op: Firestore manages its own lifecycle
  }

  Future<void> clean() async {
    try {
      await FirebaseFirestore.instance.clearPersistence();
      debugPrint('🧹 Firestore local cache cleared successfully');
    } catch (e) {
      debugPrint(
        '⚠️ DatabaseService: Could not clear Firestore persistence: $e',
      );
      // clearPersistence can only run before Firestore is used,
      // so this may throw if the app is already using Firestore.
      // In that case, the cache will be cleared on next app restart.
    }
  }
}
