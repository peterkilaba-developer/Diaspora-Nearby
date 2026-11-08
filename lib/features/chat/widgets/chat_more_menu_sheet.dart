import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/core/data/countries.dart';
import 'package:diaspora_nearby/core/data/world_languages.dart';
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
  final VoidCallback? onStartAiVoiceChat;
  final ValueChanged<String>? onSendAiPrompt;

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
    this.onStartAiVoiceChat,
    this.onSendAiPrompt,
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

  void _showLanguagePickerModal(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _AiAgentLanguagePickerSheet(
              onSelectPrompt: (prompt) {
                Navigator.pop(sheetCtx);
                onSendAiPrompt?.call(prompt);
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final repo = ref.read(chatRepositoryProvider);
    final currentUserId = repo.currentUserId ?? '';
    final isAiAgent =
        chat.metadata?['isAiAgent'] == true ||
        chat.participants.contains('diaspora_ai_agent') ||
        chat.id.startsWith('ai_agent_');
    final isDirect = chat.isDirect && !isAiAgent;
    final isGroup = chat.isGroup;
    final isListingChat = chat.isListingChat;
    final listingId = chat.metadata?['listingId'] as String?;
    final isCommunity = chat.isCommunity;
    final isEvent = chat.isEvent;
    // Corridor chambers are auto-membership organizations — treat them as a
    // distinct "kind" of organization so labels and exit-actions can differ
    // (e.g. they can't be "unfollowed").
    final isChamber = chat.isOrganization && chat.id.startsWith('org_chamber_');

    if (isAiAgent) {
      return Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.2,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    AppBottomSheetItem(
                      icon: LucideIcons.globe,
                      iconColor: Colors.teal.shade600,
                      iconBgColor: Colors.teal.withValues(alpha: 0.12),
                      title: 'Change Language / Badili Lugha',
                      subtitle:
                          'Languages spoken in your home & host countries or search all',
                      onTap: () {
                        final rootCtx = Navigator.of(
                          context,
                          rootNavigator: true,
                        ).context;
                        Navigator.pop(context);
                        _showLanguagePickerModal(rootCtx);
                      },
                    ),
                    AppBottomSheetItem(
                      icon: LucideIcons.eraser,
                      iconColor: Colors.orange.shade700,
                      iconBgColor: Colors.orange.withValues(alpha: 0.12),
                      title: 'Clear chat',
                      subtitle: 'Clear conversation history',
                      onTap: onClearChat,
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

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
                          builder: (_) => BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: RelationshipResponseModal(request: request),
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
                      if (onQRExchange != null) {
                        Navigator.pop(context);
                        onQRExchange!();
                        return;
                      }
                      final rootContext = Navigator.of(
                        context,
                        rootNavigator: true,
                      ).context;
                      final user = ref.read(authRepositoryProvider).currentUser;
                      final profileRepo = ref.read(profileRepositoryProvider);
                      final cachedProfile =
                          ref.read(userProfileProvider).value ??
                          (user != null
                              ? profileRepo.getCachedProfile(user.uid)
                              : null);
                      Navigator.pop(context);
                      if (user != null) {
                        final myProfile =
                            cachedProfile ??
                            await profileRepo.getUserProfile(user.uid);
                        if (myProfile != null && rootContext.mounted) {
                          showDialog(
                            context: rootContext,
                            useRootNavigator: true,
                            builder: (_) => BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: ProfileQRCodeDialog(profile: myProfile),
                            ),
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
                    Consumer(
                      builder: (context, ref, _) {
                        final listing = ref
                            .watch(_shopListingMenuProvider(listingId))
                            .value;
                        final isJob =
                            listing?.listingType == ListingType.job ||
                            chat.isJobListingChat;
                        final isService =
                            listing?.listingType == ListingType.service ||
                            chat.isServiceListingChat;
                        final catName = isService
                            ? 'Service'
                            : isJob
                            ? 'Job'
                            : 'Product';
                        final catLower = catName.toLowerCase();
                        return AppBottomSheetItem(
                          icon: isJob
                              ? LucideIcons.briefcase
                              : isService
                              ? LucideIcons.wrench
                              : LucideIcons.shoppingBag,
                          iconColor: Colors.green.shade700,
                          iconBgColor: Colors.green.shade50,
                          title: 'View $catLower',
                          subtitle: isJob
                              ? 'See job details, compensation, and requirements'
                              : isService
                              ? 'See service details, rates, and availability'
                              : 'See product details, price, and photos',
                          onTap: () {
                            Navigator.pop(context);
                            context.push('/marketplace/listing/$listingId');
                          },
                        );
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
                          final isService =
                              listing.listingType == ListingType.service;
                          final catName = isService
                              ? 'Service'
                              : isJob
                              ? 'Job'
                              : 'Product';
                          final catLower = catName.toLowerCase();
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
                                ? (isJob
                                      ? 'Reopen job'
                                      : isService
                                      ? 'Reopen service'
                                      : 'Relist $catLower')
                                : (isJob
                                      ? 'Mark as Filled'
                                      : isService
                                      ? 'Mark as Booked'
                                      : 'Mark as Sold'),
                            subtitle: showRelist
                                ? 'Make this $catLower available again'
                                : (isJob
                                      ? 'Let applicants know this job is filled'
                                      : isService
                                      ? 'Let clients know this service is currently booked'
                                      : 'Let shoppers know this $catLower is sold'),
                            onTap: () {
                              final messenger = ScaffoldMessenger.maybeOf(
                                context,
                              );
                              final marketplaceRepo = ref.read(
                                marketplaceRepositoryProvider,
                              );
                              Navigator.pop(context);
                              final newStatus = showRelist
                                  ? ListingStatus.active
                                  : ListingStatus.sold;
                              final statusText = showRelist
                                  ? '$catName is now available again'
                                  : (isJob
                                        ? 'Job marked as Filled'
                                        : isService
                                        ? 'Service marked as Booked'
                                        : '$catName marked as Sold');
                              messenger?.showSnackBar(
                                SnackBar(content: Text(statusText)),
                              );
                              unawaited(() async {
                                try {
                                  await Future.wait([
                                    marketplaceRepo.updateListingStatus(
                                      listingId,
                                      newStatus,
                                    ),
                                    repo.sendTextMessage(
                                      chat.id,
                                      statusText,
                                      type: 'system',
                                      participants: chat.participants,
                                    ),
                                  ]);
                                  ref.invalidate(
                                    _shopListingMenuProvider(listingId),
                                  );
                                } catch (e) {
                                  debugPrint(
                                    'Error updating shop listing status: $e',
                                  );
                                }
                              }());
                            },
                          );
                        },
                      ),
                    AppBottomSheetItem(
                      icon: LucideIcons.edit3,
                      iconColor: theme.colorScheme.primary,
                      iconBgColor: theme.colorScheme.primaryContainer,
                      title: 'Manage ${chat.listingChatNounLower}',
                      subtitle:
                          'Edit ${chat.listingChatNounLower} name, description, and ${chat.listingParticipantPlural}',
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
                    title: '${chat.listingChatNoun} info',
                    subtitle:
                        'Manage ${chat.listingChatNounLower} settings and ${chat.listingParticipantPlural}',
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
                        ? 'Leave ${chat.listingChatNounLower}'
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

class _AiAgentLanguagePickerSheet extends ConsumerStatefulWidget {
  final ValueChanged<String> onSelectPrompt;

  const _AiAgentLanguagePickerSheet({required this.onSelectPrompt});

  @override
  ConsumerState<_AiAgentLanguagePickerSheet> createState() =>
      _AiAgentLanguagePickerSheetState();
}

class _AiAgentLanguagePickerSheetState
    extends ConsumerState<_AiAgentLanguagePickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _resolveCountryCode({
    required String? code,
    required String? countryName,
  }) {
    final trimmedCode = code?.trim().toUpperCase() ?? '';
    if (trimmedCode.isNotEmpty) return trimmedCode;
    final trimmedName = countryName?.trim().toLowerCase() ?? '';
    if (trimmedName.isEmpty) return '';
    for (final c in countries) {
      if (c.name.toLowerCase() == trimmedName ||
          c.code.toLowerCase() == trimmedName) {
        return c.code.toUpperCase();
      }
    }
    return '';
  }

  String _promptForLanguage(WorldLanguage lang) {
    switch (lang.code.toLowerCase()) {
      case 'sw':
        return 'Tafadhali ongea nami kwa Kiswahili kuanzia sasa.';
      case 'en':
        return 'Please communicate with me in English.';
      case 'fr':
        return 'Veuillez communiquer avec moi en français.';
      case 'ar':
        return 'يرجى التحدث معي باللغة العربية.';
      case 'es':
        return 'Por favor comunícate conmigo en español.';
      case 'pt':
        return 'Por favor, comunique-se comigo em português.';
      default:
        return 'Please communicate with me in ${lang.name} (${lang.nativeName}).';
    }
  }

  String _subtitleForLanguage(
    WorldLanguage lang, {
    required String homeCode,
    required String hostCode,
    Country? homeCountry,
    Country? hostCountry,
  }) {
    final upperCodes = lang.countryCodes.map((c) => c.toUpperCase()).toSet();
    final inHome = homeCode.isNotEmpty && upperCodes.contains(homeCode);
    final inHost = hostCode.isNotEmpty && upperCodes.contains(hostCode);
    if (inHome && inHost) {
      final homeName = homeCountry?.name ?? homeCode;
      final hostName = hostCountry?.name ?? hostCode;
      return homeName == hostName
          ? 'Spoken in $homeName'
          : 'Spoken in $homeName & $hostName';
    }
    if (inHome) {
      return 'Home country • ${homeCountry?.name ?? homeCode}';
    }
    if (inHost) {
      return 'Host country • ${hostCountry?.name ?? hostCode}';
    }
    final langCountries = getCountriesForLanguage(lang);
    if (langCountries.isEmpty) return 'Communicate in ${lang.name}';
    final sample = langCountries.take(3).map((c) => c.name).join(', ');
    final extra = langCountries.length > 3 ? ' +${langCountries.length - 3}' : '';
    return '$sample$extra';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = ref.watch(userProfileProvider).value;

    final homeCode = _resolveCountryCode(
      code: profile?.homeCountryCode,
      countryName: profile?.homeCountry,
    );
    final hostCode = _resolveCountryCode(
      code: profile?.hostCountryCode ?? profile?.currentLocation?.countryCode,
      countryName: profile?.hostCountry,
    );

    final Country? homeCountry = homeCode.isNotEmpty
        ? getCountryByCode(homeCode)
        : null;
    final Country? hostCountry = hostCode.isNotEmpty
        ? getCountryByCode(hostCode)
        : null;

    final List<WorldLanguage> corridorLanguages = [];
    final Set<String> seenCorridorCodes = {};

    for (final code in [homeCode, hostCode]) {
      if (code.isEmpty) continue;
      for (final lang in getOfficialLanguagesForCountry(code)) {
        if (seenCorridorCodes.add(lang.code)) {
          corridorLanguages.add(lang);
        }
      }
    }

    // Also include any spoken languages listed on the user's profile
    if (profile?.languages != null) {
      for (final spoken in profile!.languages!) {
        final norm = spoken.trim().toLowerCase();
        if (norm.isEmpty) continue;
        for (final lang in worldLanguages) {
          if (lang.name.toLowerCase() == norm ||
              lang.nativeName.toLowerCase() == norm) {
            if (seenCorridorCodes.add(lang.code)) {
              corridorLanguages.add(lang);
            }
          }
        }
      }
    }

    // Fallback if profile countries aren't loaded yet
    if (corridorLanguages.isEmpty) {
      for (final code in ['TZ', 'US']) {
        for (final lang in getOfficialLanguagesForCountry(code)) {
          if (seenCorridorCodes.add(lang.code)) {
            corridorLanguages.add(lang);
          }
        }
      }
    }

    final q = _query.trim().toLowerCase();
    final List<WorldLanguage> searchResults = q.isEmpty
        ? const <WorldLanguage>[]
        : worldLanguages.where((lang) {
            if (lang.name.toLowerCase().contains(q) ||
                lang.nativeName.toLowerCase().contains(q) ||
                lang.code.toLowerCase().contains(q)) {
              return true;
            }
            for (final c in getCountriesForLanguage(lang)) {
              if (c.name.toLowerCase().contains(q) ||
                  c.code.toLowerCase() == q) {
                return true;
              }
            }
            return false;
          }).toList();

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Container(
          padding: EdgeInsets.only(bottom: bottomInset),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.2,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 12, 8),
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.globe,
                        color: AppTheme.accent,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Select AI Agent Language / Chagua Lugha',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.x, size: 18),
                        onPressed: () => Navigator.of(context).pop(),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: 'Search other languages or countries...',
                      prefixIcon: const Icon(LucideIcons.search, size: 18),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(LucideIcons.x, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                            )
                          : null,
                      isDense: true,
                      filled: true,
                      fillColor: AppTheme.elevationColor(context, 3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.only(bottom: 16),
                    children: [
                      if (q.isEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
                          child: Text(
                            'YOUR HOME & HOST COUNTRY LANGUAGES',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: theme.hintColor,
                            ),
                          ),
                        ),
                        ...corridorLanguages.map(
                          (lang) => AppBottomSheetItem(
                            icon: LucideIcons.languages,
                            iconColor: AppTheme.accent,
                            iconBgColor: AppTheme.accent.withValues(
                              alpha: 0.12,
                            ),
                            title:
                                '${lang.primaryFlag}  ${lang.displayLabel}',
                            subtitle: _subtitleForLanguage(
                              lang,
                              homeCode: homeCode,
                              hostCode: hostCode,
                              homeCountry: homeCountry,
                              hostCountry: hostCountry,
                            ),
                            onTap: () => widget.onSelectPrompt(
                              _promptForLanguage(lang),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                          child: Text(
                            'OTHER LANGUAGES',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: theme.hintColor,
                            ),
                          ),
                        ),
                        ...worldLanguages
                            .where(
                              (lang) => !seenCorridorCodes.contains(lang.code),
                            )
                            .map(
                              (lang) => AppBottomSheetItem(
                                icon: LucideIcons.languages,
                                iconColor: AppTheme.accent,
                                iconBgColor: AppTheme.accent.withValues(
                                  alpha: 0.12,
                                ),
                                title:
                                    '${lang.primaryFlag}  ${lang.displayLabel}',
                                subtitle: _subtitleForLanguage(
                                  lang,
                                  homeCode: homeCode,
                                  hostCode: hostCode,
                                  homeCountry: homeCountry,
                                  hostCountry: hostCountry,
                                ),
                                onTap: () => widget.onSelectPrompt(
                                  _promptForLanguage(lang),
                                ),
                              ),
                            ),
                      ] else if (searchResults.isEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.all(28),
                          child: Center(
                            child: Text(
                              'No matching languages found.',
                              style: TextStyle(color: theme.hintColor),
                            ),
                          ),
                        ),
                      ] else ...[
                        ...searchResults.map(
                          (lang) => AppBottomSheetItem(
                            icon: LucideIcons.languages,
                            iconColor: AppTheme.accent,
                            iconBgColor: AppTheme.accent.withValues(
                              alpha: 0.12,
                            ),
                            title:
                                '${lang.primaryFlag}  ${lang.displayLabel}',
                            subtitle: _subtitleForLanguage(
                              lang,
                              homeCode: homeCode,
                              hostCode: hostCode,
                              homeCountry: homeCountry,
                              hostCountry: hostCountry,
                            ),
                            onTap: () => widget.onSelectPrompt(
                              _promptForLanguage(lang),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
