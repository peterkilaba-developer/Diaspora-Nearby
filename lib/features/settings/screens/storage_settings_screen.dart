import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/shared/ui/glass_container.dart';
import 'package:diaspora_nearby/features/shared/utils/app_snackbar.dart';
import 'package:diaspora_nearby/features/shared/utils/confirm_dialog.dart';
import 'package:diaspora_nearby/features/shared/utils/loading_mixin.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/core/services/database_service.dart';
import 'package:diaspora_nearby/features/auth/services/session_service.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class StorageSettingsScreen extends ConsumerStatefulWidget {
  const StorageSettingsScreen({super.key});

  @override
  ConsumerState<StorageSettingsScreen> createState() =>
      _StorageSettingsScreenState();
}

class _StorageSettingsScreenState extends ConsumerState<StorageSettingsScreen>
    with ConsumerLoadingMixin {
  Future<void> _clearImageCache() => withLoading(
    () async {
      await DefaultCacheManager().emptyCache();
      if (mounted) AppSnackbar.success(context, 'Image cache cleared');
    },
    onError: (e, _) {
      if (mounted) AppSnackbar.error(context, 'Error clearing cache: $e');
    },
  );

  Future<void> _clearDatabase() async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Clear Local Database?',
      message:
          'This will remove all cached messages and communities from this device. '
          'They will be re-synced from the server when you open them again.',
      confirmText: 'Clear',
      isDestructive: true,
    );
    if (!confirmed) return;

    await withLoading(
      () async {
        await DatabaseService().clean();
        if (mounted) AppSnackbar.success(context, 'Local database cleared');
      },
      onError: (e, _) {
        if (mounted) AppSnackbar.error(context, 'Error clearing database: $e');
      },
    );
  }

  Future<void> _fullReset() async {
    final confirmed = await ConfirmDialog.destructive(
      context,
      title: 'Full App Reset?',
      message:
          'This will clear ALL local data, settings, and log you out. '
          'The app will return to its initial state.',
      confirmText: 'RESET EVERYTHING',
    );
    if (!confirmed) return;

    await withLoading(
      () async {
        await DatabaseService().clean();
        await ref.read(sessionServiceProvider).clearAll();
        await DefaultCacheManager().emptyCache();
        await ref.read(authRepositoryProvider).signOut();

        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      },
      onError: (e, _) {
        if (mounted) AppSnackbar.error(context, 'Error during reset: $e');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Storage & Cache')),
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
                  onTap: isLoading ? null : _clearImageCache,
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
                  onTap: isLoading ? null : _clearDatabase,
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
                  onTap: isLoading ? null : _fullReset,
                ),
              ),
            ],
          ),
          if (isLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.3),
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
                color: iconColor.withValues(alpha: 0.1),
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
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
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
