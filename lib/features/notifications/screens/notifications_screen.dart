import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:intl/intl.dart';

import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/hosting/services/hosting_service.dart';
import 'package:diaspora_nearby/features/notifications/models/notification_item.dart';
import 'package:diaspora_nearby/features/notifications/providers/notification_count_provider.dart';
import 'package:diaspora_nearby/features/notifications/repository/notifications_repository.dart';
import 'package:diaspora_nearby/features/hosting/repository/hosting_repository.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notificationsAsync = ref.watch(notificationsStreamProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Notifications',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(LucideIcons.moreVertical, size: 20),
            onSelected: (value) {
              if (value == 'mark_all_read') _markAllRead();
              if (value == 'clear_all') _clearAll();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'mark_all_read',
                child: Text('Mark all as read'),
              ),
              const PopupMenuItem(
                value: 'clear_all',
                child: Text('Clear all'),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelStyle: GoogleFonts.outfit(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          unselectedLabelStyle: GoogleFonts.outfit(
            fontWeight: FontWeight.w400,
            fontSize: 14,
          ),
          indicatorColor: Theme.of(context).colorScheme.onSurface,
          labelColor: Theme.of(context).colorScheme.onSurface,
          unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.alertCircle, size: 16),
                  const SizedBox(width: 6),
                  const Text('Action Required'),
                  _buildBadge(notificationsAsync),
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
      body: notificationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) {
          debugPrint('❌ Notifications error: $e\n$st');
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.alertTriangle, size: 40, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)),
                  const SizedBox(height: 12),
                  Text(
                    'Error loading notifications',
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$e',
                    style: GoogleFonts.outfit(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => ref.invalidate(notificationsStreamProvider),
                    icon: const Icon(LucideIcons.refreshCw, size: 16),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        },
        data: (allNotifications) {
          final actionRequired = allNotifications
              .where((n) => n.actionRequired && !n.actionCompleted)
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

              // Tab 2: All Notifications
              allNotifications.isEmpty
                  ? _buildEmptyState(
                      icon: LucideIcons.bellOff,
                      title: 'No notifications yet',
                      subtitle: 'You\'ll see activity here',
                    )
                  : _buildList(allNotifications, isDark),
            ],
          );
        },
      ),
    );
  }

  // ── Badge on the Action Required tab ─────────────────────────────────

  Widget _buildBadge(AsyncValue<List<NotificationItem>> async) {
    final count = async.valueOrNull
            ?.where((n) => n.actionRequired && !n.actionCompleted)
            .length ??
        0;
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Text(
        '$count',
        style: GoogleFonts.outfit(
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
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15)),
          const SizedBox(height: 12),
          Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }

  // ── Notification list ────────────────────────────────────────────────

  Widget _buildList(List<NotificationItem> items, bool isDark) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, __) => Divider(
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
    // Mark as read
    final userId = ref.read(authRepositoryProvider).currentUser?.uid;
    if (userId != null) {
      ref.read(notificationsRepositoryProvider).markAsRead(userId, item.id);
    }

    // Navigate based on type
    switch (item.type) {
      case NotificationType.hostingInterest:
        // Tap card → open the host's full profile
        final hostId = item.payload['hostId'] as String?;
        if (hostId != null) {
          context.push('/profile/$hostId');
        }
        break;
      case NotificationType.hostingSelected:
      case NotificationType.hostingSessionEvent:
        final chatId = item.payload['chatId'] as String?;
        if (chatId != null) {
          context.push('/chats/$chatId');
        }
        break;
      case NotificationType.relationshipRequest:
        final fromUserId = item.payload['fromUserId'] as String?;
        final requestId = item.payload['requestId'] as String?;
        if (fromUserId != null) {
          context.push('/profile/$fromUserId?requestId=${requestId ?? ''}&action=review');
        }
        break;
      case NotificationType.relationshipAccepted:
        final chatId = item.payload['chatId'] as String?;
        if (chatId != null) {
          context.push('/chats/$chatId');
        }
        break;
      case NotificationType.groupInvitation:
        final chatId = item.payload['chatId'] as String?;
        if (chatId != null) {
          context.push('/chats/$chatId/info');
        }
        break;
      case NotificationType.proxyRequest:
        context.push('/dsp/emergency-fund');
        break;
      case NotificationType.dspTransfer:
        final chatId = item.payload['chatId'] as String?;
        if (chatId != null) {
          context.push('/chats/$chatId');
        } else {
          context.push('/dsp/points');
        }
        break;
      case NotificationType.system:
        break;
    }
  }

  void _handleAction(NotificationItem item, String action) {
    final userId = ref.read(authRepositoryProvider).currentUser?.uid;
    if (userId == null) return;

    switch (action) {
      case 'select_host':
        _selectHost(item);
        break;
      case 'reject_host':
        _rejectHost(item);
        break;
      case 'view_chat':
        final chatId = item.payload['chatId'] as String?;
        if (chatId != null) context.push('/chats/$chatId');
        ref
            .read(notificationsRepositoryProvider)
            .markActionCompleted(userId, item.id);
        break;
      case 'view_profile':
        final profileId = item.payload['fromUserId'] as String? ??
            item.payload['hostId'] as String?;
        if (profileId != null) context.push('/profile/$profileId');
        break;
      case 'dismiss':
        _dismissNotification(item);
        break;
    }
  }

  Future<void> _selectHost(NotificationItem item) async {
    final userId = ref.read(authRepositoryProvider).currentUser?.uid;
    if (userId == null) return;

    final requestId = item.payload['requestId'] as String?;
    final hostId = item.payload['hostId'] as String?;
    final hostName = item.payload['hostName'] as String? ?? 'Host';
    if (requestId == null || hostId == null) {
      debugPrint('Error selecting host: missing requestId=$requestId or hostId=$hostId');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid notification data. Please dismiss this notification.')),
        );
      }
      return;
    }

    try {
      // 1. Fetch the full hosting request
      final request = await ref.read(hostingRepositoryProvider).getRequest(requestId);
      if (request == null) {
        throw Exception('This hosting request no longer exists. It may have expired.');
      }

      // 2. Fetch host profile
      final hostProfile = await ref
          .read(profileRepositoryProvider)
          .getUserProfile(hostId);
      if (hostProfile == null) {
        throw Exception('Could not load host profile.');
      }

      // 3. Create/find DM between traveler and host
      final chatRepo = ref.read(chatRepositoryProvider);
      final chat = await chatRepo.createDirectChat(hostId);
      if (chat == null) {
        throw Exception('Could not create chat with host.');
      }

      // 4. Confirm arrangement (creates session, updates request to matched + active)
      final session = await ref.read(hostingServiceProvider).confirmArrangement(
        request: request,
        hostId: hostId,
        hostName: hostProfile.fullName,
        hostPhoto: hostProfile.profileImage,
        chatId: chat.id,
      );
      if (session == null) {
        throw Exception('Could not create hosting session. Please try again.');
      }

      // 5. Send arrangement system message to the DM
      await chatRepo.sendTextMessage(
        chat.id,
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

      // 6. Mark notification as completed
      await ref
          .read(notificationsRepositoryProvider)
          .markActionCompleted(userId, item.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${hostProfile.fullName} selected as your host!')),
        );
        // Navigate to the DM
        context.push('/chats/${chat.id}');
      }
    } catch (e) {
      debugPrint('Error selecting host: $e');
      if (mounted) {
        final message = e is Exception
            ? e.toString().replaceFirst('Exception: ', '')
            : 'Something went wrong. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _rejectHost(NotificationItem item) async {
    final userId = ref.read(authRepositoryProvider).currentUser?.uid;
    if (userId == null) return;

    final requestId = item.payload['requestId'] as String?;
    final hostId = item.payload['hostId'] as String?;
    if (requestId == null || hostId == null) {
      debugPrint('Error rejecting host: missing requestId=$requestId or hostId=$hostId');
      // Clear stale notification anyway
      await ref
          .read(notificationsRepositoryProvider)
          .markActionCompleted(userId, item.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notification cleared.')),
        );
      }
      return;
    }

    try {
      // Remove host from interested list
      await ref
          .read(hostingRepositoryProvider)
          .withdrawInterest(requestId, hostId);
      // Mark this notification as completed (dismissed)
      await ref
          .read(notificationsRepositoryProvider)
          .markActionCompleted(userId, item.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Host declined')),
        );
      }
    } catch (e) {
      debugPrint('Error rejecting host: $e');
      // Still clear the notification if the request doesn't exist
      await ref
          .read(notificationsRepositoryProvider)
          .markActionCompleted(userId, item.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Host declined')),
        );
      }
    }
  }

  void _dismissNotification(NotificationItem item) {
    final userId = ref.read(authRepositoryProvider).currentUser?.uid;
    if (userId == null) return;
    ref.read(notificationsRepositoryProvider).deleteNotification(userId, item.id);
  }

  void _markAllRead() {
    final userId = ref.read(authRepositoryProvider).currentUser?.uid;
    if (userId == null) return;
    ref.read(notificationsRepositoryProvider).markAllAsRead(userId);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All notifications marked as read')),
    );
  }

  void _clearAll() {
    final userId = ref.read(authRepositoryProvider).currentUser?.uid;
    if (userId == null) return;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear all notifications?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(notificationsRepositoryProvider).clearAll(userId);
            },
            child: const Text('Clear', style: TextStyle(color: AppTheme.error)),
          ),
        ],
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
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight:
                                  item.isRead ? FontWeight.w500 : FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          timeago.format(item.createdAt, allowFromNow: true),
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Body
                    Text(
                      item.body,
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
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
                      Row(
                        children: [
                          const Icon(
                            LucideIcons.checkCircle,
                            size: 14,
                            color: AppTheme.success,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Completed',
                            style: GoogleFonts.outfit(
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
        child: Icon(config.icon, size: 20, color: config.color.withValues(alpha: 0.7)),
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
                style: GoogleFonts.outfit(
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
