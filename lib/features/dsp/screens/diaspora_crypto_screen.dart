import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'dart:async';
import 'dart:math';
import 'package:diaspora_nearby/core/data/countries.dart'
    hide getContinentByCountryCode;
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';

import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import 'package:intl/intl.dart';
import 'package:diaspora_nearby/features/governance/repository/governance_repository.dart';
import 'package:diaspora_nearby/features/community/repository/community_repository.dart';
import 'package:diaspora_nearby/features/community/models/community_data.dart';
import 'package:diaspora_nearby/features/chat/utils/community_chat_utils.dart';
import 'package:diaspora_nearby/features/governance/services/governance_service.dart';
import 'package:diaspora_nearby/features/dsp/screens/gvi_corridor_list_screen.dart';
import 'package:diaspora_nearby/features/dsp/screens/ddi_treasury_detail_screen.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/dsp/services/epoch_service.dart';
import 'package:diaspora_nearby/features/dsp/services/exploration_registry.dart';
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/dsp/services/smart_wallet_service.dart';
import 'package:diaspora_nearby/features/dsp/providers/dsp_valuation_provider.dart';
import 'package:diaspora_nearby/features/dsp/models/user_points.dart';
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';

class DiasporaCryptoScreen extends ConsumerStatefulWidget {
  const DiasporaCryptoScreen({super.key});

  @override
  ConsumerState<DiasporaCryptoScreen> createState() =>
      _DiasporaCryptoScreenState();
}

class _DiasporaCryptoScreenState extends ConsumerState<DiasporaCryptoScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _walletCreationTriggered = false;

  Future<void> _trackExploration(String actionId) async {
    final userId = ref.read(authRepositoryProvider).currentUser?.uid;
    if (userId != null) {
      final rewarded = await ref
          .read(pointsServiceProvider)
          .trackExplorationReward(userId, actionId);
      if (rewarded && mounted) {
        showExplorationRewardToast(context);
      }
    }
  }

  // Economic Tracking State (Replaced simulated GVI)
  Timer? _corridorTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabSelection);
    // Trigger governance election checks on load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(governanceServiceProvider).checkAndTriggerElections();
      // Track initial tab
      _trackExploration(ExplorationAction.dspDashboard);
      // Migrate legacy 'eoa' walletType to 'smart' in Firestore
      _migrateWalletType();
    });
  }

  /// Patches legacy 'eoa' walletType in Firestore to 'smart'.
  /// This is a one-time self-healing migration for existing users.
  Future<void> _migrateWalletType() async {
    try {
      final user = ref.read(authRepositoryProvider).currentUser;
      if (user == null) return;
      final profile = ref.read(userProfileProvider).value;
      if (profile?.walletAddress != null &&
          profile!.walletAddress!.isNotEmpty) {
        return;
      }
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!doc.exists) return;
      final currentType = doc.data()?['walletType'] as String?;
      if (currentType != null && currentType != 'smart') {
        debugPrint(
          '[CryptoScreen] Migrating walletType "$currentType" → "smart"',
        );
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({'walletType': 'smart'});
      }
    } catch (e) {
      debugPrint(
        '[CryptoScreen] walletType migration error (non-blocking): $e',
      );
    }
  }

  void _handleTabSelection() {
    if (!_tabController.indexIsChanging) {
      if (_tabController.index == 0) {
        _trackExploration(ExplorationAction.dspDashboard);
      } else if (_tabController.index == 1) {
        _trackExploration(ExplorationAction.dspTreasuries);
      }
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    _corridorTimer?.cancel();
    super.dispose();
  }

  /// Pull-to-refresh handler — invalidates the on-chain balance providers so
  /// the next read re-fetches from the chain. Without this, Riverpod's
  /// FutureProvider caches the first response forever, leaving users staring
  /// at a stale balance until they kill the app.
  Future<void> _refreshBalances() async {
    ref.invalidate(tokenBalanceProvider);
    ref.invalidate(batchTokenBalancesProvider);
    ref.invalidate(onChainTransfersProvider);
    try {
      // Await the user-balance refetch so the RefreshIndicator spinner stays
      // up until the value is actually back, not just a tick after invalidate.
      await ref.read(tokenBalanceProvider.future);
    } catch (_) {
      // Provider already handles its own errors and returns '0'. Swallow here
      // so the refresh indicator dismisses cleanly even on RPC failure.
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).value;
    final country = profile?.homeCountry ?? 'Home Country';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          '\$DIASPORA Token Ecosystem',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppTheme.accentDark,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // --- Tab Bar ---
          Container(
            color: AppTheme.accentDark,
            child: TabBar(
              controller: _tabController,
              indicatorColor: Colors.orange,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
              tabs: const [
                Tab(text: 'DASHBOARD'),
                Tab(text: 'TREASURIES'),
              ],
            ),
          ),

          Expanded(
            child: Container(
              decoration: AppTheme.pageDecoration(context),
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildDashboardTab(context, country, profile?.uid ?? ''),
                  _buildTreasuriesTab(context, profile),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardTab(
    BuildContext context,
    String country,
    String userId,
  ) {
    return RefreshIndicator(
      onRefresh: _refreshBalances,
      child: SingleChildScrollView(
        // AlwaysScrollable ensures pull-to-refresh works even when content is
        // shorter than the viewport.
        physics: const AlwaysScrollableScrollPhysics(),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              _buildHero(country),
              const SizedBox(height: 24),
              // Personal $DIASPORA TDE Distribution Schedule
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.pageHorizontalPadding,
                ),
                child: _buildTokenEpochDetailCard(context, userId),
              ),
              const SizedBox(height: 24),
              // Token Transactions
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.pageHorizontalPadding,
                ),
                child: _buildTokenTransactionsSection(context, userId),
              ),
              // Learn More link to website
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () => launchUrl(
                        Uri.parse('https://diasporanearby.com/#economy'),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              LucideIcons.bookOpen,
                              size: 16,
                              color: AppTheme.accent,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Learn More About \$DIASPORA Economy',
                              style: TextStyle(
                                color: AppTheme.accent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(
                              LucideIcons.externalLink,
                              size: 12,
                              color: AppTheme.accent,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── ECONOMY DASHBOARD ───────────────────────────────────────────────
  Widget _buildEconomyDashboard(String country) {
    final gdpAsync = ref.watch(fiatGdpProvider);
    final supplyAsync = ref.watch(globalSupplyProvider);
    final memberCountAsync = ref.watch(globalMemberCountProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hero Card — Floor Price
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.accentDark,
                AppTheme.accentDark.withValues(alpha: 0.85),
              ],
            ),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(AppTheme.standardBorderRadius),
              bottomRight: Radius.circular(AppTheme.standardBorderRadius),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Image.asset(
                    'assets/icons/logo-orange-transparent-32.png',
                    width: 32,
                    height: 32,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'DIASPORA ECONOMY',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.activity,
                          size: 10,
                          color: Colors.greenAccent,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'LIVE',
                          style: TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Dynamic DSP Value — mirrors DSP page dashboard
              Builder(
                builder: (context) {
                  final valuation = ref.watch(dspValuationProvider);
                  final projectedPrice = valuation.impliedValueUsd * 3.5;

                  return Column(
                    children: [
                      const Text(
                        'Current Floor Price',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '1 \$DIASPORA = ${valuation.formattedImpliedValue}',
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Projected: \$${projectedPrice.toStringAsFixed(4)}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.orange,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 3-stat row
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.pageHorizontalPadding,
          ),
          child: Row(
            children: [
              // Fiat GDP
              Expanded(
                child: gdpAsync.when(
                  data: (gdp) => _buildStatCard(
                    'Fiat GDP',
                    '\$${NumberFormat.compact().format(gdp)}',
                    LucideIcons.dollarSign,
                  ),
                  loading: () =>
                      _buildStatCard('Fiat GDP', '—', LucideIcons.dollarSign),
                  error: (_, _) =>
                      _buildStatCard('Fiat GDP', '—', LucideIcons.dollarSign),
                ),
              ),
              const SizedBox(width: 8),
              // $DIASPORA Supply
              Expanded(
                child: supplyAsync.when(
                  data: (supply) => _buildStatCard(
                    '\$DIASPORA Cap',
                    NumberFormat.compact().format(supply),
                    LucideIcons.coins,
                  ),
                  loading: () =>
                      _buildStatCard('\$DIASPORA Cap', '—', LucideIcons.coins),
                  error: (_, _) =>
                      _buildStatCard('\$DIASPORA Cap', '—', LucideIcons.coins),
                ),
              ),
              const SizedBox(width: 8),
              // Network
              Expanded(
                child: memberCountAsync.when(
                  data: (members) => _buildStatCard(
                    'Network',
                    NumberFormat.compact().format(members),
                    LucideIcons.users,
                  ),
                  loading: () =>
                      _buildStatCard('Network', '—', LucideIcons.users),
                  error: (_, _) =>
                      _buildStatCard('Network', '—', LucideIcons.users),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: AppTheme.cardDecoration(context),
      child: Column(
        children: [
          Icon(icon, size: 18, color: AppTheme.accent),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildTreasuriesTab(BuildContext context, ProfileData? profile) {
    final country = profile?.homeCountry ?? 'Home Country';
    return RefreshIndicator(
      onRefresh: _refreshBalances,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Economy dashboard flush to top
              _buildEconomyDashboard(country),
              const SizedBox(height: 24),
              // Bilateral corridors + treasuries
              Padding(
                padding: AppTheme.pagePaddingEdgeInsets,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildBilateralMatrix(profile),
                    const SizedBox(height: 24),
                    _buildCommunityTreasuries(profile),
                    const SizedBox(height: 24),
                    // Learn More link
                    GestureDetector(
                      onTap: () => launchUrl(
                        Uri.parse('https://diasporanearby.com/#decoupling'),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              LucideIcons.bookOpen,
                              size: 16,
                              color: AppTheme.accent,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Full Tokenomics & Governance',
                              style: TextStyle(
                                color: AppTheme.accent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(
                              LucideIcons.externalLink,
                              size: 12,
                              color: AppTheme.accent,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHero(String country) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
      decoration: AppTheme.pageDecoration(context).copyWith(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(15),
          bottomRight: Radius.circular(15),
        ),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.accentDark, AppTheme.accent],
        ),
      ),
      child: Column(
        children: [
          Image.asset(
            'assets/icons/logo-orange-transparent-80.png',
            width: 80,
            height: 80,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 16),
          const Text(
            '\$DIASPORA',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'The Hard Asset for the Global Diaspora.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.white70,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Trust-to-Asset Engine',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white54,
              fontWeight: FontWeight.w400,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 24),
          _buildMyWalletSection(context),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => launchUrl(
              Uri.parse(
                'https://basescan.org/token/0x55d7e7d006938A15082752225ED44Fd130B87735',
              ),
              mode: LaunchMode.externalApplication,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.externalLink,
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 6),
                Text(
                  'View on Blockchain',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBilateralMatrix(ProfileData? profile) {
    final country = profile?.homeCountry ?? 'Home Country';
    final countryCode = profile?.homeCountryCode ?? 'TZ';
    final homeFlag = getCountryByCode(countryCode)?.flag ?? '🇹🇿';

    final corridorsAsync = ref.watch(corridorsProvider);

    return Container(
      padding: AppTheme.cardPaddingEdgeInsets,
      decoration: AppTheme.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(homeFlag, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              const Text(
                'ACTIVE BILATERAL CORRIDORS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          corridorsAsync.when(
            data: (corridors) {
              if (corridors.isEmpty) {
                return const Center(
                  child: Text(
                    'No active corridors yet',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                );
              }
              return Table(
                columnWidths: const {
                  0: FlexColumnWidth(1.5),
                  1: FlexColumnWidth(1),
                  2: FlexColumnWidth(1),
                },
                children: [
                  TableRow(
                    children: [
                      _buildMatrixHeader('CORRIDOR'),
                      _buildMatrixHeader('GDP (\$DIASPORA)', center: true),
                      _buildMatrixHeader('TX COUNT', alignRight: true),
                    ],
                  ),
                  ...corridors.take(10).map((c) {
                    final fromFlag =
                        getCountryByCode(c.senderCountry)?.flag ?? '🏳️';
                    final toFlag =
                        getCountryByCode(c.receiverCountry)?.flag ?? '🏳️';

                    return TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            '$fromFlag → $toFlag',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            NumberFormat('#,###').format(c.cumulativeGdp),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.accent,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            c.transactionCount.toString(),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.blueGrey,
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => GviCorridorListScreen(
                      homeCountry: countryCode.isNotEmpty
                          ? countryCode
                          : country,
                    ),
                  ),
                );
              },
              child: const Text(
                'View All Economic Activity',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMatrixHeader(
    String label, {
    bool alignRight = false,
    bool center = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        textAlign: center
            ? TextAlign.center
            : (alignRight ? TextAlign.right : TextAlign.left),
        style: const TextStyle(
          fontSize: 10,
          color: Colors.grey,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildRaceTo1Billion(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final globalSupplyAsync = ref.watch(globalSupplyProvider);
        final globalMembers = ref.watch(globalMemberCountProvider).value ?? 0;
        return globalSupplyAsync.when(
          data: (totalMinted) {
            final epochService = ref.read(epochServiceProvider);
            final epoch = epochService.getCurrentCommunityEpoch(
              totalMinted,
              globalMembers,
            );
            final prevEpoch = epochService.getPreviousCommunityEpoch(
              epoch.level,
            );
            final int prevDspTarget = prevEpoch?.dspTarget ?? 0;
            final double target = epoch.dspTarget.toDouble();
            final double progress =
                ((totalMinted - prevDspTarget) / (target - prevDspTarget))
                    .clamp(0.0, 1.0);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
              padding: const EdgeInsets.all(16),
              decoration: AppTheme.cardDecoration(context),
              child: Column(
                children: [
                  _buildSectionHeader(
                    'THE GREAT RESET',
                    'Race to Epoch ${epoch.level}',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${NumberFormat('#,###').format(totalMinted)} / ${NumberFormat('#,###').format(epoch.dspTarget)} \$DIASPORA',
                    style: const TextStyle(
                      fontSize: 16,
                      color: AppTheme.accent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 12,
                      backgroundColor: Colors.black12,
                      color: AppTheme.accent,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'During TDE 1–9, your PCT converts DSP into on-chain \$DIASPORA while any unconverted DSP carries over as you build trust. At TDE 10 (100% of the epoch target), The Great Reset completes — resetting any remaining unconverted DSP to 0 and unlocking the next 10x epoch.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
        );
      },
    );
  }

  Widget _buildCommunityTreasuries(ProfileData? profile) {
    final userId = profile?.uid ?? '';

    // Watch all communities the user is part of
    final communitiesAsync = ref.watch(userCommunitiesStreamProvider(userId));
    final communities = communitiesAsync.value ?? [];

    // Filter into pools
    final homePool = communities
        .where((c) => c.id.startsWith('home_') && c.id != 'global_community')
        .toList();
    final hostPool = communities
        .where(
          (c) =>
              (c.id.startsWith('host_') || c.id.startsWith('past_')) &&
              c.id != 'global_community',
        )
        .toList();

    // Sort by type (Continent > Country > State > City)
    int getTypeWeight(String? type) {
      switch (type) {
        case 'continent':
          return 0;
        case 'country':
          return 1;
        case 'state':
          return 2;
        case 'city':
          return 3;
        default:
          return 4;
      }
    }

    homePool.sort(
      (a, b) => getTypeWeight(a.type).compareTo(getTypeWeight(b.type)),
    );
    hostPool.sort(
      (a, b) => getTypeWeight(b.type).compareTo(getTypeWeight(a.type)),
    ); // Reverse sort for host pool

    final epochService = EpochService();
    // Use Global Community for Epoch calculation as a baseline
    final globalCommunity = communities.firstWhere(
      (c) => c.id == 'global_community',
      orElse: () => Community(
        id: 'global_community',
        name: 'Global',
        memberCount: 0,
        images: [],
        isPrivate: false,
        members: [],
      ),
    );
    final int globalMembers = globalCommunity.memberCount;
    final int globalCumulative = globalCommunity.cumulativeEarnings;
    epochService.getCurrentCommunityEpoch(globalCumulative, globalMembers);
    epochService.getCurrentTgeEventNumber(globalCumulative, globalMembers);

    // Circulating wealth was previously computed here but never read.
    // The pre-TGE display shows only locked treasuries, so the calculation
    // was effectively dead. Removed to keep the file clean; the inputs
    // (`globalCumulative`, `globalMembers`) are still referenced above.

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('COMMUNITY BASED TREASURIES', 'Sovereign Reserves'),
        const Text(
          'Community treasuries are transparent multi-sig reserves managed by elected community leaders and funded through the 1:1 Ubuntu community match.',
          style: TextStyle(
            fontSize: 14,
            color: Colors.blueGrey,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 24),

        // 1. Global Community
        const Text(
          'GLOBAL ECONOMY',
          style: TextStyle(
            color: AppTheme.accent,
            letterSpacing: 1.2,
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 12),

        // 0. Community Earnings (Static Card)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Container(
            padding: AppTheme.cardPaddingEdgeInsets,
            decoration: AppTheme.cardDecoration(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.accent.withValues(alpha: 0.1),
                      ),
                      child: const Icon(
                        LucideIcons.globe,
                        size: 24,
                        color: AppTheme.accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Community Earnings',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Image.asset(
                                'assets/icons/logo-orange-transparent-32.png',
                                width: 28,
                                height: 28,
                                fit: BoxFit.contain,
                              ),
                              const SizedBox(width: 6),
                              // Sum the on-chain wallets visible to this user.
                              (() {
                                final batchAsync = ref.watch(
                                  batchTokenBalancesProvider,
                                );
                                final total = batchAsync.when(
                                  data: (b) => b.totalDistributed,
                                  loading: () => '...',
                                  error: (_, _) => '0',
                                );
                                return Text(
                                  '$total \$DIASPORA',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Colors.orange,
                                  ),
                                );
                              })(),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Network Status',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      'Visible On-chain Wealth',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: _GovernanceUnitCard(
            unitId: 'global_community',
            communityId: 'global_community',
            defaultTitle: 'Global Reserve',
            subtitle:
                'Zero-fee transfers & remittances, chamber leadership, charities & protocol upkeep · 10% Ubuntu community match',
            icon: LucideIcons.globe,
            governanceType: 'Global Reserve',
          ),
        ),

        // 3. Home Communities Pool
        if (homePool.isNotEmpty) ...[
          const Text(
            'YOUR ORIGINS',
            style: TextStyle(
              color: AppTheme.accent,
              letterSpacing: 1.2,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          ...homePool.map((community) {
            final String unitId =
                CommunityChatUtils.getCanonicalGovernanceUnitId(community.id);
            final String effectiveType = CommunityChatUtils.inferCommunityType(
              type: community.type,
              id: community.id,
              unitId: unitId,
            );
            final String defaultTitle =
                CommunityChatUtils.generateTreasuryTitle(
                  name: community.name,
                  type: effectiveType,
                  locationType: community.locationType ?? 'home',
                  id: community.id,
                  unitId: unitId,
                  homeCountryCode: community.homeCountryCode,
                  hostCountryCode: community.hostCountryCode,
                );
            final String tributeLabel =
                CommunityChatUtils.generateTreasurySubtitle(
                  type: effectiveType,
                  id: community.id,
                  unitId: unitId,
                );

            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _GovernanceUnitCard(
                unitId: unitId,
                communityId: community.id,
                defaultTitle: defaultTitle,
                subtitle: tributeLabel,
                icon: effectiveType == 'continent'
                    ? LucideIcons.map
                    : (effectiveType == 'country'
                          ? LucideIcons.flag
                          : effectiveType == 'state'
                          ? LucideIcons.landmark
                          : LucideIcons.home),
                governanceType: 'Leader Multi-sig',
              ),
            );
          }),
        ],

        // 4. Host Communities Pool
        if (hostPool.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text(
            'YOUR RESIDENCE',
            style: TextStyle(
              color: Colors.orange,
              letterSpacing: 1.2,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          ...hostPool.map((community) {
            final String unitId =
                CommunityChatUtils.getCanonicalGovernanceUnitId(community.id);
            final String effectiveType = CommunityChatUtils.inferCommunityType(
              type: community.type,
              id: community.id,
              unitId: unitId,
            );
            final String defaultTitle =
                CommunityChatUtils.generateTreasuryTitle(
                  name: community.name,
                  type: effectiveType,
                  locationType: community.locationType ?? 'host',
                  id: community.id,
                  unitId: unitId,
                  homeCountryCode: community.homeCountryCode,
                  hostCountryCode: community.hostCountryCode,
                );
            final String tributeLabel =
                CommunityChatUtils.generateTreasurySubtitle(
                  type: effectiveType,
                  id: community.id,
                  unitId: unitId,
                );

            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _GovernanceUnitCard(
                unitId: unitId,
                communityId: community.id,
                defaultTitle: defaultTitle,
                subtitle: tributeLabel,
                icon: effectiveType == 'city'
                    ? LucideIcons.mapPin
                    : (effectiveType == 'state'
                          ? LucideIcons.landmark
                          : LucideIcons.map),
                governanceType: 'Leader Multi-sig',
              ),
            );
          }),
        ],

        // 5. System Treasuries (Moved to bottom)
        const SizedBox(height: 24),
        const Text(
          'SYSTEM RESERVES',
          style: TextStyle(
            color: AppTheme.accent,
            letterSpacing: 1.2,
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 12),

        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: _GovernanceUnitCard(
            unitId: 'founders',
            defaultTitle: 'Founders & Core Team',
            subtitle: 'Core Maintenance (10%)',
            icon: LucideIcons.users,
            governanceType: 'Vesting Schedule',
            customAvatarAsset: 'assets/icons/logo-orange-transparent-48.png',
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: _GovernanceUnitCard(
            unitId: 'liquidity',
            defaultTitle: 'Liquidity Treasury',
            subtitle: 'DEX Liquidity & Market Access',
            icon: LucideIcons.droplets,
            governanceType: 'Protocol Managed Liquidity',
            customAvatarAsset: 'assets/icons/logo-orange-transparent-48.png',
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: _GovernanceUnitCard(
            unitId: 'burn',
            defaultTitle: 'Natural Burn Pool',
            subtitle: 'Protocol Deflationary Sink',
            icon: LucideIcons.flame,
            governanceType: 'Automated Protocol Burn',
            customAvatarAsset: 'assets/icons/logo-orange-transparent-48.png',
          ),
        ),

        const SizedBox(height: 16),
        _buildRaceTo1Billion(context),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          subtitle.toUpperCase(),
          style: const TextStyle(
            color: AppTheme.accent,
            letterSpacing: 1.2,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: AppTheme.elementSpacing),
      ],
    );
  }

  Widget _buildMyWalletSection(BuildContext context) {
    final walletAsync = ref.watch(userWalletProvider);
    final cachedAddr = ref.read(userProfileProvider).value?.walletAddress;

    return walletAsync.when(
      loading: () => _buildSmartWalletContent(
        cachedAddr != null && cachedAddr.isNotEmpty
            ? SmartWalletData(address: cachedAddr)
            : null,
      ),
      error: (_, _) => _buildSmartWalletContent(null),
      data: (walletData) {
        // Auto-trigger wallet creation if user doesn't have one yet
        if ((walletData == null || !walletData.hasWallet) &&
            !_walletCreationTriggered) {
          _walletCreationTriggered = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            debugPrint('[CryptoScreen] Triggering smart wallet creation...');
            ref.read(smartWalletServiceProvider).ensureSmartWallet();
          });
        }
        return _buildSmartWalletContent(walletData);
      },
    );
  }

  Widget _buildSmartWalletContent(SmartWalletData? walletData) {
    final hasWallet = walletData?.hasWallet == true;
    final displayAddress = walletData?.address ?? '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header Row ──
          Row(
            children: [
              const Icon(LucideIcons.wallet, color: Colors.white),
              const SizedBox(width: 12),
              const Text(
                'Smart Wallet',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.shield, color: Colors.white, size: 10),
                    SizedBox(width: 4),
                    Text(
                      'Gasless',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Key Features ──
          Row(
            children: [
              _buildWalletFeature(LucideIcons.smartphone, 'Phone-Based'),
              const SizedBox(width: 8),
              _buildWalletFeature(LucideIcons.zap, 'Zero Gas Fees'),
              const SizedBox(width: 8),
              _buildWalletFeature(LucideIcons.lock, 'Self-Custodial'),
            ],
          ),
          const SizedBox(height: 16),

          // ── Wallet Address or Creating State ──
          if (hasWallet) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Address Row
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          displayAddress,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                          maxLines: 2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(text: displayAddress),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Wallet address copied!'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            LucideIcons.copy,
                            color: Colors.white70,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Balance Row
                  const SizedBox(height: 10),
                  Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Consumer(
                      builder: (context, ref, _) {
                        final balanceAsync = ref.watch(tokenBalanceProvider);
                        final valuation = ref.watch(dspValuationProvider);
                        return balanceAsync.when(
                          data: (balance) {
                            final parsedInt = (double.tryParse(balance) ?? 0)
                                .toInt();
                            final usdEst = valuation.formatBalance(parsedInt);
                            return Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                Image.asset(
                                  'assets/icons/logo-orange-transparent-32.png',
                                  width: 24,
                                  height: 24,
                                ),
                                Text(
                                  '$balance \$DIASPORA',
                                  style: const TextStyle(
                                    color: Colors.orange,
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '($usdEst)',
                                  style: const TextStyle(
                                    color: Color(0xFF38BDF8),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            );
                          },
                          loading: () => Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Balance: ',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.orange,
                                ),
                              ),
                            ],
                          ),
                          error: (_, _) => Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Balance: ',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const Text(
                                '—',
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  LucideIcons.shieldCheck,
                  color: Colors.lightGreenAccent,
                  size: 16,
                ),
                SizedBox(width: 8),
                Text(
                  'Smart Wallet Active',
                  style: TextStyle(
                    color: Colors.lightGreenAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(
                    'https://aerodrome.finance/swap?from=0x55d7e7d006938A15082752225ED44Fd130B87735&to=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913',
                  ),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(
                  LucideIcons.repeat,
                  size: 16,
                  color: Colors.black,
                ),
                label: const Text(
                  'Swap / Sell on Aerodrome',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.black,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
              ),
            ),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.orange,
                    ),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Creating your smart wallet...',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWalletFeature(IconData icon, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: Colors.white70),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTokenEpochDetailCard(BuildContext context, String userId) {
    if (userId.isEmpty) return const SizedBox.shrink();

    final globalSupplyAsync = ref.watch(globalSupplyProvider);
    final globalMembersAsync = ref.watch(globalMemberCountProvider);
    final epochService = ref.watch(epochServiceProvider);
    final userPointsAsync = ref.watch(userPointsProvider(userId));
    final trustDataAsync = ref.watch(userTrustProvider(userId));

    final displayPoints =
        userPointsAsync.value ??
        UserPoints(
          userId: userId,
          totalPoints: 0,
          availablePoints: 0,
          currentStreak: 0,
          dailyMessageCount: 0,
          dailyShareCount: 0,
          lastUpdated: DateTime.now(),
          lastActivityDate: DateTime.now(),
          dailyCommunitiesMessaged: const [],
          completedExplorationActions: const [],
          lifetimeEarnings: const {},
          homeCountryCode: null,
          signupDate: DateTime.now(),
          tdeHistory: const [],
        );

    final trustData = trustDataAsync.value;
    final double effectiveTrustScore =
        trustData?.trustScore ?? (displayPoints.trustScore?.toDouble() ?? 0.0);
    final int effectiveQrCount =
        trustData?.uniqueQrCount ?? displayPoints.qrConnectionCount;

    return globalSupplyAsync.when(
      data: (supply) {
        return globalMembersAsync.when(
          data: (members) {
            final epoch = epochService.getCurrentCommunityEpoch(
              supply,
              members,
            );

            // Personal $DIASPORA distributed to logged-in user in this Epoch
            final epochHistory = displayPoints.tdeHistory
                .where((e) => e.epoch == epoch.level)
                .toList();
            final double userDistributed = epochHistory.fold(
              0.0,
              (acc, e) => acc + e.amount,
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: _buildSectionHeader(
                        'TDE Schedule',
                        'TOKEN DISTRIBUTION SCHEDULE',
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${NumberFormat.compact().format(userDistributed)} \$DIASPORA',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.warning,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: AppTheme.cardPaddingEdgeInsets,
                  decoration: AppTheme.cardDecoration(context),
                  child: _buildTokenTdeMilestones(
                    context,
                    epoch,
                    supply,
                    members,
                    displayPoints,
                    epochService,
                    effectiveQrCount,
                    effectiveTrustScore,
                  ),
                ),
              ],
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  Widget _buildTokenTdeMilestones(
    BuildContext context,
    CommunityEpochDefinition epoch,
    int currentSupply,
    int currentMembers,
    UserPoints userPoints,
    EpochService epochService,
    int uniqueQrCount,
    double trustScore,
  ) {
    final prevEpoch = epochService.getPreviousCommunityEpoch(epoch.level);
    final int prevDspTarget = prevEpoch?.dspTarget ?? 0;
    final int prevMemberTarget = prevEpoch?.memberTarget ?? 0;

    final int dspRange = epoch.dspTarget - prevDspTarget;
    final int memberRange = epoch.memberTarget - prevMemberTarget;

    final int stepSize = (dspRange / 10).round();
    final int memberStepSize = (memberRange / 10).round();
    final int effectiveMemberStep = memberStepSize > 0 ? memberStepSize : 1;

    return Column(
      children: List.generate(10, (index) {
        final tdeNumber = index + 1;

        final stepStart = prevDspTarget + (index * stepSize);
        final stepTarget = prevDspTarget + ((index + 1) * stepSize);

        final memberStart = prevMemberTarget + (index * effectiveMemberStep);
        final memberTarget =
            prevMemberTarget + ((index + 1) * effectiveMemberStep);

        // Logged-in user's personal $DIASPORA distribution record for this TDE
        final record = userPoints.tdeHistory.firstWhere(
          (e) => e.epoch == epoch.level && e.tdeNumber == tdeNumber,
          orElse: () => TdeDistributionRecord(
            epoch: -1,
            tdeNumber: -1,
            amount: 0,
            efficiency: 0,
            date: DateTime.now(),
          ),
        );

        final bool isSupplyMet = currentSupply >= stepTarget;
        final bool isCompleted = isSupplyMet;
        final bool isActive = !isCompleted && currentSupply >= stepStart;

        double supplyProgress = 0.0;
        double memberProgress = 0.0;

        if (isActive) {
          supplyProgress = ((currentSupply - stepStart) / stepSize).clamp(
            0.0,
            1.0,
          );
          memberProgress =
              ((currentMembers - memberStart) / effectiveMemberStep).clamp(
                0.0,
                1.0,
              );
        }

        return Container(
          margin: const EdgeInsets.only(bottom: AppTheme.elementSpacing),
          padding: EdgeInsets.symmetric(
            horizontal: isActive ? AppTheme.cardHorizontalPadding : 0,
            vertical: AppTheme.cardVerticalPadding,
          ),
          decoration: isActive
              ? AppTheme.cardDecoration(
                  context,
                ).copyWith(color: AppTheme.accent.withValues(alpha: 0.03))
              : const BoxDecoration(),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'TDE $tdeNumber',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isCompleted
                                    ? Colors.grey.withValues(alpha: 0.5)
                                    : (isActive
                                          ? Theme.of(
                                              context,
                                            ).textTheme.bodyMedium?.color
                                          : Colors.grey),
                              ),
                            ),
                            if (isActive)
                              Text(
                                '${(supplyProgress * 100).toInt()}% • ${(memberProgress * 100).toInt()}%',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isActive
                                      ? AppTheme.accent
                                      : Colors.grey.withValues(alpha: 0.5),
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            else if (isCompleted)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${NumberFormat.compact().format(record.amount)} \$DIASPORA',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.warning.withValues(
                                        alpha: 0.5,
                                      ),
                                      fontSize: 11,
                                    ),
                                  ),
                                  if (record.amount > 0)
                                    Text(
                                      '${(record.efficiency * 100).toInt()}%',
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.grey.withValues(
                                          alpha: 0.5,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                          ],
                        ),
                        if (isActive) ...[
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: supplyProgress,
                              minHeight: 4,
                              backgroundColor: Colors.grey.withValues(
                                alpha: 0.1,
                              ),
                              color: AppTheme.accent,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: memberProgress,
                              minHeight: 4,
                              backgroundColor: Colors.grey.withValues(
                                alpha: 0.1,
                              ),
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${NumberFormat.compact().format(currentSupply)} / ${NumberFormat.compact().format(stepTarget)} Target',
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: AppTheme.accent,
                                ),
                              ),
                              Text(
                                '${NumberFormat.compact().format(currentMembers)} / ${NumberFormat.compact().format(memberTarget)} Users',
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: Colors.blue,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.cardDecoration(context).color,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'YOUR STATUS',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Builder(
                                  builder: (context) {
                                    final currentTrust =
                                        (trustScore > 0
                                                ? trustScore
                                                : (userPoints.trustScore ?? 0))
                                            .round();
                                    final trustColor =
                                        EpochService.getEfficiencyColor(
                                          currentTrust,
                                        );

                                    return Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'Trust Score',
                                          style: TextStyle(fontSize: 10),
                                        ),
                                        Text(
                                          '$currentTrust PCT',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: trustColor,
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                                const SizedBox(height: 16),
                                Builder(
                                  builder: (context) {
                                    final isPostFirstTge =
                                        userPoints.firstTgeReceivedAt != null ||
                                        userPoints.tdeHistory.isNotEmpty;
                                    final qrMet =
                                        isPostFirstTge || uniqueQrCount >= 10;
                                    final label = isPostFirstTge
                                        ? 'Auto-included'
                                        : '$uniqueQrCount / 10';
                                    return Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'QR Exchanges',
                                          style: TextStyle(fontSize: 10),
                                        ),
                                        Text(
                                          label,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: qrMet
                                                ? Colors.green
                                                : Colors.orange,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                                const SizedBox(height: 16),
                                Builder(
                                  builder: (context) {
                                    double efficiency = 0.0;
                                    final trust =
                                        (trustScore > 0
                                                ? trustScore
                                                : (userPoints.trustScore ?? 0))
                                            .round();
                                    if (trust > 0) {
                                      efficiency = epochService
                                          .calculateEfficiency(trust);
                                      if (efficiency > 1.0) efficiency = 1.0;
                                    }

                                    return Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'Efficiency',
                                          style: TextStyle(fontSize: 10),
                                        ),
                                        Text(
                                          '${(efficiency * 100).toInt()}%',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color:
                                                EpochService.getEfficiencyColor(
                                                  trust,
                                                ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                                const SizedBox(height: 16),
                                Builder(
                                  builder: (context) {
                                    final isPostFirstTge =
                                        userPoints.firstTgeReceivedAt != null ||
                                        userPoints.tdeHistory.isNotEmpty;
                                    final qrMet =
                                        isPostFirstTge || uniqueQrCount >= 10;
                                    final currentBalance =
                                        userPoints.availablePoints;
                                    double efficiency = 0.0;
                                    final trust =
                                        (trustScore > 0
                                                ? trustScore
                                                : (userPoints.trustScore ?? 0))
                                            .round();
                                    if (trust > 0) {
                                      efficiency = epochService
                                          .calculateEfficiency(trust);
                                      if (efficiency > 1.0) efficiency = 1.0;
                                    }
                                    final double payout =
                                        currentBalance * efficiency;
                                    final valuation = ref.watch(
                                      dspValuationProvider,
                                    );
                                    final usdEst = valuation.formatBalance(
                                      payout.round(),
                                    );
                                    return Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'Estimated Payout',
                                          style: TextStyle(fontSize: 10),
                                        ),
                                        if (!qrMet)
                                          const Text(
                                            '— complete QR gate first',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.grey,
                                            ),
                                          )
                                        else
                                          Text.rich(
                                            TextSpan(
                                              children: [
                                                TextSpan(
                                                  text:
                                                      '${NumberFormat('#,###').format(payout.round())} \$DIASPORA ',
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: AppTheme.warning,
                                                  ),
                                                ),
                                                TextSpan(
                                                  text: '($usdEst)',
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFF38BDF8),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ] else if (isCompleted) ...[
                          const Text(
                            'Distributed',
                            style: TextStyle(fontSize: 10, color: Colors.green),
                          ),
                        ] else
                          Text(
                            'Unlocks at ${NumberFormat.compact().format(stepStart)} epoch target',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildTokenTransactionsSection(BuildContext context, String userId) {
    if (userId.isEmpty) return const SizedBox.shrink();

    final onChainAsync = ref.watch(onChainTransfersProvider);
    final userPoints = ref.watch(userPointsProvider(userId)).value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'BLOCKCHAIN ACTIVITIES',
          'On-chain transactions & distributions',
        ),
        onChainAsync.when(
          data: (onChainTransfers) {
            final List<_BlockchainEvent> activities = [];

            // 1. Add real on-chain ERC-20 transfer events from Ethereum Base Blockchain
            for (final tx in onChainTransfers) {
              final title = tx.isIncoming
                  ? 'Received from ${tx.shortFrom}'
                  : 'Sent to ${tx.shortTo}';

              activities.add(
                _BlockchainEvent(
                  title: title,
                  timestamp: tx.timestamp,
                  amount: tx.amount,
                  isPositive: tx.isIncoming,
                  txHash: tx.txHash,
                  category: tx.isIncoming
                      ? _TxCategory.token
                      : _TxCategory.transfer,
                ),
              );
            }

            // 2. Add TGE distributions (these are on-chain mints)
            if (userPoints != null) {
              for (final record in userPoints.tdeHistory) {
                // Skip if already present from on-chain logs
                if (record.txHash != null &&
                    activities.any((a) => a.txHash == record.txHash)) {
                  continue;
                }
                activities.add(
                  _BlockchainEvent(
                    title:
                        'Epoch ${record.epoch} TDE ${record.tdeNumber} Distribution',
                    timestamp: record.date,
                    amount: record.amount,
                    isPositive: record.amount >= 0,
                    subtitle:
                        'Efficiency: ${(record.efficiency * 100).toStringAsFixed(1)}%',
                    txHash: record.txHash,
                    category: _TxCategory.token,
                  ),
                );
              }
            }

            // 3. Also include Firestore token transfer records (assetType == 'token')
            //    to catch any on-chain txns that might be outside the RPC log window
            final firestoreTxAsync = ref.watch(
              userTransactionsProvider(userId),
            );
            firestoreTxAsync.whenData((transactions) {
              for (final tx in transactions) {
                final isTokenAsset =
                    tx.metadata?['assetType'] == 'token' ||
                    tx.action.toLowerCase().contains('token_transfer');
                if (!isTokenAsset) continue;

                final txHash = tx.metadata?['txHash'] as String?;
                // Skip duplicates already from on-chain logs
                if (txHash != null &&
                    activities.any((a) => a.txHash == txHash)) {
                  continue;
                }

                activities.add(
                  _BlockchainEvent(
                    title: tx.displayAction,
                    timestamp: tx.timestamp,
                    amount: tx.points.toDouble(),
                    isPositive: tx.points >= 0,
                    txHash: txHash,
                    category: _TxCategory.token,
                  ),
                );
              }
            });

            // 4. Sort by date descending
            activities.sort((a, b) => b.timestamp.compareTo(a.timestamp));

            if (activities.isEmpty) {
              return _buildNoOnChainActivityCard(context);
            }

            final displayCount = min(activities.length, 8);
            final hasMore = activities.length > 8;

            return Column(
              children: [
                ...List.generate(displayCount, (index) {
                  final act = activities[index];
                  final isLast = index == displayCount - 1 && !hasMore;
                  return _buildActivityTile(context, act, showDivider: !isLast);
                }),
                if (hasMore)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: TextButton(
                      onPressed: () {
                        // Show all activities in a bottom sheet
                        _showAllActivities(context, activities);
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'View All ${activities.length} Transactions',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.accent,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            LucideIcons.chevronDown,
                            size: 14,
                            color: AppTheme.accent,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
          loading: () => _buildNoOnChainActivityCard(
            context,
            subtitle: 'Checking the blockchain in the background...',
          ),
          error: (err, stack) => Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: AppTheme.cardDecoration(context),
            child: Row(
              children: [
                Icon(
                  LucideIcons.alertTriangle,
                  size: 16,
                  color: Colors.orange.shade400,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Could not fetch blockchain data',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNoOnChainActivityCard(
    BuildContext context, {
    String subtitle =
        '\$DIASPORA token transfers and TGE\ndistributions will appear here.',
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      decoration: AppTheme.cardDecoration(context),
      child: Column(
        children: [
          Icon(
            LucideIcons.hexagon,
            size: 32,
            color: Colors.orange.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            'No on-chain activity yet',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityTile(
    BuildContext context,
    _BlockchainEvent act, {
    bool showDivider = true,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sign = act.isPositive ? '+' : '-';

    // All blockchain activities use orange/token styling
    final IconData icon;
    if (act.category == _TxCategory.transfer && !act.isPositive) {
      icon = LucideIcons.arrowUpRight;
    } else if (act.isPositive) {
      icon = LucideIcons.arrowDownLeft;
    } else {
      icon = LucideIcons.hexagon;
    }
    const accentColor = Colors.orange;

    final amountColor = act.isPositive
        ? (isDark ? Colors.greenAccent.shade200 : AppTheme.accent)
        : Colors.red.shade400;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            children: [
              // Icon
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accentColor, size: 16),
              ),
              const SizedBox(width: 12),
              // Title & timestamp
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      act.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          act.subtitle ?? _formatRelativeTime(act.timestamp),
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            'ON-CHAIN',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Amount
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$sign${NumberFormat('#,###.##').format(act.amount.abs())}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: amountColor,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    '\$DIASPORA',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: accentColor.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
              // Basescan link (always present for on-chain tx)
              if (act.txHash != null && act.txHash!.isNotEmpty) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => launchUrl(
                    Uri.parse('https://basescan.org/tx/${act.txHash}'),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Icon(
                    LucideIcons.externalLink,
                    size: 14,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.06),
          ),
      ],
    );
  }

  void _showAllActivities(
    BuildContext context,
    List<_BlockchainEvent> activities,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                // Handle bar
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.hexagon,
                        size: 18,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'All On-Chain Transactions (${activities.length})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: activities.length,
                    itemBuilder: (context, index) {
                      return _buildActivityTile(
                        context,
                        activities[index],
                        showDivider: index < activities.length - 1,
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _formatRelativeTime(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat.MMMd().format(timestamp);
  }

  /// Builds a compact card showing the DSP estimated value and factor breakdown.

  /// Compact factor chip for the valuation card.
}

class _GovernanceUnitCard extends ConsumerWidget {
  final String unitId;
  final String? communityId;
  final String defaultTitle;
  final String subtitle;
  final IconData icon;
  final String governanceType;
  final String? customAvatarAsset;

  const _GovernanceUnitCard({
    required this.unitId,
    this.communityId,
    required this.defaultTitle,
    required this.subtitle,
    required this.icon,
    required this.governanceType,
    this.customAvatarAsset,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use Riverpod StreamProvider instead of StreamBuilder so that
    // ref.watch(treasuryTokenBalanceProvider) chains properly.
    final unitAsync = ref.watch(governanceUnitStreamProvider(unitId));
    final unit = unitAsync.value;
    final String walletAddr = unit?.walletAddress ?? '';

    // [SYSTEM RESERVES] System stats available via systemTreasuryProvider if needed

    final communityAsync = communityId != null
        ? ref.watch(communityProvider(communityId!))
        : const AsyncValue<Community?>.data(null);

    // Read on-chain $DIASPORA balance from batch provider (avoids rate-limiting)
    // Fall back to Firestore treasury DSP balance when no wallet assigned
    final double firestoreBalance = unit?.treasuryBalance ?? 0;
    final batchAsync = ref.watch(batchTokenBalancesProvider);

    final String balance = batchAsync.when(
      data: (batch) {
        final onChain = batch.balances[unitId];
        if (onChain != null && onChain != '0') return onChain;
        // Fallback to Firestore DSP balance
        return firestoreBalance > 0 ? firestoreBalance.toInt().toString() : '0';
      },
      loading: () => '...',
      error: (_, _) =>
          firestoreBalance > 0 ? firestoreBalance.toInt().toString() : '0',
    );
    final bool isSystemReserve =
        unitId == 'founders' ||
        unitId == 'liquidity' ||
        unitId == 'burn' ||
        unitId == 'global_community';

    // Show loading state while governance unit hasn't loaded yet
    if (unitAsync.isLoading) {
      return Container(
        padding: AppTheme.cardPaddingEdgeInsets,
        decoration: AppTheme.cardDecoration(context),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return communityAsync.when(
      data: (community) {
        final effectiveType = CommunityChatUtils.inferCommunityType(
          type: community?.type,
          id: community?.id ?? communityId,
          unitId: unitId,
        );
        final bool isCommunityReserve =
            effectiveType == 'state' || effectiveType == 'continent';
        final String title = (unitId == 'global_community' || isSystemReserve)
            ? defaultTitle
            : (community != null
                  ? CommunityChatUtils.generateTreasuryTitle(
                      name: community.name,
                      type: effectiveType,
                      locationType: community.locationType,
                      id: community.id,
                      unitId: unitId,
                      homeCountryCode: community.homeCountryCode,
                      hostCountryCode: community.hostCountryCode,
                    )
                  : defaultTitle);

        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DdiTreasuryDetailScreen(
                title: title,
                subtitle: subtitle,
                walletAddress: walletAddr,
                balance: balance,
                isSystemReserve: isSystemReserve || isCommunityReserve,
                unitId: unitId,
              ),
            ),
          ),
          child: Container(
            padding: AppTheme.cardPaddingEdgeInsets,
            decoration: AppTheme.cardDecoration(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (customAvatarAsset != null)
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.transparent,
                        ),
                        child: Image.asset(
                          customAvatarAsset!,
                          fit: BoxFit.contain,
                        ),
                      )
                    else
                      CommunityChatUtils.getCommunityAvatar(
                        context: context,
                        type: community?.type,
                        locationType: community?.locationType,
                        homeCountryCode: community?.homeCountryCode,
                        flag: community?.flag,
                        profileImage: community?.profileImage,
                        communityId: community?.id,
                        size: 44,
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Image.asset(
                                'assets/icons/logo-orange-transparent-32.png',
                                width: 28,
                                height: 28,
                                fit: BoxFit.contain,
                              ),
                              const SizedBox(width: 6),
                              Builder(
                                builder: (context) {
                                  final valuation = ref.watch(
                                    dspValuationProvider,
                                  );
                                  final parsedVal =
                                      (double.tryParse(balance) ?? 0).toInt();
                                  final usdEst = valuation.formatBalance(
                                    parsedVal,
                                  );
                                  return Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: '$balance \$DIASPORA ',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Colors.orange,
                                          ),
                                        ),
                                        TextSpan(
                                          text: '($usdEst)',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                            color: Color(0xFF38BDF8),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Chevron hint that card is tappable
                    const Icon(
                      LucideIcons.chevronRight,
                      size: 18,
                      color: Colors.grey,
                    ),
                  ],
                ),

                // Wallet address (if available)
                if (walletAddr.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(
                        LucideIcons.wallet,
                        size: 10,
                        color: Colors.blueGrey,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          walletAddr,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.blueGrey,
                            fontFamily: 'monospace',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],

                // Subtitle
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => _buildErrorCard(context, defaultTitle),
    );
  }

  Widget _buildErrorCard(BuildContext context, String title) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(context),
      child: Text('Error loading $title'),
    );
  }
}

enum _TxCategory { token, transfer }

class _BlockchainEvent {
  final String title;
  final String? subtitle;
  final DateTime timestamp;
  final double amount;
  final bool isPositive;
  final String? txHash;
  final _TxCategory category;

  _BlockchainEvent({
    required this.title,
    this.subtitle,
    required this.timestamp,
    required this.amount,
    required this.isPositive,
    this.txHash,
    this.category = _TxCategory.token,
  });
}
