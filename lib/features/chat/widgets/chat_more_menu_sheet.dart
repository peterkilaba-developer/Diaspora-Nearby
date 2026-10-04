import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/chat/models/chat.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/profile/models/relationship.dart';
import 'package:diaspora_nearby/features/profile/models/relationship_request.dart';
import 'package:diaspora_nearby/features/governance/models/governance_unit.dart';
import 'package:diaspora_nearby/features/community/models/community_data.dart';
import 'package:diaspora_nearby/features/shared/widgets/bottom_sheet_item.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/widgets/profile_qr_code_dialog.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:go_router/go_router.dart';

class ChatMoreMenuSheet extends ConsumerWidget {
  final Chat chat;
  final String displayName;
  final Relationship? existingRelationship;
  final RelationshipRequest? pendingSentRequest;
  final RelationshipRequest? pendingIncomingRequest;
  final Community? community;
  final GovernanceUnit? governanceUnit;
  final bool hasAnyProfileField;
  final bool hasVerifiedTarget;

  // Callbacks for ChatScreen logic
  final VoidCallback onAddRelationship;
  final VoidCallback onVerifyUser;
  final VoidCallback onVouchUser;
  final VoidCallback onClearChat;
  final VoidCallback onDeleteChat;
  final VoidCallback onLeaveChat;
  final VoidCallback onBlockUser;
  final VoidCallback onReportUser;
  final VoidCallback onUnblockUser;
  final VoidCallback onStartGroupChat;
  final VoidCallback onCreateGroupEvent;
  final VoidCallback onShareCommunity;
  final VoidCallback onCreateCommunityGroup;
  final VoidCallback onCreateCommunityEvent;
  final VoidCallback onCreateCommunityOrg;
  final VoidCallback onDDILoans;
  final VoidCallback onLeaderElections;
  final VoidCallback? onChamberOfCommerce;
  final VoidCallback? onChambersOfCommerce;
  final VoidCallback? onQRExchange;

  const ChatMoreMenuSheet({
    super.key,
    required this.chat,
    required this.displayName,
    this.existingRelationship,
    this.pendingSentRequest,
    this.pendingIncomingRequest,
    this.community,
    this.governanceUnit,
    this.hasAnyProfileField = false,
    this.hasVerifiedTarget = false,
    required this.onAddRelationship,
    required this.onVerifyUser,
    required this.onVouchUser,
    required this.onClearChat,
    required this.onDeleteChat,
    required this.onLeaveChat,
    required this.onBlockUser,
    required this.onReportUser,
    required this.onUnblockUser,
    required this.onStartGroupChat,
    required this.onCreateGroupEvent,
    required this.onShareCommunity,
    required this.onCreateCommunityGroup,
    required this.onCreateCommunityEvent,
    required this.onCreateCommunityOrg,
    required this.onDDILoans,
    required this.onLeaderElections,
    this.onChamberOfCommerce,
    this.onChambersOfCommerce,
    this.onQRExchange,
  });

  /// Returns true if the existing relationship is a family type
  /// Also checks pending requests for family types
  bool _isExistingFamily() {
    const familyTypes = {
      'wife',
      'husband',
      'daughter',
      'son',
      'mother',
      'father',
      'sister',
      'brother',
      'aunt',
      'uncle',
      'nephew',
      'niece',
      'cousin',
    };
    if (existingRelationship != null &&
        familyTypes.contains(existingRelationship!.type.toLowerCase())) {
      return true;
    }
    if (pendingSentRequest != null &&
        familyTypes.contains(
          pendingSentRequest!.relationshipType.toLowerCase(),
        )) {
      return true;
    }
    if (pendingIncomingRequest != null &&
        familyTypes.contains(
          pendingIncomingRequest!.relationshipType.toLowerCase(),
        )) {
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final repo = ref.read(chatRepositoryProvider);
    final currentUserId = repo.currentUserId ?? '';
    final isDirect = chat.isDirect;
    final isGroup = chat.isGroup;
    final isCommunity = chat.isCommunity;
    final isEvent = chat.isEvent;
    // Corridor chambers are auto-membership organizations — treat them as a
    // distinct "kind" of organization so labels and exit-actions can differ
    // (e.g. they can't be "unfollowed").
    final isChamber = chat.isOrganization && chat.id.startsWith('org_chamber_');

    final nameToUse = isDirect ? displayName.split(' ').first : displayName;

    final isCountry =
        community?.type == 'country' ||
        chat.id.contains('_country_') ||
        (community?.id.contains('_country_') ?? false);
    final isTown =
        community?.type == 'town' ||
        community?.type == 'city' ||
        chat.id.contains('_town_') ||
        chat.id.contains('_city_') ||
        (community?.id.contains('_town_') ?? false) ||
        (community?.id.contains('_city_') ?? false);
    final isHostLocation =
        community?.locationType == 'host' ||
        chat.locationType == 'host' ||
        chat.id.contains('_host_') ||
        (community?.id.contains('_host_') ?? false);
    final isHomeLocation =
        community?.locationType == 'home' ||
        chat.locationType == 'home' ||
        chat.id.contains('_home_') ||
        (community?.id.contains('_home_') ?? false);

    // DDI is ONLY available for host/home town and host/home country communities (NOT state/province, continent, or global)
    final isDDIAvailable =
        isCommunity &&
        (isTown || isCountry) &&
        (isHostLocation || isHomeLocation);

    final ddiTitle = isCountry
        ? (isHostLocation ? 'Host Country DDI Loans' : 'Home Country DDI Loans')
        : (isHostLocation ? 'Host Town DDI Loans' : 'Home Town DDI Loans');

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Flexible(
            child: ListView(
              shrinkWrap: true,
              physics: const BouncingScrollPhysics(),
              children: [
                // Relationship (Direct Only)
                if (isDirect) ...[
                  if (existingRelationship != null)
                    AppBottomSheetItem(
                      icon: LucideIcons.heart,
                      iconColor: Colors.pink.shade600,
                      iconBgColor: Colors.pink.shade50,
                      title: 'Relationship',
                      subtitle: existingRelationship!.type,
                      onTap: () {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'You are connected as ${existingRelationship!.type}',
                            ),
                          ),
                        );
                      },
                    )
                  else if (pendingSentRequest != null)
                    AppBottomSheetItem(
                      icon: LucideIcons.clock,
                      iconColor: Colors.orange.shade600,
                      iconBgColor: Colors.orange.shade50,
                      title: 'Relationship request waiting',
                      subtitle: 'Request sent to $nameToUse',
                      onTap: () {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Request is pending acceptance'),
                          ),
                        );
                      },
                    )
                  else if (pendingIncomingRequest != null)
                    AppBottomSheetItem(
                      icon: LucideIcons.bellRing,
                      iconColor: Colors.green.shade600,
                      iconBgColor: Colors.green.shade50,
                      title: 'Accept Request',
                      subtitle: '$nameToUse sent you a request',
                      onTap: () {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Please check your notifications to accept.',
                            ),
                          ),
                        );
                      },
                    )
                  else
                    AppBottomSheetItem(
                      icon: LucideIcons.heartHandshake,
                      iconColor: Colors.pink.shade600,
                      iconBgColor: Colors.pink.shade50,
                      title: 'Add Relationship',
                      subtitle: 'Define your relationship with $nameToUse',
                      onTap: onAddRelationship,
                    ),
                  const Divider(height: 1),
                  AppBottomSheetItem(
                    icon: LucideIcons.qrCode,
                    iconColor: theme.colorScheme.primary,
                    iconBgColor: theme.colorScheme.primary.withValues(
                      alpha: 0.1,
                    ),
                    title: 'Identity QR Exchange',
                    subtitle: 'Perform in-person QR handshake with $nameToUse',
                    onTap: () async {
                      Navigator.pop(context);
                      if (onQRExchange != null) {
                        onQRExchange!();
                      } else {
                        final user = ref
                            .read(authRepositoryProvider)
                            .currentUser;
                        if (user != null) {
                          final myProfile =
                              ref.read(userProfileProvider).value ??
                              await ref
                                  .read(profileRepositoryProvider)
                                  .getUserProfile(user.uid);
                          if (myProfile != null && context.mounted) {
                            showDialog(
                              context: context,
                              builder: (context) =>
                                  ProfileQRCodeDialog(profile: myProfile),
                            );
                          }
                        }
                      }
                    },
                  ),
                  const Divider(height: 1),
                ],

                // Event Attendees
                if (isEvent && chat.eventId != null)
                  AppBottomSheetItem(
                    icon: LucideIcons.userCheck,
                    iconColor: Colors.blue.shade700,
                    iconBgColor: Colors.blue.shade50,
                    title: 'Event attendees',
                    subtitle: "View who's attending this event",
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/events/${chat.eventId}/attendees');
                    },
                  ),

                // Group / Profile actions
                if (isDirect) ...[
                  AppBottomSheetItem(
                    icon: LucideIcons.user,
                    iconColor: theme.colorScheme.primary,
                    iconBgColor: theme.colorScheme.primaryContainer,
                    title: 'View Profile',
                    subtitle: 'Check user credentials and trust score',
                    onTap: () {
                      Navigator.pop(context);
                      final otherId = chat.getOtherParticipantId(currentUserId);
                      if (otherId != null) context.push('/profile/$otherId');
                    },
                  ),
                  AppBottomSheetItem(
                    icon: LucideIcons.users,
                    iconColor: Colors.blue.shade700,
                    iconBgColor: Colors.blue.shade50,
                    title: 'Start group chat',
                    subtitle: 'Create a group with $nameToUse',
                    onTap: onStartGroupChat,
                  ),
                  if (hasAnyProfileField && !_isExistingFamily())
                    hasVerifiedTarget
                        ? AppBottomSheetItem(
                            icon: LucideIcons.shieldCheck,
                            iconColor: AppTheme.accent,
                            iconBgColor: AppTheme.accent.withValues(alpha: 0.1),
                            title: 'Vouch',
                            subtitle: 'Update your vouch for $nameToUse',
                            onTap: onVouchUser,
                          )
                        : AppBottomSheetItem(
                            icon: LucideIcons.shieldCheck,
                            iconColor: AppTheme.accent,
                            iconBgColor: AppTheme.accent.withValues(alpha: 0.1),
                            title: 'Verify & Vouch',
                            subtitle: 'Verify or vouch for $nameToUse',
                            onTap: onVerifyUser,
                          ),
                ] else if (!isCommunity && !isEvent) ...[
                  AppBottomSheetItem(
                    icon: LucideIcons.settings,
                    iconColor: Colors.grey.shade700,
                    iconBgColor: Colors.grey.shade100,
                    title: isChamber
                        ? 'Chamber info'
                        : (chat.isOrganization
                              ? 'Organization info'
                              : 'Group info'),
                    subtitle: isChamber
                        ? 'Council, members, and chamber settings'
                        : (chat.isOrganization
                              ? 'Manage organization settings'
                              : 'Manage group settings'),
                    onTap: () {
                      Navigator.pop(context);
                      // Chambers route to their full detail screen so users
                      // get the Chamber Council card + leadership-request CTA,
                      // not the generic org-info screen.
                      if (isChamber) {
                        final orgId = chat.id.replaceFirst('org_', '');
                        context.push('/organization/$orgId');
                        return;
                      }
                      context.push(
                        '/chats/${chat.id}/info',
                        extra: {
                          'name': chat.name,
                          'image': chat.photoUrl,
                          'type': chat.type,
                        },
                      );
                    },
                  ),
                  AppBottomSheetItem(
                    icon: LucideIcons.calendarPlus,
                    iconColor: Colors.orange.shade700,
                    iconBgColor: Colors.orange.shade50,
                    title: isChamber
                        ? 'Create Chamber Event'
                        : (chat.isOrganization
                              ? 'Create Organization Event'
                              : 'Create Group Event'),
                    subtitle: isChamber
                        ? 'Host an event for this chamber'
                        : (chat.isOrganization
                              ? 'Host an event for this organization'
                              : 'Host an event for this group'),
                    onTap: onCreateGroupEvent,
                  ),
                ],

                // Community Specific Actions
                if (isCommunity) ...[
                  AppBottomSheetItem(
                    icon: LucideIcons.share2,
                    iconColor: Colors.blue.shade700,
                    iconBgColor: Colors.blue.shade50,
                    title: 'Share Community',
                    subtitle: 'Share this community with others',
                    onTap: onShareCommunity,
                  ),
                  AppBottomSheetItem(
                    icon: LucideIcons.users,
                    iconColor: Colors.blue.shade700,
                    iconBgColor: Colors.blue.shade50,
                    title: 'Create Community Group',
                    subtitle: 'Start a public group in this community',
                    onTap: onCreateCommunityGroup,
                  ),
                  AppBottomSheetItem(
                    icon: LucideIcons.calendarDays,
                    iconColor: Colors.orange.shade700,
                    iconBgColor: Colors.orange.shade50,
                    title: 'Create Community Event',
                    subtitle: 'Host an event for this community',
                    onTap: onCreateCommunityEvent,
                  ),
                  AppBottomSheetItem(
                    icon: LucideIcons.briefcase,
                    iconColor: Colors.purple.shade700,
                    iconBgColor: Colors.purple.shade50,
                    title: 'Create Community Org/Business',
                    subtitle: 'Register a business in this community',
                    onTap: onCreateCommunityOrg,
                  ),
                  // Diaspora Direct Investments: limited to home/host town and home/host country communities
                  if (isDDIAvailable) ...[
                    AppBottomSheetItem(
                      icon: LucideIcons.landmark,
                      iconColor: Colors.orange,
                      iconBgColor: Colors.orange.withValues(alpha: 0.1),
                      customIconWidget: Image.asset(
                        'assets/icons/logo-orange-transparent-24.png',
                        width: 22,
                        height: 22,
                      ),
                      title: ddiTitle,
                      subtitle: 'Apply for community-backed investment loans',
                      onTap: onDDILoans,
                    ),
                  ],
                  // Bilateral Chamber of Commerce for Host Country
                  if (isHostLocation &&
                      isCountry &&
                      onChamberOfCommerce != null) ...[
                    AppBottomSheetItem(
                      icon: LucideIcons.building2,
                      iconColor: Colors.teal.shade700,
                      iconBgColor: Colors.teal.shade50,
                      title: 'Chamber of Commerce',
                      subtitle: 'Bilateral trade & investment corridor chamber',
                      onTap: onChamberOfCommerce!,
                    ),
                  ],
                  // Bilateral Chambers of Commerce for Home Country (links to all host corridors)
                  if (isHomeLocation &&
                      isCountry &&
                      onChambersOfCommerce != null) ...[
                    AppBottomSheetItem(
                      icon: LucideIcons.network,
                      iconColor: Colors.teal.shade700,
                      iconBgColor: Colors.teal.shade50,
                      title: 'Chambers of Commerce',
                      subtitle:
                          'Explore trade corridors with all host countries',
                      onTap: onChambersOfCommerce!,
                    ),
                  ],
                  AppBottomSheetItem(
                    icon: LucideIcons.vote,
                    iconColor: AppTheme.accent,
                    iconBgColor: AppTheme.accent.withValues(alpha: 0.1),
                    title: 'Council of Community Leaders',
                    subtitle: (governanceUnit?.isActiveElection ?? false)
                        ? 'Active council election in progress'
                        : 'Elect council members and treasury signers',
                    onTap: onLeaderElections,
                  ),
                ],

                const Divider(height: 1),

                // Common actions
                AppBottomSheetItem(
                  icon: LucideIcons.eraser,
                  iconColor: Colors.orange.shade700,
                  iconBgColor: Colors.orange.shade50,
                  title: 'Clear chat',
                  subtitle: 'Clear messages for me',
                  onTap: onClearChat,
                ),

                if (isDirect) ...[
                  AppBottomSheetItem(
                    icon: LucideIcons.trash2,
                    iconColor: Colors.red.shade700,
                    iconBgColor: Colors.red.shade50,
                    title: 'Delete chat',
                    subtitle: 'Remove conversation',
                    onTap: onDeleteChat,
                    isDestructive: true,
                  ),
                  const Divider(height: 1),
                  _BlockActionItem(
                    chat: chat,
                    currentUserId: currentUserId,
                    onBlock: onBlockUser,
                    onUnblock: onUnblockUser,
                  ),
                  AppBottomSheetItem(
                    icon: LucideIcons.flag,
                    iconColor: Colors.red.shade700,
                    iconBgColor: Colors.red.shade50,
                    title: 'Report User',
                    subtitle: 'Notify moderators of policy violations',
                    onTap: onReportUser,
                    isDestructive: true,
                  ),
                ] else if (!isCommunity && !isChamber) ...[
                  // Chambers are auto-membership and cannot be unfollowed —
                  // skip this destructive action entirely on chamber chats.
                  AppBottomSheetItem(
                    icon: LucideIcons.logOut,
                    iconColor: Colors.red.shade700,
                    iconBgColor: Colors.red.shade50,
                    title: isGroup
                        ? 'Leave group'
                        : (isEvent ? 'Leave event' : 'Unfollow Organization'),
                    subtitle: 'Remove from your list',
                    onTap: onLeaveChat,
                    isDestructive: true,
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BlockActionItem extends ConsumerWidget {
  final Chat chat;
  final String currentUserId;
  final VoidCallback onBlock;
  final VoidCallback onUnblock;

  const _BlockActionItem({
    required this.chat,
    required this.currentUserId,
    required this.onBlock,
    required this.onUnblock,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).value;
    final otherId = chat.getOtherParticipantId(currentUserId);
    if (otherId == null) return const SizedBox.shrink();

    final isBlocked = profile?.blockedUsers?.contains(otherId) ?? false;

    return AppBottomSheetItem(
      icon: isBlocked ? LucideIcons.shieldCheck : LucideIcons.ban,
      iconColor: isBlocked ? Colors.green.shade700 : Colors.red.shade700,
      iconBgColor: isBlocked ? Colors.green.shade50 : Colors.red.shade50,
      title: isBlocked ? 'Unblock User' : 'Block User',
      subtitle: isBlocked ? 'Allow them to message you' : 'Block this user',
      isDestructive: !isBlocked,
      onTap: isBlocked ? onUnblock : onBlock,
    );
  }
}
