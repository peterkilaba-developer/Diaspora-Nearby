import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart'; // [NEW]
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
          const SizedBox(height: 24),
          _buildSectionHeader(context, 'LEGAL'),
          _buildSettingsItem(
            context,
            icon: LucideIcons.fileText,
            title: 'Privacy Policy',
            subtitle: 'Read our privacy policy',
            onTap: () => _launchUrl('https://diasporanearby.com/privacy'),
          ),
          _buildSettingsItem(
            context,
            icon: LucideIcons.fileSignature,
            title: 'Terms of Service (EULA)',
            subtitle: 'Read our terms of service',
            onTap: () => _launchUrl('https://diasporanearby.com/terms'),
          ),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $url');
    }
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
              color: Theme.of(context).colorScheme.primary,
            ),
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
      leading: Icon(
        icon,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      title: Text(title),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      trailing: const Icon(LucideIcons.chevronRight, size: 16),
      onTap: onTap,
    );
  }
}
