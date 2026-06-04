import 'package:flutter/material.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

class AdminDashboardScreen extends StatelessWidget {
  final Widget child;

  const AdminDashboardScreen({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;

    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 250,
            color: Colors.grey[900],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  child: const Row(
                    children: [
                      Icon(
                        LucideIcons.shieldCheck,
                        color: Colors.blue,
                        size: 24,
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Admin Panel',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.grey),
                const SizedBox(height: 16),
                _SidebarItem(
                  icon: LucideIcons.layoutDashboard,
                  label: 'Overview',
                  isActive: location == '/admin/overview',
                  onTap: () => context.go('/admin/overview'),
                ),
                _SidebarItem(
                  icon: LucideIcons.users,
                  label: 'Users',
                  isActive: location == '/admin/users',
                  onTap: () => context.go('/admin/users'),
                ),
                _SidebarItem(
                  icon: LucideIcons.home,
                  label: 'Communities',
                  isActive: location == '/admin/communities',
                  onTap: () => context.go('/admin/communities'),
                ),
                _SidebarItem(
                  icon: LucideIcons.landmark,
                  label: 'Chamber Requests',
                  isActive: location == '/admin/chamber-requests',
                  onTap: () => context.go('/admin/chamber-requests'),
                ),
                const Spacer(),
                _SidebarItem(
                  icon: LucideIcons.arrowLeft,
                  label: 'Exit Admin',
                  isActive: false,
                  onTap: () => context.go('/profile'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),

          // Main Content
          Expanded(
            child: Column(
              children: [
                AppBar(
                  backgroundColor: AppTheme.elevationColor(
                    context,
                    1,
                  ), // Level 1 header
                  elevation: 0,
                  title: Text(
                    _getTitle(location),
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  iconTheme: const IconThemeData(color: Colors.black),
                  actions: [
                    IconButton(
                      icon: const Icon(LucideIcons.bell),
                      onPressed: () {},
                    ),
                    const SizedBox(width: 16),
                  ],
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getTitle(String location) {
    if (location.contains('overview')) return 'Dashboard Overview';
    if (location.contains('users')) return 'User Management';
    if (location.contains('communities')) return 'Community Management';
    return 'Admin Dashboard';
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.blue.withValues(alpha: 0.1)
              : Colors.transparent,
          border: isActive
              ? const Border(left: BorderSide(color: Colors.blue, width: 4))
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isActive ? Colors.blue : Colors.grey[400],
              size: 20,
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.blue : Colors.grey[400],
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
