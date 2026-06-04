import 'package:diaspora_nearby/features/admin_dashboard/services/admin_service.dart';
import 'package:flutter/material.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:intl/intl.dart';

class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
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
      backgroundColor: AppTheme.elevationColor(context, 0), // Level 0 page bg
      body: Column(
        children: [
          // Search & Filters Header
          Container(
            padding: const EdgeInsets.all(24),
            color: AppTheme.elevationColor(context, 1), // Level 1 header
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText: 'Search users by name, email, or phone...',
                      prefixIcon: const Icon(LucideIcons.search, size: 20),
                      filled: true,
                      fillColor: AppTheme.elevationColor(
                        context,
                        2,
                      ), // Level 2 input
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                _FilterButton(
                  label: 'Filter',
                  icon: LucideIcons.filter,
                  onTap: () {},
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Users Table/List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final users =
                    snapshot.data?.docs
                        .map((doc) {
                          return ProfileData.fromJson({
                            ...doc.data() as Map<String, dynamic>,
                            'uid': doc.id,
                          });
                        })
                        .where((u) {
                          final query = _searchQuery.toLowerCase();
                          return u.fullName.toLowerCase().contains(query) ||
                              (u.phone.toLowerCase().contains(query));
                        })
                        .toList() ??
                    [];

                if (users.isEmpty) {
                  return const Center(
                    child: Text('No users found matching your search.'),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 24,
                  ),
                  itemCount: users.length,
                  separatorBuilder: (c, i) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final user = users[index];
                    return _UserTile(user: user, ref: ref);
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

class _UserTile extends StatelessWidget {
  final ProfileData user;
  final WidgetRef ref;

  const _UserTile({required this.user, required this.ref});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.elevationColor(context, 1), // Level 1 card
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundImage: NetworkImage(user.profileImage),
            child: null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      user.fullName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (user.isAdmin == true) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Admin',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                    if (user.isBanned == true) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Banned',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  user.phone,
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Joined ${user.createdAt != null ? DateFormat.yMMMd().format(user.createdAt!) : "N/A"}',
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      // Manage User Dialog
                    },
                    child: const Text('Manage'),
                  ),
                  IconButton(
                    icon: Icon(
                      user.isBanned == true
                          ? LucideIcons.unlock
                          : LucideIcons.ban,
                      size: 18,
                      color: user.isBanned == true ? Colors.green : Colors.red,
                    ),
                    onPressed: () => _toggleBan(context, user, ref),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _toggleBan(
    BuildContext context,
    ProfileData user,
    WidgetRef ref,
  ) async {
    final action = user.isBanned == true ? 'Unban' : 'Ban';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$action User'),
        content: Text(
          'Are you sure you want to ${action.toLowerCase()} ${user.fullName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              action,
              style: TextStyle(
                color: user.isBanned == true ? Colors.green : Colors.red,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final adminService = ref.read(adminServiceProvider);
      await adminService.banUser(user.uid!, !(user.isBanned == true));
    }
  }
}

class _FilterButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _FilterButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.elevationColor(context, 1), // Level 1 button
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.grey[600]),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}
