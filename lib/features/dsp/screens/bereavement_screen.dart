import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/dsp/models/bereavement_model.dart';
import 'package:diaspora_nearby/features/profile/models/relationship.dart';
import 'package:diaspora_nearby/features/dsp/services/bereavement_service.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/profile/widgets/relationship_card.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:diaspora_nearby/features/dsp/services/exploration_registry.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart';

final _qualifiedRelativesProvider =
    FutureProvider.family<List<Relationship>, String>((ref, userId) {
      return ref.read(bereavementServiceProvider).getQualifiedRelatives(userId);
    });

final _potentialProxiesProvider =
    FutureProvider.family<List<ProfileData>, String>((ref, userId) {
      return ref.read(bereavementServiceProvider).getPotentialProxies(userId);
    });

final _eligibilityProvider = FutureProvider.family<EligibilityResult, String>((
  ref,
  userId,
) {
  return ref.read(bereavementServiceProvider).checkEligibility(userId);
});

class BereavementScreen extends ConsumerStatefulWidget {
  const BereavementScreen({super.key});

  @override
  ConsumerState<BereavementScreen> createState() => _BereavementScreenState();
}

class _BereavementScreenState extends ConsumerState<BereavementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    unawaited(_trackExploration());
  }

  Future<void> _trackExploration() async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user != null) {
      final rewarded = await ref
          .read(pointsServiceProvider)
          .trackExplorationReward(user.uid, ExplorationAction.dspBereavement);
      if (rewarded && mounted) {
        showExplorationRewardToast(context);
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bereavement Fund'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.accent,
          unselectedLabelColor: Colors.grey,
          indicatorColor: AppTheme.accent,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Beneficiaries'),
            Tab(text: 'Support'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [_OverviewTab(), _MembershipTab(), _ClaimsTab()],
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(
        left: AppTheme.cardPadding,
        right: AppTheme.cardPadding,
        top: AppTheme.cardPadding,
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero Section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: AppTheme.cardDecoration(
              context,
            ).copyWith(borderRadius: BorderRadius.circular(20)),
            child: Column(
              children: [
                const Icon(LucideIcons.heart, size: 48, color: AppTheme.accent),
                const SizedBox(height: 12),
                const Text(
                  'Dignity in Repatriation',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Community-pooled resources for repatriation and travel costs.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          const Text(
            'Support Benefits',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          _buildFeatureItem(
            context,
            icon: LucideIcons.plane,
            title: 'Full Repatriation',
            description: 'Up to \$50,000 for repatriation costs.',
          ),
          const SizedBox(height: 10),
          _buildFeatureItem(
            context,
            icon: LucideIcons.users,
            title: 'Family Travel',
            description: 'Round-trip flights for up to 4 members.',
          ),
          const SizedBox(height: 10),
          _buildFeatureItem(
            context,
            icon: LucideIcons.home,
            title: 'Funeral Expenses',
            description: 'Funeral home services and supplies.',
          ),
          const SizedBox(height: 10),
          _buildFeatureItem(
            context,
            icon: LucideIcons.coins,
            title: 'Earn Rewards',
            description: '100 DSP annually for contributing.',
          ),
          const SizedBox(height: 16),

          // Learn More link
          Center(
            child: GestureDetector(
              onTap: () => launchUrl(
                Uri.parse('https://diasporanearby.com/#bereavement'),
                mode: LaunchMode.externalApplication,
              ),
              child: Text(
                'Learn more about the Bereavement Fund →',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(
    BuildContext context, {
    required IconData icon,
    String? imagePath,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: imagePath != null
              ? EdgeInsets.zero
              : const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: imagePath != null
                ? Colors.transparent
                : AppTheme.cardDecoration(context).color,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: imagePath != null
              ? Image.asset(
                  imagePath,
                  width: 48,
                  height: 48,
                  fit: BoxFit.contain,
                )
              : Icon(icon, color: AppTheme.accent, size: 24),
        ),
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
                description,
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MembershipTab extends ConsumerStatefulWidget {
  const _MembershipTab();

  @override
  ConsumerState<_MembershipTab> createState() => _MembershipTabState();
}

class _MembershipTabState extends ConsumerState<_MembershipTab> {
  static BereavementMembership? _cachedMembership;
  BereavementMembership? _optimisticMembership;

  void _showSetupCoverageDialog(EligibilityResult eligibility) {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null) return;

    final relatives =
        ref.read(_qualifiedRelativesProvider(user.uid)).value ?? [];
    final potentialProxies =
        ref.read(_potentialProxiesProvider(user.uid)).value ?? [];

    showDialog(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: _SetupCoverageDialog(
          userId: user.uid,
          initialRelatives: relatives,
          potentialProxies: potentialProxies,
          onConfirm: (proxyId, coveredIds) =>
              _initiateMembership(proxyId, coveredIds),
        ),
      ),
    );
  }

  Future<void> _initiateMembership(
    String proxyId,
    List<String> coveredIds,
  ) async {
    final user = ref.read(authRepositoryProvider).currentUser;
    final profile = ref.read(userProfileProvider).value;

    if (user == null || profile == null) return;

    final prev = _optimisticMembership;
    setState(() {
      _optimisticMembership = BereavementMembership(
        userId: user.uid,
        country: profile.homeCountry ?? 'Unknown',
        status: MembershipStatus.pending_proxy,
        joinedDate: DateTime.now(),
        annualContribution: 100.0,
        supportNumber: 'DN-BER-PENDING',
        proxyUserId: proxyId,
        proxyStatus: ProxyStatus.pending,
        coveredFamilyMembers: coveredIds,
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Proxy request sent! Waiting for acceptance.'),
      ),
    );

    try {
      await ref
          .read(bereavementServiceProvider)
          .requestProxyAndJoin(
            userId: user.uid,
            country: profile.homeCountry ?? 'Unknown',
            proxyUserId: proxyId,
            coveredFamilyMembers: coveredIds,
          );
    } catch (e) {
      if (mounted) {
        setState(() => _optimisticMembership = prev);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _processPayment() async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null) return;

    final current =
        _optimisticMembership ??
        ref.read(membershipStreamProvider(user.uid)).value ??
        _cachedMembership;
    final prev = _optimisticMembership;
    if (current != null) {
      setState(() {
        _optimisticMembership = BereavementMembership(
          userId: current.userId,
          country: current.country,
          status: MembershipStatus.active,
          joinedDate: current.joinedDate,
          annualContribution: current.annualContribution,
          supportNumber: current.supportNumber,
          proxyUserId: current.proxyUserId,
          proxyStatus: ProxyStatus.accepted,
          coveredFamilyMembers: current.coveredFamilyMembers,
          nextPaymentDate: DateTime.now().add(const Duration(days: 365)),
        );
      });
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Beta Access Activated! Welcome to the Fund.'),
      ),
    );

    try {
      await ref
          .read(bereavementServiceProvider)
          .completeMembershipPayment(user.uid);
    } catch (e) {
      if (mounted) {
        setState(() => _optimisticMembership = prev);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Payment Error: $e')));
      }
    }
  }

  Widget _buildMembershipBody(
    BuildContext context,
    String uid,
    BereavementMembership? liveMembership,
  ) {
    final membership = _optimisticMembership ?? liveMembership;
    if (membership == null) {
      return _buildReadiness(uid);
    }

    if (membership.status == MembershipStatus.pending_proxy) {
      return _buildStatusPage(
        icon: LucideIcons.clock,
        title: 'Waiting for Proxy',
        description:
            'You have sent a request to your chosen proxy. Once they accept, you can proceed to payment.',
        color: Colors.orange,
      );
    }

    if (membership.status == MembershipStatus.pending_payment) {
      return _buildPaymentPage(membership);
    }

    final rels = ref.watch(_qualifiedRelativesProvider(membership.userId)).value ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 50),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: _buildStatusCard(context, membership),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              children: [
                _buildInfoRow('Support Number', membership.supportNumber),
                const Divider(),
                _buildInfoRow(
                  'Annual Contribution',
                  '\$${membership.annualContribution.round()}',
                ),
                const Divider(),
                _buildInfoRow('Home Country', membership.country),
                const Divider(),
                _buildInfoRow(
                  'Member Since',
                  DateFormat('MMM d, yyyy').format(membership.joinedDate),
                ),
                const Divider(),
                _buildInfoRow(
                  'Next Contribution',
                  membership.nextPaymentDate != null
                      ? DateFormat(
                          'MMM d, yyyy',
                        ).format(membership.nextPaymentDate!)
                      : 'N/A',
                ),
                const Divider(),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Beneficiaries & Proxy',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Your designated proxy and supported family members.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
          ),

          Container(
            margin: const EdgeInsets.all(16),
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.cardDecoration(context).color,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildBeneficiaryItem(
                  icon: LucideIcons.shieldAlert,
                  name: membership.proxyUserId != null
                      ? 'Proxy User (${membership.proxyUserId})'
                      : 'No Proxy',
                  relation: 'Designated Proxy',
                  isProxy: true,
                ),
                const Divider(),
                if (membership.coveredFamilyMembers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 16.0),
                    child: Text(
                      'No supported family members added yet.',
                      style: TextStyle(
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                else
                  Column(
                    children: membership.coveredFamilyMembers.map((id) {
                      String name = 'Unknown Member';
                      String relation = 'Relative';

                      if (id.startsWith('friend_')) {
                        name = id.replaceFirst('friend_', '');
                        relation = 'Friend';
                      } else {
                        final r = rels.where((k) => k.id == id).firstOrNull;
                        if (r != null) {
                          name = r.name;
                          relation = r.type;
                        } else if (id.isNotEmpty) {
                          name = 'Member ($id)';
                        }
                      }

                      return _buildBeneficiaryItem(
                        icon: LucideIcons.user,
                        name: name,
                        relation: relation,
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authRepositoryProvider).currentUser;
    if (user == null) return const Center(child: Text('Please log in'));

    // Pre-watch relatives & proxies so opening dialog is 0ms
    ref.watch(_qualifiedRelativesProvider(user.uid));
    ref.watch(_potentialProxiesProvider(user.uid));

    final membershipAsync = ref.watch(membershipStreamProvider(user.uid));
    if (membershipAsync.hasValue) {
      _cachedMembership = membershipAsync.value;
      if (membershipAsync.value != null &&
          _optimisticMembership != null &&
          membershipAsync.value!.status == _optimisticMembership!.status) {
        _optimisticMembership = null;
      }
    }

    return membershipAsync.when(
      data: (membership) => _buildMembershipBody(context, user.uid, membership),
      loading: () => _buildMembershipBody(context, user.uid, _cachedMembership),
      error: (e, st) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildPaymentPage(BereavementMembership membership) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.sparkles, size: 64, color: AppTheme.accent),
            const SizedBox(height: 24),
            const Text(
              'Ready to Activate',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Your proxy has accepted. Activate your free beta coverage below.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.sparkles,
                    color: Colors.amber.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Free Beta Access — No payment required during beta. '
                      'Annual contribution (\$100) will apply after launch.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber.shade800,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _processPayment,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Activate Free Beta Access'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusPage({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: color),
            const SizedBox(height: 24),
            Text(
              title,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadiness(String userId) {
    final eligibilityAsync = ref.watch(_eligibilityProvider(userId));
    final result =
        eligibilityAsync.value ??
        EligibilityResult(
          isProfileComplete: false,
          isProfileVerified: false,
          hasEnoughTrust: false,
          hasEnoughRelatives: false,
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Membership Eligibility',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Complete these steps to join the Bereavement Fund.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),

          _buildChecklistItem(
            'Verified Profile',
            result.isProfileVerified,
            'Complete identity verification.',
          ),

          _buildChecklistItem(
            'Community Trust (>67)',
            result.hasEnoughTrust,
            'Increase your Trust Score.',
          ),
          _buildChecklistItem(
            'Qualified Network',
            result.hasEnoughRelatives,
            'Add at least 2 relatives.',
          ),

          const SizedBox(height: 24),
          _SuggestedProxiesList(userId: userId),
          const SizedBox(height: 8),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: result.isEligible
                  ? () => _showSetupCoverageDialog(result)
                  : null,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: AppTheme.accent,
                disabledBackgroundColor: Colors.grey.withValues(alpha: 0.2),
              ),
              child: const Text('Setup Coverage'),
            ),
          ),
          if (!result.isEligible)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Center(
                child: Text(
                  'Please meet all conditions to proceed.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
        ],
      ),
    );
  }

  Widget _buildChecklistItem(String title, bool isMet, String helpAction) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isMet
            ? Colors.green.withValues(alpha: 0.05)
            : Colors.red.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            isMet ? LucideIcons.checkCircle : LucideIcons.xCircle,
            color: isMet ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 16),
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
                ),
                if (!isMet)
                  Text(
                    helpAction,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(
    BuildContext context,
    BereavementMembership membership,
  ) {
    Color statusColor;
    String statusText;

    switch (membership.status) {
      case MembershipStatus.active:
        statusColor = Colors.green;
        statusText = 'Active';
        break;
      case MembershipStatus.inactive:
        statusColor = Colors.red;
        statusText = 'Inactive';
        break;
      case MembershipStatus.pending_proxy:
      case MembershipStatus.pending_payment:
        statusColor = Colors.orange;
        statusText = 'Pending';
        break;
      case MembershipStatus.grace_period:
        statusColor = Colors.yellow.shade800;
        statusText = 'Grace Period';
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(LucideIcons.shieldCheck, size: 48, color: statusColor),
          const SizedBox(height: 16),
          Text(
            statusText,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: statusColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Coverage Status',
            style: TextStyle(color: statusColor.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildBeneficiaryItem({
    required IconData icon,
    required String name,
    required String relation,
    bool isProxy = false,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: AppTheme.accent),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(
                relation,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        if (isProxy)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'PROXY',
              style: TextStyle(fontSize: 10, color: Colors.blue),
            ),
          ),
      ],
    );
  }
}

final membershipStreamProvider =
    StreamProvider.family<BereavementMembership?, String>((ref, userId) {
      return ref.read(bereavementServiceProvider).streamMembership(userId);
    });

class _ClaimsTab extends ConsumerStatefulWidget {
  const _ClaimsTab();

  @override
  ConsumerState<_ClaimsTab> createState() => _ClaimsTabState();
}

class _ClaimsTabState extends ConsumerState<_ClaimsTab> {
  static List<BereavementClaim> _cachedClaims = [];
  final List<BereavementClaim> _optimisticClaims = [];

  void _showClaimDialog() {
    showDialog<BereavementClaim>(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: const _SubmitClaimDialog(),
      ),
    ).then((optimisticClaim) {
      if (optimisticClaim != null && mounted) {
        setState(() {
          _optimisticClaims.insert(0, optimisticClaim);
        });
      }
    });
  }

  Widget _buildClaimsList(BuildContext context, List<BereavementClaim> live) {
    final liveNames = live.map((c) => c.deceasedName).toSet();
    final pendingOptimistic = _optimisticClaims
        .where((c) => !liveNames.contains(c.deceasedName))
        .toList();
    final claims = [...pendingOptimistic, ...live];

    if (claims.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.clipboardList,
              size: 64,
              color: Colors.grey.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            const Text(
              'No support requests yet',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).padding.bottom + 80,
      ),
      itemCount: claims.length,
      itemBuilder: (context, index) {
        final claim = claims[index];
        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            tileColor: AppTheme.cardDecoration(context).color,
            contentPadding: const EdgeInsets.all(16),
            title: Text(
              claim.deceasedName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'broadcast') {
                  _showBroadcastDialog(context, claim);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'broadcast',
                  child: Row(
                    children: [
                      Icon(LucideIcons.megaphone, size: 18),
                      SizedBox(width: 8),
                      Text('Broadcast Announcement'),
                    ],
                  ),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  'Passed Away \u2022 ${DateFormat('MMM d').format(claim.dateOfDeath)}',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 8),
                _buildStatusProgress(context, claim.status),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authRepositoryProvider).currentUser;
    if (user == null) return const Center(child: Text('Please log in'));

    final membership = ref.watch(membershipStreamProvider(user.uid)).value;
    final bool canRequest =
        membership?.status == MembershipStatus.active ||
        membership?.status == MembershipStatus.grace_period;

    final claimsAsync = ref.watch(claimsStreamProvider(user.uid));
    if (claimsAsync.hasValue) {
      _cachedClaims = claimsAsync.value!;
    }

    return Scaffold(
      floatingActionButton: canRequest
          ? FloatingActionButton.extended(
              onPressed: _showClaimDialog,
              icon: const Icon(LucideIcons.heartHandshake),
              label: const Text('Request Support'),
              backgroundColor: AppTheme.accent,
            )
          : null,
      body: claimsAsync.when(
        data: (claims) => _buildClaimsList(context, claims),
        loading: () => _buildClaimsList(context, _cachedClaims),
        error: (e, st) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildStatusProgress(BuildContext context, ClaimStatus status) {
    int step = 0;
    switch (status) {
      case ClaimStatus.submitted:
        step = 1;
        break;
      case ClaimStatus.under_review:
        step = 2;
        break;
      case ClaimStatus.approved:
        step = 3;
        break;
      case ClaimStatus.paid:
        step = 4;
        break;
      case ClaimStatus.rejected:
        step = 0;
        break;
    }

    if (status == ClaimStatus.rejected) {
      return const Text(
        'Request Rejected - Please contact support',
        style: TextStyle(
          color: Colors.red,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: step / 4,
            backgroundColor: Colors.grey.withValues(alpha: 0.2),
            color: AppTheme.accent,
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _getStatusLabel(status),
          style: const TextStyle(
            fontSize: 11,
            color: AppTheme.accent,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  String _getStatusLabel(ClaimStatus status) {
    switch (status) {
      case ClaimStatus.submitted:
        return 'Processing Request (25%)';
      case ClaimStatus.under_review:
        return 'Under Review (50%)';
      case ClaimStatus.approved:
        return 'Approved - Scheduling Transfer (75%)';
      case ClaimStatus.paid:
        return 'Funds Transferred (100%)';
      default:
        return '';
    }
  }

  void _showBroadcastDialog(BuildContext context, BereavementClaim claim) {
    showDialog(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
          title: const Text('Broadcast Announcement'),
          content: Text(
            'Notify community members about the passing of ${claim.deceasedName}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Announcement broadcasted to community.'),
                  ),
                );
              },
              child: const Text('Broadcast'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestedProxiesList extends ConsumerWidget {
  final String userId;
  const _SuggestedProxiesList({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proxies = ref.watch(_potentialProxiesProvider(userId)).value ?? [];
    if (proxies.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Suggested Proxies (Verified Contacts)",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: proxies.length,
          itemBuilder: (context, index) {
            final p = proxies[index];
            final mockRel = Relationship(
              id: p.uid!,
              name: p.firstName,
              type: 'Verified Contact',
              status: 'active',
              createdAt: DateTime.now(),
            );

            return RelationshipCard(
              relationship: mockRel,
              enableActions: false,
            );
          },
        ),
      ],
    );
  }
}

final claimsStreamProvider =
    StreamProvider.family<List<BereavementClaim>, String>((ref, userId) {
      return ref.read(bereavementServiceProvider).streamUserClaims(userId);
    });

class _SubmitClaimDialog extends ConsumerStatefulWidget {
  const _SubmitClaimDialog();

  @override
  ConsumerState<_SubmitClaimDialog> createState() => _SubmitClaimDialogState();
}

class _SubmitClaimDialogState extends ConsumerState<_SubmitClaimDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _relationController = TextEditingController();
  final _descController = TextEditingController();
  DateTime? _dateOfDeath;

  @override
  void dispose() {
    _nameController.dispose();
    _relationController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _dateOfDeath == null) {
      if (_dateOfDeath == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select date of death')),
        );
      }
      return;
    }

    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null) return;

    final deceasedName = _nameController.text;
    final relationship = _relationController.text;
    final dateOfDeath = _dateOfDeath!;
    final description = _descController.text;

    final optimistic = BereavementClaim(
      id: 'optimistic_${DateTime.now().millisecondsSinceEpoch}',
      userId: user.uid,
      deceasedName: deceasedName,
      relationship: relationship,
      dateOfDeath: dateOfDeath,
      status: ClaimStatus.submitted,
      submittedDate: DateTime.now(),
      description: description,
    );

    final service = ref.read(bereavementServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context, optimistic);
    messenger.showSnackBar(
      const SnackBar(content: Text('Support request submitted successfully')),
    );

    unawaited(
      service
          .submitClaim(
            userId: user.uid,
            deceasedName: deceasedName,
            relationship: relationship,
            dateOfDeath: dateOfDeath,
            description: description,
          )
          .catchError((Object e) {
            messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
          }),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _dateOfDeath = picked);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
      title: const Text('New Support Request'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Deceased Name'),
                validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _relationController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Relationship (e.g. Father/Sister)',
                ),
                validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Date of Death'),
                  child: Text(
                    _dateOfDeath == null
                        ? 'Select Date'
                        : DateFormat('yyyy-MM-dd').format(_dateOfDeath!),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Description / Notes',
                ),
                maxLines: 3,
                validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Submit')),
      ],
    );
  }
}

class _SetupCoverageDialog extends ConsumerStatefulWidget {
  final String userId;
  final List<Relationship> initialRelatives;
  final List<ProfileData> potentialProxies;
  final Function(String proxyId, List<String> coveredIds) onConfirm;

  const _SetupCoverageDialog({
    required this.userId,
    required this.initialRelatives,
    required this.potentialProxies,
    required this.onConfirm,
  });

  @override
  ConsumerState<_SetupCoverageDialog> createState() =>
      _SetupCoverageDialogState();
}

class _SetupCoverageDialogState extends ConsumerState<_SetupCoverageDialog> {
  final _proxyController = TextEditingController();
  final _friendController = TextEditingController();

  bool _isProxyValid = false;

  late List<String> _coveredIds;
  late List<String> _displayNames;

  @override
  void initState() {
    super.initState();
    _coveredIds = widget.initialRelatives.map((r) => r.id).toList();
    _displayNames = widget.initialRelatives.map((r) => r.name).toList();

    _proxyController.addListener(() {
      setState(() {
        _isProxyValid = _proxyController.text.trim().isNotEmpty;
      });
    });
  }

  void _addFriend() {
    final val = _friendController.text.trim();
    if (val.isNotEmpty) {
      setState(() {
        _coveredIds.add('friend_$val');
        _displayNames.add('$val (Friend)');
        _friendController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final proxies =
        ref.watch(_potentialProxiesProvider(widget.userId)).value ??
        widget.potentialProxies;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
      title: const Text('Join Fund'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Supported Family Members',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_displayNames.isNotEmpty)
              ..._displayNames.map(
                (name) => Padding(
                  padding: const EdgeInsets.only(bottom: 4.0),
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.user,
                        size: 16,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Text(name),
                      const Spacer(),
                      const Icon(
                        LucideIcons.check,
                        size: 16,
                        color: Colors.green,
                      ),
                    ],
                  ),
                ),
              )
            else
              const Text(
                'No qualified relatives found.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),

            if (_displayNames.isEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Add a close friend for support:',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _friendController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        hintText: 'Friend Name',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.plusCircle),
                    onPressed: _addFriend,
                  ),
                ],
              ),
            ],

            const Divider(height: 32),

            const Text(
              'Designated Proxy',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Required. A member who will act on your behalf.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _proxyController,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Proxy User ID / Name',
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(LucideIcons.search),
                errorText: _isProxyValid ? null : 'Required *',
              ),
            ),
            if (proxies.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Suggestions (Verified Contacts)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 150,
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: proxies.length,
                  itemBuilder: (context, index) {
                    final p = proxies[index];
                    final mockRel = Relationship(
                      id: p.uid!,
                      name: p.firstName,
                      type: 'Verified Contact',
                      status: 'active',
                      createdAt: DateTime.now(),
                    );

                    return InkWell(
                      onTap: () {
                        setState(() {
                          _proxyController.text = p.uid ?? '';
                        });
                      },
                      child: IgnorePointer(
                        child: RelationshipCard(
                          relationship: mockRel,
                          enableActions: false,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isProxyValid
              ? () {
                  widget.onConfirm(_proxyController.text, _coveredIds);
                  Navigator.pop(context);
                }
              : null,
          child: const Text('Join Fund'),
        ),
      ],
    );
  }
}
