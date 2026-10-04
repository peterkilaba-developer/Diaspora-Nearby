import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/relationship_repository.dart';
import 'package:diaspora_nearby/features/trust/repository/trust_repository.dart';
import 'package:diaspora_nearby/features/shared/utils/country_utils.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:diaspora_nearby/features/chat/widgets/chat_confirmation_sheet.dart';

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
    'Immediate Family (Emergency Fund Eligible)': [
      'Wife',
      'Husband',
      'Daughter',
      'Son',
    ],
    'Close Family (Emergency Fund Eligible)': [
      'Mother',
      'Father',
      'Sister',
      'Brother',
    ],
    'Extended Family': ['Aunt', 'Uncle', 'Nephew', 'Niece', 'Cousin'],
  };

  static const Set<String> _familyTypes = {
    'wife',
    'husband',
    'daughter',
    'son',
    'mother',
    'father',
    'sister',
    'brother',
    'aunt',
    'uncle',
    'nephew',
    'niece',
    'cousin',
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
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.4,
                  ),
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
                      const SizedBox(height: 4),
                      _buildItem(
                        context,
                        'Community Member',
                        theme,
                        isSpecial: true,
                      ),
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

  Widget _buildItem(
    BuildContext context,
    String rel,
    ThemeData theme, {
    bool isSpecial = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: isSpecial
              ? theme.colorScheme.primary.withValues(alpha: 0.03)
              : theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.03,
                ),
          borderRadius: BorderRadius.circular(12),
          border: isSpecial
              ? Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                )
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
            rel == 'Community Member'
                ? LucideIcons.users
                : isSpecial
                ? LucideIcons.userCheck
                : LucideIcons.heart,
            size: 20,
            color: theme.colorScheme.primary,
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
            if (context.mounted) {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (context) => ChatConfirmationSheet(
                  title: 'Confirm Relationship',
                  message:
                      'Send a request to ${widget.otherUserName} to add them as your $rel?',
                  actionTitle: 'Confirm Relationship',
                  subtitle: 'The other person must confirm the relationship.',
                  icon: LucideIcons.heartHandshake,
                  isDestructive: false,
                  onAction: () {
                    Navigator.pop(context); // Close sheet
                    _saveRelationship(rel);
                  },
                ),
              );
            }
          },
        ),
      ),
    );
  }

  Future<void> _saveRelationship(String type) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final currentUserId = ref.read(authRepositoryProvider).currentUser?.uid;
      if (currentUserId == null) return;

      if (mounted) {
        Navigator.pop(context); // Close sheet
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Sending relationship request...')),
      );

      final currentUserProfile = await ref
          .read(profileRepositoryProvider)
          .getUserProfile(currentUserId);

      // [COI] Block family requests when either party has verified or vouched
      if (_familyTypes.contains(type.toLowerCase())) {
        final trustRepo = ref.read(trustRepositoryProvider);

        // Check both directions: A→B and B→A
        final hasVerifiedThem = await trustRepo.hasVerifiedUser(
          currentUserId,
          widget.otherUserId,
        );
        final theyVerifiedMe = await trustRepo.hasVerifiedUser(
          widget.otherUserId,
          currentUserId,
        );
        final hasVouchedThem = await trustRepo.hasVouched(
          currentUserId,
          widget.otherUserId,
        );
        final theyVouchedMe = await trustRepo.hasVouched(
          widget.otherUserId,
          currentUserId,
        );

        if (hasVerifiedThem ||
            theyVerifiedMe ||
            hasVouchedThem ||
            theyVouchedMe) {
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Cannot add as family — a verification or vouch already '
                'exists between you (Conflict of Interest).',
              ),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      // [NEW] Validate Single Parent/Spouse Rule
      if (['Father', 'Mother', 'Wife', 'Husband'].contains(type)) {
        final existingRelationships = await ref
            .read(relationshipRepositoryProvider)
            .getRelationshipsList(currentUserId);
        final hasParent = existingRelationships.any(
          (r) => r.type == type && r.status == 'active',
        );
        if (hasParent) {
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Text('You can only have one active $type.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      final flag = CountryUtils.getCountryFlag(
        currentUserProfile?.homeCountryCode,
      );

      final fullName = currentUserProfile?.fullName.trim();
      final composedName =
          '${currentUserProfile?.firstName ?? ''} ${currentUserProfile?.lastName ?? ''}'
              .trim();
      final senderName = composedName.isNotEmpty
          ? composedName
          : (fullName != null && fullName.isNotEmpty ? fullName : 'User');

      await ref
          .read(relationshipRepositoryProvider)
          .sendRelationshipRequest(
            fromUserId: currentUserId,
            fromUserName: senderName,
            fromUserFlag: flag,
            fromUserPhoto: currentUserProfile?.profileImage,
            toUserId: widget.otherUserId,
            toUserName: widget.otherUserName,
            toUserPhoto: widget.otherUserPhoto,
            relationshipType: type,
          );

      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(content: Text('Relationship request sent')),
      );
    } catch (e) {
      String msg = e.toString();
      if (e is FirebaseFunctionsException &&
          e.message != null &&
          e.message!.isNotEmpty) {
        msg = e.message!;
      } else if (msg.startsWith('Exception: ')) {
        msg = msg.substring('Exception: '.length);
      }
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}
