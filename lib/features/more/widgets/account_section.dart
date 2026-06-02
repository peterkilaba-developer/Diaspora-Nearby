import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/notifications/services/push_notification_service.dart';
import 'package:diaspora_nearby/features/shared/ui/glass_container.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/core/providers/theme_provider.dart';
import 'package:diaspora_nearby/features/dsp/services/exploration_registry.dart';
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';

import 'package:diaspora_nearby/features/settings/screens/privacy_settings_screen.dart'; // [NEW]

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
              // 1.5 Location
              if (!kIsWeb)
                _buildMenuItem(
                  context,
                  icon: LucideIcons.mapPin,
                  iconColor: Colors.teal,
                  title: 'Location Settings',
                  subtitle: 'Manage background location access',
                  onTap: () {
                    _showLocationDialog(context, ref);
                  },
                  ref: ref,
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

  void _showLocationDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            bool isLoading = true;
            bool isGranted = false;

            // Fetch status once
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (isLoading) {
                final status = await Permission.locationAlways.status;
                if (context.mounted) {
                  setDialogState(() {
                    isGranted = status.isGranted || status.isLimited;
                    isLoading = false;
                  });
                }
              }
            });

            return AlertDialog(
              title: const Row(
                children: [
                  Icon(LucideIcons.mapPin),
                  SizedBox(width: 8),
                  Text('Location Settings'),
                ],
              ),
              content: isLoading
                  ? const SizedBox(
                      height: 50,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Background location enables features like nearby searches even when the app is minimized.',
                          style: TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 16),
                        SwitchListTile(
                          title: const Text('Always Allow'),
                          subtitle: Text(isGranted ? 'Enabled' : 'Disabled'),
                          value: isGranted,
                          activeThumbColor: Colors.teal,
                          onChanged: (val) async {
                            if (val) {
                              final fgStatus = await Permission.location.status;
                              if (!fgStatus.isGranted && !fgStatus.isLimited) {
                                await Permission.location.request();
                              }
                              final status = await Permission.locationAlways
                                  .request();
                              if (status.isPermanentlyDenied ||
                                  status.isDenied) {
                                await openAppSettings();
                              } else {
                                if (context.mounted) {
                                  setDialogState(() {
                                    isGranted =
                                        status.isGranted || status.isLimited;
                                  });
                                }
                              }
                            } else {
                              await openAppSettings();
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'To disable, use system settings.',
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
}
