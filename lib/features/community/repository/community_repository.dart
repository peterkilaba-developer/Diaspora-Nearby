import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart' hide Query;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:diaspora_nearby/models/community_data.dart';
import 'package:diaspora_nearby/services/database_service.dart';
import 'package:diaspora_nearby/features/shared/data/local/entities/community_entity.dart';

final communityRepositoryProvider = Provider((ref) => CommunityRepository());

class CommunityRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Isar? _isar = DatabaseService().isar;

  // ===========================================================================
  // OFFLINE-FIRST METHODS (Isar)
  // ===========================================================================

  Stream<List<Community>> watchUserCommunities(String uid) {
    if (_isar == null) {
      // WEB: Direct Firestore watch
      return _firestore
          .collection('communities')
          .where('members', arrayContains: uid)
          .snapshots()
          .map((snapshot) => snapshot.docs.map((doc) {
                final data = doc.data();
                return Community.fromJson({...data, 'id': doc.id});
              }).toList());
    }
    return _isar!.communityEntitys
        .filter()
        .membersElementEqualTo(uid)
        .watch(fireImmediately: true)
        .map((entities) => entities.map(_mapEntityToModel).toList());
  }

  /// Get communities from Local DB (Snapshot)
  Future<List<Community>> getLocalUserCommunities(String uid) async {
    if (_isar == null) return [];
    final entities = await _isar!.communityEntitys
        .filter()
        .membersElementEqualTo(uid)
        .findAll();
    return entities.map(_mapEntityToModel).toList();
  }

  /// Sync User Communities (Remote -> Local)
  /// Call this when the app starts, or on pull-to-refresh.
  Future<void> syncUserCommunities(String uid) async {
    try {
      final membersQuery = await _firestore
          .collection('communities')
          .where('members', arrayContains: uid)
          .get();

      // Legacy support for 'memberIds'
      final memberIdsQuery = await _firestore
          .collection('communities')
          .where('memberIds', arrayContains: uid)
          .get();

      final allDocs = [...membersQuery.docs, ...memberIdsQuery.docs];
      final uniqueDocs = <String, DocumentSnapshot>{};
      
      for (var doc in allDocs) {
        uniqueDocs[doc.id] = doc;
      }

      final communities = uniqueDocs.values.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        if (data['members'] == null && data['memberIds'] != null) {
          data['members'] = data['memberIds'];
        }
        return Community.fromJson({...data, 'id': doc.id});
      }).toList();

      if (_isar != null) {
        await _saveCommunitiesToLocal(communities);
        debugPrint('✅ Synced ${communities.length} communities to local DB');
      }
      
    } catch (e) {
      debugPrint('❌ Error syncing communities: $e');
      // In offline-first, we just fail silently for the sync, 
      // the user still sees local data.
    }
  }

  // ===========================================================================
  // HYBRID METHODS (Legacy Support / Migration)
  // ===========================================================================

  /// Get Community (Try Local, then Remote)
  Future<Community?> getCommunity(String communityId) async {
    // 1. Try Local
    if (_isar != null) {
      final local = await _isar!.communityEntitys
          .filter()
          .firestoreIdEqualTo(communityId)
          .findFirst();
          
      if (local != null) {
        // Trigger background update if needed (stale-while-revalidate logic can go here)
        _fetchAndSaveCommunity(communityId); 
        return _mapEntityToModel(local);
      }
    }

    // 2. Fetch Remote
    return await _fetchAndSaveCommunity(communityId);
  }

  Future<Community?> _fetchAndSaveCommunity(String communityId) async {
    try {
      final doc = await _firestore.collection('communities').doc(communityId).get();
      if (doc.exists) {
        final community = Community.fromJson({...doc.data()!, 'id': doc.id});
        await _saveCommunitiesToLocal([community]);
        return community;
      }
    } catch (e) {
      debugPrint('Error fetching community: $e');
    }
    return null;
  }

  // ===========================================================================
  // WRITE METHODS (Ideally invalidates cache or optimistic updates)
  // ===========================================================================

  Future<Community?> joinOrCreateCommunity({
    required String uid,
    required String homeCountryCode,
    String? hostCountryCode,
    required String city,
    required String locationType,
    String? state,
    String? country,
  }) async {
    // ... (Keep existing complex logic, but update local DB on success)
    // For brevity, I'm keeping the logic but adding the local save.
    
    try {
       var query = _firestore.collection('communities')
          .where('locationType', isEqualTo: locationType)
          .where('homeCountryCode', isEqualTo: homeCountryCode);
          
      if (hostCountryCode != null) {
        query = query.where('hostCountryCode', isEqualTo: hostCountryCode);
      }
      
      final querySnapshot = await query.get();
      Community? existingCommunity;
      
      for (var doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final loc = data['location'] as Map<String, dynamic>?;
        if (loc != null && 
            loc['city'] == city && 
            loc['state'] == state && 
            loc['country'] == country) {
              existingCommunity = Community.fromJson({...data, 'id': doc.id});
              break;
        }
      }

      final now = DateTime.now().millisecondsSinceEpoch;

      if (existingCommunity != null) {
        if (!existingCommunity.members.contains(uid)) {
          await _firestore.collection('communities').doc(existingCommunity.id).update({
            'members': FieldValue.arrayUnion([uid]),
            'totalMembers': FieldValue.increment(1),
          });
          
          final updated = existingCommunity.copyWith(
            members: [...existingCommunity.members, uid],
            memberCount: (existingCommunity.memberCount) + 1
          );
          
          await _saveCommunitiesToLocal([updated]);
          return updated;
        }
        await _saveCommunitiesToLocal([existingCommunity]);
        return existingCommunity;
      } else {
        // Create new
        final newDocRef = _firestore.collection('communities').doc();
         final name = '$city Community'; 
        
        final newCommunity = Community(
          id: newDocRef.id,
          name: name,
          description: 'Community for $city',
          type: 'diaspora',
          locationType: locationType,
          homeCountryCode: homeCountryCode,
          hostCountryCode: hostCountryCode,
          location: {
            'city': city,
            'state': state,
            'country': country,
            'countryCode': hostCountryCode ?? homeCountryCode,
          },
          members: [uid],
          admins: [uid],
          memberCount: 1,
          totalMembers: 1,
          createdAt: now,
          updatedAt: now,
          isPrivate: false,
          images: [],
        );

        final data = newCommunity.toJson();
        data['members'] = [uid];
        data['memberCount'] = 1;
        data['totalMembers'] = 1;
        
        await newDocRef.set(data);
        await _saveCommunitiesToLocal([newCommunity]);
        return newCommunity;
      }
    } catch (e) {
      debugPrint("Error joining/creating community: $e");
      return null;
    }
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================
  
  // Backwards compatibility for existing FutureProvider calls
  Future<List<Community>> getUserCommunities(String uid) async {
    // Trigger sync
    syncUserCommunities(uid); 
    // Return local immediately (stale but fast)
    return getLocalUserCommunities(uid);
  }

  Future<List<Community>> getAllCommunities() async {
     // This might be heavy, but let's just fetch from firestore for now as it's rarely used
     // Or implement syncAllCommunities()
      try {
      final snapshot = await _firestore.collection('communities').get();
      final list = snapshot.docs
          .map((doc) => Community.fromJson({...doc.data(), 'id': doc.id}))
          .toList();
      await _saveCommunitiesToLocal(list);
      return list;
    } catch (e) {
      return [];
    }
  }

  Future<void> _saveCommunitiesToLocal(List<Community> communities) async {
    if (_isar == null) return;
    await _isar!.writeTxn(() async {
      for (final c in communities) {
        final entity = _mapModelToEntity(c);
        
        // Check if exists to preserve ID if possible? Isar handles upsert by index.
        // We use firestoreId as a unique index with replace=true.
        // However, we need to map the internal Isar ID if we want to update.
        // But here we rely on the @Index(replace: true) on firestoreId.
        // Wait, Isar auto-increment ID is separate.
        // We need to find the existing Isar ID if we want to update it properly
        // OR rely on Isar's distinct constraint to replace the object.
        // If unique:true, replace:true is set, putting a new object with same firestoreId
        // might replace it, but the auto-increment ID changes unless we reuse it.
        // Better: Find existing by firestoreId.
        
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
      description: entity.description,
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
    entity.description = model.description;
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
