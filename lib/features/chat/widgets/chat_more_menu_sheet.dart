import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/chat/models/chat.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/profile/models/relationship.dart';
import 'package:diaspora_nearby/features/profile/models/relationship_request.dart';
import 'package:diaspora_nearby/features/governance/models/governance_unit.dart';
import 'package:diaspora_nearby/features/community/models/community_data.dart';
import 'package:diaspora_nearby/features/events/models/event_data.dart';
import 'package:diaspora_nearby/features/shared/widgets/bottom_sheet_item.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/widgets/profile_qr_code_dialog.dart';
import 'package:diaspora_nearby/features/profile/widgets/relationship_response_modal.dart';
import 'package:diaspora_nearby/features/marketplace/models/marketplace_listing.dart';
import 'package:diaspora_nearby/features/marketplace/repository/marketplace_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/relationship_repository.dart';
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';
import 'package:diaspora_nearby/features/trust/widgets/trust_slider_widget.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:go_router/go_router.dart';

final _shopListingMenuProvider =
    FutureProvider.family<MarketplaceListing?, String>((ref, listingId) async {
      if (listingId.isEmpty) return null;
      return ref.watch(marketplaceRepositoryProvider).getListingById(listingId);
    });

class ChatMoreMenuSheet extends ConsumerWidget {
  final Chat chat;
  final String displayName;
  final Relationship? existingRelationship;
  final RelationshipRequest? pendingSentRequest;
  final RelationshipRequest? pendingIncomingRequest;
  final Community? community;
  final Event? event;
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
  final VoidCallback? onAcceptRelationshipRequest;

  const ChatMoreMenuSheet({
    super.key,
    required this.chat,
    required this.displayName,
    this.existingRelationship,
    this.pendingSentRequest,
    this.pendingIncomingRequest,
    this.community,
    this.event,
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
    this.onAcceptRelationshipRequest,
  });

  /// Returns true if the existing relationship is a family type
  /// Also checks pending requests and live providers for family types
  bool _isExistingFamily(WidgetRef ref, String currentUserId) {
    if (existingRelationship != null &&
        TrustSliderWidget.isFamilyRelationshipType(
          existingRelationship!.type,
        )) {
      return true;
    }
    if (pendingSentRequest != null &&
        TrustSliderWidget.isFamilyRelationshipType(
          pendingSentRequest!.relationshipType,
        )) {
      return true;
    }
    if (pendingIncomingRequest != null &&
        TrustSliderWidget.isFamilyRelationshipType(
          pendingIncomingRequest!.relationshipType,
        )) {
      return true;
    }
    final otherId = chat.getOtherParticipantId(currentUserId);
    if (currentUserId.isNotEmpty && otherId != null && otherId.isNotEmpty) {
      final rels = ref.watch(userRelationshipsProvider(currentUserId)).value;
      if (rels != null &&
          rels.any(
            (r) =>
                r.id == otherId &&
                r.status == 'active' &&
                TrustSliderWidget.isFamilyRelationshipType(r.type),
          )) {
        return true;
      }
      final trustData = ref.watch(userTrustProvider(currentUserId)).value;
      if (TrustSliderWidget.isFamilyRelationshipType(
        trustData?.relationshipTypes[otherId],
      )) {
        return true;
      }
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
    final isListingChat = chat.isListingChat;
    final listingId = chat.metadata?['listingId'] as String?;
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
                        final messenger = ScaffoldMessenger.maybeOf(context);
                        Navigator.pop(context);
                        messenger?.showSnackBar(
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
                        final messenger = ScaffoldMessenger.maybeOf(context);
                        Navigator.pop(context);
                        messenger?.showSnackBar(
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
                        if (onAcceptRelationshipRequest != null) {
                          onAcceptRelationshipRequest!();
                          return;
                        }
                        final rootContext = Navigator.of(
                          context,
                          rootNavigator: true,
                        ).context;
                        final request = pendingIncomingRequest!;
                        Navigator.pop(context);
                        showModalBottomSheet(
                          context: rootContext,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) =>
                              RelationshipResponseModal(request: request),
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
                      if (onQRExchange != null) {
                        Navigator.pop(context);
                        onQRExchange!();
                        return;
                      }
                      // Capture root context & providers before popping the sheet,
                      // because Navigator.pop(context) unmounts the bottom sheet's context.
                      final rootContext = Navigator.of(
                        context,
                        rootNavigator: true,
                      ).context;
                      final user = ref.read(authRepositoryProvider).currentUser;
                      final cachedProfile = ref.read(userProfileProvider).value;
                      final profileRepo = ref.read(profileRepositoryProvider);
                      Navigator.pop(context);
                      if (user != null) {
                        final myProfile =
                            cachedProfile ??
                            await profileRepo.getUserProfile(user.uid);
                        if (myProfile != null && rootContext.mounted) {
                          showDialog(
                            context: rootContext,
                            useRootNavigator: true,
                            builder: (_) =>
                                ProfileQRCodeDialog(profile: myProfile),
                          );
                        }
                      }
                    },
                  ),
                  const Divider(height: 1),
                ],

                // Event Actions & Inline Management
                if (isEvent) ...[
                  Builder(
                    builder: (context) {
                      final effectiveEventId =
                          chat.eventId ??
                          (chat.id.startsWith('event_')
                              ? chat.id.substring('event_'.length)
                              : null);
                      if (effectiveEventId == null) {
                        return const SizedBox.shrink();
                      }
                      final isEventCreator =
                          currentUserId.isNotEmpty &&
                          (event?.creatorId == currentUserId ||
                              chat.createdBy == currentUserId ||
                              (chat.admins?.contains(currentUserId) ?? false));

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isEventCreator) ...[
                            AppBottomSheetItem(
                              icon: LucideIcons.settings,
                              iconColor: theme.colorScheme.primary,
                              iconBgColor: theme.colorScheme.primaryContainer,
                              title: 'Manage event',
                              subtitle:
                                  'Edit event details, schedule, or delete',
                              onTap: () {
                                Navigator.pop(context);
                                context.push(
                                  '/events/edit/$effectiveEventId',
                                  extra: event,
                                );
                              },
                            ),
                            AppBottomSheetItem(
                              icon: LucideIcons.qrCode,
                              iconColor: Colors.teal.shade700,
                              iconBgColor: Colors.teal.shade50,
                              title: 'Organizer check-in QR',
                              subtitle: 'Display QR code for attendee check-in',
                              onTap: () {
                                Navigator.pop(context);
                                context.push(
                                  '/events/qr/$effectiveEventId',
                                  extra: {
                                    'title': event?.title ?? chat.name,
                                    'isCreator': true,
                                  },
                                );
                              },
                            ),
                          ],
                          AppBottomSheetItem(
                            icon: LucideIcons.calendar,
                            iconColor: Colors.orange.shade700,
                            iconBgColor: Colors.orange.shade50,
                            title: 'Event details',
                            subtitle: 'View event schedule and location',
                            onTap: () {
                              Navigator.pop(context);
                              context.push(
                                '/events/$effectiveEventId?fromChat=true',
                                extra: event,
                              );
                            },
                          ),
                          AppBottomSheetItem(
                            icon: LucideIcons.userCheck,
                            iconColor: Colors.blue.shade700,
                            iconBgColor: Colors.blue.shade50,
                            title: 'Event attendees',
                            subtitle: "View who's attending this event",
                            onTap: () {
                              Navigator.pop(context);
                              context.push(
                                '/events/$effectiveEventId/attendees',
                                extra: event,
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ],

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
                  if (hasAnyProfileField &&
                      !_isExistingFamily(ref, currentUserId))
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
                ] else if (isListingChat) ...[
                  if (listingId != null && listingId.isNotEmpty)
                    AppBottomSheetItem(
                      icon: LucideIcons.shoppingBag,
                      iconColor: Colors.green.shade700,
                      iconBgColor: Colors.green.shade50,
                      title: 'View listing',
                      subtitle: 'See product details, price, and photos',
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/marketplace/listing/$listingId');
                      },
                    ),
                  if (currentUserId.isNotEmpty &&
                      (chat.createdBy == currentUserId ||
                          (chat.admins?.contains(currentUserId) ?? false))) ...[
                    if (listingId != null && listingId.isNotEmpty)
                      Consumer(
                        builder: (context, ref, _) {
                          final listing = ref
                              .watch(_shopListingMenuProvider(listingId))
                              .value;
                          if (listing == null) return const SizedBox.shrink();
                          final isSold = listing.status == ListingStatus.sold;
                          final isPaused =
                              listing.status == ListingStatus.paused;
                          final isJob = listing.listingType == ListingType.job;
                          final showRelist = isSold || isPaused;

                          return AppBottomSheetItem(
                            icon: showRelist
                                ? LucideIcons.rotateCcw
                                : LucideIcons.checkCircle2,
                            iconColor: showRelist
                                ? AppTheme.accent
                                : Colors.green.shade700,
                            iconBgColor: showRelist
                                ? AppTheme.accent.withValues(alpha: 0.1)
                                : Colors.green.shade50,
                            title: showRelist
                                ? 'Relist item'
                                : (isJob ? 'Mark as Filled' : 'Mark as Sold'),
                            subtitle: showRelist
                                ? 'Make this listing available again'
                                : (isJob
                                      ? 'Let applicants know this position is filled'
                                      : 'Let shoppers know this item is sold'),
                            onTap: () async {
                              final messenger = ScaffoldMessenger.maybeOf(
                                context,
                              );
                              Navigator.pop(context);
                              final newStatus = showRelist
                                  ? ListingStatus.active
                                  : ListingStatus.sold;
                              final statusText = showRelist
                                  ? 'Listing is now available again'
                                  : (isJob
                                        ? 'Position marked as Filled'
                                        : 'Item marked as Sold');
                              try {
                                await ref
                                    .read(marketplaceRepositoryProvider)
                                    .updateListingStatus(listingId, newStatus);
                                ref.invalidate(
                                  _shopListingMenuProvider(listingId),
                                );
                                await repo.sendTextMessage(
                                  chat.id,
                                  statusText,
                                  type: 'system',
                                  participants: chat.participants,
                                );
                                messenger?.showSnackBar(
                                  SnackBar(content: Text(statusText)),
                                );
                              } catch (e) {
                                debugPrint(
                                  'Error updating shop listing status: $e',
                                );
                              }
                            },
                          );
                        },
                      ),
                    AppBottomSheetItem(
                      icon: LucideIcons.edit3,
                      iconColor: theme.colorScheme.primary,
                      iconBgColor: theme.colorScheme.primaryContainer,
                      title: 'Manage shop',
                      subtitle: 'Edit shop name, description, and shoppers',
                      onTap: () {
                        Navigator.pop(context);
                        context.push(
                          '/chats/${chat.id}/info',
                          extra: {
                            'name': chat.name,
                            'image': chat.photoUrl,
                            'type': chat.type,
                            'initialEdit': true,
                          },
                        );
                      },
                    ),
                  ],
                  AppBottomSheetItem(
                    icon: LucideIcons.settings,
                    iconColor: Colors.grey.shade700,
                    iconBgColor: Colors.grey.shade100,
                    title: 'Shop info',
                    subtitle: 'Manage shop settings and shoppers',
                    onTap: () {
                      Navigator.pop(context);
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
                ] else if (!isCommunity && !isEvent) ...[
                  if (isGroup &&
                      currentUserId.isNotEmpty &&
                      (chat.createdBy == currentUserId ||
                          (chat.admins?.contains(currentUserId) ?? false)))
                    AppBottomSheetItem(
                      icon: LucideIcons.edit3,
                      iconColor: theme.colorScheme.primary,
                      iconBgColor: theme.colorScheme.primaryContainer,
                      title: 'Manage group',
                      subtitle: 'Edit group name, description, and members',
                      onTap: () {
                        Navigator.pop(context);
                        context.push(
                          '/chats/${chat.id}/info',
                          extra: {
                            'name': chat.name,
                            'image': chat.photoUrl,
                            'type': chat.type,
                            'initialEdit': true,
                          },
                        );
                      },
                    ),
                  if (chat.isOrganization &&
                      !isChamber &&
                      currentUserId.isNotEmpty &&
                      (chat.createdBy == currentUserId ||
                          (chat.admins?.contains(currentUserId) ?? false)))
                    AppBottomSheetItem(
                      icon: LucideIcons.sliders,
                      iconColor: theme.colorScheme.primary,
                      iconBgColor: theme.colorScheme.primaryContainer,
                      title: 'Manage organization',
                      subtitle:
                          'Edit organization profile, admins, and products',
                      onTap: () {
                        Navigator.pop(context);
                        final orgId = chat.id.replaceFirst('org_', '');
                        context.push('/organization/manage?orgId=$orgId');
                      },
                    ),
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
                              ? 'View members and organization info'
                              : 'Manage group settings and members'),
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
                    title: isListingChat
                        ? 'Leave shop'
                        : isGroup
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
