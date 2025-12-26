import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/models/community_data.dart';

final communityRepositoryProvider = Provider((ref) => CommunityRepository());

class CommunityRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<Community?> getCommunity(String communityId) async {
    try {
      final doc = await _firestore.collection('communities').doc(communityId).get();
      if (doc.exists) {
        return Community.fromJson({...doc.data()!, 'id': doc.id});
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<List<Community>> getUserCommunities(String uid) async {
    try {
      // Query both 'members' (correct) and 'memberIds' (legacy/service bug)
      final membersQuery = await _firestore
          .collection('communities')
          .where('members', arrayContains: uid)
          .get();
          
      final memberIdsQuery = await _firestore
          .collection('communities')
          .where('memberIds', arrayContains: uid)
          .get();
      
      final Map<String, Community> communities = {};
      
      void processDocs(List<QueryDocumentSnapshot> docs) {
        for (var doc in docs) {
          if (!communities.containsKey(doc.id)) {
            final data = doc.data() as Map<String, dynamic>;
            // Fix field mismatch for model parsing
            if (data['members'] == null && data['memberIds'] != null) {
              data['members'] = data['memberIds'];
            }
            communities[doc.id] = Community.fromJson({...data, 'id': doc.id});
          }
        }
      }

      processDocs(membersQuery.docs);
      processDocs(memberIdsQuery.docs);
      
      return communities.values.toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<Community>> getAllCommunities() async {
    try {
      final snapshot = await _firestore.collection('communities').get();
      return snapshot.docs
          .map((doc) => Community.fromJson({...doc.data(), 'id': doc.id}))
          .toList();
    } catch (e) {
      return [];
    }
    }

  Future<Community?> joinOrCreateCommunity({
    required String uid,
    required String homeCountryCode,
    String? hostCountryCode, // Null if home community
    required String city,
    required String locationType, // home, host, city, state, etc.
    String? state,
    String? country,
  }) async {
    try {
      // 1. Construct Unique Community Identifier Logic
      // For simplicity in this iteration, we look for a community with matching:
      // locationType, homeCountryCode, hostCountryCode (if applicable), and city.

      Query query = _firestore.collection('communities')
          .where('locationType', isEqualTo: locationType)
          .where('homeCountryCode', isEqualTo: homeCountryCode);
          
      if (hostCountryCode != null) {
        query = query.where('hostCountryCode', isEqualTo: hostCountryCode);
      }
      
      // Note: If we use 'city' in location map, we can't query it easily without an index on 'location.city'
      // Ideally we store top-level fields for querying or rely on a composite index.
      // For now, let's assume we query by name or we rely on a deterministic ID if possible.
      // OPTION: Query by a specific set of fields.
      
      // Let's rely on constructing a query that matches the location specifically.
      if (city.isNotEmpty) {
        // This requires 'location.city' index potentially.
        // Instead, let's check top-level if we added 'city' field in registration. 
        // Based on ProfileRepository, we added 'city' to top level for organizations.
        // Let's search by name construction or verify if we can search 'location.city'.
        // SAFE BET: Filter in memory for now if volume is low, OR try to find by ID if we used deterministic IDs.
        
        // BETTER: Query for communities that 'match' the criteria.
        // Since we don't have deterministic IDs guaranteed for all, we search.
      }

      // Allow searching by exact name if we can generate it, OR search by location fields.
      // To ensure we find the *right* community, let's search by location map properties if indexed, 
      // or key fields.
      
      // IMPROVEMENT: Use deterministic ID if possible for lookup? 
      // e.g. community_home_US_host_CA_city_Toronto
      // If we don't have that, we query.
      
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
        // Join existing
        if (!existingCommunity.members.contains(uid)) {
          await _firestore.collection('communities').doc(existingCommunity.id).update({
            'members': FieldValue.arrayUnion([uid]),
            'totalMembers': FieldValue.increment(1),
          });
          // Update local object
          final updatedMembers = List<String>.from(existingCommunity.members)..add(uid);
          return existingCommunity.copyWith(
            members: updatedMembers, 
            memberCount: (existingCommunity.memberCount ?? 0) + 1
          );
        }
        return existingCommunity;
      } else {
        // Create new
        final newDocRef = _firestore.collection('communities').doc();
        
        // Generate Name
        // E.g. "Nigerians in New York" or "New York Community" depending on type
        // Use simpler naming: "{City} Community"
        final name = '$city Community'; 
        
        final newCommunity = Community(
          id: newDocRef.id,
          name: name,
          description: 'Community for $city',
          type: 'diaspora', // or specific type
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
          memberCount: 1, // field in class
          totalMembers: 1, // field in store
          createdAt: now,
          updatedAt: now,
          isPrivate: false,
          images: [],
        );

        final data = newCommunity.toJson();
        // Ensure strictly needed fields
        data['members'] = [uid];
        data['memberCount'] = 1;
        data['totalMembers'] = 1; // Explicit
        
        await newDocRef.set(data);
        return newCommunity;
      }

    } catch (e) {
      // logger.e("Error joining/creating community", error: e);
      return null;
    }
  }
}
