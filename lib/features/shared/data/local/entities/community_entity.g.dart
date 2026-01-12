// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'community_entity.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetCommunityEntityCollection on Isar {
  IsarCollection<CommunityEntity> get communityEntitys => this.collection();
}

final CommunityEntitySchema = CollectionSchema(
  name: r'CommunityEntity',
  id: int.parse('-4734722205235891796'),
  properties: {
    r'admins': PropertySchema(
      id: 0,
      name: r'admins',
      type: IsarType.stringList,
    ),
    r'chatId': PropertySchema(
      id: 1,
      name: r'chatId',
      type: IsarType.string,
    ),
    r'city': PropertySchema(
      id: 2,
      name: r'city',
      type: IsarType.string,
    ),
    r'country': PropertySchema(
      id: 3,
      name: r'country',
      type: IsarType.string,
    ),
    r'createdAt': PropertySchema(
      id: 4,
      name: r'createdAt',
      type: IsarType.long,
    ),
    r'description': PropertySchema(
      id: 5,
      name: r'description',
      type: IsarType.string,
    ),
    r'firestoreId': PropertySchema(
      id: 6,
      name: r'firestoreId',
      type: IsarType.string,
    ),
    r'flag': PropertySchema(
      id: 7,
      name: r'flag',
      type: IsarType.string,
    ),
    r'homeCountryCode': PropertySchema(
      id: 8,
      name: r'homeCountryCode',
      type: IsarType.string,
    ),
    r'hostCountryCode': PropertySchema(
      id: 9,
      name: r'hostCountryCode',
      type: IsarType.string,
    ),
    r'images': PropertySchema(
      id: 10,
      name: r'images',
      type: IsarType.stringList,
    ),
    r'isPrivate': PropertySchema(
      id: 11,
      name: r'isPrivate',
      type: IsarType.bool,
    ),
    r'locationJson': PropertySchema(
      id: 12,
      name: r'locationJson',
      type: IsarType.string,
    ),
    r'locationType': PropertySchema(
      id: 13,
      name: r'locationType',
      type: IsarType.string,
    ),
    r'memberCount': PropertySchema(
      id: 14,
      name: r'memberCount',
      type: IsarType.long,
    ),
    r'members': PropertySchema(
      id: 15,
      name: r'members',
      type: IsarType.stringList,
    ),
    r'name': PropertySchema(
      id: 16,
      name: r'name',
      type: IsarType.string,
    ),
    r'profileImage': PropertySchema(
      id: 17,
      name: r'profileImage',
      type: IsarType.string,
    ),
    r'state': PropertySchema(
      id: 18,
      name: r'state',
      type: IsarType.string,
    ),
    r'totalMembers': PropertySchema(
      id: 19,
      name: r'totalMembers',
      type: IsarType.long,
    ),
    r'type': PropertySchema(
      id: 20,
      name: r'type',
      type: IsarType.string,
    ),
    r'updatedAt': PropertySchema(
      id: 21,
      name: r'updatedAt',
      type: IsarType.long,
    )
  },
  estimateSize: _communityEntityEstimateSize,
  serialize: _communityEntitySerialize,
  deserialize: _communityEntityDeserialize,
  deserializeProp: _communityEntityDeserializeProp,
  idName: r'id',
  indexes: {
    r'firestoreId': IndexSchema(
      id: int.parse('1863077355534729001'),
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
    r'homeCountryCode': IndexSchema(
      id: int.parse('5068684165260240807'),
      name: r'homeCountryCode',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'homeCountryCode',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'locationType': IndexSchema(
      id: int.parse('-329961797783839228'),
      name: r'locationType',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'locationType',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'createdAt': IndexSchema(
      id: int.parse('-3433535483987302584'),
      name: r'createdAt',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'createdAt',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _communityEntityGetId,
  getLinks: _communityEntityGetLinks,
  attach: _communityEntityAttach,
  version: '3.1.0+1',
);

int _communityEntityEstimateSize(
  CommunityEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final list = object.admins;
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
    final value = object.chatId;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.city;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.country;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.description;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.firestoreId.length * 3;
  {
    final value = object.flag;
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
    final value = object.hostCountryCode;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final list = object.images;
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
    final value = object.locationJson;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.locationType;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final list = object.members;
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
  bytesCount += 3 + object.name.length * 3;
  {
    final value = object.profileImage;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.state;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.type;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  return bytesCount;
}

void _communityEntitySerialize(
  CommunityEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeStringList(offsets[0], object.admins);
  writer.writeString(offsets[1], object.chatId);
  writer.writeString(offsets[2], object.city);
  writer.writeString(offsets[3], object.country);
  writer.writeLong(offsets[4], object.createdAt);
  writer.writeString(offsets[5], object.description);
  writer.writeString(offsets[6], object.firestoreId);
  writer.writeString(offsets[7], object.flag);
  writer.writeString(offsets[8], object.homeCountryCode);
  writer.writeString(offsets[9], object.hostCountryCode);
  writer.writeStringList(offsets[10], object.images);
  writer.writeBool(offsets[11], object.isPrivate);
  writer.writeString(offsets[12], object.locationJson);
  writer.writeString(offsets[13], object.locationType);
  writer.writeLong(offsets[14], object.memberCount);
  writer.writeStringList(offsets[15], object.members);
  writer.writeString(offsets[16], object.name);
  writer.writeString(offsets[17], object.profileImage);
  writer.writeString(offsets[18], object.state);
  writer.writeLong(offsets[19], object.totalMembers);
  writer.writeString(offsets[20], object.type);
  writer.writeLong(offsets[21], object.updatedAt);
}

CommunityEntity _communityEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = CommunityEntity();
  object.admins = reader.readStringList(offsets[0]);
  object.chatId = reader.readStringOrNull(offsets[1]);
  object.city = reader.readStringOrNull(offsets[2]);
  object.country = reader.readStringOrNull(offsets[3]);
  object.createdAt = reader.readLongOrNull(offsets[4]);
  object.description = reader.readStringOrNull(offsets[5]);
  object.firestoreId = reader.readString(offsets[6]);
  object.flag = reader.readStringOrNull(offsets[7]);
  object.homeCountryCode = reader.readStringOrNull(offsets[8]);
  object.hostCountryCode = reader.readStringOrNull(offsets[9]);
  object.id = id;
  object.images = reader.readStringList(offsets[10]);
  object.isPrivate = reader.readBool(offsets[11]);
  object.locationJson = reader.readStringOrNull(offsets[12]);
  object.locationType = reader.readStringOrNull(offsets[13]);
  object.memberCount = reader.readLong(offsets[14]);
  object.members = reader.readStringList(offsets[15]);
  object.name = reader.readString(offsets[16]);
  object.profileImage = reader.readStringOrNull(offsets[17]);
  object.state = reader.readStringOrNull(offsets[18]);
  object.totalMembers = reader.readLongOrNull(offsets[19]);
  object.type = reader.readStringOrNull(offsets[20]);
  object.updatedAt = reader.readLongOrNull(offsets[21]);
  return object;
}

P _communityEntityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readStringList(offset)) as P;
    case 1:
      return (reader.readStringOrNull(offset)) as P;
    case 2:
      return (reader.readStringOrNull(offset)) as P;
    case 3:
      return (reader.readStringOrNull(offset)) as P;
    case 4:
      return (reader.readLongOrNull(offset)) as P;
    case 5:
      return (reader.readStringOrNull(offset)) as P;
    case 6:
      return (reader.readString(offset)) as P;
    case 7:
      return (reader.readStringOrNull(offset)) as P;
    case 8:
      return (reader.readStringOrNull(offset)) as P;
    case 9:
      return (reader.readStringOrNull(offset)) as P;
    case 10:
      return (reader.readStringList(offset)) as P;
    case 11:
      return (reader.readBool(offset)) as P;
    case 12:
      return (reader.readStringOrNull(offset)) as P;
    case 13:
      return (reader.readStringOrNull(offset)) as P;
    case 14:
      return (reader.readLong(offset)) as P;
    case 15:
      return (reader.readStringList(offset)) as P;
    case 16:
      return (reader.readString(offset)) as P;
    case 17:
      return (reader.readStringOrNull(offset)) as P;
    case 18:
      return (reader.readStringOrNull(offset)) as P;
    case 19:
      return (reader.readLongOrNull(offset)) as P;
    case 20:
      return (reader.readStringOrNull(offset)) as P;
    case 21:
      return (reader.readLongOrNull(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _communityEntityGetId(CommunityEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _communityEntityGetLinks(CommunityEntity object) {
  return [];
}

void _communityEntityAttach(
    IsarCollection<dynamic> col, Id id, CommunityEntity object) {
  object.id = id;
}

extension CommunityEntityByIndex on IsarCollection<CommunityEntity> {
  Future<CommunityEntity?> getByFirestoreId(String firestoreId) {
    return getByIndex(r'firestoreId', [firestoreId]);
  }

  CommunityEntity? getByFirestoreIdSync(String firestoreId) {
    return getByIndexSync(r'firestoreId', [firestoreId]);
  }

  Future<bool> deleteByFirestoreId(String firestoreId) {
    return deleteByIndex(r'firestoreId', [firestoreId]);
  }

  bool deleteByFirestoreIdSync(String firestoreId) {
    return deleteByIndexSync(r'firestoreId', [firestoreId]);
  }

  Future<List<CommunityEntity?>> getAllByFirestoreId(
      List<String> firestoreIdValues) {
    final values = firestoreIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'firestoreId', values);
  }

  List<CommunityEntity?> getAllByFirestoreIdSync(
      List<String> firestoreIdValues) {
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

  Future<Id> putByFirestoreId(CommunityEntity object) {
    return putByIndex(r'firestoreId', object);
  }

  Id putByFirestoreIdSync(CommunityEntity object, {bool saveLinks = true}) {
    return putByIndexSync(r'firestoreId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByFirestoreId(List<CommunityEntity> objects) {
    return putAllByIndex(r'firestoreId', objects);
  }

  List<Id> putAllByFirestoreIdSync(List<CommunityEntity> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'firestoreId', objects, saveLinks: saveLinks);
  }
}

extension CommunityEntityQueryWhereSort
    on QueryBuilder<CommunityEntity, CommunityEntity, QWhere> {
  QueryBuilder<CommunityEntity, CommunityEntity, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterWhere> anyCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'createdAt'),
      );
    });
  }
}

extension CommunityEntityQueryWhere
    on QueryBuilder<CommunityEntity, CommunityEntity, QWhereClause> {
  QueryBuilder<CommunityEntity, CommunityEntity, QAfterWhereClause> idEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterWhereClause>
      idNotEqualTo(Id id) {
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterWhereClause>
      idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterWhereClause> idLessThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterWhereClause> idBetween(
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterWhereClause>
      firestoreIdEqualTo(String firestoreId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'firestoreId',
        value: [firestoreId],
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterWhereClause>
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterWhereClause>
      homeCountryCodeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'homeCountryCode',
        value: [null],
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterWhereClause>
      homeCountryCodeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'homeCountryCode',
        lower: [null],
        includeLower: false,
        upper: [],
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterWhereClause>
      homeCountryCodeEqualTo(String? homeCountryCode) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'homeCountryCode',
        value: [homeCountryCode],
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterWhereClause>
      homeCountryCodeNotEqualTo(String? homeCountryCode) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'homeCountryCode',
              lower: [],
              upper: [homeCountryCode],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'homeCountryCode',
              lower: [homeCountryCode],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'homeCountryCode',
              lower: [homeCountryCode],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'homeCountryCode',
              lower: [],
              upper: [homeCountryCode],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterWhereClause>
      locationTypeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'locationType',
        value: [null],
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterWhereClause>
      locationTypeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'locationType',
        lower: [null],
        includeLower: false,
        upper: [],
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterWhereClause>
      locationTypeEqualTo(String? locationType) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'locationType',
        value: [locationType],
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterWhereClause>
      locationTypeNotEqualTo(String? locationType) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'locationType',
              lower: [],
              upper: [locationType],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'locationType',
              lower: [locationType],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'locationType',
              lower: [locationType],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'locationType',
              lower: [],
              upper: [locationType],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterWhereClause>
      createdAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'createdAt',
        value: [null],
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterWhereClause>
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterWhereClause>
      createdAtEqualTo(int? createdAt) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'createdAt',
        value: [createdAt],
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterWhereClause>
      createdAtNotEqualTo(int? createdAt) {
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterWhereClause>
      createdAtGreaterThan(
    int? createdAt, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'createdAt',
        lower: [createdAt],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterWhereClause>
      createdAtLessThan(
    int? createdAt, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'createdAt',
        lower: [],
        upper: [createdAt],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterWhereClause>
      createdAtBetween(
    int? lowerCreatedAt,
    int? upperCreatedAt, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'createdAt',
        lower: [lowerCreatedAt],
        includeLower: includeLower,
        upper: [upperCreatedAt],
        includeUpper: includeUpper,
      ));
    });
  }
}

extension CommunityEntityQueryFilter
    on QueryBuilder<CommunityEntity, CommunityEntity, QFilterCondition> {
  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      adminsIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'admins',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      adminsIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'admins',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      adminsElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'admins',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      adminsElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'admins',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      adminsElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'admins',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      adminsElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'admins',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      adminsElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'admins',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      adminsElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'admins',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      adminsElementContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'admins',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      adminsElementMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'admins',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      adminsElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'admins',
        value: '',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      adminsElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'admins',
        value: '',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      adminsLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'admins',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      adminsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'admins',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      adminsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'admins',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      adminsLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'admins',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      adminsLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'admins',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      adminsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'admins',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      chatIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'chatId',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      chatIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'chatId',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      chatIdEqualTo(
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      chatIdLessThan(
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      chatIdBetween(
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      chatIdEndsWith(
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      chatIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'chatId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      chatIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'chatId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      chatIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'chatId',
        value: '',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      chatIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'chatId',
        value: '',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      cityIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'city',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      cityIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'city',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      cityEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'city',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      cityGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'city',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      cityLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'city',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      cityBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'city',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      cityStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'city',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      cityEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'city',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      cityContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'city',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      cityMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'city',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      cityIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'city',
        value: '',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      cityIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'city',
        value: '',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      countryIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'country',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      countryIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'country',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      countryEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'country',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      countryGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'country',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      countryLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'country',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      countryBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'country',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      countryStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'country',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      countryEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'country',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      countryContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'country',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      countryMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'country',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      countryIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'country',
        value: '',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      countryIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'country',
        value: '',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      createdAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'createdAt',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      createdAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'createdAt',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      createdAtEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      createdAtGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      createdAtLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      createdAtBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'createdAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      descriptionIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'description',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      descriptionIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'description',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      descriptionEqualTo(
    String? value, {
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      descriptionGreaterThan(
    String? value, {
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      descriptionLessThan(
    String? value, {
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      descriptionBetween(
    String? lower,
    String? upper, {
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      descriptionContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'description',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      descriptionMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'description',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      descriptionIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'description',
        value: '',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      descriptionIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'description',
        value: '',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      firestoreIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'firestoreId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      firestoreIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'firestoreId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      firestoreIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'firestoreId',
        value: '',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      firestoreIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'firestoreId',
        value: '',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      flagIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'flag',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      flagIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'flag',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      flagEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'flag',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      flagGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'flag',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      flagLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'flag',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      flagBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'flag',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      flagStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'flag',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      flagEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'flag',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      flagContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'flag',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      flagMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'flag',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      flagIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'flag',
        value: '',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      flagIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'flag',
        value: '',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      homeCountryCodeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'homeCountryCode',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      homeCountryCodeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'homeCountryCode',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      homeCountryCodeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'homeCountryCode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      homeCountryCodeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'homeCountryCode',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      homeCountryCodeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'homeCountryCode',
        value: '',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      homeCountryCodeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'homeCountryCode',
        value: '',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      hostCountryCodeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'hostCountryCode',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      hostCountryCodeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'hostCountryCode',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      hostCountryCodeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'hostCountryCode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      hostCountryCodeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'hostCountryCode',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      hostCountryCodeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'hostCountryCode',
        value: '',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      hostCountryCodeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'hostCountryCode',
        value: '',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      idGreaterThan(
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      idLessThan(
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      idBetween(
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

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      imagesIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'images',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      imagesIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'images',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      imagesElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'images',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      imagesElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'images',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      imagesElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'images',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      imagesElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'images',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      imagesElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'images',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      imagesElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'images',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      imagesElementContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'images',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      imagesElementMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'images',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      imagesElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'images',
        value: '',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      imagesElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'images',
        value: '',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      imagesLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'images',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      imagesIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'images',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      imagesIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'images',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      imagesLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'images',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      imagesLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'images',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      imagesLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'images',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      isPrivateEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isPrivate',
        value: value,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      locationJsonIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'locationJson',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      locationJsonIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'locationJson',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      locationJsonEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'locationJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      locationJsonGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'locationJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      locationJsonLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'locationJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      locationJsonBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'locationJson',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      locationJsonStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'locationJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      locationJsonEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'locationJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      locationJsonContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'locationJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      locationJsonMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'locationJson',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      locationJsonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'locationJson',
        value: '',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      locationJsonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'locationJson',
        value: '',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      locationTypeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'locationType',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      locationTypeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'locationType',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      locationTypeEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'locationType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      locationTypeGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'locationType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      locationTypeLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'locationType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      locationTypeBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'locationType',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      locationTypeStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'locationType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      locationTypeEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'locationType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      locationTypeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'locationType',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      locationTypeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'locationType',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      locationTypeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'locationType',
        value: '',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      locationTypeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'locationType',
        value: '',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      memberCountEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'memberCount',
        value: value,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      memberCountGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'memberCount',
        value: value,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      memberCountLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'memberCount',
        value: value,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      memberCountBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'memberCount',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      membersIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'members',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      membersIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'members',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      membersElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'members',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      membersElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'members',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      membersElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'members',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      membersElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'members',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      membersElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'members',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      membersElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'members',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      membersElementContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'members',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      membersElementMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'members',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      membersElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'members',
        value: '',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      membersElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'members',
        value: '',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      membersLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'members',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      membersIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'members',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      membersIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'members',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      membersLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'members',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      membersLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'members',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      membersLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'members',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      nameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      nameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      nameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      nameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'name',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      nameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      nameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      nameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      nameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'name',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      nameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      nameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      profileImageIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'profileImage',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      profileImageIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'profileImage',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      profileImageEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'profileImage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      profileImageGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'profileImage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      profileImageLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'profileImage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      profileImageBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'profileImage',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      profileImageStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'profileImage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      profileImageEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'profileImage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      profileImageContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'profileImage',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      profileImageMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'profileImage',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      profileImageIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'profileImage',
        value: '',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      profileImageIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'profileImage',
        value: '',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      stateIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'state',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      stateIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'state',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      stateEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'state',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      stateGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'state',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      stateLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'state',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      stateBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'state',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      stateStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'state',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      stateEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'state',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      stateContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'state',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      stateMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'state',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      stateIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'state',
        value: '',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      stateIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'state',
        value: '',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      totalMembersIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'totalMembers',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      totalMembersIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'totalMembers',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      totalMembersEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'totalMembers',
        value: value,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      totalMembersGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'totalMembers',
        value: value,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      totalMembersLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'totalMembers',
        value: value,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      totalMembersBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'totalMembers',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      typeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'type',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      typeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'type',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      typeEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'type',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      typeGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'type',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      typeLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'type',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      typeBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'type',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      typeStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'type',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      typeEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'type',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      typeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'type',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      typeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'type',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      typeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'type',
        value: '',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      typeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'type',
        value: '',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      updatedAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'updatedAt',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      updatedAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'updatedAt',
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      updatedAtEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      updatedAtGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      updatedAtLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterFilterCondition>
      updatedAtBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'updatedAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension CommunityEntityQueryObject
    on QueryBuilder<CommunityEntity, CommunityEntity, QFilterCondition> {}

extension CommunityEntityQueryLinks
    on QueryBuilder<CommunityEntity, CommunityEntity, QFilterCondition> {}

extension CommunityEntityQuerySortBy
    on QueryBuilder<CommunityEntity, CommunityEntity, QSortBy> {
  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy> sortByChatId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'chatId', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      sortByChatIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'chatId', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy> sortByCity() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'city', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      sortByCityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'city', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy> sortByCountry() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'country', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      sortByCountryDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'country', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      sortByDescription() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'description', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      sortByDescriptionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'description', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      sortByFirestoreId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'firestoreId', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      sortByFirestoreIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'firestoreId', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy> sortByFlag() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'flag', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      sortByFlagDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'flag', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      sortByHomeCountryCode() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'homeCountryCode', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      sortByHomeCountryCodeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'homeCountryCode', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      sortByHostCountryCode() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hostCountryCode', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      sortByHostCountryCodeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hostCountryCode', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      sortByIsPrivate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isPrivate', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      sortByIsPrivateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isPrivate', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      sortByLocationJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'locationJson', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      sortByLocationJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'locationJson', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      sortByLocationType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'locationType', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      sortByLocationTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'locationType', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      sortByMemberCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'memberCount', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      sortByMemberCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'memberCount', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy> sortByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      sortByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      sortByProfileImage() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileImage', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      sortByProfileImageDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileImage', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy> sortByState() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'state', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      sortByStateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'state', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      sortByTotalMembers() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalMembers', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      sortByTotalMembersDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalMembers', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy> sortByType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      sortByTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      sortByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      sortByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension CommunityEntityQuerySortThenBy
    on QueryBuilder<CommunityEntity, CommunityEntity, QSortThenBy> {
  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy> thenByChatId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'chatId', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      thenByChatIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'chatId', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy> thenByCity() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'city', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      thenByCityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'city', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy> thenByCountry() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'country', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      thenByCountryDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'country', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      thenByDescription() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'description', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      thenByDescriptionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'description', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      thenByFirestoreId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'firestoreId', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      thenByFirestoreIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'firestoreId', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy> thenByFlag() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'flag', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      thenByFlagDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'flag', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      thenByHomeCountryCode() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'homeCountryCode', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      thenByHomeCountryCodeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'homeCountryCode', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      thenByHostCountryCode() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hostCountryCode', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      thenByHostCountryCodeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hostCountryCode', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      thenByIsPrivate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isPrivate', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      thenByIsPrivateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isPrivate', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      thenByLocationJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'locationJson', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      thenByLocationJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'locationJson', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      thenByLocationType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'locationType', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      thenByLocationTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'locationType', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      thenByMemberCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'memberCount', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      thenByMemberCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'memberCount', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy> thenByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      thenByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      thenByProfileImage() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileImage', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      thenByProfileImageDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileImage', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy> thenByState() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'state', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      thenByStateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'state', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      thenByTotalMembers() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalMembers', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      thenByTotalMembersDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalMembers', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy> thenByType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      thenByTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'type', Sort.desc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      thenByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QAfterSortBy>
      thenByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension CommunityEntityQueryWhereDistinct
    on QueryBuilder<CommunityEntity, CommunityEntity, QDistinct> {
  QueryBuilder<CommunityEntity, CommunityEntity, QDistinct> distinctByAdmins() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'admins');
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QDistinct> distinctByChatId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'chatId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QDistinct> distinctByCity(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'city', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QDistinct> distinctByCountry(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'country', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QDistinct>
      distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QDistinct>
      distinctByDescription({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'description', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QDistinct>
      distinctByFirestoreId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'firestoreId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QDistinct> distinctByFlag(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'flag', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QDistinct>
      distinctByHomeCountryCode({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'homeCountryCode',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QDistinct>
      distinctByHostCountryCode({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'hostCountryCode',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QDistinct> distinctByImages() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'images');
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QDistinct>
      distinctByIsPrivate() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isPrivate');
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QDistinct>
      distinctByLocationJson({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'locationJson', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QDistinct>
      distinctByLocationType({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'locationType', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QDistinct>
      distinctByMemberCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'memberCount');
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QDistinct>
      distinctByMembers() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'members');
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QDistinct> distinctByName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'name', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QDistinct>
      distinctByProfileImage({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'profileImage', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QDistinct> distinctByState(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'state', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QDistinct>
      distinctByTotalMembers() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'totalMembers');
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QDistinct> distinctByType(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'type', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CommunityEntity, CommunityEntity, QDistinct>
      distinctByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAt');
    });
  }
}

extension CommunityEntityQueryProperty
    on QueryBuilder<CommunityEntity, CommunityEntity, QQueryProperty> {
  QueryBuilder<CommunityEntity, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<CommunityEntity, List<String>?, QQueryOperations>
      adminsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'admins');
    });
  }

  QueryBuilder<CommunityEntity, String?, QQueryOperations> chatIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'chatId');
    });
  }

  QueryBuilder<CommunityEntity, String?, QQueryOperations> cityProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'city');
    });
  }

  QueryBuilder<CommunityEntity, String?, QQueryOperations> countryProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'country');
    });
  }

  QueryBuilder<CommunityEntity, int?, QQueryOperations> createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<CommunityEntity, String?, QQueryOperations>
      descriptionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'description');
    });
  }

  QueryBuilder<CommunityEntity, String, QQueryOperations>
      firestoreIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'firestoreId');
    });
  }

  QueryBuilder<CommunityEntity, String?, QQueryOperations> flagProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'flag');
    });
  }

  QueryBuilder<CommunityEntity, String?, QQueryOperations>
      homeCountryCodeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'homeCountryCode');
    });
  }

  QueryBuilder<CommunityEntity, String?, QQueryOperations>
      hostCountryCodeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'hostCountryCode');
    });
  }

  QueryBuilder<CommunityEntity, List<String>?, QQueryOperations>
      imagesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'images');
    });
  }

  QueryBuilder<CommunityEntity, bool, QQueryOperations> isPrivateProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isPrivate');
    });
  }

  QueryBuilder<CommunityEntity, String?, QQueryOperations>
      locationJsonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'locationJson');
    });
  }

  QueryBuilder<CommunityEntity, String?, QQueryOperations>
      locationTypeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'locationType');
    });
  }

  QueryBuilder<CommunityEntity, int, QQueryOperations> memberCountProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'memberCount');
    });
  }

  QueryBuilder<CommunityEntity, List<String>?, QQueryOperations>
      membersProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'members');
    });
  }

  QueryBuilder<CommunityEntity, String, QQueryOperations> nameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'name');
    });
  }

  QueryBuilder<CommunityEntity, String?, QQueryOperations>
      profileImageProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'profileImage');
    });
  }

  QueryBuilder<CommunityEntity, String?, QQueryOperations> stateProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'state');
    });
  }

  QueryBuilder<CommunityEntity, int?, QQueryOperations> totalMembersProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'totalMembers');
    });
  }

  QueryBuilder<CommunityEntity, String?, QQueryOperations> typeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'type');
    });
  }

  QueryBuilder<CommunityEntity, int?, QQueryOperations> updatedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAt');
    });
  }
}
