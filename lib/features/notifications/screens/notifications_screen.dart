import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:intl/intl.dart';

import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/hosting/models/hosting_request.dart';
import 'package:diaspora_nearby/features/hosting/services/hosting_service.dart';
import 'package:diaspora_nearby/features/notifications/models/notification_item.dart';
import 'package:diaspora_nearby/features/notifications/providers/notification_count_provider.dart';
import 'package:diaspora_nearby/features/notifications/repository/notifications_repository.dart';
import 'package:diaspora_nearby/features/hosting/repository/hosting_repository.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final Set<String> _optimisticReadIds = {};
  final Set<String> _optimisticCompletedIds = {};
  final Set<String> _optimisticDeletedIds = {};
  bool _optimisticMarkedAllRead = false;
  bool _optimisticClearedAll = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<NotificationItem> _applyOptimisticState(List<NotificationItem> items) {
    if (_optimisticClearedAll) return const [];
    final result = <NotificationItem>[];
    for (var item in items) {
      if (_optimisticDeletedIds.contains(item.id)) continue;
      final isRead =
          item.isRead ||
          _optimisticMarkedAllRead ||
          _optimisticReadIds.contains(item.id) ||
          _optimisticCompletedIds.contains(item.id);
      final actionCompleted =
          item.actionCompleted || _optimisticCompletedIds.contains(item.id);
      if (isRead != item.isRead || actionCompleted != item.actionCompleted) {
        item = item.copyWith(isRead: isRead, actionCompleted: actionCompleted);
      }
      result.add(item);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(authRepositoryProvider).currentUser?.uid;
    final cachedNotifications = userId != null
        ? ref.read(notificationsRepositoryProvider).getCachedNotifications(
            userId,
          )
        : null;
    final notificationsAsync = ref.watch(notificationsStreamProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final rawNotifications =
        notificationsAsync.value ?? cachedNotifications;
    final effectiveNotifications = rawNotifications != null
        ? _applyOptimisticState(rawNotifications)
        : null;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/chats');
            }
          },
        ),
        title: const Text(
          'Notifications',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(LucideIcons.moreVertical, size: 20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onSelected: (value) {
              if (!mounted) return;
              if (value == 'mark_all_read') _markAllRead();
              if (value == 'clear_all') _clearAll();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'mark_all_read',
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.checkCheck,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    const SizedBox(width: 8),
                    const Text('Mark all as read'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'clear_all',
                child: Row(
                  children: [
                    Icon(LucideIcons.trash2, size: 16, color: AppTheme.error),
                    SizedBox(width: 8),
                    Text('Clear all', style: TextStyle(color: AppTheme.error)),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w400,
            fontSize: 14,
          ),
          indicatorColor: Theme.of(context).colorScheme.onSurface,
          labelColor: Theme.of(context).colorScheme.onSurface,
          unselectedLabelColor: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.4),
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.alertCircle, size: 16),
                  const SizedBox(width: 6),
                  const Text('Action Required'),
                  _buildBadge(effectiveNotifications),
                ],
              ),
            ),
            const Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.checkCircle2, size: 16),
                  SizedBox(width: 6),
                  Text('Completed'),
                ],
              ),
            ),
            const Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.inbox, size: 16),
                  SizedBox(width: 6),
                  Text('All'),
                ],
              ),
            ),
          ],
        ),
      ),
      body: effectiveNotifications != null
          ? _buildTabsContent(effectiveNotifications, isDark)
          : notificationsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) {
                debugPrint('❌ Notifications error: $e\n$st');
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.alertTriangle,
                          size: 40,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Error loading notifications',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$e',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () =>
                              ref.invalidate(notificationsStreamProvider),
                          icon: const Icon(LucideIcons.refreshCw, size: 16),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                );
              },
              data: (allNotifications) => _buildTabsContent(
                _applyOptimisticState(allNotifications),
                isDark,
              ),
            ),
    );
  }

  Widget _buildTabsContent(
    List<NotificationItem> allNotifications,
    bool isDark,
  ) {
    final actionRequired = allNotifications
        .where((n) => n.actionRequired && !n.actionCompleted)
        .toList();
    final completed = allNotifications
        .where((n) => n.actionRequired && n.actionCompleted)
        .toList();

    return TabBarView(
      controller: _tabController,
      children: [
        // Tab 1: Action Required
        actionRequired.isEmpty
            ? _buildEmptyState(
                icon: LucideIcons.checkCircle2,
                title: 'All caught up!',
                subtitle: 'No pending actions',
              )
            : _buildList(actionRequired, isDark),

        // Tab 2: Completed
        completed.isEmpty
            ? _buildEmptyState(
                icon: LucideIcons.checkCheck,
                title: 'No completed actions yet',
                subtitle: 'Completed actions will appear here',
              )
            : _buildList(completed, isDark),

        // Tab 3: All Notifications
        allNotifications.isEmpty
            ? _buildEmptyState(
                icon: LucideIcons.bellOff,
                title: 'No notifications yet',
                subtitle: 'You\'ll see activity here',
              )
            : _buildList(allNotifications, isDark),
      ],
    );
  }

  // ── Badge on the Action Required tab ─────────────────────────────────

  Widget _buildBadge(List<NotificationItem>? items) {
    final count =
        items?.where((n) => n.actionRequired && !n.actionCompleted).length ?? 0;
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Text(
        '$count',
        style: const TextStyle(
          color: AppTheme.error,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // ── Empty state ──────────────────────────────────────────────────────

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 56,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.15),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }

  // ── Notification list ────────────────────────────────────────────────

  Widget _buildList(List<NotificationItem> items, bool isDark) {
    return ListView.separated(
      padding: EdgeInsets.only(
        top: 8,
        bottom: 8 + MediaQuery.of(context).padding.bottom,
      ),
      itemCount: items.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        indent: 72,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return _NotificationCard(
          item: item,
          isDark: isDark,
          onTap: () => _handleTap(item),
          onAction: (action) => _handleAction(item, action),
          onDismiss: () => _dismissNotification(item),
        );
      },
    );
  }

  // ── Actions ──────────────────────────────────────────────────────────

  void _handleTap(NotificationItem item) {
    final userId = ref.read(authRepositoryProvider).currentUser?.uid;
    setState(() {
      _optimisticReadIds.add(item.id);
    });
    if (userId != null) {
      unawaited(
        ref.read(notificationsRepositoryProvider).markAsRead(userId, item.id),
      );
    }

    String? route;
    bool isGoRoute = false;
    bool shouldCompleteAction = false;

    // Navigate based on type
    switch (item.type) {
      case NotificationType.hostingInterest:
        final hostId = item.payload['hostId'] as String?;
        if (hostId != null && hostId.isNotEmpty) {
          route = '/profile/$hostId';
        }
        break;
      case NotificationType.hostingSelected:
      case NotificationType.hostingSessionEvent:
        final chatId = item.payload['chatId'] as String?;
        if (chatId != null && chatId.isNotEmpty) {
          route = '/chats/$chatId';
        }
        shouldCompleteAction = true;
        break;
      case NotificationType.relationshipRequest:
        final fromUserId = item.payload['fromUserId'] as String?;
        final requestId = item.payload['requestId'] as String?;
        if (fromUserId != null && fromUserId.isNotEmpty) {
          route =
              '/profile/$fromUserId?requestId=${requestId ?? ''}&action=review';
        }
        break;
      case NotificationType.relationshipAccepted:
        final chatId = item.payload['chatId'] as String?;
        if (chatId != null && chatId.isNotEmpty) {
          route = '/chats/$chatId';
        }
        shouldCompleteAction = true;
        break;
      case NotificationType.groupInvitation:
        final chatId = item.payload['chatId'] as String?;
        if (chatId != null && chatId.isNotEmpty) {
          route = '/chats/$chatId/info';
        }
        break;
      case NotificationType.proxyRequest:
        route = '/dsp/emergency-fund';
        shouldCompleteAction = true;
        break;
      case NotificationType.dspTransfer:
        final chatId = item.payload['chatId'] as String?;
        if (chatId != null && chatId.isNotEmpty) {
          route = '/chats/$chatId';
        } else {
          route = '/dsp/points';
        }
        break;

      // ── Travel / Peer Bookings ──
      case NotificationType.travelBookingRequest:
      case NotificationType.travelBookingConfirmed:
      case NotificationType.travelBookingDeclined:
      case NotificationType.travelBookingCancelled:
      case NotificationType.travelTripReminder:
        final chatId = item.payload['chatId'] as String?;
        if (chatId != null && chatId.isNotEmpty) {
          route = '/chats/$chatId';
        } else {
          route = '/dsp/travel/stays';
        }
        shouldCompleteAction = true;
        break;

      // ── Events ──
      case NotificationType.eventNew:
      case NotificationType.eventReminder:
      case NotificationType.eventUpdate:
      case NotificationType.eventCancelled:
      case NotificationType.eventNewAttendee:
        final eventId = item.payload['eventId'] as String?;
        if (eventId != null && eventId.isNotEmpty) {
          route = '/events/$eventId';
        } else {
          route = '/events';
          isGoRoute = true;
        }
        break;

      // ── Governance / Elections ──
      case NotificationType.electionStarted:
      case NotificationType.electionEndingSoon:
      case NotificationType.electionResults:
        route = '/communities';
        isGoRoute = true;
        shouldCompleteAction = true;
        break;

      // ── Marketplace ──
      case NotificationType.marketplaceInquiry:
        final chatId = item.payload['chatId'] as String?;
        if (chatId != null && chatId.isNotEmpty) {
          route = '/chats/$chatId';
        } else {
          final listingId = item.payload['listingId'] as String?;
          if (listingId != null && listingId.isNotEmpty) {
            route = '/marketplace/listing/$listingId';
          } else {
            route = '/marketplace';
            isGoRoute = true;
          }
        }
        shouldCompleteAction = true;
        break;
      case NotificationType.marketplaceStatusChange:
      case NotificationType.marketplacePriceDrop:
        final listingId = item.payload['listingId'] as String?;
        if (listingId != null && listingId.isNotEmpty) {
          route = '/marketplace/listing/$listingId';
        } else {
          route = '/marketplace';
          isGoRoute = true;
        }
        break;

      // ── Real Estate ──
      case NotificationType.realEstateInquiry:
        final chatId = item.payload['chatId'] as String?;
        if (chatId != null && chatId.isNotEmpty) {
          route = '/chats/$chatId';
        } else {
          route = '/dsp/real-estate/buy';
        }
        shouldCompleteAction = true;
        break;
      case NotificationType.realEstateMatch:
      case NotificationType.realEstatePriceChange:
      case NotificationType.realEstateStatusChange:
        route = '/dsp/real-estate/buy';
        break;

      // ── Trust & Verification ──
      case NotificationType.trustPeerVerified:
      case NotificationType.trustPeerVouched:
      case NotificationType.trustFullTrustReceived:
      case NotificationType.trustNoTrustReceived:
      case NotificationType.trustStakeConsensusAgree:
      case NotificationType.trustStakeConsensusDisagree:
        final fromUserId =
            (item.payload['fromUserId'] ?? item.payload['userId']) as String?;
        if (fromUserId != null && fromUserId.isNotEmpty) {
          route = '/profile/$fromUserId';
        }
        break;
      case NotificationType.trustMilestone:
        break;

      // ── Community ──
      case NotificationType.communityJoined:
      case NotificationType.communityNewMember:
        route = '/communities';
        isGoRoute = true;
        break;

      // ── Organization ──
      case NotificationType.orgInvitation:
      case NotificationType.orgAnnouncement:
        break;

      // ── Emergency Fund ──
      case NotificationType.emergencyFundStaked:
      case NotificationType.emergencyFundPaymentSuccess:
      case NotificationType.emergencyFundMembershipActive:
      case NotificationType.emergencyFundDspRefunded:
        route = '/dsp/emergency-fund';
        break;

      case NotificationType.system:
        break;
    }

    if (shouldCompleteAction && item.actionRequired && !item.actionCompleted) {
      setState(() {
        _optimisticCompletedIds.add(item.id);
      });
      if (userId != null) {
        unawaited(
          ref
              .read(notificationsRepositoryProvider)
              .markActionCompleted(userId, item.id),
        );
      }
    }

    if (route != null && mounted) {
      if (isGoRoute) {
        context.go(route);
      } else {
        context.push(route);
      }
    }
  }

  void _handleAction(NotificationItem item, String action) {
    final userId = ref.read(authRepositoryProvider).currentUser?.uid;
    if (userId == null) return;

    String? route;
    bool isGoRoute = false;
    bool markCompleted = false;

    switch (action) {
      case 'select_host':
        _selectHost(item);
        return;
      case 'reject_host':
        _rejectHost(item);
        return;
      case 'view_chat':
        final chatId = item.payload['chatId'] as String?;
        if (chatId != null && chatId.isNotEmpty) {
          route = '/chats/$chatId';
        }
        markCompleted = true;
        break;
      case 'view_profile':
        final profileId =
            item.payload['fromUserId'] as String? ??
            item.payload['hostId'] as String?;
        if (profileId != null && profileId.isNotEmpty) {
          route = '/profile/$profileId';
        }
        break;
      case 'view_event':
        final eventId = item.payload['eventId'] as String?;
        if (eventId != null && eventId.isNotEmpty) {
          route = '/events/$eventId';
        }
        markCompleted = true;
        break;
      case 'view_listing':
        final listingId = item.payload['listingId'] as String?;
        if (listingId != null && listingId.isNotEmpty) {
          route = '/marketplace/listing/$listingId';
        }
        markCompleted = true;
        break;
      case 'view_election':
        route = '/communities';
        isGoRoute = true;
        markCompleted = true;
        break;
      case 'dismiss':
        _dismissNotification(item);
        return;
    }

    if (markCompleted) {
      setState(() {
        _optimisticCompletedIds.add(item.id);
        _optimisticReadIds.add(item.id);
      });
      unawaited(
        ref
            .read(notificationsRepositoryProvider)
            .markActionCompleted(userId, item.id),
      );
    }

    if (route != null && mounted) {
      if (isGoRoute) {
        context.go(route);
      } else {
        context.push(route);
      }
    }
  }

  Future<void> _selectHost(NotificationItem item) async {
    final userId = ref.read(authRepositoryProvider).currentUser?.uid;
    if (userId == null) return;

    final requestId = item.payload['requestId'] as String?;
    final hostId = item.payload['hostId'] as String?;
    if (requestId == null || hostId == null) {
      debugPrint(
        'Error selecting host: missing requestId=$requestId or hostId=$hostId',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Invalid notification data. Please dismiss this notification.',
            ),
          ),
        );
      }
      return;
    }

    // Optimistically mark notification completed on frame 0
    setState(() {
      _optimisticCompletedIds.add(item.id);
      _optimisticReadIds.add(item.id);
    });
    unawaited(
      ref
          .read(notificationsRepositoryProvider)
          .markActionCompleted(userId, item.id),
    );

    final profileRepo = ref.read(profileRepositoryProvider);
    final cachedHostProfile = profileRepo.getCachedProfile(hostId);
    final hostDisplayName =
        cachedHostProfile?.fullName ??
        (item.payload['hostName'] as String?) ??
        'Host';

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$hostDisplayName selected as your host!')),
      );
    }

    try {
      final hostingRepo = ref.read(hostingRepositoryProvider);
      final chatRepo = ref.read(chatRepositoryProvider);

      // Fetch request, host profile, and create/find DM concurrently
      final results = await Future.wait([
        hostingRepo.getRequest(requestId),
        cachedHostProfile != null
            ? Future.value(cachedHostProfile)
            : profileRepo.getUserProfile(hostId),
        chatRepo.createDirectChat(hostId),
      ]);

      final request = results[0] as HostingRequest?;
      final hostProfile = results[1] as ProfileData?;
      final chat = results[2] as dynamic;

      if (request == null) {
        throw Exception(
          'This hosting request no longer exists. It may have expired.',
        );
      }
      if (hostProfile == null) {
        throw Exception('Could not load host profile.');
      }
      if (chat == null) {
        throw Exception('Could not create chat with host.');
      }

      final targetChatId = chat.id as String;
      if (mounted) {
        context.push('/chats/$targetChatId');
      }

      // Run arrangement confirmation and system message in background
      final hostingService = ref.read(hostingServiceProvider);
      unawaited(
        () async {
          try {
            final session = await hostingService.confirmArrangement(
              request: request,
              hostId: hostId,
              hostName: hostProfile.fullName,
              hostPhoto: hostProfile.profileImage,
              chatId: targetChatId,
            );
            if (session != null) {
              await chatRepo.sendTextMessage(
                targetChatId,
                '🏠 Hosting arrangement confirmed! '
                '${request.travelerName} will be hosted by ${hostProfile.fullName} '
                'from ${_formatDate(request.arrivalDate)} to ${_formatDate(request.departureDate)}. '
                'Use this chat to coordinate the details.',
                type: 'system',
                senderIdOverride: 'system',
                senderNameOverride: 'Hosting',
                metadata: {
                  'systemType': 'hosting_arrangement',
                  'sessionId': session.id,
                  'requestId': request.id,
                  'travelerId': request.travelerId,
                  'travelerName': request.travelerName,
                  'travelerPhoto': request.travelerPhoto,
                  'hostId': hostId,
                  'hostName': hostProfile.fullName,
                  'hostPhoto': hostProfile.profileImage,
                  'communityName': request.communityName,
                  'arrivalDate': request.arrivalDate.toIso8601String(),
                  'departureDate': request.departureDate.toIso8601String(),
                  'stayDuration': request.stayDuration,
                },
              );
            }
          } catch (e) {
            debugPrint('Background error confirming arrangement: $e');
          }
        }(),
      );
    } catch (e) {
      debugPrint('Error selecting host: $e');
      if (mounted) {
        setState(() {
          _optimisticCompletedIds.remove(item.id);
        });
        final message = e is Exception
            ? e.toString().replaceFirst('Exception: ', '')
            : 'Something went wrong. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _rejectHost(NotificationItem item) async {
    final userId = ref.read(authRepositoryProvider).currentUser?.uid;
    if (userId == null) return;

    // Optimistically mark completed and show feedback immediately on frame 0
    setState(() {
      _optimisticCompletedIds.add(item.id);
      _optimisticReadIds.add(item.id);
    });
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Host declined')));
    }

    final requestId = item.payload['requestId'] as String?;
    final hostId = item.payload['hostId'] as String?;
    if (requestId == null || hostId == null) {
      unawaited(
        ref
            .read(notificationsRepositoryProvider)
            .markActionCompleted(userId, item.id),
      );
      return;
    }

    unawaited(
      Future.wait([
        ref.read(hostingRepositoryProvider).withdrawInterest(requestId, hostId),
        ref
            .read(notificationsRepositoryProvider)
            .markActionCompleted(userId, item.id),
      ]).catchError((Object e) {
        debugPrint('Error rejecting host: $e');
        return <void>[];
      }),
    );
  }

  void _dismissNotification(NotificationItem item) {
    final userId = ref.read(authRepositoryProvider).currentUser?.uid;
    if (userId == null) return;
    setState(() {
      _optimisticDeletedIds.add(item.id);
    });
    unawaited(
      ref
          .read(notificationsRepositoryProvider)
          .deleteNotification(userId, item.id),
    );
  }

  Future<void> _markAllRead() async {
    final userId = ref.read(authRepositoryProvider).currentUser?.uid;
    if (userId == null) return;
    setState(() {
      _optimisticMarkedAllRead = true;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All notifications marked as read')),
      );
    }
    unawaited(
      ref
          .read(notificationsRepositoryProvider)
          .markAllAsRead(userId)
          .catchError((Object e) {
            if (mounted) {
              setState(() {
                _optimisticMarkedAllRead = false;
              });
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Error marking read: $e')));
            }
          }),
    );
  }

  void _clearAll() {
    final userId = ref.read(authRepositoryProvider).currentUser?.uid;
    if (userId == null) return;

    showDialog(
      context: context,
      builder: (dialogContext) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
          title: const Text('Clear all notifications?'),
          content: const Text('This cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                setState(() {
                  _optimisticClearedAll = true;
                });
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('All notifications cleared')),
                  );
                }
                unawaited(
                  ref
                      .read(notificationsRepositoryProvider)
                      .clearAll(userId)
                      .catchError((Object e) {
                        if (mounted) {
                          setState(() {
                            _optimisticClearedAll = false;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error clearing notifications: $e'),
                            ),
                          );
                        }
                      }),
                );
              },
              child: const Text(
                'Clear',
                style: TextStyle(color: AppTheme.error),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return DateFormat('MMM d, yyyy').format(dt);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notification Card Widget
// ─────────────────────────────────────────────────────────────────────────────

class _NotificationCard extends StatelessWidget {
  final NotificationItem item;
  final bool isDark;
  final VoidCallback onTap;
  final void Function(String action) onAction;
  final VoidCallback onDismiss;

  const _NotificationCard({
    required this.item,
    required this.isDark,
    required this.onTap,
    required this.onAction,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = item.isRead
        ? Colors.transparent
        : (isDark
              ? AppTheme.accent.withValues(alpha: 0.06)
              : AppTheme.accent.withValues(alpha: 0.04));

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismiss(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppTheme.error.withValues(alpha: 0.1),
        child: const Icon(LucideIcons.trash2, color: AppTheme.error, size: 20),
      ),
      child: InkWell(
        onTap: onTap,
        child: Container(
          color: bgColor,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Icon ──
              _buildIcon(),
              const SizedBox(width: 14),

              // ── Content ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title row
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: item.isRead
                                  ? FontWeight.w500
                                  : FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          timeago.format(item.createdAt, allowFromNow: true),
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Body
                    Text(
                      item.body,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.6),
                        height: 1.4,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),

                    // ── Action buttons ──
                    if (item.actionRequired && !item.actionCompleted) ...[
                      const SizedBox(height: 10),
                      _buildActionButtons(context),
                    ],

                    // ── Completed badge ──
                    if (item.actionRequired && item.actionCompleted) ...[
                      const SizedBox(height: 8),
                      const Row(
                        children: [
                          Icon(
                            LucideIcons.checkCircle,
                            size: 14,
                            color: AppTheme.success,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Completed',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.success,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Type-specific icon ───────────────────────────────────────────────

  Widget _buildIcon() {
    final config = _iconConfig;
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: config.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Icon(
          config.icon,
          size: 20,
          color: config.color.withValues(alpha: 0.7),
        ),
      ),
    );
  }

  _IconConfig get _iconConfig {
    switch (item.type) {
      case NotificationType.hostingInterest:
        return const _IconConfig(LucideIcons.planeTakeoff, AppTheme.accent);
      case NotificationType.hostingSelected:
        return const _IconConfig(LucideIcons.checkCircle, AppTheme.success);
      case NotificationType.hostingSessionEvent:
        return const _IconConfig(LucideIcons.calendarCheck, AppTheme.info);
      case NotificationType.relationshipRequest:
        return const _IconConfig(LucideIcons.userPlus, AppTheme.accent);
      case NotificationType.relationshipAccepted:
        return const _IconConfig(LucideIcons.userCheck, AppTheme.success);
      case NotificationType.groupInvitation:
        return const _IconConfig(LucideIcons.users, AppTheme.info);
      case NotificationType.proxyRequest:
        return const _IconConfig(LucideIcons.shield, AppTheme.warning);
      case NotificationType.dspTransfer:
        return const _IconConfig(LucideIcons.coins, AppTheme.warning);

      // ── Travel / Peer Bookings ──
      case NotificationType.travelBookingRequest:
        return const _IconConfig(LucideIcons.calendarPlus, AppTheme.accent);
      case NotificationType.travelBookingConfirmed:
        return const _IconConfig(LucideIcons.calendarCheck, AppTheme.success);
      case NotificationType.travelBookingDeclined:
        return const _IconConfig(LucideIcons.calendarX, AppTheme.error);
      case NotificationType.travelBookingCancelled:
        return const _IconConfig(LucideIcons.calendarX, AppTheme.warning);
      case NotificationType.travelTripReminder:
        return const _IconConfig(LucideIcons.alarmClock, AppTheme.info);

      // ── Events ──
      case NotificationType.eventNew:
        return const _IconConfig(LucideIcons.partyPopper, AppTheme.accent);
      case NotificationType.eventReminder:
        return const _IconConfig(LucideIcons.bellRing, AppTheme.warning);
      case NotificationType.eventUpdate:
        return const _IconConfig(LucideIcons.refreshCw, AppTheme.info);
      case NotificationType.eventCancelled:
        return const _IconConfig(LucideIcons.calendarX, AppTheme.error);
      case NotificationType.eventNewAttendee:
        return const _IconConfig(LucideIcons.userPlus2, AppTheme.success);

      // ── Governance / Elections ──
      case NotificationType.electionStarted:
        return const _IconConfig(LucideIcons.vote, AppTheme.accent);
      case NotificationType.electionEndingSoon:
        return const _IconConfig(LucideIcons.timer, AppTheme.warning);
      case NotificationType.electionResults:
        return const _IconConfig(LucideIcons.trophy, AppTheme.success);

      // ── Marketplace ──
      case NotificationType.marketplaceInquiry:
        return const _IconConfig(LucideIcons.shoppingBag, AppTheme.accent);
      case NotificationType.marketplaceStatusChange:
        return const _IconConfig(LucideIcons.badgeCheck, AppTheme.info);
      case NotificationType.marketplacePriceDrop:
        return const _IconConfig(LucideIcons.trendingDown, AppTheme.success);

      // ── Real Estate ──
      case NotificationType.realEstateInquiry:
        return const _IconConfig(LucideIcons.building2, AppTheme.accent);
      case NotificationType.realEstateMatch:
        return const _IconConfig(LucideIcons.search, AppTheme.info);
      case NotificationType.realEstatePriceChange:
        return const _IconConfig(LucideIcons.trendingDown, AppTheme.warning);
      case NotificationType.realEstateStatusChange:
        return const _IconConfig(LucideIcons.badgeCheck, AppTheme.info);

      // ── Trust & Verification ──
      case NotificationType.trustPeerVerified:
        return const _IconConfig(LucideIcons.shieldCheck, AppTheme.success);
      case NotificationType.trustPeerVouched:
        return const _IconConfig(LucideIcons.heartHandshake, AppTheme.accent);
      case NotificationType.trustFullTrustReceived:
        return const _IconConfig(LucideIcons.shieldCheck, AppTheme.accent);
      case NotificationType.trustNoTrustReceived:
        return const _IconConfig(LucideIcons.shieldAlert, AppTheme.error);
      case NotificationType.trustStakeConsensusAgree:
        return const _IconConfig(LucideIcons.coins, AppTheme.success);
      case NotificationType.trustStakeConsensusDisagree:
        return const _IconConfig(LucideIcons.shieldAlert, AppTheme.warning);
      case NotificationType.trustMilestone:
        return const _IconConfig(LucideIcons.award, AppTheme.warning);

      // ── Community ──
      case NotificationType.communityJoined:
        return const _IconConfig(LucideIcons.home, AppTheme.success);
      case NotificationType.communityNewMember:
        return const _IconConfig(LucideIcons.userPlus, AppTheme.info);

      // ── Organization ──
      case NotificationType.orgInvitation:
        return const _IconConfig(LucideIcons.building, AppTheme.accent);
      case NotificationType.orgAnnouncement:
        return const _IconConfig(LucideIcons.megaphone, AppTheme.info);

      // ── Emergency Fund ──
      case NotificationType.emergencyFundStaked:
        return const _IconConfig(LucideIcons.coins, AppTheme.warning);
      case NotificationType.emergencyFundPaymentSuccess:
        return const _IconConfig(LucideIcons.creditCard, AppTheme.success);
      case NotificationType.emergencyFundMembershipActive:
        return const _IconConfig(LucideIcons.shieldCheck, AppTheme.success);
      case NotificationType.emergencyFundDspRefunded:
        return const _IconConfig(LucideIcons.refreshCw, AppTheme.info);

      case NotificationType.system:
        return const _IconConfig(LucideIcons.bell, AppTheme.accent);
    }
  }

  // ── Action buttons per type ──────────────────────────────────────────

  Widget _buildActionButtons(BuildContext context) {
    switch (item.type) {
      case NotificationType.hostingInterest:
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _actionChip(
              label: 'Select',
              icon: LucideIcons.checkCircle,
              color: AppTheme.success,
              onTap: () => onAction('select_host'),
            ),
            _actionChip(
              label: 'Reject',
              icon: LucideIcons.xCircle,
              color: AppTheme.error,
              onTap: () => onAction('reject_host'),
            ),
          ],
        );
      case NotificationType.hostingSelected:
      case NotificationType.hostingSessionEvent:
        return Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            _actionChip(
              label: 'View Chat',
              icon: LucideIcons.messageCircle,
              color: AppTheme.info,
              onTap: () => onAction('view_chat'),
            ),
          ],
        );
      case NotificationType.relationshipRequest:
        return Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            _actionChip(
              label: 'View Profile',
              icon: LucideIcons.user,
              color: AppTheme.accent,
              onTap: () => onAction('view_profile'),
            ),
          ],
        );
      case NotificationType.relationshipAccepted:
        return Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            _actionChip(
              label: 'Start Chat',
              icon: LucideIcons.messageCircle,
              color: AppTheme.success,
              onTap: () => onAction('view_chat'),
            ),
          ],
        );
      case NotificationType.groupInvitation:
        return Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            _actionChip(
              label: 'View Group',
              icon: LucideIcons.users,
              color: AppTheme.info,
              onTap: () => onAction('view_chat'),
            ),
          ],
        );
      case NotificationType.proxyRequest:
        return Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            _actionChip(
              label: 'View Request',
              icon: LucideIcons.externalLink,
              color: AppTheme.warning,
              onTap: () => onAction('view_chat'),
            ),
          ],
        );

      // ── Travel / Peer Bookings ──
      case NotificationType.travelBookingRequest:
        return Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            _actionChip(
              label: 'View Booking',
              icon: LucideIcons.calendarCheck,
              color: AppTheme.accent,
              onTap: () => onAction('view_chat'),
            ),
          ],
        );
      case NotificationType.travelBookingConfirmed:
      case NotificationType.travelBookingDeclined:
      case NotificationType.travelBookingCancelled:
        return Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            _actionChip(
              label: 'View Chat',
              icon: LucideIcons.messageCircle,
              color: AppTheme.info,
              onTap: () => onAction('view_chat'),
            ),
          ],
        );

      // ── Events ──
      case NotificationType.eventCancelled:
      case NotificationType.eventUpdate:
      case NotificationType.eventNew:
      case NotificationType.eventReminder:
        return Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            _actionChip(
              label: 'View Event',
              icon: LucideIcons.calendarDays,
              color: AppTheme.accent,
              onTap: () => onAction('view_event'),
            ),
          ],
        );

      // ── Governance / Elections ──
      case NotificationType.electionStarted:
      case NotificationType.electionEndingSoon:
        return Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            _actionChip(
              label: 'Cast Vote',
              icon: LucideIcons.vote,
              color: AppTheme.accent,
              onTap: () => onAction('view_election'),
            ),
          ],
        );

      // ── Marketplace ──
      case NotificationType.marketplaceInquiry:
        return Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            _actionChip(
              label: 'Reply',
              icon: LucideIcons.messageCircle,
              color: AppTheme.accent,
              onTap: () => onAction('view_chat'),
            ),
          ],
        );

      // ── Real Estate ──
      case NotificationType.realEstateInquiry:
        return Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            _actionChip(
              label: 'Reply',
              icon: LucideIcons.messageCircle,
              color: AppTheme.accent,
              onTap: () => onAction('view_chat'),
            ),
          ],
        );

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _actionChip({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconConfig {
  final IconData icon;
  final Color color;
  const _IconConfig(this.icon, this.color);
}
