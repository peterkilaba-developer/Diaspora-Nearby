import 'package:diaspora_nearby/features/events/models/event_data.dart';

/// Local event cache service.
///
/// Previously powered by Isar. Now a no-op — Firestore's built-in offline
/// persistence handles all local caching automatically.
class EventLocalService {
  EventLocalService();

  Stream<List<Event>> watchFutureEvents() {
    return const Stream.empty();
  }

  Stream<List<Event>> watchUserEvents(String userId) {
    return const Stream.empty();
  }

  Stream<List<Event>> watchJoinedEvents(String userId) {
    return const Stream.empty();
  }

  Future<void> saveEvent(Event event) async {}

  Future<void> saveEvents(List<Event> events) async {}

  Future<Event?> getEvent(String eventId) async {
    return null;
  }
}
