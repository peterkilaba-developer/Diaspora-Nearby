import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/relationship_repository.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/profile/models/relationship.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/trust/repository/trust_repository.dart';
import 'package:diaspora_nearby/features/shared/utils/country_utils.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:diaspora_nearby/features/chat/widgets/chat_confirmation_sheet.dart';

class RelationshipSelectionModal extends ConsumerStatefulWidget {
  final String otherUserId;
  final String otherUserName;
  final String? otherUserPhoto;
  final bool includeFriend;
  final bool includeFamily;
  final Function(String type)? onSelected;

  const RelationshipSelectionModal({
    super.key,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserPhoto,
    this.includeFriend = true,
    this.includeFamily = true,
    this.onSelected,
  });

  @override
  ConsumerState<RelationshipSelectionModal> createState() =>
      _RelationshipSelectionModalState();
}

class _RelationshipSelectionModalState
    extends ConsumerState<RelationshipSelectionModal> {
  late final AuthRepository _authRepo;
  late final ProfileRepository _profileRepo;
  late final TrustRepository _trustRepo;
  late final RelationshipRepository _relationshipRepo;
  late final ChatRepository _chatRepo;
  ScaffoldMessengerState? _messenger;

  // [PERF] Pre-warmed eligibility futures started in initState
  Future<ProfileData?>? _myProfileFuture;
  Future<bool>? _hasDialogueFuture;
  Future<bool>? _coiFuture;
  Future<List<Relationship>>? _existingRelsFuture;

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
  void initState() {
    super.initState();
    _authRepo = ref.read(authRepositoryProvider);
    _profileRepo = ref.read(profileRepositoryProvider);
    _trustRepo = ref.read(trustRepositoryProvider);
    _relationshipRepo = ref.read(relationshipRepositoryProvider);
    _chatRepo = ref.read(chatRepositoryProvider);
    _prewarmChecks();
  }

  void _prewarmChecks() {
    final currentUserId = _authRepo.currentUser?.uid;
    if (currentUserId == null) return;
    final otherUserId = widget.otherUserId;

    final cachedProfile =
        ref.read(userProfileProvider).value ??
        _profileRepo.getCachedProfile(currentUserId);
    _myProfileFuture = cachedProfile != null
        ? Future.value(cachedProfile)
        : _profileRepo.getUserProfile(currentUserId);

    _hasDialogueFuture = _chatRepo.hasBilateralDialogue(
      currentUserId,
      otherUserId,
    );

    final cachedRels = _relationshipRepo.getCachedRelationships(currentUserId);
    _existingRelsFuture = cachedRels != null
        ? Future.value(cachedRels)
        : _relationshipRepo.getRelationshipsList(currentUserId);

    if (widget.includeFamily) {
      _coiFuture = Future.wait<bool>([
        _trustRepo.hasVerifiedUser(currentUserId, otherUserId),
        _trustRepo.hasVerifiedUser(otherUserId, currentUserId),
        _trustRepo.hasVouched(currentUserId, otherUserId),
        _trustRepo.hasVouched(otherUserId, currentUserId),
      ]).then((results) => results.any((v) => v));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.maybeOf(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
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
                      if (widget.includeFamily)
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
                        if (widget.includeFamily) const Divider(height: 32),
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

            if (context.mounted) {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (sheetContext) => ChatConfirmationSheet(
                  title: 'Confirm Relationship',
                  message:
                      'Send a request to ${widget.otherUserName} to add them as your $rel?',
                  actionTitle: 'Confirm Relationship',
                  subtitle: 'The other person must confirm the relationship.',
                  icon: LucideIcons.heartHandshake,
                  isDestructive: false,
                  onAction: () {
                    _saveRelationship(rel, sheetContext: sheetContext);
                  },
                ),
              );
            }
          },
        ),
      ),
    );
  }

  Future<void> _saveRelationship(
    String type, {
    BuildContext? sheetContext,
  }) async {
    final messenger =
        _messenger ?? (mounted ? ScaffoldMessenger.maybeOf(context) : null);
    final currentUserId = _authRepo.currentUser?.uid;
    if (currentUserId == null) {
      if (sheetContext != null && sheetContext.mounted) {
        Navigator.pop(sheetContext);
      }
      return;
    }

    final otherUserId = widget.otherUserId;
    final otherUserName = widget.otherUserName;
    final otherUserPhoto = widget.otherUserPhoto;

    // [PERF] Close sheets and show instant confirmation on frame 0 (0ms)
    if (sheetContext != null && sheetContext.mounted) {
      Navigator.pop(sheetContext);
    }
    if (mounted) {
      Navigator.pop(context);
    }
    messenger?.showSnackBar(
      const SnackBar(content: Text('Relationship request sent')),
    );

    unawaited(() async {
      try {
        final isFamily = _familyTypes.contains(type.toLowerCase());
        final needsSingleCheck = [
          'Father',
          'Mother',
          'Wife',
          'Husband',
        ].contains(type);

        final results = await Future.wait<dynamic>([
          _myProfileFuture ?? _profileRepo.getUserProfile(currentUserId),
          _hasDialogueFuture ??
              _chatRepo.hasBilateralDialogue(currentUserId, otherUserId),
          if (isFamily)
            _coiFuture ??
                Future.wait<bool>([
                  _trustRepo.hasVerifiedUser(currentUserId, otherUserId),
                  _trustRepo.hasVerifiedUser(otherUserId, currentUserId),
                  _trustRepo.hasVouched(currentUserId, otherUserId),
                  _trustRepo.hasVouched(otherUserId, currentUserId),
                ]).then((vals) => vals.any((v) => v))
          else
            Future.value(false),
          if (needsSingleCheck)
            _existingRelsFuture ??
                _relationshipRepo.getRelationshipsList(currentUserId)
          else
            Future.value(const <Relationship>[]),
        ]);

        final currentUserProfile = results[0] as ProfileData?;
        final hasDialogue = results[1] as bool;
        final hasCoi = results[2] as bool;
        final existingRelationships = results[3] as List<Relationship>;

        if (!hasDialogue) {
          messenger?.hideCurrentSnackBar();
          messenger?.showSnackBar(
            const SnackBar(
              content: Text(
                'A mutual direct chat is required before requesting a relationship. '
                'Both users must send at least one message.',
              ),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        if (isFamily && hasCoi) {
          messenger?.hideCurrentSnackBar();
          messenger?.showSnackBar(
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

        if (needsSingleCheck) {
          final hasParent = existingRelationships.any(
            (r) => r.type == type && r.status == 'active',
          );
          if (hasParent) {
            messenger?.hideCurrentSnackBar();
            messenger?.showSnackBar(
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

        await _relationshipRepo.sendRelationshipRequest(
          fromUserId: currentUserId,
          fromUserName: senderName,
          fromUserFlag: flag,
          fromUserPhoto: currentUserProfile?.profileImage,
          toUserId: otherUserId,
          toUserName: otherUserName,
          toUserPhoto: otherUserPhoto,
          relationshipType: type,
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
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    }());
  }
}
