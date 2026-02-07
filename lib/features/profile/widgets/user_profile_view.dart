import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:diaspora_nearby/features/chat/repository/report_repository.dart'; // [NEW]
import 'package:go_router/go_router.dart';

import 'package:diaspora_nearby/features/profile/models/profile_data.dart';

import 'package:diaspora_nearby/features/community/models/community_data.dart'
    as comm_model;
import 'package:diaspora_nearby/features/shared/widgets/user_card.dart';
import 'package:diaspora_nearby/core/data/countries.dart' as country_data;
import 'package:diaspora_nearby/core/utils/location_utils.dart';
import 'package:diaspora_nearby/theme/app_theme.dart'; // [FIXED]

import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/profile/widgets/relationship_card.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import 'package:diaspora_nearby/features/more/widgets/account_section.dart';

import 'package:diaspora_nearby/features/more/screens/feedback_screen.dart';
import 'package:diaspora_nearby/features/shared/screens/placeholder_screen.dart';
import 'package:diaspora_nearby/features/sharing/services/sharing_service.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/shared/widgets/confetti_overlay.dart';
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';
import 'package:diaspora_nearby/features/trust/models/trust_data.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:diaspora_nearby/core/utils/pwa_utils.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/widgets/relationship_selection_modal.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/relationship_repository.dart';
import 'package:diaspora_nearby/features/profile/models/relationship.dart';
import 'package:diaspora_nearby/features/profile/models/relationship_request.dart';
import 'package:diaspora_nearby/features/community/services/community_service.dart'; // For broadcast
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diaspora_nearby/features/profile/widgets/relationship_response_modal.dart';
import 'package:diaspora_nearby/features/dsp/services/exploration_registry.dart';
import 'package:diaspora_nearby/features/trust/widgets/trust_slider_widget.dart';
import 'package:diaspora_nearby/features/trust/widgets/profile_verification_modal.dart';
import 'package:diaspora_nearby/features/trust/widgets/verification_alert_modal.dart';
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart';
import 'package:diaspora_nearby/features/profile/widgets/profile_qr_code_dialog.dart';

class UserProfileView extends ConsumerWidget {
  final ProfileData profile;
  final bool isSelf;
  final bool isEnforced;
  final VoidCallback onEdit;

  final double? distanceKm;
  final VoidCallback onRefresh;
  final String? src;

  Widget _buildFlagWarning() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.error.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 16, color: AppTheme.error),
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


    this.distanceKm,
    required this.onRefresh,
    this.src,
  });

  Future<void> _handleVerifyUser(BuildContext context, WidgetRef ref) async {
    final currentUserId = ref.read(authRepositoryProvider).currentUser?.uid;
    if (currentUserId == null) return;

    // 1. Check existing relationship
    final relRepo = ref.read(relationshipRepositoryProvider);
    final rel = await relRepo.getRelationship(
      userId: currentUserId,
      relatedUserId: profile.uid!,
    );

    if (rel != null && rel.status == 'active') {
      // Deny verification for conflict of interest
      if (context.mounted) {
        VerificationAlertModal.show(
          context,
          type: VerificationAlertType.conflict,
          title: 'Conflict of Interest',
          message:
              'You cannot verify a relative. Verification must be performed by independent community members.',
        );
      }
      return;
    }

    // 2. Check eligibility (already verified or daily limit)
    final trustService = ref.read(trustServiceProvider);
    final eligibilityError = await trustService.checkVerificationEligibility(
        currentUserId, profile.uid!);
    if (eligibilityError != null) {
      if (context.mounted) {
        VerificationAlertType type = VerificationAlertType.error;
        if (eligibilityError.contains('already verified')) {
          type = VerificationAlertType.alreadyVerified;
        } else if (eligibilityError.contains('limit reached')) {
          type = VerificationAlertType.limit;
        } else if (eligibilityError.contains('complete your profile') ||
            eligibilityError.contains('Verified User') ||
            eligibilityError.contains('acquired at least')) {
          type = VerificationAlertType.requirements;
        }

        VerificationAlertModal.show(
          context,
          type: type,
          title: type == VerificationAlertType.requirements
              ? 'Requirements Not Met'
              : 'Action Restricted',
          message: eligibilityError,
        );
      }
      return;
    }

    // 3. Show Relationship Selection
    if (context.mounted) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (modalContext) => RelationshipSelectionModal(
          otherUserId: profile.uid!,
          otherUserName: '${profile.firstName} ${profile.lastName}',
          includeFriend: true,
          onSelected: (type) async {
            Navigator.pop(modalContext);

            final socialTypes = [
              'Colleague',
              'Business Partner',
              'Community Member',
              'Friend'
            ];
            if (socialTypes.contains(type)) {
              // Allow verification
              if (context.mounted) {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (context) => ProfileVerificationModal(
                    targetUser: profile,
                    currentUserId: currentUserId,
                  ),
                );
              }
            } else {
              // It's a relative, send request and deny verification
              if (context.mounted) {
                VerificationAlertModal.show(
                  context,
                  type: VerificationAlertType.conflict,
                  title: 'Verification Blocked',
                  message:
                      'Relationship request sent. You cannot verify relatives to ensure unbiased community trust.',
                );
              }
              await _sendRelationshipRequest(ref, type);
            }
          },
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flaggedFieldsAsync =
        ref.watch(flaggedFieldsProvider(profile.uid ?? ''));
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
          if (isSelf)
            IconButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => ProfileQRCodeDialog(profile: profile),
                );
              },
              icon: const Icon(LucideIcons.qrCode, size: 20),
              tooltip: 'Identity QR',
            ),
          if (!isSelf && profile.uid != null)
             PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'block') {
                  _handleBlockUser(context, ref, profile);
                } else if (value == 'report') {
                  _handleReportUser(context, ref, profile);
                } else if (value == 'verify') {
                  _handleVerifyUser(context, ref);
                }
              },
              itemBuilder: (BuildContext context) {
                return [
                  const PopupMenuItem<String>(
                    value: 'verify',
                    child: Row(
                      children: [
                        Icon(LucideIcons.shieldCheck, size: 18, color: AppTheme.accent),
                        SizedBox(width: 8),
                        Text('Verify User', style: TextStyle(color: AppTheme.accent)),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'report',
                    child: Row(
                      children: [
                        Icon(LucideIcons.flag, size: 18, color: AppTheme.error),
                        SizedBox(width: 8),
                        Text('Report User', style: TextStyle(color: AppTheme.error)),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'block',
                    child: Row(
                      children: [
                        Icon(LucideIcons.ban, size: 18),
                        SizedBox(width: 8),
                        Text('Block User'),
                      ],
                    ),
                  ),
                ];
              },
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
                  // User Card (Safe)
                  UserCardView(
                    key: const ValueKey('view_UserCard'),
                    user: profile,
                    flaggedFields: flaggedFields,
                    searchQuery: '',
                    onNameTap: () {},
                    onChatTap: isSelf
                        ? null
                        : () => context.push('/chat/direct/${profile.uid}'),
                    isStatic: true, // We are in View mode
                    distanceKm: distanceKm,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppTheme.standardBorderRadius),
                    ),
                  ),

                  // const SizedBox(height: 16), // REMOVED GAP
                  
                  // [NEW] Public DSP Balance Card (Visible to others)
                  if (!isSelf && profile.uid != null) ...[
                    Consumer(
                        builder: (context, ref, child) {
                          final pointsAsync =
                              ref.watch(userPointsProvider(profile.uid!));
                          final trustAsync =
                              ref.watch(userTrustProvider(profile.uid!));

                          return pointsAsync.when(
                            data: (userPoints) {
                              final points = userPoints?.availablePoints ?? 0;
                              final formattedPoints =
                                  NumberFormat('#,###').format(points);
                              
                              // Get trust score (default to 0 if loading/error)
                              final double trustScore = trustAsync.value?.trustScore ?? 0;
                              final double progress = trustScore / 100.0;

                              // Determine Color based on Trust Score
                              Color trustColor;
                              if (trustScore <= 20) {
                                trustColor = AppTheme.error; // Red (0-20)
                              } else if (trustScore <= 40) {
                                trustColor = Colors.deepOrange; // Deep Orange (21-40)
                              } else if (trustScore <= 60) {
                                trustColor = Colors.amber; // Amber (41-60)
                              } else if (trustScore <= 80) {
                                trustColor = Colors.lightGreen; // Light Green (61-80)
                              } else {
                                trustColor = AppTheme.accent; // Green/Accent (81-100)
                              }

                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppTheme.pageHorizontalPadding,
                                  vertical: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: trustColor.withOpacity(0.1),
                                  borderRadius: const BorderRadius.vertical(
                                    bottom: Radius.circular(AppTheme.standardBorderRadius),
                                  ),
                                  // Border removed as per request
                                ),
                                  child: Row(
                                    children: [
                                      // PoCT Score Graph
                                      SizedBox(
                                        height: 52,
                                        width: 52,
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            // Background Track
                                            CircularProgressIndicator(
                                              value: 1.0,
                                              strokeWidth: 4,
                                              valueColor: AlwaysStoppedAnimation<Color>(
                                                trustColor.withOpacity(0.2),
                                              ),
                                            ),
                                            // Progress Indicator
                                            CircularProgressIndicator(
                                              value: progress,
                                              strokeWidth: 4,
                                              valueColor: AlwaysStoppedAnimation<Color>(
                                                trustColor,
                                              ),
                                              strokeCap: StrokeCap.round,
                                            ),
                                            // Text Percentage
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
                                      // Labels Grid
                                      Expanded(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // Top Row: Community Status & Balance
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
                                                    color: trustColor.withOpacity(0.8),
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            // Middle Row: PoCT Score & Balance Amount
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  'PoCT Score',
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
                                            // Bottom Row: Days Active
                                            Builder(builder: (context) {
                                              final signupDate =
                                                  userPoints?.signupDate ??
                                                      DateTime.now();
                                              final daysActive = DateTime.now()
                                                  .difference(signupDate)
                                                  .inDays;
                                              return Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text(
                                                    'Active: $daysActive days',
                                                    style: TextStyle(
                                                      color: trustColor
                                                          .withOpacity(0.8),
                                                      fontSize: 11,
                                                      fontStyle: FontStyle.italic,
                                                    ),
                                                  ),
                                                  const SizedBox(),
                                                ],
                                              );
                                            }),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                              );
                            },
                            loading: () => const SizedBox.shrink(),
                            error: (_, __) => const SizedBox.shrink(),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                  ],

                  // Diaspora Economy Section (Only for Self)
                  // Diaspora Economy Section (Only for Self)
                  if (isSelf) ...[
                    _safelyBuild(
                      () => _buildSectionHeader(
                        context,
                        'Diaspora Economy Ecosystem',
                        icon: LucideIcons.wallet,
                      ),
                      label: 'EconomyHeader',
                    ),

                    _safelyBuild(
                      () => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. DSP Points
                          _buildEconomyCard(
                            context,
                            icon: LucideIcons.coins,
                            title: 'Diaspora Social Points - DSP',
                            description: 'Earn & convert to tokens',
                            color: AppTheme.accent,
                            onTap: () => context.push('/dsp/points'),
                          ),

                          const SizedBox(height: 12),

                          // 2. Diaspora Token - $DSP
                          _buildEconomyCard(
                            context,
                            icon: LucideIcons.coins,
                            imagePath: 'assets/icons/logo-original.png',
                            imageColor: Colors.orange,
                            title: 'Diaspora Token - \$DSP',
                            description: 'Hold Invest Spend Swap or Trade',
                            color: AppTheme.accent,
                            isComingSoon: false,
                            onTap: () {
                              _trackExploration(
                                context,
                                ref,
                                ExplorationAction.economyCrypto,
                              );
                              context.push('/dsp/crypto');
                            },
                          ),
                          const SizedBox(height: 12),

                          // 3. Bereavement (Moved Down)
                          _buildEconomyCard(
                            context,
                            icon: LucideIcons.heart,
                            title: 'Bereavement Community Fund',
                            description: 'Repatriation Travel & Funeral Support',
                            color: AppTheme.accent,
                            isComingSoon: false,
                            onTap: () {
                              _trackExploration(
                                context,
                                ref,
                                ExplorationAction.economyBereavement,
                              );
                              context.push('/dsp/bereavement');
                            },
                          ),
                          const SizedBox(height: 12),

                          // 4. Remittances
                          _buildEconomyCard(
                            context,
                            icon: LucideIcons.send,
                            title: 'International Remittances',
                            description:
                                'Send money to ${profile.homeCountry ?? 'home'}',
                            color: AppTheme.accent,
                            isComingSoon: true,
                            onTap: () {
                              _trackExploration(
                                context,
                                ref,
                                ExplorationAction.economyRemittances,
                              );
                              context.push('/dsp/remittances');
                            },
                          ),
                          const SizedBox(height: 12),

                          // 5. Airline Portal
                          _buildEconomyCard(
                            context,
                            icon: LucideIcons.plane,
                            title: 'International Air Flight Portal',
                            description: 'Discounted flights',
                            color: AppTheme.accent,
                            isComingSoon: true,
                            onTap: () {
                              _trackExploration(
                                context,
                                ref,
                                ExplorationAction.economyAirline,
                              );
                              context.push('/dsp/airline');
                            },
                          ),
                          const SizedBox(height: 12),

                          // 6. DFDI
                          _buildEconomyCard(
                            context,
                            icon: LucideIcons.trendingUp,
                            title: 'Diaspora Foreign Direct Investments - DFDI',
                            description:
                                'Invest with Community & Community Invest in You',
                            color: AppTheme.accent,
                            isComingSoon: true,
                            onTap: () {
                              _trackExploration(
                                context,
                                ref,
                                ExplorationAction.economyDfdi,
                              );
                              context.push('/dsp/dfdi');
                            },
                          ),
                        ],
                      ),
                      label: 'DiasporaEconomyCards',
                    ),
                    const SizedBox(height: 16),
                  ],

                  const SizedBox(height: 16),

                  // [NEW] In-Person QR Connection (Priority)
                  if (profile.firstQrConnection != null)
                    _safelyBuild(
                      () => _buildQRConnectionSection(context, ref),
                      label: 'QRConnection',
                    ),

                  const SizedBox(height: 16),

                  // [NEW] Trust & Reputation Section (Everyone, detailed for others)
                  _safelyBuild(
                    () => _buildTrustSection(context, ref),
                    label: 'TrustSection',
                  ),

                  // Residency & Location
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

                  // Business Profile
                  if (profile.businessProfile?.isBusinessVerified == true)
                    _safelyBuild(
                      () =>
                          _buildBusinessCard(context, profile.businessProfile!),
                      label: 'BusinessCard',
                    ),

                  // [NEW] Related to
                  _safelyBuild(
                    () => _buildRelationshipsSection(context, ref),
                    label: 'Relationships',
                  ),
                  const SizedBox(height: 16),

                  // Bio
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
                          if (flaggedFields.contains('Bio')) _buildFlagWarning(),
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

                  // Professional Info
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
                          if (flaggedFields.contains('Occupation')) _buildFlagWarning(),
                          _buildSectionContainer(
                            context,
                            child: _buildProfessionalDisplay(context),
                          ),
                        ],
                      ),
                      label: 'Profession',
                    ),

                  // Languages
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

                  // Education
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
                          if (flaggedFields.contains('Education')) _buildFlagWarning(),
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

                  // Interests
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

                  // Community Support
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

                  // Availability
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

                  // Meeting Preferences
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

                  // Social Media
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

                  const SizedBox(height: 8),

                  if (isSelf) ...[
                    const SizedBox(height: 16),

                    // --- Consolidated More Menu Content (for Self) ---

                    // Web App (PWA)
                    if (kIsWeb) ...[
                      _buildSectionHeader(
                        context, 
                        'WEB APP',
                        icon: LucideIcons.monitor,
                      ),
                      _buildSectionContainer(
                        context,
                        child: _buildMenuItem(
                          context,
                          icon: LucideIcons.download,
                          iconColor: Theme.of(context).colorScheme.primary,
                          title: 'Install as App',
                          subtitle: 'Add Diaspora to your home screen',
                          onTap: () async {
                            final result = await PwaUtils.promptInstall();
                            if (!result) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Installation not supported or already installed.',
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Quick Actions
                    _buildSectionHeader(
                      context, 
                      'QUICK ACTIONS',
                      icon: LucideIcons.zap,
                    ),
                    _buildSectionContainer(
                      context,
                      child: Column(
                        children: [
                          _buildMenuItem(
                            context,
                            icon: LucideIcons.share2,
                            iconColor: const Color(0xFF25D366),
                            title: 'Invite family and friends',
                            subtitle: 'Share the app with others',
                            onTap: () {
                              _trackExploration(
                                context,
                                ref,
                                ExplorationAction.profileInvite,
                              );
                              // [NEW] Track Engagement Reward
                              ref
                                  .read(pointsServiceProvider)
                                  .trackExternalShare(
                                    profile.uid!,
                                    'app_invite',
                                  );

                              SharingService.instance.shareApp();
                            },
                          ),
                          _buildMenuItem(
                            context,
                            icon: LucideIcons.messageSquare,
                            iconColor: Colors.indigo,
                            title: 'Send Feedback',
                            subtitle: 'Help us improve the app',
                            onTap: () {
                              _trackExploration(
                                context,
                                ref,
                                ExplorationAction.profileFeedback,
                              );
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const FeedbackScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Support
                    _buildSectionHeader(
                      context, 
                      'SUPPORT',
                      icon: LucideIcons.lifeBuoy,
                    ),
                    _buildSectionContainer(
                      context,
                      child: Column(
                        children: [
                          _buildMenuItem(
                            context,
                            icon: LucideIcons.star,
                            iconColor: Colors.orange,
                            title: 'Rate App',
                            subtitle: 'Share your experience',
                            onTap: () {
                              _trackExploration(
                                context,
                                ref,
                                ExplorationAction.profileRateApp,
                              );
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const PlaceholderScreen(
                                    title: 'Rate App',
                                    icon: LucideIcons.star,
                                    message:
                                        'Enjoying the app? Please rate us on the app store!\n\n(Coming Soon)',
                                  ),
                                ),
                              );
                            },
                          ),
                          _buildMenuItem(
                            context,
                            icon: LucideIcons.helpCircle,
                            iconColor: Colors.cyan,
                            title: 'Help Center',
                            subtitle: 'Get answers',
                            onTap: () {
                              _trackExploration(
                                context,
                                ref,
                                ExplorationAction.profileHelpCenter,
                              );
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const PlaceholderScreen(
                                    title: 'Help Center',
                                    icon: LucideIcons.helpCircle,
                                    message:
                                        'Find answers to common questions.\n\n(Coming Soon)',
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),


                    // Account Settings
                    _buildSectionHeader(
                      context, 
                      'ACCOUNT SETTINGS',
                      icon: LucideIcons.settings,
                    ),
                    AccountSection(userProfile: profile),
                  ],
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
      padding: padding ?? const EdgeInsets.all(AppTheme.sectionHorizontalPadding), // 8px padding
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppTheme.standardBorderRadius), // 16px radius
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
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
        Row(
          children: [
            Icon(
              LucideIcons.clock,
              size: 16,
              color: Theme.of(context).primaryColor,
            ),
            const SizedBox(width: 8),
            Text(
              isSinceBirth ? 'Birth' : '$yearText$durationText',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ],
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
        const SizedBox(height: 4),
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

              return ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.mapPin, size: 16),
                    if (flag != null) ...[
                      const SizedBox(width: 8),
                      Text(flag, style: const TextStyle(fontSize: 18)),
                    ],
                  ],
                ),
                title: Text(formattedAddress),
                subtitle: Text(
                  'Until ${() {
                    try {
                      final dt = DateTime.parse(p.until);
                      return dt.year.toString();
                    } catch (_) {
                      return p.until;
                    }
                  }()}',
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
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: Theme.of(context).brightness == Brightness.dark
              ? [
                  Colors.blue.shade900.withOpacity(0.2),
                  Colors.indigo.shade900.withOpacity(0.2),
                ]
              : [Colors.blue.shade50, Colors.indigo.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
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
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
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

  // [NEW] Trust Section
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
              color: AppTheme.accent.withOpacity(0.05),
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
                      child: const Icon(LucideIcons.check,
                          size: 10, color: Colors.white),
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
                ref.watch(userProfileByIdProvider(info.otherUid)).when(
                      data: (otherProfile) {
                        if (otherProfile == null) return const SizedBox.shrink();
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
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                if (info.locationAddress != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.mapPin,
                            size: 14, color: Colors.grey),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Connected in ${formatFullAddress(info.locationAddress!)}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
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
                        const Icon(LucideIcons.calendar,
                            size: 14, color: Colors.grey),
                        const SizedBox(width: 6),
                        Text(
                          DateFormat.yMMMd().add_jm().format(
                                DateTime.parse(info.timestamp),
                              ),
                          style:
                              const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                    const Text(
                      '10,000 DSP EARNED',
                      style: TextStyle(
                        color: Color(0xFFFFD700), // Gold
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

  Widget _buildTrustSection(BuildContext context, WidgetRef ref) {
    // If self, maybe show differently or linked to "Improve Score"
    // For now, consistent view.

    final trustAsync = ref.watch(userTrustProvider(profile.uid!));

    return trustAsync.when(
      data: (trust) {
        if (trust == null) return const SizedBox.shrink(); // No score yet

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              context, 
              'Community Trust',
              icon: LucideIcons.shieldCheck,
            ),
            _buildSectionContainer(
              context,
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        LucideIcons.shieldCheck,
                        color: _getLevelColor(context, trust.level),
                        size: 32,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Trust Score: ${trust.trustScore.round()}/100',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              trust.level.displayName,
                              style: TextStyle(
                                color: _getLevelColor(context, trust.level),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isSelf)
                        // Show "Vouches: X" in sage green, aligned with trust score
                        Text(
                          '${trust.vouchCount} Vouches',
                          style: const TextStyle(
                            color: Color(0xFF8FBC8F), // Sage green text
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                       if (!isSelf)
                        TextButton.icon(
                          onPressed: () => _handleVouch(context, ref),
                          icon: const Icon(
                            LucideIcons.thumbsUp, 
                            size: 14, 
                            color: Color(0xFF8FBC8F),
                          ),
                          label: const Text(
                            'Vouch',
                            style: TextStyle(
                              color: Color(0xFF8FBC8F),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // [NEW] Trust Slider for Peer Rating
                  if (!isSelf)
                    FutureBuilder<double?>(
                      future: ref
                          .read(trustServiceProvider)
                          .getMyRating(ref.read(authRepositoryProvider).currentUser!.uid, profile.uid!),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: LinearProgressIndicator(minHeight: 2));
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: TrustSliderWidget(
                            targetUserId: profile.uid!,
                            currentUserId: ref.read(authRepositoryProvider).currentUser!.uid,
                            initialRating: snapshot.data,
                          ),
                        );
                      },
                    ),

                  // Breakdown
                  _buildTrustBar(context, 'Identity', trust.identityScore, 20),
                  const SizedBox(height: 8),
                  _buildTrustBar(context, 'Activity', trust.activityScore, 20),
                  const SizedBox(height: 8),
                  _buildTrustBar(context, 'Reliability', trust.reliabilityScore, 20),
                  const SizedBox(height: 8),
                  _buildTrustBar(context, 'Helpfulness', trust.helpfulnessScore, 20),
                  const SizedBox(height: 8),
                  _buildTrustBar(
                    context,
                    'Reputation',
                    trust.reputationScore,
                    20,
                  ),

                  if (isSelf) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Complete your profile and engage with the community to increase your score!',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildTrustBar(
    BuildContext context,
    String label,
    num current,
    num max,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            Text(
              '${current.round()}/${max.round()}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: current / max,
          backgroundColor: Colors.grey.withOpacity(0.2),
          color: _getScoreColor(current, max),
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }

  Color _getScoreColor(num current, num max) {
    double pct = current / max;
    if (pct <= 0.2) return AppTheme.error;
    if (pct <= 0.4) return Colors.deepOrange;
    if (pct <= 0.6) return Colors.amber;
    if (pct <= 0.8) return Colors.lightGreen;
    return AppTheme.accent;
  }

  Color _getLevelColor(BuildContext context, TrustLevel level) {
    switch (level) {
      case TrustLevel.lowTrust:
        return AppTheme.error;
      case TrustLevel.basicTrust:
        return Colors.deepOrange;
      case TrustLevel.mediumTrust:
        return Colors.amber;
      case TrustLevel.standardTrust:
        return Colors.lightGreen;
      case TrustLevel.highTrust:
        return AppTheme.accent;
    }
    return AppTheme.error;
  }

  Future<void> _sendRelationshipRequest(WidgetRef ref, String type) async {
    final currentUserId = ref.read(authRepositoryProvider).currentUser?.uid;
    if (currentUserId == null) return;
    
    final relRepo = ref.read(relationshipRepositoryProvider);
    final profileRepo = ref.read(profileRepositoryProvider);
    
    final currentUserProfile = await profileRepo.getUserProfile(currentUserId);
    String flag = '🌍';
    if (currentUserProfile?.homeCountryCode != null) {
      try {
        int flagOffset = 0x1F1E6;
        int asciiOffset = 0x41;
        String country = currentUserProfile!.homeCountryCode!.toUpperCase();
        int firstChar = country.codeUnitAt(0) - asciiOffset + flagOffset;
        int secondChar = country.codeUnitAt(1) - asciiOffset + flagOffset;
        flag = String.fromCharCode(firstChar) + String.fromCharCode(secondChar);
      } catch (e) {}
    }

    await relRepo.sendRelationshipRequest(
      fromUserId: currentUserId,
      fromUserName: '${currentUserProfile?.firstName ?? ''} ${currentUserProfile?.lastName ?? ''}'.trim(),
      fromUserFlag: flag,
      toUserId: profile.uid!,
      toUserName: '${profile.firstName} ${profile.lastName}',
      relationshipType: type,
    );
  }

  void _handleVouch(BuildContext context, WidgetRef ref) async {
    final currentUserId = ref.read(authRepositoryProvider).currentUser?.uid;
    if (currentUserId == null) return;

    // 1. Check existing relationship
    final relRepo = ref.read(relationshipRepositoryProvider);
    final rel = await relRepo.getRelationship(
      userId: currentUserId,
      relatedUserId: profile.uid!,
    );

    if (rel != null && rel.status == 'active') {
       // Deny vouch for conflict of interest
       if (context.mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(
              content: Text('You cannot vouch for a relative (Conflict of Interest).'),
              backgroundColor: Colors.orange,
           ),
         );
       }
       return;
    }

    // 2. Check if already vouched
    final trustService = ref.read(trustServiceProvider);
    final eligibilityError = await trustService.checkVouchEligibility(currentUserId, profile.uid!);
    if (eligibilityError != null) {
       if (context.mounted) {
          if (eligibilityError.contains('complete your profile') ||
              eligibilityError.contains('PoCT score') ||
              eligibilityError.contains('acquired at least')) {
            VerificationAlertModal.show(
              context,
              type: VerificationAlertType.requirements,
              title: 'Requirements Not Met',
              message: eligibilityError,
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(eligibilityError)),
            );
          }
       }
       return;
    }

    // 3. Show Relationship Selection
    if (context.mounted) {
       showModalBottomSheet(
         context: context,
         isScrollControlled: true,
         builder: (modalContext) => RelationshipSelectionModal(
           otherUserId: profile.uid!,
           otherUserName: '${profile.firstName} ${profile.lastName}',
           includeFriend: true,
           onSelected: (type) async {
              Navigator.pop(modalContext);
              
              final socialTypes = ['Colleague', 'Business Partner', 'Community Member', 'Friend'];
              if (socialTypes.contains(type)) {
                 // Allow vouching
                 if (context.mounted) {
                    _showVouchConfirmationDialog(context, ref, type);
                 }
              } else {
                 // It's a relative, send request and deny vouching
                 if (context.mounted) {
                   ScaffoldMessenger.of(context).showSnackBar(
                     const SnackBar(
                       content: Text('Relationship request sent. Vouching blocked (Conflict of Interest).'),
                       backgroundColor: Colors.orange,
                     ),
                   );
                 }
                 await _sendRelationshipRequest(ref, type);
              }
           },
         ),
       );
    }
  }

  void _showVouchConfirmationDialog(BuildContext context, WidgetRef ref, String relationship) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Vouch'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Relationship: $relationship'),
            const SizedBox(height: 12),
            const Text(
              'By vouching, you stake a small portion of your reputation on this user\'s trustworthiness.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              _submitVouch(context, ref, relationship);
            },
            child: const Text('Vouch'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitVouch(BuildContext context, WidgetRef ref, String relationship) async {
    try {
      final currentUser = ref.read(authRepositoryProvider).currentUser;
      if (currentUser != null) {
        await ref.read(trustServiceProvider).vouchForUser(
          fromUserId: currentUser.uid,
          toUserId: profile.uid!,
          relationship: relationship,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Vouch submitted successfully!')),
          );
          // Trigger refresh of trust data
          ref.refresh(userTrustProvider(profile.uid!));
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
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
      backgroundColor: isOutline ? Colors.transparent : null,
      side: isOutline
          ? BorderSide(color: Theme.of(context).dividerColor)
          : null,
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







  Widget _buildEconomyCard(
    BuildContext context, {
    required IconData icon,
    String? imagePath, // [NEW] Optional image
    Color? imageColor, // [NEW] Optional color filter for image
    required String title,
    required String description,
    required Color color,
    required VoidCallback onTap,
    bool isComingSoon = false,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: Theme.of(context).brightness == Brightness.dark
                ? [color.withOpacity(0.15), color.withOpacity(0.05)]
                : [color.withOpacity(0.1), color.withOpacity(0.05)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: imagePath != null
                      ? const EdgeInsets.all(10)
                      : const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: imagePath != null
                        ? (imageColor != null ? imageColor.withOpacity(0.2) : Colors.transparent)
                        : color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: imagePath != null
                      ? Image.asset(
                          imagePath,
                          width: 24,
                          height: 24,
                          fit: BoxFit.contain,
                          color: imageColor,
                        )
                      : Icon(icon, color: color, size: 24),
                ),
                if (isComingSoon)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey.shade800
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      'Coming Soon',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                  )
                else if (trailing != null)
                  trailing,
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).hintColor,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
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
            Icon(
              icon,
              size: 16,
              color: Theme.of(context).hintColor,
            ),
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

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.textTheme.bodySmall?.color?.withOpacity(
                          0.6,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              LucideIcons.chevronRight,
              size: 14,
              color: theme.iconTheme.color?.withOpacity(0.3),
            ),
          ],
        ),
      ),
    );
  }


  Future<void> _trackExploration(BuildContext context, WidgetRef ref, String actionId) async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user != null) {
      final rewarded = await ref
          .read(pointsServiceProvider)
          .trackExplorationReward(user.uid, actionId);
      if (rewarded) {
        confettiOverlayKey.currentState?.play();
        if (context.mounted) {
          showExplorationRewardToast(context);
        }
      }
    }
  }



  // [NEW] Relationship Section Builder
  Widget _buildRelationshipsSection(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, 'Related to'),

        // Incoming Requests (Self Only)
        if (isSelf) _buildIncomingRequests(context, ref),

        _buildSectionContainer(
          context,
          padding: const EdgeInsets.all(AppTheme.pageHorizontalPadding),
          child: ref
              .watch(userRelationshipsProvider(profile.uid!))
              .when(
                data: (relationships) {
                  // [NEW] Filtered Logic: Only display the 12 'Relative' types in this section.
                  // Types: Immediate (4) + Close (4) + Extended (4)
                  final relativeTypes = const {
                    'Wife', 'Husband', 'Daughter', 'Son',
                    'Mother', 'Father', 'Sister', 'Brother',
                    'Aunt', 'Uncle', 'Niece', 'Cousin'
                  };
                  
                  final activeRelationships = relationships
                      .where((r) => relativeTypes.contains(r.type))
                      .toList();
                      
                  if (activeRelationships.isEmpty) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8.0),
                      child: const Text(
                        'No active relatives.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    );
                  }
                  return Column(
                    children: activeRelationships
                        .map(
                          (rel) => RelationshipCard(
                            relationship: rel,
                            enableActions: isSelf,
                          ),
                        )
                        .toList(),
                  );
                  /* 
              if (relationships.isEmpty) {
                return const Text('No relationships added yet.', style: TextStyle(color: Colors.grey));
              }
              return Column(
                children: relationships.map((rel) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: Colors.pink.shade50,
                    child: Text(rel.flag ?? 'â¤ï¸', style: const TextStyle(fontSize: 16)), // Use flag or heart
                  ),
                  title: Text(rel.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(rel.type),
                  onTap: () {
                     // Open Profile on tap
                     context.push('/profile/${rel.id}');
                  },
                  trailing: IconButton(
                    icon: const Icon(LucideIcons.moreHorizontal),
                    onPressed: () => _showRelationshipActionDialog(context, ref, rel),
                  ),
                )).toList(),
              );
             */
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

  // [NEW] Incoming Requests Widget
  Widget _buildIncomingRequests(BuildContext context, WidgetRef ref) {
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
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pending Requests (${snapshot.data!.length})',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade900,
                ),
              ),
              const SizedBox(height: 8),
              ...snapshot.data!.map(
                (req) => Card(
                  elevation: 0,
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Text(
                              req.fromUserFlag,
                              style: const TextStyle(fontSize: 20),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: RichText(
                                text: TextSpan(
                                  text: '${req.fromUserName} ',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                  children: [
                                    const TextSpan(
                                      text: 'wants to add you as ',
                                      style: TextStyle(
                                        fontWeight: FontWeight.normal,
                                      ),
                                    ),
                                    TextSpan(
                                      text: req.relationshipType,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  _handleRejectRequest(context, ref, req),
                              child: const Text(
                                'Reject',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () =>
                                  _handleAcceptRequest(context, ref, req),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 0,
                                ),
                                minimumSize: const Size(0, 32),
                              ),
                              child: const Text('Accept'),
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
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: possibleTypes
                        .map(
                          (type) => RadioListTile<String>(
                            title: Text(type),
                            value: type,
                            groupValue: tempSelected,
                            onChanged: (val) =>
                                setState(() => tempSelected = val),
                          ),
                        )
                        .toList(),
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
        String myFlag = '❤️';
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
    // Confirm rejection (warn about PoCT penalty if desired, or simpler)
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
        final pointsService = ref.read(
          pointsServiceProvider,
        ); // [FIX] Use provider
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
        });
  }

  // [NEW] Relationship Action Dialog
  void _showRelationshipActionDialog(
    BuildContext context,
    WidgetRef ref,
    Relationship rel,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(rel.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Relationship: ${rel.type}'),
            const SizedBox(height: 16),
            const Text(
              'What would you like to do?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.push('/chat/direct/${rel.id}'); // Or view profile
            },
            child: const Text('Chat'),
          ),

          TextButton.icon(
            icon: const Icon(LucideIcons.megaphone, size: 16),
            label: const Text('Announce Passing'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              _showBereavementBroadcastConfirmation(context, ref, rel);
            },
          ),

          // Delete option
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.grey),
            onPressed: () async {
              Navigator.pop(context);
              final confirm = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Remove Relationship?'),
                  content: Text('Remove ${rel.name} as ${rel.type}?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Remove'),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                await ref
                    .read(relationshipRepositoryProvider)
                    .deleteRelationship(
                      userId: profile.uid!,
                      relatedUserId: rel.id,
                    );
              }
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _showBereavementBroadcastConfirmation(
    BuildContext context,
    WidgetRef ref,
    Relationship rel,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Broadcast Announcement?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This will send a bereavement announcement to your:\n\u2022 Home Country Community\n\u2022 Host City Community\n\nThis action is for community support.',
            ),
            const SizedBox(height: 16),
            Text(
              'Subject: Passing of ${rel.type} ${rel.name}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            icon: const Icon(LucideIcons.send),
            label: const Text('Broadcast'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(context);

              // Trigger broadcast
              try {
                final communityService = ref.read(communityServiceProvider);

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Broadcasting announcement...')),
                );

                await communityService.broadcastBereavementAnnouncement(
                  userId: profile.uid,
                  userName: profile.fullName,
                  deceasedName: rel.name,
                  relationship: rel.type,
                  homeCountryCode: profile.homeCountryCode ?? '',
                  hostCountryCode: profile.hostCountryCode,
                  hostCity: profile.hostLocation.city,
                );

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Bereavement announcement sent to communities.',
                      ),
                    ),
                  );
                }
              } catch (e) {
                debugPrint('Broadcast failed: $e');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Broadcast failed: $e')),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  void _handleBlockUser(BuildContext context, WidgetRef ref, ProfileData profile) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Block User?'),
        content: Text('Are you sure you want to block ${profile.fullName}? They will not be able to message you or see your posts.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context); // Close dialog
              
              final currentUserId = ref.read(authRepositoryProvider).currentUser?.uid;
              if (currentUserId == null) return;

              try {
                await ref.read(reportRepositoryProvider).blockUser(currentUserId, profile.uid!);
                
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('User blocked')),
                  );
                  Navigator.pop(context); // Go back to previous screen
                }
              } catch (e) {
                // Handle error
              }
            },
            child: const Text('Block', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _handleReportUser(BuildContext context, WidgetRef ref, ProfileData profile) {
    final reasons = [
      'Fake Account',
      'Harassment or Bullying',
      'Inappropriate Content',
      'Spam',
      'Other',
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report User'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: reasons.length,
            itemBuilder: (context, index) {
              return ListTile(
                title: Text(reasons[index]),
                onTap: () async {
                  Navigator.pop(context); 
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Submitting report...')),
                  );

                  try {
                    final currentUserId = ref.read(authRepositoryProvider).currentUser?.uid;
                    if (currentUserId == null) return;
                    
                    await ref.read(reportRepositoryProvider).reportUser(
                      reporterId: currentUserId,
                      reportedUserId: profile.uid!,
                      reason: reasons[index],
                    );

                    if (context.mounted) {
                      showExplorationRewardToast(
                        context,
                        message: 'Report submitted. Thank you!',
                        points: 0,
                      );
                    }
                  } catch (e) {
                    // Handle error
                  }
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ],
      ),
    );
  }
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
                      ref.refresh(
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
