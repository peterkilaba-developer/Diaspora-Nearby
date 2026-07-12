import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/notifications/services/push_notification_service.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/dsp/services/exploration_registry.dart';
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart';
import 'package:diaspora_nearby/core/widgets/app_install_card.dart';

class EconomyHubScreen extends ConsumerStatefulWidget {
  const EconomyHubScreen({super.key});

  @override
  ConsumerState<EconomyHubScreen> createState() => _EconomyHubScreenState();
}

class _EconomyHubScreenState extends ConsumerState<EconomyHubScreen>
    with WidgetsBindingObserver {
  bool _locationAlwaysGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkLocationAlwaysStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check when user returns from system settings
    if (state == AppLifecycleState.resumed) {
      _checkLocationAlwaysStatus();
    }
  }

  Future<void> _checkLocationAlwaysStatus() async {
    if (kIsWeb) {
      if (mounted) setState(() => _locationAlwaysGranted = true);
      return;
    }
    try {
      final status = await Permission.locationAlways.status;
      if (mounted) {
        setState(() {
          _locationAlwaysGranted = status.isGranted || status.isLimited;
        });
      }
    } catch (e) {
      debugPrint('Error checking locationAlways: $e');
      // Treat as granted if we can't check, to avoid confusion
      if (mounted) setState(() => _locationAlwaysGranted = true);
    }
  }

  Future<void> _requestLocationAlways() async {
    if (kIsWeb) return;
    try {
      // Ensure foreground location is granted first
      final fgStatus = await Permission.location.status;
      if (!fgStatus.isGranted && !fgStatus.isLimited) {
        await Permission.location.request();
      }

      final status = await Permission.locationAlways.request();
      if (status.isPermanentlyDenied || status.isDenied) {
        // On most Android versions, locationAlways requires going to Settings
        await openAppSettings();
      }
      await _checkLocationAlwaysStatus();
    } catch (e) {
      debugPrint('Error requesting locationAlways: $e');
      await openAppSettings();
      await _checkLocationAlwaysStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileProvider);
    final isAdmin = profileAsync.value?.isAdmin == true;
    final homeCountry = profileAsync.value?.homeCountry;
    final profile = profileAsync.value;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(LucideIcons.globe, size: 22, color: AppTheme.accent),
            SizedBox(width: 8),
            Text(
              'Diaspora Ecosystem',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.radio, size: 22),
            onPressed: () => context.go('/radio'),
          ),
          const SizedBox(width: 4),
        ],
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: AppTheme.pageHorizontalPadding,
          right: AppTheme.pageHorizontalPadding,
          top: 8,
          bottom: MediaQuery.of(context).padding.bottom + 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- PWA INSTALL + TESTER SIGNUP (web only) ---
            if (kIsWeb) ...[const AppInstallCard(), const SizedBox(height: 16)],

            // ============================================
            // SECTION 1: SAFETY NET (Emergency Fund first)
            // ============================================
            _buildSectionHeader(context, 'SAFETY NET', LucideIcons.shieldAlert),
            _buildSectionContainer(
              context,
              child: Column(
                children: [
                  _buildRow(
                    context,
                    ref: ref,
                    icon: LucideIcons.shieldAlert,
                    iconColor: Colors.red.shade400,
                    title: 'Community Emergency Fund',
                    subtitle: 'Medical, Legal, Bereavement & Repatriation',
                    explorationAction: ExplorationAction.economyEmergencyFund,
                    onTap: () => context.push('/dsp/emergency-fund'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ============================================
            // SECTION 2: MY WALLET
            // ============================================
            _buildSectionHeader(context, 'MY WALLET', LucideIcons.wallet),
            _buildSectionContainer(
              context,
              child: Column(
                children: [
                  _buildRow(
                    context,
                    ref: ref,
                    icon: LucideIcons.coins,
                    iconColor: AppTheme.accent,
                    title: 'Diaspora Social Points (DSP)',
                    subtitle: 'Earn & convert to tokens',
                    explorationAction: ExplorationAction.walletView,
                    onTap: () => context.push('/dsp/points'),
                  ),
                  _buildRow(
                    context,
                    ref: ref,
                    icon: LucideIcons.coins,
                    iconColor: Colors.orange,
                    title: r'$DIASPORA Token',
                    subtitle: 'Hold, Invest, Spend, Swap or Trade',
                    explorationAction: ExplorationAction.economyCrypto,
                    onTap: () => context.push('/dsp/crypto'),
                    useLogoImage: true,
                  ),
                  // Remittances (Admin only)
                  if (isAdmin)
                    _buildRow(
                      context,
                      ref: ref,
                      icon: LucideIcons.send,
                      iconColor: AppTheme.accent,
                      title: 'International Remittances',
                      subtitle: 'Send money to ${homeCountry ?? 'home'}',
                      explorationAction: ExplorationAction.economyRemittances,
                      onTap: () => context.push('/dsp/remittances'),
                      isComingSoon: true,
                    ),
                  // DDI — Host Community Loans (Admin only)
                  if (isAdmin)
                    _buildRow(
                      context,
                      ref: ref,
                      icon: LucideIcons.landmark,
                      iconColor: AppTheme.accent,
                      title: 'DDI Loans',
                      subtitle:
                          'Host community business loans — funded by host treasury',
                      explorationAction: ExplorationAction.economyDfdi,
                      onTap: () => context.push('/dsp/dfdi'),
                      isComingSoon: true,
                    ),
                  // DFDI — Home Country Large Projects (Admin only)
                  if (isAdmin)
                    _buildRow(
                      context,
                      ref: ref,
                      icon: LucideIcons.trendingUp,
                      iconColor: AppTheme.accent,
                      title: 'DFDI Projects',
                      subtitle:
                          'Home country direct investments — \$1M+ from home treasury',
                      explorationAction: ExplorationAction.economyDfdi,
                      onTap: () => context.push('/dsp/dfdi'),
                      isComingSoon: true,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ============================================
            // SECTION 3: MARKETPLACE
            // ============================================
            _buildSectionHeader(
              context,
              'MARKETPLACE',
              LucideIcons.shoppingBag,
            ),
            _buildSectionContainer(
              context,
              child: Column(
                children: [
                  _buildRow(
                    context,
                    ref: ref,
                    icon: LucideIcons.package,
                    iconColor: Colors.teal,
                    title: 'Products',
                    subtitle: 'Buy from diaspora businesses',
                    onTap: () => context.push('/marketplace?type=product'),
                  ),
                  _buildRow(
                    context,
                    ref: ref,
                    icon: LucideIcons.wrench,
                    iconColor: Colors.deepPurple,
                    title: 'Services',
                    subtitle: 'Find diaspora services',
                    onTap: () => context.push('/marketplace?type=service'),
                  ),
                  _buildRow(
                    context,
                    ref: ref,
                    icon: LucideIcons.briefcase,
                    iconColor: Colors.orange.shade700,
                    title: 'Jobs',
                    subtitle: 'Find opportunities',
                    onTap: () => context.push('/marketplace?type=job'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ============================================
            // SECTION 4: REAL ESTATE
            // ============================================
            _buildSectionHeader(context, 'REAL ESTATE', LucideIcons.building),
            _buildSectionContainer(
              context,
              child: Column(
                children: [
                  _buildRow(
                    context,
                    ref: ref,
                    icon: LucideIcons.map,
                    iconColor: Colors.amber.shade700,
                    title: 'Land & Plots',
                    subtitle: 'Rent, Lease or Buy',
                    onTap: () => context.push('/dsp/real-estate/plot'),
                  ),
                  _buildRow(
                    context,
                    ref: ref,
                    icon: LucideIcons.sprout,
                    iconColor: Colors.green.shade600,
                    title: 'Farms',
                    subtitle: 'Rent, Lease or Buy',
                    onTap: () => context.push('/dsp/real-estate/farm'),
                  ),
                  _buildRow(
                    context,
                    ref: ref,
                    icon: LucideIcons.home,
                    iconColor: Colors.blue.shade600,
                    title: 'Houses',
                    subtitle: 'Rent, Lease or Buy',
                    onTap: () => context.push('/dsp/real-estate/house'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ============================================
            // SECTION 5: TRAVEL
            // ============================================
            _buildSectionHeader(context, 'TRAVEL', LucideIcons.plane),
            _buildSectionContainer(
              context,
              child: Column(
                children: [
                  _buildRow(
                    context,
                    ref: ref,
                    icon: LucideIcons.plane,
                    iconColor: Colors.blue,
                    title: 'Flights',
                    subtitle: 'Book flights',
                    onTap: () => context.push('/dsp/travel/flights'),
                  ),
                  _buildRow(
                    context,
                    ref: ref,
                    icon: LucideIcons.hotel,
                    iconColor: Colors.deepPurple,
                    title: 'Hotels',
                    subtitle: 'Find hotels',
                    onTap: () => context.push('/dsp/travel/hotels'),
                  ),
                  _buildRow(
                    context,
                    ref: ref,
                    icon: LucideIcons.home,
                    iconColor: Colors.teal,
                    title: 'Stays',
                    subtitle: 'Short-term stays',
                    onTap: () => context.push('/dsp/travel/stays'),
                  ),
                  _buildRow(
                    context,
                    ref: ref,
                    icon: LucideIcons.car,
                    iconColor: Colors.orange,
                    title: 'Car Rental',
                    subtitle: 'Rent a car',
                    onTap: () => context.push('/dsp/travel/car-rental'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ============================================
            // SECTION 6: QUICK SETTINGS
            // ============================================
            _buildSectionHeader(context, 'QUICK SETTINGS', LucideIcons.zap),
            _buildSectionContainer(
              context,
              child: Column(
                children: [
                  // Notification toggle
                  _buildToggleRow(
                    context,
                    ref: ref,
                    icon: LucideIcons.bell,
                    iconColor: Colors.purple,
                    title: 'Push Notifications',
                    subtitle: 'Receive updates & alerts',
                    value: profile?.notificationsEnabled ?? false,
                    onChanged: (val) async {
                      final uid = profile?.uid;
                      if (uid == null) return;
                      if (val) {
                        await ref
                            .read(pushNotificationServiceProvider)
                            .registerForUser(uid);
                      } else {
                        await ref
                            .read(pushNotificationServiceProvider)
                            .disableNotifications(uid);
                      }
                    },
                  ),
                  // Location Always toggle (native only)
                  if (!kIsWeb)
                    _buildToggleRow(
                      context,
                      ref: ref,
                      icon: LucideIcons.mapPin,
                      iconColor: Colors.blue,
                      title: 'Location Always',
                      subtitle: 'Allow background location updates',
                      value: _locationAlwaysGranted,
                      onChanged: (val) async {
                        if (val) {
                          await _requestLocationAlways();
                        } else {
                          // Can't revoke programmatically — send to settings
                          await openAppSettings();
                          // Re-check after returning from settings
                          await _checkLocationAlwaysStatus();
                        }
                      },
                    ),
                  // My Profile
                  _buildRow(
                    context,
                    ref: ref,
                    icon: LucideIcons.user,
                    iconColor: AppTheme.accent,
                    title: 'My Profile',
                    subtitle: 'View & edit your profile',
                    explorationAction: ExplorationAction.profileEdit,
                    onTap: () => context.push('/profile'),
                  ),
                  // Settings
                  _buildRow(
                    context,
                    ref: ref,
                    icon: LucideIcons.settings,
                    iconColor: Colors.grey,
                    title: 'Settings',
                    subtitle: 'Account, privacy & theme',
                    explorationAction: ExplorationAction.moreScreenSettings,
                    onTap: () => context.push('/settings'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ─── Section header (uppercase label + icon) ───
  Widget _buildSectionHeader(
    BuildContext context,
    String title,
    IconData icon,
  ) {
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

  // ─── Section card container ───
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

  // ─── Standard navigable row ───
  Widget _buildRow(
    BuildContext context, {
    required WidgetRef ref,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    String? explorationAction,
    bool isComingSoon = false,
    bool useLogoImage = false,
  }) {
    final theme = Theme.of(context);

    final effectiveOnTap = explorationAction != null
        ? () {
            _trackExploration(context, ref, explorationAction);
            onTap();
          }
        : onTap;

    return InkWell(
      onTap: effectiveOnTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.sectionHorizontalPadding,
          vertical: 14,
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
              child: useLogoImage
                  ? Padding(
                      padding: const EdgeInsets.all(8),
                      child: Image.asset(
                        'assets/icons/logo-orange-transparent-24.png',
                        width: 20,
                        height: 20,
                        fit: BoxFit.contain,
                      ),
                    )
                  : Icon(icon, color: iconColor, size: 20),
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
                      fontSize: 15,
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
            if (isComingSoon)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark
                      ? Colors.grey.shade800
                      : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'Coming Soon',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: theme.brightness == Brightness.dark
                        ? Colors.grey.shade400
                        : Colors.grey.shade600,
                  ),
                ),
              )
            else
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

  // ─── Toggle row (switch instead of chevron) ───
  Widget _buildToggleRow(
    BuildContext context, {
    required WidgetRef ref,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.sectionHorizontalPadding,
        vertical: 10,
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
                    fontSize: 15,
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
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppTheme.accent,
          ),
        ],
      ),
    );
  }

  // ─── Exploration tracking ───
  Future<void> _trackExploration(
    BuildContext context,
    WidgetRef ref,
    String actionId,
  ) async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user != null) {
      final rewarded = await ref
          .read(pointsServiceProvider)
          .trackExplorationReward(user.uid, actionId);
      if (rewarded && context.mounted) {
        showExplorationRewardToast(context);
      }
    }
  }
}
