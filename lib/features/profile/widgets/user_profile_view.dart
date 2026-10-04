import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:url_launcher/url_launcher.dart';

import 'package:go_router/go_router.dart';

import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/shared/widgets/user_card.dart';
import 'package:diaspora_nearby/core/data/countries.dart' as country_data;
import 'package:diaspora_nearby/core/utils/location_utils.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/profile/widgets/relationship_card.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';

import 'package:diaspora_nearby/features/trust/services/trust_service.dart';
import 'package:diaspora_nearby/features/trust/repository/trust_repository.dart';

import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';

import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/relationship_repository.dart';
import 'package:diaspora_nearby/features/profile/models/relationship.dart';
import 'package:diaspora_nearby/features/profile/models/relationship_request.dart';
// For broadcast
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diaspora_nearby/features/profile/widgets/relationship_response_modal.dart';

import 'package:diaspora_nearby/features/profile/widgets/profile_qr_code_dialog.dart';

import 'package:diaspora_nearby/features/dsp/models/user_points.dart';
import 'package:diaspora_nearby/features/trust/models/trust_data.dart';

class UserProfileView extends ConsumerWidget {
  final ProfileData profile;
  final bool isSelf;
  final bool isEnforced;
  final VoidCallback onEdit;
  final Future<bool?> Function(List<String> missingFields)?
  onShowCompleteProfile;

  final double? distanceKm;
  final VoidCallback onRefresh;
  final String? src;

  Widget _buildFlagWarning() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: AppTheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isSelf
                  ? 'Flagged as incorrect. Please update or remove.'
                  : 'Flagged by community as potentially incorrect.',
              style: const TextStyle(fontSize: 12, color: AppTheme.error),
            ),
          ),
        ],
      ),
    );
  }

  const UserProfileView({
    super.key,
    required this.profile,
    required this.isSelf,
    this.isEnforced = false,
    required this.onEdit,
    this.onShowCompleteProfile,
    this.distanceKm,
    required this.onRefresh,
    this.src,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flaggedFieldsAsync = ref.watch(
      flaggedFieldsProvider(profile.uid ?? ''),
    );
    final flaggedFields = flaggedFieldsAsync.value ?? [];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          if (isSelf)
            TextButton.icon(
              onPressed: onEdit,
              icon: const Icon(LucideIcons.edit, size: 16),
              label: const Text('Edit'),
            ),
          IconButton(
            onPressed: () async {
              if (isSelf) {
                showDialog(
                  context: context,
                  builder: (context) => ProfileQRCodeDialog(profile: profile),
                );
              } else {
                final currentUser = ref
                    .read(authRepositoryProvider)
                    .currentUser;
                if (currentUser == null) return;
                var myProfile = ref.read(userProfileProvider).value;
                myProfile ??= await ref
                    .read(profileRepositoryProvider)
                    .getUserProfile(currentUser.uid);
                if (myProfile != null && context.mounted) {
                  showDialog(
                    context: context,
                    builder: (context) =>
                        ProfileQRCodeDialog(profile: myProfile!),
                  );
                }
              }
            },
            icon: const Icon(LucideIcons.qrCode, size: 20),
            tooltip: 'Identity QR',
          ),
        ],
        leading: () {
          if (isEnforced) return const SizedBox();
          if (src == 'qr' && !isSelf) {
            return IconButton(
              icon: const Icon(LucideIcons.x),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Close and go to my profile',
            );
          }
          return null;
        }(),
      ),
      body: Builder(
        builder: (context) {
          // [FIXED] Deep Link Check for Relationship Request Review
          // Allow checking for relationship requests regardless of whether viewing self or others
          // This enables notifications to properly trigger the modal when tapping them
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final uri = GoRouterState.of(context).uri;
            if (uri.queryParameters['action'] == 'review' &&
                uri.queryParameters['requestId'] != null) {
              _showReviewDialog(
                context,
                ref,
                uri.queryParameters['requestId']!,
              );
            }
          });

          return _safelyBuild(
            () => SingleChildScrollView(
              padding: EdgeInsets.only(
                top: 16,
                left: AppTheme.pageHorizontalPadding,
                right: AppTheme.pageHorizontalPadding,
                bottom: 16 + MediaQuery.of(context).padding.bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isSelf && profile.uid != null)
                    _PendingRequestMonitor(profileUserId: profile.uid!),

                  // ══════════════════════════════════
                  // 🔝 GLOBAL USER CARD (stays on top)
                  // ══════════════════════════════════
                  UserCardView(
                    key: const ValueKey('view_UserCard'),
                    user: profile,
                    flaggedFields: flaggedFields,
                    searchQuery: '',
                    onNameTap: () {},
                    onChatTap: isSelf
                        ? null
                        : () => context.push('/chat/direct/${profile.uid}'),
                    isStatic: true,
                    distanceKm: distanceKm,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppTheme.standardBorderRadius),
                    ),
                  ),

                  // 🎚️ TRUST SLIDER — removed from profile page.
                  // Vouching is only available on the chat "show more"
                  // page where users have had prior interaction.

                  // ══════════════════════════════════
                  // 📊 COMMUNITY STATUS CARD (no onTap)
                  // ══════════════════════════════════
                  if (!isSelf && profile.uid != null) ...[
                    Consumer(
                      builder: (context, ref, child) {
                        final pointsAsync = ref.watch(
                          userPointsProvider(profile.uid!),
                        );
                        final trustAsync = ref.watch(
                          userTrustProvider(profile.uid!),
                        );

                        return pointsAsync.when(
                          data: (userPoints) {
                            final points = userPoints?.availablePoints ?? 0;
                            final formattedPoints = NumberFormat(
                              '#,###',
                            ).format(points);

                            final double trustScore =
                                trustAsync.value?.trustScore ?? 0;
                            final double progress = trustScore / 100.0;

                            Color trustColor;
                            if (trustScore <= 20) {
                              trustColor = AppTheme.error;
                            } else if (trustScore <= 40) {
                              trustColor = Colors.deepOrange;
                            } else if (trustScore <= 60) {
                              trustColor = Colors.amber;
                            } else if (trustScore <= 80) {
                              trustColor = Colors.lightGreen;
                            } else {
                              trustColor = AppTheme.accent;
                            }

                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppTheme.pageHorizontalPadding,
                                vertical: 16,
                              ),
                              decoration: BoxDecoration(
                                color: trustColor.withValues(alpha: 0.1),
                                borderRadius: const BorderRadius.vertical(
                                  bottom: Radius.circular(
                                    AppTheme.standardBorderRadius,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  // PCT Score Graph
                                  SizedBox(
                                    height: 52,
                                    width: 52,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        CircularProgressIndicator(
                                          value: 1.0,
                                          strokeWidth: 4,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                trustColor.withValues(
                                                  alpha: 0.2,
                                                ),
                                              ),
                                        ),
                                        CircularProgressIndicator(
                                          value: progress,
                                          strokeWidth: 4,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                trustColor,
                                              ),
                                          strokeCap: StrokeCap.round,
                                        ),
                                        Text(
                                          '${trustScore.toInt()}',
                                          style: TextStyle(
                                            color: trustColor,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'Community Status',
                                              style: TextStyle(
                                                color: trustColor,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                            Text(
                                              'Balance',
                                              style: TextStyle(
                                                color: trustColor.withValues(
                                                  alpha: 0.8,
                                                ),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'PCT Score',
                                              style: TextStyle(
                                                color: trustColor,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Text(
                                              '$formattedPoints DSP',
                                              style: TextStyle(
                                                color: trustColor,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              textAlign: TextAlign.end,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Builder(
                                          builder: (context) {
                                            final signupDate =
                                                userPoints?.signupDate ??
                                                DateTime.now();
                                            final daysActive = DateTime.now()
                                                .difference(signupDate)
                                                .inDays;
                                            final formattedDate = DateFormat(
                                              'MMM d, yyyy',
                                            ).format(signupDate);
                                            return Row(
                                              children: [
                                                Text(
                                                  'Member Since: $formattedDate · $daysActive Days',
                                                  style: TextStyle(
                                                    color: trustColor
                                                        .withValues(alpha: 0.8),
                                                    fontSize: 11,
                                                    fontStyle: FontStyle.italic,
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                      ],
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
                    ),
                    const SizedBox(height: 16),
                  ],

                  const SizedBox(height: 16),

                  // ══════════════════════════════════════════
                  // 📍 GENESIS MILESTONES — Section Header
                  // ══════════════════════════════════════════
                  _buildPoctSectionHeader(
                    context,
                    title: 'Genesis Milestones',
                    subtitle: 'One-time +10 PCT at first 10 unique',
                    icon: LucideIcons.trophy,
                  ),
                  const SizedBox(height: 12),

                  // ─────────────────────────────────────
                  // 1️⃣ PROFILE COMPLETION (X/12)
                  // ─────────────────────────────────────
                  _buildMilestoneSubHeader(
                    context,
                    title: 'Profile Completion',
                    icon: LucideIcons.userCheck,
                    current: profile.completedMilestoneFieldCount,
                    target: profile.totalMilestoneFields,
                  ),
                  const SizedBox(height: 8),

                  // -- Bio --
                  if (profile.bio != null && profile.bio!.isNotEmpty)
                    _safelyBuild(
                      () => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader(
                            context,
                            'About Me',
                            icon: LucideIcons.info,
                          ),
                          if (flaggedFields.contains('Bio'))
                            _buildFlagWarning(),
                          _buildSectionContainer(
                            context,
                            child: Text(
                              profile.bio!,
                              style: const TextStyle(height: 1.5),
                            ),
                          ),
                        ],
                      ),
                      label: 'Bio',
                    ),

                  // -- Residency & Location --
                  if ((profile.yearsInHostCountry != null &&
                          profile.yearsInHostCountry!.isNotEmpty) ||
                      (profile.pastLocations?.isNotEmpty ?? false))
                    _safelyBuild(
                      () => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader(
                            context,
                            'Residency & Locations',
                            icon: LucideIcons.map,
                          ),
                          _buildSectionContainer(
                            context,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildResidencySection(context),
                                const SizedBox(height: 12),
                                _buildPastLocationsSection(context),
                              ],
                            ),
                          ),
                        ],
                      ),
                      label: 'LocationSection',
                    ),

                  // -- Professional Info --
                  if ((profile.profession?.isNotEmpty ?? false) ||
                      (profile.industry?.isNotEmpty ?? false))
                    _safelyBuild(
                      () => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader(
                            context,
                            'Professional Info',
                            icon: LucideIcons.graduationCap,
                          ),
                          if (flaggedFields.contains('Occupation'))
                            _buildFlagWarning(),
                          _buildSectionContainer(
                            context,
                            child: _buildProfessionalDisplay(context),
                          ),
                        ],
                      ),
                      label: 'Profession',
                    ),

                  // -- Education --
                  if (profile.education != null &&
                      profile.education!.isNotEmpty)
                    _safelyBuild(
                      () => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader(
                            context,
                            'Education',
                            icon: LucideIcons.school,
                          ),
                          if (flaggedFields.contains('Education'))
                            _buildFlagWarning(),
                          _buildSectionContainer(
                            context,
                            child: Column(
                              children: profile.education!
                                  .map(
                                    (edu) => ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                        edu.institution,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      subtitle: Text(
                                        '${edu.degree} \u2022 ${edu.graduationYear}',
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ],
                      ),
                      label: 'Education',
                    ),

                  // -- Languages --
                  if (profile.languages?.isNotEmpty ?? false)
                    _safelyBuild(
                      () => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader(
                            context,
                            'Languages',
                            icon: LucideIcons.languages,
                          ),
                          _buildSectionContainer(
                            context,
                            child: _buildTagsDisplay(
                              context,
                              profile.languages!,
                            ),
                          ),
                        ],
                      ),
                      label: 'Languages',
                    ),

                  // -- Interests --
                  if (profile.interests?.isNotEmpty ?? false)
                    _safelyBuild(
                      () => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader(
                            context,
                            'Interests',
                            icon: LucideIcons.sparkles,
                          ),
                          _buildSectionContainer(
                            context,
                            child: _buildTagsDisplay(
                              context,
                              profile.interests!,
                            ),
                          ),
                        ],
                      ),
                      label: 'Interests',
                    ),

                  // -- Community Support --
                  if ((profile.servicesOffered?.isNotEmpty ?? false) ||
                      (profile.lookingFor?.isNotEmpty ?? false))
                    _safelyBuild(
                      () => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader(
                            context,
                            'Community Support',
                            icon: LucideIcons.heartHandshake,
                          ),
                          _buildSectionContainer(
                            context,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (profile.servicesOffered?.isNotEmpty ??
                                    false) ...[
                                  const Text(
                                    'Services I Can Offer',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _buildTagsDisplay(
                                    context,
                                    profile.servicesOffered!,
                                    isOutline: true,
                                  ),
                                  const SizedBox(height: 16),
                                ],
                                if (profile.lookingFor?.isNotEmpty ??
                                    false) ...[
                                  const Text(
                                    "What I'm Looking For",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _buildTagsDisplay(
                                    context,
                                    profile.lookingFor!,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      label: 'CommunitySupport',
                    ),

                  // -- Availability --
                  if (profile.availability?.isNotEmpty ?? false)
                    _safelyBuild(
                      () => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader(
                            context,
                            'Availability',
                            icon: LucideIcons.calendar,
                          ),
                          _buildSectionContainer(
                            context,
                            child: _buildTagsDisplay(
                              context,
                              profile.availability!,
                            ),
                          ),
                        ],
                      ),
                      label: 'Availability',
                    ),

                  // -- Meeting Preferences --
                  if (profile.meetingPreferences?.isNotEmpty ?? false)
                    _safelyBuild(
                      () => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader(
                            context,
                            'Meeting Preferences',
                            icon: LucideIcons.users,
                          ),
                          _buildSectionContainer(
                            context,
                            child: _buildTagsDisplay(
                              context,
                              profile.meetingPreferences!,
                            ),
                          ),
                        ],
                      ),
                      label: 'MeetingPrefs',
                    ),

                  // -- Social Media --
                  if (profile.socialLinks != null)
                    _safelyBuild(
                      () => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader(
                            context,
                            'Social Media',
                            icon: LucideIcons.globe,
                          ),
                          _buildSectionContainer(
                            context,
                            child: Wrap(
                              spacing: 16,
                              children: [
                                if (profile
                                        .socialLinks!
                                        .instagram
                                        ?.isNotEmpty ??
                                    false)
                                  _buildSocialLink(
                                    LucideIcons.instagram,
                                    profile.socialLinks!.instagram!,
                                  ),
                                if (profile.socialLinks!.twitter?.isNotEmpty ??
                                    false)
                                  _buildSocialLink(
                                    LucideIcons.twitter,
                                    profile.socialLinks!.twitter!,
                                  ),
                                if (profile.socialLinks!.linkedin?.isNotEmpty ??
                                    false)
                                  _buildSocialLink(
                                    LucideIcons.linkedin,
                                    profile.socialLinks!.linkedin!,
                                  ),
                                if (profile.socialLinks!.facebook?.isNotEmpty ??
                                    false)
                                  _buildSocialLink(
                                    LucideIcons.facebook,
                                    profile.socialLinks!.facebook!,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      label: 'SocialMedia',
                    ),

                  // -- Business Profile --
                  if (profile.businessProfile?.isBusinessVerified == true)
                    _safelyBuild(
                      () =>
                          _buildBusinessCard(context, profile.businessProfile!),
                      label: 'BusinessCard',
                    ),

                  const SizedBox(height: 20),

                  // ─────────────────────────────────────
                  // 2️⃣ FAMILY CONNECTIONS (X/10)
                  // ─────────────────────────────────────
                  if (profile.uid != null)
                    Consumer(
                      builder: (context, ref, _) {
                        final trustAsync = ref.watch(
                          userTrustProvider(profile.uid!),
                        );
                        final trust = trustAsync.value;
                        final familyCount = trust?.uniqueFamilyCount ?? 0;
                        final genesisFamilyIds = trust?.genesisFamilyIds ?? [];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildMilestoneSubHeader(
                              context,
                              title: 'Family Connections',
                              icon: LucideIcons.heartHandshake,
                              current: familyCount > 10 ? 10 : familyCount,
                              target: 10,
                            ),
                            const SizedBox(height: 8),
                            if (genesisFamilyIds.isNotEmpty)
                              _buildMilestoneUserCards(
                                context,
                                ref,
                                userIds: genesisFamilyIds,
                                emptyMessage: 'No family connections yet',
                              )
                            else
                              _buildEmptyMilestoneCard(
                                context,
                                'No family connections yet',
                                LucideIcons.heartHandshake,
                              ),
                            // Incoming/Sent requests (self only)
                            if (isSelf) _buildIncomingRequests(context, ref),
                            if (isSelf) _buildSentRequests(context, ref),
                          ],
                        );
                      },
                    ),

                  const SizedBox(height: 20),

                  // ─────────────────────────────────────
                  // 3️⃣ COMMUNITY VERIFICATIONS (X/10)
                  // ─────────────────────────────────────
                  if (profile.uid != null)
                    Consumer(
                      builder: (context, ref, _) {
                        final trustAsync = ref.watch(
                          userTrustProvider(profile.uid!),
                        );
                        final trust = trustAsync.value;
                        final verificationCount =
                            trust?.uniqueVerificationCount ?? 0;
                        final capped = verificationCount > 10
                            ? 10
                            : verificationCount;
                        final genesisVerificationIds =
                            trust?.genesisVerificationIds ?? [];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildMilestoneSubHeader(
                              context,
                              title: 'Community Verifications',
                              icon: LucideIcons.shieldCheck,
                              current: capped,
                              target: 10,
                            ),
                            const SizedBox(height: 8),
                            if (genesisVerificationIds.isNotEmpty)
                              _buildMilestoneUserCards(
                                context,
                                ref,
                                userIds: genesisVerificationIds,
                                emptyMessage: 'No verifications yet',
                              )
                            else
                              _buildEmptyMilestoneCard(
                                context,
                                'No verifications yet',
                                LucideIcons.shieldCheck,
                              ),
                          ],
                        );
                      },
                    ),

                  const SizedBox(height: 20),

                  // ─────────────────────────────────────
                  // 4️⃣ COMMUNITY VOUCHES (X/10)
                  // ─────────────────────────────────────
                  if (profile.uid != null)
                    Consumer(
                      builder: (context, ref, _) {
                        final trustAsync = ref.watch(
                          userTrustProvider(profile.uid!),
                        );
                        final trust = trustAsync.value;
                        final vouchCount = trust?.uniqueVouchCount ?? 0;
                        final capped = vouchCount > 10 ? 10 : vouchCount;
                        final genesisVouchIds = trust?.genesisVouchIds ?? [];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildMilestoneSubHeader(
                              context,
                              title: 'Community Vouches',
                              icon: LucideIcons.award,
                              current: capped,
                              target: 10,
                            ),
                            const SizedBox(height: 8),
                            if (genesisVouchIds.isNotEmpty)
                              _buildMilestoneUserCards(
                                context,
                                ref,
                                userIds: genesisVouchIds,
                                emptyMessage: 'No vouches yet',
                              )
                            else
                              _buildEmptyMilestoneCard(
                                context,
                                'No vouches yet',
                                LucideIcons.award,
                              ),
                          ],
                        );
                      },
                    ),

                  const SizedBox(height: 20),

                  // ─────────────────────────────────────
                  // 5️⃣ FRIENDS (X/10)
                  // ─────────────────────────────────────
                  if (profile.uid != null)
                    Consumer(
                      builder: (context, ref, _) {
                        final trustAsync = ref.watch(
                          userTrustProvider(profile.uid!),
                        );
                        final trust = trustAsync.value;
                        final friendCount = trust?.uniqueFriendCount ?? 0;
                        final genesisFriendIds = trust?.genesisFriendIds ?? [];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildMilestoneSubHeader(
                              context,
                              title: 'Friend Connections',
                              icon: LucideIcons.users,
                              current: friendCount > 10 ? 10 : friendCount,
                              target: 10,
                            ),
                            const SizedBox(height: 8),
                            if (genesisFriendIds.isNotEmpty)
                              _buildMilestoneUserCards(
                                context,
                                ref,
                                userIds: genesisFriendIds,
                                emptyMessage: 'No friend connections yet',
                              )
                            else
                              _buildEmptyMilestoneCard(
                                context,
                                'No friend connections yet',
                                LucideIcons.users,
                              ),
                          ],
                        );
                      },
                    ),

                  const SizedBox(height: 20),

                  // ─────────────────────────────────────
                  // 6️⃣ QR CONNECTIONS (X/10)
                  // ─────────────────────────────────────
                  if (profile.uid != null)
                    Consumer(
                      builder: (context, ref, _) {
                        final trustAsync = ref.watch(
                          userTrustProvider(profile.uid!),
                        );
                        final trust = trustAsync.value;
                        final qrCount = trust?.uniqueQrCount ?? 0;
                        final genesisQrIds = trust?.genesisQrIds ?? [];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildMilestoneSubHeader(
                              context,
                              title: 'QR Identity Exchanges',
                              icon: LucideIcons.qrCode,
                              current: qrCount > 10 ? 10 : qrCount,
                              target: 10,
                            ),
                            const SizedBox(height: 8),
                            // Show QR exchange cards with location/timestamp
                            if (genesisQrIds.isNotEmpty)
                              _buildQrExchangeCards(
                                context,
                                ref,
                                userIds: genesisQrIds,
                                profileUid: profile.uid!,
                              )
                            else
                              _buildEmptyMilestoneCard(
                                context,
                                'No QR identity exchanges yet',
                                LucideIcons.qrCode,
                              ),
                          ],
                        );
                      },
                    ),

                  const SizedBox(height: 24),

                  // ─────────────────────────────────────
                  // 7️⃣ ACTIVE LOCATION TRANSPARENCY (1/1)
                  // ─────────────────────────────────────
                  if (profile.uid != null)
                    Consumer(
                      builder: (context, ref, _) {
                        final cityForfeited =
                            profile.cityVisibilityForfeited == true;
                        final hasCurrentLocation =
                            profile.currentLocation != null;
                        final visibilityOn =
                            profile.showCurrentLocationName != false;
                        final isTransparent =
                            !cityForfeited &&
                            hasCurrentLocation &&
                            visibilityOn;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildMilestoneSubHeader(
                              context,
                              title: 'Location Transparency',
                              icon: LucideIcons.mapPin,
                              current: isTransparent ? 1 : 0,
                              target: 1,
                            ),
                            const SizedBox(height: 8),
                            if (isTransparent)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AppTheme.accent.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppTheme.accent.withValues(
                                      alpha: 0.3,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      LucideIcons.checkCircle2,
                                      color: AppTheme.accent,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Active Location Transparency',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.accent,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Earning +10 PCT for maintaining community transparency.',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Theme.of(
                                                context,
                                              ).hintColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              _buildEmptyMilestoneCard(
                                context,
                                cityForfeited
                                    ? 'Transparency Permanently Forfeited'
                                    : 'Location Transparency Inactive',
                                LucideIcons.mapPinOff,
                                iconColor: cityForfeited
                                    ? AppTheme.error
                                    : null,
                              ),
                          ],
                        );
                      },
                    ),

                  const SizedBox(height: 24),

                  // ══════════════════════════════════════════
                  // 🔄 TRUST SLIDER VOUCHES — Section Header
                  // ══════════════════════════════════════════
                  if (profile.uid != null)
                    Consumer(
                      builder: (context, ref, _) {
                        final trustAsync = ref.watch(
                          userTrustProvider(profile.uid!),
                        );
                        return trustAsync.when(
                          data: (trust) {
                            if (trust == null) return const SizedBox.shrink();
                            return _buildTrustSliderVouchesSection(
                              context,
                              ref,
                              trust,
                            );
                          },
                          loading: () => const SizedBox.shrink(),
                          error: (_, _) => const SizedBox.shrink(),
                        );
                      },
                    ),

                  const SizedBox(height: 24),

                  // ══════════════════════════════════════════
                  // 🕐 SENIORITY — Section
                  // ══════════════════════════════════════════
                  if (profile.uid != null)
                    Consumer(
                      builder: (context, ref, _) {
                        final pointsAsync = ref.watch(
                          userPointsProvider(profile.uid!),
                        );
                        return pointsAsync.when(
                          data: (userPoints) {
                            if (userPoints == null) {
                              return const SizedBox.shrink();
                            }
                            return _buildSenioritySection(context, userPoints);
                          },
                          loading: () => const SizedBox.shrink(),
                          error: (_, _) => const SizedBox.shrink(),
                        );
                      },
                    ),

                  const SizedBox(height: 24),

                  // ══════════════════════════════════════════
                  // ⚠️ PENALTIES — Section
                  // ══════════════════════════════════════════
                  if (profile.uid != null)
                    Consumer(
                      builder: (context, ref, _) {
                        final trustAsync = ref.watch(
                          userTrustProvider(profile.uid!),
                        );
                        return trustAsync.when(
                          data: (trust) {
                            if (trust == null) return const SizedBox.shrink();
                            return _buildPenaltiesSection(context, trust);
                          },
                          loading: () => const SizedBox.shrink(),
                          error: (_, _) => const SizedBox.shrink(),
                        );
                      },
                    ),

                  const SizedBox(height: 8),
                ],
              ),
            ),
            label: 'ProfileBody',
          );
        },
      ),
    );
  }

  /// [NEW] Integrity Safety Wrapper
  Widget _safelyBuild(Widget Function() builder, {String label = 'Section'}) {
    try {
      return builder();
    } catch (e) {
      debugPrint('Error rendering $label: $e');
      return const SizedBox.shrink();
    }
  }

  Widget _buildSectionContainer(
    BuildContext context, {
    required Widget child,
    EdgeInsetsGeometry? padding,
  }) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.zero, // 0px margins
      padding:
          padding ??
          const EdgeInsets.all(
            AppTheme.sectionHorizontalPadding,
          ), // 8px padding
      decoration: AppTheme.cardDecoration(context),
      child: child,
    );
  }

  Widget _buildResidencySection(BuildContext context) {
    if (profile.yearsInHostCountry == null ||
        profile.yearsInHostCountry!.isEmpty) {
      return const SizedBox.shrink();
    }

    final isSinceBirth = profile.yearsInHostCountry == 'Since birth';
    final yearText = profile.yearsInHostCountry!;
    String durationText = '';

    if (!isSinceBirth) {
      final startYear = int.tryParse(yearText);
      if (startYear != null) {
        final diff = DateTime.now().year - startYear;
        durationText = ' \u2022 $diff years';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Lived in ${profile.hostCountry ?? 'this country'} since',
          style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: AppTheme.innerDecoration(context),
          child: Row(
            children: [
              Icon(
                LucideIcons.clock,
                size: 16,
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(width: 8),
              Text(
                isSinceBirth ? 'Birth' : '$yearText$durationText',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPastLocationsSection(BuildContext context) {
    if (profile.pastLocations == null || profile.pastLocations!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Also lived in',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        ...profile.pastLocations!.map((p) {
          return (() {
            try {
              String? flag;
              if (p.location.countryCode != null) {
                flag = country_data
                    .getCountryByCode(p.location.countryCode!)
                    ?.flag;
              }

              // Fallback: search by country name if code is missing
              if (flag == null && p.location.country != null) {
                final countries = country_data.countries
                    .where(
                      (c) =>
                          c.name.toLowerCase() ==
                              p.location.country!.toLowerCase() ||
                          c.code.toLowerCase() ==
                              p.location.country!.toLowerCase(),
                    )
                    .toList();
                if (countries.isNotEmpty) flag = countries.first.flag;
              }

              // [STANDARDIZATION] Use full address
              final formattedAddress = formatFullAddress(
                p.location.formattedAddress,
              );

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: AppTheme.innerDecoration(context),
                child: Row(
                  children: [
                    const Icon(
                      LucideIcons.mapPin,
                      size: 16,
                      color: Colors.grey,
                    ),
                    if (flag != null) ...[
                      const SizedBox(width: 8),
                      Text(flag, style: const TextStyle(fontSize: 18)),
                    ],
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formattedAddress,
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Until ${() {
                              try {
                                final dt = DateTime.parse(p.until);
                                return dt.year.toString();
                              } catch (_) {
                                return p.until;
                              }
                            }()}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            } catch (e) {
              debugPrint('Error rendering past location: $e');
              return const SizedBox.shrink();
            }
          })();
        }),
      ],
    );
  }

  Widget _buildBusinessCard(BuildContext context, BusinessProfile business) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(
        context,
      ).copyWith(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.blue.shade600,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(LucideIcons.briefcase, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      business.businessName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.blue.shade900
                            : Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        business.businessType,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.blue.shade300
                              : Colors.blue.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.green.shade900
                      : Colors.green.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  'Verified Business',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.green.shade300
                        : Colors.green.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            business.businessDescription,
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              if (business.businessEmail.isNotEmpty)
                _buildBusinessContact(
                  LucideIcons.globe,
                  business.businessEmail,
                  'mailto:${business.businessEmail}',
                ),
              if (business.businessPhone.isNotEmpty)
                _buildBusinessContact(
                  LucideIcons.phone,
                  business.businessPhone,
                  'tel:${business.businessPhone}',
                ),
              if (business.website.isNotEmpty)
                _buildBusinessContact(
                  LucideIcons.link,
                  business.website,
                  business.website,
                ),
            ],
          ),
          if (business.businessAddress.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(LucideIcons.mapPin, size: 14, color: Colors.blue.shade600),
                const SizedBox(width: 4),
                // [STANDARDIZATION] Use full address
                Expanded(
                  child: Text(
                    formatFullAddress(business.businessAddress),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildQRConnectionSection(BuildContext context, WidgetRef ref) {
    final info = profile.firstQrConnection!;

    return Padding(
      padding: const EdgeInsets.only(top: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: AppTheme.accent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        LucideIcons.check,
                        size: 10,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Trusted In-Person Connection'.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.accent,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ref
                    .watch(userProfileByIdProvider(info.otherUid))
                    .when(
                      data: (otherProfile) {
                        if (otherProfile == null) {
                          return const SizedBox.shrink();
                        }
                        return UserCardView(
                          user: otherProfile,
                          flaggedFields: const [],
                          searchQuery: '',
                          onNameTap: () =>
                              context.push('/profile/${otherProfile.uid}'),
                          isStatic: true,
                          showCurrentLocation: false,
                        );
                      },
                      loading: () => const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      error: (_, _) => const SizedBox.shrink(),
                    ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.mapPin,
                        size: 14,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          info.locationAddress != null &&
                                  info.locationAddress != 'Location Unavailable'
                              ? 'Connected in ${info.locationAddress!}'
                              : 'Location not recorded',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          LucideIcons.calendar,
                          size: 14,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          DateFormat.yMMMd().add_jm().format(
                            DateTime.parse(info.timestamp),
                          ),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    const Text(
                      '100 DSP EARNED',
                      style: TextStyle(
                        color: AppTheme.accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBusinessContact(IconData icon, String text, String url) {
    return InkWell(
      onTap: () => launchUrl(Uri.parse(url)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.blue.shade600),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: Colors.blue.shade600,
              decoration: TextDecoration.underline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagsDisplay(
    BuildContext context,
    List<String> tags, {
    bool isOutline = false,
  }) {
    // [FIX] Sanitize input list to remove nulls or empty strings
    final validTags = tags.where((t) => t.isNotEmpty).toList();

    if (validTags.isEmpty) {
      return const Text('Not specified', style: TextStyle(color: Colors.grey));
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: validTags
          .map((tag) => _buildChip(context, tag, isOutline: isOutline))
          .toList(),
    );
  }

  Widget _buildChip(
    BuildContext context,
    String tag, {
    bool isOutline = false,
  }) {
    return Chip(
      label: Text(tag),
      backgroundColor: isOutline
          ? Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
          : null,
      side: BorderSide.none,
    );
  }

  Widget _buildSocialLink(IconData icon, String url) {
    return IconButton(
      icon: Icon(icon),
      onPressed: () => launchUrl(Uri.parse(url)),
      tooltip: url,
    );
  }

  Widget _buildProfessionalDisplay(BuildContext context) {
    final professions =
        profile.profession?.where((t) => t.isNotEmpty).toList() ?? [];
    final industries =
        profile.industry?.where((t) => t.isNotEmpty).toList() ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (professions.isNotEmpty || industries.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...professions.map(
                (t) => _buildChip(context, t, isOutline: false),
              ),
              // Use outline for industries to visually distinguish them in the same flow
              ...industries.map((t) => _buildChip(context, t, isOutline: true)),
            ],
          ),

        if (profile.occupation != null && profile.occupation!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                LucideIcons.briefcase,
                size: 16,
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  profile.occupation!,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title, {
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: Theme.of(context).hintColor),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).hintColor,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // [NEW] Relationship Section Builder
  // ignore: unused_element
  Widget _buildRelationshipsSection(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Incoming Requests (Self Only)
        if (isSelf) _buildIncomingRequests(context, ref),

        // [NEW] Sent Requests (Self Only)
        if (isSelf) _buildSentRequests(context, ref),

        _buildSectionContainer(
          context,
          padding: const EdgeInsets.all(AppTheme.pageHorizontalPadding),
          child: ref
              .watch(userRelationshipsProvider(profile.uid!))
              .when(
                data: (relationships) {
                  if (relationships.isEmpty) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16.0),
                      alignment: Alignment.center,
                      child: Text(
                        'No relationships added yet.',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    );
                  }

                  // Sort by name for consistency
                  final sorted = List<Relationship>.from(relationships)
                    ..sort((a, b) => a.name.compareTo(b.name));

                  return _buildGroupedRelationships(context, sorted);
                },
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(8.0),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (e, st) => Text(
                  'Error loading relationships: $e',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
        ),
      ],
    );
  }

  // [UPDATED] Sent Requests Widget — theme-aware with cancel button
  Widget _buildSentRequests(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return StreamBuilder<List<RelationshipRequest>>(
      stream: ref
          .read(relationshipRepositoryProvider)
          .getSentRequests(profile.uid!),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sent Requests (${snapshot.data!.length})',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              ...snapshot.data!.map(
                (req) => Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            // Profile photo avatar
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: theme.colorScheme.primary
                                  .withValues(alpha: 0.15),
                              backgroundImage:
                                  req.toUserPhoto != null &&
                                      req.toUserPhoto!.isNotEmpty
                                  ? NetworkImage(req.toUserPhoto!)
                                  : null,
                              child:
                                  req.toUserPhoto == null ||
                                      req.toUserPhoto!.isEmpty
                                  ? Text(
                                      req.toUserName.isNotEmpty
                                          ? req.toUserName[0].toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: theme.colorScheme.primary,
                                        fontSize: 16,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    req.toUserName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'As: ${req.relationshipType}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Side-by-side Pending / Cancel buttons
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: null, // Disabled — info only
                                icon: const Icon(LucideIcons.clock, size: 14),
                                label: const Text('Pending'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.orange,
                                  disabledForegroundColor: Colors.orange,
                                  side: BorderSide(
                                    color: Colors.orange.withValues(alpha: 0.4),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _handleCancelSentRequest(context, ref, req),
                                icon: const Icon(LucideIcons.x, size: 14),
                                label: const Text('Cancel'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: theme.colorScheme.error,
                                  side: BorderSide(
                                    color: theme.colorScheme.error.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // [NEW] Grouped Relationships Widget
  Widget _buildGroupedRelationships(
    BuildContext context,
    List<Relationship> relationships,
  ) {
    final Map<String, List<Relationship>> grouped = {
      'Immediate Family': [],
      'Extended Family': [],
      'Friends': [],
      'Professional': [],
      'Community': [],
    };
    final List<Relationship> others = [];

    for (final rel in relationships) {
      final type = rel.type.toLowerCase();
      if ([
        'father',
        'mother',
        'son',
        'daughter',
        'husband',
        'wife',
        'brother',
        'sister',
        'grandfather',
        'grandmother',
        'grandson',
        'granddaughter',
      ].contains(type)) {
        grouped['Immediate Family']!.add(rel);
      } else if ([
        'uncle',
        'aunt',
        'nephew',
        'niece',
        'cousin',
        'relative',
      ].contains(type)) {
        grouped['Extended Family']!.add(rel);
      } else if (['friend', 'best friend', 'close friend'].contains(type)) {
        grouped['Friends']!.add(rel);
      } else if ([
        'business partner',
        'colleague',
        'mentor',
        'mentee',
      ].contains(type)) {
        grouped['Professional']!.add(rel);
      } else if (['community member', 'neighbor', 'leader'].contains(type)) {
        grouped['Community']!.add(rel);
      } else {
        others.add(rel);
      }
    }

    // Add 'Others' if active
    if (others.isNotEmpty) {
      grouped['Others'] = others;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in grouped.entries)
          if (entry.value.isNotEmpty) ...[
            ...entry.value.map(
              (rel) =>
                  RelationshipCard(relationship: rel, enableActions: isSelf),
            ),
            const SizedBox(height: 4),
          ],
      ],
    );
  }

  // [UPDATED] Incoming Requests Widget — theme-aware
  Widget _buildIncomingRequests(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return StreamBuilder<List<RelationshipRequest>>(
      stream: ref
          .read(relationshipRepositoryProvider)
          .getIncomingRequests(profile.uid!),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pending Requests (${snapshot.data!.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(height: 8),
              ...snapshot.data!.map(
                (req) => Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            // Profile photo avatar
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: Colors.orange.withValues(
                                alpha: 0.15,
                              ),
                              backgroundImage:
                                  req.fromUserPhoto != null &&
                                      req.fromUserPhoto!.isNotEmpty
                                  ? NetworkImage(req.fromUserPhoto!)
                                  : null,
                              child:
                                  req.fromUserPhoto == null ||
                                      req.fromUserPhoto!.isEmpty
                                  ? Text(
                                      req.fromUserName.isNotEmpty
                                          ? req.fromUserName[0].toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange.shade700,
                                        fontSize: 16,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    req.fromUserName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  RichText(
                                    text: TextSpan(
                                      text: 'Wants to add you as ',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                      children: [
                                        TextSpan(
                                          text: req.relationshipType,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: theme.colorScheme.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Side-by-side Decline / Accept buttons
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _handleRejectRequest(context, ref, req),
                                icon: const Icon(LucideIcons.x, size: 14),
                                label: const Text('Decline'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: theme.colorScheme.error,
                                  side: BorderSide(
                                    color: theme.colorScheme.error.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () =>
                                    _handleAcceptRequest(context, ref, req),
                                icon: const Icon(LucideIcons.check, size: 14),
                                label: const Text('Accept'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleAcceptRequest(
    BuildContext context,
    WidgetRef ref,
    RelationshipRequest req,
  ) async {
    try {
      final repository = ref.read(relationshipRepositoryProvider);

      // Determine possible reciprocal types logic
      // e.g. if my request says "Father", I must be "Son" or "Daughter" (or "Child")
      // Logic should be in Repository to map "Father" -> ["Son", "Daughter"]
      List<String> possibleTypes = repository.getPossibleReciprocalTypes(
        req.relationshipType,
      );

      String? selectedType;

      if (possibleTypes.length == 1) {
        selectedType = possibleTypes.first;
      } else {
        // Show Selection Dialog
        selectedType = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            String? tempSelected = possibleTypes.first;
            return StatefulBuilder(
              builder: (context, setState) {
                return AlertDialog(
                  title: const Text('Accept as...'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RadioGroup<String>(
                          groupValue: tempSelected,
                          onChanged: (val) =>
                              setState(() => tempSelected = val),
                          child: Column(
                            children: possibleTypes
                                .map(
                                  (type) => RadioListTile<String>(
                                    title: Text(type),
                                    value: type,
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.amber.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                size: 18,
                                color: Colors.amber,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Binding Commitment: Accepting directly ties your trust and economic fortune together. If either member is penalized for misconduct or fraud, identical DSP & PCT penalties will be deducted from your account.',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(fontSize: 11, height: 1.3),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, tempSelected),
                      child: const Text('Confirm'),
                    ),
                  ],
                );
              },
            );
          },
        );
      }

      if (selectedType != null) {
        // Get my flag
        String myFlag = '';
        if (profile.homeCountryCode != null) {
          try {
            final country = country_data.getCountryByCode(
              profile.homeCountryCode!,
            );
            if (country != null) myFlag = country.flag;
          } catch (_) {}
        }

        await repository.acceptRequest(req, myFlag, selectedType);
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Request accepted!')));
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error accepting: $e')));
      }
    }
  }

  Future<void> _handleRejectRequest(
    BuildContext context,
    WidgetRef ref,
    RelationshipRequest req,
  ) async {
    // Confirm rejection (warn about PCT penalty if desired, or simpler)
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Reject Relationship?'),
        content: const Text(
          'Rejecting this request will signal that you do NOT know this person as claimed. This may affect their Community Trust score.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Reject & Penalize'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ref.read(relationshipRepositoryProvider).rejectRequest(req);
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Request rejected.')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error rejecting: $e')));
        }
      }
    }
  }

  // [NEW] Cancel Sent Request handler
  Future<void> _handleCancelSentRequest(
    BuildContext context,
    WidgetRef ref,
    RelationshipRequest req,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cancel Request?'),
        content: Text(
          'Cancel your ${req.relationshipType} request to ${req.toUserName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(c).colorScheme.error,
            ),
            child: const Text('Cancel Request'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ref.read(relationshipRepositoryProvider).cancelSentRequest(req);
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Request cancelled.')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error cancelling: $e')));
        }
      }
    }
  }

  void _showReviewDialog(
    BuildContext context,
    WidgetRef ref,
    String requestId,
  ) {
    // Fetch request or wait for stream?
    // Since this is a one-off, fetching directly via stream might be tricky.
    // But _buildIncomingRequests is already streaming.
    // If the request is pending, it will show up in the list.
    // However, to show a *Dialog*, we need the request object.
    // I'll fetch it from collection directly for the dialog?
    // Or just let the user see it in the list (highlighted?).
    // The requirement said "automatic accept/reject dialog".
    // I will trigger a simple fetch for the dialog.
    FirebaseFirestore.instance
        .collection('relationship_requests')
        .doc(requestId)
        .get()
        .then((doc) {
          if (doc.exists && doc.data() != null) {
            final data = doc.data()!;
            if (data['status'] == 'pending') {
              final req = RelationshipRequest.fromMap(data);
              // Show the same card but in dialog
              if (context.mounted) {
                showDialog(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Review Relationship Request'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${req.fromUserName} wants to add you as ${req.relationshipType}',
                        ),
                        const SizedBox(height: 16),
                        // Could reuse card logic or buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () {
                                Navigator.pop(c);
                                _handleRejectRequest(context, ref, req);
                              },
                              child: const Text(
                                'Reject',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.pop(c);
                                _handleAcceptRequest(context, ref, req);
                              },
                              child: const Text('Accept'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }
            }
          }
        });
  }

  // ══════════════════════════════════════════════════════
  //  PCT SECTION BUILDERS
  // ══════════════════════════════════════════════════════

  /// Main section header — plain text, no card wrapper
  Widget _buildPoctSectionHeader(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.pageHorizontalPadding,
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: fg.withValues(alpha: 0.7)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    color: fg,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Milestone sub-header with progress bar — uses theme colors
  Widget _buildMilestoneSubHeader(
    BuildContext context, {
    required String title,
    required IconData icon,
    required int current,
    required int target,
  }) {
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onSurface;
    final progress = (current / target).clamp(0.0, 1.0);
    final isComplete = current >= target;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.pageHorizontalPadding,
        vertical: 4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: fg.withValues(alpha: 0.6)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: fg,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (isComplete)
                const Icon(
                  LucideIcons.checkCircle,
                  size: 16,
                  color: AppTheme.accent,
                )
              else
                Text(
                  '$current / $target',
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.6),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: fg.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation<Color>(
                isComplete
                    ? AppTheme.accent
                    : AppTheme.accent.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build QR exchange cards with location and timestamp
  Widget _buildQrExchangeCards(
    BuildContext context,
    WidgetRef ref, {
    required List<String> userIds,
    required String profileUid,
  }) {
    if (userIds.isEmpty) {
      return _buildEmptyMilestoneCard(
        context,
        'No QR identity exchanges yet',
        LucideIcons.qrCode,
      );
    }

    return FutureBuilder<Map<String, Map<String, dynamic>>>(
      future: ref
          .read(trustRepositoryProvider)
          .getQrExchangeRecords(profileUid),
      builder: (context, snapshot) {
        final records = snapshot.data ?? {};

        return Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AppTheme.pageHorizontalPadding,
          ),
          child: Column(
            children: userIds.map((uid) {
              final exchangeData = records[uid];
              return Consumer(
                builder: (context, ref, _) {
                  final profileAsync = ref.watch(userProfileByIdProvider(uid));
                  return profileAsync.when(
                    data: (userProfile) {
                      if (userProfile == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            UserCardView(
                              user: userProfile,
                              searchQuery: '',
                              onNameTap: () => context.push('/profile/$uid'),
                              onChatTap: () =>
                                  context.push('/chat/direct/$uid'),
                              isStatic: false,
                            ),
                            if (exchangeData != null)
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 12,
                                  right: 12,
                                  bottom: 8,
                                ),
                                child: Row(
                                  children: [
                                    // Location
                                    if (exchangeData['locationAddress'] !=
                                            null &&
                                        exchangeData['locationAddress'] !=
                                            'Location Unavailable') ...[
                                      const Icon(
                                        LucideIcons.mapPin,
                                        size: 12,
                                        color: Colors.grey,
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          exchangeData['locationAddress']
                                              as String,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    // Timestamp
                                    if (exchangeData['timestamp'] != null) ...[
                                      const Icon(
                                        LucideIcons.calendar,
                                        size: 12,
                                        color: Colors.grey,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _formatExchangeTimestamp(
                                          exchangeData['timestamp'],
                                        ),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                    loading: () => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Container(
                        height: 60,
                        decoration: BoxDecoration(
                          color: AppTheme.elevationColor(context, 1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(
                          child: SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                    ),
                    error: (_, _) => const SizedBox.shrink(),
                  );
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  String _formatExchangeTimestamp(dynamic timestamp) {
    try {
      if (timestamp is Timestamp) {
        return DateFormat.yMMMd().format(timestamp.toDate());
      } else if (timestamp is String) {
        return DateFormat.yMMMd().format(DateTime.parse(timestamp));
      }
    } catch (_) {}
    return '';
  }

  /// Build milestone user cards for a list of user IDs
  Widget _buildMilestoneUserCards(
    BuildContext context,
    WidgetRef ref, {
    required List<String> userIds,
    required String emptyMessage,
  }) {
    if (userIds.isEmpty) {
      return _buildEmptyMilestoneCard(context, emptyMessage, LucideIcons.users);
    }

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppTheme.pageHorizontalPadding,
      ),
      child: Column(
        children: userIds.map((uid) {
          return Consumer(
            builder: (context, ref, _) {
              final profileAsync = ref.watch(userProfileByIdProvider(uid));
              return profileAsync.when(
                data: (profile) {
                  if (profile == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: UserCardView(
                      user: profile,
                      searchQuery: '',
                      onNameTap: () => context.push('/profile/$uid'),
                      onChatTap: () => context.push('/chat/direct/$uid'),
                      isStatic: false,
                    ),
                  );
                },
                loading: () => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      color: AppTheme.elevationColor(context, 1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                ),
                error: (_, _) => const SizedBox.shrink(),
              );
            },
          );
        }).toList(),
      ),
    );
  }

  /// Empty state placeholder for milestones
  Widget _buildEmptyMilestoneCard(
    BuildContext context,
    String message,
    IconData icon, {
    Color? iconColor,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppTheme.pageHorizontalPadding,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: AppTheme.elevationColor(context, 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color:
                iconColor ??
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Shows a bottom sheet with a list of users for a given trust metric.
  void _showVotersSheet(
    BuildContext context,
    WidgetRef ref,
    String title,
    List<String> userIds,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: _buildMilestoneUserCards(
                    context,
                    ref,
                    userIds: userIds,
                    emptyMessage: 'No voters yet',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Trust Slider Vouches Stats section
  Widget _buildTrustSliderVouchesSection(
    BuildContext context,
    WidgetRef ref,
    TrustData trust,
  ) {
    final totalRatings = trust.vouchedByCount;
    final avgRating = trust.averageRating;
    final fullTrustVoterIds = trust.fullTrustVoterIds;
    final noTrustVoterIds = trust.noTrustVoterIds;
    final poctFromVouches = (totalRatings ~/ 10); // +1 PCT per 10 unique
    final nextMilestone = ((totalRatings ~/ 10) + 1) * 10;
    final progressToNext = totalRatings % 10;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPoctSectionHeader(
          context,
          title: 'Continuous Trust Score',
          subtitle: '+1 PCT per 10 unique full-trust voters',
          icon: LucideIcons.barChart3,
        ),
        const SizedBox(height: 12),
        Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AppTheme.pageHorizontalPadding,
          ),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.elevationColor(context, 1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              // Stats row 1: No Trust, Avg Rating, Full Trust
              Row(
                children: [
                  _buildStatBadge(
                    context,
                    label: 'No Trust',
                    value: '${noTrustVoterIds.length}',
                    onTap: () => _showVotersSheet(
                      context,
                      ref,
                      'No Trust Voters',
                      noTrustVoterIds,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildStatBadge(
                    context,
                    label: 'Avg Rating',
                    value: avgRating.toStringAsFixed(1),
                  ),
                  const SizedBox(width: 8),
                  _buildStatBadge(
                    context,
                    label: 'Full Trust',
                    value: '${fullTrustVoterIds.length}',
                    onTap: () => _showVotersSheet(
                      context,
                      ref,
                      'Full Trust Voters',
                      fullTrustVoterIds,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Stats row 2: Total Ratings (full width)
              Row(
                children: [
                  _buildStatBadge(
                    context,
                    label: 'Total Ratings',
                    value: '$totalRatings',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // PCT earned + progress to next
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PCT Earned: $poctFromVouches',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Next award at $nextMilestone ratings ($progressToNext/10)',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.6),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progressToNext / 10.0,
                  minHeight: 4,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Helper: compact stat badge — theme colors only
  Widget _buildStatBadge(
    BuildContext context, {
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    final fg = Theme.of(context).colorScheme.onSurface;
    return Expanded(
      child: Material(
        color: fg.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: fg,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.5),
                    fontSize: 10,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Seniority section — days active with progress to next award
  Widget _buildSenioritySection(BuildContext context, UserPoints userPoints) {
    final daysActive = DateTime.now().difference(userPoints.signupDate).inDays;
    final poctFromSeniority = daysActive ~/ 100; // +1 PCT per 100 days
    final progressDays = daysActive % 100;
    final nextMilestone = ((daysActive ~/ 100) + 1) * 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPoctSectionHeader(
          context,
          title: 'Seniority',
          subtitle: '+1 PCT per 100 active days',
          icon: LucideIcons.clock,
        ),
        const SizedBox(height: 12),
        Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AppTheme.pageHorizontalPadding,
          ),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.elevationColor(context, 1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        LucideIcons.calendarDays,
                        size: 16,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$daysActive Days Active',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '+$poctFromSeniority PCT',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Next award at $nextMilestone days ($progressDays/100)',
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progressDays / 100.0,
                  minHeight: 4,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Penalties section — breakdown of all penalty types
  Widget _buildPenaltiesSection(BuildContext context, TrustData trust) {
    final penalties = <_PenaltyItem>[
      _PenaltyItem(
        label: 'Blocked by Users',
        count: trust.blockedByCount,
        icon: LucideIcons.ban,
      ),
      _PenaltyItem(
        label: 'Flagged Messages',
        count: trust.flaggedMessagesCount,
        icon: LucideIcons.flag,
      ),
      _PenaltyItem(
        label: 'Reported Fraud',
        count: trust.reportedFraudCount,
        icon: LucideIcons.alertTriangle,
      ),

      _PenaltyItem(
        label: 'Event No-Shows',
        count: trust.eventNoShowCount,
        icon: LucideIcons.calendarX,
      ),
      _PenaltyItem(
        label: 'Rejected Family',
        count: trust.rejectedFamilyConnectionsCount,
        icon: LucideIcons.userX,
      ),
      _PenaltyItem(
        label: 'Banned Vouchees',
        count: trust.bannedVoucheeCount,
        icon: LucideIcons.userMinus,
      ),
    ];

    // Total penalty: -10 PCT per 10 of each type
    final totalPenaltyPoCT = penalties.fold<int>(
      0,
      (acc, p) => acc + ((p.count ~/ 10) * 10),
    );

    final hasPenalties = penalties.any((p) => p.count > 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPoctSectionHeader(
          context,
          title: 'Penalties',
          subtitle: '-10 PCT per 10 infractions of each type',
          icon: LucideIcons.alertOctagon,
        ),
        const SizedBox(height: 12),
        Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AppTheme.pageHorizontalPadding,
          ),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.elevationColor(context, 1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: hasPenalties
              ? Column(
                  children: [
                    ...penalties
                        .where((p) => p.count > 0)
                        .map(
                          (p) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Icon(
                                  p.icon,
                                  size: 14,
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.5),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    p.label,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${p.count}',
                                  style: const TextStyle(
                                    color: AppTheme.error,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '-${(p.count ~/ 10) * 10} PCT',
                                  style: TextStyle(
                                    color: AppTheme.error.withValues(
                                      alpha: 0.7,
                                    ),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total Penalty',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '-$totalPenaltyPoCT PCT',
                          style: const TextStyle(
                            color: AppTheme.error,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              : const Row(
                  children: [
                    Icon(
                      LucideIcons.checkCircle,
                      size: 16,
                      color: AppTheme.accent,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'No penalties — clean record!',
                      style: TextStyle(
                        color: AppTheme.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Helper class for penalty breakdown items
class _PenaltyItem {
  final String label;
  final int count;
  final IconData icon;
  const _PenaltyItem({
    required this.label,
    required this.count,
    required this.icon,
  });
}

// [NEW] Monitor for pending requests from this profile
class _PendingRequestMonitor extends ConsumerStatefulWidget {
  final String profileUserId;
  const _PendingRequestMonitor({required this.profileUserId});

  @override
  ConsumerState<_PendingRequestMonitor> createState() =>
      _PendingRequestMonitorState();
}

class _PendingRequestMonitorState
    extends ConsumerState<_PendingRequestMonitor> {
  bool _hasShown = false;

  @override
  Widget build(BuildContext context) {
    if (_hasShown) return const SizedBox.shrink();

    final currentUser = ref.watch(authRepositoryProvider).currentUser;
    if (currentUser == null) return const SizedBox.shrink();

    // Listen to MY incoming requests
    return StreamBuilder<List<RelationshipRequest>>(
      stream: ref
          .watch(relationshipRepositoryProvider)
          .getIncomingRequests(currentUser.uid),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        // Check if there's a pending request from the [profileUserId]
        final requests = snapshot.data!;
        try {
          final pending = requests.firstWhere(
            (r) =>
                r.fromUserId == widget.profileUserId && r.status == 'pending',
          );

          if (!_hasShown) {
            _hasShown = true; // Mark as shown to prevent loop/repeated dialogs
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                showDialog(
                  context: context,
                  barrierDismissible: true, // Allow dismiss
                  builder: (_) => RelationshipResponseModal(
                    request: pending,
                    onAccepted: () {
                      // Refresh data
                      // Refresh data
                      ref.invalidate(
                        userRelationshipsProvider(widget.profileUserId),
                      );
                    },
                  ),
                ).then((_) {
                  // Optionally reset _hasShown if we want to allow showing again on re-visit?
                  // But usually once per session/visit is better.
                  // If dismissed without action, user can find it in their own "Relationships" list (if implemented there)
                  // or refresh this page.
                });
              }
            });
          }
        } catch (_) {
          // No matching request found
        }

        return const SizedBox.shrink();
      },
    );
  }
}
