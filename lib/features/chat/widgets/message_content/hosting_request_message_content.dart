import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'package:diaspora_nearby/features/hosting/models/hosting_request.dart';
import 'package:diaspora_nearby/features/hosting/repository/hosting_repository.dart';
import 'package:diaspora_nearby/features/hosting/services/hosting_service.dart';
import 'package:diaspora_nearby/features/hosting/widgets/interested_hosts_sheet.dart';
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';

/// Rich card rendered inside the community chat when a traveler broadcasts
/// a hosting request. Shows traveler info, travel dates, purpose, and a
/// "Show Interest" button for potential hosts.
class HostingRequestMessageContent extends ConsumerStatefulWidget {
  final Message message;
  final bool isOwn;

  const HostingRequestMessageContent({
    super.key,
    required this.message,
    required this.isOwn,
  });

  @override
  ConsumerState<HostingRequestMessageContent> createState() =>
      _HostingRequestMessageContentState();
}

class _HostingRequestMessageContentState
    extends ConsumerState<HostingRequestMessageContent> {
  final bool _isShowingInterest = false;
  bool _optimisticInterested = false;

  Map<String, dynamic> get _meta => widget.message.metadata ?? {};

  String get _travelerName => _meta['travelerName'] as String? ?? 'Traveler';
  String? get _travelerPhoto => _meta['travelerPhoto'] as String?;
  String? get _travelerFlag => _meta['travelerFlag'] as String?;
  String get _travelerId => _meta['travelerId'] as String? ?? '';
  String? get _purpose => _meta['purpose'] as String?;
  int get _guestCount => (_meta['guestCount'] as int?) ?? 1;
  int get _stayDuration => (_meta['stayDuration'] as int?) ?? 0;
  String? get _requestId => _meta['hostingRequestId'] as String?;

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
    return DateFormat('MMM d, yyyy').format(dt);
  }

  String _countryFlag(String? code) {
    if (code == null || code.length != 2) return '';
    final codeUnits = code.toUpperCase().codeUnits;
    return String.fromCharCodes(codeUnits.map((c) => 0x1F1E6 - 0x41 + c));
  }

  Future<void> _handleShowInterest() async {
    final reqId = _requestId;
    if (reqId == null || reqId.isEmpty) return;

    final trustService = ref.read(trustServiceProvider);
    final hostingService = ref.read(hostingServiceProvider);
    final messenger = ScaffoldMessenger.of(context);

    // Optimistic 0ms update
    setState(() => _optimisticInterested = true);

    unawaited(() async {
      try {
        final trustScore = await trustService.calculateTrustScore(null);
        if (trustScore < 91) {
          if (mounted) {
            setState(() => _optimisticInterested = false);
            messenger.showSnackBar(
              const SnackBar(
                content: Text(
                  'Trust Score of 91+ required to offer Peer Hosting.',
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }

        await hostingService.showInterest(reqId);
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Interest shown! The traveler will be notified.'),
              backgroundColor: AppTheme.accent,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _optimisticInterested = false);
          final message = e is Exception
              ? e.toString().replaceFirst('Exception: ', '')
              : 'Something went wrong. Please try again.';
          messenger.showSnackBar(
            SnackBar(content: Text(message), backgroundColor: Colors.red),
          );
        }
      }
    }());
  }

  @override
  Widget build(BuildContext context) {
    final arrivalDate = _parseDate('arrivalDate');
    final departureDate = _parseDate('departureDate');
    final currentUserId = ref.watch(authStateProvider).value?.uid;
    final isTraveler = currentUserId == _travelerId;

    // Watch the hosting request for live interest count
    final requestAsync = _requestId != null && _requestId!.isNotEmpty
        ? ref.watch(
            communityHostingRequestsProvider(
              _meta['communityId'] as String? ?? '',
            ),
          )
        : null;

    // Find this specific request in the stream
    int interestedCount = 0;
    bool alreadyInterested = _optimisticInterested;
    bool isMatched = false;
    if (requestAsync != null) {
      final requests = requestAsync.value ?? [];
      final thisReq = requests.where((r) => r.id == _requestId).firstOrNull;
      if (thisReq != null) {
        final streamHasMe =
            currentUserId != null &&
            thisReq.interestedHostIds.contains(currentUserId);
        interestedCount =
            thisReq.interestedHostIds.length +
            ((_optimisticInterested && !streamHasMe) ? 1 : 0);
        alreadyInterested = _optimisticInterested || streamHasMe;
        isMatched = thisReq.status != HostingRequestStatus.pending;
      }
    }

    return Container(
      width: 280,
      padding: EdgeInsets.zero,
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
                const Icon(LucideIcons.plane, size: 18, color: AppTheme.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Hosting Request',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        LucideIcons.calendarDays,
                        size: 12,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${_stayDuration}d',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Traveler Info ──────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: GestureDetector(
              onTap: () {
                if (_travelerId.isNotEmpty) {
                  context.push('/profile/$_travelerId');
                }
              },
              child: Row(
                children: [
                  // Avatar
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: AppTheme.accent.withValues(alpha: 0.15),
                    backgroundImage: _travelerPhoto != null
                        ? NetworkImage(_travelerPhoto!)
                        : null,
                    child: _travelerPhoto == null
                        ? const Icon(
                            LucideIcons.user,
                            size: 18,
                            color: AppTheme.accent,
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (_travelerFlag != null &&
                                _travelerFlag!.isNotEmpty) ...[
                              Text(
                                _countryFlag(_travelerFlag),
                                style: const TextStyle(fontSize: 16),
                              ),
                              const SizedBox(width: 4),
                            ],
                            Flexible(
                              child: Text(
                                _travelerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(
                                    context,
                                  ).textTheme.bodyLarge?.color,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Tap to view profile',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.accent.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),

          // ── Divider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Divider(
              height: 1,
              color: AppTheme.accent.withValues(alpha: 0.2),
            ),
          ),

          const SizedBox(height: 10),

          // ── Travel Details ─────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              children: [
                _detailRow(
                  icon: LucideIcons.calendar,
                  label: 'Dates',
                  value:
                      '${_formatDate(arrivalDate)} → ${_formatDate(departureDate)}',
                ),
                const SizedBox(height: 6),
                if (_purpose != null && _purpose!.isNotEmpty) ...[
                  _detailRow(
                    icon: LucideIcons.briefcase,
                    label: 'Purpose',
                    value: _purpose!,
                  ),
                  const SizedBox(height: 6),
                ],
                _detailRow(
                  icon: LucideIcons.users,
                  label: 'Guests',
                  value: '$_guestCount',
                ),
                const SizedBox(height: 6),
                _detailRow(
                  icon: LucideIcons.coins,
                  label: 'Host Earns',
                  value: '${_stayDuration * 10} DSP',
                  valueColor: AppTheme.accent,
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Interested hosts count ─────────────────────────
          if (interestedCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.heart,
                      size: 14,
                      color: AppTheme.accent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$interestedCount host${interestedCount == 1 ? '' : 's'} interested',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).textTheme.bodyMedium?.color,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 10),

          // ── Action Button ──────────────────────────────────
          if (!isTraveler)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: alreadyInterested || _isShowingInterest
                      ? null
                      : _handleShowInterest,
                  icon: _isShowingInterest
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          alreadyInterested
                              ? LucideIcons.checkCircle
                              : LucideIcons.heartHandshake,
                          size: 16,
                        ),
                  label: Text(
                    alreadyInterested ? 'Interest Shown' : 'Show Interest',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: alreadyInterested
                        ? Colors.grey.shade400
                        : AppTheme.accent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade400,
                    disabledForegroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ),

          // ── Traveler actions ───────────────────────────────
          // When request is already matched, show confirmation
          if (isTraveler && isMatched)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      LucideIcons.checkCircle2,
                      size: 14,
                      color: Colors.green.shade700,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Host Selected ✓',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // When still pending and hosts have shown interest
          if (isTraveler && !isMatched && interestedCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    // Find the actual HostingRequest object to pass to the sheet
                    final requests = requestAsync?.value ?? [];
                    final thisReq = requests
                        .where((r) => r.id == _requestId)
                        .firstOrNull;
                    if (thisReq != null) {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: InterestedHostsSheet(request: thisReq),
                        ),
                      );
                    }
                  },
                  icon: const Icon(LucideIcons.users, size: 16),
                  label: Text(
                    'View Interested Hosts ($interestedCount)',
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
            ),

          // ── No interest yet indicator for traveler ─────────
          if (isTraveler && !isMatched && interestedCount == 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.clock, size: 14, color: AppTheme.accent),
                    SizedBox(width: 6),
                    Text(
                      'Waiting for hosts...',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _detailRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
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
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: valueColor ?? Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
        ),
      ],
    );
  }
}
