import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/notifications/services/push_notification_service.dart';
import 'package:diaspora_nearby/features/shared/ui/glass_container.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/core/localization/app_localizations.dart';
import 'package:diaspora_nearby/core/providers/locale_provider.dart';
import 'package:diaspora_nearby/core/providers/theme_provider.dart';
import 'package:diaspora_nearby/features/dsp/services/exploration_registry.dart';
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart';
import 'package:diaspora_nearby/core/services/pwa_install_service.dart';
import 'package:go_router/go_router.dart';
import 'package:diaspora_nearby/features/settings/screens/privacy_settings_screen.dart';
import 'package:diaspora_nearby/features/settings/widgets/language_selector_sheet.dart';

class AccountSection extends ConsumerWidget {
  final ProfileData? userProfile;
  const AccountSection({super.key, this.userProfile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currentLang = ref.watch(currentWorldLanguageProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // --- Your Account ---
        GlassContainer(
          child: Column(
            children: [
              // 0. App Language (All Main Official Languages of Every Country)
              _buildMenuItem(
                context,
                icon: LucideIcons.languages,
                iconColor: AppTheme.accent,
                title: AppLocalizations.tr(ref, 'App Language'),
                subtitle:
                    '${currentLang.primaryFlag}  ${currentLang.displayLabel}',
                onTap: () => showLanguageSelectorSheet(context, ref),
                ref: ref,
              ),
              // 1. Notifications
              _buildMenuItem(
                context,
                icon: LucideIcons.bell,
                iconColor: Colors.purple,
                title: AppLocalizations.tr(ref, 'Push Notifications'),
                subtitle: AppLocalizations.tr(
                  ref,
                  'Manage notification preferences',
                ),
                onTap: () {
                  final effectiveProfile =
                      ref.read(userProfileProvider).value ?? userProfile;
                  if (effectiveProfile != null &&
                      effectiveProfile.uid != null) {
                    _showNotificationDialog(context, ref, effectiveProfile);
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
                title: AppLocalizations.tr(ref, 'Privacy & Safety'),
                subtitle: AppLocalizations.tr(
                  ref,
                  'Control your privacy settings',
                ),
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
                title: AppLocalizations.tr(ref, 'Trust & Verification'),
                subtitle: AppLocalizations.tr(
                  ref,
                  'View your Community Trust breakdown',
                ),
                onTap: () {
                  context.push('/profile');
                },
                actionId: ExplorationAction.moreScreenTrust,
                ref: ref,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // --- App Info & Theme ---
        _buildSectionHeader(AppLocalizations.tr(ref, 'APP INFO')),
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
                  Text(
                    AppLocalizations.tr(ref, 'Theme Mode'),
                    style: const TextStyle(fontWeight: FontWeight.w500),
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
        // --- Logout (moved below Theme Mode) ---
        GlassContainer(
          child: _buildMenuItem(
            context,
            icon: LucideIcons.logOut,
            iconColor: theme.disabledColor,
            title: AppLocalizations.tr(ref, 'Log Out'),
            subtitle: AppLocalizations.tr(ref, 'Sign out of your account'),
            onTap: () => _showLogoutConfirm(context, ref),
            ref: ref,
          ),
        ),
        const SizedBox(height: 16),
        // --- Delete Account ---
        GlassContainer(
          child: _buildMenuItem(
            context,
            icon: LucideIcons.trash2,
            iconColor: const Color(0xFFEF4444),
            title: AppLocalizations.tr(ref, 'Delete My Account'),
            titleColor: const Color(0xFFEF4444),
            subtitle: AppLocalizations.tr(
              ref,
              'Permanently delete your account and data',
            ),
            onTap: () => _showDeleteAccountConfirm(context, ref),
            ref: ref,
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
        final latestProfile =
            ref.read(userProfileProvider).value ?? userProfile;
        bool isEnabled = latestProfile.notificationsEnabled ?? false;
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 24,
                ),
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
                      onChanged: (val) {
                        setDialogState(() => isEnabled = val);
                        final uid = userProfile.uid;
                        if (uid != null) {
                          final current =
                              ref.read(userProfileProvider).value ??
                              ref
                                  .read(profileRepositoryProvider)
                                  .getCachedProfile(uid) ??
                              userProfile;
                          final updated = current.copyWith(
                            notificationsEnabled: val,
                          );
                          ref
                              .read(userProfileProvider.notifier)
                              .updateProfile(updated);
                          ref
                              .read(profileRepositoryProvider)
                              .cacheProfile(uid, updated);

                          if (val) {
                            unawaited(
                              ref
                                  .read(pushNotificationServiceProvider)
                                  .registerForUser(uid),
                            );
                          } else {
                            unawaited(
                              ref
                                  .read(pushNotificationServiceProvider)
                                  .disableNotifications(uid),
                            );
                          }
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
          ),
        );
      },
    );
  }

  void _showDeleteAccountConfirm(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
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
                  builder: (_) => BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
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
      ),
    );
  }

  void _showLogoutConfirm(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
          title: const Text('Log Out'),
          content: const Text('Are you sure you want to log out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await ref.read(authRepositoryProvider).signOut();
              },
              child: const Text('Log Out', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }
}
