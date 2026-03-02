/// Local organization cache service.
///
/// Previously powered by Isar. Now a no-op — Firestore's built-in offline
/// persistence handles all local caching automatically.
class OrganizationLocalService {
  OrganizationLocalService();

  Future<void> saveOrganization(Map<String, dynamic> data) async {}

  Future<Map<String, dynamic>?> getOrganization(String orgId) async {
    return null;
  }

  Future<List<Map<String, dynamic>>> getUserOrganizations(String userId) async {
    return [];
  }
}
