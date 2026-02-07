import 'package:isar/isar.dart';
import 'package:diaspora_nearby/core/services/database_service.dart';
import 'package:diaspora_nearby/features/events/models/event_data.dart';
import 'package:diaspora_nearby/features/shared/data/local/entities/event_entity.dart';

class EventLocalService {
  final Isar? _isar;

  EventLocalService() : _isar = DatabaseService().isar;

  Stream<List<Event>> watchFutureEvents() {
    if (_isar == null) return const Stream.empty();
    
    final today = DateTime.now();
    final todayStr =
        "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
        
    return _isar!.eventEntitys
        .filter()
        .startDateGreaterThan(todayStr, include: true)
        .watch(fireImmediately: true)
        .map((entities) => entities.map(_mapEntityToModel).toList());
  }

  Stream<List<Event>> watchUserEvents(String userId) {
    if (_isar == null) return const Stream.empty();
    return _isar!.eventEntitys
        .filter()
        .creatorIdEqualTo(userId)
        .watch(fireImmediately: true)
        .map((entities) => entities.map(_mapEntityToModel).toList());
  }

  Stream<List<Event>> watchJoinedEvents(String userId) {
    if (_isar == null) return const Stream.empty();
    return _isar!.eventEntitys
        .filter()
        .attendeesElementEqualTo(userId)
        .watch(fireImmediately: true)
        .map((entities) => entities.map(_mapEntityToModel).toList());
  }

  Future<Event?> getEvent(String eventId) async {
    if (_isar == null) return null;
    final entity = await _isar!.eventEntitys
        .filter()
        .firestoreIdEqualTo(eventId)
        .findFirst();
    
    if (entity != null) return _mapEntityToModel(entity);
    return null;
  }

  Future<void> saveEvent(Event event) async {
    if (_isar == null) return;
    
    await _isar!.writeTxn(() async {
      final existing = await _isar!.eventEntitys
          .filter()
          .firestoreIdEqualTo(event.id)
          .findFirst();

      final entity = _mapModelToEntity(event);
      if (existing != null) {
        entity.id = existing.id; // Preserve Local ID
      }
      
      await _isar!.eventEntitys.put(entity);
    });
  }

  Future<void> saveEvents(List<Event> events) async {
    if (_isar == null) return;
    await _isar!.writeTxn(() async {
      for (final event in events) {
        final existing = await _isar!.eventEntitys
            .filter()
            .firestoreIdEqualTo(event.id)
            .findFirst();

        final entity = _mapModelToEntity(event);
        if (existing != null) {
          entity.id = existing.id; // Preserve Local ID
        }
        await _isar!.eventEntitys.put(entity);
      }
    });
  }

  // Mappers
  EventEntity _mapModelToEntity(Event event) {
    final entity = EventEntity()
      ..firestoreId = event.id
      ..creatorId = event.creatorId
      ..title = event.title
      ..description = event.description
      ..startDate = event.startDate
      ..endDate = event.endDate
      ..startTime = event.startTime
      ..endTime = event.endTime
      ..location = event.location
      ..category = event.category
      ..imageUrl = event.imageUrl
      ..attendees = event.attendees
      ..attendeeCount = event.attendeeCount
      ..interested = event.interested
      ..invitedUserIds = event.invitedUserIds
      ..isPaid = event.isPaid
      ..ticketPrice = event.ticketPrice
      ..maxAttendees = event.maxAttendees
      ..venueName = event.venueName
      ..venueAddress = event.venueAddress
      ..venueCity = event.venueCity
      ..venueState = event.venueState
      ..venueCountry = event.venueCountry
      ..status = event.status
      ..attendingPermission = event.attendingPermission
      ..chatId = event.chatId
      ..homeCountryCode = event.homeCountryCode
      ..hostCountryCode = event.hostCountryCode
      ..createdAt = event.createdAt
      ..latitude = event.latitude
      ..longitude = event.longitude
      ..organizationId = event.organizationId
      ..organizationName = event.organizationName;
    
    return entity;
  }

  Event _mapEntityToModel(EventEntity entity) {
    return Event(
      id: entity.firestoreId,
      creatorId: entity.creatorId,
      title: entity.title,
      description: entity.description,
      startDate: entity.startDate,
      endDate: entity.endDate,
      startTime: entity.startTime,
      endTime: entity.endTime,
      location: entity.location,
      category: entity.category,
      imageUrl: entity.imageUrl,
      attendees: entity.attendees?.toList() ?? [],
      attendeeCount: entity.attendeeCount ?? 0,
      interested: entity.interested?.toList() ?? [],
      invitedUserIds: entity.invitedUserIds?.toList() ?? [],
      isPaid: entity.isPaid,
      ticketPrice: entity.ticketPrice,
      maxAttendees: entity.maxAttendees,
      venueName: entity.venueName,
      venueAddress: entity.venueAddress,
      venueCity: entity.venueCity,
      venueState: entity.venueState,
      venueCountry: entity.venueCountry,
      status: entity.status ?? 'published',
      attendingPermission: entity.attendingPermission,
      chatId: entity.chatId,
      homeCountryCode: entity.homeCountryCode,
      hostCountryCode: entity.hostCountryCode,
      createdAt: entity.createdAt ?? '',
      latitude: entity.latitude,
      longitude: entity.longitude,
      organizationId: entity.organizationId,
      organizationName: entity.organizationName,
    );
  }
}
