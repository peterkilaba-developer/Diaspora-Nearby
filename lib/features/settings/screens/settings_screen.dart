import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/core/utils/pwa_utils.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/more/widgets/account_section.dart';
import 'package:diaspora_nearby/features/more/screens/feedback_screen.dart';
import 'package:diaspora_nearby/features/shared/screens/placeholder_screen.dart';
import 'package:diaspora_nearby/features/sharing/services/sharing_service.dart';
import 'package:diaspora_nearby/features/dsp/services/exploration_registry.dart';
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profileAsync = ref.watch(userProfileProvider);
    final profile = profileAsync.value;
    final currentUserId =
        ref.watch(authRepositoryProvider).currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          top: 16,
          left: AppTheme.pageHorizontalPadding,
          right: AppTheme.pageHorizontalPadding,
          bottom: 16 + MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Web App (PWA)
            if (kIsWeb) ...[
              _buildSectionHeader(
                context,
                'WEB APP',
                icon: LucideIcons.monitor,
              ),
              _buildSectionContainer(
                context,
                child: _buildMenuItem(
                  context,
                  ref: ref,
                  icon: LucideIcons.download,
                  iconColor: theme.colorScheme.primary,
                  title: 'Install as App',
                  subtitle: 'Add Diaspora to your home screen',
                  onTap: () async {
                    final result = await PwaUtils.promptInstall();
                    if (!result) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Installation not supported or already installed.',
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Quick Actions
            _buildSectionHeader(
              context,
              'QUICK ACTIONS',
              icon: LucideIcons.zap,
            ),
            _buildSectionContainer(
              context,
              child: Column(
                children: [
                  _buildMenuItem(
                    context,
                    ref: ref,
                    icon: LucideIcons.share2,
                    iconColor: const Color(0xFF25D366),
                    title: 'Invite family and friends',
                    subtitle: 'Share the app with others',
                    explorationAction: ExplorationAction.profileInvite,
                    onTap: () {
                      if (currentUserId.isNotEmpty) {
                        ref
                            .read(pointsServiceProvider)
                            .trackExternalShare(currentUserId, 'app_invite');
                      }
                      SharingService.instance.shareApp();
                    },
                  ),
                  _buildMenuItem(
                    context,
                    ref: ref,
                    icon: LucideIcons.messageSquare,
                    iconColor: Colors.indigo,
                    title: 'Send Feedback',
                    subtitle: 'Help us improve the app',
                    explorationAction: ExplorationAction.profileFeedback,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const FeedbackScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Support
            _buildSectionHeader(
              context,
              'SUPPORT',
              icon: LucideIcons.lifeBuoy,
            ),
            _buildSectionContainer(
              context,
              child: Column(
                children: [
                  _buildMenuItem(
                    context,
                    ref: ref,
                    icon: LucideIcons.star,
                    iconColor: Colors.orange,
                    title: 'Rate App',
                    subtitle: 'Share your experience',
                    explorationAction: ExplorationAction.profileRateApp,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PlaceholderScreen(
                            title: 'Rate App',
                            icon: LucideIcons.star,
                            message:
                                'Enjoying the app? Please rate us on the app store!\n\n(Coming Soon)',
                          ),
                        ),
                      );
                    },
                  ),
                  _buildMenuItem(
                    context,
                    ref: ref,
                    icon: LucideIcons.helpCircle,
                    iconColor: Colors.cyan,
                    title: 'Help Center',
                    subtitle: 'Get answers',
                    explorationAction: ExplorationAction.profileHelpCenter,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PlaceholderScreen(
                            title: 'Help Center',
                            icon: LucideIcons.helpCircle,
                            message:
                                'Find answers to common questions.\n\n(Coming Soon)',
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Account Settings
            _buildSectionHeader(
              context,
              'ACCOUNT SETTINGS',
              icon: LucideIcons.settings,
            ),
            AccountSection(userProfile: profile),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title, {
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: theme.colorScheme.onSurface.withOpacity(0.5),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
              color: theme.colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionContainer(
    BuildContext context, {
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(AppTheme.standardBorderRadius),
      ),
      child: child,
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required WidgetRef ref,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    String? explorationAction,
  }) {
    final theme = Theme.of(context);

    final effectiveOnTap = explorationAction != null
        ? trackExplorationCallback(ref, context, explorationAction, onTap)
        : onTap;

    return InkWell(
      onTap: effectiveOnTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.sectionHorizontalPadding,
          vertical: 16,
        ),
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
                      color: theme.textTheme.bodyMedium?.color,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.textTheme.bodySmall?.color
                            ?.withOpacity(0.7),
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: theme.iconTheme.color?.withOpacity(0.3),
            ),
          ],
        ),
      ),
    );
  }
}
