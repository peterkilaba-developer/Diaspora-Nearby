import 'package:diaspora_nearby/features/community/models/community_data.dart';

/// Local community cache service.
///
/// Previously powered by Isar. Now a no-op — Firestore's built-in offline
/// persistence handles all local caching automatically.
class CommunityLocalService {
  CommunityLocalService();

  Stream<List<Community>> watchUserCommunities(String uid) {
    return Stream.value([]);
  }

  Future<List<Community>> getLocalUserCommunities(String uid) async {
    return [];
  }

  Future<Community?> getCommunity(String communityId) async {
    return null;
  }

  Future<void> saveCommunitiesToLocal(List<Community> communities) async {
    // No-op: Firestore offline persistence caches documents automatically
  }
}
