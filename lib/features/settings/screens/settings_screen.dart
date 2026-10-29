import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/core/localization/app_localizations.dart';
import 'package:diaspora_nearby/core/utils/pwa_utils.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/more/widgets/account_section.dart';
import 'package:diaspora_nearby/features/more/screens/feedback_screen.dart';
import 'package:diaspora_nearby/features/shared/screens/placeholder_screen.dart';
import 'package:diaspora_nearby/features/sharing/services/sharing_service.dart';
import 'package:diaspora_nearby/features/dsp/services/exploration_registry.dart';
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    _prewarmReferralCode();
  }

  void _prewarmReferralCode() {
    final currentUserId = ref.read(authRepositoryProvider).currentUser?.uid;
    if (currentUserId == null || currentUserId.isEmpty) return;

    final pointsRepo = ref.read(pointsRepositoryProvider);
    if (pointsRepo.getCachedReferralCode(currentUserId) != null) return;

    unawaited(
      () async {
        try {
          var code = await pointsRepo.getReferralCode(currentUserId);
          if (code == null) {
            final profileRepo = ref.read(profileRepositoryProvider);
            final userProfile =
                profileRepo.getCachedProfile(currentUserId) ??
                await profileRepo.getUserProfile(currentUserId);
            if (userProfile != null) {
              code = await pointsRepo.generateReferralCode(
                currentUserId,
                userProfile.firstName,
                userProfile.homeCountryCode ?? 'US',
              );
            }
          }
          if (code != null) {
            pointsRepo.cacheReferralCode(currentUserId, code);
          }
        } catch (e) {
          debugPrint('Error prewarming referral code: $e');
        }
      }(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUserId =
        ref.watch(authRepositoryProvider).currentUser?.uid ?? '';
    final profileAsync = ref.watch(userProfileProvider);
    final profile =
        profileAsync.value ??
        (currentUserId.isNotEmpty
            ? ref.read(profileRepositoryProvider).getCachedProfile(
                currentUserId,
              )
            : null);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: Text(AppLocalizations.tr(ref, 'Settings'))),
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
                child: Column(
                  children: [
                    _buildMenuItem(
                      context,
                      ref: ref,
                      icon: LucideIcons.download,
                      iconColor: theme.colorScheme.primary,
                      title: 'Install as App',
                      subtitle: 'Add Diaspora to your home screen',
                      onTap: () async {
                        final result = await PwaUtils.promptInstall();
                        if (!result && context.mounted) {
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
                    _buildMenuItem(
                      context,
                      ref: ref,
                      icon: LucideIcons.smartphone,
                      iconColor: Colors.deepPurple,
                      title: 'Become a Mobile App Tester',
                      subtitle: 'Get early access to our Android & iOS apps',
                      onTap: () => _showTesterSignupDialog(context, ref),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Quick Actions
            _buildSectionHeader(
              context,
              AppLocalizations.tr(ref, 'QUICK ACTIONS'),
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
                    title: AppLocalizations.tr(
                      ref,
                      'Invite family and friends',
                    ),
                    subtitle: AppLocalizations.tr(
                      ref,
                      'Share the app with others',
                    ),
                    explorationAction: ExplorationAction.profileInvite,
                    onTap: () {
                      if (currentUserId.isNotEmpty) {
                        unawaited(
                          ref
                              .read(pointsServiceProvider)
                              .trackExternalShare(currentUserId, 'app_invite'),
                        );
                        final pointsRepo = ref.read(pointsRepositoryProvider);
                        final cachedCode = pointsRepo.getCachedReferralCode(
                          currentUserId,
                        );
                        // Open share sheet immediately in 0ms using cached code
                        SharingService.instance.shareApp(
                          referralCode: cachedCode,
                        );
                        if (cachedCode == null) {
                          _prewarmReferralCode();
                        }
                      } else {
                        SharingService.instance.shareApp();
                      }
                    },
                  ),
                  _buildMenuItem(
                    context,
                    ref: ref,
                    icon: LucideIcons.messageSquare,
                    iconColor: Colors.indigo,
                    title: AppLocalizations.tr(ref, 'Send Feedback'),
                    subtitle: AppLocalizations.tr(
                      ref,
                      'Help us improve the app',
                    ),
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
              AppLocalizations.tr(ref, 'SUPPORT'),
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
                    title: AppLocalizations.tr(ref, 'Rate App'),
                    subtitle: AppLocalizations.tr(ref, 'Share your experience'),
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
                    title: AppLocalizations.tr(ref, 'Help Center'),
                    subtitle: AppLocalizations.tr(ref, 'Get answers'),
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
              AppLocalizations.tr(ref, 'ACCOUNT SETTINGS'),
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
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionContainer(BuildContext context, {required Widget child}) {
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
                      color: theme.textTheme.bodyMedium?.color,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.textTheme.bodySmall?.color?.withValues(
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

  void _showTesterSignupDialog(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final emailController = TextEditingController();
    String selectedPlatform = 'both';
    final currentUserId =
        ref.read(authRepositoryProvider).currentUser?.uid ?? '';
    ref.read(userProfileProvider);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.elevationColor(context, 3),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.standardBorderRadius),
        ),
      ),
      builder: (ctx) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: StatefulBuilder(
            builder: (ctx, setState) {
              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom,
                  left: 20,
                  right: 20,
                  top: 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle bar
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: theme.hintColor.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Header with icon
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.deepPurple.shade400,
                                Colors.deepPurple.shade700,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            LucideIcons.smartphone,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Become a Mobile Tester',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: theme.textTheme.bodyLarge?.color,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Get early access before public launch',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: theme.hintColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Info note
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            LucideIcons.info,
                            size: 16,
                            color: Colors.deepPurple.shade300,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'We need your email to send TestFlight (iOS) or Google Play (Android) invites. Use the email linked to your Apple ID or Google account.',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.hintColor,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Email field
                    Text(
                      'Email Address',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: theme.textTheme.bodyMedium?.color,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        hintText: 'your@email.com',
                        prefixIcon: const Icon(LucideIcons.mail, size: 18),
                        filled: true,
                        fillColor: AppTheme.elevationColor(ctx, 2),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Platform selection
                    Text(
                      'Platform',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: theme.textTheme.bodyMedium?.color,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _platformChip(
                          ctx,
                          label: 'Android',
                          icon: LucideIcons.smartphone,
                          selected:
                              selectedPlatform == 'android' ||
                              selectedPlatform == 'both',
                          onTap: () => setState(() {
                            selectedPlatform = selectedPlatform == 'android'
                                ? 'both'
                                : 'android';
                          }),
                        ),
                        const SizedBox(width: 8),
                        _platformChip(
                          ctx,
                          label: 'iOS',
                          icon: LucideIcons.tablet,
                          selected:
                              selectedPlatform == 'ios' ||
                              selectedPlatform == 'both',
                          onTap: () => setState(() {
                            selectedPlatform = selectedPlatform == 'ios'
                                ? 'both'
                                : 'ios';
                          }),
                        ),
                        const SizedBox(width: 8),
                        _platformChip(
                          ctx,
                          label: 'Both',
                          icon: LucideIcons.layers,
                          selected: selectedPlatform == 'both',
                          onTap: () => setState(() {
                            selectedPlatform = 'both';
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Submit button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () {
                          final email = emailController.text.trim();
                          if (email.isEmpty || !email.contains('@')) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('Please enter a valid email'),
                              ),
                            );
                            return;
                          }

                          // Pop modal, show SnackBar, and launch TestFlight URL immediately in 0ms
                          Navigator.of(ctx).pop();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const Icon(
                                      LucideIcons.checkCircle,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'You\'re signed up! We\'ll send an invite to $email',
                                      ),
                                    ),
                                  ],
                                ),
                                backgroundColor: AppTheme.accent,
                              ),
                            );
                          }

                          if (selectedPlatform == 'ios' ||
                              selectedPlatform == 'both') {
                            unawaited(
                              launchUrl(
                                Uri.parse(
                                  'https://testflight.apple.com/join/vB3XzPKg',
                                ),
                                mode: LaunchMode.externalApplication,
                              ).catchError((_) => false),
                            );
                          }

                          unawaited(
                            FirebaseFirestore.instance
                                .collection('app_testers')
                                .doc(currentUserId)
                                .set({
                                  'email': email,
                                  'platform': selectedPlatform,
                                  'userId': currentUserId,
                                  'signedUpAt': FieldValue.serverTimestamp(),
                                  'status': 'pending',
                                })
                                .catchError((Object e) {
                                  debugPrint('Error saving app_testers: $e');
                                }),
                          );
                        },
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(LucideIcons.send, size: 16),
                            SizedBox(width: 8),
                            Text(
                              'Sign Up as Tester',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 16 + MediaQuery.of(ctx).padding.bottom),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _platformChip(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? Colors.deepPurple.withValues(alpha: 0.12)
                : AppTheme.elevationColor(context, 2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? Colors.deepPurple : theme.hintColor,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected
                      ? Colors.deepPurple
                      : theme.textTheme.bodyMedium?.color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
