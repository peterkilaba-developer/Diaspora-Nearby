import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/hosting/repository/hosting_repository.dart';
import 'package:diaspora_nearby/features/hosting/services/hosting_service.dart';
import 'package:diaspora_nearby/features/hosting/models/hosting_session.dart';
import 'package:diaspora_nearby/features/hosting/screens/hosting_qr_screen.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

/// Rich card rendered inside a DM when a hosting arrangement is confirmed.
/// Shows arrangement summary: traveler ↔ host, dates, community, and
/// a status indicator for the session.
class HostingArrangementMessageContent extends ConsumerStatefulWidget {
  final Message message;
  final bool isOwn;

  const HostingArrangementMessageContent({
    super.key,
    required this.message,
    required this.isOwn,
  });

  @override
  ConsumerState<HostingArrangementMessageContent> createState() =>
      _HostingArrangementMessageContentState();
}

class _HostingArrangementMessageContentState
    extends ConsumerState<HostingArrangementMessageContent> {
  bool _isProcessing = false;

  Map<String, dynamic> get _meta => widget.message.metadata ?? {};

  String get _travelerName => _meta['travelerName'] as String? ?? 'Traveler';
  String? get _travelerPhoto => _meta['travelerPhoto'] as String?;
  String get _hostName => _meta['hostName'] as String? ?? 'Host';
  String? get _hostPhoto => _meta['hostPhoto'] as String?;
  String get _communityName => _meta['communityName'] as String? ?? '';
  int get _stayDuration => (_meta['stayDuration'] as int?) ?? 0;
  String? get _sessionId => _meta['sessionId'] as String?;

  DateTime? _parseDate(String key) {
    final raw = _meta[key];
    if (raw == null) return null;
    try {
      return DateTime.parse(raw as String);
    } catch (_) {
      return null;
    }
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    return DateFormat('MMM d').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final arrivalDate = _parseDate('arrivalDate');
    final departureDate = _parseDate('departureDate');
    final currentUserId = ref.watch(authStateProvider).value?.uid;
    final travelerId = _meta['travelerId'] as String? ?? '';
    final hostId = _meta['hostId'] as String? ?? '';
    final isTraveler = currentUserId == travelerId;
    final isHost = currentUserId == hostId;
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    // Watch session for live status
    String sessionStatus = 'confirmed';
    HostingSession? liveSession;
    if (_sessionId != null && currentUserId != null) {
      final sessionAsync = ref.watch(
        activeHostingSessionProvider(currentUserId),
      );
      liveSession = sessionAsync.value;
      if (liveSession != null && liveSession.id == _sessionId) {
        sessionStatus = liveSession.status.name;
      } else {
        liveSession = null;
      }
    }

    return Container(
      width: 280,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.accent.withValues(alpha: 0.08),
            AppTheme.accent.withValues(alpha: 0.15),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accent.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.15),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(15),
                topRight: Radius.circular(15),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  LucideIcons.checkCircle2,
                  size: 18,
                  color: AppTheme.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Hosting Confirmed',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: onSurface,
                    ),
                  ),
                ),
                _statusBadge(sessionStatus, context),
              ],
            ),
          ),

          // ── People Row ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Row(
              children: [
                // Traveler
                Expanded(
                  child: _personColumn(
                    context: context,
                    label: 'Traveler',
                    name: _travelerName,
                    photo: _travelerPhoto,
                    isMe: isTraveler,
                  ),
                ),
                // Arrow
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    LucideIcons.arrowLeftRight,
                    size: 20,
                    color: onSurface.withValues(alpha: 0.5),
                  ),
                ),
                // Host
                Expanded(
                  child: _personColumn(
                    context: context,
                    label: 'Host',
                    name: _hostName,
                    photo: _hostPhoto,
                    isMe: !isTraveler,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Divider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Divider(
              height: 1,
              color: AppTheme.accent.withValues(alpha: 0.2),
            ),
          ),

          const SizedBox(height: 10),

          // ── Details ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              children: [
                _detailRow(
                  context: context,
                  icon: LucideIcons.mapPin,
                  label: 'Community',
                  value: _communityName,
                ),
                const SizedBox(height: 6),
                _detailRow(
                  context: context,
                  icon: LucideIcons.calendar,
                  label: 'Dates',
                  value:
                      '${_formatDate(arrivalDate)} → ${_formatDate(departureDate)} ($_stayDuration days)',
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ── Next Steps ─────────────────────────────────────
          Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            padding: const EdgeInsets.all(10),
            // Use accent-tinted decoration matching the hosting request card
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.info,
                  size: 14,
                  color: onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _nextStepsText(sessionStatus, isTraveler),
                    style: TextStyle(
                      fontSize: 12,
                      color: onSurface.withValues(alpha: 0.5),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Action Buttons ──────────────────────────────────
          _buildActionButtons(
            sessionStatus: sessionStatus,
            isTraveler: isTraveler,
            isHost: isHost,
            session: liveSession,
          ),
        ],
      ),
    );
  }

  Widget _personColumn({
    required BuildContext context,
    required String label,
    required String name,
    String? photo,
    required bool isMe,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: AppTheme.accent.withValues(alpha: 0.15),
          backgroundImage: photo != null && photo.isNotEmpty
              ? NetworkImage(photo)
              : null,
          child: photo == null || photo.isEmpty
              ? const Icon(LucideIcons.user, size: 18, color: AppTheme.accent)
              : null,
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: onSurface.withValues(alpha: 0.5),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          isMe ? 'You' : name.split(' ').first,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: onSurface,
          ),
        ),
      ],
    );
  }

  Widget _detailRow({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: AppTheme.accent),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: onSurface.withValues(alpha: 0.5),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: valueColor ?? onSurface,
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusBadge(String status, BuildContext context) {
    final Color color;
    final IconData icon;
    final String text;

    switch (status) {
      case 'active':
        color = AppTheme.accent;
        icon = LucideIcons.activity;
        text = 'Active';
        break;
      case 'endRequested':
        color = AppTheme.accent;
        icon = LucideIcons.clock;
        text = 'Ending';
        break;
      case 'ended':
        color = AppTheme.accent;
        icon = LucideIcons.coins;
        text = 'Settle';
        break;
      case 'settled':
        color = AppTheme.accent;
        icon = LucideIcons.checkCircle;
        text = 'Settled';
        break;
      case 'completed':
        color = AppTheme.accentDark;
        icon = LucideIcons.checkCircle2;
        text = 'Complete';
        break;
      case 'cancelled':
        color = AppTheme.error;
        icon = LucideIcons.xCircle;
        text = 'Cancelled';
        break;
      default: // confirmed
        color = AppTheme.accent;
        icon = LucideIcons.clock;
        text = 'Pending';
        break;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  String _nextStepsText(String status, bool isTraveler) {
    switch (status) {
      case 'active':
        return 'Stay is active! When ready to end, both parties confirm checkout.';
      case 'completed':
        return 'Stay completed. Thank you for using Diaspora hosting!';
      case 'cancelled':
        return 'This arrangement was cancelled.';
      default:
        if (isTraveler) {
          return 'Coordinate your arrival details here. On arrival day, use QR check-in to activate your stay.';
        }
        return 'Coordinate with your guest here. On their arrival day, use QR check-in to start the hosting session.';
    }
  }

  // =========================================================================
  // ACTION BUTTONS
  // =========================================================================

  Widget _buildActionButtons({
    required String sessionStatus,
    required bool isTraveler,
    required bool isHost,
    HostingSession? session,
  }) {
    // No actions for settled/cancelled/completed sessions or non-participants
    if (session == null ||
        sessionStatus == 'settled' ||
        sessionStatus == 'cancelled') {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        children: [
          Divider(height: 1, color: AppTheme.accent.withValues(alpha: 0.2)),
          const SizedBox(height: 10),

          // ── CONFIRMED: Show QR Check-in button ──
          if (sessionStatus == 'confirmed')
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isProcessing
                    ? null
                    : () => _openQRScreen(session, isHost),
                icon: Icon(
                  isHost ? LucideIcons.qrCode : LucideIcons.camera,
                  size: 16,
                ),
                label: Text(
                  isHost ? 'Show Check-in QR' : 'Scan to Check In',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
              ),
            ),

          // ── ACTIVE: Show End Stay button ──
          if (sessionStatus == 'active')
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isProcessing
                    ? null
                    : () => _requestEndStay(session),
                icon: const Icon(LucideIcons.logOut, size: 16),
                label: Text(
                  _isProcessing ? 'Processing...' : 'End Stay',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
              ),
            ),

          // ── END REQUESTED: Confirm end or waiting ──
          if (sessionStatus == 'endRequested') ...[
            if (session.endRequestedBy != null &&
                ((isTraveler && session.endRequestedBy == session.travelerId) ||
                    (isHost && session.endRequestedBy == session.hostId)))
              // This user requested the end — waiting for the other
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    'Waiting for ${isTraveler ? 'host' : 'traveler'} to confirm...',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.accent,
                    ),
                  ),
                ),
              )
            else
              // Other party requested end — show confirm button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isProcessing
                      ? null
                      : () => _settleSession(session),
                  icon: const Icon(LucideIcons.checkCircle, size: 16),
                  label: Text(
                    _isProcessing ? 'Processing...' : 'Confirm End of Stay',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
          ],

          // ── ENDED: Complete Session ──
          if (sessionStatus == 'ended')
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isProcessing ? null : () => _settleSession(session),
                icon: const Icon(LucideIcons.checkCircle, size: 16),
                label: Text(
                  _isProcessing ? 'Processing...' : 'Complete Stay',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── ACTION HANDLERS ─────────────────────────────────────

  void _openQRScreen(HostingSession session, bool isHost) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HostingQRScreen(session: session, isHost: isHost),
      ),
    );
  }

  Future<void> _requestEndStay(HostingSession session) async {
    // Confirm with a dialog first
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'End Stay?',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Are you sure you want to end this stay? '
          'The other party will need to confirm to complete the session.',
          style: TextStyle(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
            ),
            child: const Text('End Stay'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isProcessing = true);

    try {
      final hostingService = ref.read(hostingServiceProvider);
      final success = await hostingService.requestEndStay(session.id);

      if (!mounted) return;

      if (success) {
        // Send a DM system message
        await _sendEndRequestMessage(session);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('End stay requested. Waiting for confirmation.'),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to request end stay.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error requesting end stay.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _settleSession(HostingSession session) async {
    setState(() => _isProcessing = true);

    try {
      final hostingService = ref.read(hostingServiceProvider);
      final success = await hostingService.settleSession(session.id);

      if (!mounted) return;

      if (success) {
        // Send a DM system message about settlement
        await _sendSettlementMessage(session);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Hosting session completed successfully!'),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to complete session. Please try again.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error during settlement.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── DM Notification Messages ──────────────────────────────

  Future<void> _sendEndRequestMessage(HostingSession session) async {
    final chatId = session.chatId;
    if (chatId == null || chatId.isEmpty) return;
    try {
      final chatRepo = ref.read(chatRepositoryProvider);
      await chatRepo.sendTextMessage(
        chatId,
        'End of stay requested. Waiting for both parties to confirm checkout.',
        type: 'system',
        senderIdOverride: 'system',
        senderNameOverride: 'Hosting',
      );
    } catch (e) {
      debugPrint('[Hosting] Failed to send end-request message: $e');
    }
  }

  Future<void> _sendSettlementMessage(HostingSession session) async {
    final chatId = session.chatId;
    if (chatId == null || chatId.isEmpty) return;
    try {
      final chatRepo = ref.read(chatRepositoryProvider);
      final days = session.actualDays ?? session.stayDurationDays ?? 1;
      await chatRepo.sendTextMessage(
        chatId,
        'Hosting session complete! $days day${days > 1 ? 's' : ''} of hosting. Thank you for using Diaspora Hosting!',
        type: 'system',
        senderIdOverride: 'system',
        senderNameOverride: 'Hosting',
      );
    } catch (e) {
      debugPrint('[Hosting] Failed to send settlement message: $e');
    }
  }
}
