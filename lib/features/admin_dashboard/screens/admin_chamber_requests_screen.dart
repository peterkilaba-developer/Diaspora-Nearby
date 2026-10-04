import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/organization/models/chamber_leadership_request.dart';
import 'package:diaspora_nearby/features/organization/models/chamber_roles.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

/// Stream of all pending leadership requests across all chambers.
final _allPendingRequestsProvider =
    StreamProvider<List<ChamberLeadershipRequest>>((ref) {
      return FirebaseFirestore.instance
          .collection('leadershipRequests')
          .where('status', isEqualTo: ChamberLeadershipRequest.statusPending)
          .limit(200)
          .snapshots()
          .map(
            (snap) =>
                snap.docs
                    .map(
                      (d) => ChamberLeadershipRequest.fromJson(d.id, d.data()),
                    )
                    .toList()
                  ..sort((a, b) {
                    final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
                    final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
                    return bt.compareTo(at); // newest first
                  }),
          );
    });

/// Admin dashboard screen: review pending chamber leadership requests and
/// approve / reject them. Flipping `approved: true` here triggers the
/// `onChamberLeadershipRequestApproved` Cloud Function which performs the
/// actual appointment server-side.
class AdminChamberRequestsScreen extends ConsumerWidget {
  const AdminChamberRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(_allPendingRequestsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chamber Leadership Requests'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: requestsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Error loading requests: $e'),
          ),
        ),
        data: (requests) {
          if (requests.isEmpty) {
            return _buildEmpty(context);
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: requests.length,
            itemBuilder: (context, i) => _RequestCard(request: requests[i]),
          );
        },
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.inbox,
            size: 48,
            color: theme.iconTheme.color?.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          const Text(
            'No pending requests',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'When someone requests a chamber seat, it shows up here.',
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends ConsumerStatefulWidget {
  final ChamberLeadershipRequest request;
  const _RequestCard({required this.request});

  @override
  ConsumerState<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends ConsumerState<_RequestCard> {
  bool _busy = false;

  Future<void> _approve() async {
    final adminUid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (adminUid == null) return;
    setState(() => _busy = true);
    try {
      await FirebaseFirestore.instance
          .collection('leadershipRequests')
          .doc(widget.request.id)
          .update({
            'approved': true,
            'decidedBy': adminUid,
            'decidedAt': FieldValue.serverTimestamp(),
          });
      // The trigger function will flip status to 'approved' and perform
      // the actual appointment server-side. We just removed this card
      // from the pending stream by setting approved=true (status updated
      // by the trigger shortly after).
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Approved — performing appointment for ${ChamberRoles.displayName(widget.request.role)}.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Approve failed: $e')));
      }
    }
  }

  Future<void> _reject() async {
    final adminUid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (adminUid == null) return;

    final note = await _promptNote(context);
    if (note == null) return; // user cancelled

    setState(() => _busy = true);
    try {
      await FirebaseFirestore.instance
          .collection('leadershipRequests')
          .doc(widget.request.id)
          .update({
            'status': ChamberLeadershipRequest.statusRejected,
            'approved': false,
            'decisionNote': note.isEmpty ? null : note,
            'decidedBy': adminUid,
            'decidedAt': FieldValue.serverTimestamp(),
          });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Request rejected.')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Reject failed: $e')));
      }
    }
  }

  Future<String?> _promptNote(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Optional note explaining the decision. Sent to the requester as the rejection reason.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              maxLength: 200,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'e.g. Please build chamber tenure first.',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final req = widget.request;
    final profileAsync = ref.watch(userProfileByIdProvider(req.userId));
    final chamberAsync = ref.watch(_chamberDocProvider(req.chamberId));

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Requester avatar
                profileAsync.when(
                  loading: () => const CircleAvatar(radius: 20),
                  error: (_, _) => const CircleAvatar(
                    radius: 20,
                    child: Icon(LucideIcons.user, size: 18),
                  ),
                  data: (p) {
                    if (p == null) {
                      return const CircleAvatar(
                        radius: 20,
                        child: Icon(LucideIcons.user, size: 18),
                      );
                    }
                    if (p.profileImage.isNotEmpty) {
                      return CircleAvatar(
                        radius: 20,
                        backgroundImage: CachedNetworkImageProvider(
                          p.profileImage,
                        ),
                      );
                    }
                    return CircleAvatar(
                      radius: 20,
                      backgroundColor: AppTheme.accent.withValues(alpha: 0.2),
                      child: Text(
                        p.firstName.isNotEmpty
                            ? p.firstName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: AppTheme.accent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      profileAsync.when(
                        loading: () => const Text('…'),
                        error: (_, _) => Text(req.userId),
                        data: (p) => Text(
                          p == null
                              ? req.userId
                              : '${p.firstName} ${p.lastName}'.trim(),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'wants ${ChamberRoles.displayName(req.role)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: chamberAsync.when(
                    loading: () => const Text('…'),
                    error: (_, _) => Text(req.chamberId),
                    data: (doc) => Text(
                      (doc?.data()?['name'] as String?) ?? req.chamberId,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.accent,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            if (req.message.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  req.message,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                if (req.createdAt != null)
                  Expanded(
                    child: Text(
                      _relativeTime(req.createdAt!),
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  ),
                if (_busy) ...[
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                ],
                OutlinedButton.icon(
                  onPressed: _busy ? null : _reject,
                  icon: const Icon(LucideIcons.x, size: 16),
                  label: const Text('Reject'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.error,
                    side: const BorderSide(color: AppTheme.error),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : _approve,
                  icon: const Icon(LucideIcons.check, size: 16),
                  label: const Text('Approve'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${(diff.inDays / 30).floor()}mo ago';
  }
}

/// Single-shot fetch of a chamber doc by id (used to show the chamber name
/// on each card without re-querying every rebuild).
final _chamberDocProvider =
    FutureProvider.family<DocumentSnapshot<Map<String, dynamic>>?, String>((
      ref,
      orgId,
    ) async {
      return FirebaseFirestore.instance
          .collection('organizations')
          .doc(orgId)
          .get();
    });
