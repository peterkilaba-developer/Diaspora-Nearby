import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/relationship_repository.dart';
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart';
import 'package:diaspora_nearby/core/data/countries.dart';


class RelationshipSelectionModal extends ConsumerStatefulWidget {
  final String otherUserId;
  final String otherUserName;
  final bool includeFriend;
  final Function(String type)? onSelected;

  const RelationshipSelectionModal({
    super.key,
    required this.otherUserId,
    required this.otherUserName,
    this.includeFriend = true,
    this.onSelected,
  });

  @override
  ConsumerState<RelationshipSelectionModal> createState() =>
      _RelationshipSelectionModalState();
}

class _RelationshipSelectionModalState
    extends ConsumerState<RelationshipSelectionModal> {
  final Map<String, List<String>> _relationships = {
    'Immediate Family (Fund Eligible)': ['Wife', 'Husband', 'Daughter', 'Son'],
    'Close Family (Fund Eligible)': ['Mother', 'Father', 'Sister', 'Brother'],
    'Extended Family': ['Aunt', 'Uncle', 'Niece', 'Cousin'], // [UPDATED] Removed generic 'Relative'
    'Social Connections': ['Colleague', 'Business Partner', 'Community Member'],
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 24),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppTheme.pageHorizontalPadding, 16, AppTheme.pageHorizontalPadding, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'How are you related to ${widget.otherUserName}?',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var entry in _relationships.entries) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(AppTheme.pageHorizontalPadding, 8, AppTheme.pageHorizontalPadding, 8),
                        child: Row(
                          children: [
                            Text(
                              entry.key,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...entry.value.map(
                        (rel) => _buildItem(context, rel, theme),
                      ),
                    ],
                    if (widget.includeFriend) ...[
                       const Divider(height: 32),
                       _buildItem(context, 'Friend', theme, isSpecial: true),
                    ],
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(BuildContext context, String rel, ThemeData theme, {bool isSpecial = false}) {
     return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 4,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: isSpecial 
                ? theme.colorScheme.primary.withOpacity(0.05)
                : theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12),
            border: isSpecial ? Border.all(color: theme.colorScheme.primary.withOpacity(0.2)) : null,
          ),
          child: ListTile(
            title: Text(
              rel,
              style: TextStyle(
                fontWeight: isSpecial ? FontWeight.bold : FontWeight.w500,
                color: isSpecial ? theme.colorScheme.primary : null,
              ),
            ),
            leading: Icon(
              isSpecial ? LucideIcons.userCheck : LucideIcons.heart,
              size: 20,
              color: isSpecial ? theme.colorScheme.primary : theme.colorScheme.primary,
            ),
            trailing: Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onTap: () async {
              if (widget.onSelected != null) {
                 widget.onSelected!(rel);
                 return;
              }
              
              // Standard logic for ChatScreen (direct add)
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: const Text('Confirm Relationship'),
                    content: Text(
                      'Send a request to ${widget.otherUserName} to add them as your $rel?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Confirm'),
                      ),
                    ],
                  );
                },
              );

              if (confirmed == true) {
                await _saveRelationship(rel);
              }
            },
          ),
        ),
      );
  }

  Future<void> _saveRelationship(String type) async {
    try {
      final currentUserId = ref.read(authRepositoryProvider).currentUser?.uid;
      if (currentUserId == null) return;

      if (mounted) {
        Navigator.pop(context); // Close sheet
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sending relationship request...')),
        );
      }

      final currentUserProfile = await ref
          .read(profileRepositoryProvider)
          .getUserProfile(currentUserId);

      // [NEW] Validate Single Parent/Spouse Rule
      if (['Father', 'Mother', 'Wife', 'Husband'].contains(type)) {
        final existingRelationships = await ref.read(relationshipRepositoryProvider).getRelationshipsList(currentUserId);
        final hasParent = existingRelationships.any((r) => r.type == type && r.status == 'active');
        if (hasParent) {
          if (mounted) {
             ScaffoldMessenger.of(context).hideCurrentSnackBar();
             ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('You can only have one active $type.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }

      String flag = '🌍';
      if (currentUserProfile?.homeCountryCode != null) {
        flag = getCountryByCode(currentUserProfile!.homeCountryCode!)?.flag ?? '🌍';
      }

      await ref
          .read(relationshipRepositoryProvider)
          .sendRelationshipRequest(
            fromUserId: currentUserId,
            fromUserName:
                '${currentUserProfile?.firstName ?? ''} ${currentUserProfile?.lastName ?? ''}'
                    .trim()
                    .isNotEmpty
                ? '${currentUserProfile?.firstName} ${currentUserProfile?.lastName}'
                : 'User',
            fromUserFlag: flag,
            toUserId: widget.otherUserId,
            toUserName: widget.otherUserName,
            relationshipType: type,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        showExplorationRewardToast(
          context,
          message: 'Relationship request sent',
          points: 5, // Small bonus for social connection
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to send request: $e')));
      }
    }
  }
}
