import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:intl/intl.dart';
import 'package:diaspora_nearby/core/data/countries.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../dsp/models/user_points.dart';
import '../models/governance_unit.dart';
import '../repository/governance_repository.dart';
import '../services/governance_service.dart';
import '../../community/models/community_data.dart';
import '../../chat/utils/community_chat_utils.dart';
import '../../community/repository/community_repository.dart';
import '../../profile/repository/profile_repository.dart';
import '../../profile/models/profile_data.dart';
import '../../dsp/repository/points_repository.dart';

class LeaderSelectionScreen extends ConsumerStatefulWidget {
  final String unitId;
  final Community? community;

  const LeaderSelectionScreen({
    super.key, 
    required this.unitId,
    this.community,
  });

  @override
  ConsumerState<LeaderSelectionScreen> createState() => _LeaderSelectionScreenState();
}

class _LeaderSelectionScreenState extends ConsumerState<LeaderSelectionScreen> {
  String? _selectedCandidateId;
  String? _selectedSignerId;
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final governanceUnitAsync = ref.watch(governanceRepositoryProvider).watchGovernanceUnit(widget.unitId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice of the Diaspora'),
        backgroundColor: AppTheme.accentDark,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<GovernanceUnit?>(
        stream: governanceUnitAsync,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final unit = snapshot.data;
          if (unit == null || !unit.isActiveElection) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.vote, size: 48, color: AppTheme.accent),
                   ),
                   const SizedBox(height: 16),
                   Text(
                    'Governance Not Initiated (${unit?.level.name ?? "Unknown"})', 
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                   ),
                   const SizedBox(height: 8),
                   const Padding(
                     padding: EdgeInsets.symmetric(horizontal: 32),
                     child: Text(
                      'There is no active election cycle for this community Leader role at this time.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                     ),
                     ),
                   const SizedBox(height: 24),
                   TextButton.icon(
                     onPressed: () async {
                        await ref.read(governanceServiceProvider).seedMockElection(widget.unitId);
                        setState(() { /* Rebuild to catch changes */ });
                     },
                     icon: const Icon(LucideIcons.playCircle, size: 16),
                     label: const Text('Start Mock Election (Debug)'),
                   ),
                  ],
                ),
              );
            }
          final activeUnit = unit!;

          return SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              child: Column(
                children: [
                   Padding(
                    padding: const EdgeInsets.all(AppTheme.pageHorizontalPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(activeUnit),
                        
                        const SizedBox(height: 24),
                        _buildCurrentCouncil(activeUnit.councilMembers),

                        const SizedBox(height: 32),
                        const Text(
                          'SELECT YOUR REPRESENTATIVE',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2),
                        ),
                        const SizedBox(height: 16),
                          FutureBuilder<List<UserPoints>>(
                          future: ref.read(governanceServiceProvider).getCandidates(widget.unitId),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(child: Padding(
                                padding: EdgeInsets.all(32.0),
                                child: CircularProgressIndicator(),
                              ));
                            }
                            var candidates = snapshot.data ?? [];
                            
                            if (candidates.isEmpty) {
                              candidates = List.generate(5, (index) => UserPoints(
                                userId: 'mock-leader-$index',
                                totalPoints: 150000 + (index * 1234),
                                trustScore: 85 + index,
                                availablePoints: 50000,
                                currentStreak: 5,
                                dailyMessageCount: 10,
                                lastUpdated: DateTime.now(),
                                signupDate: DateTime.now().subtract(const Duration(days: 365)),
                                walletAddress: '0x${List.generate(40, (_) => 'A').join()}'
                              ));
                            }

                            if (candidates.isEmpty) {
                              return const Center(child: Text('No eligible Leaders found for this election.'));
                            }
                            
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildCandidateList(candidates),
                                
                                if (activeUnit.isTreasuryBearing)
                                  _buildMultiSigSelection(candidates),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 32),
                        _buildSubmitButton(activeUnit),
                        SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required IconData icon,
    String? subtitle,
    bool isDemo = false,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: theme.colorScheme.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (isDemo) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'DEMO',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 9, 
                    fontWeight: FontWeight.bold, 
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold, 
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5), 
              letterSpacing: 1.2,
            ),
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildHeader(GovernanceUnit unit) {
    final communityId = unit.communityId;
    
    if (widget.community != null) {
      return _buildHeaderContent(unit, community: widget.community!);
    }

    if (communityId != null) {
      return Consumer(
        builder: (context, ref, _) {
          final communityAsync = ref.watch(communityProvider(communityId));
          return communityAsync.when(
            data: (community) {
              if (community == null) return _buildHeaderContent(unit);
              return _buildHeaderContent(unit, community: community);
            },
            loading: () => _buildHeaderContent(unit, isLoading: true),
            error: (_, __) => _buildHeaderContent(unit),
          );
        },
      );
    }
    return _buildHeaderContent(unit);
  }

  Widget _buildHeaderContent(GovernanceUnit unit, {Community? community, bool isLoading = false}) {
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
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.accentDark, AppTheme.accentDark.withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppTheme.standardBorderRadius),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentDark.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (community != null)
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
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
                const CircleAvatar(radius: 16, backgroundColor: Colors.white24)
              else 
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                  child: const Icon(LucideIcons.landmark, color: Colors.white, size: 16),
                ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                     Text(
                      isLoading ? 'Loading...' : communityName,
                      style: const TextStyle(
                        fontSize: 22, 
                        fontWeight: FontWeight.bold, 
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      unit.isTreasuryBearing 
                        ? 'Institutional Treasury Custodians' 
                        : 'Governance Leader Selection',
                      style: TextStyle(
                        fontSize: 14, 
                        fontWeight: FontWeight.w500, 
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'The Diaspora Nearby platform is self-governing. Your vote determines which trusted community Leaders guide the council and safeguard the institutional treasury for the common good.',
            style: TextStyle(
              fontSize: 14, 
              color: Colors.white.withValues(alpha: 0.8), 
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentCouncil(List<String> memberIds) {
    final bool isMock = memberIds.isEmpty;
    final displayIds = isMock ? ['mock_1', 'mock_2', 'mock_3'] : memberIds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: isMock ? 'Mock Community Council' : 'Current Council Leaders',
          icon: LucideIcons.users,
          isDemo: isMock,
        ),
        ...displayIds.take(3).map((id) {
          return _LeaderTile(
            userId: id,
            isMock: id.startsWith('mock'),
            mockIndex: id.startsWith('mock') ? displayIds.indexOf(id) : null,
            showCheckmark: true,
            variant: LeaderTileVariant.council,
          );
        }).toList(),
      ],
    );
  }

  Widget _buildCandidateList(List<UserPoints> candidates) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        _buildSectionHeader(
          title: 'Vote for Council Leader',
          icon: LucideIcons.checkSquare,
        ),
        ...candidates.map((c) {
          final isSelected = _selectedCandidateId == c.userId;
          return _LeaderTile(
            userId: c.userId,
            userPoints: c,
            isSelected: isSelected,
            isMock: c.userId.startsWith('mock'),
            mockIndex: c.userId.startsWith('mock') ? candidates.indexOf(c) : null,
            onChanged: (val) => setState(() => _selectedCandidateId = val),
            variant: LeaderTileVariant.candidate,
          );
        }),
      ],
    );
  }

  Widget _buildMultiSigSelection(List<UserPoints> candidates) {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null) return const SizedBox.shrink();

    return Consumer(
      builder: (context, ref, _) {
        final myPointsAsync = ref.watch(userPointsProvider(user.uid));
        final theme = Theme.of(context);
        
        return Container(
          margin: const EdgeInsets.only(top: 24),
          padding: AppTheme.cardPaddingEdgeInsets,
          decoration: BoxDecoration(
            color: AppTheme.warning.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppTheme.standardBorderRadius),
          ),
          child: myPointsAsync.when(
            data: (myPoints) {
              final isLeaderCandidate = (myPoints?.totalDsp ?? 0) >= 100000 && (myPoints?.trustScore ?? 0) >= 67;
              
              if (!isLeaderCandidate) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader(
                      title: 'Treasury Multi-Sig Signer',
                      icon: LucideIcons.lock,
                    ),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        children: [
                          Icon(LucideIcons.users, size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Peer Selection: Only eligible Leader candidates can cast votes for treasury multi-sig signers. Your council vote still counts!',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader(
                    title: 'Treasury Multi-Sig Signer',
                    icon: LucideIcons.key,
                  ),
                  Text(
                    'Select which elected Leader should hold a key to the community treasury wallet.',
                    style: theme.textTheme.bodyMedium,
                  ),
                   const SizedBox(height: 16),
                   
                    ...candidates.take(5).map((c) {
                      return _LeaderTile(
                        userId: c.userId,
                        userPoints: c,
                        isSelected: _selectedSignerId == c.userId,
                        isMock: c.userId.startsWith('mock'),
                        mockIndex: c.userId.startsWith('mock') ? candidates.indexOf(c) : null,
                        onChanged: (val) => setState(() => _selectedSignerId = val),
                        variant: LeaderTileVariant.signer,
                      );
                    }).toList(),
                   
                   Padding(
                     padding: const EdgeInsets.only(top: 12.0),
                     child: Text(
                       '* Requires 3/5 consensus for transactions',
                       style: theme.textTheme.labelSmall?.copyWith(
                         fontStyle: FontStyle.italic, 
                         color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                       ),
                     ),
                   ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_,__) => const SizedBox.shrink(),
          ),
        );
      },
    );
  }

  Widget _buildSubmitButton(GovernanceUnit unit) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: (_selectedCandidateId == null || _isSubmitting) ? null : _submitVote,
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.accentDark,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.standardBorderRadius)),
        ),
        child: _isSubmitting
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text('Cast My Governance Vote', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Future<void> _submitVote() async {
    final user = ref.read(authRepositoryProvider).currentUser;
    setState(() => _isSubmitting = true);

    try {
      if (user != null) {
        await ref.read(governanceServiceProvider).castVote(
          unitId: widget.unitId,
          voterId: user.uid,
          candidateId: _selectedCandidateId!,
          signerId: _selectedSignerId,
        );
      } else {
        await Future.delayed(const Duration(seconds: 1)); 
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Your vote has been recorded on the chain of trust.')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error casting vote: $e')),
        );
      }
    }
  }
}

enum LeaderTileVariant { council, candidate, signer }

class _LeaderTile extends ConsumerWidget {
  final String userId;
  final UserPoints? userPoints;
  final bool isSelected;
  final ValueChanged<String?>? onChanged;
  final bool isMock;
  final int? mockIndex;
  final bool showCheckmark;
  final LeaderTileVariant variant;

  const _LeaderTile({
    required this.userId,
    this.userPoints,
    this.isSelected = false,
    this.onChanged,
    this.isMock = false,
    this.mockIndex,
    this.showCheckmark = false,
    this.variant = LeaderTileVariant.council,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileByIdProvider(userId));
    final pointsAsync = userPoints != null 
        ? AsyncValue.data(userPoints)
        : (isMock ? const AsyncValue.data(null) : ref.watch(userPointsProvider(userId)));

    final isCandidate = variant == LeaderTileVariant.candidate;
    final isSigner = variant == LeaderTileVariant.signer;
    final isCouncil = variant == LeaderTileVariant.council;

    if (isMock) {
      final mockNames = ['Zainab H.', 'Kwame O.', 'Amara K.', 'Johnathan D.', 'Sarah L.'];
      final name = mockIndex != null ? mockNames[mockIndex! % mockNames.length] : 'Mock Leader';
      final dspValue = userPoints?.totalPoints ?? 150000;
      final dspBalance = NumberFormat('#,###').format(dspValue);
      
      final theme = Theme.of(context);
      return _buildTileContainer(
        context,
        isSelected: isSelected,
        background: isSigner ? (isSelected ? AppTheme.warning.withValues(alpha: 0.2) : AppTheme.warning.withValues(alpha: 0.05)) : null,
        borderColor: isSigner ? (isSelected ? Colors.amber.shade800 : Colors.amber.shade200) : null,
        onTap: onChanged != null ? () => onChanged!(userId) : null,
        child: Row(
          children: [
            CircleAvatar(
              radius: isSigner ? 20 : 24,
              backgroundColor: isSigner ? AppTheme.warning.withValues(alpha: 0.2) : theme.colorScheme.primary.withValues(alpha: 0.1),
              child: Text(name[0], style: TextStyle(color: isSigner ? AppTheme.warning : theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: isSigner ? 13 : 15)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Row(
                    children: [
                      const Text('🗺️', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold, 
                            fontSize: isSigner ? 14 : 15,
                            color: isSigner ? AppTheme.warning : theme.colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (isCandidate || isSigner || isCouncil) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          isSigner ? LucideIcons.key : LucideIcons.shieldCheck, 
                          size: 13, 
                          color: isSigner ? AppTheme.warning : theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isSigner ? 'Treasury Key Holder' : '${userPoints?.trustScore ?? 85} PoCT',
                          style: TextStyle(
                            fontSize: 12, 
                            color: isSigner ? AppTheme.warning.withValues(alpha: 0.8) : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (isCandidate || isCouncil) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                            image: DecorationImage(
                              image: AssetImage('assets/icons/logo-original.png'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$dspBalance \$DSP',
                          style: TextStyle(
                            fontSize: 13, 
                            color: theme.colorScheme.tertiary, 
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (onChanged != null)
              Radio<String>(
                value: userId,
                groupValue: isSelected ? userId : null,
                onChanged: onChanged,
                activeColor: isSigner ? AppTheme.warning : theme.colorScheme.primary,
              )
            else if (showCheckmark)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Icon(LucideIcons.checkCircle, color: Colors.green, size: 18),
              ),
          ],
        ),
      );
    }

    return profileAsync.when(
      data: (profile) {
        if (profile == null) return const SizedBox.shrink();
        
        final theme = Theme.of(context);
        return pointsAsync.when(
          data: (points) {
            final up = points ?? userPoints;
            final flag = profile.homeCountryCode != null 
                ? getCountryByCode(profile.homeCountryCode!)?.flag ?? '🗺️'
                : '🗺️';
            final fullName = '${profile.firstName} ${profile.lastName ?? ""}';
            final dspBalance = up != null ? NumberFormat('#,###').format(up.totalPoints) : null;

            return _buildTileContainer(
              context,
              isSelected: isSelected,
              background: isSigner ? (isSelected ? AppTheme.warning.withValues(alpha: 0.2) : AppTheme.warning.withValues(alpha: 0.05)) : null,
              borderColor: isSigner ? (isSelected ? Colors.amber.shade800 : Colors.amber.shade200) : null,
              onTap: onChanged != null ? () => onChanged!(userId) : null,
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
                                  color: isSigner ? AppTheme.warning : theme.colorScheme.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (isCandidate || isSigner || isCouncil) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                isSigner ? LucideIcons.key : LucideIcons.shieldCheck, 
                                size: 13, 
                                color: isSigner ? AppTheme.warning : theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isSigner ? 'Treasury Key Holder' : '${up?.trustScore ?? 0} PoCT',
                                style: TextStyle(
                                  fontSize: 12, 
                                  color: isSigner ? AppTheme.warning.withValues(alpha: 0.8) : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if ((isCandidate || isCouncil) && dspBalance != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                width: 16,
                                height: 16,
                                decoration: const BoxDecoration(
                                  image: DecorationImage(
                                    image: AssetImage('assets/icons/logo-original.png'),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '$dspBalance \$DSP',
                                style: TextStyle(
                                  fontSize: 13, 
                                  color: theme.colorScheme.tertiary, 
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (onChanged != null)
                    Radio<String>(
                      value: userId,
                      groupValue: isSelected ? userId : null,
                      onChanged: onChanged,
                      activeColor: isSigner ? AppTheme.warning : theme.colorScheme.primary,
                    )
                  else if (showCheckmark)
                    const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: Icon(LucideIcons.checkCircle, color: Colors.green, size: 18),
                    ),
                ],
              ),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildAvatar(BuildContext context, ProfileData profile, {bool isSigner = false}) {
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

  Widget _buildTileContainer(BuildContext context, {
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
          color: background ?? (isSelected ? AppTheme.accent.withValues(alpha: 0.05) : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: borderColor ?? (isSelected ? AppTheme.accent : Colors.grey.shade200),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color: (borderColor ?? AppTheme.accent).withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ] : null,
        ),
        child: child,
      ),
    );
  }
}
