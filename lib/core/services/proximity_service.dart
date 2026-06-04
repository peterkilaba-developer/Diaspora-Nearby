import 'package:flutter/foundation.dart';

class ProximityService {
  ProximityService();

  Future<void> checkAndNotify(String userId) async {
    // [REFACTORED] Proximity logic has moved to Firebase Cloud Functions.
    // This method is now a no-op to avoid redundant Firestore reads and battery drain.
    // The background service still calls LocationUpdateService which triggers the Cloud Function.
    debugPrint(
      '📍 [PROXIMITY] Local check skipped. Relying on Cloud Functions.',
    );
  }

  // [DEPRECATED] Helper for PushNotificationService to check deduplication
  // No longer needed as server handles deduplication via proximity_history.
  Future<bool> hasRecentlyNotified(String userId) async {
    return false;
  }
}
