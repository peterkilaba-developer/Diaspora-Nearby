import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/core/data/countries.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../dsp/models/user_points.dart';
import '../models/governance_unit.dart';
import '../models/governance_roles.dart';
import '../repository/governance_repository.dart';
import '../services/governance_service.dart';
import '../../community/models/community_data.dart';
import '../../chat/utils/community_chat_utils.dart';
import '../../community/repository/community_repository.dart';
import '../../profile/repository/profile_repository.dart';
import '../../profile/models/profile_data.dart';
import '../../dsp/repository/points_repository.dart';
import '../../trust/repository/trust_repository.dart';
import '../../trust/models/trust_data.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/dsp/services/exploration_registry.dart';
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart';

class LeaderSelectionScreen extends ConsumerStatefulWidget {
  final String unitId;
  final Community? community;

  const LeaderSelectionScreen({
    super.key,
    required this.unitId,
    this.community,
  });

  @override
  ConsumerState<LeaderSelectionScreen> createState() =>
      _LeaderSelectionScreenState();
}

class _LeaderSelectionScreenState extends ConsumerState<LeaderSelectionScreen> {
  final bool _isSubmitting = false;

  List<UserPoints>? _cachedQualified;
  Future<List<UserPoints>>? _qualifiedFuture;

  final Map<String, List<String>> _optimisticRoleCandidates = {};
  final Map<String, Map<String, VoteSummary>> _optimisticVoteSummaries = {};
  final Map<String, String> _optimisticMyVerdict = {};

  @override
  void initState() {
    super.initState();
    _cachedQualified = ref
        .read(governanceServiceProvider)
        .getCachedQualifiedCandidates(widget.unitId);
    _loadQualifiedCandidates();
    _trackExploration();
  }

  Future<void> _trackExploration() async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user != null) {
      final rewarded = await ref
          .read(pointsServiceProvider)
          .trackExplorationReward(
            user.uid,
            ExplorationAction.governanceLeaderSelection,
          );
      if (rewarded && mounted) {
        showExplorationRewardToast(context);
      }
    }
  }

  void _loadQualifiedCandidates() {
    _qualifiedFuture = ref
        .read(governanceServiceProvider)
        .getQualifiedCandidates(widget.unitId);
  }

  GovernanceUnit _applyOptimisticUnit(GovernanceUnit base) {
    if (_optimisticRoleCandidates.isEmpty) return base;
    final json = base.toJson();
    final rc = Map<String, dynamic>.from(json['roleCandidates'] as Map? ?? {});
    for (final entry in _optimisticRoleCandidates.entries) {
      final current = List<String>.from(rc[entry.key] as List? ?? []);
      for (final uid in entry.value) {
        if (!current.contains(uid)) current.add(uid);
      }
      rc[entry.key] = current;
    }
    json['roleCandidates'] = rc;
    return GovernanceUnit.fromJson(json);
  }

  Map<String, VoteSummary> _mergeOptimisticVotes(
    String role,
    Map<String, VoteSummary> base,
  ) {
    final opt = _optimisticVoteSummaries[role];
    if (opt == null || opt.isEmpty) return base;
    return {...base, ...opt};
  }

  @override
  Widget build(BuildContext context) {
    final govRepo = ref.watch(governanceRepositoryProvider);
    final governanceUnitAsync = govRepo.watchGovernanceUnit(widget.unitId);
    final cachedUnit = govRepo.getCachedGovernanceUnit(widget.unitId);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Voice of the Diaspora'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor:
            Theme.of(context).appBarTheme.foregroundColor ??
            Theme.of(context).colorScheme.onSurface,
        actions: const [],
      ),
      body: StreamBuilder<GovernanceUnit?>(
        initialData: cachedUnit,
        stream: governanceUnitAsync,
        builder: (context, snapshot) {
          final unit = snapshot.data ?? cachedUnit;

          final activeUnit =
              unit ??
              GovernanceUnit(
                id: widget.unitId,
                name: (widget.community?.name ?? widget.unitId)
                    .replaceAll('_', ' ')
                    .toUpperCase()
                    .replaceAll('COUNTRY ', '')
                    .replaceAll('STATE ', ''),
                level: widget.unitId.contains('global')
                    ? GovernanceLevel.global
                    : widget.unitId.contains('continent')
                    ? GovernanceLevel.continent
                    : widget.unitId.contains('country')
                    ? GovernanceLevel.country
                    : widget.unitId.contains('state')
                    ? GovernanceLevel.state
                    : GovernanceLevel.local,
                type: widget.unitId.contains('global')
                    ? GovernanceType.global
                    : widget.unitId.contains('continent')
                    ? GovernanceType.continent
                    : widget.unitId.contains('country')
                    ? GovernanceType.country
                    : widget.unitId.contains('state')
                    ? GovernanceType.state
                    : GovernanceType.local,
                isActiveElection: true, // Continuous voting = always active
              );

          final displayUnit = _applyOptimisticUnit(activeUnit);
          final currentUser = ref.watch(authRepositoryProvider).currentUser;
          final profileRepo = ref.watch(profileRepositoryProvider);
          final cachedProfile = currentUser != null
              ? profileRepo.getCachedProfile(currentUser.uid)
              : null;
          final profileAsync = currentUser != null
              ? profileRepo.watchProfile(currentUser.uid)
              : const Stream<ProfileData?>.empty();

          return StreamBuilder<ProfileData?>(
            initialData: cachedProfile,
            stream: profileAsync,
            builder: (context, profileSnapshot) {
              final profile = profileSnapshot.data ?? cachedProfile;

              return RefreshIndicator(
                onRefresh: () async {
                  _loadQualifiedCandidates();
                  setState(() {});
                  await _qualifiedFuture;
                },
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      key: const ValueKey('governance-header'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 16.0,
                          horizontal: AppTheme.pageHorizontalPadding,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [_buildHeader(displayUnit, profile)],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      key: const ValueKey('governance-content'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.pageHorizontalPadding,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ⑤ TOP — Elected leaders
                            const SizedBox(height: 16),
                            _buildCurrentCouncil(displayUnit),

                            // ④ Election progress — top 3 per role
                            const SizedBox(height: 24),
                            _buildElectionProgress(displayUnit),

                            // ③ Election tally / running candidates
                            const SizedBox(height: 24),
                            _buildRunningCandidatesSection(
                              displayUnit,
                              currentUser?.uid,
                            ),

                            // ② Qualified candidates pool
                            const SizedBox(height: 24),
                            _buildQualifiedCandidatesPool(
                              displayUnit,
                              currentUser?.uid,
                            ),

                            // ① Election rules
                            const SizedBox(height: 24),
                            _buildElectionValiditySection(displayUnit, profile),

                            // ① Candidate eligibility (auto-qualified)
                            const SizedBox(height: 24),
                            _buildCandidateEligibilitySection(
                              displayUnit,
                              profile,
                            ),

                            SizedBox(
                              height:
                                  MediaQuery.of(context).padding.bottom + 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ──────────────────────────────────
  // HEADER
  // ──────────────────────────────────

  Widget _buildHeader(GovernanceUnit unit, ProfileData? profile) {
    final communityId = unit.communityId;

    if (widget.community != null) {
      return _buildHeaderContent(unit, profile, community: widget.community!);
    }

    if (communityId != null) {
      return Consumer(
        builder: (context, ref, _) {
          final communityAsync = ref.watch(communityProvider(communityId));
          return communityAsync.when(
            data: (community) {
              if (community == null) return _buildHeaderContent(unit, profile);
              return _buildHeaderContent(unit, profile, community: community);
            },
            loading: () => _buildHeaderContent(unit, profile, isLoading: true),
            error: (_, _) => _buildHeaderContent(unit, profile),
          );
        },
      );
    }
    return _buildHeaderContent(unit, profile);
  }

  Widget _buildHeaderContent(
    GovernanceUnit unit,
    ProfileData? profile, {
    Community? community,
    bool isLoading = false,
  }) {
    final String communityName = community != null
        ? CommunityChatUtils.generateCommunityNameFromParts(
            name: community.name,
            locationType: community.locationType ?? 'home',
            id: community.id,
          )
        : unit.name;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.cardHorizontalPadding,
        vertical: 24,
      ),
      decoration: AppTheme.cardDecoration(context).copyWith(
        borderRadius: BorderRadius.circular(AppTheme.standardBorderRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (community != null)
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: CommunityChatUtils.getCommunityAvatar(
                    context: context,
                    communityId: community.id,
                    profileImage: community.profileImage,
                    type: community.type,
                    locationType: community.locationType,
                    homeCountryCode: community.homeCountryCode,
                    flag: community.flag,
                    size: 32,
                  ),
                )
              else if (isLoading)
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.1),
                )
              else
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    LucideIcons.landmark,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                    size: 16,
                  ),
                ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isLoading ? 'Loading...' : communityName,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Council of Community Leaders',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Your community is self-governing through continuous voting. '
            'Qualified members can run for leadership roles. '
            'Candidacy earned at the local level automatically cascades '
            'to all higher communities (state, country, continent, global).',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  /// ⓪ Candidate Eligibility — wrapped in _buildSectionCard at the bottom.
  Widget _buildCandidateEligibilitySection(
    GovernanceUnit unit,
    ProfileData? profile,
  ) {
    final isLocal = unit.level == GovernanceLevel.local;
    if (!isLocal) return const SizedBox.shrink();

    return _buildSectionCard(
      stepNumber: 0,
      stepLabel: 'ELIGIBILITY',
      header: _buildSectionHeader(
        title: 'Candidate Eligibility',
        icon: LucideIcons.badgeCheck,
      ),
      description:
          'Members who meet all criteria are automatically added to the Qualified Pool.',
      child: _buildEligibilityRulesContent(unit, profile),
    );
  }

  /// Returns just the eligibility criteria list (used inside section card).
  Widget _buildEligibilityRulesContent(
    GovernanceUnit unit,
    ProfileData? profile,
  ) {
    return Consumer(
      builder: (context, ref, _) {
        final cachedTrust = profile?.uid != null
            ? ref.read(trustRepositoryProvider).getCachedTrustData(profile!.uid!)
            : null;
        final trustDataAsync = profile != null
            ? ref.watch(trustDataProvider(profile.uid!))
            : const AsyncValue<TrustData?>.data(null);

        final resolvedTrust = trustDataAsync.value ?? cachedTrust;
        if (resolvedTrust != null || !trustDataAsync.isLoading) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildEligibilityCriterion(
                '7 Genesis Milestones Completed',
                isMet:
                    (resolvedTrust?.awardedQualificationMilestones.length ?? 0) >=
                    7,
              ),
              _buildEligibilityCriterion(
                '100+ Days on App',
                isMet:
                    profile?.createdAt != null &&
                    DateTime.now().difference(profile!.createdAt!).inDays >=
                        100,
              ),
              _buildEligibilityCriterion(
                'Admin of 100+ Member Group Chat',
                isMet: resolvedTrust?.isCouncilEligible ?? false,
              ),
              _buildEligibilityCriterion(
                'PCT Score ≥ 91',
                isMet: (resolvedTrust?.trustScore ?? 0) >= 91,
              ),
            ],
          );
        }

        return const Center(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
    );
  }

  Widget _buildEligibilityCriterion(String text, {bool isMet = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isMet ? LucideIcons.checkCircle : LucideIcons.circle,
            size: 11,
            color: isMet
                ? Colors.greenAccent
                : Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                color: isMet
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.5),
                fontWeight: isMet ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────
  // ⑤ ELECTED LEADERS (TOP)
  // ──────────────────────────────────

  Widget _buildCurrentCouncil(GovernanceUnit unit) {
    final memberIds = unit.councilMembers;

    return _buildSectionCard(
      key: const ValueKey('governance-council'),
      stepNumber: 5,
      stepLabel: 'ELECTED',
      header: _buildSectionHeader(
        title: 'Elected Leaders',
        icon: LucideIcons.crown,
      ),
      description:
          'Community members who have been elected to leadership roles by popular vote.',
      child: memberIds.isEmpty
          ? _buildSectionEmptyState(
              icon: LucideIcons.crown,
              title: 'No Leaders Elected',
              message:
                  'This community has not yet elected its council representatives.',
            )
          : Column(
              children: memberIds.map((id) {
                final role = unit.councilRoles[id];
                final roleName = role != null
                    ? GovernanceRoles.displayName(role)
                    : 'Council Member';
                return _LeaderTile(
                  userId: id,
                  showCheckmark: true,
                  variant: LeaderTileVariant.council,
                  subtitle: roleName,
                );
              }).toList(),
            ),
    );
  }

  // ──────────────────────────────────────────
  // ④ ELECTION PROGRESS (Top 3 per role)
  // ──────────────────────────────────────────

  Widget _buildElectionProgress(GovernanceUnit unit) {
    final hasAnyCandidates = GovernanceRoles.all.any(
      (role) => (unit.roleCandidates[role] ?? []).isNotEmpty,
    );

    Widget content;
    if (!hasAnyCandidates) {
      content = _buildSectionEmptyState(
        icon: LucideIcons.barChart3,
        title: 'No Election Data',
        message:
            'Once candidates declare their candidacy, the top contenders for each role will appear here.',
      );
    } else {
      content = Column(
        children: GovernanceRoles.all.map((role) {
          final candidateIds = unit.roleCandidates[role] ?? [];
          if (candidateIds.isEmpty) return const SizedBox.shrink();

          final roleName = GovernanceRoles.displayName(role);
          final roleIcon = GovernanceRoles.icon(role);
          final govService = ref.watch(governanceServiceProvider);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    roleIcon,
                    size: 14,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    roleName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.primary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              StreamBuilder<Map<String, VoteSummary>>(
                initialData: govService.getCachedRoleCandidateVotes(
                  widget.unitId,
                  role,
                ),
                stream: govService.watchRoleCandidateVotes(widget.unitId, role),
                builder: (context, voteSnapshot) {
                  final voteSummaries = _mergeOptimisticVotes(
                    role,
                    voteSnapshot.data ?? {},
                  );

                  // Build sorted list of candidates by favorable rate
                  final ranked =
                      candidateIds.map((id) {
                        return voteSummaries[id] ??
                            VoteSummary(candidateId: id, role: role);
                      }).toList()..sort((a, b) {
                        // Sort by favorable rate desc, then total votes desc
                        final cmp = b.favorableRate.compareTo(a.favorableRate);
                        if (cmp != 0) return cmp;
                        return b.totalVotes.compareTo(a.totalVotes);
                      });

                  // Take top 3
                  final top3 = ranked.take(3).toList();

                  return Column(
                    children: List.generate(top3.length, (index) {
                      final summary = top3[index];
                      return _ElectionProgressRow(
                        rank: index + 1,
                        candidateId: summary.candidateId,
                        voteSummary: summary,
                      );
                    }),
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
          );
        }).toList(),
      );
    }

    return _buildSectionCard(
      stepNumber: 4,
      stepLabel: 'PROGRESS',
      header: _buildSectionHeader(
        title: 'Election Progress',
        icon: LucideIcons.barChart3,
      ),
      description: 'Live leaderboard showing top 3 candidates for each role.',
      child: content,
    );
  }

  // ──────────────────────────────────────────
  // ② QUALIFIED CANDIDATES POOL (Auto-populated)
  // ──────────────────────────────────────────

  Widget _buildQualifiedCandidatesPool(
    GovernanceUnit unit,
    String? currentUserId,
  ) {
    return _buildSectionCard(
      stepNumber: 2,
      stepLabel: 'QUALIFY',
      header: _buildSectionHeader(
        title: 'Qualified Candidates',
        icon: LucideIcons.star,
      ),
      description:
          'Members who meet all eligibility criteria are automatically added here. '
          'Tap your card to select a role and announce your candidacy.',
      child: FutureBuilder<List<UserPoints>>(
        future: _qualifiedFuture,
        initialData: _cachedQualified,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              snapshot.data == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: CircularProgressIndicator(),
              ),
            );
          }
          final qualified = snapshot.data ?? [];
          _cachedQualified = qualified;

          if (qualified.isEmpty) {
            return _buildSectionEmptyState(
              icon: LucideIcons.star,
              title: 'No Qualified Candidates',
              message:
                  'No members currently meet all eligibility criteria. '
                  'Members must complete all 7 Genesis Milestones, be on the app for 100+ days, be an admin of a '
                  'group chat with 100+ members, and have a PCT score of 91+.',
            );
          }

          return Column(
            children: qualified.map((candidate) {
              final isMe = candidate.userId == currentUserId;
              return _QualifiedCandidateTile(
                userId: candidate.userId,
                userPoints: candidate,
                isCurrentUser: isMe,
                onRunForRole: isMe
                    ? () => _showRoleSelectionModal(unit, candidate.userId)
                    : null,
              );
            }).toList(),
          );
        },
      ),
    );
  }

  // ──────────────────────────────────
  // ROLE SELECTION MODAL
  // ──────────────────────────────────

  void _showRoleSelectionModal(GovernanceUnit unit, String userId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.elevationColor(context, 3),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
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
                const SizedBox(height: 20),
                Text(
                  'SELECT YOUR ROLE',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Theme.of(context).colorScheme.onSurface,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose the leadership position you want to run for. '
                  'Your candidacy will be announced to the community.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 24),
                ...GovernanceRoles.all.map((role) {
                  final isAlreadyRunning =
                      unit.roleCandidates[role]?.contains(userId) ?? false;
                  return _RoleSelectionTile(
                    role: role,
                    isAlreadyRunning: isAlreadyRunning,
                    onTap: isAlreadyRunning
                        ? null
                        : () => _confirmRoleSelection(unit, userId, role),
                  );
                }),
                SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmRoleSelection(
    GovernanceUnit unit,
    String userId,
    String role,
  ) async {
    Navigator.of(context).pop(); // Close modal

    final roleName = GovernanceRoles.displayName(role);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
          backgroundColor: AppTheme.elevationColor(context, 3),
          title: Text('Run for $roleName?'),
          content: Text(
            'You are about to announce your candidacy for $roleName. '
            'This will:\n\n'
            '• Move you to the $roleName candidate pool\n'
            '• Cast your self-vote (Yay) automatically\n'
            '• Notify all community members via chat\n\n'
            'Are you ready to run?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text('Run for $roleName'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    final previousQualified = _cachedQualified != null
        ? List<UserPoints>.from(_cachedQualified!)
        : null;
    final previousRoleCandidates = List<String>.from(
      _optimisticRoleCandidates[role] ?? const [],
    );

    setState(() {
      _optimisticRoleCandidates[role] = [...previousRoleCandidates, userId];
      final roleMap = Map<String, VoteSummary>.from(
        _optimisticVoteSummaries[role] ?? const {},
      );
      final existingSummary = roleMap[userId];
      roleMap[userId] = VoteSummary(
        candidateId: userId,
        role: role,
        yayCount: (existingSummary?.yayCount ?? 0) + 1,
        nayCount: existingSummary?.nayCount ?? 0,
        abstainCount: existingSummary?.abstainCount ?? 0,
      );
      _optimisticVoteSummaries[role] = roleMap;
      if (_cachedQualified != null) {
        _cachedQualified = _cachedQualified!
            .where((c) => c.userId != userId)
            .toList();
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Your candidacy for $roleName has been announced!'),
          backgroundColor: AppTheme.accent,
        ),
      );
    }

    unawaited(
      ref
          .read(governanceServiceProvider)
          .selectRoleAndSelfVote(unit.id, userId, role)
          .then((_) {
            if (mounted) {
              _loadQualifiedCandidates();
              setState(() {});
            }
          })
          .catchError((Object e) {
            if (mounted) {
              setState(() {
                _optimisticRoleCandidates[role] = previousRoleCandidates;
                _optimisticVoteSummaries[role]?.remove(userId);
                if (previousQualified != null) {
                  _cachedQualified = previousQualified;
                }
              });
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Error: $e')));
            }
          }),
    );
  }

  // ──────────────────────────────────────────────
  // ROLE-SPECIFIC CANDIDATE SECTIONS (Per Role)
  // ──────────────────────────────────────────────

  /// ③ Consolidated section: shows all running candidates grouped by role,
  /// or a single empty card if no one is running for any role.
  Widget _buildRunningCandidatesSection(
    GovernanceUnit unit,
    String? currentUserId,
  ) {
    // Check if any role has candidates
    final hasAnyCandidates = GovernanceRoles.all.any(
      (role) => (unit.roleCandidates[role] ?? []).isNotEmpty,
    );

    Widget content;
    if (!hasAnyCandidates) {
      content = _buildSectionEmptyState(
        icon: LucideIcons.vote,
        title: 'No Running Candidates',
        message:
            'No community members have declared candidacy for any role yet. '
            'Qualified members can select a role from the pool below to run.',
      );
    } else {
      content = Column(
        children: GovernanceRoles.all.map((role) {
          final candidateIds = unit.roleCandidates[role] ?? [];
          if (candidateIds.isEmpty) return const SizedBox.shrink();

          final roleName = GovernanceRoles.displayName(role);
          final roleIcon = GovernanceRoles.icon(role);
          final govService = ref.watch(governanceServiceProvider);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    roleIcon,
                    size: 14,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    roleName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.primary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Stream live vote data for this role
              StreamBuilder<Map<String, VoteSummary>>(
                initialData: govService.getCachedRoleCandidateVotes(
                  widget.unitId,
                  role,
                ),
                stream: govService.watchRoleCandidateVotes(widget.unitId, role),
                builder: (context, voteSnapshot) {
                  final rawSummaries = voteSnapshot.data ?? {};
                  final voteSummaries = _mergeOptimisticVotes(
                    role,
                    rawSummaries,
                  );

                  return Column(
                    children: candidateIds.map((candidateId) {
                      final summary = voteSummaries[candidateId];
                      return _RoleCandidateVoteCard(
                        unitId: widget.unitId,
                        candidateId: candidateId,
                        role: role,
                        voteSummary: summary,
                        currentUserId: currentUserId,
                        isSubmitting: _isSubmitting,
                        onVote: (verdict) => _castVote(
                          unit,
                          candidateId,
                          role,
                          verdict,
                          currentUserId!,
                          summary,
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          );
        }).toList(),
      );
    }

    return _buildSectionCard(
      stepNumber: 3,
      stepLabel: 'VOTE',
      header: _buildSectionHeader(
        title: 'Election Tally',
        icon: LucideIcons.vote,
      ),
      description:
          'Candidates who declared their candidacy. Cast your vote: Yay, Abstain, or Nay.',
      child: content,
    );
  }

  /// ① Election validity requirements — rendered as its own section at page bottom.
  Widget _buildElectionValiditySection(
    GovernanceUnit unit,
    ProfileData? profile,
  ) {
    final isLocal = unit.level == GovernanceLevel.local;
    return _buildSectionCard(
      stepNumber: 1,
      stepLabel: 'RULES',
      header: _buildSectionHeader(
        title: 'Election Rules',
        icon: LucideIcons.shieldCheck,
      ),
      description: 'For the election results to be valid:',
      child: Column(
        children: [
          _buildEligibilityCriterion(
            '50% Community Quorum required for valid election',
          ),
          _buildEligibilityCriterion(
            'Minimum 4 community members to enable voting',
          ),
          _buildEligibilityCriterion('>50% Yay votes required for winner'),
          _buildEligibilityCriterion(
            'Leaders below 50% favorable are automatically voted out',
          ),
          _buildEligibilityCriterion('Continuous voting — no election windows'),
          _buildEligibilityCriterion(
            isLocal
                ? 'Candidates are qualified, trusted community members'
                : 'Candidates are elected Leaders from sub-communities',
          ),
        ],
      ),
    );
  }

  Future<void> _castVote(
    GovernanceUnit unit,
    String candidateId,
    String role,
    String verdict,
    String voterId,
    VoteSummary? currentSummary,
  ) async {
    final voteKey = '${role}_$candidateId';
    final previousVerdict = _optimisticMyVerdict[voteKey];
    final previousSummary = currentSummary;

    var yay = currentSummary?.yayCount ?? 0;
    var nay = currentSummary?.nayCount ?? 0;
    var abstain = currentSummary?.abstainCount ?? 0;

    if (previousVerdict == VoteVerdict.yay && yay > 0) yay--;
    if (previousVerdict == VoteVerdict.nay && nay > 0) nay--;
    if (previousVerdict == VoteVerdict.abstain && abstain > 0) abstain--;

    if (verdict == VoteVerdict.yay) yay++;
    if (verdict == VoteVerdict.nay) nay++;
    if (verdict == VoteVerdict.abstain) abstain++;

    setState(() {
      _optimisticMyVerdict[voteKey] = verdict;
      final roleMap = Map<String, VoteSummary>.from(
        _optimisticVoteSummaries[role] ?? const {},
      );
      roleMap[candidateId] = VoteSummary(
        candidateId: candidateId,
        role: role,
        yayCount: yay,
        nayCount: nay,
        abstainCount: abstain,
      );
      _optimisticVoteSummaries[role] = roleMap;
    });

    final verdictLabel = verdict == VoteVerdict.yay
        ? 'Yay'
        : verdict == VoteVerdict.nay
        ? 'Nay'
        : 'Abstain';
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Vote recorded: $verdictLabel'),
          backgroundColor: AppTheme.accent,
        ),
      );
    }

    unawaited(
      ref
          .read(governanceServiceProvider)
          .castRoleVote(
            unitId: unit.id,
            voterId: voterId,
            candidateId: candidateId,
            role: role,
            verdict: verdict,
          )
          .catchError((Object e) {
            if (mounted) {
              setState(() {
                if (previousVerdict != null) {
                  _optimisticMyVerdict[voteKey] = previousVerdict;
                } else {
                  _optimisticMyVerdict.remove(voteKey);
                }
                final roleMap = Map<String, VoteSummary>.from(
                  _optimisticVoteSummaries[role] ?? const {},
                );
                if (previousSummary != null) {
                  roleMap[candidateId] = previousSummary;
                } else {
                  roleMap.remove(candidateId);
                }
                _optimisticVoteSummaries[role] = roleMap;
              });
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Error casting vote: $e')));
            }
          }),
    );
  }

  // ──────────────────────────────────
  // SHARED WIDGETS
  // ──────────────────────────────────

  /// Standardized section card wrapper used by all 4 sections.
  Widget _buildSectionCard({
    Key? key,
    required int stepNumber,
    required String stepLabel,
    required Widget header,
    required String description,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Container(
      key: key,
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: AppTheme.cardDecoration(context).color,
        borderRadius: BorderRadius.circular(AppTheme.standardBorderRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Step badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'STEP $stepNumber · $stepLabel',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.primary,
                letterSpacing: 1.0,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: header,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Child content with 4px horizontal padding from section edge
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required IconData icon,
    String? subtitle,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: theme.colorScheme.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              letterSpacing: 1.2,
            ),
          ),
        ],
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildSectionEmptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: AppTheme.cardDecoration(context).color,
        borderRadius: BorderRadius.circular(AppTheme.standardBorderRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 32, color: Colors.grey.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════
// HELPER WIDGETS
// ════════════════════════════════════════════

enum LeaderTileVariant { council, candidate, signer, defaultVariant }

/// Tile for displaying a leader / council member.
class _LeaderTile extends ConsumerWidget {
  final String userId;
  final bool showCheckmark;
  final LeaderTileVariant variant;
  final String? subtitle;

  const _LeaderTile({
    required this.userId,
    this.showCheckmark = false,
    this.variant = LeaderTileVariant.defaultVariant,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cachedProfile = ref
        .read(profileRepositoryProvider)
        .getCachedProfile(userId);
    final cachedPoints = ref
        .read(pointsRepositoryProvider)
        .getCachedUserPoints(userId);
    final profileAsync = ref.watch(userProfileByIdProvider(userId));
    final pointsAsync = ref.watch(userPointsProvider(userId));

    final isSigner = variant == LeaderTileVariant.signer;
    final isCandidate = variant == LeaderTileVariant.candidate;
    final isCouncil = variant == LeaderTileVariant.council;

    final profile = profileAsync.value ?? cachedProfile;
    if (profile == null) return const SizedBox.shrink();

    final up = pointsAsync.value ?? cachedPoints;
    final theme = Theme.of(context);
    final flag = profile.homeCountryCode != null
        ? getCountryByCode(profile.homeCountryCode!)?.flag ?? '🗺️'
        : '🗺️';
    final fullName = '${profile.firstName} ${profile.lastName}';

    return _buildTileContainer(
      context,
      isSelected: false,
      background: isSigner ? AppTheme.warning.withValues(alpha: 0.05) : null,
      borderColor: isSigner ? Colors.amber.shade200 : null,
      onTap: null,
      child: Row(
        children: [
          _buildAvatar(context, profile, isSigner: isSigner),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(flag, style: TextStyle(fontSize: isSigner ? 14 : 16)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        fullName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: isSigner ? 14 : 15,
                          color: isSigner
                              ? AppTheme.warning
                              : theme.colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
                if (isCandidate || isSigner || isCouncil) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        isSigner ? LucideIcons.key : LucideIcons.shieldCheck,
                        size: 13,
                        color: isSigner
                            ? AppTheme.warning
                            : theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isSigner
                            ? 'Treasury Key Holder'
                            : '${up?.trustScore ?? 0} PCT',
                        style: TextStyle(
                          fontSize: 12,
                          color: isSigner
                              ? AppTheme.warning.withValues(alpha: 0.8)
                              : theme.colorScheme.onSurface.withValues(
                                  alpha: 0.6,
                                ),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (showCheckmark)
            Icon(
              LucideIcons.checkCircle2,
              size: 20,
              color: variant == LeaderTileVariant.council
                  ? Colors.green
                  : AppTheme.accentDark,
            ),
        ],
      ),
    );
  }

  Widget _buildAvatar(
    BuildContext context,
    ProfileData profile, {
    bool isSigner = false,
  }) {
    if (profile.profileImage.isNotEmpty) {
      return CircleAvatar(
        radius: isSigner ? 20 : 24,
        backgroundImage: CachedNetworkImageProvider(profile.profileImage),
      );
    }
    return CircleAvatar(
      radius: isSigner ? 20 : 24,
      backgroundColor: AppTheme.accent.withValues(alpha: 0.1),
      child: Text(
        profile.firstName[0],
        style: TextStyle(
          color: AppTheme.accent,
          fontWeight: FontWeight.bold,
          fontSize: isSigner ? 14 : 16,
        ),
      ),
    );
  }

  Widget _buildTileContainer(
    BuildContext context, {
    required Widget child,
    required bool isSelected,
    VoidCallback? onTap,
    Color? background,
    Color? borderColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color:
              background ??
              (isSelected
                  ? AppTheme.accent.withValues(alpha: 0.05)
                  : AppTheme.cardDecoration(context).color),
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: (borderColor ?? AppTheme.accent).withValues(
                      alpha: 0.1,
                    ),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: child,
      ),
    );
  }
}

/// Tile for qualified candidates pool — shows "Run for Role" button for self.
class _QualifiedCandidateTile extends ConsumerWidget {
  final String userId;
  final UserPoints? userPoints;
  final bool isCurrentUser;
  final VoidCallback? onRunForRole;

  const _QualifiedCandidateTile({
    required this.userId,
    this.userPoints,
    this.isCurrentUser = false,
    this.onRunForRole,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cachedProfile = ref
        .read(profileRepositoryProvider)
        .getCachedProfile(userId);
    final cachedPoints =
        userPoints ??
        ref.read(pointsRepositoryProvider).getCachedUserPoints(userId);
    final profileAsync = ref.watch(userProfileByIdProvider(userId));
    final pointsAsync = userPoints != null
        ? AsyncValue.data(userPoints)
        : ref.watch(userPointsProvider(userId));

    final profile = profileAsync.value ?? cachedProfile;
    if (profile == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final up = pointsAsync.value ?? cachedPoints;
    final flag = profile.homeCountryCode != null
        ? getCountryByCode(profile.homeCountryCode!)?.flag ?? '🗺️'
        : '🗺️';
    final fullName = '${profile.firstName} ${profile.lastName}';

    return GestureDetector(
      onTap: isCurrentUser ? onRunForRole : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isCurrentUser
              ? AppTheme.accent.withValues(alpha: 0.08)
              : AppTheme.cardDecoration(context).color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // Avatar
            profile.profileImage.isNotEmpty
                ? CircleAvatar(
                    radius: 24,
                    backgroundImage: CachedNetworkImageProvider(
                      profile.profileImage,
                    ),
                  )
                : CircleAvatar(
                    radius: 24,
                    backgroundColor: AppTheme.accent.withValues(alpha: 0.1),
                    child: Text(
                      profile.firstName[0],
                      style: const TextStyle(
                        color: AppTheme.accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
            const SizedBox(width: 16),

            // Name & stats
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(flag, style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          fullName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: theme.colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isCurrentUser)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'YOU',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.accent,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        LucideIcons.shieldCheck,
                        size: 13,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${up?.trustScore ?? 0} PCT · Qualified',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Action
            if (isCurrentUser)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.accent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.flag, size: 14, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'Run',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              )
            else
              Icon(
                LucideIcons.checkCircle2,
                size: 20,
                color: Colors.green.withValues(alpha: 0.7),
              ),
          ],
        ),
      ),
    );
  }
}

/// Role selection tile in the bottom sheet modal.
class _RoleSelectionTile extends StatelessWidget {
  final String role;
  final bool isAlreadyRunning;
  final VoidCallback? onTap;

  const _RoleSelectionTile({
    required this.role,
    this.isAlreadyRunning = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roleName = GovernanceRoles.displayName(role);
    final roleIcon = GovernanceRoles.icon(role);
    final roleDesc = GovernanceRoles.description(role);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isAlreadyRunning
              ? Colors.grey.withValues(alpha: 0.1)
              : AppTheme.elevationColor(context, 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              roleIcon,
              size: 28,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    roleName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: isAlreadyRunning
                          ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isAlreadyRunning
                        ? 'Already running for this role'
                        : roleDesc,
                    style: TextStyle(
                      fontSize: 12,
                      color: isAlreadyRunning
                          ? theme.colorScheme.onSurface.withValues(alpha: 0.3)
                          : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            if (isAlreadyRunning)
              Icon(
                LucideIcons.checkCircle2,
                size: 20,
                color: Colors.green.withValues(alpha: 0.5),
              )
            else
              Icon(
                LucideIcons.chevronRight,
                size: 20,
                color: theme.colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }
}

/// Vote card for a candidate running for a specific role.
/// Displays Yay / Nay / Hold buttons and live vote counts.
class _RoleCandidateVoteCard extends ConsumerWidget {
  final String unitId;
  final String candidateId;
  final String role;
  final VoteSummary? voteSummary;
  final String? currentUserId;
  final bool isSubmitting;
  final void Function(String verdict) onVote;

  const _RoleCandidateVoteCard({
    required this.unitId,
    required this.candidateId,
    required this.role,
    this.voteSummary,
    this.currentUserId,
    this.isSubmitting = false,
    required this.onVote,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cachedProfile = ref
        .read(profileRepositoryProvider)
        .getCachedProfile(candidateId);
    final profileAsync = ref.watch(userProfileByIdProvider(candidateId));
    final theme = Theme.of(context);

    final yay = voteSummary?.yayCount ?? 0;
    final nay = voteSummary?.nayCount ?? 0;
    final abstain = voteSummary?.abstainCount ?? 0;
    final total = yay + nay + abstain;
    final favorableRate = voteSummary?.favorableRate ?? 0.0;
    final isWinning = voteSummary?.isWinning ?? false;

    final profile = profileAsync.value ?? cachedProfile;
    if (profile == null) return const SizedBox.shrink();

    final flag = profile.homeCountryCode != null
        ? getCountryByCode(profile.homeCountryCode!)?.flag ?? '🗺️'
        : '🗺️';
    final fullName = '${profile.firstName} ${profile.lastName}';
    final isSelf = candidateId == currentUserId;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppTheme.standardBorderRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Candidate info row
          Row(
            children: [
              profile.profileImage.isNotEmpty
                  ? CircleAvatar(
                      radius: 22,
                      backgroundImage: CachedNetworkImageProvider(
                        profile.profileImage,
                      ),
                    )
                  : CircleAvatar(
                      radius: 22,
                      backgroundColor: AppTheme.accent.withValues(alpha: 0.1),
                      child: Text(
                        profile.firstName[0],
                        style: const TextStyle(
                          color: AppTheme.accent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(flag, style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            fullName,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: theme.colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isSelf)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'YOU',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.accent,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (total > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${(favorableRate * 100).toStringAsFixed(0)}% favorable · $total votes',
                        style: TextStyle(
                          fontSize: 12,
                          color: isWinning
                              ? Colors.green
                              : theme.colorScheme.onSurface.withValues(
                                  alpha: 0.5,
                                ),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          // Vote progress bar (full width, reduced height)
          if (total > 0) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Row(
                children: [
                  if (yay > 0)
                    Expanded(
                      flex: yay,
                      child: Container(height: 0.5, color: Colors.green),
                    ),
                  if (nay > 0)
                    Expanded(
                      flex: nay,
                      child: Container(height: 0.5, color: Colors.redAccent),
                    ),
                  if (abstain > 0)
                    Expanded(
                      flex: abstain,
                      child: Container(height: 0.5, color: Colors.amber),
                    ),
                ],
              ),
            ),
          ],

          // Vote action buttons — Yay left, Abstain center, Nay right
          if (currentUserId != null && !isSelf) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                _VoteButton(
                  label: 'Yay',
                  icon: LucideIcons.thumbsUp,
                  count: yay,
                  color: Colors.green,
                  isSubmitting: isSubmitting,
                  onTap: () => onVote(VoteVerdict.yay),
                ),
                const SizedBox(width: 8),
                _VoteButton(
                  label: 'Abstain',
                  icon: LucideIcons.minus,
                  count: abstain,
                  color: Colors.amber,
                  isSubmitting: isSubmitting,
                  onTap: () => onVote(VoteVerdict.abstain),
                ),
                const SizedBox(width: 8),
                _VoteButton(
                  label: 'Nay',
                  icon: LucideIcons.thumbsDown,
                  count: nay,
                  color: Colors.redAccent,
                  isSubmitting: isSubmitting,
                  onTap: () => onVote(VoteVerdict.nay),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Compact leaderboard row for a candidate in the Election Progress section.
class _ElectionProgressRow extends ConsumerWidget {
  final int rank;
  final String candidateId;
  final VoteSummary voteSummary;

  const _ElectionProgressRow({
    required this.rank,
    required this.candidateId,
    required this.voteSummary,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cachedProfile = ref
        .read(profileRepositoryProvider)
        .getCachedProfile(candidateId);
    final profileAsync = ref.watch(userProfileByIdProvider(candidateId));
    final theme = Theme.of(context);

    // Rank labels
    final rankLabel = '#$rank';
    final rankColor = switch (rank) {
      1 => Colors.amber,
      2 => Colors.grey.shade400,
      3 => Colors.brown.shade300,
      _ => theme.colorScheme.onSurface.withValues(alpha: 0.5),
    };

    final profile = profileAsync.value ?? cachedProfile;
    if (profile == null) {
      if (profileAsync.isLoading) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary.withValues(alpha: 0.3),
              ),
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    final flag = profile.homeCountryCode != null
        ? getCountryByCode(profile.homeCountryCode!)?.flag ?? '🗺️'
        : '🗺️';
    final fullName = '${profile.firstName} ${profile.lastName}';
    final pct = (voteSummary.favorableRate * 100).toStringAsFixed(0);
    final isWinning = voteSummary.isWinning;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Rank
          Text(
            rankLabel,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: rankColor,
            ),
          ),
          const SizedBox(width: 10),

          // Avatar
          CircleAvatar(
            radius: 16,
            backgroundImage: profile.profileImage.isNotEmpty
                ? NetworkImage(profile.profileImage)
                : null,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
            child: profile.profileImage.isEmpty
                ? Text(
                    profile.firstName.substring(0, 1).toUpperCase(),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),

          // Name + vote bar
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$flag $fullName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                // Favorable rate bar (full width, reduced height)
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: voteSummary.favorableRate,
                    minHeight: 0.5,
                    backgroundColor: theme.colorScheme.onSurface.withValues(
                      alpha: 0.08,
                    ),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isWinning ? AppTheme.accent : AppTheme.warning,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // Rate + vote count
          Text(
            '$pct% · ${voteSummary.totalVotes}v',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: isWinning ? AppTheme.accent : AppTheme.warning,
            ),
          ),
        ],
      ),
    );
  }
}

/// Individual vote action button (Yay / Abstain / Nay) with Lucide icon + count.
class _VoteButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final int count;
  final Color color;
  final bool isSubmitting;
  final VoidCallback onTap;

  const _VoteButton({
    required this.label,
    required this.icon,
    this.count = 0,
    required this.color,
    required this.isSubmitting,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buttonBg = theme.colorScheme.surfaceContainerHighest.withValues(
      alpha: 0.5,
    );
    return Expanded(
      child: GestureDetector(
        onTap: isSubmitting ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSubmitting ? buttonBg.withValues(alpha: 0.3) : buttonBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: isSubmitting
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 14, color: color),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      if (count > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            count.toString(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: color,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
