import 'dart:convert';
import 'package:isar/isar.dart';
import 'package:flutter/foundation.dart';
import 'package:diaspora_nearby/core/services/database_service.dart';
import 'package:diaspora_nearby/features/community/models/community_data.dart';
import 'package:diaspora_nearby/features/shared/data/local/entities/community_entity.dart';

class CommunityLocalService {
  final Isar? _isar;

  CommunityLocalService() : _isar = DatabaseService().isar;

  Stream<List<Community>> watchUserCommunities(String uid) {
    if (_isar == null) return Stream.value([]);
    return _isar!.communityEntitys
        .filter()
        .membersElementEqualTo(uid)
        .watch(fireImmediately: true)
        .map((entities) => entities.map(_mapEntityToModel).toList());
  }

  Future<List<Community>> getLocalUserCommunities(String uid) async {
    if (_isar == null) return [];
    final entities = await _isar!.communityEntitys
        .filter()
        .membersElementEqualTo(uid)
        .findAll();
    return entities.map(_mapEntityToModel).toList();
  }

  Future<Community?> getCommunity(String communityId) async {
    if (_isar == null) return null;
    final local = await _isar!.communityEntitys
        .filter()
        .firestoreIdEqualTo(communityId)
        .findFirst();

    if (local != null) {
      return _mapEntityToModel(local);
    }
    return null;
  }

  Future<void> saveCommunitiesToLocal(List<Community> communities) async {
    if (_isar == null) return;
    try {
      await _isar!.writeTxn(() async {
        for (final c in communities) {
          final entity = _mapModelToEntity(c);
          
          final existing = await _isar!.communityEntitys
              .filter()
              .firestoreIdEqualTo(c.id)
              .findFirst();

          if (existing != null) {
            entity.id = existing.id; // Preserve Local ID
          }

          await _isar!.communityEntitys.put(entity);
        }
      });
    } catch (e) {
      debugPrint('Error saving communities to local: $e');
    }
  }

  Community _mapEntityToModel(CommunityEntity entity) {
    Map<String, dynamic>? locMap;
    if (entity.locationJson != null) {
      try {
        locMap = jsonDecode(entity.locationJson!);
      } catch (_) {}
    }

    return Community(
      id: entity.firestoreId,
      name: entity.name,
      homeCountryCode: entity.homeCountryCode,
      hostCountryCode: entity.hostCountryCode,
      locationType: entity.locationType,
      type: entity.type,
      profileImage: entity.profileImage,
      memberCount: entity.memberCount,
      totalMembers: entity.totalMembers,
      isPrivate: entity.isPrivate,
      location: locMap,
      chatId: entity.chatId,
      flag: entity.flag,
      members: entity.members ?? [],
      admins: entity.admins ?? [],
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
      images: entity.images ?? [],
    );
  }

  CommunityEntity _mapModelToEntity(Community model) {
    final entity = CommunityEntity();
    entity.firestoreId = model.id;
    entity.name = model.name;
    entity.homeCountryCode = model.homeCountryCode;
    entity.hostCountryCode = model.hostCountryCode;
    entity.locationType = model.locationType;
    entity.type = model.type;
    entity.profileImage = model.profileImage;
    entity.memberCount = model.memberCount;
    entity.totalMembers = model.totalMembers;
    entity.isPrivate = model.isPrivate;
    entity.chatId = model.chatId;
    entity.flag = model.flag;
    entity.members = model.members;
    entity.admins = model.admins;
    entity.createdAt = model.createdAt;
    entity.updatedAt = model.updatedAt;
    entity.images = model.images;

    if (model.location != null) {
      entity.locationJson = jsonEncode(model.location);
      entity.city = model.location!['city'];
      entity.state = model.location!['state'];
      entity.country = model.location!['country'];
    }

    return entity;
  }
}
