import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/profile/models/relationship_request.dart';
import 'package:diaspora_nearby/features/profile/repository/relationship_repository.dart';
import 'package:diaspora_nearby/features/shared/utils/app_snackbar.dart';

class RelationshipResponseModal extends ConsumerStatefulWidget {
  final RelationshipRequest request;
  final VoidCallback? onAccepted;

  const RelationshipResponseModal({
    super.key,
    required this.request,
    this.onAccepted,
  });

  @override
  ConsumerState<RelationshipResponseModal> createState() =>
      _RelationshipResponseModalState();
}

class _RelationshipResponseModalState
    extends ConsumerState<RelationshipResponseModal> {
  String? _selectedReciprocalType;
  final bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final repository = ref.read(relationshipRepositoryProvider);
    final possibleTypes = repository.getPossibleReciprocalTypes(
      widget.request.relationshipType,
    );

    // Auto-select if only one option and not yet selected
    if (possibleTypes.length == 1 && _selectedReciprocalType == null) {
      _selectedReciprocalType = possibleTypes.first;
    }

    final theme = Theme.of(context);
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: PopScope(
        canPop: true,
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8.0,
              vertical: 24.0,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Sender's profile photo
                Center(
                  child: CircleAvatar(
                    radius: 32,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    backgroundImage:
                        widget.request.fromUserPhoto != null &&
                            widget.request.fromUserPhoto!.isNotEmpty
                        ? NetworkImage(widget.request.fromUserPhoto!)
                        : null,
                    child:
                        widget.request.fromUserPhoto == null ||
                            widget.request.fromUserPhoto!.isEmpty
                        ? Text(
                            widget.request.fromUserName.isNotEmpty
                                ? widget.request.fromUserName[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 24,
                              color: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer,
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Relationship Request',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: Theme.of(context).textTheme.bodyLarge,
                    children: [
                      TextSpan(
                        text: widget.request.fromUserName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const TextSpan(text: ' Wants to add you as '),
                      TextSpan(
                        text: widget.request.relationshipType,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const TextSpan(text: '.'),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Confirm your relationship:',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                if (possibleTypes.length > 1)
                  RadioGroup<String>(
                    groupValue: _selectedReciprocalType,
                    onChanged: (val) =>
                        setState(() => _selectedReciprocalType = val),
                    child: Column(
                      children: possibleTypes
                          .map(
                            (type) => RadioListTile<String>(
                              title: Text(type),
                              value: type,
                              contentPadding: EdgeInsets.zero,
                            ),
                          )
                          .toList(),
                    ),
                  )
                else
                  ListTile(
                    leading: const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                    ),
                    title: Text(_selectedReciprocalType ?? possibleTypes.first),
                    subtitle: const Text('Logical reciprocal relationship'),
                  ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.shield_outlined,
                            size: 18,
                            color: Colors.amber,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Circle of Trust Commitment',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Accepting this relationship directly binds your trust score and economic standing together. If either member incurs DSP or PCT slashing penalties for fraud or misconduct, the identical penalty is deducted from your account. Circle of Trust members are also excluded from Trust Slider staking.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.85,
                          ),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                if (_isLoading)
                  const Center(child: CircularProgressIndicator())
                else
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Later'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed: _selectedReciprocalType == null
                              ? null
                              : _acceptRequest,
                          child: const Text('Confirm & Accept'),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _rejectRequest,
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  child: const Text('Reject Request'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _acceptRequest() async {
    if (_selectedReciprocalType == null) return;

    final reciprocalType = _selectedReciprocalType!;
    final repository = ref.read(relationshipRepositoryProvider);

    // [PERF] Close modal and invoke callback on frame 0 (0ms)
    if (mounted) {
      Navigator.pop(context);
      widget.onAccepted?.call();
      AppSnackbar.success(context, 'Relationship confirmed!');
    }

    unawaited(
      repository.acceptRequest(widget.request, '', reciprocalType).catchError((
        Object e,
      ) {
        debugPrint('Error accepting relationship request: $e');
      }),
    );
  }

  Future<void> _rejectRequest() async {
    final repository = ref.read(relationshipRepositoryProvider);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
          title: const Text('Reject Relationship?'),
          content: const Text(
            'Rejecting this request will signal that you do NOT know this person as claimed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Reject'),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      // [PERF] Pop modal and show feedback on frame 0 (0ms)
      Navigator.pop(context);
      AppSnackbar.info(context, 'Request rejected.');

      unawaited(
        repository.rejectRequest(widget.request).catchError((Object e) {
          debugPrint('Error rejecting relationship request: $e');
        }),
      );
    }
  }
}
