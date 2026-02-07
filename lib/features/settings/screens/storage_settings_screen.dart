import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/shared/ui/glass_container.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/core/services/database_service.dart';
import 'package:diaspora_nearby/features/auth/services/session_service.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class StorageSettingsScreen extends ConsumerStatefulWidget {
  const StorageSettingsScreen({super.key});

  @override
  ConsumerState<StorageSettingsScreen> createState() => _StorageSettingsScreenState();
}

class _StorageSettingsScreenState extends ConsumerState<StorageSettingsScreen> {
  bool _isClearing = false;

  Future<void> _clearImageCache() async {
    setState(() => _isClearing = true);
    try {
      await DefaultCacheManager().emptyCache();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image cache cleared')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error clearing cache: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  Future<void> _clearDatabase() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Local Database?'),
        content: const Text(
          'This will remove all cached messages and communities from this device. '
          'They will be re-synced from the server when you open them again.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isClearing = true);
    try {
      await DatabaseService().clean();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Local database cleared')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error clearing database: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  Future<void> _fullReset() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(LucideIcons.alertTriangle, color: Colors.red),
            SizedBox(width: 8),
            Text('Full App Reset?'),
          ],
        ),
        content: const Text(
          'This will clear ALL local data, settings, and log you out. '
          'The app will return to its initial state.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('RESET EVERYTHING'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isClearing = true);
    try {
      // 1. Clear Database
      await DatabaseService().clean();
      // 2. Clear Preferences
      await ref.read(sessionServiceProvider).clearAll();
      // 3. Clear Image Cache
      await DefaultCacheManager().emptyCache();
      // 4. Sign Out
      await ref.read(authRepositoryProvider).signOut();
      
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error during reset: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage & Cache'),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(AppTheme.pageHorizontalPadding),
            children: [
              const Text(
                'Manage your local data and cache to free up space or fix synchronization issues.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 24),
              
              _buildSectionHeader('CACHE MANAGEMENT'),
              GlassContainer(
                child: _buildStorageItem(
                  icon: LucideIcons.image,
                  iconColor: Colors.blue,
                  title: 'Clear Image Cache',
                  subtitle: 'Free up space used by profile photos and media',
                  onTap: _isClearing ? null : _clearImageCache,
                ),
              ),
              const SizedBox(height: 16),
              
              _buildSectionHeader('DATABASE'),
              GlassContainer(
                child: _buildStorageItem(
                  icon: LucideIcons.database,
                  iconColor: Colors.green,
                  title: 'Clear Local Database',
                  subtitle: 'Re-sync communities and messages from server',
                  onTap: _isClearing ? null : _clearDatabase,
                ),
              ),
              const SizedBox(height: 32),
              
              _buildSectionHeader('TROUBLESHOOTING'),
              GlassContainer(
                child: _buildStorageItem(
                  icon: LucideIcons.refreshCcw,
                  iconColor: Colors.red,
                  title: 'Full Application Reset',
                  titleColor: Colors.red,
                  subtitle: 'Clear all data and log out',
                  onTap: _isClearing ? null : _fullReset,
                ),
              ),
            ],
          ),
          if (_isClearing)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildStorageItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    Color? titleColor,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                      color: titleColor,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
