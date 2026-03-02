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
  final String? otherUserPhoto;
  final bool includeFriend;
  final Function(String type)? onSelected;

  const RelationshipSelectionModal({
    super.key,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserPhoto,
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
    'Extended Family (Fund Eligible)': [
      'Aunt',
      'Uncle',
      'Nephew',
      'Niece',
      'Cousin',
    ],
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
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.pageHorizontalPadding,
                16,
                AppTheme.pageHorizontalPadding,
                16,
              ),
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
                        padding: const EdgeInsets.fromLTRB(
                          AppTheme.pageHorizontalPadding,
                          8,
                          AppTheme.pageHorizontalPadding,
                          8,
                        ),
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

  // [UPDATED] Family types that are free
  static const Set<String> _familyTypes = {
    'wife', 'husband', 'daughter', 'son', 'mother', 'father',
    'sister', 'brother', 'aunt', 'uncle', 'nephew', 'niece', 'cousin',
  };

  bool _isFamilyType(String type) =>
      _familyTypes.contains(type.toLowerCase());

  bool _isFriendType(String type) =>
      type.toLowerCase() == 'friend';

  /// All connections earn both users 1,000 DSP
  bool _isFreeConnection(String type) => true;

  Widget _buildItem(
    BuildContext context,
    String rel,
    ThemeData theme, {
    bool isSpecial = false,
  }) {
    final isFree = _isFreeConnection(rel);
    final isFriend = _isFriendType(rel);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: isSpecial
              ? theme.colorScheme.primary.withValues(alpha: 0.03)
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
          border: isSpecial
              ? Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2))
              : null,
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
            color: theme.colorScheme.primary,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Earn 1,000 DSP',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.green,
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              Icon(
                LucideIcons.chevronRight,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
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
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Send a request to ${widget.otherUserName} to add them as your $rel?',
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.green.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              LucideIcons.heartHandshake,
                              size: 18,
                              color: Colors.green,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Both users earn 1,000 DSP ✓',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
        final existingRelationships = await ref
            .read(relationshipRepositoryProvider)
            .getRelationshipsList(currentUserId);
        final hasParent = existingRelationships.any(
          (r) => r.type == type && r.status == 'active',
        );
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

      String flag = '';
      if (currentUserProfile?.homeCountryCode != null) {
        flag =
            getCountryByCode(currentUserProfile!.homeCountryCode!)?.flag ??
            '';
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
            fromUserPhoto: currentUserProfile?.profileImage,
            toUserId: widget.otherUserId,
            toUserName: widget.otherUserName,
            toUserPhoto: widget.otherUserPhoto,
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send request: $e')));
      }
    }
  }
}
