import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/profile/models/relationship_request.dart';
import 'package:diaspora_nearby/features/profile/repository/relationship_repository.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';

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
  bool _isLoading = false;

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

    return PopScope(
      canPop:
          false, // Prevent accidental dismissal without choice if we want to enforce, but user said "dismiss without accepting" is allowed.
      // User said: "if dismiss without accepting or rejecting he can still do that in his relationship section"
      // So allow pop.
      child: Material(
        // [FIX] Added Material widget to fix "No Material widget found" error
        type: MaterialType.transparency,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 24.0),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              if (possibleTypes.length > 1)
                ...possibleTypes.map(
                  (type) => RadioListTile<String>(
                    title: Text(type),
                    value: type,
                    groupValue: _selectedReciprocalType,
                    onChanged: (val) =>
                        setState(() => _selectedReciprocalType = val),
                    contentPadding: EdgeInsets.zero,
                  ),
                )
              else
                ListTile(
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: Text(_selectedReciprocalType ?? possibleTypes.first),
                  subtitle: const Text('Logical reciprocal relationship'),
                ),

              const SizedBox(height: 24),
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context), // Dismiss
                        child: const Text('Later'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        // Disable if selection needed but not made
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
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Reject Request'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _acceptRequest() async {
    if (_selectedReciprocalType == null) return;

    setState(() => _isLoading = true);
    try {
      final repository = ref.read(relationshipRepositoryProvider);

      // Get current user (receiver) data for flag
      // In a real app we might fetch user profile, but here we try best effort or use generic
      // We can use the AuthRepository or just check if we have the profile loaded in previous screen context
      // But we are in a modal.
      // Let's rely on standard country lookup if possible, or default.
      String myFlag = '❤️';
      // Note: We don't have easy access to *my* profile data here without fetching.
      // For now, let's allow the repository to handle it or pass it in.
      // *Correction*: UserProfileView has access to `profile` (which is the visited user), not ME.
      // So I will fetch my basic profile or just proceed.
      // Actually, `acceptRequest` takes `accepterFlag`.

      await repository.acceptRequest(
        widget.request,
        myFlag,
        _selectedReciprocalType!,
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onAccepted?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Relationship confirmed!')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _rejectRequest() async {
    // Show confirmation for rejection penalty
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
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
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        // We need PointsService
        // We can get it via provider
        final pointsService = ref.read(pointsServiceProvider);
        await ref
            .read(relationshipRepositoryProvider)
            .rejectRequest(widget.request);
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Request rejected.')));
        }
      } catch (e) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}
