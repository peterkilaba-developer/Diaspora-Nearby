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
                          color: AppTheme.accent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.accent.withValues(alpha: 0.2),
                          ),
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
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '1 DSP = ${valuation.formattedImpliedValue}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Projected: \$${projectedPrice.toStringAsFixed(4)}',
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
              // DSP Volume
              Expanded(
                child: supplyAsync.when(
                  data: (supply) => _buildStatCard(
                    'DSP Supply',
                    NumberFormat.compact().format(supply),
                    LucideIcons.coins,
                  ),
                  loading: () =>
                      _buildStatCard('DSP Supply', '—', LucideIcons.coins),
                  error: (_, _) =>
                      _buildStatCard('DSP Supply', '—', LucideIcons.coins),
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
                          color: AppTheme.accent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.accent.withValues(alpha: 0.2),
                          ),
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
            '\$DIASPORA Token Ecosystem',
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
            'Reputation-to-Asset Engine',
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
                      _buildMatrixHeader('GDP (DSP)', center: true),
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
                    builder: (context) =>
                        GviCorridorListScreen(homeCountry: country),
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
        return globalSupplyAsync.when(
          data: (totalMinted) {
            const double target = 1000000;
            final double progress = (totalMinted / target).clamp(0.0, 1.0);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
              padding: const EdgeInsets.all(16),
              decoration: AppTheme.cardDecoration(context),
              child: Column(
                children: [
                  _buildSectionHeader('THE GREAT RESET', 'Race to Epoch 1'),
                  const SizedBox(height: 16),
                  Text(
                    '${NumberFormat('#,###').format(totalMinted)} / 1,000,000 DSP',
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
                    'Upon reaching 1 Million DSP + 100 Members, Epoch 1 (The Great Reset) completes. Complete 10 unique in-person Identity QR exchanges to qualify for your first TGE — every TGE after that is automatic.',
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
          'Community based wallets are multi-sig accounts overseen by elected Leaders and funded by the decentralized sovereign split (10% Matching).',
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
                              // Use actual on-chain totalDistributed from batch provider
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
                      'Aggregated Distributed Wealth',
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
                'Global Reserve — 10% Tribute · Funds chambers operations, charitable donations, and protocol upkeep',
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
            final String unitId = community.id.contains('_')
                ? community.id.substring(community.id.indexOf('_') + 1)
                : community.id;

            // Determine allocation % based on hierarchy depth
            final bool hasHomeState = homePool.any((c) => c.type == 'state');
            String tributeLabel;
            if (community.type == 'country' && hasHomeState) {
              tributeLabel =
                  'Foreign Diaspora Direct Investments — 5% Tribute (Split)';
            } else if (community.type == 'state') {
              tributeLabel =
                  'Foreign Diaspora Direct Investments — 5% Tribute (Split)';
            } else {
              tributeLabel =
                  'Foreign Diaspora Direct Investments — 10% Tribute';
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _GovernanceUnitCard(
                unitId: unitId,
                communityId: community.id,
                defaultTitle: '${community.name} Treasury',
                subtitle: tributeLabel,
                icon: community.type == 'continent'
                    ? LucideIcons.map
                    : (community.type == 'country'
                          ? LucideIcons.flag
                          : community.type == 'state'
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
            final String unitId = community.id.contains('_')
                ? community.id.substring(community.id.indexOf('_') + 1)
                : community.id;

            // Determine allocation % based on hierarchy depth
            final bool hasHostState = hostPool.any((c) => c.type == 'state');
            String tributeLabel;
            if (community.type == 'country' && hasHostState) {
              tributeLabel =
                  'Diaspora Direct Investments Loans — 5% Tribute (Split)';
            } else if (community.type == 'state') {
              tributeLabel =
                  'Diaspora Direct Investments Loans — 5% Tribute (Split)';
            } else {
              tributeLabel = 'Diaspora Direct Investments Loans — 10% Tribute';
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _GovernanceUnitCard(
                unitId: unitId,
                communityId: community.id,
                defaultTitle: '${community.name} Treasury',
                subtitle: tributeLabel,
                icon: community.type == 'city'
                    ? LucideIcons.mapPin
                    : (community.type == 'state'
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

    return walletAsync.when(
      loading: () => Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
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
          const SizedBox(height: 12),

          // ── Description ──
          const Center(
            child: Text(
              'Auto-created from your phone number. No keys to manage, no gas fees.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
          ),
          const SizedBox(height: 16),

          // ── Key Features ──
          Row(
            children: [
              _buildWalletFeature(LucideIcons.smartphone, 'Phone-Based'),
              const SizedBox(width: 8),
              _buildWalletFeature(LucideIcons.zap, 'Zero Gas Fees'),
              const SizedBox(width: 8),
              _buildWalletFeature(LucideIcons.lock, 'Non-Custodial'),
            ],
          ),
          const SizedBox(height: 16),

          // ── Wallet Address or Creating State ──
          if (hasWallet) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
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
                  Consumer(
                    builder: (context, ref, _) {
                      final balanceAsync = ref.watch(tokenBalanceProvider);
                      final valuation = ref.watch(dspValuationProvider);
                      return balanceAsync.when(
                        data: (balance) {
                          final parsedInt =
                              (double.tryParse(balance) ?? 0).toInt();
                          final usdEst = valuation.formatBalance(parsedInt);
                          return Wrap(
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
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
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
                  'Swap / Sell \$DIASPORA on Aerodrome',
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
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
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

            // 1. Add real on-chain ERC-20 transfer events from Coinbase L2 Base Blockchain
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
    // Show DSP label when using Firestore fallback (no on-chain balance available)
    final bool hasOnChain =
        batchAsync.value?.balances[unitId] != null &&
        batchAsync.value!.balances[unitId] != '0';
    final bool showingDsp =
        !hasOnChain && walletAddr.isEmpty && firestoreBalance > 0;
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
        final cleanName = community?.name
            .replaceAll('Community', '')
            .replaceAll('Treasury', '')
            .trim();
        // Global Reserve is not a community treasury — always use the
        // defaultTitle ("Global Reserve") instead of appending "Community
        // Treasury" to whatever the underlying community doc is named.
        final title = unitId == 'global_community'
            ? defaultTitle
            : (cleanName != null && cleanName.isNotEmpty
                  ? '$cleanName Community Treasury'
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
                isSystemReserve: isSystemReserve,
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
                                  final valuation =
                                      ref.watch(dspValuationProvider);
                                  final parsedVal =
                                      (double.tryParse(balance) ?? 0).toInt();
                                  final usdEst =
                                      valuation.formatBalance(parsedVal);
                                  return Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: showingDsp
                                              ? '$balance DSP '
                                              : '$balance \$DIASPORA ',
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
