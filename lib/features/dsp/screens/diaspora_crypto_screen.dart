import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'dart:async';
import 'dart:math';
import 'package:diaspora_nearby/features/profile/screens/user_profile_screen.dart';
import 'package:diaspora_nearby/core/data/countries.dart' hide getContinentByCountryCode;
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/dsp/repository/interest_repository.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import 'package:intl/intl.dart';
import 'package:diaspora_nearby/features/governance/repository/governance_repository.dart';
import 'package:diaspora_nearby/features/governance/services/governance_service.dart';
import 'package:diaspora_nearby/features/governance/screens/leader_selection_screen.dart';
import 'package:diaspora_nearby/features/governance/models/governance_unit.dart';
import 'package:diaspora_nearby/features/governance/screens/active_elections_screen.dart';
import 'package:diaspora_nearby/features/governance/screens/election_history_screen.dart';
import 'package:diaspora_nearby/features/community/repository/community_repository.dart';
import 'package:diaspora_nearby/features/community/models/community_data.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/chat/utils/community_chat_utils.dart';
import 'package:diaspora_nearby/core/utils/location_utils.dart';
import 'package:diaspora_nearby/features/dsp/screens/gvi_corridor_list_screen.dart';

class DiasporaCryptoScreen extends ConsumerStatefulWidget {
  const DiasporaCryptoScreen({super.key});

  @override
  ConsumerState<DiasporaCryptoScreen> createState() =>
      _DiasporaCryptoScreenState();
}

class _DiasporaCryptoScreenState extends ConsumerState<DiasporaCryptoScreen> {
  bool _isLoading = false;
  bool _hasRegistered = false;
  
  final TextEditingController _walletController = TextEditingController();
  bool _isSavingWallet = false;
  bool _isEditingWallet = false;

  // GVI Simulation State
  double _gviValue = 1.42;
  double _gviTrend = 4.2;
  bool _gviIsUp = true;
  Timer? _gviTimer;
  Timer? _corridorTimer;
  final Random _random = Random();
  final Map<String, double> _corridorGvis = {};
  final Map<String, bool> _corridorTrendUp = {};

  @override
  void initState() {
    super.initState();
    _checkStatus();
    _loadWalletData();
    _startGviSimulation();
    // Trigger governance election checks on load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(governanceServiceProvider).checkAndTriggerElections();
    });
  }

  void _startGviSimulation() {
    // Global GVI: 500ms updates
    _gviTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (mounted) {
        setState(() {
          final changeAmount = (_random.nextDouble() * 0.09 + 0.01);
          _gviIsUp = _random.nextBool();
          
          if (_gviIsUp) {
            _gviValue += changeAmount;
            _gviTrend = changeAmount * 100;
          } else {
            _gviValue -= changeAmount;
            _gviTrend = changeAmount * 100;
          }
          _gviValue = _gviValue.clamp(1.10, 1.80);
        });
      }
    });

    // Individual Corridors: 1s updates
    _corridorTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          for (final key in _corridorGvis.keys) {
            final change = (_random.nextDouble() * 0.09 + 0.01);
            final up = _random.nextBool();
            _corridorTrendUp[key] = up;
            if (up) {
              _corridorGvis[key] = (_corridorGvis[key]! + change).clamp(1.10, 1.80);
            } else {
              _corridorGvis[key] = (_corridorGvis[key]! - change).clamp(1.10, 1.80);
            }
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _walletController.dispose();
    _gviTimer?.cancel();
    _corridorTimer?.cancel();
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

    final userPoints = await ref.read(pointsRepositoryProvider).getUserPoints(user.uid);
    if (userPoints?.walletAddress != null) {
      _walletController.text = userPoints!.walletAddress!;
    }
  }

  Future<void> _saveWalletAddress() async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null) return;
    
    setState(() => _isSavingWallet = true);
    
    try {
      await ref.read(pointsRepositoryProvider).updateWalletAddress(
        user.uid, 
        _walletController.text.trim(),
      );
      
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
         ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving wallet: $e')),
        );
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
        title: const Text('\$DIASPORA Token Ecosystem', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.accentDark,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            // --- Tab Bar ---
            Container(
              color: AppTheme.accentDark,
              child: TabBar(
                indicatorColor: Colors.orange,
                indicatorWeight: 3,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                tabs: const [
                  Tab(text: 'DASHBOARD'),
                  Tab(text: 'TOKENOMICS'),
                  Tab(text: 'TREASURIES'),
                ],
              ),
            ),
            
            // --- Tab Content ---
            Expanded(
              child: TabBarView(
                children: [
                  _buildDashboardTab(context, country),
                  _buildTokenomicsTab(context, country, profile),
                  _buildTreasuriesTab(context, profile),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardTab(BuildContext context, String country) {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildHero(country),
          _buildFooter(context),
        ],
      ),
    );
  }

  Widget _buildTokenomicsTab(BuildContext context, String country, ProfileData? profile) {
    return SingleChildScrollView(
      padding: AppTheme.pagePaddingEdgeInsets.copyWith(top: 16, bottom: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildGviDashboard(country),
          const SizedBox(height: AppTheme.elementSpacing),
          _buildBilateralMatrix(profile),
          const SizedBox(height: 24),
          _buildSectionHeader('THE ASSET', '\$DSP Token'),
          const Text(
            '\$DSP is a sovereign hard asset engineered for the 1.5 billion global Diaspora. It provides the decentralized stable value transfer and storage infrastructure required for communal economic autonomy.',
            style: TextStyle(fontSize: 16, color: Colors.grey, height: 1.6),
          ),
          const SizedBox(height: 32),
          
          _buildSectionHeader('THE TRUST ENGINE', 'PoCT V3.1'),
          const Text(
            'Proof of Community Trust (PoCT) replaces credit scores with Social Collateral. Your trust score is an automated calculation based on five technical modules: Identity, Activity, Reliability, Helpfulness, and Reputation.',
            style: TextStyle(fontSize: 16, color: Colors.grey, height: 1.6),
          ),
          const SizedBox(height: 16),
          _buildUtilityItem(LucideIcons.shieldCheck, '10/10 Verification Rule', 'Genesis verification requires 10 family connections and 10 unrelated QR exchanges.'),
          _buildUtilityItem(LucideIcons.zap, 'Socio-Slashing', 'Fraud triggers a Trust Cascade, penalizing the actor and their vouchers to protect the ecosystem.'),
          const SizedBox(height: 32),

          _buildSectionHeader('MONETARY POLICY', 'Sigmoid Stability'),
          const Text(
            'Algorithmic scarcity and instant liquidity are provided through the Sigmoid Bonding Curve AMM.',
            style: TextStyle(fontSize: 16, color: Colors.grey, height: 1.6),
          ),
          const SizedBox(height: 16),
          _buildUtilityItem(LucideIcons.trendingUp, 'Sigmoid AMM', 'Permanent 24/7 liquidity pool that dampens volatility and ensures a mathematical price floor.'),
          _buildUtilityItem(LucideIcons.flame, 'Dual-Burn Strategy', 'Equilibrium Burn (Tx fees) + Natural Burn (Conversion Efficiency) ensure long-term value preservation.'),
          const SizedBox(height: 32),

          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              children: [
                Icon(LucideIcons.database, size: 48, color: AppTheme.accent),
                const SizedBox(height: 16),
                Text(
                  'Stable Value Infrastructure',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  'By anchoring value to the economic reality of trade and remittances, \$DSP creates a frictionless, global stable value transfer and storage infrastructure for our people.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.blueGrey, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          
          _buildSectionHeader('GVI ANCHORS', 'Bilateral Corridors'),
          _buildGviExplanation(),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildTreasuriesTab(BuildContext context, ProfileData? profile) {
    return SingleChildScrollView(
      padding: AppTheme.pagePaddingEdgeInsets.copyWith(top: 16, bottom: 48),
      child: Column(
        children: [
          _buildInstitutionalTreasuries(profile),
        ],
      ),
    );
  }

  Widget _buildHero(String country) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
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
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: _isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Join the \$Diaspora Whitelist', style: TextStyle(fontWeight: FontWeight.bold)),
            )
          else
            _buildWalletSection(country),
        ],
      ),
    );
  }

  Widget _buildBilateralMatrix(ProfileData? profile) {
    final country = profile?.homeCountry ?? 'Home Country';
    final countryCode = profile?.homeCountryCode ?? 'TZ';
    final homeFlag = getCountryByCode(countryCode)?.flag ?? '🇹🇿';
    
    // Bilateral GVI Matrix: Mapping anchor country connections to key diaspora hubs
    final List<Map<String, dynamic>> allCorridors = [
      {'target': 'United Kingdom', 'flag': '🇬🇧', 'gvi': 1.48, 'status': 'Stable'},
      {'target': 'United States', 'flag': '🇺🇸', 'gvi': 1.52, 'status': 'High Liquidity'},
      {'target': 'United Arab Emirates', 'flag': '🇦🇪', 'gvi': 1.39, 'status': 'Rising'},
      {'target': 'South Africa', 'flag': '🇿🇦', 'gvi': 1.35, 'status': 'Stable'},
      {'target': 'Canada', 'flag': '🇨🇦', 'gvi': 1.41, 'status': 'Stable'},
      {'target': 'Germany', 'flag': '🇩🇪', 'gvi': 1.38, 'status': 'Growing'},
      {'target': 'Kenya', 'flag': '🇰🇪', 'gvi': 1.25, 'status': 'Active'},
      {'target': 'Rwanda', 'flag': '🇷🇼', 'gvi': 1.18, 'status': 'Stable'},
      {'target': 'India', 'flag': '🇮🇳', 'gvi': 1.32, 'status': 'Stable'},
      {'target': 'Nigeria', 'flag': '🇳🇬', 'gvi': 1.45, 'status': 'High Vol.'},
      {'target': 'Uganda', 'flag': '🇺🇬', 'gvi': 1.15, 'status': 'Active'},
      {'target': 'Ghana', 'flag': '🇬🇭', 'gvi': 1.22, 'status': 'Emerging'},
    ];

    // Initialize simulation state for these corridors if not already done
    for (var corridor in allCorridors) {
      final name = corridor['target'] as String;
      if (!_corridorGvis.containsKey(name)) {
        _corridorGvis[name] = corridor['gvi'] as double;
        _corridorTrendUp[name] = true;
      }
    }

    final corridors = allCorridors
        .where((c) => c['target'] != (profile?.homeCountry ?? ''))
        .take(10)
        .toList();

    return Container(
      padding: AppTheme.cardPaddingEdgeInsets,
      decoration: BoxDecoration(
        color: AppTheme.accentDark.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppTheme.standardBorderRadius),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(homeFlag, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              const Text('BILATERAL GVI MATRIX', 
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
            ],
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(1),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(1),
              },
              children: [
                TableRow(
                  children: [
                    _buildMatrixHeader('CORRIDOR'),
                    _buildMatrixHeader('GVI', center: true),
                    _buildMatrixHeader('STATUS', alignRight: true),
                  ],
                ),
                  ...corridors.map((c) {
                    final name = c['target'] as String;
                    final gviValue = _corridorGvis[name] ?? c['gvi'] as double;
                    final isUp = _corridorTrendUp[name] ?? true;
                    
                    return TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text('${c['flag']} $name', 
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(gviValue.toStringAsFixed(2), 
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12, 
                              fontWeight: FontWeight.bold, 
                              color: isUp ? AppTheme.accent : Colors.redAccent,
                            )),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(c['status'], 
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 10, color: Colors.blueGrey)),
                        ),
                      ],
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => GviCorridorListScreen(homeCountry: country),
                  ),
                );
              },
              child: const Text('View Full GVI Corridor List', 
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.accent)),
            ),
          ),
          const Text(
            'Matrix reflects bilateral algorithmic clearing efficiency between sovereignty centers.',
            style: TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _buildMatrixHeader(String label, {bool alignRight = false, bool center = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(label, 
        textAlign: center ? TextAlign.center : (alignRight ? TextAlign.right : TextAlign.left),
        style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildGviDashboard(String country) {
    return Container(
      padding: AppTheme.cardPaddingEdgeInsets,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppTheme.standardBorderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('LIVE GVI STATUS',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2)),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_gviValue.toStringAsFixed(2),
                          style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.accent)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                            color: (_gviIsUp ? Colors.green : Colors.red).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4)),
                        child: Row(
                          children: [
                            Icon(
                                _gviIsUp
                                    ? LucideIcons.trendingUp
                                    : LucideIcons.trendingDown,
                                color: _gviIsUp ? Colors.green : Colors.red,
                                size: 12),
                            const SizedBox(width: 2),
                            Text('${_gviIsUp ? "+" : "-"}${_gviTrend.toStringAsFixed(1)}%',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: _gviIsUp ? Colors.green : Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Icon(LucideIcons.activity,
                  color: AppTheme.accent, size: 32),
            ],
          ),
          const Divider(height: 32),
          _buildGviMetric('Trade Settlements', 'Bilateral Trade Flow', 0.85),
          const SizedBox(height: 16),
          _buildGviMetric(
              'Remittances', 'Remittance Velocity', 0.92),
          const SizedBox(height: 16),
          _buildGviMetric(
              'Fiat Pair Parity - Forex', 'Forex Market Resilience', 0.74),
          const SizedBox(height: 24),
          Text(
            'Anchor value includes P2P, B2C, and B2B flows.',
            style: TextStyle(
                fontSize: 11,
                color: Colors.grey.withAlpha(204),
                fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _buildGviMetric(String label, String subtitle, double value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 6,
            backgroundColor: Colors.grey.withOpacity(0.1),
            valueColor: const AlwaysStoppedAnimation(AppTheme.accent),
          ),
        ),
      ],
    );
  }

  Widget _buildGviExplanation() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.accent.withOpacity(0.1)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _buildGviLayer(LucideIcons.container, 'Trade Settlements', 'Commercial settlement volumes across corridors.'),
          const Divider(height: 32),
          _buildGviLayer(LucideIcons.send, 'Remittances', 'Recurring p2p value transfer velocity.'),
          const Divider(height: 32),
          _buildGviLayer(LucideIcons.lineChart, 'Fiat Pair Parity - Forex', 'Stabilizing against hyper-inflationary local currencies.'),
        ],
      ),
    );
  }

  Widget _buildGviLayer(IconData icon, String title, String desc) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.accent, size: 24),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 2),
              Text(desc, style: const TextStyle(color: Colors.grey, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWalletSection(String country) {
    bool hasWallet = _walletController.text.isNotEmpty;
    bool showInput = !hasWallet || _isEditingWallet;
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(LucideIcons.wallet, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  showInput ? 'Connect Your \$Diaspora Wallet' : 'Your Connected Wallet',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              if (hasWallet && !showInput)
                 IconButton(
                   icon: const Icon(LucideIcons.edit2, color: Colors.white70, size: 16),
                   onPressed: () => setState(() => _isEditingWallet = true),
                   padding: EdgeInsets.zero,
                   constraints: const BoxConstraints(),
                 )
            ],
          ),
          const SizedBox(height: 12),
          if (showInput) ...[
             Container(
               padding: const EdgeInsets.symmetric(horizontal: 16),
               decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
               child: TextField(
                 controller: _walletController,
                 decoration: const InputDecoration(border: InputBorder.none, hintText: 'Enter Wallet Address', hintStyle: TextStyle(fontSize: 13, color: Colors.black38)),
                 style: const TextStyle(color: Colors.black87, fontSize: 14),
               ),
             ),
             const SizedBox(height: 12),
             SizedBox(
               width: double.infinity,
               child: FilledButton(
                 onPressed: _isSavingWallet ? null : _saveWalletAddress,
                 style: FilledButton.styleFrom(backgroundColor: AppTheme.accentDark, foregroundColor: Colors.white),
                 child: _isSavingWallet
                     ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                     : const Text('Secure Your Whitelist Spot'),
               ),
             ),
          ] else ...[
             Container(
               width: double.infinity,
               padding: const EdgeInsets.all(12),
               decoration: BoxDecoration(color: Colors.black.withOpacity(0.2), borderRadius: BorderRadius.circular(16)),
               child: Text(_walletController.text, style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
             ),
             const SizedBox(height: 8),
             const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   Icon(LucideIcons.checkCircle, color: Colors.lightGreenAccent, size: 14),
                   SizedBox(width: 4),
                   Text('Ready for \$Diaspora TGE', style: TextStyle(color: Colors.lightGreenAccent, fontSize: 12)),
                ],
             ),
          ]
        ],
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
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.accent.withOpacity(0.1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _buildSectionHeader('EPOCH STATUS', 'The Race to Epoch 1'),
                  const SizedBox(height: 16),
                  Text('${NumberFormat('#,###').format(totalMinted)} / 1,000,000 DSP', style: const TextStyle(fontSize: 16, color: AppTheme.accent, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: LinearProgressIndicator(value: progress, minHeight: 12, backgroundColor: Colors.black12, color: AppTheme.accent),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Upon reaching 1 Million DSP + 100 Members, Epoch 1 completes. You must meet the Genesis Gate (10,000 DSP + 51 Trust Score) to qualify.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        );
      },
    );
  }

  Widget _buildInstitutionalTreasuries(ProfileData? profile) {
    final country = profile?.homeCountry ?? 'Home Country';
    final countryCode = profile?.homeCountryCode ?? 'TZ';
    
    // Generate Community IDs for visual consistency
    final countryCommunityId = 'home_country_${countryCode.toLowerCase()}';
    
    final continentCode = getContinentByCountryCode(countryCode);
    final continentName = getContinentName(continentCode);
    final continentCommunityId = 'home_continent_${continentName.toLowerCase().replaceAll(' ', '-')}';
    
    const globalCommunityId = 'global_community';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('INSTITUTIONAL TREASURIES', 'Sovereign Reserves'),
        const Text(
          'Security First: Institutional wallets are multi-sig accounts overseen by elected Leaders and funded by the 50/50 sovereign split.',
          style: TextStyle(fontSize: 14, color: Colors.blueGrey, fontStyle: FontStyle.italic),
        ),
        const SizedBox(height: 24),
        
        _GovernanceUnitCard(
          unitId: 'country_${countryCode.toLowerCase()}',
          communityId: countryCommunityId,
          homeCountryCode: countryCode,
          defaultTitle: '$country Community Treasury',
          subtitle: 'Home Country Development (10%)',
          icon: LucideIcons.flag,
          governanceType: 'Leader Multi-sig',
        ),
        
        const SizedBox(height: 16),
        
        _GovernanceUnitCard(
          unitId: 'continent_${continentName.toLowerCase()}', 
          communityId: continentCommunityId,
          defaultTitle: '$continentName Continent Treasury',
          subtitle: 'Regional Infrastructure (10%)',
          icon: LucideIcons.map,
          governanceType: 'Leader Multi-sig',
        ),
        
        const SizedBox(height: 16),
        
        _GovernanceUnitCard(
          unitId: 'ecosystem',
          communityId: null,
          defaultTitle: 'Global Ecosystem Treasury',
          subtitle: 'Protocol Maintenance & R&D (10%)',
          icon: LucideIcons.layers,
          governanceType: 'Leader Multi-sig',
        ),

        const SizedBox(height: 16),
        
        _GovernanceUnitCard(
          unitId: 'emergencies_fund',
          communityId: null,
          defaultTitle: 'Emergencies Fund',
          subtitle: 'Medical, Legal, Repatriation (10%)',
          icon: LucideIcons.heartHandshake,
          governanceType: 'Council Multi-sig',
        ),
        
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
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(LucideIcons.vote, color: AppTheme.accent, size: 20),
              SizedBox(width: 12),
              Text(
                'Democratic Selection',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Selection Mechanism: Every community member votes to elect Leaders who represent their interests and hold treasury mandates.',
            style: TextStyle(fontSize: 13, color: Colors.blueGrey),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ActiveElectionsScreen()),
              );
            },
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppTheme.accent),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('View Active Leader Elections'),
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
            '\$Diaspora Token: Wealth for You. Wealth for Home.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.accentDark),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
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
        Text(subtitle.toUpperCase(), style: const TextStyle(color: AppTheme.accent, letterSpacing: 1.2, fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 4),
        Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
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
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(desc, style: const TextStyle(color: Colors.grey, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GovernanceUnitCard extends ConsumerWidget {
  final String unitId;
  final String? communityId;
  final String? homeCountryCode;
  final String defaultTitle;
  final String subtitle;
  final IconData icon;
  final String governanceType;

  const _GovernanceUnitCard({
    required this.unitId,
    this.communityId,
    this.homeCountryCode,
    required this.defaultTitle,
    required this.subtitle,
    required this.icon,
    required this.governanceType,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unitAsync = ref.watch(governanceRepositoryProvider).watchGovernanceUnit(unitId);
    
    // Prioritize homeCountryCode provider if available
    final communityAsync = homeCountryCode != null 
        ? ref.watch(homeCountryCommunityProvider(homeCountryCode!))
        : (communityId != null 
            ? ref.watch(communityProvider(communityId!))
            : const AsyncValue<Community?>.data(null));

    return StreamBuilder<GovernanceUnit?>(
      stream: unitAsync,
      builder: (context, snapshot) {
        final unit = snapshot.data;
        final signers = unit?.signers ?? ['Awaiting Election'];
        final balance = unit != null ? NumberFormat('#,###').format(unit.treasuryBalance) : '0';

        return communityAsync.when(
          data: (community) {
            final cleanName = community?.name
                .replaceAll('Community', '')
                .replaceAll('Treasury', '')
                .trim();
            final title = cleanName != null && cleanName.isNotEmpty
                ? '$cleanName Community Treasury'
                : defaultTitle;

            return Container(
              padding: AppTheme.cardPaddingEdgeInsets,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(AppTheme.standardBorderRadius),
                border: Border.all(color: AppTheme.accent.withValues(alpha: 0.1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
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
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                                  '$balance \$Diaspora', 
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold, 
                                    fontSize: 13, 
                                    color: AppTheme.accentDark,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (governanceType.isNotEmpty)
                              Text(
                                governanceType.toUpperCase(), 
                                style: const TextStyle(
                                  fontSize: 10, 
                                  color: Colors.grey, 
                                  fontWeight: FontWeight.bold, 
                                  letterSpacing: 1.1,
                                ),
                              ),
                            if (governanceType.isNotEmpty)
                              const SizedBox(height: 4),
                            const Text(
                              'Multi-Sig Wallet Signatories', 
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.history, size: 20, color: Colors.grey),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ElectionHistoryScreen(
                                unitId: unitId,
                                unitName: title,
                              ),
                            ),
                          );
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),

                  if (unit?.isActiveElection == true) ...[
                    _buildVoteButton(context, unitId, community: community),
                    const SizedBox(height: 12),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: signers.map((signer) {
                      if (signer == 'Awaiting Election') {
                         return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.accent.withOpacity(0.2)),
                          ),
                          child: Text(
                            signer,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.accentDark),
                          ),
                        );
                      }
                      
                      // For actual user IDs, fetch profile and show flag + name
                      return _SignerChip(userId: signer);
                    }).toList(),
                  ),
                ],
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
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withOpacity(0.1)),
      ),
      child: Text('Error loading $title'),
    );
  }

  Widget _buildVoteButton(BuildContext context, String id, {Community? community}) {
    return ElevatedButton(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => LeaderSelectionScreen(unitId: id, community: community)),
        );
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.accent,
      ),
      child: const Text('Vote Now', style: TextStyle(color: Colors.white)),
    );
  }
}

class _SignerChip extends ConsumerWidget {
  final String userId;
  
  const _SignerChip({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileByIdProvider(userId));
    
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => UserProfileScreen(userId: userId)),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.accent.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.accent.withOpacity(0.2)),
        ),
        child: profileAsync.when(
          data: (profile) {
            if (profile == null) return const SizedBox.shrink();
            final country = getCountryByCode(profile.homeCountryCode ?? 'TZ');
            final flag = country?.flag ?? '🇹🇿';
            final name = profile.firstName.isNotEmpty ? profile.firstName : 'User';
            
            return Text(
              '$flag $name',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.accentDark),
            );
          },
          loading: () => const SizedBox(
            width: 10, height: 10, 
            child: CircularProgressIndicator(strokeWidth: 1)
          ),
          error: (_, __) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}


