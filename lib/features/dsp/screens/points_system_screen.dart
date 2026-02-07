import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
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
import 'package:diaspora_nearby/features/dsp/widgets/exploration_progress_card.dart';

import 'package:diaspora_nearby/features/dsp/widgets/earning_activity_tile.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/dsp/services/epoch_service.dart';
import 'package:diaspora_nearby/features/community/services/community_service.dart'; 
import 'package:diaspora_nearby/features/dsp/widgets/country_leaderboard_item.dart';
import 'package:diaspora_nearby/features/community/repository/community_repository.dart';
import 'package:diaspora_nearby/features/community/models/community_data.dart';
import 'countries_leaderboard_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:diaspora_nearby/core/utils/location_utils.dart';
import 'package:diaspora_nearby/core/data/countries.dart' as data;


final referralStatsProvider = FutureProvider.family<Map<String, dynamic>?, String>((ref, userId) {
  return ref.read(pointsRepositoryProvider).getReferralStats(userId);
});

// [FIX] StreamProvider to prevent flickering
final userPointsStreamProvider = StreamProvider.family.autoDispose<UserPoints?, String>((ref, userId) {
  return ref.read(pointsRepositoryProvider).streamUserPoints(userId);
});

// Verified fields provider for detailed trust dashboard
final verifiedFieldsProvider = FutureProvider.family<Set<String>, String>((ref, userId) {
  return ref.read(trustServiceProvider).getVerifiedFields(userId);
});

final globalSupplyProvider = StreamProvider<int>((ref) {
  return ref.watch(pointsRepositoryProvider).streamGlobalSupply();
});

// [FIX] Provider for transactions to prevent stream recreation/flickering on rebuilds
final recentTransactionsProvider = StreamProvider.family.autoDispose<List<PointsTransaction>, String>((ref, userId) {
  return ref.watch(pointsRepositoryProvider).streamTransactionHistory(userId, limit: 10);
});

class PointsSystemScreen extends ConsumerStatefulWidget {
  const PointsSystemScreen({super.key});

  @override
  ConsumerState<PointsSystemScreen> createState() => _PointsSystemScreenState();
}

class _PointsSystemScreenState extends ConsumerState<PointsSystemScreen> {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndGenerateCode();
    });
  }


  Future<void> _checkAndGenerateCode() async {
    final userId = ref.read(authRepositoryProvider).currentUser?.uid;
    if (userId == null) return;

    final stats = await ref.read(pointsRepositoryProvider).getReferralStats(userId);
    if (stats == null) {
      final profile = await ref.read(profileRepositoryProvider).getUserProfile(userId);
      if (profile != null) {
        final firstName = profile.firstName;
        final countryCode = profile.homeLocation.countryCode ?? 'TZ';
        await ref.read(pointsRepositoryProvider).generateReferralCode(userId, firstName, countryCode);
        if (mounted) {
          ref.invalidate(referralStatsProvider(userId));
        }
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
    // [FIX] Use ref.watch for stream to prevent flickering on rebuilds
    final userPointsAsync = ref.watch(pointsRepositoryProvider).streamUserPoints(userId);
    final userPointsValue = ref.watch(userPointsStreamProvider(userId));
    final trustDataAsync = ref.watch(userTrustProvider(userId));
    final referralStatsAsync = ref.watch(referralStatsProvider(userId));
    // [FIX] Use provider stream
    final transactionsStream = ref.watch(recentTransactionsProvider(userId).stream);

     return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor, // Use theme background
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D5A47), // Keep Hero Sage for brand identity
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        title: const Text('Diaspora Social Points', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: userPointsValue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (userPoints) {
           if (userPoints == null) return const Center(child: Text('No points data'));
           
           return DefaultTabController(
             length: 3,
             child: Column(
               children: [
                 // --- Tab Bar ---
                 Container(
                   color: const Color(0xFF2D5A47),
                   child: TabBar(
                     indicatorColor: AppTheme.accent,
                     indicatorWeight: 3,
                     labelColor: Colors.white,
                     unselectedLabelColor: Colors.white60,
                     labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                     tabs: const [
                       Tab(text: 'DASHBOARD'),
                       Tab(text: 'EARNING'),
                       Tab(text: 'TRUST & TGE'),
                     ],
                   ),
                 ),
                 
                 // --- Tab Content ---
                 Expanded(
                   child: TabBarView(
                     children: [
                       _buildDashboardTab(context, userPoints, trustDataAsync, referralStatsAsync, transactionsStream),
                       _buildEarningTab(context, userPoints, referralStatsAsync),
                       _buildTrustTab(context, userPoints, trustDataAsync, userId),
                     ],
                   ),
                 ),
               ],
             ),
           );
        },
      ),
    );
  }

  // --- TAB 1: DASHBOARD ---
  Widget _buildDashboardTab(
    BuildContext context, 
    UserPoints userPoints, 
    AsyncValue<TrustData?> trustDataAsync,
    AsyncValue<Map<String, dynamic>?> referralStatsAsync,
    Stream<List<PointsTransaction>> transactionsStream,
  ) {
     return SingleChildScrollView(
       child: SafeArea(
         top: false,
         bottom: true, // [FIX] Add bottom safe area
         child: Column(
           children: [
             // Dashboard Body
           Padding(
             padding: const EdgeInsets.symmetric(horizontal: AppTheme.pageHorizontalPadding),
             child: Column(
               crossAxisAlignment: CrossAxisAlignment.start,
               children: [
                 const SizedBox(height: 16),
                 _buildSectionHeader('DASHBOARD', 'Overview'),
                 _buildBalanceSummary(context, userPoints, trustDataAsync.value?.trustScore ?? 0.0),
                 const SizedBox(height: AppTheme.sectionVerticalPadding),
                 
                 // Quick Actions / Streak
                 _buildStreakCard(context, userPoints),
                 const SizedBox(height: 16),
                 
                 // Race to 1 Billion (Epoch 1)
                 // Race to 1 Trillion Scale
                 _buildPlatformStatusCard(context),
                 
                 // Current Epoch Details
                 _buildEpochDetailCard(context, userPoints),
                 
                 // Recent Activity
                 _buildSectionHeader('LIVE ACTIVITY', 'Recent Transactions'),
                 _buildTransactionHistory(context, transactionsStream),
                 const SizedBox(height: 40),
               ],
             ),
           ),
         ],
       ),
     ));
  }

  // --- TAB 2: EARNING (Proof of Activity) ---
  Widget _buildEarningTab(
    BuildContext context, 
    UserPoints userPoints, 
    AsyncValue<Map<String, dynamic>?> referralStatsAsync
  ) {
    // Implement Earning Activities List
    return SingleChildScrollView(
       padding: const EdgeInsets.symmetric(
         horizontal: AppTheme.pageHorizontalPadding, 
         vertical: AppTheme.sectionVerticalPadding
       ),
       child: SafeArea(
         top: false,
         bottom: true,
         child: Column(
           crossAxisAlignment: CrossAxisAlignment.start,
           children: [
             // [NEW] Ecosystem Section at the TOP
             _buildEcosystemWalletsSection(),
             const SizedBox(height: 32),
             
             const Text(
               'Proof of Activity - PoA',
               style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
             ),
             const SizedBox(height: 8),
             Text(
               'Earn DSP by actively contributing to the network. Interaction creates value.',
               style: TextStyle(color: Theme.of(context).hintColor),
             ),
             const SizedBox(height: 24),
            
            // Growth
            _buildSectionHeader('GROWTH', 'Starting Out'),
            EarningActivityTile(
              title: 'New User Bonus',
              subtitle: 'Just for joining!',
              icon: LucideIcons.gift,
              rewardAmount: 1000,
              isCompleted: true,
              iconColor: Colors.purple,
            ),
            referralStatsAsync.when(
               data: (stats) => EarningActivityTile(
                 title: 'Refer Family & Friends',
                 subtitle: 'Per invited user',
                 icon: LucideIcons.users,
                 rewardAmount: 1000,
                 progressLabel: '${stats?['usedCount'] ?? 0} Invited',
                 iconColor: Colors.blue,
               ),
               loading: () => const SizedBox.shrink(),
               error: (_,__) => const SizedBox.shrink(),
            ),
              EarningActivityTile(
              title: 'Complete Profile',
              subtitle: 'Add photo & details',
              icon: LucideIcons.userCheck,
              rewardAmount: 1000,
              isCompleted: userPoints.completedExplorationActions.contains('complete_profile'),
              iconColor: Colors.green,
            ),
             EarningActivityTile(
               title: 'Connect Family',
               subtitle: 'Verified family member',
               icon: LucideIcons.heart,
               rewardAmount: 1000,
               iconColor: Colors.pinkAccent,
               earnedAmount: userPoints.lifetimeEarnings['family_connection'],
             ),
             
             const SizedBox(height: 24),
             _buildSectionHeader('ENGAGEMENT', 'Daily Activity'),
             EarningActivityTile(
                title: 'Send Messages',
                subtitle: 'To family or friends',
                icon: LucideIcons.send,
                rewardAmount: 10,
                progress: userPoints.dailyMessageCount / 100.0,
                progressLabel: '${userPoints.dailyMessageCount} sent today',
                iconColor: Colors.orange,
                earnedAmount: userPoints.lifetimeEarnings['daily_message'],
             ),
             EarningActivityTile(
                title: 'Start New DM',
                subtitle: 'Reach out to someone new',
                icon: LucideIcons.messageSquarePlus,
                rewardAmount: 100,
                iconColor: Colors.blueAccent,
                earnedAmount: userPoints.lifetimeEarnings['started_new_dm'],
             ),
             EarningActivityTile(
                title: 'Community Post',
                subtitle: 'Share with your group',
                icon: LucideIcons.megaphone,
                rewardAmount: 100,
                progress: userPoints.dailyCommunitiesMessaged.length / 1.0, // binary 0 or 1 really
                progressLabel: userPoints.dailyCommunitiesMessaged.isNotEmpty ? 'Posted' : '0 Posted',
                isCompleted: userPoints.dailyCommunitiesMessaged.isNotEmpty,
                iconColor: Colors.purpleAccent,
                earnedAmount: userPoints.lifetimeEarnings['community_message'],
             ),
             EarningActivityTile(
                title: 'Verify Peer (L2)',
                subtitle: 'Vouch for user details',
                icon: LucideIcons.shieldCheck,
                rewardAmount: 100,
                iconColor: AppTheme.accent,
                earnedAmount: userPoints.lifetimeEarnings['verifier_reward'],
             ),
            EarningActivityTile(
                 title: 'Share Content',
                 subtitle: 'Share externally (In/Out)',
                 icon: LucideIcons.share2,
                 rewardAmount: 100,
                 progress: (userPoints.dailyShareCount) / 5.0,
                 progressLabel: '${userPoints.dailyShareCount} sent',
                 iconColor: Colors.teal,
                 earnedAmount: userPoints.lifetimeEarnings['daily_share'],
             ),
             // [NEW] Missing Activities from DSP_EARNING_MODEL_REFINED.md
             EarningActivityTile(
                title: 'Share Invite Code',
                subtitle: 'Post your link manually',
                icon: LucideIcons.qrCode,
                rewardAmount: 100,
                iconColor: Colors.cyan,
                earnedAmount: userPoints.lifetimeEarnings['share_invite_code'],
             ),
             EarningActivityTile(
                title: 'Join Public Group',
                subtitle: 'Enter a public circle',
                icon: LucideIcons.users,
                rewardAmount: 100,
                iconColor: Colors.lightBlue,
                earnedAmount: userPoints.lifetimeEarnings['join_public_group'],
             ),
            EarningActivityTile(
                title: 'Join Private Group',
                subtitle: 'Enter a gated circle',
                icon: LucideIcons.lock,
                rewardAmount: 100,
                iconColor: Colors.indigoAccent,
                earnedAmount: userPoints.lifetimeEarnings['join_private_group'],
             ),
            
            const SizedBox(height: 24),
            _buildSectionHeader('IMPACT', 'High Value Actions'),
            EarningActivityTile(
              title: 'Create an Event',
              subtitle: 'Organize local gathering',
              icon: LucideIcons.calendar,
              rewardAmount: 1000,
              iconColor: Colors.redAccent,
              earnedAmount: userPoints.lifetimeEarnings['create_event'],
            ),
            EarningActivityTile(
              title: 'Verify Event Check-in',
              subtitle: 'Scan attendee QR',
              icon: LucideIcons.qrCode,
              rewardAmount: 1000,
              iconColor: Colors.black87,
              earnedAmount: userPoints.lifetimeEarnings['verified_check_in'],
            ),
            EarningActivityTile(
              title: 'Create Org / Business', 
              subtitle: 'List business/non-profit',
              icon: LucideIcons.building,
              rewardAmount: 1000,
              iconColor: Colors.indigo,
              earnedAmount: userPoints.lifetimeEarnings['create_organization'],
            ),
            EarningActivityTile(
              title: 'Host a Traveler',
              subtitle: 'Verified Hospitality',
              icon: LucideIcons.home,
              rewardAmount: 1000,
              iconColor: Colors.brown,
              earnedAmount: userPoints.lifetimeEarnings['host_a_traveler'],
            ),
            EarningActivityTile(
              title: 'Maintenance Streak',
              subtitle: '10-Day Streak',
              icon: LucideIcons.flame,
              rewardAmount: 1000,
              progress: userPoints.currentStreak / 10.0,
              progressLabel: '${userPoints.currentStreak}/10 days',
              iconColor: Colors.deepOrange,
              earnedAmount: userPoints.lifetimeEarnings['maintenance_streak_bonus'],
            ),
            EarningActivityTile(
              title: 'Legendary Streak',
              subtitle: '100-Day Streak',
              icon: LucideIcons.trophy,
              rewardAmount: 10000,
              progress: userPoints.currentStreak / 100.0,
              progressLabel: '${userPoints.currentStreak}/100 days',
              iconColor: Colors.amber,
              earnedAmount: userPoints.lifetimeEarnings['legendary_streak_bonus'],
            ),

             
         ],
       ),
    ));
  }

  // --- TAB 3: TRUST & TGE (Proof of Community Trust) ---
  Widget _buildTrustTab(
    BuildContext context, 
    UserPoints userPoints, 
    AsyncValue<TrustData?> trustDataAsync,
    String userId,
  ) {
    // Will implement logic from DspGuideView here
    // Need to fetch verified fields properly if not passed
    // For now, placeholder with FutureBuilder for verified fields if needed
    final trustData = trustDataAsync.value;
    final curScore = trustData?.trustScore ?? 0.0;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.pageHorizontalPadding,
        vertical: AppTheme.sectionVerticalPadding
      ),
      child: SafeArea(
        top: false,
        bottom: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
             const Text(
                'Proof of Community Trust - PoCT',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Earning is only half the battle. TrustScore determines your TGE eligibility and swap efficiency.',
                style: TextStyle(color: Theme.of(context).hintColor),
              ),
            const SizedBox(height: 24),
            
            // Trust Slider Vis
            _buildSubHeader('The Trust Slider'),
            Text('How others rate you affects your score:', style: TextStyle(color: Theme.of(context).hintColor)),
            const SizedBox(height: 8),
              _buildTrustIndicator(AppTheme.error, 'Red (0-20)', 'Low Trust'),
              _buildTrustIndicator(Colors.deepOrange, 'Deep Orange (21-40)', 'Basic Trust'),
              _buildTrustIndicator(Colors.amber, 'Amber (41-60)', 'Medium Trust'),
              _buildTrustIndicator(Colors.lightGreen, 'Light Green (61-80)', 'Standard Trust'),
              _buildTrustIndicator(AppTheme.accent, 'Sage Green (81-100)', 'High Trust'),
             
            const SizedBox(height: 24),
            _buildSubHeader('Your Status Journey'),
             const SizedBox(height: 16), // [NEW] Added margin between title and first card
             // We need 'daysActive' calculation here
             // We can calculate it from userPoints.signupDate
              Builder(
                builder: (context) {
                  final daysActive = userPoints.signupDate != null 
                     ? DateTime.now().difference(userPoints.signupDate!).inDays 
                     : 0;
                  return _buildLevelDashboard(context, trustData, daysActive, userPoints.totalPoints);
                }
              ),
             
             const SizedBox(height: 24),
             _buildSubHeader('TGE Efficiency Gates'),
             const SizedBox(height: 16),
             _buildEarningGateTable(curScore),
             

        ],
      ),
    ));
  }

  // --- HELPERS FOR TRUST & TGE TABS ---


  // --- RESTORED DASHBOARD WIDGETS ---

  Widget _buildHero(BuildContext context, UserPoints points) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 20, // Adjusted padding since app bar is visible
        bottom: 30,
        left: AppTheme.pageHorizontalPadding,
        right: AppTheme.pageHorizontalPadding,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF2D5A47), // Match AppBar
      ),
      child: Column(
        children: [
          const Icon(
            LucideIcons.coins,
            size: 60,
            color: AppTheme.accent,
          ),
          const SizedBox(height: 16),
          Text(
            '${NumberFormat('#,###').format(points.availablePoints)} DSP',
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Phase: Progressing to Epoch 1',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String subtitle, String title, {double titleSize = 20}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(subtitle, style: const TextStyle(color: AppTheme.accent, letterSpacing: 1.2, fontWeight: FontWeight.bold, fontSize: 11)),
        const SizedBox(height: 4),
        Text(title, style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildBalanceSummary(BuildContext context, UserPoints points, double trustScore) {
    final epochService = ref.read(epochServiceProvider);
    final double efficiency = epochService.calculateEfficiency(trustScore);
    final String efficiencyStatus = '${(efficiency * 100).toInt()}%';
    
    final int totalPoints = points.totalPoints;
    final int nextMilestone = 10000; // Confirmed 10k Genesis Gate
    final double progress = (totalPoints / nextMilestone).clamp(0.0, 1.0);
    // Qualification is now strictly DSP based (10k), trust score determines efficiency %
    final bool isQualified = totalPoints >= 10000;

    return Container(
      padding: AppTheme.cardPaddingEdgeInsets,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppTheme.standardBorderRadius),
        boxShadow: [
          BoxShadow(
             color: Colors.black.withOpacity(0.05),
             blurRadius: 10,
             offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
               Expanded(child: _buildBalanceItem('Trust Score', trustScore.toStringAsFixed(0), LucideIcons.shieldCheck)),
               Container(width: 1, height: 40, color: Colors.grey.withOpacity(0.2)),
               Expanded(child: _buildBalanceItem('Net Balance', NumberFormat('#,###').format(totalPoints), LucideIcons.wallet)),
               Container(width: 1, height: 40, color: Colors.grey.withOpacity(0.2)),
               Expanded(child: _buildBalanceItem('TGE Efficiency', efficiencyStatus, LucideIcons.barChart2)),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.grey.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation(isQualified ? AppTheme.accent : Colors.orange),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${NumberFormat('#,###').format(totalPoints)} / 10,000 DSP', style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
              if (isQualified) 
                 const Text('QUALIFIED', style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold))
              else
                 Text('Need ${NumberFormat('#,###').format(10000 - totalPoints)} more DSP', style: const TextStyle(fontSize: 11, color: Colors.orange)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildBalanceItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 20, color: AppTheme.accent),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: TextStyle(color: Theme.of(context).hintColor, fontSize: 11)),
      ],
    );
  }

  Widget _buildStreakCard(BuildContext context, UserPoints points) {
     return Container(
       padding: AppTheme.cardPaddingEdgeInsets,
       decoration: BoxDecoration(
         color: AppTheme.accent.withOpacity(0.05),
         borderRadius: BorderRadius.circular(AppTheme.standardBorderRadius),

       ),
       child: Row(
         children: [
           const Icon(LucideIcons.flame, color: Colors.deepOrange, size: 32),
           const SizedBox(width: 16),
           Column(
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
               Text('${points.currentStreak} Day Streak', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
               const Text('Consistency unlocks higher rewards', style: TextStyle(color: Colors.grey, fontSize: 12)),
             ],
           )
         ],
       ),
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
             final epoch = epochService.getCurrentCommunityEpoch(supply, members);
             final eventNumber = epochService.getCurrentTgeEventNumber(supply, members);
             return Container(
                margin: const EdgeInsets.symmetric(vertical: 0),
                padding: const EdgeInsets.all(4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                 children: [
                                  Text('EPOCH ${epoch.level} / 10', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  Text('Community Era', style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
                                 ],
                               ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).cardColor,
                                  borderRadius: BorderRadius.circular(AppTheme.standardBorderRadius),
                                ),
                                child: Text(
                                  'TGE $eventNumber / 10', 
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accent, fontSize: 12)
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
                    _buildSectionHeader('GLOBAL SCALE', 'Proof of Action'),
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
          error: (_,__) => const SizedBox.shrink(),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_,__) => const SizedBox.shrink(),
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
            Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            Text('${NumberFormat.compact().format(current)} / $label', style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: Colors.grey.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }

  Widget _buildEpochRoadmap(BuildContext context, int currentEpoch, int currentTge) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
         const Text('Epoch Roadmap', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
         const SizedBox(height: 12),
         Column(
           children: [
             Row(
               children: List.generate(5, (index) => _buildEpochStep(index + 1, currentEpoch)),
             ),
             const SizedBox(height: 16),
             Row(
               children: List.generate(5, (index) => _buildEpochStep(index + 6, currentEpoch)),
             ),
           ],
         )
      ],
    );
  }

  Widget _buildEpochDetailCard(BuildContext context, UserPoints userPoints) {
    final globalSupplyAsync = ref.watch(globalSupplyProvider);
    final globalMembersAsync = ref.watch(globalMemberCountProvider);
    final epochService = ref.watch(epochServiceProvider);

    return globalSupplyAsync.when(
      data: (supply) {
        return globalMembersAsync.when(
          data: (members) {
             final epoch = epochService.getCurrentCommunityEpoch(supply, members);
             final prevEpoch = epochService.getPreviousCommunityEpoch(epoch.level);
             
             final int prevDspTarget = prevEpoch?.dspTarget ?? 0;
             final int prevMemberTarget = prevEpoch?.memberTarget ?? 0;
             
             // Range-based progress calculation
             final double supplyProgress = ((supply - prevDspTarget) / (epoch.dspTarget - prevDspTarget)).clamp(0.0, 1.0);
             final double memberProgress = ((members - prevMemberTarget) / (epoch.memberTarget - prevMemberTarget)).clamp(0.0, 1.0);

             // Calculate Total Distributed for this Epoch
             final epochHistory = userPoints.tgeHistory.where((e) => e.epoch == epoch.level).toList();
             final double totalDistributed = epochHistory.fold(0.0, (sum, e) => sum + e.amount);

             return Container(
               margin: const EdgeInsets.symmetric(vertical: AppTheme.pageHorizontalPadding),
               padding: AppTheme.cardPaddingEdgeInsets,
               decoration: BoxDecoration(
                 color: Theme.of(context).cardColor,
                 borderRadius: BorderRadius.circular(AppTheme.standardBorderRadius),

               ),
               child: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   Row(
                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
                     crossAxisAlignment: CrossAxisAlignment.center,
                     children: [
                       _buildSectionHeader('CURRENT EPOCH PROGRESS', 'Epoch ${epoch.level}'),
                       if (totalDistributed > 0)
                         Container(
                           padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                           decoration: BoxDecoration(
                             color: Colors.green.withOpacity(0.1),
                             borderRadius: BorderRadius.circular(6),

                           ),
                           child: Text(
                             '${NumberFormat.compact().format(totalDistributed)} \$DIASPORA', 
                             style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 11)
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
                           const Text('Epoch Supply', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                           Text('Target: ${NumberFormat.compact().format(epoch.dspTarget)}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                         ],
                       ),
                       Text('${NumberFormat.compact().format(supply)} / ${NumberFormat.compact().format(epoch.dspTarget)}', style: const TextStyle(fontSize: 12, color: AppTheme.accent)),
                     ],
                   ),
                   const SizedBox(height: 6),
                   ClipRRect(
                     borderRadius: BorderRadius.circular(4),
                     child: LinearProgressIndicator(
                       value: supplyProgress, 
                       minHeight: 6,
                       backgroundColor: Colors.grey.withOpacity(0.1), 
                       color: AppTheme.accent 
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
                           const Text('Epoch Population', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                           Text('Target: ${NumberFormat.compact().format(epoch.memberTarget)}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                         ],
                       ),
                       Text('${NumberFormat.compact().format(members)} / ${NumberFormat.compact().format(epoch.memberTarget)}', style: const TextStyle(fontSize: 12, color: Colors.blue)),
                     ],
                   ),
                   const SizedBox(height: 6),
                   ClipRRect(
                     borderRadius: BorderRadius.circular(4),
                     child: LinearProgressIndicator(
                       value: memberProgress, 
                       minHeight: 6,
                       backgroundColor: Colors.grey.withOpacity(0.1), 
                       color: Colors.blue
                     ),
                   ),
                   const SizedBox(height: 24),
                   
                   // TGE Schedule
                   const Text('TGE Schedule', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                   const SizedBox(height: 12),
                   _buildTGEMilestones(context, epoch, supply, members, userPoints, epochService),
                 ],
               ),
             );
          },
          loading: () => const SizedBox.shrink(),
          error: (_,__) => const SizedBox.shrink(),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_,__) => const SizedBox.shrink(),
    );
  }

  Widget _buildTGEMilestones(BuildContext context, CommunityEpochDefinition epoch, int currentSupply, int currentMembers, UserPoints userPoints, EpochService epochService) {
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
           final memberTarget = prevMemberTarget + ((index + 1) * effectiveMemberStep);
           
           // Find specific record for this TGE
           final record = userPoints.tgeHistory.firstWhere(
              (e) => e.epoch == epoch.level && e.tgeNumber == tgeNumber,
              orElse: () => TgeDistributionRecord(epoch: -1, tgeNumber: -1, amount: 0, efficiency: 0, date: DateTime.now()),
           );
           
           final bool isSupplyMet = currentSupply >= stepTarget;
           final bool isMembersMet = currentMembers >= memberTarget;
           
           final bool isCompleted = isSupplyMet && isMembersMet;
           final bool isActive = !isCompleted && (currentSupply >= stepStart || currentMembers >= memberStart);
           
           double supplyProgress = 0.0;
           double memberProgress = 0.0;
           
            if (isActive) {
               supplyProgress = ((currentSupply - stepStart) / stepSize).clamp(0.0, 1.0);
               memberProgress = ((currentMembers - memberStart) / effectiveMemberStep).clamp(0.0, 1.0);
            }

          return Container(
            margin: const EdgeInsets.only(bottom: AppTheme.elementSpacing),
            padding: AppTheme.cardPaddingEdgeInsets,
            decoration: BoxDecoration(
              color: isActive ? AppTheme.accent.withOpacity(0.05) : Colors.transparent,
              borderRadius: BorderRadius.circular(AppTheme.standardBorderRadius),

            ),
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
                                  color: isCompleted ? Colors.grey.withOpacity(0.5) : (isActive ? Theme.of(context).textTheme.bodyMedium?.color : Colors.grey)
                                )
                              ),
                              if (isActive) 
                                Row(
                                  children: [
                                    Icon(Icons.bolt, size: 10, color: AppTheme.accent.withOpacity(0.7)),
                                    const SizedBox(width: 4),
                                    Text('${(supplyProgress * 100).toInt()}%', style: TextStyle(fontSize: 10, color: isActive ? AppTheme.accent : Colors.grey.withOpacity(0.5), fontWeight: FontWeight.bold)),
                                    const SizedBox(width: 8),
                                    Icon(Icons.people, size: 10, color: (isActive ? Colors.blue : Colors.grey).withOpacity(0.7)),
                                    const SizedBox(width: 4),
                                    Text('${(memberProgress * 100).toInt()}%', style: TextStyle(fontSize: 10, color: isActive ? Colors.blue : Colors.grey.withOpacity(0.5), fontWeight: FontWeight.bold)),
                                  ],
                                )
                              else if (isCompleted)
                                Builder(
                                  builder: (context) {
                                    double amount;
                                    double efficiency;
                                    Color textColor;
                                    
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '${NumberFormat.compact().format(record.amount)} \$DIASPORA', 
                                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.withOpacity(0.5), fontSize: 11)
                                        ),

                                        if (record.amount > 0)
                                          Text(
                                            '${(record.efficiency * 100).toInt()}%',
                                            style: TextStyle(fontSize: 9, color: Colors.grey.withOpacity(0.5))
                                          ),
                                      ],
                                    );
                                  }
                                )
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
                                backgroundColor: Colors.grey.withOpacity(0.1),
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
                                backgroundColor: Colors.grey.withOpacity(0.1),
                                color: Colors.blue,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${NumberFormat.compact().format(currentSupply)} / ${NumberFormat.compact().format(stepTarget)} DSP',
                                  style: const TextStyle(fontSize: 9, color: AppTheme.accent)
                                ),
                                Text(
                                  '${NumberFormat.compact().format(currentMembers)} / ${NumberFormat.compact().format(memberTarget)} Users',
                                  style: const TextStyle(fontSize: 9, color: Colors.blue)
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // User Status Section
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.withOpacity(0.1)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('YOUR STATUS', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
                                  const SizedBox(height: 16),
                                    // Row 1: Trust Check (Adopt PoCT Spectrum Color)
                                    Builder(builder: (context) {
                                      final currentTrust = userPoints.trustScore ?? 0;
                                      Color trustColor = AppTheme.error;
                                      if (currentTrust >= 81) trustColor = AppTheme.accent;
                                      else if (currentTrust >= 61) trustColor = Colors.lightGreen;
                                      else if (currentTrust >= 41) trustColor = Colors.amber;
                                      else if (currentTrust >= 21) trustColor = Colors.deepOrange;
                                      
                                      return Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text('Trust Score', style: TextStyle(fontSize: 10)),
                                          Text(
                                            '$currentTrust PoCT',
                                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: trustColor),
                                          ),
                                        ],
                                      );
                                    }),
                                  const SizedBox(height: 16),
                                  // Row 2: Balance Check (Remove Check Emoji)
                                  Builder(builder: (context) {
                                    final epochDef = epochService.getEpoch(epoch.level);
                                    final currentBalance = userPoints.availablePoints;
                                    final requiredBalance = epochDef.minDspRequired;
                                    final isBalanceMet = currentBalance >= requiredBalance;
                                    
                                    return Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('DSP Balance', style: TextStyle(fontSize: 10)),
                                        Text(
                                          '${NumberFormat.compact().format(currentBalance)} / ${NumberFormat.compact().format(requiredBalance)} DSP',
                                          style: TextStyle(fontSize: 10, color: isBalanceMet ? Colors.green : Colors.orange, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    );
                                  }),
                                  const SizedBox(height: 16),
                                  // Row 3: Efficiency (Replace label and align)
                                  Builder(builder: (context) {
                                     final potential = epochService.calculateTGESwap(
                                        epochNumber: epoch.level, 
                                        currentDspBalance: userPoints.availablePoints.toDouble(), 
                                        trustScore: userPoints.trustScore ?? 0
                                     );
                                     double efficiency = 0.0;
                                     final trust = userPoints.trustScore ?? 0;
                                     if (trust > 0) {
                                        efficiency = (trust / 10).ceil() / 10.0;
                                        if (efficiency > 1.0) efficiency = 1.0;
                                     }
                                     
                                     return Row( 
                                       mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                       children: [
                                         const Text('Efficiency', style: TextStyle(fontSize: 10)),
                                         Text(
                                           '${(efficiency * 100).toInt()}%',
                                           style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.accent),
                                         ),
                                       ],
                                     );
                                  }),
                                  const SizedBox(height: 16),
                                  // Row 4: Qualification Status
                                  Builder(builder: (context) {
                                     final epochDef = epochService.getEpoch(epoch.level);
                                     final isQualified = userPoints.availablePoints >= epochDef.minDspRequired;
                                     
                                     return Row( 
                                       mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                       children: [
                                         const Text('Status', style: TextStyle(fontSize: 10)),
                                         Text(
                                           isQualified ? 'QUALIFIED' : 'NOT QUALIFIED',
                                           style: TextStyle(
                                             fontSize: 10, 
                                             fontWeight: FontWeight.bold, 
                                             color: isQualified ? Colors.green : Colors.grey
                                           ),
                                         ),
                                       ],
                                     );
                                  }),
                                ],
                              ),
                            )
                          ] else if (isCompleted) ...[
                             const Text('Distributed', style: TextStyle(fontSize: 10, color: Colors.green)),
                          ] else 
                            Text('Unlocks at ${NumberFormat.compact().format(stepStart)} DSP', style: const TextStyle(fontSize: 10, color: Colors.grey)),
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


  Widget _buildTransactionHistory(BuildContext context, Stream<List<PointsTransaction>> stream) {
    return StreamBuilder<List<PointsTransaction>>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('No recent activity')));
        }
        return Column(
          children: snapshot.data!.map((tx) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: AppTheme.accent.withOpacity(0.1),
              child: _getIconForAction(tx.action),
            ),
            title: Text(tx.displayAction, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text(DateFormat.yMMMd().format(tx.timestamp), style: const TextStyle(fontSize: 12)),
            trailing: Text('+${tx.points}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
          )).toList(),
        );
      },
    );
  }

  Widget _getIconForAction(String action) {
    if (action.contains('message')) return const Icon(LucideIcons.messageCircle, size: 16, color: AppTheme.accent);
    if (action.contains('referral')) return const Icon(LucideIcons.users, size: 16, color: AppTheme.accent);
    if (action.contains('share')) return const Icon(LucideIcons.share2, size: 16, color: AppTheme.accent);
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
                style: TextStyle(fontSize: 14, color: Theme.of(context).textTheme.bodyMedium?.color),
                children: [
                  TextSpan(text: '$title: ', style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                  TextSpan(text: desc),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildLevelDashboard(BuildContext context, TrustData? trustData, int daysActive, int dspBalance) {
    final curScore = trustData?.trustScore ?? 0.0;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Account Status Journey (Age/Days Active)
        _buildSubHeader('Account Status'),
        const SizedBox(height: 12),
        _buildStatusCard(
          context,
          title: 'Newcomer',
          level: TrustLevel.lowTrust, // Reusing enum for color/icon logic if needed, or just style manually
          isActive: daysActive < 10,
          requirements: [
            RequirementItem('Active < 10 Days', daysActive < 10),
          ],
          progress: [daysActive / 10.0],
          progressLabels: ['$daysActive / 10 Days'],
          isCompleted: daysActive >= 10,
          levelColor: Colors.blueGrey,
        ),
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
          levelColor: Colors.blue,
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
          levelColor: Colors.purple,
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
          requirements: [
            RequirementItem('Score: 0 - 20', curScore >= 0),
          ],
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
          requirements: [
            RequirementItem('Score: 21 - 40', curScore > 20),
          ],
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
          requirements: [
            RequirementItem('Score: 41 - 60', curScore > 40),
          ],
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
          requirements: [
            RequirementItem('Score: 61 - 80', curScore > 60),
          ],
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
          requirements: [
            RequirementItem('Score: 81 - 100', curScore > 80),
          ],
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
    String? currentStats,
    bool isCompleted = false,
    Color levelColor = AppTheme.accent,
  }) {
    final color = isActive ? levelColor : (isCompleted ? Colors.green : Colors.grey);
    final backgroundColor = isActive 
        ? levelColor.withOpacity(0.05) 
        : (isCompleted ? Colors.green.withOpacity(0.02) : Colors.grey.withOpacity(0.05));
    final borderColor = isActive 
        ? levelColor.withOpacity(0.3) 
        : (isCompleted ? Colors.green.withOpacity(0.2) : Colors.grey.withOpacity(0.1));

    return Opacity(
      opacity: isActive || isCompleted ? 1.0 : 0.6,
      child: Container(
        width: double.infinity,
        padding: AppTheme.cardPaddingEdgeInsets,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(AppTheme.standardBorderRadius),

        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isCompleted ? LucideIcons.checkCircle2 : (isActive ? LucideIcons.star : LucideIcons.lock),
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.accent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('CURRENT', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ...requirements.map((req) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(
                    req.isMet ? LucideIcons.checkCircle2 : LucideIcons.circle,
                    size: 14,
                    color: req.isMet ? Colors.green : color.withOpacity(0.5),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      req.label,
                      style: TextStyle(
                        fontSize: 13,
                        color: req.isMet ? Theme.of(context).textTheme.bodyMedium?.color : Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7),
                        fontWeight: req.isMet ? FontWeight.w500 : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            )),
            if (isActive && !isCompleted && progress != null && progressLabels != null) ...[
              const SizedBox(height: 16),
              const Text('Next Level Progress:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 8),
              for (int i = 0; i < progress.length; i++) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(progressLabels[i], style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    Text('${(progress[i].clamp(0.0, 1.0) * 100).toInt()}%', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress[i].clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: color.withOpacity(0.1),
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
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppTheme.standardBorderRadius),
      ),
      child: Column(
        children: [
          _buildEfficiencyRow('PoCT Score', 'Efficiency', 'Status', isHeader: true),
          _buildEfficiencyRow('91 - 100', '100%', 'Maximum Yield', textColor: AppTheme.accent),
          _buildEfficiencyRow('81 - 90', '90%', 'Very High Yield', textColor: Colors.green),
          _buildEfficiencyRow('71 - 80', '80%', 'High Yield', textColor: Colors.lightGreen),
          _buildEfficiencyRow('61 - 70', '70%', 'Good Yield', textColor: Colors.lime),
          _buildEfficiencyRow('51 - 60', '60%', 'Standard Yield', textColor: Colors.yellow[700]),
          _buildEfficiencyRow('41 - 50', '50%', 'Basic Yield', textColor: Colors.amber),
          _buildEfficiencyRow('31 - 40', '40%', 'Low Yield', textColor: Colors.orange),
          _buildEfficiencyRow('21 - 30', '30%', 'Very Low Yield', textColor: Colors.deepOrange),
          _buildEfficiencyRow('11 - 20', '20%', 'Minimal Yield', textColor: AppTheme.error),
          _buildEfficiencyRow('1 - 10', '10%', 'Entry Yield', textColor: AppTheme.error.withOpacity(0.7)),
          _buildEfficiencyRow('0', '0%', 'No Yield', textColor: Colors.grey),
        ],
      ),
    );
  }

  Widget _buildEfficiencyRow(String score, String rate, String status, {bool isHeader = false, bool isLast = false, Color? textColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isHeader ? AppTheme.accent.withOpacity(0.05) : null,

      ),
      child: Row(
        children: [
          Expanded(child: Text(score, style: TextStyle(fontSize: 12, fontWeight: isHeader ? FontWeight.bold : FontWeight.normal))),
          Expanded(child: Text(rate, style: TextStyle(
            fontSize: 12, 
            fontWeight: isHeader ? FontWeight.bold : FontWeight.bold, 
            color: isHeader ? null : (textColor ?? Colors.grey)
          ))),
          Expanded(child: Text(status, style: TextStyle(
            fontSize: 12, 
            fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
            color: isHeader ? null : textColor
          ))),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48),
      decoration: const BoxDecoration(
        color: AppTheme.accentDark,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.pageHorizontalPadding),
        child: Column(
          children: [
            const Text(
              'The Great Reset waits for no one.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 12),
            const Text(
              "Don't be a spectator to the future of social wealth. Be an owner.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 15),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: Colors.white),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: const Text('Start Your Journey Now', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
  // [NEW] Ecosystem Wallets (Home Country & Platform) - Moved from DiasporaCryptoScreen
  Widget _buildEcosystemWalletsSection() {
    final profile = ref.watch(userProfileProvider).value;
    final homeCountryCode = profile?.homeCountryCode;
    
    // [FIX] Fetch home location communities directly (not all user communities)
    // This ensures we show home country/continent treasuries, not host location
    final homeCountryCommunityAsync = homeCountryCode != null
        ? ref.watch(homeCountryCommunityProvider(homeCountryCode!))
        : const AsyncValue<Community?>.data(null);

    final homeCountryCommunity = homeCountryCommunityAsync.value;
    
    // Fetch home continent community using generated ID
    Community? continentCommunity;
    if (homeCountryCode != null) {
      final continentCode = getContinentByCountryCode(homeCountryCode);
      final continentName = getContinentName(continentCode);
      final continentId = generateCommunityId(
        locationType: 'home',
        type: 'continent',
        continent: continentName,
      );
      
      final continentAsync = ref.watch(communityProvider(continentId));
      continentCommunity = continentAsync.value;
    }
    
    // Fallback names if not joined yet
    // [NEW] Use CommunityChatUtils for naming convention (DRY)
    
    // 1. Continent
    String continentDisplayName = "Continent Community";
    if (continentCommunity != null) {
      continentDisplayName = CommunityChatUtils.generateCommunityNameFromParts(
        name: continentCommunity.name,
        locationType: continentCommunity.locationType ?? '',
        id: continentCommunity.id,
      );
    } else if (homeCountryCode != null) {
       final rawContinent = getContinentName(getContinentByCountryCode(homeCountryCode) ?? '');
       if (rawContinent.isNotEmpty) {
          continentDisplayName = CommunityChatUtils.generateCommunityNameFromParts(
            name: rawContinent,
            locationType: 'home', // Default context for treasury
            id: 'continent_$rawContinent',
          );
       }
    }
    
    // 2. Home Country
    String homeCountryDisplayName = "Home Country Community";
    if (homeCountryCommunity != null) {
      homeCountryDisplayName = CommunityChatUtils.generateCommunityNameFromParts(
        name: homeCountryCommunity.name,
        locationType: homeCountryCommunity.locationType ?? '',
        id: homeCountryCommunity.id,
      );
    } else if (homeCountryCode != null) {
      final countryData = data.getCountryByCode(homeCountryCode);
      if (countryData != null) {
        homeCountryDisplayName = CommunityChatUtils.generateCommunityNameFromParts(
            name: countryData.name,
            locationType: 'home',
             id: 'country_$homeCountryCode',
        );
      }
    }

    final systemTreasury = ref.watch(systemTreasuryProvider).value ?? {};
    final ecosystemPoints = systemTreasury['ecosystemPoints'] as int? ?? 0;
    final liquidityPoints = systemTreasury['liquidityPoints'] as int? ?? 0;
    final foundersPoints = systemTreasury['foundersPoints'] as int? ?? 0;

    // Use Distributed DSP balance (Linear increment)
    final homePoints = homeCountryCommunity?.points ?? 0;
    final continentPoints = continentCommunity?.points ?? 0;

    // Total Community Wealth (Sum of all 10% pots)
    final totalCommunityWealth = homePoints + continentPoints + ecosystemPoints + liquidityPoints + foundersPoints;
    
    // Global Epoch for labeling
    final epochService = EpochService();
    final globalCommunity = ref.watch(communityProvider('global_community')).value;
    final int globalMembers = globalCommunity?.memberCount ?? 0;
    final int globalCumulative = globalCommunity?.cumulativeEarnings ?? 0;
    final currentGlobalEpoch = epochService.getCurrentCommunityEpoch(globalCumulative, globalMembers);
    final int globalTgeEvent = epochService.getCurrentTgeEventNumber(globalCumulative, globalMembers);

    // Get Country Flag
    final countryData = homeCountryCode != null ? data.getCountryByCode(homeCountryCode) : null;
    final homeFlag = countryData?.flag ?? '🏳️';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // [NEW] Community Wealth Summary Card (The "50% Community card")
          // [NEW] Community Wealth Summary Card (Global Community Treasury)
          _buildWalletDisplayCard(
             title: 'Global Community Earnings',
             tokenBalance: null, // Global treasury address usually system-managed
             icon: LucideIcons.globe, 
             color: AppTheme.accent,
             percentage: '50%', // [FIX] Move percentage here for consistent placement
             balance: _formatPoints(totalCommunityWealth),
             epochLabel: 'Aggregated Distributed DSP', 
             avatarWidget: CommunityChatUtils.getCommunityAvatar(
                context: context,
                type: 'global',
                locationType: 'global', 
                communityId: 'global_community', // Valid dummy ID for global
                size: 20, 
             ),
          ),
          // Note: margins handled by _buildWalletDisplayCard's internal padding if standard,
          // but _buildWalletDisplayCard uses card decoration. 
          // The previous manual card had page padding. 
          // Check _buildWalletDisplayCard implementation:
          // It returns a container with decoration but NO external padding.
          // The parent list (SingleChildScrollView) has padding: AppTheme.pageHorizontalPadding.
          // So this card will align correctly with other cards.
          const SizedBox(height: 24),
          
          // 1. Continent Treasury
          _buildWalletDisplayCard(
             title: '$continentDisplayName Treasury',
             tokenBalance: continentCommunity?.walletAddress, 
             icon: LucideIcons.globe, // Fallback icon, mostly unused if avatarWidget is present
             color: AppTheme.accent,
             percentage: '10%', 
             balance: _formatPoints(continentPoints),
             epochLabel: 'Epoch ${currentGlobalEpoch.level} • TGE $globalTgeEvent/10',
             avatarWidget: CommunityChatUtils.getCommunityAvatar(
                context: context,
                type: 'continent',
                locationType: 'home', // or 'host', but treasury usually implies belonging/home
                communityId: continentCommunity?.id, 
                // Fallback for visual generation if community object missing
                flag: null, 
                size: 20, 
             ),
          ),
          const SizedBox(height: 12),

          // 2. Home Country Treasury
          _buildWalletDisplayCard(
             title: '$homeCountryDisplayName Treasury',
             tokenBalance: homeCountryCommunity?.walletAddress,
             icon: LucideIcons.flag,
             color: Colors.green,
             percentage: '10%',
             balance: _formatPoints(homePoints),
             epochLabel: 'Epoch ${currentGlobalEpoch.level} • TGE $globalTgeEvent/10',
             avatarWidget: CommunityChatUtils.getCommunityAvatar(
                context: context,
                type: 'country',
                locationType: 'home',
                communityId: homeCountryCommunity?.id,
                homeCountryCode: homeCountryCode, // Pass code for flag generation if community obj missing
                size: 20,
             ),
          ),
          const SizedBox(height: 12),
          
          // 3. Ecosystem Treasury
          _buildWalletDisplayCard(
             title: 'Ecosystem Treasury',
             tokenBalance: systemTreasury['ecosystemWallet'], 
             icon: LucideIcons.layers,
             color: AppTheme.accent,
             percentage: '10%', 
             balance: _formatPoints(ecosystemPoints), 
             epochLabel: 'Epoch ${currentGlobalEpoch.level} • TGE $globalTgeEvent/10',
             avatarWidget: Container(
               width: 24, 
               height: 24,
               decoration: const BoxDecoration(
                 shape: BoxShape.circle,
                 color: Colors.transparent, // Explicitly transparent
               ),
               child: Image.asset('assets/icons/logo-original.png', fit: BoxFit.contain),
             ),
          ),
          const SizedBox(height: 12),
          
          // 4. Liquidity & AMM
          _buildWalletDisplayCard(
            title: 'Liquidity & AMM',
            tokenBalance: systemTreasury['liquidityWallet'], 
            icon: LucideIcons.repeat,
            color: AppTheme.accent,
            percentage: '10%',
            balance: _formatPoints(liquidityPoints),
            epochLabel: 'Epoch ${currentGlobalEpoch.level} • TGE $globalTgeEvent/10',
          ),
          const SizedBox(height: 12),

          // 5. Founders & Core Team
          _buildWalletDisplayCard(
            title: 'Founders & Core Team',
            tokenBalance: systemTreasury['foundersWallet'], 
            icon: LucideIcons.users,
            color: AppTheme.accent,
            percentage: '10%',
            balance: _formatPoints(foundersPoints),
            epochLabel: 'Epoch ${currentGlobalEpoch.level} • TGE $globalTgeEvent/10',
          ),
          const SizedBox(height: 24),
          
          // Admin Task: Sync Balances
          Center(
            child: TextButton.icon(
              onPressed: () async {
                try {
                  await ref.read(pointsServiceProvider).syncTreasuryBalances();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Treasury balances synchronized!')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error syncing: $e')),
                    );
                  }
                }
              },
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Sync Treasury Balances'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.accent.withOpacity(0.7),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final leaderboardAsync = ref.watch(countryLeaderboardProvider);


    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.pageHorizontalPadding),
          child: _buildSectionHeader('CURRENCY', 'Country Epoch DSP Leaderboard'),
        ),
        const SizedBox(height: 12), // Added 12 + 12 = 24px gap
        Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.01) : Colors.black.withOpacity(0.01),
            borderRadius: BorderRadius.circular(AppTheme.standardBorderRadius),
          ),
          child: Column(
            children: [
                ...leaderboardAsync.maybeWhen(
                  data: (countries) => countries.take(10).map((country) => CountryLeaderboardItem(
                    country: country, 
                  )),
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
                MaterialPageRoute(builder: (context) => const CountriesLeaderboardScreen()),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.accent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.standardBorderRadius)),
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
    required String? tokenBalance,
    required IconData icon,
    required Color color,
    required String percentage,
    required String balance, 
    String? epochLabel,
    Widget? avatarWidget, // [NEW] Added for flags/globes
  }) {
      // Theme aware colors
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final themeTextColor = isDark ? Colors.white : Colors.black87;
      final subTextColor = isDark ? Colors.white54 : Colors.black54;
      // [FIX] Adjusted opacity for minimal contrast (0.02 -> 0.01)
      final cardColor = isDark ? Colors.white.withOpacity(0.01) : Colors.black.withOpacity(0.01);

      return Container(
        padding: AppTheme.cardPaddingEdgeInsets,
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(AppTheme.standardBorderRadius),
        ),
       child: Column(
         crossAxisAlignment: CrossAxisAlignment.start,
         children: [
            Row(
              children: [
                 if (avatarWidget != null) ...[
                   avatarWidget!,
                   const SizedBox(width: 8),
                 ] else ...[
                   Icon(icon, size: 18, color: color),
                   const SizedBox(width: 8),
                 ],
                 Expanded(
                   child: Text(
                     title, 
                     style: TextStyle(fontWeight: FontWeight.bold, color: themeTextColor, fontSize: 14)
                   )
                 ),
                 if (percentage.isNotEmpty)
                   Text(
                     percentage, 
                     style: const TextStyle(
                       fontWeight: FontWeight.bold, 
                       color: AppTheme.accent, 
                       fontSize: 14
                     )
                   ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
               width: double.infinity,
               padding: const EdgeInsets.all(12),
               decoration: BoxDecoration(
                 color: isDark ? Colors.white.withOpacity(0.02) : Colors.black.withOpacity(0.02),
                 borderRadius: BorderRadius.circular(AppTheme.standardBorderRadius),
               ),
               child: Text(
                 tokenBalance ?? 'Balance Pending TGE',
                 style: TextStyle(
                   fontFamily: 'monospace',
                   fontSize: 12,
                   color: tokenBalance != null ? themeTextColor : (isDark ? Colors.white38 : Colors.black38),
                   fontStyle: tokenBalance != null ? FontStyle.normal : FontStyle.italic,
                 ),
                 maxLines: 1,
                 overflow: TextOverflow.ellipsis,
               ),
            ),
            const SizedBox(height: 12),
            
            // Row 3: Epoch Info | Balance
             Row(
               children: [
                 if (epochLabel != null) 
                   Text(
                     epochLabel, 
                     style: TextStyle(
                       color: subTextColor, 
                       fontSize: 12, 
                       fontWeight: FontWeight.bold
                     )
                   )
                 else
                   Text(
                     'Treasury balance', 
                     style: TextStyle(
                       color: subTextColor, 
                       fontSize: 12
                     )
                   ),
                 const Spacer(),
                 Text(
                   balance, 
                   style: TextStyle(
                     color: themeTextColor, 
                     fontWeight: FontWeight.bold, 
                     fontSize: 14,
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
                    : (isCompleted || isActive ? AppTheme.accent : Colors.grey.withOpacity(0.3))
                )
              ),
              Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCompleted ? AppTheme.accent : (isActive ? AppTheme.accent : Colors.grey.withOpacity(0.1)),
                ),
                child: Center(
                  child: isCompleted 
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : Text('$epochNum', style: TextStyle(fontSize: 10, color: isActive ? Colors.white : Colors.grey, fontWeight: FontWeight.bold)),
                ),
              ),
              Expanded(
                child: Container(
                  height: 2, 
                  color: (epochNum == 5 || epochNum == 10) 
                    ? Colors.transparent 
                    : (isCompleted ? AppTheme.accent : Colors.grey.withOpacity(0.3))
                )
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (isActive)
            const Text('Active', style: TextStyle(fontSize: 10, color: AppTheme.accent, fontWeight: FontWeight.bold))
          else if (isCompleted)
             const Text('Done', style: TextStyle(fontSize: 10, color: AppTheme.accent))
          else
            const Text('Locked', style: TextStyle(fontSize: 10, color: Colors.grey)),
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
