import 'package:flutter/material.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:diaspora_nearby/features/chat/utils/community_chat_utils.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/dsp/models/user_points.dart';
import 'package:diaspora_nearby/features/dsp/models/points_transaction.dart';
import 'package:diaspora_nearby/features/trust/models/trust_data.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/community/repository/community_repository.dart';
import 'countries_leaderboard_screen.dart';
import 'package:diaspora_nearby/features/dsp/widgets/country_leaderboard_item.dart';
import 'package:diaspora_nearby/features/dsp/services/exploration_registry.dart';
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart';
import 'package:diaspora_nearby/features/dsp/services/epoch_service.dart';

final referralStatsProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, userId) {
      return ref.read(pointsRepositoryProvider).getReferralStats(userId);
    });

// [FIX] StreamProvider to prevent flickering
final userPointsStreamProvider = StreamProvider.family
    .autoDispose<UserPoints?, String>((ref, userId) {
      return ref.read(pointsRepositoryProvider).streamUserPoints(userId);
    });

// Verified fields provider for detailed trust dashboard
final verifiedFieldsProvider = FutureProvider.family<Set<String>, String>((
  ref,
  userId,
) {
  return ref.read(trustServiceProvider).getVerifiedFields(userId);
});

// [NEW] Stream provider for profile data to track completion progress
final userProfileStreamProvider = StreamProvider.family
    .autoDispose<ProfileData?, String>((ref, userId) {
      return ref.read(profileRepositoryProvider).watchProfile(userId);
    });

final globalSupplyProvider = StreamProvider<int>((ref) {
  return ref.watch(pointsRepositoryProvider).streamGlobalSupply();
});

// [FIX] Provider for transactions to prevent stream recreation/flickering on rebuilds
final recentTransactionsProvider = StreamProvider.family
    .autoDispose<List<PointsTransaction>, String>((ref, userId) {
      return ref
          .watch(pointsRepositoryProvider)
          .streamTransactionHistory(userId, limit: 10);
    });

class PointsSystemScreen extends ConsumerStatefulWidget {
  const PointsSystemScreen({super.key});

  @override
  ConsumerState<PointsSystemScreen> createState() => _PointsSystemScreenState();
}

class _PointsSystemScreenState extends ConsumerState<PointsSystemScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabSelection);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndGenerateCode();
      // Track initial tab
      _trackExploration(ExplorationAction.dspDashboard);
    });
    _syncCommunities();
  }

  void _handleTabSelection() {
    if (!_tabController.indexIsChanging) {
      if (_tabController.index == 0) {
        _trackExploration(ExplorationAction.dspDashboard);
      } else if (_tabController.index == 1) {
        _trackExploration(ExplorationAction.dspPoA);
      } else if (_tabController.index == 2) {
        _trackExploration(ExplorationAction.dspPoCT);
      }
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _syncCommunities() async {
    final userId = ref.read(authRepositoryProvider).currentUser?.uid;
    if (userId == null) return;
    await ref.read(communityRepositoryProvider).syncUserCommunities(userId);
  }

  Future<void> _checkAndGenerateCode() async {
    final userId = ref.read(authRepositoryProvider).currentUser?.uid;
    if (userId == null) return;

    final stats = await ref
        .read(pointsRepositoryProvider)
        .getReferralStats(userId);
    if (stats == null) {
      final profile = await ref
          .read(profileRepositoryProvider)
          .getUserProfile(userId);
      if (profile != null) {
        final firstName = profile.firstName;
        final countryCode = profile.homeLocation.countryCode ?? 'TZ';
        await ref
            .read(pointsRepositoryProvider)
            .generateReferralCode(userId, firstName, countryCode);
        if (mounted) {
          ref.invalidate(referralStatsProvider(userId));
        }
      }
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authRepositoryProvider).currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final userId = user.uid;
    // [FIX] Watch referral stats async
    final trustDataAsync = ref.watch(userTrustProvider(userId));
    final referralStatsAsync = ref.watch(referralStatsProvider(userId));
    // [FIX] Watch transactions async
    final transactionsAsync = ref.watch(recentTransactionsProvider(userId));

    // [NEW] Watch profile stream
    final userProfileAsync = ref.watch(userProfileStreamProvider(userId));
    final userPointsValue = ref.watch(userPointsStreamProvider(userId));

    return Scaffold(
      backgroundColor: Theme.of(
        context,
      ).scaffoldBackgroundColor, // Use theme background
      appBar: AppBar(
        backgroundColor: const Color(
          0xFF2D5A47,
        ), // Keep Hero Sage for brand identity
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        title: const Text(
          'DSP - Diaspora Social Points',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Container(
        decoration: AppTheme.pageDecoration(context),
        child: userPointsValue.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(child: Text('Error: $err')),
          data: (userPoints) {
            // [FIX] Show page even if no points data - display 0 values
            final displayPoints =
                userPoints ??
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
                  tgeHistory: const [],
                );

            return Column(
              children: [
                // --- Tab Bar ---
                Container(
                  color: const Color(0xFF2D5A47),
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: AppTheme.accent,
                    indicatorWeight: 3,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white60,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    tabs: const [
                      Tab(text: 'DASHBOARD'),
                      Tab(text: 'PoA'),
                      Tab(text: 'PoCT'),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildDashboardTab(
                        context,
                        displayPoints,
                        trustDataAsync,
                        referralStatsAsync,
                        transactionsAsync,
                      ),
                      _buildPoATab(
                        context,
                        displayPoints,
                        displayPoints.lifetimeEarnings,
                      ),
                      _buildPoCTTab(
                        context,
                        displayPoints,
                        trustDataAsync,
                        userProfileAsync,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // --- TAB 1: DASHBOARD ---
  Widget _buildDashboardTab(
    BuildContext context,
    UserPoints userPoints,
    AsyncValue<TrustData?> trustDataAsync,
    AsyncValue<Map<String, dynamic>?> referralStatsAsync,
    AsyncValue<List<PointsTransaction>> transactionsAsync,
  ) {
    return RefreshIndicator(
      onRefresh: () async {
        _trackExploration(ExplorationAction.dspSyncTreasury);
        final userId = ref.read(authRepositoryProvider).currentUser?.uid;
        if (userId != null) {
          await ref
              .read(communityRepositoryProvider)
              .syncUserCommunities(userId);
          // TODO: Fix this provider, it's not defined in this file.
          // ref.invalidate(userCommunitiesStreamProvider(userId));
        }
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.pageHorizontalPadding,
        ),
        physics: const AlwaysScrollableScrollPhysics(),
        child: SafeArea(
          top: false,
          bottom: true, // [FIX] Add bottom safe area
          child: Column(
            children: [
              // Dashboard Body
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Builder(
                    builder: (context) {
                      final trustData = trustDataAsync.value;
                      return _buildBalanceSummary(
                        context,
                        userPoints,
                        trustData?.trustScore ?? 0.0,
                        trustData?.uniqueQrCount ?? 0,
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  // Activity Earnings DSP Distribution
                  _buildSectionHeader(
                    'ACTIVITY EARNINGS DSP DISTRIBUTION',
                    'Community & System Treasuries',
                  ),
                  const SizedBox(height: 8),
                  _buildEcosystemWalletsSection(),
                  const SizedBox(height: 32),

                  // Race to 1 Billion (Epoch 1)
                  // Race to 1 Trillion Scale
                  _buildPlatformStatusCard(context),

                  // Current Epoch Details
                  Builder(
                    builder: (context) {
                      final qr = trustDataAsync.value?.uniqueQrCount ?? 0;
                      return _buildEpochDetailCard(context, userPoints, qr);
                    },
                  ),

                  // Recent Activity
                  _buildSectionHeader('LIVE ACTIVITY', 'Recent Transactions'),
                  const SizedBox(height: 12),
                  transactionsAsync.when(
                    data: (transactions) {
                      if (transactions.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              'No transactions yet',
                              style: TextStyle(
                                color: Colors.grey.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        );
                      }
                      return Column(
                        children: transactions
                            .map((tx) => _buildTransactionItem(context, tx))
                            .toList(),
                      );
                    },
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    error: (err, _) => Center(child: Text('Error: $err')),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- TAB 2: PoA (Proof of Activity) ---
  Widget _buildPoATab(
    BuildContext context,
    UserPoints userPoints,
    Map<String, int> lifetimeEarnings,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.pageHorizontalPadding,
        vertical: AppTheme.sectionVerticalPadding,
      ),
      child: SafeArea(
        top: false,
        bottom: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),

            const Text(
              'Activity Earnings DSP Distribution',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Earn DSP through real actions that build community value. Every connection, transaction, and contribution counts.',
              style: TextStyle(color: Theme.of(context).hintColor),
            ),
            const SizedBox(height: 24),

            // === SECTION: Getting Started ===
            _buildSubHeader('Getting Started'),
            const SizedBox(height: 8),

            _buildActivityCard(
              context,
              title: 'Welcome Bonus',
              subtitle: 'Awarded automatically when you sign up',
              amount: '1,000 DSP',
              earned: lifetimeEarnings['welcome_bonus'] ?? 0,
            ),
            _buildActivityCard(
              context,
              title: 'Complete Your Profile',
              subtitle:
                  'Fill all 10 profile fields to unlock the genesis bonus',
              amount: '10,000 DSP',
              earned: lifetimeEarnings['profile_completion'] ?? 0,
            ),

            const SizedBox(height: 24),

            // === SECTION: Identity & Connections ===
            _buildSubHeader('Identity & Connections'),
            const SizedBox(height: 8),

            _buildActivityCard(
              context,
              title: 'Invite Family & Friends',
              subtitle: 'Someone signs up using your referral code',
              amount: '1,000 DSP each',
              earned:
                  (lifetimeEarnings['referral_reward_referrer'] ?? 0) +
                  (lifetimeEarnings['referral_reward_referee'] ?? 0),
            ),
            _buildActivityCard(
              context,
              title: 'Family Connection',
              subtitle: 'Send or accept a family relationship request',
              amount: '1,000 DSP',
              earned: lifetimeEarnings['family_connection'] ?? 0,
            ),
            _buildActivityCard(
              context,
              title: 'Friend Connection',
              subtitle: 'Send or accept a friend relationship request',
              amount: '1,000 DSP',
              earned: lifetimeEarnings['friend_connection'] ?? 0,
            ),
            _buildActivityCard(
              context,
              title: 'QR Connect',
              subtitle: 'Scan someone\'s QR code in person',
              amount: '1,000 DSP',
              earned: lifetimeEarnings['identity_qr_exchange'] ?? 0,
            ),

            const SizedBox(height: 24),

            // === SECTION: Verification ===
            _buildSubHeader('Verification'),
            const SizedBox(height: 8),

            _buildActivityCard(
              context,
              title: 'Verify Peer',
              subtitle: 'Verify someone\'s identity',
              amount: '1,000 DSP',
              earned: lifetimeEarnings['verifier_reward'] ?? 0,
            ),
            _buildActivityCard(
              context,
              title: 'Verified by Peer',
              subtitle: 'Someone verifies your identity',
              amount: '1,000 DSP',
              earned: lifetimeEarnings['verified_by_peer'] ?? 0,
            ),
            _buildActivityCard(
              context,
              title: 'Verify a Solution',
              subtitle: 'Mark a chat answer as a verified solution',
              amount: '1,000 DSP',
              earned:
                  lifetimeEarnings['verified_solution_verifier_reward'] ?? 0,
            ),
            _buildActivityCard(
              context,
              title: 'Verified Solution Author',
              subtitle: 'Someone marks your chat answer as a verified solution',
              amount: '1,000 DSP per verification',
              earned:
                  (lifetimeEarnings['verified_solution_author_reward'] ?? 0) +
                  (lifetimeEarnings['verified_solution_milestone'] ?? 0),
            ),

            const SizedBox(height: 24),

            // === SECTION: Vouching ===
            _buildSubHeader('Vouching'),
            const SizedBox(height: 8),

            _buildActivityCard(
              context,
              title: 'Vouch for Peer',
              subtitle:
                  'Vouch for someone\'s trustworthiness (+ 1,000 DSP staked)',
              amount: '1,000 DSP',
              earned:
                  (lifetimeEarnings['vouch_reward'] ?? 0) +
                  (lifetimeEarnings['trust_vouch_reward'] ?? 0),
            ),
            _buildActivityCard(
              context,
              title: 'Vouched by Peer',
              subtitle: 'Someone vouches for your trustworthiness',
              amount: '1,000 DSP',
              earned: lifetimeEarnings['vouched_by_peer'] ?? 0,
            ),
            _buildActivityCard(
              context,
              title: 'Vouch Consensus — Agree',
              subtitle: 'You agreed with the community on a vouch outcome',
              amount: '100 DSP',
              earned: lifetimeEarnings['vouch_consensus_agree'] ?? 0,
            ),
            _buildActivityCard(
              context,
              title: 'Trust Stake — Agreement Reward',
              subtitle: 'Another full-trust rater agrees with your stake',
              amount: '100 DSP',
              earned: lifetimeEarnings['trust_stake_agreement_reward'] ?? 0,
            ),
            _buildActivityCard(
              context,
              title: 'Trust Stake — Refund',
              subtitle:
                  'Your remaining stake returned when you exit full trust',
              amount: 'Variable',
              earned: lifetimeEarnings['trust_stake_refund'] ?? 0,
            ),

            const SizedBox(height: 24),

            // === SECTION: Economy & Travel ===
            _buildSubHeader('Economy & Travel'),
            const SizedBox(height: 8),

            _buildActivityCard(
              context,
              title: 'Economy Transaction',
              subtitle: 'Buy or sell on the marketplace (\$1 USD = 1 DSP)',
              amount: '\$1 = 1 DSP',
              earned:
                  (lifetimeEarnings['economy_transaction_buyer'] ?? 0) +
                  (lifetimeEarnings['economy_transaction_seller'] ?? 0),
            ),
            _buildActivityCard(
              context,
              title: 'Host a Traveler',
              subtitle: 'Host someone visiting your area',
              amount: '1,000 DSP',
              earned:
                  (lifetimeEarnings['host_traveler_host_reward'] ?? 0) +
                  (lifetimeEarnings['host_traveler_guest_reward'] ?? 0),
            ),

            const SizedBox(height: 24),

            // === SECTION: Community Participation ===
            _buildSubHeader('Community Participation'),
            const SizedBox(height: 8),

            _buildActivityCard(
              context,
              title: 'Event QR Check-in',
              subtitle: 'Attend a community event (QR verified)',
              amount: '1,000 DSP',
              earned: lifetimeEarnings['event_attendance'] ?? 0,
            ),
            _buildActivityCard(
              context,
              title: 'Host an Event',
              subtitle: 'Earn per verified attendee at your event',
              amount: '1,000 DSP each',
              earned: lifetimeEarnings['event_hosting_per_attendee'] ?? 0,
            ),

            const SizedBox(height: 24),

            // === SECTION: Groups & Moderation ===
            _buildSubHeader('Groups & Moderation'),
            const SizedBox(height: 8),

            _buildActivityCard(
              context,
              title: 'Group Invite Accepted',
              subtitle: 'Inviter rewarded when their invite is accepted',
              amount: '100 DSP',
              earned: lifetimeEarnings['Group Invite Accepted'] ?? 0,
            ),
            _buildActivityCard(
              context,
              title: 'Joined Group',
              subtitle: 'You accepted a group invite',
              amount: '100 DSP',
              earned: lifetimeEarnings['Joined Group'] ?? 0,
            ),
            _buildActivityCard(
              context,
              title: 'Rejected Group Invite',
              subtitle: 'Compensation if you decline a group invite',
              amount: '100 DSP',
              earned: lifetimeEarnings['Rejected Group Invite'] ?? 0,
            ),
            _buildActivityCard(
              context,
              title: 'Report a Message',
              subtitle: 'Flag a message for community review',
              amount: '100 DSP',
              earned: lifetimeEarnings['report_message'] ?? 0,
            ),
            _buildActivityCard(
              context,
              title: 'Report a Sender',
              subtitle: 'Flag a sender for community review',
              amount: '100 DSP',
              earned: lifetimeEarnings['report_sender'] ?? 0,
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // --- TAB 3: PoCT (Proof of Community Trust) ---
  Widget _buildPoCTTab(
    BuildContext context,
    UserPoints userPoints,
    AsyncValue<TrustData?> trustDataAsync,
    AsyncValue<ProfileData?> userProfileAsync,
  ) {
    final trustData = trustDataAsync.value;
    final curScore = trustData?.trustScore ?? 0.0;
    final daysActive = DateTime.now().difference(userPoints.signupDate).inDays;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.pageHorizontalPadding,
        vertical: AppTheme.sectionVerticalPadding,
      ),
      child: SafeArea(
        top: false,
        bottom: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            const Text(
              'Proof of Community Trust',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Your trust score grows as the community gets to know you. The higher your score, the more you unlock.',
              style: TextStyle(color: Theme.of(context).hintColor),
            ),
            const SizedBox(height: 16),
            Text(
              'DSP is earned instantly for all activities (except Profile Completion, which requires 10 fields for a 10,000 DSP payout). PoCT is earned instantly for general activities. For the four core connection milestones (Family, Friend, QR Connect, and Vouched/Verified), you earn 1,000 DSP instantly per connection, but the 10 PoCT is awarded only at 10× intervals (10, 100, 1K...).',
              style: TextStyle(
                color: Theme.of(context).hintColor,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 16),

            // --- Identity & Profile ---
            _buildTrustCard(
              context,
              title: 'Complete Your Profile',
              subtitle:
                  'Fill 10 profile fields to fully complete your profile and earn your genesis bonus.',
              amount: '+10 PoCT  •  10,000 DSP',
              standing:
                  '${userProfileAsync.value?.completedMilestoneFieldCount ?? 0}/10 Fields',
            ),

            // --- Verification ---
            _buildSubHeader('Verification'),
            const SizedBox(height: 8),
            _buildTrustCard(
              context,
              title: 'Verified by Peer',
              subtitle:
                  '1,000 DSP earned instantly per connection. +10 PoCT awarded at 10, 100, 1K... unique verifications.',
              amount: '+10 PoCT per 10× milestone',
              standing: '${trustData?.uniqueVerificationCount ?? 0} Received',
            ),
            _buildTrustCard(
              context,
              title: 'Verify Peer',
              subtitle:
                  'You verifying someone else. Earn 1,000 DSP instantly. Does not award PoCT (action builds trust for them, not you).',
              amount: '0 PoCT',
              standing: '-- Given',
            ),

            const SizedBox(height: 16),

            // --- Vouching ---
            _buildSubHeader('Vouching'),
            const SizedBox(height: 8),
            _buildTrustCard(
              context,
              title: 'Vouched by Peer',
              subtitle:
                  '1,000 DSP earned instantly per connection. +10 PoCT awarded at 10, 100, 1K... unique vouches.',
              amount: '+10 PoCT per 10× milestone',
              standing: '${trustData?.uniqueVouchCount ?? 0} Received',
            ),
            _buildTrustCard(
              context,
              title: 'Vouch for Peer',
              subtitle:
                  'You vouching for someone else. Earn 1,000 DSP + 1,000 DSP staked. Does not award PoCT (action builds trust for them, not you).',
              amount: '0 PoCT',
              standing: '-- Given',
            ),

            // --- Connections ---
            _buildTrustCard(
              context,
              title: 'Family Connection',
              subtitle:
                  '1,000 DSP earned instantly per connection. +10 PoCT awarded at 10, 100, 1K... unique connections.',
              amount: '+10 PoCT per 10× milestone',
              standing: '${trustData?.uniqueFamilyCount ?? 0} Connected',
            ),
            _buildTrustCard(
              context,
              title: 'Friend Connection',
              subtitle:
                  '1,000 DSP earned instantly per connection. +10 PoCT awarded at 10, 100, 1K... unique connections.',
              amount: '+10 PoCT per 10× milestone',
              standing: '${trustData?.uniqueFriendCount ?? 0} Connected',
            ),
            _buildTrustCard(
              context,
              title: 'QR Connect',
              subtitle:
                  '1,000 DSP earned instantly per connection. +10 PoCT awarded at 10, 100, 1K... unique connections.',
              amount: '+10 PoCT per 10× milestone',
              standing: '${trustData?.uniqueQrCount ?? 0} Scanned',
            ),

            // --- Seniority ---
            _buildTrustCard(
              context,
              title: 'Account Age',
              subtitle: 'Time on the platform builds trust.',
              amount: '+1 PoCT every 100 days',
              standing: '$daysActive Days',
            ),

            // Trust Slider Vis
            Container(
              margin: const EdgeInsets.symmetric(vertical: 48),
              padding: const EdgeInsets.all(16),
              decoration: AppTheme.cardDecoration(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSubHeader('The Trust Slider'),
                  const SizedBox(height: 4),
                  Text(
                    'How others rate you affects your score:',
                    style: TextStyle(color: Theme.of(context).hintColor),
                  ),
                  const SizedBox(height: 12),
                  _buildTrustIndicator(
                    AppTheme.error,
                    'Red (0-20)',
                    'Low Trust',
                  ),
                  _buildTrustIndicator(
                    Colors.deepOrange,
                    'Deep Orange (21-40)',
                    'Basic Trust',
                  ),
                  _buildTrustIndicator(
                    Colors.amber,
                    'Amber (41-60)',
                    'Medium Trust',
                  ),
                  _buildTrustIndicator(
                    Colors.lightGreen,
                    'Light Green (61-80)',
                    'Standard Trust',
                  ),
                  _buildTrustIndicator(
                    AppTheme.accent,
                    'Sage Green (81-100)',
                    'High Trust',
                  ),
                ],
              ),
            ),
            Builder(
              builder: (context) {
                final daysActive = DateTime.now()
                    .difference(userPoints.signupDate)
                    .inDays;
                return _buildLevelDashboard(
                  context,
                  trustData,
                  daysActive,
                  userPoints.totalPoints,
                );
              },
            ),

            const SizedBox(height: 24),

            const SizedBox(height: 24),
            _buildSubHeader('TGE Efficiency Gates'),
            const SizedBox(height: 16),
            _buildEarningGateTable(curScore),
          ],
        ),
      ),
    );
  }

  // --- HELPERS FOR CARDS ---

  /// PoA activity card: title, subtitle, and amount each on their own row.
  Widget _buildActivityCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String amount,
    required int earned,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.cardDecoration(context).color,
        borderRadius: BorderRadius.circular(10),
      ),
      margin: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Title + Earned
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${NumberFormat('#,###').format(earned)} earned',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: earned > 0
                      ? AppTheme.accent
                      : Theme.of(context).hintColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Row 2: Subtitle
          Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
          ),
          const SizedBox(height: 4),
          // Row 3: Amount badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              amount,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.green,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// PoCT trust card: title, subtitle, amount, and standing each on their own row.
  Widget _buildTrustCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String amount,
    required String standing,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.cardDecoration(context).color,
        borderRadius: BorderRadius.circular(10),
      ),
      margin: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Title + Standing
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                standing,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Row 2: Subtitle
          Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
          ),
          const SizedBox(height: 4),
          // Row 3: Amount/reward badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              amount,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- RESTORED DASHBOARD WIDGETS ---

  Widget _buildSectionHeader(
    String subtitle,
    String title, {
    double titleSize = 20,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (subtitle.isNotEmpty) ...[
          Text(
            subtitle,
            style: const TextStyle(
              color: AppTheme.accent,
              letterSpacing: 1.2,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
        ],
        Text(
          title,
          style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildBalanceSummary(
    BuildContext context,
    UserPoints points,
    double trustScore,
    int uniqueQrCount,
  ) {
    final epochService = ref.read(epochServiceProvider);
    final double efficiency = epochService.calculateEfficiency(trustScore);
    final String efficiencyStatus = '${(efficiency * 100).toInt()}%';
    final Color efficiencyColor = EpochService.getEfficiencyColor(trustScore);

    final int totalPoints = points.totalPoints;
    // TGE gate is now 10 unique Identity QR exchanges — and only for the
    // user's first TGE. After firstTgeReceivedAt is stamped, every TGE
    // after that is automatic and the gate disappears.
    const int qrGateThreshold = 10;
    final bool isPostFirstTge =
        points.firstTgeReceivedAt != null || points.tgeHistory.isNotEmpty;
    final double progress = isPostFirstTge
        ? 1.0
        : (uniqueQrCount / qrGateThreshold).clamp(0.0, 1.0);
    final bool isQualified = isPostFirstTge || uniqueQrCount >= qrGateThreshold;

    return Container(
      padding: AppTheme.cardPaddingEdgeInsets,
      decoration: AppTheme.cardDecoration(context),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildBalanceItemColored(
                  'Trust Score',
                  trustScore.toStringAsFixed(0),
                  LucideIcons.shieldCheck,
                  efficiencyColor,
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.grey.withValues(alpha: 0.2),
              ),
              Expanded(
                child: _buildBalanceItem(
                  'Net Balance',
                  NumberFormat('#,###').format(totalPoints),
                  LucideIcons.wallet,
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.grey.withValues(alpha: 0.2),
              ),
              Expanded(
                child: _buildBalanceItemColored(
                  'TGE Efficiency',
                  efficiencyStatus,
                  LucideIcons.barChart2,
                  efficiencyColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.grey.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation(
                isQualified ? AppTheme.accent : Colors.orange,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isPostFirstTge
                    ? 'Auto-included in every future TGE'
                    : '$uniqueQrCount / $qrGateThreshold unique QR exchanges',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).hintColor,
                ),
              ),
              if (isQualified)
                const Text(
                  'QUALIFIED',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                )
              else
                Text(
                  'Need ${qrGateThreshold - uniqueQrCount} more QR exchange${qrGateThreshold - uniqueQrCount == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 11, color: Colors.orange),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 20, color: AppTheme.accent),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        Text(
          label,
          style: TextStyle(color: Theme.of(context).hintColor, fontSize: 11),
        ),
      ],
    );
  }

  /// Like _buildBalanceItem but with a custom [valueColor] for the value text and icon.
  Widget _buildBalanceItemColored(
    String label,
    String value,
    IconData icon,
    Color valueColor,
  ) {
    return Column(
      children: [
        Icon(icon, size: 20, color: valueColor),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: valueColor,
          ),
        ),
        Text(
          label,
          style: TextStyle(color: Theme.of(context).hintColor, fontSize: 11),
        ),
      ],
    );
  }

  // [NEW] Provider for global member count
  final globalMemberCountProvider = StreamProvider<int>((ref) {
    return ref.watch(pointsRepositoryProvider).streamGlobalMemberCount();
  });

  Widget _buildPlatformStatusCard(BuildContext context) {
    final globalSupplyAsync = ref.watch(globalSupplyProvider);
    final globalMembersAsync = ref.watch(globalMemberCountProvider);
    final epochService = ref.watch(epochServiceProvider);

    return globalSupplyAsync.when(
      data: (supply) {
        return globalMembersAsync.when(
          data: (members) {
            final epoch = epochService.getCurrentCommunityEpoch(
              supply,
              members,
            );
            final eventNumber = epochService.getCurrentTgeEventNumber(
              supply,
              members,
            );
            return Container(
              margin: EdgeInsets.zero,
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: AppTheme.cardDecoration(
                      context,
                    ).copyWith(borderRadius: BorderRadius.zero),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'EPOCH ${epoch.level} / 10',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  'Community Era',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context).hintColor,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.cardDecoration(context).color,
                                borderRadius: BorderRadius.circular(
                                  AppTheme.standardBorderRadius,
                                ),
                              ),
                              child: Text(
                                'TGE $eventNumber / 10',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.accent,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Detailed Visual Roadmap
                        _buildEpochRoadmap(context, epoch.level, eventNumber),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Main Progress Bars
                  _buildSectionHeader(
                    'GLOBAL SCALE',
                    'Activity Earnings DSP Distribution',
                  ),
                  const SizedBox(height: 12),

                  // Supply Progress (1QD)
                  _buildProgressBar(
                    title: 'DSP Distributed',
                    current: supply.toDouble(),
                    target: 1000000000000000.0, // 1QD
                    label: '1QD',
                    color: AppTheme.accent,
                  ),
                  const SizedBox(height: 16),

                  // Member Progress (100B)
                  _buildProgressBar(
                    title: 'Diaspora Population',
                    current: members.toDouble(),
                    target: 100000000000.0, // 100B
                    label: '100B',
                    color: Colors.blue,
                  ),
                ],
              ),
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

  Widget _buildProgressBar({
    required String title,
    required double current,
    required double target,
    required String label,
    required Color color,
  }) {
    final double progress = (current / target).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            Text(
              '${NumberFormat.compact().format(current)} / $label',
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: Colors.grey.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }

  Widget _buildEpochRoadmap(
    BuildContext context,
    int currentEpoch,
    int currentTge,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Epoch Roadmap',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 12),
        Column(
          children: [
            Row(
              children: List.generate(
                5,
                (index) => _buildEpochStep(index + 1, currentEpoch),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: List.generate(
                5,
                (index) => _buildEpochStep(index + 6, currentEpoch),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEpochDetailCard(
    BuildContext context,
    UserPoints userPoints,
    int uniqueQrCount,
  ) {
    final globalSupplyAsync = ref.watch(globalSupplyProvider);
    final globalMembersAsync = ref.watch(globalMemberCountProvider);
    final epochService = ref.watch(epochServiceProvider);

    return globalSupplyAsync.when(
      data: (supply) {
        return globalMembersAsync.when(
          data: (members) {
            final epoch = epochService.getCurrentCommunityEpoch(
              supply,
              members,
            );
            final prevEpoch = epochService.getPreviousCommunityEpoch(
              epoch.level,
            );

            final int prevDspTarget = prevEpoch?.dspTarget ?? 0;
            final int prevMemberTarget = prevEpoch?.memberTarget ?? 0;

            // Range-based progress calculation
            final double supplyProgress =
                ((supply - prevDspTarget) / (epoch.dspTarget - prevDspTarget))
                    .clamp(0.0, 1.0);
            final double memberProgress =
                ((members - prevMemberTarget) /
                        (epoch.memberTarget - prevMemberTarget))
                    .clamp(0.0, 1.0);

            // Calculate Total Distributed for this Epoch
            final epochHistory = userPoints.tgeHistory
                .where((e) => e.epoch == epoch.level)
                .toList();
            final double totalDistributed = epochHistory.fold(
              0.0,
              (sum, e) => sum + e.amount,
            );

            return Container(
              margin: const EdgeInsets.symmetric(
                vertical: AppTheme.pageHorizontalPadding,
              ),
              padding: const EdgeInsets.symmetric(
                vertical: AppTheme.cardVerticalPadding,
              ),
              decoration: AppTheme.cardDecoration(
                context,
              ).copyWith(borderRadius: BorderRadius.zero),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildSectionHeader(
                        'CURRENT EPOCH PROGRESS',
                        'Epoch ${epoch.level}',
                      ),
                      if (totalDistributed > 0)
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
                            '${NumberFormat.compact().format(totalDistributed)} \$DIASPORA',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.warning,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Epoch Max Supply
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Epoch Supply',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Target: ${NumberFormat.compact().format(epoch.dspTarget)}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${NumberFormat.compact().format(supply)} / ${NumberFormat.compact().format(epoch.dspTarget)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.accent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: supplyProgress,
                      minHeight: 6,
                      backgroundColor: Colors.grey.withValues(alpha: 0.1),
                      color: AppTheme.accent,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Epoch Min Population
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Epoch Population',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Target: ${NumberFormat.compact().format(epoch.memberTarget)}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${NumberFormat.compact().format(members)} / ${NumberFormat.compact().format(epoch.memberTarget)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: memberProgress,
                      minHeight: 6,
                      backgroundColor: Colors.grey.withValues(alpha: 0.1),
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // TGE Schedule
                  const Text(
                    'TGE Schedule',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  _buildTGEMilestones(
                    context,
                    epoch,
                    supply,
                    members,
                    userPoints,
                    epochService,
                    uniqueQrCount,
                  ),
                ],
              ),
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

  Widget _buildTGEMilestones(
    BuildContext context,
    CommunityEpochDefinition epoch,
    int currentSupply,
    int currentMembers,
    UserPoints userPoints,
    EpochService epochService,
    int uniqueQrCount,
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
        final tgeNumber = index + 1;

        final stepStart = prevDspTarget + (index * stepSize);
        final stepTarget = prevDspTarget + ((index + 1) * stepSize);

        final memberStart = prevMemberTarget + (index * effectiveMemberStep);
        final memberTarget =
            prevMemberTarget + ((index + 1) * effectiveMemberStep);

        // Find specific record for this TGE
        final record = userPoints.tgeHistory.firstWhere(
          (e) => e.epoch == epoch.level && e.tgeNumber == tgeNumber,
          orElse: () => TgeDistributionRecord(
            epoch: -1,
            tgeNumber: -1,
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
                  // Removed status icon to expand horizontally

                  // Details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'TGE $tgeNumber',
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
                              Builder(
                                builder: (context) {
                                  // double amount; // These variables are not used
                                  // double efficiency; // These variables are not used
                                  // Color textColor; // These variables are not used

                                  return Column(
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
                                  );
                                },
                              ),
                          ],
                        ),
                        if (isActive) ...[
                          const SizedBox(height: 6),
                          // Supply Bar
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
                          // Population Bar
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
                                '${NumberFormat.compact().format(currentSupply)} / ${NumberFormat.compact().format(stepTarget)} DSP',
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
                          // User Status Section
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
                                // Row 1: Trust Check (Adopt PoCT Spectrum Color)
                                Builder(
                                  builder: (context) {
                                    final currentTrust =
                                        userPoints.trustScore ?? 0;
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
                                          '$currentTrust PoCT',
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
                                // Row 2: QR Gate (10 unique exchanges) — first
                                // TGE only; auto-included after that.
                                Builder(
                                  builder: (context) {
                                    final isPostFirstTge =
                                        userPoints.firstTgeReceivedAt != null ||
                                        userPoints.tgeHistory.isNotEmpty;
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
                                // Row 3: Efficiency (Replace label and align)
                                Builder(
                                  builder: (context) {
                                    // final potential = epochService.calculateTGESwap( // potential is not used
                                    //    epochNumber: epoch.level,
                                    //    currentDspBalance: userPoints.availablePoints.toDouble(),
                                    //    trustScore: userPoints.trustScore ?? 0
                                    // );
                                    double efficiency = 0.0;
                                    final trust = userPoints.trustScore ?? 0;
                                    if (trust > 0) {
                                      efficiency = (trust / 10).ceil() / 10.0;
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
                                // Row 4: Estimated payout — gated on QR
                                // qualification (or post-first-TGE auto-qualify).
                                Builder(
                                  builder: (context) {
                                    final isPostFirstTge =
                                        userPoints.firstTgeReceivedAt != null ||
                                        userPoints.tgeHistory.isNotEmpty;
                                    final qrMet =
                                        isPostFirstTge || uniqueQrCount >= 10;
                                    final currentBalance =
                                        userPoints.availablePoints;
                                    double efficiency = 0.0;
                                    final trust = userPoints.trustScore ?? 0;
                                    if (trust > 0) {
                                      efficiency = (trust / 10).ceil() / 10.0;
                                      if (efficiency > 1.0) efficiency = 1.0;
                                    }
                                    final double payout =
                                        currentBalance * efficiency;
                                    final payoutStr = qrMet
                                        ? '${NumberFormat('#,###').format(payout.round())} \$DIASPORA'
                                        : '— complete QR gate first';

                                    return Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'Estimated Payout',
                                          style: TextStyle(fontSize: 10),
                                        ),
                                        Text(
                                          payoutStr,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: qrMet
                                                ? AppTheme.warning
                                                : Colors.grey,
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
                            'Unlocks at ${NumberFormat.compact().format(stepStart)} DSP epoch supply',
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

  Widget _buildTransactionItem(BuildContext context, PointsTransaction tx) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: AppTheme.accent.withValues(alpha: 0.1),
        child: _getIconForAction(tx.action),
      ),
      title: Text(
        tx.displayAction,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
      subtitle: Text(
        DateFormat.yMMMd().format(tx.timestamp),
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Text(
        '+${tx.points}',
        style: const TextStyle(
          color: Colors.green,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _getIconForAction(String action) {
    if (action.contains('message')) {
      return const Icon(
        LucideIcons.messageCircle,
        size: 16,
        color: AppTheme.accent,
      );
    }
    if (action.contains('referral')) {
      return const Icon(LucideIcons.users, size: 16, color: AppTheme.accent);
    }
    if (action.contains('share')) {
      return const Icon(LucideIcons.share2, size: 16, color: AppTheme.accent);
    }
    return const Icon(LucideIcons.zap, size: 16, color: AppTheme.accent);
  }

  Widget _buildSubHeader(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
    );
  }

  Widget _buildTrustIndicator(Color color, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0, left: 8.0),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                ),
                children: [
                  TextSpan(
                    text: '$title: ',
                    style: TextStyle(fontWeight: FontWeight.bold, color: color),
                  ),
                  TextSpan(text: desc),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelDashboard(
    BuildContext context,
    TrustData? trustData,
    int daysActive,
    int dspBalance,
  ) {
    final curScore = trustData?.trustScore ?? 0.0;
    final seniorityPoints = (daysActive / 100).floor();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Account Status Journey (Age/Days Active)
        _buildSubHeader('Seniority & Status'),
        const SizedBox(height: 16),
        Container(
          padding: AppTheme.cardPaddingEdgeInsets,
          decoration: AppTheme.cardDecoration(context),
          child: Row(
            children: [
              const Icon(LucideIcons.calendar, color: AppTheme.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Seniority Points',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '+$seniorityPoints PoCT earned from $daysActive days',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                    const Text(
                      'Rule: +1 PoCT for every 100 days of activity',
                      style: TextStyle(
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                seniorityPoints.toString(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.accent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildStatusCard(
          context,
          title: 'Newcomer',
          level: TrustLevel.lowTrust,
          isActive: daysActive < 10,
          requirements: [RequirementItem('Active < 10 Days', daysActive < 10)],
          progress: [daysActive / 10.0],
          progressLabels: ['$daysActive / 10 Days'],
          isCompleted: daysActive >= 10,
          levelColor: AppTheme.error,
        ),
        // ... (rest of the cards)
        const SizedBox(height: 10),
        _buildStatusCard(
          context,
          title: 'Member',
          level: TrustLevel.basicTrust,
          isActive: daysActive >= 10 && daysActive < 100,
          requirements: [
            RequirementItem('Active: 10 - 100 Days', daysActive >= 10),
          ],
          progress: [(daysActive - 10) / 90.0],
          progressLabels: ['$daysActive / 100 Days'],
          isCompleted: daysActive >= 100,
          levelColor: Colors.deepOrange,
        ),
        const SizedBox(height: 10),
        _buildStatusCard(
          context,
          title: 'Resident',
          level: TrustLevel.mediumTrust,
          isActive: daysActive >= 100 && daysActive < 200,
          requirements: [
            RequirementItem('Active: 100 - 200 Days', daysActive >= 100),
          ],
          progress: [(daysActive - 100) / 100.0],
          progressLabels: ['$daysActive / 200 Days'],
          isCompleted: daysActive >= 200,
          levelColor: Colors.amber,
        ),
        const SizedBox(height: 10),
        _buildStatusCard(
          context,
          title: 'Leader',
          level: TrustLevel.highTrust,
          isActive: daysActive >= 200 && daysActive < 300,
          requirements: [
            RequirementItem('Active: 200 - 300 Days', daysActive >= 200),
          ],
          progress: [(daysActive - 200) / 100.0],
          progressLabels: ['$daysActive / 300 Days'],
          isCompleted: daysActive >= 300,
          levelColor: AppTheme.accent,
        ),

        const SizedBox(height: 24),
        _buildSubHeader('PoCT Trust Levels'),
        const SizedBox(height: 12),

        // Trust Score Journey
        _buildStatusCard(
          context,
          title: 'Low Trust',
          level: TrustLevel.lowTrust,
          isActive: curScore <= 20,
          requirements: [RequirementItem('Score: 0 - 20', curScore >= 0)],
          progress: [curScore / 20.0],
          progressLabels: ['Score: ${curScore.toStringAsFixed(1)}/20'],
          isCompleted: curScore > 20,
          levelColor: AppTheme.error,
        ),
        const SizedBox(height: 12),
        _buildStatusCard(
          context,
          title: 'Basic Trust',
          level: TrustLevel.basicTrust,
          isActive: curScore > 20 && curScore <= 40,
          requirements: [RequirementItem('Score: 21 - 40', curScore > 20)],
          progress: [curScore / 40.0],
          progressLabels: ['Score: ${curScore.toStringAsFixed(1)}/40'],
          isCompleted: curScore > 40,
          levelColor: Colors.deepOrange,
        ),
        const SizedBox(height: 12),
        _buildStatusCard(
          context,
          title: 'Medium Trust',
          level: TrustLevel.mediumTrust,
          isActive: curScore > 40 && curScore <= 60,
          requirements: [RequirementItem('Score: 41 - 60', curScore > 40)],
          progress: [curScore / 60.0],
          progressLabels: ['Score: ${curScore.toStringAsFixed(1)}/60'],
          isCompleted: curScore > 60,
          levelColor: Colors.amber,
        ),
        const SizedBox(height: 12),
        _buildStatusCard(
          context,
          title: 'Standard Trust',
          level: TrustLevel.standardTrust,
          isActive: curScore > 60 && curScore <= 80,
          requirements: [RequirementItem('Score: 61 - 80', curScore > 60)],
          progress: [curScore / 80.0],
          progressLabels: ['Score: ${curScore.toStringAsFixed(1)}/80'],
          isCompleted: curScore > 80,
          levelColor: Colors.lightGreen,
        ),
        const SizedBox(height: 12),
        _buildStatusCard(
          context,
          title: 'High Trust',
          level: TrustLevel.highTrust,
          isActive: curScore > 80,
          requirements: [RequirementItem('Score: 81 - 100', curScore > 80)],
          progress: [curScore / 100.0],
          progressLabels: ['Score: ${curScore.toStringAsFixed(1)}/100'],
          isCompleted: curScore >= 100, // Or just active if maxed
          levelColor: AppTheme.accent,
        ),
      ],
    );
  }

  Widget _buildStatusCard(
    BuildContext context, {
    required String title,
    required TrustLevel level,
    required bool isActive,
    required List<RequirementItem> requirements,
    List<double>? progress,
    List<String>? progressLabels,
    bool isCompleted = false,
    Color levelColor = AppTheme.accent,
  }) {
    final color = isActive
        ? levelColor
        : (isCompleted ? Colors.green : Colors.grey);
    // final backgroundColor = isActive // Not used
    //     ? levelColor.withValues(alpha: 0.05)
    //     : (isCompleted ? Colors.green.withValues(alpha: 0.02) : Colors.grey.withValues(alpha: 0.05));
    // final borderColor = isActive // Not used
    //     ? levelColor.withValues(alpha: 0.3)
    //     : (isCompleted ? Colors.green.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.1));

    return Opacity(
      opacity: isActive || isCompleted ? 1.0 : 0.6,
      child: Container(
        width: double.infinity,
        padding: AppTheme.cardPaddingEdgeInsets,
        decoration: AppTheme.cardDecoration(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isCompleted
                      ? LucideIcons.checkCircle2
                      : (isActive ? LucideIcons.star : LucideIcons.lock),
                  color: color,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isActive ? AppTheme.accentDark : color,
                  ),
                ),
                const Spacer(),
                if (isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.accent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'CURRENT',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ...requirements.map(
              (req) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(
                      req.isMet ? LucideIcons.checkCircle2 : LucideIcons.circle,
                      size: 14,
                      color: req.isMet
                          ? Colors.green
                          : color.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        req.label,
                        style: TextStyle(
                          fontSize: 13,
                          color: req.isMet
                              ? Theme.of(context).textTheme.bodyMedium?.color
                              : Theme.of(context).textTheme.bodyMedium?.color
                                    ?.withValues(alpha: 0.7),
                          fontWeight: req.isMet
                              ? FontWeight.w500
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (isActive &&
                !isCompleted &&
                progress != null &&
                progressLabels != null) ...[
              const SizedBox(height: 16),
              const Text(
                'Next Level Progress:',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              for (int i = 0; i < progress.length; i++) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      progressLabels[i],
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                    Text(
                      '${(progress[i].clamp(0.0, 1.0) * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isActive ? levelColor : color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress[i].clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: color.withValues(alpha: 0.1),
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEarningGateTable(double currentScore) {
    // [UPDATED]
    return Container(
      decoration: AppTheme.cardDecoration(context),
      child: Column(
        children: [
          _buildEfficiencyRow(
            'PoCT Score',
            'Efficiency',
            'Status',
            isHeader: true,
          ),
          // Rows use the same 5-band color scale as the trust slider
          _buildEfficiencyRow(
            '91 - 100',
            '100%',
            'Maximum Yield',
            textColor: EpochService.getEfficiencyColor(95),
          ),
          _buildEfficiencyRow(
            '81 - 90',
            '90%',
            'Very High Yield',
            textColor: EpochService.getEfficiencyColor(85),
          ),
          _buildEfficiencyRow(
            '71 - 80',
            '80%',
            'High Yield',
            textColor: EpochService.getEfficiencyColor(75),
          ),
          _buildEfficiencyRow(
            '61 - 70',
            '70%',
            'Good Yield',
            textColor: EpochService.getEfficiencyColor(65),
          ),
          _buildEfficiencyRow(
            '51 - 60',
            '60%',
            'Standard Yield',
            textColor: EpochService.getEfficiencyColor(55),
          ),
          _buildEfficiencyRow(
            '41 - 50',
            '50%',
            'Basic Yield',
            textColor: EpochService.getEfficiencyColor(45),
          ),
          _buildEfficiencyRow(
            '31 - 40',
            '40%',
            'Low Yield',
            textColor: EpochService.getEfficiencyColor(35),
          ),
          _buildEfficiencyRow(
            '21 - 30',
            '30%',
            'Very Low Yield',
            textColor: EpochService.getEfficiencyColor(25),
          ),
          _buildEfficiencyRow(
            '11 - 20',
            '20%',
            'Minimal Yield',
            textColor: EpochService.getEfficiencyColor(15),
          ),
          _buildEfficiencyRow(
            '1 - 10',
            '10%',
            'Entry Yield',
            textColor: EpochService.getEfficiencyColor(5),
          ),
          _buildEfficiencyRow(
            '0',
            '0%',
            'No Yield',
            textColor: EpochService.getEfficiencyColor(0),
          ),
        ],
      ),
    );
  }

  Widget _buildEfficiencyRow(
    String score,
    String rate,
    String status, {
    bool isHeader = false,
    Color? textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isHeader ? AppTheme.accent.withValues(alpha: 0.05) : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              score,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Expanded(
            child: Text(
              rate,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isHeader ? FontWeight.bold : FontWeight.bold,
                color: isHeader ? null : (textColor ?? Colors.grey),
              ),
            ),
          ),
          Expanded(
            child: Text(
              status,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
                color: isHeader ? null : textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // [NEW] Ecosystem Wallets (Home Country & Platform) - Moved from DiasporaCryptoScreen
  Widget _buildEcosystemWalletsSection() {
    final profile = ref.watch(userProfileProvider).value;
    final userId = profile?.uid ?? '';

    // Watch all communities the user is part of
    final communitiesAsync = ref.watch(userCommunitiesStreamProvider(userId));
    final communities = communitiesAsync.value ?? [];

    // Filter into pools (EXCLUDING Global Community which is handled separately)
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

    // Sort by type (Continent > Country > City) - Removed State for 7-slot symmetry
    int getTypeWeight(String? type) {
      switch (type) {
        case 'continent':
          return 0;
        case 'country':
          return 1;
        case 'city':
          return 2;
        default:
          return 3;
      }
    }

    homePool.sort(
      (a, b) => getTypeWeight(a.type).compareTo(getTypeWeight(b.type)),
    );
    hostPool.sort(
      (a, b) => getTypeWeight(a.type).compareTo(getTypeWeight(b.type)),
    );

    final systemTreasury = ref.watch(systemTreasuryProvider).value ?? {};

    final foundersPoints = systemTreasury['foundersPoints'] as int? ?? 0;
    // Post-2026-06-04: backend writes `liquidityPoints`. We sum both so this
    // screen renders correctly during the transition window (old backend
    // still writing `investorsPoints` → migration runs → new backend writes
    // `liquidityPoints`). After the data migration zeros `investorsPoints`,
    // the legacy term is 0 and only `liquidityPoints` contributes.
    final liquidityPoints =
        (systemTreasury['liquidityPoints'] as int? ?? 0) +
        (systemTreasury['investorsPoints'] as int? ?? 0);
    final burnedPoints = systemTreasury['burnedPoints'] as int? ?? 0;

    // [FIX] Total Community Wealth is derived from Global Supply / 2 (1:1 Match Ratio)
    // Previously, we summed only the user's communities, which excluded others' exclusive communities.
    final globalSupplyAsync = ref.watch(globalSupplyProvider);
    final globalSupply = globalSupplyAsync.value ?? 0;
    final totalCommunityWealth = (globalSupply / 2).round();

    // Global Epoch for labeling
    final epochService = EpochService();
    final globalCommunity = ref
        .watch(communityProvider('global_community'))
        .value;
    final int globalMembers = globalCommunity?.memberCount ?? 0;
    final int globalCumulative = globalCommunity?.cumulativeEarnings ?? 0;
    final int globalTgeEvent = epochService.getCurrentTgeEventNumber(
      globalCumulative,
      globalMembers,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Global Community Wealth Summary Card
          _buildWalletDisplayCard(
            title: 'Community Earnings',
            icon: LucideIcons.layers,
            color: AppTheme.accent,
            percentage: '50% of Supply',
            points: totalCommunityWealth,
            efficiency: 1.0,
            epochLabel: 'Aggregated Distributed Wealth',
            avatarWidget: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.accent.withValues(alpha: 0.1),
              ),
              child: const Icon(
                LucideIcons.globe,
                size: 12,
                color: AppTheme.accent,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 1.1 Global Reserve (10% Tribute)
          _buildWalletDisplayCard(
            title: 'Global Reserve',
            icon: LucideIcons.globe,
            color: AppTheme.accent,
            percentage: '10%',
            points: globalCommunity?.points ?? 0,
            efficiency: epochService.calculateEfficiency(
              globalCommunity?.averagePoCT ?? 0,
            ),
            trustScore: (globalCommunity?.averagePoCT ?? 0).toDouble(),
            tgeEvent: globalTgeEvent,
            epochLabel:
                'Chambers operations · Charitable donations · Protocol upkeep',
            avatarWidget: CommunityChatUtils.getCommunityAvatar(
              context: context,
              type: globalCommunity?.type ?? 'global',
              locationType: 'global',
              communityId: 'global_community',
              size: 20,
            ),
          ),
          const SizedBox(height: 24),

          // 2. Home Communities Section
          if (homePool.isNotEmpty) ...[
            _buildSectionHeader(
              'YOUR ORIGINS',
              'Home Community Treasuries',
              titleSize: 16,
            ),
            const SizedBox(height: 8),
            ...homePool.map((community) {
              const percentage = "10%";
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildWalletDisplayCard(
                  title:
                      '${CommunityChatUtils.generateCommunityNameFromParts(name: community.name, locationType: community.locationType ?? 'home', id: community.id)} Treasury',
                  icon: LucideIcons.home,
                  color: AppTheme.accent,
                  percentage: percentage,
                  points: community.points,
                  efficiency: epochService.calculateEfficiency(
                    community.averagePoCT,
                  ),
                  trustScore: community.averagePoCT.toDouble(),
                  tgeEvent: globalTgeEvent,
                  avatarWidget: CommunityChatUtils.getCommunityAvatar(
                    context: context,
                    type: community.type ?? 'country',
                    locationType: 'home',
                    communityId: community.id,
                    homeCountryCode: community.homeCountryCode,
                    size: 20,
                  ),
                ),
              );
            }),
            const SizedBox(height: 12),
          ],

          // 3. Host Communities Section
          if (hostPool.isNotEmpty) ...[
            _buildSectionHeader(
              'YOUR RESIDENCE',
              'Host Community Treasuries',
              titleSize: 16,
            ),
            const SizedBox(height: 8),
            ...hostPool.map((community) {
              const percentage = "10%";
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildWalletDisplayCard(
                  title:
                      '${CommunityChatUtils.generateCommunityNameFromParts(name: community.name, locationType: community.locationType ?? 'host', id: community.id)} Treasury',
                  icon: LucideIcons.mapPin,
                  color: Colors.orange,
                  percentage: percentage,
                  points: community.points,
                  efficiency: epochService.calculateEfficiency(
                    community.averagePoCT,
                  ),
                  trustScore: community.averagePoCT.toDouble(),
                  tgeEvent: globalTgeEvent,
                  avatarWidget: CommunityChatUtils.getCommunityAvatar(
                    context: context,
                    type: community.type ?? 'country',
                    locationType: 'host',
                    communityId: community.id,
                    size: 20,
                  ),
                ),
              );
            }),
            const SizedBox(height: 12),
          ],

          _buildSectionHeader('PLATFORM', 'System Treasuries', titleSize: 16),
          const SizedBox(height: 8),

          const SizedBox(height: 12),

          // 6. Liquidity Treasury
          _buildWalletDisplayCard(
            title: 'Liquidity Treasury',
            icon: LucideIcons.droplets,
            color: Colors.cyan,
            percentage: '10%',
            points: liquidityPoints,
            efficiency: 1.0,
            epochLabel:
                'DEX Liquidity & Market Access • TGE $globalTgeEvent/10',
          ),
          const SizedBox(height: 12),

          // 7. Founders & Core Team
          _buildWalletDisplayCard(
            title: 'Founders & Core Team',
            icon: LucideIcons.users,
            color: AppTheme.accent,
            percentage: '10%',
            points: foundersPoints,
            efficiency: 1.0,
            trustScore: 100.0, // Guaranteed 100% Efficiency
            tgeEvent: globalTgeEvent,
            avatarWidget: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.accent.withValues(alpha: 0.1),
              ),
              child: Image.asset(
                'assets/icons/logo-original.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 7. Burned Infrastructure (Unassigned Slots)
          _buildWalletDisplayCard(
            title: 'Burned Infrastructure',
            icon: LucideIcons.flame,
            color: Colors.redAccent,
            percentage: 'BURN',
            points: burnedPoints,
            efficiency: 1.0,
            epochLabel: 'Fixed 10% Infrastructure Burn',
          ),
          const SizedBox(height: 24),

          // Admin Task: Sync Balances
          Center(
            child: TextButton.icon(
              onPressed: () async {
                try {
                  await ref.read(pointsServiceProvider).syncTreasuryBalances();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Treasury balances synchronized!'),
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Error syncing: $e')));
                }
              },
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Sync Treasury Balances'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.accent.withValues(alpha: 0.7),
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Leaderboard Section
          // _buildSectionHeader('Global Governance', 'Community Leaderboard'),
          _buildCountriesLeaderboard(context),
        ],
      ),
    );
  }

  Widget _buildCountriesLeaderboard(BuildContext context) {
    // final isDark = Theme.of(context).brightness == Brightness.dark; // Not used
    final leaderboardAsync = ref.watch(countryLeaderboardProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.pageHorizontalPadding,
          ),
          child: _buildSectionHeader('CURRENCY', 'Country Epoch Leaderboard'),
        ),
        const SizedBox(height: 12), // Added 12 + 12 = 24px gap
        Container(
          decoration: AppTheme.cardDecoration(context),
          child: Column(
            children: [
              ...leaderboardAsync.maybeWhen(
                data: (countries) => countries
                    .take(10)
                    .map((country) => CountryLeaderboardItem(country: country)),
                orElse: () => [
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CountriesLeaderboardScreen(),
                ),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.accent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  AppTheme.standardBorderRadius,
                ),
              ),
              side: BorderSide.none,
            ),
            child: const Text('View Full Leaderboard'),
          ),
        ),
      ],
    );
  }

  String _formatPoints(int points) {
    return '${points.toString().replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]},")} DSP';
  }

  Widget _buildWalletDisplayCard({
    required String title,
    required IconData icon,
    required Color color,
    required String percentage,
    required int points,
    double? efficiency,
    String? epochLabel,
    Widget? avatarWidget,
    double? trustScore,
    int? tgeEvent,
  }) {
    // Theme aware colors
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Corrected theme variable usage
    final themeTextColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white54 : Colors.black54;

    // Payout calculation
    final double eff = efficiency ?? 1.0;
    final payout = points * eff;
    final payoutStr =
        '${NumberFormat('#,###').format(payout.round())} \$DIASPORA';

    return Container(
      padding: AppTheme.cardPaddingEdgeInsets,
      decoration: AppTheme.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (avatarWidget != null) ...[
                avatarWidget,
                const SizedBox(width: 8),
              ] else ...[
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: themeTextColor,
                    fontSize: 13,
                  ),
                ),
              ),
              if (percentage.isNotEmpty)
                Text(
                  percentage,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.accent,
                    fontSize: 13,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ESTIMATED \$DIASPORA PAYOUT',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: subTextColor,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      payoutStr,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.warning,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              if (trustScore != null || tgeEvent != null)
                Expanded(
                  child: RichText(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: TextStyle(
                        color: subTextColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                      children: [
                        if (trustScore != null) ...[
                          const TextSpan(text: 'Efficiency: '),
                          TextSpan(
                            text: '${(eff * 100).toInt()}%',
                            style: TextStyle(
                              color: EpochService.getEfficiencyColor(
                                trustScore,
                              ),
                            ),
                          ),
                        ],
                        if (trustScore != null && tgeEvent != null)
                          const TextSpan(text: ' • '),
                        if (tgeEvent != null)
                          TextSpan(text: 'TGE $tgeEvent/10'),
                      ],
                    ),
                  ),
                )
              else if (epochLabel != null)
                Expanded(
                  child: Text(
                    epochLabel,
                    style: TextStyle(
                      color: subTextColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else
                Text(
                  'Treasury balance',
                  style: TextStyle(color: subTextColor, fontSize: 11),
                ),
              const SizedBox(width: 8),
              Text(
                _formatPoints(points),
                style: const TextStyle(
                  color: AppTheme.accent,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEpochStep(int epochNum, int currentEpoch) {
    final isCompleted = epochNum < currentEpoch;
    final isActive = epochNum == currentEpoch;

    return Expanded(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 2,
                  color: (epochNum == 1 || epochNum == 6)
                      ? Colors.transparent
                      : (isCompleted || isActive
                            ? AppTheme.accent
                            : Colors.grey.withValues(alpha: 0.3)),
                ),
              ),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCompleted
                      ? AppTheme.accent
                      : (isActive
                            ? AppTheme.accent
                            : Colors.grey.withValues(alpha: 0.1)),
                ),
                child: Center(
                  child: isCompleted
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : Text(
                          '$epochNum',
                          style: TextStyle(
                            fontSize: 10,
                            color: isActive ? Colors.white : Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              Expanded(
                child: Container(
                  height: 2,
                  color: (epochNum == 5 || epochNum == 10)
                      ? Colors.transparent
                      : (isCompleted
                            ? AppTheme.accent
                            : Colors.grey.withValues(alpha: 0.3)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (isActive)
            const Text(
              'Active',
              style: TextStyle(
                fontSize: 10,
                color: AppTheme.accent,
                fontWeight: FontWeight.bold,
              ),
            )
          else if (isCompleted)
            const Text(
              'Done',
              style: TextStyle(fontSize: 10, color: AppTheme.accent),
            )
          else
            const Text(
              'Locked',
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
        ],
      ),
    );
  }
}

class RequirementItem {
  final String label;
  final bool isMet;

  RequirementItem(this.label, this.isMet);
}
