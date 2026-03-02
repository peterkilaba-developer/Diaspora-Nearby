import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/dsp/services/exploration_registry.dart';
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart';

class EconomyHubScreen extends ConsumerWidget {
  const EconomyHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profileAsync = ref.watch(userProfileProvider);
    final isAdmin = profileAsync.valueOrNull?.isAdmin == true;
    final homeCountry = profileAsync.valueOrNull?.homeCountry;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(LucideIcons.wallet, size: 22, color: AppTheme.accent),
            SizedBox(width: 8),
            Text(
              'Diaspora Economy',
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
            // --- 1. DIASPORA MARKETPLACE (top, most used) ---
            _buildEconomyCard(
              context,
              ref: ref,
              icon: LucideIcons.store,
              title: 'Diaspora Marketplace',
              description: 'Products Services and Jobs Listings',
              color: Colors.teal,
              explorationAction: ExplorationAction.economyMarketplace,
              onTap: () => context.push('/marketplace'),
            ),

            const SizedBox(height: 24),

            // --- 1b. REAL ESTATE ---
            Text(
              'Real Estate',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface.withOpacity(0.7),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildQuickAccessCard(
                    context,
                    icon: LucideIcons.map,
                    title: 'Plot',
                    subtitle: 'Rent Lease Buy',
                    color: Colors.amber.shade700,
                    onTap: () => context.push('/dsp/real-estate/plot'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildQuickAccessCard(
                    context,
                    icon: LucideIcons.sprout,
                    title: 'Farm',
                    subtitle: 'Rent Lease Buy',
                    color: Colors.green.shade600,
                    onTap: () => context.push('/dsp/real-estate/farm'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildQuickAccessCard(
                    context,
                    icon: LucideIcons.home,
                    title: 'House',
                    subtitle: 'Rent Lease Buy',
                    color: Colors.blue.shade600,
                    onTap: () => context.push('/dsp/real-estate/house'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // --- 2. DIASPORA TRAVEL PORTAL ---
            Text(
              'Diaspora Travel Portal',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface.withOpacity(0.7),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),

            // Travel Portal - 2x2 Grid
            Row(
              children: [
                Expanded(
                  child: _buildQuickAccessCard(
                    context,
                    icon: LucideIcons.plane,
                    title: 'Flights',
                    subtitle: 'Book flights',
                    color: Colors.blue,
                    isComingSoon: false,
                    onTap: () => context.push('/dsp/travel/flights'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildQuickAccessCard(
                    context,
                    icon: LucideIcons.hotel,
                    title: 'Hotels',
                    subtitle: 'Find hotels',
                    color: Colors.deepPurple,
                    isComingSoon: false,
                    onTap: () => context.push('/dsp/travel/hotels'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildQuickAccessCard(
                    context,
                    icon: LucideIcons.home,
                    title: 'Stays',
                    subtitle: 'Short-term stays',
                    color: Colors.teal,
                    isComingSoon: false,
                    onTap: () => context.push('/dsp/travel/stays'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildQuickAccessCard(
                    context,
                    icon: LucideIcons.car,
                    title: 'Car Rental',
                    subtitle: 'Rent a car',
                    color: Colors.orange,
                    isComingSoon: false,
                    onTap: () => context.push('/dsp/travel/car-rental'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // --- 3. IN-APP POINTS AND BLOCKCHAIN TOKENS ---
            Text(
              'In-App Points and Blockchain Tokens',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface.withOpacity(0.7),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),

            // DSP Points
            _buildEconomyCard(
              context,
              ref: ref,
              icon: LucideIcons.coins,
              title: 'Diaspora Social Points - DSP',
              description: 'Earn & convert to tokens',
              color: AppTheme.accent,
              explorationAction: ExplorationAction.walletView,
              onTap: () => context.push('/dsp/points'),
            ),
            const SizedBox(height: 12),

            // Diaspora Token
            _buildEconomyCard(
              context,
              ref: ref,
              icon: LucideIcons.coins,
              imagePath: 'assets/icons/logo-original.png',
              imageColor: Colors.orange,
              title: 'Diaspora Token - \$DIASPORA',
              description: 'Hold Invest Spend Swap or Trade',
              color: AppTheme.accent,
              explorationAction: ExplorationAction.economyCrypto,
              onTap: () => context.push('/dsp/crypto'),
            ),
            const SizedBox(height: 12),

            // Remittances (Admin only)
            if (isAdmin) ...[
              _buildEconomyCard(
                context,
                ref: ref,
                icon: LucideIcons.send,
                title: 'International Remittances',
                description: 'Send money to ${homeCountry ?? 'home'}',
                color: AppTheme.accent,
                isComingSoon: true,
                explorationAction: ExplorationAction.economyRemittances,
                onTap: () => context.push('/dsp/remittances'),
              ),
              const SizedBox(height: 12),
            ],

            // DFDI (Admin only)
            if (isAdmin) ...[
              _buildEconomyCard(
                context,
                ref: ref,
                icon: LucideIcons.trendingUp,
                title: 'Diaspora Foreign Direct Investments - DFDI',
                description:
                    'Invest with Community & Community Invest in You',
                color: AppTheme.accent,
                isComingSoon: true,
                explorationAction: ExplorationAction.economyDfdi,
                onTap: () => context.push('/dsp/dfdi'),
              ),
              const SizedBox(height: 12),
            ],

            const SizedBox(height: 24),

            // --- 4. COMMUNITY SUPPORT ---
            Text(
              'Community Support',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface.withOpacity(0.7),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),

            _buildEconomyCard(
              context,
              ref: ref,
              icon: LucideIcons.shieldAlert,
              title: 'Community Emergency Fund',
              description: 'Medical, Legal, Bereavement & Repatriation',
              color: AppTheme.accent,
              explorationAction: ExplorationAction.economyEmergencyFund,
              onTap: () => context.push('/dsp/emergency-fund'),
            ),

            const SizedBox(height: 24),

            // --- 5. MY PROFILE & SETTINGS ---
            Text(
              'My Profile & Settings',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface.withOpacity(0.7),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),

            _buildEconomyCard(
              context,
              ref: ref,
              icon: LucideIcons.user,
              title: 'My Profile',
              description: 'View & edit your profile',
              color: AppTheme.accent,
              explorationAction: ExplorationAction.profileEdit,
              onTap: () => context.push('/profile'),
            ),
            const SizedBox(height: 12),

            _buildEconomyCard(
              context,
              ref: ref,
              icon: LucideIcons.settings,
              title: 'Settings',
              description: 'Account, privacy, notifications & theme',
              color: AppTheme.accent,
              explorationAction: ExplorationAction.moreScreenSettings,
              onTap: () => context.push('/settings'),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAccessCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    bool isComingSoon = false,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: AppTheme.cardDecoration(context).copyWith(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                if (isComingSoon)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.brightness == Brightness.dark
                          ? Colors.grey.shade800
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Coming Soon',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: theme.brightness == Brightness.dark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.hintColor,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEconomyCard(
    BuildContext context, {
    required WidgetRef ref,
    required IconData icon,
    String? imagePath,
    Color? imageColor,
    required String title,
    required String description,
    required Color color,
    required VoidCallback onTap,
    required String explorationAction,
    bool isComingSoon = false,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () {
        _trackExploration(context, ref, explorationAction);
        onTap();
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        decoration: AppTheme.cardDecoration(context).copyWith(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            imagePath != null
                ? Image.asset(
                    imagePath,
                    width: 24,
                    height: 24,
                    fit: BoxFit.contain,
                    color: imageColor,
                  )
                : Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.hintColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isComingSoon)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
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
              ),
          ],
        ),
      ),
    );
  }

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
