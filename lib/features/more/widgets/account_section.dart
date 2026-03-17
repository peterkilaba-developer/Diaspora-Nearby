import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/shared/screens/placeholder_screen.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/notifications/services/push_notification_service.dart';
import 'package:diaspora_nearby/features/shared/ui/glass_container.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/core/providers/theme_provider.dart';
import 'package:diaspora_nearby/features/dsp/services/exploration_registry.dart';
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart';
import 'package:diaspora_nearby/core/services/pwa_install_service.dart';
import 'package:diaspora_nearby/core/services/database_service.dart';
import 'package:go_router/go_router.dart';
import 'package:diaspora_nearby/features/settings/screens/privacy_settings_screen.dart'; // [NEW]
import 'package:diaspora_nearby/features/settings/screens/storage_settings_screen.dart'; // [NEW]
import 'package:diaspora_nearby/features/community/services/community_service.dart';
import 'package:cloud_functions/cloud_functions.dart';

class AccountSection extends ConsumerWidget {
  final ProfileData? userProfile;
  const AccountSection({super.key, this.userProfile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // --- Your Account ---
        GlassContainer(
          child: Column(
            children: [
              // 1. Notifications
              _buildMenuItem(
                context,
                icon: LucideIcons.bell,
                iconColor: Colors.purple,
                title: 'Push Notifications',
                subtitle: 'Manage notification preferences',
                onTap: () {
                  if (userProfile != null && userProfile!.uid != null) {
                    _showNotificationDialog(context, ref, userProfile!);
                  }
                },
                actionId: ExplorationAction.moreScreenNotifications,
                ref: ref, // [FIX]
              ),
              // 2. Privacy
              _buildMenuItem(
                context,
                icon: LucideIcons.shield,
                iconColor: Colors.blue.shade600,
                title: 'Privacy & Safety',
                subtitle: 'Control your privacy settings',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PrivacySettingsScreen(),
                    ),
                  );
                },
                actionId: ExplorationAction.moreScreenPrivacy,
                ref: ref, // [FIX]
              ),
              // 2.1 Trust
              _buildMenuItem(
                context,
                icon: LucideIcons.shieldCheck,
                iconColor: Colors.green,
                title: 'Trust & Reputation',
                subtitle: 'View your Community Trust breakdown',
                onTap: () {
                  context.push('/profile');
                },
                actionId: ExplorationAction.moreScreenTrust,
                ref: ref,
              ),
              // 3. Settings
              _buildMenuItem(
                context,
                icon: LucideIcons.settings,
                iconColor: Colors.grey,
                title: 'Settings',
                subtitle: 'App preferences and notifications',
                onTap: () {
                  // Tracking placeholder
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PlaceholderScreen(
                        title: 'Settings',
                        icon: LucideIcons.settings,
                        message:
                            'General application settings.\n\n(Coming Soon)',
                      ),
                    ),
                  );
                },
                actionId: ExplorationAction.moreScreenSettings,
                ref: ref, // [FIX]
              ),
              // 4. Storage & Cache
              _buildMenuItem(
                context,
                icon: LucideIcons.database,
                iconColor: Colors.orange,
                title: 'Storage & Cache',
                subtitle: 'Manage local data and media cache',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const StorageSettingsScreen(),
                    ),
                  );
                },
                ref: ref,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // --- Logout ---
        GlassContainer(
          child: _buildMenuItem(
            context,
            icon: LucideIcons.logOut,
            iconColor: theme.disabledColor,
            title: 'Log Out',
            subtitle: 'Sign out of your account',
            onTap: () => _showLogoutConfirm(context, ref),
            ref: ref, // [FIX]
          ),
        ),
        const SizedBox(height: 16),
        // --- App Info & Theme ---
        _buildSectionHeader('APP INFO'),
        // [NEW] PWA Install Button
        Consumer(
          builder: (context, ref, _) {
            final canInstall = ref.watch(pwaInstallServiceProvider);
            if (!canInstall) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: GlassContainer(
                child: _buildMenuItem(
                  context,
                  icon: LucideIcons.download,
                  iconColor: theme.colorScheme.primary,
                  title: 'Install App',
                  subtitle: 'Add to Home Screen for better experience',
                  onTap: () async {
                    await ref
                        .read(pwaInstallServiceProvider.notifier)
                        .promptInstall();
                  },
                  ref: ref,
                ),
              ),
            );
          },
        ),
        GlassContainer(
          padding: const EdgeInsets.all(
            AppTheme.sectionHorizontalPadding,
          ), // 8px padding
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Theme Mode',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        _buildThemeToggle(
                          context,
                          ref,
                          LucideIcons.sun,
                          ThemeMode.light,
                        ),
                        _buildThemeToggle(
                          context,
                          ref,
                          LucideIcons.moon,
                          ThemeMode.dark,
                        ),
                        _buildThemeToggle(
                          context,
                          ref,
                          LucideIcons.monitor,
                          ThemeMode.system,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Center(
                child: Column(
                  children: [
                    Image.asset(
                      'assets/icons/logo-transparent-48.png',
                      width: 48,
                      height: 48,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Diaspora Nearby',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Text(
                      'Version 1.0.0',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // --- Delete Account ---
        GlassContainer(
          child: _buildMenuItem(
            context,
            icon: LucideIcons.trash2,
            iconColor: const Color(0xFFEF4444),
            title: 'Delete My Account',
            titleColor: const Color(0xFFEF4444),
            subtitle: 'Permanently delete your account and data',
            onTap: () => _showDeleteAccountConfirm(context, ref),
            ref: ref, // [FIX]
          ),
        ),
        const SizedBox(height: 16),
        // --- Admin Tools (visible in debug mode OR when isAdmin) ---
        if (kDebugMode || (userProfile?.isAdmin ?? false)) ...[
          _buildSectionHeader('ADMIN TOOLS'),
          // Bootstrap: Become Admin (only in debug mode when not yet admin)
          if (kDebugMode && !(userProfile?.isAdmin ?? false))
            GlassContainer(
              child: _buildMenuItem(
                context,
                icon: LucideIcons.shieldAlert,
                iconColor: Colors.amber,
                title: 'Become Admin',
                subtitle: 'Bootstrap: Set admin claim on your account',
                onTap: () => _bootstrapAdmin(context, ref),
                ref: ref,
              ),
            ),
          if (kDebugMode && !(userProfile?.isAdmin ?? false))
            const SizedBox(height: 8),
          GlassContainer(
            child: _buildMenuItem(
              context,
              icon: LucideIcons.database,
              iconColor: Colors.red,
              title: 'Reset Database',
              subtitle: 'ADMIN ONLY: Wipe collections and data',
              onTap: () => _showAdminResetDialog(context, ref),
              ref: ref,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _buildThemeToggle(
    BuildContext context,
    WidgetRef ref,
    IconData icon,
    ThemeMode mode,
  ) {
    final currentTheme = ref.watch(themeProvider);
    final isActive = currentTheme == mode;

    return GestureDetector(
      onTap: () {
        ref.read(themeProvider.notifier).setTheme(mode);
      },
      child: Container(
        width: 32,
        height: 32,
        decoration: isActive
            ? BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 2,
                  ),
                ],
              )
            : null,
        child: Icon(
          icon,
          size: 14,
          color: isActive
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).disabledColor,
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppTheme.pageHorizontalPadding,
        bottom: 8,
      ),
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

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? titleColor,
    Color? subtitleColor,
    Widget? iconWidget,
    String? actionId,
    required WidgetRef ref, // [FIX]
  }) {
    final theme = Theme.of(context);

    // Wrap onTap if actionId is provided
    final effectiveOnTap = actionId != null
        ? trackExplorationCallback(ref, context, actionId, onTap)
        : onTap;

    return InkWell(
      onTap: effectiveOnTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.sectionHorizontalPadding,
          vertical: 16,
        ), // 8px horizontal
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: iconWidget ?? Icon(icon, color: iconColor, size: 20),
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
                      color: titleColor ?? theme.textTheme.bodyMedium?.color,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color:
                            subtitleColor ??
                            theme.textTheme.bodySmall?.color?.withValues(
                              alpha: 0.7,
                            ),
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: theme.iconTheme.color?.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }

  void _showNotificationDialog(
    BuildContext context,
    WidgetRef ref,
    ProfileData userProfile,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        bool isEnabled = userProfile.notificationsEnabled ?? false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(LucideIcons.bell),
                  SizedBox(width: 8),
                  Text('Notifications'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: const Text('Enable Notifications'),
                    subtitle: Text(
                      isEnabled
                          ? 'You will receive updates'
                          : 'Notifications are disabled',
                    ),
                    value: isEnabled,
                    activeThumbColor: Colors.purple,
                    onChanged: (val) async {
                      setDialogState(() => isEnabled = val);
                      if (val) {
                        await ref
                            .read(pushNotificationServiceProvider)
                            .registerForUser(userProfile.uid!);
                      } else {
                        await ref
                            .read(pushNotificationServiceProvider)
                            .disableNotifications(userProfile.uid!);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Customize individual alerts in system settings.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDeleteAccountConfirm(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(LucideIcons.alertTriangle, color: Colors.red),
            SizedBox(width: 8),
            Text('Delete Account?', style: TextStyle(color: Colors.red)),
          ],
        ),
        content: const Text(
          'Are you sure you want to permanently delete your account?\n\n'
          '• Your profile will be wiped\n'
          '• Your points will be lost\n'
          '• You will be removed from all communities\n'
          '• Communities where you are the ONLY member will be deleted\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(context);
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) =>
                    const Center(child: CircularProgressIndicator()),
              );
              try {
                await ref.read(authRepositoryProvider).deleteAccount();
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error deleting account: $e')),
                  );
                }
              }
            },
            child: const Text('DELETE PERMANENTLY'),
          ),
        ],
      ),
    );
  }

  void _showLogoutConfirm(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(authRepositoryProvider).signOut();
            },
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }
  void _bootstrapAdmin(BuildContext context, WidgetRef ref) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) =>
            const Center(child: CircularProgressIndicator()),
      );

      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable('setAdminClaim');
      await callable.call<Map<String, dynamic>>({});

      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Admin claim set! Re-open this screen.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showAdminResetDialog(BuildContext context, WidgetRef ref) async {
    final Map<String, bool> targets = {
      'Users': true,
      'Auth Accounts': true,
      'Communities': true,
      'Organizations': true,
      'Events': true,
      'Radio Health': true,
      'Chats & Messages': true,
      'Corridors': true,
      'Hosting (Requests & Sessions)': true,
      'Marketplace Listings': true,
      'Peer Listings': true,
      'Trust Data': true,
      'Storage (Photos)': true,
      'Points & Referrals': true,
      'Feedback History': true,
      'Proximity Cooldown': true,
      'Empty Communities': false,
      'Local Cache': true,
    };

    final selected = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Admin: Reset Database Options'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: targets.keys.map((key) {
                    return CheckboxListTile(
                      title: Text(key),
                      value: targets[key],
                      onChanged: (val) {
                        setState(() => targets[key] = val ?? false);
                      },
                      activeColor: Colors.red,
                    );
                  }).toList(),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  final List<String> result = [];
                  if (targets['Users']!) {
                    result.add('users');
                  }
                  if (targets['Auth Accounts']!) {
                    result.add('auth');
                  }
                  if (targets['Communities']!) {
                    result.add('communities');
                  }
                  if (targets['Organizations']!) {
                    result.add('organizations');
                  }
                  if (targets['Events']!) {
                    result.add('events');
                  }
                  if (targets['Radio Health']!) {
                    result.add('radio');
                  }
                  if (targets['Chats & Messages']!) {
                    result.add('chats');
                  }
                  if (targets['Corridors']!) {
                    result.add('corridors');
                  }
                  if (targets['Hosting (Requests & Sessions)']!) {
                    result.add('hosting');
                  }
                  if (targets['Marketplace Listings']!) {
                    result.add('marketplace');
                  }
                  if (targets['Peer Listings']!) {
                    result.add('peer_listings');
                  }
                  if (targets['Trust Data']!) {
                    result.add('trust');
                  }
                  if (targets['Storage (Photos)']!) {
                    result.add('storage');
                  }
                  if (targets['Points & Referrals']!) {
                    result.add('points');
                  }
                  if (targets['Feedback History']!) {
                    result.add('feedback');
                  }
                  if (targets['Proximity Cooldown']!) {
                    result.add('proximity');
                  }
                  if (targets['Empty Communities']!) {
                    result.add('empty_communities');
                  }
                  if (targets['Local Cache']!) {
                    result.add('local_cache');
                  }

                  Navigator.pop(context, result);
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('DELETE SELECTED'),
              ),
            ],
          );
        },
      ),
    );

    if (selected != null && selected.isNotEmpty) {
      try {
        if (!context.mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) =>
              const Center(child: CircularProgressIndicator()),
        );

        if (selected.contains('empty_communities')) {
          await ref.read(communityServiceProvider).pruneEmptyCommunities();
          selected.remove('empty_communities');
        }

        // Handle local cache clearing (client-side only)
        if (selected.contains('local_cache')) {
          try {
            await DatabaseService().clean();
            await FirebaseFirestore.instance.clearPersistence();
            debugPrint(
              '🧹 Admin Reset: Local caches cleared (Firestore persistence)',
            );
          } catch (e) {
            debugPrint('⚠️ Admin Reset: Error clearing local cache: $e');
          }
          selected.remove('local_cache');
        }

        if (selected.isNotEmpty) {
          final result = await ref
              .read(communityServiceProvider)
              .hardResetDatabase(
                resetTargets: selected,
                currentUserId: userProfile?.uid,
              );

          if (context.mounted) {
            Navigator.pop(context); // Pop loading

            final succeeded = result['success'] ?? [];
            final failed = result['failed'] ?? [];

            if (failed.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Reset Complete: ${succeeded.join(", ")}'),
                  backgroundColor: Colors.green,
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Partial Success. Failed: ${failed.join(", ")}',
                  ),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          }
        } else {
          if (context.mounted) Navigator.pop(context); // Pop loading
        }
      } catch (e) {
        if (context.mounted) {
          Navigator.pop(context); // Pop loading
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }
}
