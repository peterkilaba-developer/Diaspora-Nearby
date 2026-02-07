// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'event_entity.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetEventEntityCollection on Isar {
  IsarCollection<EventEntity> get eventEntitys => this.collection();
}

const EventEntitySchema = CollectionSchema(
  name: r'EventEntity',
  id: -1764225715171335918,
  properties: {
    r'attendeeCount': PropertySchema(
      id: 0,
      name: r'attendeeCount',
      type: IsarType.long,
    ),
    r'attendees': PropertySchema(
      id: 1,
      name: r'attendees',
      type: IsarType.stringList,
    ),
    r'attendingPermission': PropertySchema(
      id: 2,
      name: r'attendingPermission',
      type: IsarType.string,
    ),
    r'category': PropertySchema(
      id: 3,
      name: r'category',
      type: IsarType.string,
    ),
    r'chatId': PropertySchema(
      id: 4,
      name: r'chatId',
      type: IsarType.string,
    ),
    r'createdAt': PropertySchema(
      id: 5,
      name: r'createdAt',
      type: IsarType.string,
    ),
    r'creatorId': PropertySchema(
      id: 6,
      name: r'creatorId',
      type: IsarType.string,
    ),
    r'description': PropertySchema(
      id: 7,
      name: r'description',
      type: IsarType.string,
    ),
    r'endDate': PropertySchema(
      id: 8,
      name: r'endDate',
      type: IsarType.string,
    ),
    r'endTime': PropertySchema(
      id: 9,
      name: r'endTime',
      type: IsarType.string,
    ),
    r'firestoreId': PropertySchema(
      id: 10,
      name: r'firestoreId',
      type: IsarType.string,
    ),
    r'homeCountry': PropertySchema(
      id: 11,
      name: r'homeCountry',
      type: IsarType.string,
    ),
    r'homeCountryCode': PropertySchema(
      id: 12,
      name: r'homeCountryCode',
      type: IsarType.string,
    ),
    r'hostCity': PropertySchema(
      id: 13,
      name: r'hostCity',
      type: IsarType.string,
    ),
    r'hostCountry': PropertySchema(
      id: 14,
      name: r'hostCountry',
      type: IsarType.string,
    ),
    r'hostCountryCode': PropertySchema(
      id: 15,
      name: r'hostCountryCode',
      type: IsarType.string,
    ),
    r'hostState': PropertySchema(
      id: 16,
      name: r'hostState',
      type: IsarType.string,
    ),
    r'imageUrl': PropertySchema(
      id: 17,
      name: r'imageUrl',
      type: IsarType.string,
    ),
    r'interested': PropertySchema(
      id: 18,
      name: r'interested',
      type: IsarType.stringList,
    ),
    r'invitedUserIds': PropertySchema(
      id: 19,
      name: r'invitedUserIds',
      type: IsarType.stringList,
    ),
    r'isPaid': PropertySchema(
      id: 20,
      name: r'isPaid',
      type: IsarType.bool,
    ),
    r'latitude': PropertySchema(
      id: 21,
      name: r'latitude',
      type: IsarType.double,
    ),
    r'location': PropertySchema(
      id: 22,
      name: r'location',
      type: IsarType.string,
    ),
    r'longitude': PropertySchema(
      id: 23,
      name: r'longitude',
      type: IsarType.double,
    ),
    r'maxAttendees': PropertySchema(
      id: 24,
      name: r'maxAttendees',
      type: IsarType.long,
    ),
    r'organizationId': PropertySchema(
      id: 25,
      name: r'organizationId',
      type: IsarType.string,
    ),
    r'organizationName': PropertySchema(
      id: 26,
      name: r'organizationName',
      type: IsarType.string,
    ),
    r'startDate': PropertySchema(
      id: 27,
      name: r'startDate',
      type: IsarType.string,
    ),
    r'startTime': PropertySchema(
      id: 28,
      name: r'startTime',
      type: IsarType.string,
    ),
    r'status': PropertySchema(
      id: 29,
      name: r'status',
      type: IsarType.string,
    ),
    r'ticketPrice': PropertySchema(
      id: 30,
      name: r'ticketPrice',
      type: IsarType.double,
    ),
    r'title': PropertySchema(
      id: 31,
      name: r'title',
      type: IsarType.string,
    ),
    r'updatedAt': PropertySchema(
      id: 32,
      name: r'updatedAt',
      type: IsarType.string,
    ),
    r'venueAddress': PropertySchema(
      id: 33,
      name: r'venueAddress',
      type: IsarType.string,
    ),
    r'venueCity': PropertySchema(
      id: 34,
      name: r'venueCity',
      type: IsarType.string,
    ),
    r'venueCountry': PropertySchema(
      id: 35,
      name: r'venueCountry',
      type: IsarType.string,
    ),
    r'venueName': PropertySchema(
      id: 36,
      name: r'venueName',
      type: IsarType.string,
    ),
    r'venueState': PropertySchema(
      id: 37,
      name: r'venueState',
      type: IsarType.string,
    )
  },
  estimateSize: _eventEntityEstimateSize,
  serialize: _eventEntitySerialize,
  deserialize: _eventEntityDeserialize,
  deserializeProp: _eventEntityDeserializeProp,
  idName: r'id',
  indexes: {
    r'firestoreId': IndexSchema(
      id: 1863077355534729001,
      name: r'firestoreId',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(
          name: r'firestoreId',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'startDate': IndexSchema(
      id: 7723980484494730382,
      name: r'startDate',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'startDate',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'homeCountry': IndexSchema(
      id: -4646192370841681343,
      name: r'homeCountry',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'homeCountry',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'hostCountry': IndexSchema(
      id: -4079897427768623529,
      name: r'hostCountry',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'hostCountry',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'createdAt': IndexSchema(
      id: -3433535483987302584,
      name: r'createdAt',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'createdAt',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _eventEntityGetId,
  getLinks: _eventEntityGetLinks,
  attach: _eventEntityAttach,
  version: '3.1.0+1',
);

int _eventEntityEstimateSize(
  EventEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final list = object.attendees;
    if (list != null) {
      bytesCount += 3 + list.length * 3;
      {
        for (var i = 0; i < list.length; i++) {
          final value = list[i];
          bytesCount += value.length * 3;
        }
      }
    }
  }
  {
    final value = object.attendingPermission;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.category.length * 3;
  {
    final value = object.chatId;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.createdAt;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.creatorId.length * 3;
  bytesCount += 3 + object.description.length * 3;
  {
    final value = object.endDate;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.endTime;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.firestoreId.length * 3;
  {
    final value = object.homeCountry;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.homeCountryCode;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.hostCity;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.hostCountry;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.hostCountryCode;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.hostState;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.imageUrl;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final list = object.interested;
    if (list != null) {
      bytesCount += 3 + list.length * 3;
      {
        for (var i = 0; i < list.length; i++) {
          final value = list[i];
          bytesCount += value.length * 3;
        }
      }
    }
  }
  {
    final list = object.invitedUserIds;
    if (list != null) {
      bytesCount += 3 + list.length * 3;
      {
        for (var i = 0; i < list.length; i++) {
          final value = list[i];
          bytesCount += value.length * 3;
        }
      }
    }
  }
  bytesCount += 3 + object.location.length * 3;
  {
    final value = object.organizationId;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.organizationName;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.startDate.length * 3;
  bytesCount += 3 + object.startTime.length * 3;
  {
    final value = object.status;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.title.length * 3;
  {
    final value = object.updatedAt;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.venueAddress;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.venueCity;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.venueCountry;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.venueName;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.venueState;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  return bytesCount;
}

void _eventEntitySerialize(
  EventEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeLong(offsets[0], object.attendeeCount);
  writer.writeStringList(offsets[1], object.attendees);
  writer.writeString(offsets[2], object.attendingPermission);
  writer.writeString(offsets[3], object.category);
  writer.writeString(offsets[4], object.chatId);
  writer.writeString(offsets[5], object.createdAt);
  writer.writeString(offsets[6], object.creatorId);
  writer.writeString(offsets[7], object.description);
  writer.writeString(offsets[8], object.endDate);
  writer.writeString(offsets[9], object.endTime);
  writer.writeString(offsets[10], object.firestoreId);
  writer.writeString(offsets[11], object.homeCountry);
  writer.writeString(offsets[12], object.homeCountryCode);
  writer.writeString(offsets[13], object.hostCity);
  writer.writeString(offsets[14], object.hostCountry);
  writer.writeString(offsets[15], object.hostCountryCode);
  writer.writeString(offsets[16], object.hostState);
  writer.writeString(offsets[17], object.imageUrl);
  writer.writeStringList(offsets[18], object.interested);
  writer.writeStringList(offsets[19], object.invitedUserIds);
  writer.writeBool(offsets[20], object.isPaid);
  writer.writeDouble(offsets[21], object.latitude);
  writer.writeString(offsets[22], object.location);
  writer.writeDouble(offsets[23], object.longitude);
  writer.writeLong(offsets[24], object.maxAttendees);
  writer.writeString(offsets[25], object.organizationId);
  writer.writeString(offsets[26], object.organizationName);
  writer.writeString(offsets[27], object.startDate);
  writer.writeString(offsets[28], object.startTime);
  writer.writeString(offsets[29], object.status);
  writer.writeDouble(offsets[30], object.ticketPrice);
  writer.writeString(offsets[31], object.title);
  writer.writeString(offsets[32], object.updatedAt);
  writer.writeString(offsets[33], object.venueAddress);
  writer.writeString(offsets[34], object.venueCity);
  writer.writeString(offsets[35], object.venueCountry);
  writer.writeString(offsets[36], object.venueName);
  writer.writeString(offsets[37], object.venueState);
}

EventEntity _eventEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = EventEntity();
  object.attendeeCount = reader.readLongOrNull(offsets[0]);
  object.attendees = reader.readStringList(offsets[1]);
  object.attendingPermission = reader.readStringOrNull(offsets[2]);
  object.category = reader.readString(offsets[3]);
  object.chatId = reader.readStringOrNull(offsets[4]);
  object.createdAt = reader.readStringOrNull(offsets[5]);
  object.creatorId = reader.readString(offsets[6]);
  object.description = reader.readString(offsets[7]);
  object.endDate = reader.readStringOrNull(offsets[8]);
  object.endTime = reader.readStringOrNull(offsets[9]);
  object.firestoreId = reader.readString(offsets[10]);
  object.homeCountry = reader.readStringOrNull(offsets[11]);
  object.homeCountryCode = reader.readStringOrNull(offsets[12]);
  object.hostCity = reader.readStringOrNull(offsets[13]);
  object.hostCountry = reader.readStringOrNull(offsets[14]);
  object.hostCountryCode = reader.readStringOrNull(offsets[15]);
  object.hostState = reader.readStringOrNull(offsets[16]);
  object.id = id;
  object.imageUrl = reader.readStringOrNull(offsets[17]);
  object.interested = reader.readStringList(offsets[18]);
  object.invitedUserIds = reader.readStringList(offsets[19]);
  object.isPaid = reader.readBoolOrNull(offsets[20]);
  object.latitude = reader.readDoubleOrNull(offsets[21]);
  object.location = reader.readString(offsets[22]);
  object.longitude = reader.readDoubleOrNull(offsets[23]);
  object.maxAttendees = reader.readLongOrNull(offsets[24]);
  object.organizationId = reader.readStringOrNull(offsets[25]);
  object.organizationName = reader.readStringOrNull(offsets[26]);
  object.startDate = reader.readString(offsets[27]);
  object.startTime = reader.readString(offsets[28]);
  object.status = reader.readStringOrNull(offsets[29]);
  object.ticketPrice = reader.readDoubleOrNull(offsets[30]);
  object.title = reader.readString(offsets[31]);
  object.updatedAt = reader.readStringOrNull(offsets[32]);
  object.venueAddress = reader.readStringOrNull(offsets[33]);
  object.venueCity = reader.readStringOrNull(offsets[34]);
  object.venueCountry = reader.readStringOrNull(offsets[35]);
  object.venueName = reader.readStringOrNull(offsets[36]);
  object.venueState = reader.readStringOrNull(offsets[37]);
  return object;
}

P _eventEntityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readLongOrNull(offset)) as P;
    case 1:
      return (reader.readStringList(offset)) as P;
    case 2:
      return (reader.readStringOrNull(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    case 4:
      return (reader.readStringOrNull(offset)) as P;
    case 5:
      return (reader.readStringOrNull(offset)) as P;
    case 6:
      return (reader.readString(offset)) as P;
    case 7:
      return (reader.readString(offset)) as P;
    case 8:
      return (reader.readStringOrNull(offset)) as P;
    case 9:
      return (reader.readStringOrNull(offset)) as P;
    case 10:
      return (reader.readString(offset)) as P;
    case 11:
      return (reader.readStringOrNull(offset)) as P;
    case 12:
      return (reader.readStringOrNull(offset)) as P;
    case 13:
      return (reader.readStringOrNull(offset)) as P;
    case 14:
      return (reader.readStringOrNull(offset)) as P;
    case 15:
      return (reader.readStringOrNull(offset)) as P;
    case 16:
      return (reader.readStringOrNull(offset)) as P;
    case 17:
      return (reader.readStringOrNull(offset)) as P;
    case 18:
      return (reader.readStringList(offset)) as P;
    case 19:
      return (reader.readStringList(offset)) as P;
    case 20:
      return (reader.readBoolOrNull(offset)) as P;
    case 21:
      return (reader.readDoubleOrNull(offset)) as P;
    case 22:
      return (reader.readString(offset)) as P;
    case 23:
      return (reader.readDoubleOrNull(offset)) as P;
    case 24:
      return (reader.readLongOrNull(offset)) as P;
    case 25:
      return (reader.readStringOrNull(offset)) as P;
    case 26:
      return (reader.readStringOrNull(offset)) as P;
    case 27:
      return (reader.readString(offset)) as P;
    case 28:
      return (reader.readString(offset)) as P;
    case 29:
      return (reader.readStringOrNull(offset)) as P;
    case 30:
      return (reader.readDoubleOrNull(offset)) as P;
    case 31:
      return (reader.readString(offset)) as P;
    case 32:
      return (reader.readStringOrNull(offset)) as P;
    case 33:
      return (reader.readStringOrNull(offset)) as P;
    case 34:
      return (reader.readStringOrNull(offset)) as P;
    case 35:
      return (reader.readStringOrNull(offset)) as P;
    case 36:
      return (reader.readStringOrNull(offset)) as P;
    case 37:
      return (reader.readStringOrNull(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _eventEntityGetId(EventEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _eventEntityGetLinks(EventEntity object) {
  return [];
}

void _eventEntityAttach(
    IsarCollection<dynamic> col, Id id, EventEntity object) {
  object.id = id;
}

extension EventEntityByIndex on IsarCollection<EventEntity> {
  Future<EventEntity?> getByFirestoreId(String firestoreId) {
    return getByIndex(r'firestoreId', [firestoreId]);
  }

  EventEntity? getByFirestoreIdSync(String firestoreId) {
    return getByIndexSync(r'firestoreId', [firestoreId]);
  }

  Future<bool> deleteByFirestoreId(String firestoreId) {
    return deleteByIndex(r'firestoreId', [firestoreId]);
  }

  bool deleteByFirestoreIdSync(String firestoreId) {
    return deleteByIndexSync(r'firestoreId', [firestoreId]);
  }

  Future<List<EventEntity?>> getAllByFirestoreId(
      List<String> firestoreIdValues) {
    final values = firestoreIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'firestoreId', values);
  }

  List<EventEntity?> getAllByFirestoreIdSync(List<String> firestoreIdValues) {
    final values = firestoreIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'firestoreId', values);
  }

  Future<int> deleteAllByFirestoreId(List<String> firestoreIdValues) {
    final values = firestoreIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'firestoreId', values);
  }

  int deleteAllByFirestoreIdSync(List<String> firestoreIdValues) {
    final values = firestoreIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'firestoreId', values);
  }

  Future<Id> putByFirestoreId(EventEntity object) {
    return putByIndex(r'firestoreId', object);
  }

  Id putByFirestoreIdSync(EventEntity object, {bool saveLinks = true}) {
    return putByIndexSync(r'firestoreId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByFirestoreId(List<EventEntity> objects) {
    return putAllByIndex(r'firestoreId', objects);
  }

  List<Id> putAllByFirestoreIdSync(List<EventEntity> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'firestoreId', objects, saveLinks: saveLinks);
  }
}

extension EventEntityQueryWhereSort
    on QueryBuilder<EventEntity, EventEntity, QWhere> {
  QueryBuilder<EventEntity, EventEntity, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension EventEntityQueryWhere
    on QueryBuilder<EventEntity, EventEntity, QWhereClause> {
  QueryBuilder<EventEntity, EventEntity, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterWhereClause> idNotEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterWhereClause> firestoreIdEqualTo(
      String firestoreId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'firestoreId',
        value: [firestoreId],
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterWhereClause>
      firestoreIdNotEqualTo(String firestoreId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'firestoreId',
              lower: [],
              upper: [firestoreId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'firestoreId',
              lower: [firestoreId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'firestoreId',
              lower: [firestoreId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'firestoreId',
              lower: [],
              upper: [firestoreId],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterWhereClause> startDateEqualTo(
      String startDate) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'startDate',
        value: [startDate],
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterWhereClause> startDateNotEqualTo(
      String startDate) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'startDate',
              lower: [],
              upper: [startDate],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'startDate',
              lower: [startDate],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'startDate',
              lower: [startDate],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'startDate',
              lower: [],
              upper: [startDate],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterWhereClause>
      homeCountryIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'homeCountry',
        value: [null],
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterWhereClause>
      homeCountryIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'homeCountry',
        lower: [null],
        includeLower: false,
        upper: [],
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterWhereClause> homeCountryEqualTo(
      String? homeCountry) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'homeCountry',
        value: [homeCountry],
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterWhereClause>
      homeCountryNotEqualTo(String? homeCountry) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'homeCountry',
              lower: [],
              upper: [homeCountry],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'homeCountry',
              lower: [homeCountry],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'homeCountry',
              lower: [homeCountry],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'homeCountry',
              lower: [],
              upper: [homeCountry],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterWhereClause>
      hostCountryIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'hostCountry',
        value: [null],
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterWhereClause>
      hostCountryIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'hostCountry',
        lower: [null],
        includeLower: false,
        upper: [],
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterWhereClause> hostCountryEqualTo(
      String? hostCountry) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'hostCountry',
        value: [hostCountry],
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterWhereClause>
      hostCountryNotEqualTo(String? hostCountry) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'hostCountry',
              lower: [],
              upper: [hostCountry],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'hostCountry',
              lower: [hostCountry],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'hostCountry',
              lower: [hostCountry],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'hostCountry',
              lower: [],
              upper: [hostCountry],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterWhereClause> createdAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'createdAt',
        value: [null],
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterWhereClause>
      createdAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'createdAt',
        lower: [null],
        includeLower: false,
        upper: [],
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterWhereClause> createdAtEqualTo(
      String? createdAt) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'createdAt',
        value: [createdAt],
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterWhereClause> createdAtNotEqualTo(
      String? createdAt) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'createdAt',
              lower: [],
              upper: [createdAt],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'createdAt',
              lower: [createdAt],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'createdAt',
              lower: [createdAt],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'createdAt',
              lower: [],
              upper: [createdAt],
              includeUpper: false,
            ));
      }
    });
  }
}

extension EventEntityQueryFilter
    on QueryBuilder<EventEntity, EventEntity, QFilterCondition> {
  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendeeCountIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'attendeeCount',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendeeCountIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'attendeeCount',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendeeCountEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'attendeeCount',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendeeCountGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'attendeeCount',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendeeCountLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'attendeeCount',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendeeCountBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'attendeeCount',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendeesIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'attendees',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendeesIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'attendees',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendeesElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'attendees',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendeesElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'attendees',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendeesElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'attendees',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendeesElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'attendees',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendeesElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'attendees',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendeesElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'attendees',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendeesElementContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'attendees',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendeesElementMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'attendees',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendeesElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'attendees',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendeesElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'attendees',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendeesLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'attendees',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendeesIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'attendees',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendeesIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'attendees',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendeesLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'attendees',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendeesLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'attendees',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendeesLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'attendees',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendingPermissionIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'attendingPermission',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendingPermissionIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'attendingPermission',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendingPermissionEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'attendingPermission',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendingPermissionGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'attendingPermission',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendingPermissionLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'attendingPermission',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendingPermissionBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'attendingPermission',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendingPermissionStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'attendingPermission',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendingPermissionEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'attendingPermission',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendingPermissionContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'attendingPermission',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendingPermissionMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'attendingPermission',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendingPermissionIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'attendingPermission',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      attendingPermissionIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'attendingPermission',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> categoryEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'category',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      categoryGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'category',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      categoryLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'category',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> categoryBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'category',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      categoryStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'category',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      categoryEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'category',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      categoryContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'category',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> categoryMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'category',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      categoryIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'category',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      categoryIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'category',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> chatIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'chatId',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      chatIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'chatId',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> chatIdEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'chatId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      chatIdGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'chatId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> chatIdLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'chatId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> chatIdBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'chatId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      chatIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'chatId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> chatIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'chatId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> chatIdContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'chatId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> chatIdMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'chatId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      chatIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'chatId',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      chatIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'chatId',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      createdAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'createdAt',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      createdAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'createdAt',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      createdAtEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'createdAt',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      createdAtGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'createdAt',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      createdAtLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'createdAt',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      createdAtBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'createdAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      createdAtStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'createdAt',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      createdAtEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'createdAt',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      createdAtContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'createdAt',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      createdAtMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'createdAt',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      createdAtIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'createdAt',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      createdAtIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'createdAt',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      creatorIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'creatorId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      creatorIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'creatorId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      creatorIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'creatorId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      creatorIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'creatorId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      creatorIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'creatorId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      creatorIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'creatorId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      creatorIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'creatorId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      creatorIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'creatorId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      creatorIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'creatorId',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      creatorIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'creatorId',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      descriptionEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'description',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      descriptionGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'description',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      descriptionLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'description',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      descriptionBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'description',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      descriptionStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'description',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      descriptionEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'description',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      descriptionContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'description',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      descriptionMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'description',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      descriptionIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'description',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      descriptionIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'description',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      endDateIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'endDate',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      endDateIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'endDate',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> endDateEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'endDate',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      endDateGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'endDate',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> endDateLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'endDate',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> endDateBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'endDate',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      endDateStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'endDate',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> endDateEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'endDate',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> endDateContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'endDate',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> endDateMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'endDate',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      endDateIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'endDate',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      endDateIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'endDate',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      endTimeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'endTime',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      endTimeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'endTime',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> endTimeEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'endTime',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      endTimeGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'endTime',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> endTimeLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'endTime',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> endTimeBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'endTime',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      endTimeStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'endTime',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> endTimeEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'endTime',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> endTimeContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'endTime',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> endTimeMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'endTime',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      endTimeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'endTime',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      endTimeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'endTime',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      firestoreIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'firestoreId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      firestoreIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'firestoreId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      firestoreIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'firestoreId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      firestoreIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'firestoreId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      firestoreIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'firestoreId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      firestoreIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'firestoreId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      firestoreIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'firestoreId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      firestoreIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'firestoreId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      firestoreIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'firestoreId',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      firestoreIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'firestoreId',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      homeCountryIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'homeCountry',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      homeCountryIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'homeCountry',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      homeCountryEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'homeCountry',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      homeCountryGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'homeCountry',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      homeCountryLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'homeCountry',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      homeCountryBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'homeCountry',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      homeCountryStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'homeCountry',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      homeCountryEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'homeCountry',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      homeCountryContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'homeCountry',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      homeCountryMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'homeCountry',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      homeCountryIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'homeCountry',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      homeCountryIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'homeCountry',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      homeCountryCodeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'homeCountryCode',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      homeCountryCodeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'homeCountryCode',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      homeCountryCodeEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'homeCountryCode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      homeCountryCodeGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'homeCountryCode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      homeCountryCodeLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'homeCountryCode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      homeCountryCodeBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'homeCountryCode',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      homeCountryCodeStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'homeCountryCode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      homeCountryCodeEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'homeCountryCode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      homeCountryCodeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'homeCountryCode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      homeCountryCodeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'homeCountryCode',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      homeCountryCodeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'homeCountryCode',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      homeCountryCodeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'homeCountryCode',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostCityIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'hostCity',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostCityIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'hostCity',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> hostCityEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'hostCity',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostCityGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'hostCity',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostCityLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'hostCity',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> hostCityBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'hostCity',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostCityStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'hostCity',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostCityEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'hostCity',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostCityContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'hostCity',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> hostCityMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'hostCity',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostCityIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'hostCity',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostCityIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'hostCity',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostCountryIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'hostCountry',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostCountryIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'hostCountry',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostCountryEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'hostCountry',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostCountryGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'hostCountry',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostCountryLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'hostCountry',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostCountryBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'hostCountry',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostCountryStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'hostCountry',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostCountryEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'hostCountry',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostCountryContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'hostCountry',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostCountryMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'hostCountry',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostCountryIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'hostCountry',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostCountryIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'hostCountry',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostCountryCodeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'hostCountryCode',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostCountryCodeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'hostCountryCode',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostCountryCodeEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'hostCountryCode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostCountryCodeGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'hostCountryCode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostCountryCodeLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'hostCountryCode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostCountryCodeBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'hostCountryCode',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostCountryCodeStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'hostCountryCode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostCountryCodeEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'hostCountryCode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostCountryCodeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'hostCountryCode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostCountryCodeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'hostCountryCode',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostCountryCodeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'hostCountryCode',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostCountryCodeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'hostCountryCode',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostStateIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'hostState',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostStateIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'hostState',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostStateEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'hostState',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostStateGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'hostState',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostStateLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'hostState',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostStateBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'hostState',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostStateStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'hostState',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostStateEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'hostState',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostStateContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'hostState',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostStateMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'hostState',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostStateIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'hostState',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      hostStateIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'hostState',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      imageUrlIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'imageUrl',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      imageUrlIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'imageUrl',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> imageUrlEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'imageUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      imageUrlGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'imageUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      imageUrlLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'imageUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> imageUrlBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'imageUrl',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      imageUrlStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'imageUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      imageUrlEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'imageUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      imageUrlContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'imageUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> imageUrlMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'imageUrl',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      imageUrlIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'imageUrl',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      imageUrlIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'imageUrl',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      interestedIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'interested',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      interestedIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'interested',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      interestedElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'interested',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      interestedElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'interested',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      interestedElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'interested',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      interestedElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'interested',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      interestedElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'interested',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      interestedElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'interested',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      interestedElementContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'interested',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      interestedElementMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'interested',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      interestedElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'interested',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      interestedElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'interested',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      interestedLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'interested',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      interestedIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'interested',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      interestedIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'interested',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      interestedLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'interested',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      interestedLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'interested',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      interestedLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'interested',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      invitedUserIdsIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'invitedUserIds',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      invitedUserIdsIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'invitedUserIds',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      invitedUserIdsElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'invitedUserIds',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      invitedUserIdsElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'invitedUserIds',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      invitedUserIdsElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'invitedUserIds',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      invitedUserIdsElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'invitedUserIds',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      invitedUserIdsElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'invitedUserIds',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      invitedUserIdsElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'invitedUserIds',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      invitedUserIdsElementContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'invitedUserIds',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      invitedUserIdsElementMatches(String pattern,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'invitedUserIds',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      invitedUserIdsElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'invitedUserIds',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      invitedUserIdsElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'invitedUserIds',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      invitedUserIdsLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'invitedUserIds',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      invitedUserIdsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'invitedUserIds',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      invitedUserIdsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'invitedUserIds',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      invitedUserIdsLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'invitedUserIds',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      invitedUserIdsLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'invitedUserIds',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      invitedUserIdsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'invitedUserIds',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> isPaidIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'isPaid',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      isPaidIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'isPaid',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> isPaidEqualTo(
      bool? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isPaid',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      latitudeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'latitude',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      latitudeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'latitude',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> latitudeEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'latitude',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      latitudeGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'latitude',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      latitudeLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'latitude',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> latitudeBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'latitude',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> locationEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'location',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      locationGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'location',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      locationLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'location',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> locationBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'location',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      locationStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'location',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      locationEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'location',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      locationContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'location',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> locationMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'location',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      locationIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'location',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      locationIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'location',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      longitudeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'longitude',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      longitudeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'longitude',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      longitudeEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'longitude',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      longitudeGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'longitude',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      longitudeLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'longitude',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      longitudeBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'longitude',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      maxAttendeesIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'maxAttendees',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      maxAttendeesIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'maxAttendees',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      maxAttendeesEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'maxAttendees',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      maxAttendeesGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'maxAttendees',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      maxAttendeesLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'maxAttendees',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      maxAttendeesBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'maxAttendees',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      organizationIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'organizationId',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      organizationIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'organizationId',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      organizationIdEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'organizationId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      organizationIdGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'organizationId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      organizationIdLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'organizationId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      organizationIdBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'organizationId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      organizationIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'organizationId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      organizationIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'organizationId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      organizationIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'organizationId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      organizationIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'organizationId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      organizationIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'organizationId',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      organizationIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'organizationId',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      organizationNameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'organizationName',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      organizationNameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'organizationName',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      organizationNameEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'organizationName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      organizationNameGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'organizationName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      organizationNameLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'organizationName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      organizationNameBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'organizationName',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      organizationNameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'organizationName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      organizationNameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'organizationName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      organizationNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'organizationName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      organizationNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'organizationName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      organizationNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'organizationName',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      organizationNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'organizationName',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      startDateEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'startDate',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      startDateGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'startDate',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      startDateLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'startDate',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      startDateBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'startDate',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      startDateStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'startDate',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      startDateEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'startDate',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      startDateContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'startDate',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      startDateMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'startDate',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      startDateIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'startDate',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      startDateIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'startDate',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      startTimeEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'startTime',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      startTimeGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'startTime',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      startTimeLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'startTime',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      startTimeBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'startTime',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      startTimeStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'startTime',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      startTimeEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'startTime',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      startTimeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'startTime',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      startTimeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'startTime',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      startTimeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'startTime',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      startTimeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'startTime',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> statusIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'status',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      statusIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'status',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> statusEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'status',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      statusGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'status',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> statusLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'status',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> statusBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'status',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      statusStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'status',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> statusEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'status',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> statusContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'status',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> statusMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'status',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      statusIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'status',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      statusIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'status',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      ticketPriceIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'ticketPrice',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      ticketPriceIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'ticketPrice',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      ticketPriceEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ticketPrice',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      ticketPriceGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'ticketPrice',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      ticketPriceLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'ticketPrice',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      ticketPriceBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'ticketPrice',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> titleEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      titleGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> titleLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> titleBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'title',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> titleStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> titleEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> titleContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> titleMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'title',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> titleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'title',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      titleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'title',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      updatedAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'updatedAt',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      updatedAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'updatedAt',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      updatedAtEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'updatedAt',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      updatedAtGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'updatedAt',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      updatedAtLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'updatedAt',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      updatedAtBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'updatedAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      updatedAtStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'updatedAt',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      updatedAtEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'updatedAt',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      updatedAtContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'updatedAt',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      updatedAtMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'updatedAt',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      updatedAtIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'updatedAt',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      updatedAtIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'updatedAt',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueAddressIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'venueAddress',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueAddressIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'venueAddress',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueAddressEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'venueAddress',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueAddressGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'venueAddress',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueAddressLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'venueAddress',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueAddressBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'venueAddress',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueAddressStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'venueAddress',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueAddressEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'venueAddress',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueAddressContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'venueAddress',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueAddressMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'venueAddress',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueAddressIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'venueAddress',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueAddressIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'venueAddress',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueCityIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'venueCity',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueCityIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'venueCity',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueCityEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'venueCity',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueCityGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'venueCity',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueCityLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'venueCity',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueCityBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'venueCity',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueCityStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'venueCity',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueCityEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'venueCity',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueCityContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'venueCity',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueCityMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'venueCity',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueCityIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'venueCity',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueCityIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'venueCity',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueCountryIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'venueCountry',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueCountryIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'venueCountry',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueCountryEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'venueCountry',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueCountryGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'venueCountry',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueCountryLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'venueCountry',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueCountryBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'venueCountry',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueCountryStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'venueCountry',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueCountryEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'venueCountry',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueCountryContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'venueCountry',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueCountryMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'venueCountry',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueCountryIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'venueCountry',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueCountryIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'venueCountry',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueNameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'venueName',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueNameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'venueName',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueNameEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'venueName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueNameGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'venueName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueNameLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'venueName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueNameBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'venueName',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueNameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'venueName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueNameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'venueName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'venueName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'venueName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'venueName',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'venueName',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueStateIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'venueState',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueStateIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'venueState',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueStateEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'venueState',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueStateGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'venueState',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueStateLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'venueState',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueStateBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'venueState',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueStateStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'venueState',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueStateEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'venueState',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueStateContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'venueState',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueStateMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'venueState',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueStateIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'venueState',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      venueStateIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'venueState',
        value: '',
      ));
    });
  }
}

extension EventEntityQueryObject
    on QueryBuilder<EventEntity, EventEntity, QFilterCondition> {}

extension EventEntityQueryLinks
    on QueryBuilder<EventEntity, EventEntity, QFilterCondition> {}

extension EventEntityQuerySortBy
    on QueryBuilder<EventEntity, EventEntity, QSortBy> {
  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByAttendeeCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'attendeeCount', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      sortByAttendeeCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'attendeeCount', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      sortByAttendingPermission() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'attendingPermission', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      sortByAttendingPermissionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'attendingPermission', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByCategory() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'category', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByCategoryDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'category', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByChatId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'chatId', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByChatIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'chatId', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByCreatorId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'creatorId', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByCreatorIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'creatorId', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByDescription() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'description', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByDescriptionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'description', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByEndDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endDate', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByEndDateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endDate', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByEndTime() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endTime', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByEndTimeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endTime', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByFirestoreId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'firestoreId', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByFirestoreIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'firestoreId', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByHomeCountry() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'homeCountry', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByHomeCountryDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'homeCountry', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByHomeCountryCode() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'homeCountryCode', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      sortByHomeCountryCodeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'homeCountryCode', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByHostCity() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hostCity', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByHostCityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hostCity', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByHostCountry() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hostCountry', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByHostCountryDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hostCountry', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByHostCountryCode() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hostCountryCode', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      sortByHostCountryCodeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hostCountryCode', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByHostState() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hostState', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByHostStateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hostState', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByImageUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'imageUrl', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByImageUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'imageUrl', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByIsPaid() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isPaid', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByIsPaidDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isPaid', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByLatitude() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'latitude', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByLatitudeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'latitude', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByLocation() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'location', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByLocationDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'location', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByLongitude() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'longitude', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByLongitudeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'longitude', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByMaxAttendees() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'maxAttendees', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      sortByMaxAttendeesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'maxAttendees', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByOrganizationId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'organizationId', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      sortByOrganizationIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'organizationId', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      sortByOrganizationName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'organizationName', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      sortByOrganizationNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'organizationName', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByStartDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startDate', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByStartDateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startDate', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByStartTime() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startTime', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByStartTimeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startTime', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByTicketPrice() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ticketPrice', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByTicketPriceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ticketPrice', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByVenueAddress() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'venueAddress', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      sortByVenueAddressDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'venueAddress', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByVenueCity() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'venueCity', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByVenueCityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'venueCity', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByVenueCountry() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'venueCountry', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      sortByVenueCountryDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'venueCountry', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByVenueName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'venueName', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByVenueNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'venueName', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByVenueState() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'venueState', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByVenueStateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'venueState', Sort.desc);
    });
  }
}

extension EventEntityQuerySortThenBy
    on QueryBuilder<EventEntity, EventEntity, QSortThenBy> {
  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByAttendeeCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'attendeeCount', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      thenByAttendeeCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'attendeeCount', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      thenByAttendingPermission() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'attendingPermission', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      thenByAttendingPermissionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'attendingPermission', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByCategory() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'category', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByCategoryDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'category', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByChatId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'chatId', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByChatIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'chatId', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByCreatorId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'creatorId', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByCreatorIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'creatorId', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByDescription() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'description', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByDescriptionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'description', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByEndDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endDate', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByEndDateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endDate', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByEndTime() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endTime', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByEndTimeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endTime', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByFirestoreId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'firestoreId', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByFirestoreIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'firestoreId', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByHomeCountry() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'homeCountry', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByHomeCountryDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'homeCountry', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByHomeCountryCode() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'homeCountryCode', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      thenByHomeCountryCodeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'homeCountryCode', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByHostCity() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hostCity', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByHostCityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hostCity', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByHostCountry() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hostCountry', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByHostCountryDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hostCountry', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByHostCountryCode() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hostCountryCode', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      thenByHostCountryCodeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hostCountryCode', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByHostState() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hostState', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByHostStateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hostState', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByImageUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'imageUrl', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByImageUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'imageUrl', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByIsPaid() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isPaid', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByIsPaidDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isPaid', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByLatitude() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'latitude', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByLatitudeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'latitude', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByLocation() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'location', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByLocationDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'location', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByLongitude() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'longitude', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByLongitudeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'longitude', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByMaxAttendees() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'maxAttendees', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      thenByMaxAttendeesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'maxAttendees', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByOrganizationId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'organizationId', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      thenByOrganizationIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'organizationId', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      thenByOrganizationName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'organizationName', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      thenByOrganizationNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'organizationName', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByStartDate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startDate', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByStartDateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startDate', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByStartTime() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startTime', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByStartTimeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startTime', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByTicketPrice() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ticketPrice', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByTicketPriceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ticketPrice', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByVenueAddress() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'venueAddress', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      thenByVenueAddressDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'venueAddress', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByVenueCity() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'venueCity', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByVenueCityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'venueCity', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByVenueCountry() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'venueCountry', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      thenByVenueCountryDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'venueCountry', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByVenueName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'venueName', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByVenueNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'venueName', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByVenueState() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'venueState', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByVenueStateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'venueState', Sort.desc);
    });
  }
}

extension EventEntityQueryWhereDistinct
    on QueryBuilder<EventEntity, EventEntity, QDistinct> {
  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByAttendeeCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'attendeeCount');
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByAttendees() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'attendees');
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct>
      distinctByAttendingPermission({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'attendingPermission',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByCategory(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'category', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByChatId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'chatId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByCreatedAt(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByCreatorId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'creatorId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByDescription(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'description', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByEndDate(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'endDate', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByEndTime(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'endTime', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByFirestoreId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'firestoreId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByHomeCountry(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'homeCountry', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByHomeCountryCode(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'homeCountryCode',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByHostCity(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'hostCity', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByHostCountry(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'hostCountry', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByHostCountryCode(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'hostCountryCode',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByHostState(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'hostState', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByImageUrl(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'imageUrl', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByInterested() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'interested');
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByInvitedUserIds() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'invitedUserIds');
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByIsPaid() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isPaid');
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByLatitude() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'latitude');
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByLocation(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'location', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByLongitude() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'longitude');
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByMaxAttendees() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'maxAttendees');
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByOrganizationId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'organizationId',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByOrganizationName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'organizationName',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByStartDate(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'startDate', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByStartTime(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'startTime', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByStatus(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'status', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByTicketPrice() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'ticketPrice');
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByTitle(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'title', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByUpdatedAt(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAt', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByVenueAddress(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'venueAddress', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByVenueCity(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'venueCity', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByVenueCountry(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'venueCountry', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByVenueName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'venueName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByVenueState(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'venueState', caseSensitive: caseSensitive);
    });
  }
}

extension EventEntityQueryProperty
    on QueryBuilder<EventEntity, EventEntity, QQueryProperty> {
  QueryBuilder<EventEntity, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<EventEntity, int?, QQueryOperations> attendeeCountProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'attendeeCount');
    });
  }

  QueryBuilder<EventEntity, List<String>?, QQueryOperations>
      attendeesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'attendees');
    });
  }

  QueryBuilder<EventEntity, String?, QQueryOperations>
      attendingPermissionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'attendingPermission');
    });
  }

  QueryBuilder<EventEntity, String, QQueryOperations> categoryProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'category');
    });
  }

  QueryBuilder<EventEntity, String?, QQueryOperations> chatIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'chatId');
    });
  }

  QueryBuilder<EventEntity, String?, QQueryOperations> createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<EventEntity, String, QQueryOperations> creatorIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'creatorId');
    });
  }

  QueryBuilder<EventEntity, String, QQueryOperations> descriptionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'description');
    });
  }

  QueryBuilder<EventEntity, String?, QQueryOperations> endDateProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'endDate');
    });
  }

  QueryBuilder<EventEntity, String?, QQueryOperations> endTimeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'endTime');
    });
  }

  QueryBuilder<EventEntity, String, QQueryOperations> firestoreIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'firestoreId');
    });
  }

  QueryBuilder<EventEntity, String?, QQueryOperations> homeCountryProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'homeCountry');
    });
  }

  QueryBuilder<EventEntity, String?, QQueryOperations>
      homeCountryCodeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'homeCountryCode');
    });
  }

  QueryBuilder<EventEntity, String?, QQueryOperations> hostCityProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'hostCity');
    });
  }

  QueryBuilder<EventEntity, String?, QQueryOperations> hostCountryProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'hostCountry');
    });
  }

  QueryBuilder<EventEntity, String?, QQueryOperations>
      hostCountryCodeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'hostCountryCode');
    });
  }

  QueryBuilder<EventEntity, String?, QQueryOperations> hostStateProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'hostState');
    });
  }

  QueryBuilder<EventEntity, String?, QQueryOperations> imageUrlProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'imageUrl');
    });
  }

  QueryBuilder<EventEntity, List<String>?, QQueryOperations>
      interestedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'interested');
    });
  }

  QueryBuilder<EventEntity, List<String>?, QQueryOperations>
      invitedUserIdsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'invitedUserIds');
    });
  }

  QueryBuilder<EventEntity, bool?, QQueryOperations> isPaidProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isPaid');
    });
  }

  QueryBuilder<EventEntity, double?, QQueryOperations> latitudeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'latitude');
    });
  }

  QueryBuilder<EventEntity, String, QQueryOperations> locationProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'location');
    });
  }

  QueryBuilder<EventEntity, double?, QQueryOperations> longitudeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'longitude');
    });
  }

  QueryBuilder<EventEntity, int?, QQueryOperations> maxAttendeesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'maxAttendees');
    });
  }

  QueryBuilder<EventEntity, String?, QQueryOperations>
      organizationIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'organizationId');
    });
  }

  QueryBuilder<EventEntity, String?, QQueryOperations>
      organizationNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'organizationName');
    });
  }

  QueryBuilder<EventEntity, String, QQueryOperations> startDateProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'startDate');
    });
  }

  QueryBuilder<EventEntity, String, QQueryOperations> startTimeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'startTime');
    });
  }

  QueryBuilder<EventEntity, String?, QQueryOperations> statusProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'status');
    });
  }

  QueryBuilder<EventEntity, double?, QQueryOperations> ticketPriceProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'ticketPrice');
    });
  }

  QueryBuilder<EventEntity, String, QQueryOperations> titleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'title');
    });
  }

  QueryBuilder<EventEntity, String?, QQueryOperations> updatedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAt');
    });
  }

  QueryBuilder<EventEntity, String?, QQueryOperations> venueAddressProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'venueAddress');
    });
  }

  QueryBuilder<EventEntity, String?, QQueryOperations> venueCityProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'venueCity');
    });
  }

  QueryBuilder<EventEntity, String?, QQueryOperations> venueCountryProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'venueCountry');
    });
  }

  QueryBuilder<EventEntity, String?, QQueryOperations> venueNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'venueName');
    });
  }

  QueryBuilder<EventEntity, String?, QQueryOperations> venueStateProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'venueState');
    });
  }
}
