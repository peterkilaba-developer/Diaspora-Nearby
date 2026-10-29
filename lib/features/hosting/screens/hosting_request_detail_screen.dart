import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import 'package:diaspora_nearby/features/hosting/models/hosting_request.dart';
import 'package:diaspora_nearby/features/hosting/repository/hosting_repository.dart';
import 'package:diaspora_nearby/features/hosting/widgets/interested_hosts_sheet.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

/// Standalone screen for viewing a hosting request and its interested hosts.
/// Navigated to from push notifications so the traveler can review and select
/// a host without needing access to the community chat.
class HostingRequestDetailScreen extends ConsumerStatefulWidget {
  final String requestId;
  final HostingRequest? initialRequest;

  const HostingRequestDetailScreen({
    super.key,
    required this.requestId,
    this.initialRequest,
  });

  @override
  ConsumerState<HostingRequestDetailScreen> createState() =>
      _HostingRequestDetailScreenState();
}

class _HostingRequestDetailScreenState
    extends ConsumerState<HostingRequestDetailScreen> {
  HostingRequest? _request;
  bool _isLoading = true;
  String? _error;
  bool _autoOpenedSheet = false;

  @override
  void initState() {
    super.initState();
    // [PERF] Seed synchronously from route extra or repository cache for 0ms render
    _request =
        widget.initialRequest ??
        ref.read(hostingRepositoryProvider).getCachedRequest(widget.requestId);
    _isLoading = _request == null;

    if (_request != null &&
        _request!.interestedHostIds.isNotEmpty &&
        _request!.isOpen) {
      _autoOpenedSheet = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showInterestedHosts(_request!);
      });
    }

    _loadRequest();
  }

  Future<void> _loadRequest() async {
    try {
      final request = await ref
          .read(hostingRepositoryProvider)
          .getRequest(widget.requestId, force: true);
      if (mounted) {
        setState(() {
          if (request != null) {
            _request = request;
          }
          _isLoading = false;
          if (_request == null) {
            _error = 'Hosting request not found';
          }
        });

        // Auto-open the interested hosts sheet if there are interested hosts
        if (!_autoOpenedSheet &&
            _request != null &&
            _request!.interestedHostIds.isNotEmpty &&
            _request!.isOpen) {
          _autoOpenedSheet = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showInterestedHosts(_request!);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (_request == null) {
            _error = 'Failed to load request: $e';
          }
        });
      }
    }
  }

  void _showInterestedHosts(HostingRequest request) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => InterestedHostsSheet(request: request),
    );
  }

  String _formatDate(DateTime dt) {
    return DateFormat('MMM d, yyyy').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Hosting Request',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: _isLoading && _request == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _request == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    LucideIcons.alertCircle,
                    size: 48,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      fontSize: 15,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            )
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    final request = _request!;
    final isMatched =
        request.status == HostingRequestStatus.matched ||
        request.status == HostingRequestStatus.active ||
        request.status == HostingRequestStatus.completed;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Status badge
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _statusIcon(request.status),
                size: 16,
                color: _statusColor(request.status),
              ),
              const SizedBox(width: 6),
              Text(
                _statusLabel(request.status),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _statusColor(request.status),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Community
          _infoRow(
            LucideIcons.heartHandshake,
            'Community',
            request.communityName,
          ),
          const SizedBox(height: 12),

          // ── Travel dates
          _infoRow(
            LucideIcons.calendar,
            'Dates',
            '${_formatDate(request.arrivalDate)} → ${_formatDate(request.departureDate)}',
          ),
          const SizedBox(height: 12),

          // ── Duration
          _infoRow(
            LucideIcons.clock,
            'Duration',
            '${request.stayDuration} day${request.stayDuration == 1 ? '' : 's'}',
          ),
          const SizedBox(height: 12),

          // ── Purpose
          if (request.purpose != null) ...[
            _infoRow(LucideIcons.briefcase, 'Purpose', request.purpose!),
            const SizedBox(height: 12),
          ],

          // ── Guests
          if (request.guestCount != null && request.guestCount! > 1) ...[
            _infoRow(LucideIcons.users, 'Guests', '${request.guestCount}'),
            const SizedBox(height: 12),
          ],

          // ── Notes
          if (request.notes != null && request.notes!.isNotEmpty) ...[
            _infoRow(LucideIcons.messageSquare, 'Notes', request.notes!),
            const SizedBox(height: 12),
          ],

          // ── Matched host
          if (isMatched && request.matchedHostName != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.checkCircle,
                    size: 20,
                    color: AppTheme.accent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Host selected: ${request.matchedHostName}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Interested hosts section
          if (request.isOpen) ...[
            const SizedBox(height: 28),
            const Text(
              'Interested Hosts',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),

            if (request.interestedHostIds.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Icon(
                      LucideIcons.heartOff,
                      size: 36,
                      color: AppTheme.accent.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No hosts have shown interest yet',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _showInterestedHosts(request),
                  icon: const Icon(LucideIcons.users, size: 18),
                  label: Text(
                    'View ${request.interestedHostIds.length} Interested Host${request.interestedHostIds.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppTheme.accent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.5),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 14)),
            ],
          ),
        ),
      ],
    );
  }

  Color _statusColor(HostingRequestStatus status) {
    switch (status) {
      case HostingRequestStatus.pending:
        return AppTheme.accent;
      case HostingRequestStatus.matched:
        return AppTheme.info;
      case HostingRequestStatus.active:
        return AppTheme.accent;
      case HostingRequestStatus.completed:
        return AppTheme.accentDark;
      case HostingRequestStatus.cancelled:
        return AppTheme.error;
      case HostingRequestStatus.expired:
        return AppTheme.accentLight;
    }
  }

  String _statusLabel(HostingRequestStatus status) {
    switch (status) {
      case HostingRequestStatus.pending:
        return 'Looking for Hosts';
      case HostingRequestStatus.matched:
        return 'Host Matched';
      case HostingRequestStatus.active:
        return 'Active Stay';
      case HostingRequestStatus.completed:
        return 'Completed';
      case HostingRequestStatus.cancelled:
        return 'Cancelled';
      case HostingRequestStatus.expired:
        return 'Expired';
    }
  }

  IconData _statusIcon(HostingRequestStatus status) {
    switch (status) {
      case HostingRequestStatus.pending:
        return LucideIcons.search;
      case HostingRequestStatus.matched:
        return LucideIcons.heartHandshake;
      case HostingRequestStatus.active:
        return LucideIcons.home;
      case HostingRequestStatus.completed:
        return LucideIcons.checkCircle;
      case HostingRequestStatus.cancelled:
        return LucideIcons.xCircle;
      case HostingRequestStatus.expired:
        return LucideIcons.clock;
    }
  }
}
