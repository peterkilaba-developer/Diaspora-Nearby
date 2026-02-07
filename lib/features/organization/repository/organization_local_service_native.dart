import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:diaspora_nearby/core/services/database_service.dart';
import 'package:diaspora_nearby/features/shared/data/local/entities/organization_entity.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class OrganizationLocalService {
  final Isar? _isar;

  OrganizationLocalService() : _isar = DatabaseService().isar;

  Future<void> saveOrganization(Map<String, dynamic> data) async {
    if (_isar == null) return;
    try {
      await _isar!.writeTxn(() async {
        final existing = await _isar!.organizationEntitys
            .filter()
            .firestoreIdEqualTo(data['id'])
            .findFirst();

        final entity = _mapModelToEntity(data);
        if (existing != null) {
          entity.id = existing.id; // Preserve Local ID
        }
        await _isar!.organizationEntitys.put(entity);
      });
    } catch (e) {
      debugPrint('Error caching organization: $e');
    }
  }

  Future<Map<String, dynamic>?> getOrganization(String orgId) async {
    if (_isar == null) return null;
    final cachedEntity = await _isar!.organizationEntitys
        .filter()
        .firestoreIdEqualTo(orgId)
        .findFirst();
    if (cachedEntity != null) {
      return _mapEntityToModel(cachedEntity);
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getUserOrganizations(String userId) async {
    if (_isar == null) return [];
    
    final orgs = <String, Map<String, dynamic>>{};
    
    final cachedEntities = await _isar!.organizationEntitys
        .filter()
        .adminsElementEqualTo(userId)
        .or()
        .superAdminIdEqualTo(userId)
        .or()
        .pendingAdminsElementEqualTo(userId)
        .findAll();

    for (final entity in cachedEntities) {
      final org = _mapEntityToModel(entity);
      final id = org['id'];
      if (id != null) {
        orgs[id] = org;
      }
    }
    
    return orgs.values.toList();
  }

  // Mappers
  OrganizationEntity _mapModelToEntity(Map<String, dynamic> data) {
    final entity = OrganizationEntity();
    entity.firestoreId = data['id'];
    entity.name = data['name'];
    entity.businessName = data['businessName'];
    entity.profileImage = data['profileImage'];
    entity.logoUrl = data['logoUrl'];
    entity.description = data['description'];
    entity.website = data['website'];
    entity.email = data['email'];
    entity.phone = data['phone'];
    entity.address = data['address'];
    entity.superAdminId = data['superAdminId'];
    if (data['admins'] != null) {
      entity.admins = List<String>.from(data['admins']);
    }
    if (data['pendingAdmins'] != null) {
      entity.pendingAdmins = List<String>.from(data['pendingAdmins']);
    }
    if (data['followers'] != null) {
      entity.followers = List<String>.from(data['followers']);
    }
    entity.chatId = data['chatId'];
    entity.status = data['status'];
    
    // Handle timestamps
     if (data['createdAt'] is int) {
      entity.createdAt = data['createdAt'];
    } else if (data['createdAt'] is Timestamp) {
      entity.createdAt = (data['createdAt'] as Timestamp).millisecondsSinceEpoch;
    }

    if (data['updatedAt'] is int) {
      entity.updatedAt = data['updatedAt'];
    } else if (data['updatedAt'] is Timestamp) {
      entity.updatedAt = (data['updatedAt'] as Timestamp).millisecondsSinceEpoch;
    }

    // Store full blob for extra fields
    entity.metadataJson = jsonEncode(data);

    return entity;
  }

  Map<String, dynamic> _mapEntityToModel(OrganizationEntity entity) {
    if (entity.metadataJson != null) {
       try {
         return jsonDecode(entity.metadataJson!);
       } catch (e) {
         debugPrint('Error decoding org metadata: $e');
       }
    }
    return {
      'id': entity.firestoreId,
      'name': entity.name,
      'businessName': entity.businessName,
      'profileImage': entity.profileImage,
      'logoUrl': entity.logoUrl,
      'chatId': entity.chatId,
      'status': entity.status,
      // ... fallback to partial data if json missing
    };
  }
}
