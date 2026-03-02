import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'dart:async';
import 'dart:math';
import 'package:diaspora_nearby/core/data/countries.dart'
    hide getContinentByCountryCode;
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/dsp/repository/interest_repository.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import 'package:intl/intl.dart';
import 'package:diaspora_nearby/features/governance/repository/governance_repository.dart';
import 'package:diaspora_nearby/features/governance/models/governance_unit.dart';
import 'package:diaspora_nearby/features/community/repository/community_repository.dart';
import 'package:diaspora_nearby/features/community/models/community_data.dart';
import 'package:diaspora_nearby/features/chat/utils/community_chat_utils.dart';
import 'package:diaspora_nearby/features/governance/services/governance_service.dart';
import 'package:diaspora_nearby/features/dsp/screens/gvi_corridor_list_screen.dart';
import 'package:diaspora_nearby/features/dsp/screens/ddi_treasury_detail_screen.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/dsp/services/epoch_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:diaspora_nearby/features/dsp/services/exploration_registry.dart';
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';

class DiasporaCryptoScreen extends ConsumerStatefulWidget {
  const DiasporaCryptoScreen({super.key});

  @override
  ConsumerState<DiasporaCryptoScreen> createState() =>
      _DiasporaCryptoScreenState();
}

class _DiasporaCryptoScreenState extends ConsumerState<DiasporaCryptoScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _isLoading = false;
  bool _hasRegistered = false;

  final TextEditingController _walletController = TextEditingController();
  bool _isSavingWallet = false;
  bool _isEditingWallet = false;

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

  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabSelection);

    _checkStatus();
    _loadWalletData();
    // Trigger governance election checks on load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(governanceServiceProvider).checkAndTriggerElections();
      // Track initial tab
      _trackExploration(ExplorationAction.dspDashboard);
    });
  }

  void _handleTabSelection() {
    if (!_tabController.indexIsChanging) {
      if (_tabController.index == 0) {
        _trackExploration(ExplorationAction.dspDashboard);
      } else if (_tabController.index == 1) {
        _trackExploration(ExplorationAction.dspTokenomics);
      } else if (_tabController.index == 2) {
        _trackExploration(ExplorationAction.dspTreasuries);
      }
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    _corridorTimer?.cancel();
    _walletController.dispose();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null) return;

    final hasRegistered = await ref
        .read(interestRepositoryProvider)
        .checkInterest(userId: user.uid, service: 'crypto');

    if (mounted) {
      setState(() {
        _hasRegistered = hasRegistered;
      });
    }
  }

  Future<void> _loadWalletData() async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null) return;

    final userPoints = await ref
        .read(pointsRepositoryProvider)
        .getUserPoints(user.uid);
    if (userPoints?.walletAddress != null) {
      _walletController.text = userPoints!.walletAddress!;
    }
  }

  Future<void> _saveWalletAddress() async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null) return;

    final address = _walletController.text.trim();

    // Validate EVM address (0x followed by 40 hex chars)
    final ethRegex = RegExp(r'^0x[a-fA-F0-0]{40}$');
    if (!ethRegex.hasMatch(address)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter a valid wallet address (starts with 0x, 42 characters)',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isSavingWallet = true);

    try {
      await ref
          .read(pointsRepositoryProvider)
          .updateWalletAddress(user.uid, address);

      if (mounted) {
        setState(() {
          _isSavingWallet = false;
          _isEditingWallet = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Wallet address saved successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingWallet = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving wallet: $e')));
      }
    }
  }

  Future<void> _registerInterest() async {
    final user = ref.read(authRepositoryProvider).currentUser;
    final profile = ref.read(userProfileProvider).value;

    if (user == null || profile == null) return;

    setState(() => _isLoading = true);

    try {
      await ref
          .read(interestRepositoryProvider)
          .registerInterest(
            userId: user.uid,
            service: 'crypto',
            country: profile.homeCountry ?? 'Unknown',
          );

      if (mounted) {
        setState(() {
          _hasRegistered = true;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You have been added to the whitelist!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
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
                Tab(text: 'TOKENOMICS'),
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
                  _buildTokenomicsTab(context, country, profile),
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
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildHero(country),
          const SizedBox(height: 24), // Added 24px bottom margin
          // Move Token Transactions here
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.pageHorizontalPadding,
            ),
            child: _buildTokenTransactionsSection(context, userId),
          ),
          _buildFooter(context),
        ],
      ),
    );
  }

  Widget _buildTokenomicsTab(
    BuildContext context,
    String country,
    ProfileData? profile,
  ) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. LIVE ECONOMY DASHBOARD — flush to top & sides
          _buildEconomyDashboard(country),
          const SizedBox(height: 24),

          // Remaining sections with horizontal padding
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.pageHorizontalPadding,
            ).copyWith(bottom: 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 2. HOW YOUR ACTIVITY CREATES VALUE
                _buildValueCreationSection(),
                const SizedBox(height: 24),

                // 3. THE VALUE FLOW
                _buildValueFlowSection(),
                const SizedBox(height: 24),

                // 4. THE ASSET
                _buildSectionHeader('THE ASSET', '\$DIASPORA Token'),
                const Text(
                  'A sovereign digital currency for the 1.5 billion global Diaspora — backed not by speculation, but by the real economic activity of our people.',
                  style: TextStyle(fontSize: 15, color: Colors.grey, height: 1.6),
                ),
                const SizedBox(height: 16),
                _buildUtilityItem(
                  LucideIcons.globe2,
                  'Sovereign Currency',
                  'Built on Base blockchain. Your DSP converts to \$DIASPORA at each Token Generation Event.',
                ),
                _buildUtilityItem(
                  LucideIcons.shieldCheck,
                  'Trust-Backed Efficiency',
                  'Your PoCT trust score determines your DSP→\$DIASPORA conversion rate via decile scaling.',
                ),
                const SizedBox(height: 24),

                // 5. MONETARY POLICY
                _buildSectionHeader('MONETARY POLICY', 'Supply Mechanics'),
                const Text(
                  'For every 1 DSP you earn, an additional 1 DSP is minted for community treasuries, founders, and protocol reserves — the 1:1 Match.',
                  style: TextStyle(fontSize: 15, color: Colors.grey, height: 1.6),
                ),
                const SizedBox(height: 16),
                _buildUtilityItem(
                  LucideIcons.share2,
                  '1:1 Treasury Matching',
                  '70% Community Treasuries + 10% Founders + 10% Investors + 10% Burn.',
                ),
                _buildUtilityItem(
                  LucideIcons.flame,
                  'Dual-Burn',
                  'Equilibrium Burn (transaction fees) + Natural Burn (protocol reserve) reduce supply over time.',
                ),
                const SizedBox(height: 24),

                // 6. BILATERAL CORRIDORS
                _buildBilateralMatrix(profile),
                const SizedBox(height: 24),

                // 7. EPOCH PROGRESS
                _buildRaceTo1Billion(context),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ],
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
                    'assets/icons/logo-original.png',
                    width: 32,
                    height: 32,
                    color: Colors.orange,
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

              // Floor Price
              gdpAsync.when(
                data: (gdp) => supplyAsync.when(
                  data: (supply) {
                    final floorPrice = supply > 0 ? (gdp / supply) : 0.0;
                    final projectedPrice = floorPrice * 3.5;

                    return Column(
                      children: [
                        const Text(
                          'Floor Price',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '\$${floorPrice.toStringAsFixed(4)}',
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
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Floor Price = Total Fiat GDP ÷ DSP Supply',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
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

  // ─── VALUE CREATION SECTION ─────────────────────────────────────────
  Widget _buildValueCreationSection() {
    return Container(
      padding: AppTheme.cardPaddingEdgeInsets,
      decoration: AppTheme.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'HOW YOUR ACTIVITY CREATES VALUE',
            'Real Economy',
          ),
          const Text(
            'Every real transaction inside the app is tracked in its local fiat currency, normalized to USD, and added to our Fiat GDP — the real-world economic backbone of \$DIASPORA.',
            style: TextStyle(fontSize: 14, color: Colors.grey, height: 1.5),
          ),
        ],
      ),
    );
  }


  // ─── VALUE FLOW SECTION ─────────────────────────────────────────────
  Widget _buildValueFlowSection() {
    return Container(
      padding: AppTheme.cardPaddingEdgeInsets,
      decoration: AppTheme.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('THE VALUE FLOW', 'DSP → \$DIASPORA'),
          const Text(
            'DSP are off-chain social points you earn before the Token Generation Event (TGE). At TGE, your DSP is burned and converted into \$DIASPORA tokens on the Base blockchain.',
            style: TextStyle(fontSize: 14, color: Colors.grey, height: 1.5),
          ),
          const SizedBox(height: 20),

          // Flow Steps
          _buildFlowStep(
            '1',
            'You Earn DSP',
            'Through activities, sharing, and community engagement.',
            LucideIcons.arrowDown,
          ),
          _buildFlowStep(
            '2',
            'Fiat GDP Tracked',
            'Real purchases (flights, marketplace, stays) accumulate in Fiat GDP.',
            LucideIcons.arrowDown,
          ),
          _buildFlowStep(
            '3',
            'Floor Price Computed',
            'Floor Price = Total Fiat GDP ÷ Circulating Supply.',
            LucideIcons.arrowDown,
          ),
          _buildFlowStep(
            '4',
            'TGE: DSP → \$DIASPORA',
            'At each epoch milestone, DSP is burned and \$DIASPORA is minted on Base.',
            LucideIcons.arrowDown,
            isLast: true,
          ),
          const SizedBox(height: 16),

          // Final Note
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.info, size: 16, color: Colors.orange),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Post-TGE, \$DIASPORA becomes the exclusive medium of exchange within the app. DSP accumulation restarts each epoch for new supply.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlowStep(
    String number,
    String title,
    String description,
    IconData arrowIcon, {
    bool isLast = false,
  }) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  number,
                  style: const TextStyle(
                    color: AppTheme.accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
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
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (!isLast)
          const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildTreasuriesTab(BuildContext context, ProfileData? profile) {
    return SingleChildScrollView(
      padding: AppTheme.pagePaddingEdgeInsets.copyWith(top: 16),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildCommunityTreasuries(profile),
            // Add extra space at the bottom to ensure nothing is cut off
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(String country) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
      decoration: AppTheme.pageDecoration(context).copyWith(
        borderRadius: BorderRadius.zero,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.accentDark, AppTheme.accent],
        ),
      ),
      child: Column(
        children: [
          Image.asset(
            'assets/icons/logo-original.png',
            width: 80,
            height: 80,
            fit: BoxFit.contain,
            color: Colors.orange,
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
          const SizedBox(height: 24),
          if (!_hasRegistered)
            FilledButton(
              onPressed: _isLoading ? null : _registerInterest,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.accentDark,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Join the \$Diaspora Whitelist',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
            )
          else
            _buildMyWalletSection(context),
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
                  _buildSectionHeader('EPOCH STATUS', 'The Race to Epoch 1'),
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
                    'Upon reaching 1 Million DSP + 100 Members, Epoch 1 completes. You must meet the Genesis Gate (10,000 DSP) to qualify.',
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

    // Calculate Total Wealth for Community Earnings
    final systemTreasury = ref.watch(systemTreasuryProvider).value ?? {};
    final foundersPoints = systemTreasury['foundersPoints'] as int? ?? 0;
    // burnedPoints tracked but used downstream
    systemTreasury['burnedPoints'] as int? ?? 0;

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
    epochService.getCurrentCommunityEpoch(
      globalCumulative,
      globalMembers,
    );
    epochService.getCurrentTgeEventNumber(
      globalCumulative,
      globalMembers,
    );

    // Calculate Circulating Wealth (Post-TGE only)
    double circulatingWealth = 0;

    // 1. Community Pools (Unlocked by their specific TGE progress)
    for (var c in communities) {
      final int completedTge = epochService.getCompletedTgeEvents(
        c.cumulativeEarnings,
        c.memberCount,
      );
      final double unlockPercent = completedTge * 0.10; // 10% per TGE event
      circulatingWealth += (c.points * unlockPercent);
    }

    // 2. Founders (Unlocked by Global TGE progress)
    final int globalCompletedTge = epochService.getCompletedTgeEvents(
      globalCumulative,
      globalMembers,
    );
    final double globalUnlockPercent = globalCompletedTge * 0.10;
    circulatingWealth += (foundersPoints * globalUnlockPercent);

    // Note: Burned points are NOT in circulation, so they are excluded.

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
                                'assets/icons/logo-original.png',
                                width: 28,
                                height: 28,
                                fit: BoxFit.contain,
                                color: Colors.orange,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${NumberFormat('#,###').format(circulatingWealth.round())} \$DIASPORA',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.orange,
                                ),
                              ),
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
            defaultTitle: 'Global Community Treasury',
            subtitle: 'DDI — Community Investment Loans',
            icon: LucideIcons.globe,
            governanceType: 'Global Council Multi-sig',
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

            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _GovernanceUnitCard(
                unitId: unitId,
                communityId: community.id,
                // homeCountryCode: community.homeCountryCode, // REMOVED to force specific community display
                defaultTitle: '${community.name} Treasury',
                subtitle: 'DDI — Community Investment Loans',
                icon: community.type == 'continent'
                    ? LucideIcons.map
                    : (community.type == 'country'
                          ? LucideIcons.flag
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

            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _GovernanceUnitCard(
                unitId: unitId,
                communityId: community.id,
                defaultTitle: '${community.name} Treasury',
                subtitle: 'DDI — Community Investment Loans',
                icon: community.type == 'city'
                    ? LucideIcons.mapPin
                    : LucideIcons.map,
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
            customAvatarAsset: 'assets/icons/logo-original.png',
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: _GovernanceUnitCard(
            unitId: 'investors',
            defaultTitle: 'Investors & Partners',
            subtitle: 'Strategic Ecosystem Support',
            icon: LucideIcons.briefcase,
            governanceType: 'Institutional Allocation',
            customAvatarAsset: 'assets/icons/logo-original.png',
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
            customAvatarAsset: 'assets/icons/logo-original.png',
          ),
        ),

        const SizedBox(height: 16),
        _buildRaceTo1Billion(context),
        const SizedBox(height: 24),
        _buildLeaderSelectionInfo(),
      ],
    );
  }

  Widget _buildLeaderSelectionInfo() {
    return Container(
      padding: AppTheme.cardPaddingEdgeInsets,
      decoration: BoxDecoration(
        color: AppTheme.accentDark.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppTheme.standardBorderRadius),
      ),
      child: const Column(
        children: [
          Row(
            children: [
              Icon(LucideIcons.vote, color: AppTheme.accent, size: 20),
              SizedBox(width: 12),
              Text(
                'Democratic Selection',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            'Every community member votes to elect leaders in their Community "Council of Community Leaders", to represent their interests and these leaders are selected by their peers to oversee community funds.',
            style: TextStyle(fontSize: 13, color: Colors.blueGrey),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          const Text(
            '\$DIASPORA Token: Wealth for you. Wealth for your community.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppTheme.accent),
                foregroundColor: AppTheme.accent,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: const Text('Back to My Dashboard'),
            ),
          ),
          const SizedBox(height: 48),
        ],
      ),
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

  Widget _buildUtilityItem(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.accent, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyWalletSection(BuildContext context) {
    bool hasWallet = _walletController.text.isNotEmpty;
    bool showInput = !hasWallet || _isEditingWallet;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(20),
      // White background with slight opacity to blend with Hero gradient
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(
                    LucideIcons.wallet,
                    color: Colors.white,
                  ), // White for Hero contrast
                  SizedBox(width: 12),
                  Text(
                    'My Wallet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              if (hasWallet && !showInput)
                IconButton(
                  icon: const Icon(
                    LucideIcons.edit2,
                    color: Colors.white70,
                    size: 18,
                  ),
                  onPressed: () => setState(() => _isEditingWallet = true),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Edit Address',
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'Connect your wallet or create new to receive \$DIASPORA Token payout.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.white70),
            ),
          ),
          const SizedBox(height: 20),

          // Metamask/Base Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _launchURL('https://metamask.io/download/'),
                  icon: const Icon(LucideIcons.link, size: 16),
                  label: const Text('MetaMask'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _launchURL('https://keys.coinbase.com/onboarding'),
                  icon: const Icon(LucideIcons.circle, size: 16),
                  label: const Text('Base'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (showInput) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                // Using app logo orange for the input container
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.5),
                  width: 2,
                ),
              ),
              child: TextField(
                controller: _walletController,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  filled: false, // Ensure no background fill
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                  hintText: 'Enter Wallet Address (0x...)',
                  hintStyle: TextStyle(fontSize: 13, color: Colors.white54),
                ),
                // Style text with orange and bold as requested
                style: const TextStyle(
                  color: Colors.orange,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
                onChanged: (_) {
                  if (!_isEditingWallet) {
                    setState(() => _isEditingWallet = true);
                  }
                },
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isSavingWallet ? null : _saveWalletAddress,
                style: FilledButton.styleFrom(
                  backgroundColor:
                      AppTheme.accentDark, // Dark accent for button
                  foregroundColor: Colors.white,
                ),
                child: _isSavingWallet
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Secure Your Whitelist Spot'),
              ),
            ),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              // Removed the black background (Colors.black.withValues(alpha: 0.2))
              // and replaced it with a subtle white transparent bg.
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Text(
                _walletController.text,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 12),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  LucideIcons.checkCircle,
                  color: Colors.lightGreenAccent,
                  size: 16,
                ),
                SizedBox(width: 8),
                Text(
                  'Ready for \$Diaspora TGE',
                  style: TextStyle(
                    color: Colors.lightGreenAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTokenTransactionsSection(BuildContext context, String userId) {
    if (userId.isEmpty) return const SizedBox.shrink();

    final transactionsAsync = ref.watch(userTransactionsProvider(userId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('TGE LEDGER', 'Blockchain Transactions'),
        Container(
          padding: AppTheme.cardPaddingEdgeInsets,
          decoration: AppTheme.cardDecoration(context),
          child: transactionsAsync.when(
            data: (transactions) {
              final userPoints = ref.watch(userPointsProvider(userId)).value;
              final List<_BlockchainEvent> activities = [];
              // 1. Add Filtered Transactions (On-chain/Token only)
              for (final tx in transactions) {
                final action = tx.action.toLowerCase();
                final isTokenAsset = tx.metadata?['assetType'] == 'token';
                final isOnChain = tx.metadata?['onChain'] == true;
                final isTgeSpecific =
                    action.contains('tge') || action.contains('distribution');

                // Final Check: MUST be a token asset, or the action must be a TGE distribution, or explicitly on-chain
                if (isTokenAsset || isOnChain || isTgeSpecific) {
                  // Final sanity check: exclude anything that looks like a point reward even if tagged weirdly
                  final isReward =
                      action.contains('reward') ||
                      action.contains('bonus') ||
                      action.contains('streak');
                  if (isReward && !isTgeSpecific) continue;

                  activities.add(
                    _BlockchainEvent(
                      title: tx.displayAction,
                      timestamp: tx.timestamp,
                      amount: tx.points.toDouble(),
                      isPositive: tx.points >= 0,
                    ),
                  );
                }
              }

              // 2. Add TGE Distributions from History
              if (userPoints != null) {
                for (final record in userPoints.tgeHistory) {
                  activities.add(
                    _BlockchainEvent(
                      title:
                          'Epoch ${record.epoch} TGE ${record.tgeNumber} Distribution',
                      timestamp: record.date,
                      amount: record.amount,
                      isPositive: record.amount >= 0,
                      subtitle:
                          'Efficiency: ${(record.efficiency * 100).toStringAsFixed(1)}%',
                    ),
                  );
                }
              }

              // 3. Sort by date descending
              activities.sort((a, b) => b.timestamp.compareTo(a.timestamp));

              if (activities.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(
                    child: Text(
                      'No blockchain activities recorded yet.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: min(activities.length, 10), // Show top 10
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final act = activities[index];
                  final sign = act.isPositive ? '+' : '';
                  final color = act.isPositive ? Colors.green : Colors.red;

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        act.isPositive
                            ? LucideIcons.arrowDownLeft
                            : LucideIcons.arrowUpRight,
                        color: color,
                        size: 16,
                      ),
                    ),
                    title: Text(
                      act.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      act.subtitle ??
                          DateFormat.yMMMd().add_jm().format(
                            act.timestamp.toLocal(),
                          ),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    trailing: Text(
                      '$sign${NumberFormat('#,###').format(act.amount)} \$DIASPORA',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color,
                        fontSize: 14,
                      ),
                    ),
                  );
                },
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, stack) => Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Text(
                  'Error: $err',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
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
    final unitAsync = ref
        .watch(governanceRepositoryProvider)
        .watchGovernanceUnit(unitId);

    // [SYSTEM RESERVES] System stats available via systemTreasuryProvider if needed

    final communityAsync = communityId != null
        ? ref.watch(communityProvider(communityId!))
        : const AsyncValue<Community?>.data(null);

    return StreamBuilder<GovernanceUnit?>(
      stream: unitAsync,
      builder: (context, snapshot) {
        final unit = snapshot.data;

        // Pre-TGE: token balance is 0 for all treasuries
        // After TGE, this will read from blockchain wallet balance
        const String balance = '0';
        final bool isSystemReserve =
            unitId == 'founders' || unitId == 'investors' || unitId == 'burn';

        return communityAsync.when(
          data: (community) {
            final cleanName = community?.name
                .replaceAll('Community', '')
                .replaceAll('Treasury', '')
                .trim();
            final title = cleanName != null && cleanName.isNotEmpty
                ? '$cleanName Community Treasury'
                : defaultTitle;

            final walletAddr = unit?.walletAddress;

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
                                    'assets/icons/logo-original.png',
                                    width: 28,
                                    height: 28,
                                    fit: BoxFit.contain,
                                    color: Colors.orange,
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    '$balance \$DIASPORA',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Colors.orange,
                                    ),
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
                    if (walletAddr != null && walletAddr.isNotEmpty) ...[
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
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => _buildErrorCard(context, defaultTitle),
        );
      },
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

class _BlockchainEvent {
  final String title;
  final String? subtitle;
  final DateTime timestamp;
  final double amount;
  final bool isPositive;

  _BlockchainEvent({
    required this.title,
    this.subtitle,
    required this.timestamp,
    required this.amount,
    required this.isPositive,
  });
}
