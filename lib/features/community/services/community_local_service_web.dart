import 'package:diaspora_nearby/features/community/models/community_data.dart';

class CommunityLocalService {
  // No args constructor or matches native
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
    // No-op
  }
}
