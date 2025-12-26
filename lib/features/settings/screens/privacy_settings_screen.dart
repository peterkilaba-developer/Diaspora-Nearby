import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'blocked_users_screen.dart';

class PrivacySettingsScreen extends StatelessWidget {
  const PrivacySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy & Safety'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        children: [
          _buildSettingsItem(
            context,
            icon: LucideIcons.ban,
            title: 'Blocked Accounts',
            subtitle: 'Manage blocked users',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BlockedUsersScreen()),
              );
            },
          ),
          // Placeholders for future settings
          /*
          _buildSettingsItem(
            context,
            icon: LucideIcons.eye,
            title: 'Last Seen & Online',
            subtitle: 'Everyone',
            onTap: () {},
          ),
          _buildSettingsItem(
            context,
            icon: LucideIcons.lock,
            title: 'Profile Photo',
            subtitle: 'Everyone',
            onTap: () {},
          ),
          */
        ],
      ),
    );
  }

  Widget _buildSettingsItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
      title: Text(title),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      trailing: const Icon(LucideIcons.chevronRight, size: 16),
      onTap: onTap,
    );
  }
}
