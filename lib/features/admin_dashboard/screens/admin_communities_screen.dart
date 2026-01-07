import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diaspora_nearby/models/community_data.dart';
import 'package:diaspora_nearby/data/countries.dart' as country_data;

class AdminCommunitiesScreen extends ConsumerStatefulWidget {
  const AdminCommunitiesScreen({super.key});

  @override
  ConsumerState<AdminCommunitiesScreen> createState() => _AdminCommunitiesScreenState();
}

class _AdminCommunitiesScreenState extends ConsumerState<AdminCommunitiesScreen> {
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          // Header Actions
          Container(
            padding: const EdgeInsets.all(24),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText: 'Search communities by name or type...',
                      prefixIcon: const Icon(LucideIcons.search, size: 20),
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                _ActionButton(
                  label: 'Add Community',
                  icon: LucideIcons.plus,
                  onTap: () {},
                  primary: true,
                ),
              ],
            ),
          ),
          
          const Divider(height: 1),
          
          // Communities List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('communities').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final communities = snapshot.data?.docs.map((doc) {
                  return Community.fromJson({...doc.data() as Map<String, dynamic>, 'id': doc.id});
                }).where((c) {
                  final query = _searchQuery.toLowerCase();
                  return c.name.toLowerCase().contains(query) ||
                         (c.type?.toLowerCase().contains(query) ?? false);
                }).toList() ?? [];

                if (communities.isEmpty) {
                  return const Center(child: Text('No communities found.'));
                }

                return GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1.5,
                  ),
                  itemCount: communities.length,
                  itemBuilder: (context, index) {
                    final comm = communities[index];
                    return _CommunityCard(community: comm);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CommunityCard extends StatelessWidget {
  final Community community;

  const _CommunityCard({required this.community});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    community.hostCountryCode != null 
                        ? (country_data.getCountryByCode(community.hostCountryCode!)?.flag ?? (community.type?.substring(0, 1).toUpperCase() ?? 'C'))
                        : (community.type?.substring(0, 1).toUpperCase() ?? 'C'),
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      community.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      community.type?.toUpperCase() ?? 'COMMUNITY',
                      style: TextStyle(fontSize: 10, color: Colors.grey[500], fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const Icon(LucideIcons.moreVertical, size: 16, color: Colors.grey),
            ],
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${community.memberCount ?? 0}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const Text('Members', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
              _StatusBadge(isPrivate: community.isPrivate),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isPrivate;
  const _StatusBadge({required this.isPrivate});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isPrivate ? Colors.orange[50] : Colors.green[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isPrivate ? 'PRIVATE' : 'PUBLIC',
        style: TextStyle(
          fontSize: 10, 
          fontWeight: FontWeight.bold, 
          color: isPrivate ? Colors.orange : Colors.green,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: primary ? Colors.blue : Colors.white,
        foregroundColor: primary ? Colors.white : Colors.black,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: primary ? BorderSide.none : BorderSide(color: Colors.grey.shade300),
        ),
      ),
    );
  }
}

