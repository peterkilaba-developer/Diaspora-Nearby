import 'dart:async';
import 'dart:ui';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/shared/widgets/user_card.dart';
import 'package:diaspora_nearby/features/chat/services/chat_messaging_service.dart';

import 'package:diaspora_nearby/features/community/repository/community_repository.dart'; // [NEW]

class CreateGroupScreen extends ConsumerStatefulWidget {
  final String? initialParticipantId;
  final String? communityId; // [NEW]

  const CreateGroupScreen({
    super.key,
    this.initialParticipantId,
    this.communityId,
  });

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final Set<String> _selectedIds = {};
  XFile? _groupImage;
  bool _isLoading = false;
  bool _isLoadingContacts = true;

  List<ProfileData> _contacts = [];
  bool _isPublic = false; // for community groups
  String? _selectedCategory; // category for community groups

  static const List<String> _groupCategories = [
    'Faith & Spirituality',
    'Investments & Finance',
    'Business & Entrepreneurship',
    'Education & Mentorship',
    'Health & Wellness',
    'Culture & Heritage',
    'Technology & Innovation',
    'Real Estate & Housing',
    'Careers & Networking',
    'Family & Parenting',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialParticipantId != null) {
      _selectedIds.add(widget.initialParticipantId!);
    }
    // [NEW] Default to public for community groups
    if (widget.communityId != null) {
      _isPublic = true;
    }
    _seedCachedContacts();
    _loadContacts();
  }

  void _seedCachedContacts() {
    final repo = ref.read(chatRepositoryProvider);
    final profileRepo = ref.read(profileRepositoryProvider);
    final currentUserId = repo.currentUserId;
    if (currentUserId == null) return;

    final cachedChats = repo.cachedChats;
    if (cachedChats.isEmpty) return;

    final seenIds = <String>{};
    final seeded = <ProfileData>[];
    for (final chat in cachedChats) {
      if (chat.type == 'direct') {
        for (final pid in chat.participants) {
          if (pid != currentUserId && seenIds.add(pid)) {
            final p = profileRepo.getCachedProfile(pid);
            if (p != null) {
              seeded.add(p);
            }
          }
        }
      }
    }
    if (seeded.isNotEmpty) {
      _contacts = seeded;
      _isLoadingContacts = false;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    if (_contacts.isEmpty) {
      setState(() => _isLoadingContacts = true);
    }
    final repo = ref.read(chatRepositoryProvider);
    final contacts = await repo.getContactsWithDMs();

    if (mounted) {
      setState(() {
        _contacts = contacts;
        _isLoadingContacts = false;
      });
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked != null) {
      setState(() {
        _groupImage = picked;
      });
    }
  }

  Future<void> _showExclusivityDialog(String communityName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(
                  LucideIcons.shield,
                  color: theme.colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 8),
                const Expanded(child: Text('Community Exclusive Group')),
              ],
            ),
            content: RichText(
              text: TextSpan(
                style: theme.textTheme.bodyMedium,
                children: [
                  const TextSpan(
                    text: 'This group will be exclusively for members of ',
                  ),
                  TextSpan(
                    text: communityName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const TextSpan(
                    text:
                        '. Only current and future members of this community will be able to discover and join this group.',
                  ),
                ],
              ),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            actions: [
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Create Group'),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed == true) {
      _createGroup();
    }
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (_groupImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a group photo')),
      );
      return;
    }
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a group name')),
      );
      return;
    }
    if (widget.communityId != null && _selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a group category')),
      );
      return;
    }
    if (widget.communityId == null && _selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one member')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final repo = ref.read(chatRepositoryProvider);
    final communityRepo = ref.read(communityRepositoryProvider);
    final messagingService = ref.read(chatMessagingServiceProvider);
    final selectedTargets = _selectedIds.toList();
    final communityId = widget.communityId;

    // Create logic
    try {
      debugPrint('Calling repo.createGroup...');
      // Create group with NO members initially (only creator)
      final chat = await repo.createGroup(
        name,
        [], // Empty list - members are invited, not added directly
        groupImage: _groupImage,
        description: _descriptionController.text.trim(),
        communityId: communityId,
        isPublic: communityId != null ? true : _isPublic,
        category: _selectedCategory,
      );
      debugPrint('Group created: ${chat?.id}');

      if (chat != null) {
        // Dispatch invitations in the background so navigation happens in 0ms
        unawaited(() async {
          try {
            List<String> invitationTargets;
            if (communityId != null) {
              final community =
                  communityRepo.getCachedCommunity(communityId) ??
                  await communityRepo.getCommunity(communityId);
              final currentUserId = repo.currentUserId;
              invitationTargets =
                  community?.members
                      .where((id) => id != currentUserId)
                      .toList() ??
                  [];
            } else {
              invitationTargets = selectedTargets;
            }

            if (invitationTargets.isNotEmpty) {
              await messagingService.sendGroupInvitation(
                chat.id,
                name,
                invitationTargets,
              );
            }
          } catch (e) {
            debugPrint('Background invitation dispatch error: $e');
          }
        }());
      }

      if (mounted) {
        setState(() => _isLoading = false);
        if (chat != null) {
          // Pop this screen and replace with chat screen immediately
          if (context.canPop()) context.pop();
          context.pushReplacement('/chats/${chat.id}');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to create group')),
          );
        }
      }
    } catch (e, stack) {
      debugPrint('Error in _createGroup: $e\n$stack');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // [NEW] Fetch community details if applicable
    final kCommunityId = widget.communityId;
    final communityAsync = kCommunityId != null
        ? ref.watch(communityProvider(kCommunityId))
        : const AsyncValue.data(null);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.x),
          onPressed: () => context.pop(),
        ),
        title: Text(
          kCommunityId != null ? 'Create Community Group' : 'Create New Group',
        ),
        centerTitle: false,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Group Info Section
                  Row(
                    children: [
                      GestureDetector(
                        onTap: _pickImage,
                        child: Stack(
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                shape: BoxShape.circle,
                                image: _groupImage != null
                                    ? DecorationImage(
                                        image:
                                            (kIsWeb
                                                    ? NetworkImage(
                                                        _groupImage!.path,
                                                      )
                                                    : FileImage(
                                                        File(_groupImage!.path),
                                                      ))
                                                as ImageProvider,
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: _groupImage == null
                                  ? Center(
                                      child: _nameController.text.isNotEmpty
                                          ? Text(
                                              _nameController.text
                                                  .substring(0, 1)
                                                  .toUpperCase(),
                                              style: theme.textTheme.titleLarge
                                                  ?.copyWith(
                                                    color: theme
                                                        .colorScheme
                                                        .onPrimaryContainer,
                                                  ),
                                            )
                                          : Icon(
                                              LucideIcons.users,
                                              color: theme
                                                  .colorScheme
                                                  .onPrimaryContainer,
                                            ),
                                    )
                                  : null,
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  LucideIcons.camera,
                                  size: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: _nameController,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            labelText: 'Group Name',
                            filled: true,
                            fillColor: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.3),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          onChanged: (val) =>
                              setState(() {}), // rebuild for avatar preview
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _descriptionController,
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 4,
                    minLines: 3,
                    maxLength: 200,
                    decoration: InputDecoration(
                      labelText: 'Group Description (Optional)',
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      alignLabelWithHint: true,
                    ),
                  ),

                  // Category selection (community groups only)
                  if (kCommunityId != null) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedCategory,
                      decoration: InputDecoration(
                        labelText: 'Group Category',
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.3),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      items: _groupCategories
                          .map(
                            (cat) =>
                                DropdownMenuItem(value: cat, child: Text(cat)),
                          )
                          .toList(),
                      onChanged: (val) =>
                          setState(() => _selectedCategory = val),
                    ),

                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                LucideIcons.globe,
                                color: theme.colorScheme.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Community Public Group',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Public groups must be topic-based (e.g., "Business", "Investments", "Faith"). Location-based groups are not permitted as they duplicate community functionality.',
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 12),
                          communityAsync.when(
                            data: (community) => Row(
                              children: [
                                Icon(
                                  LucideIcons.users,
                                  size: 16,
                                  color: theme.textTheme.bodySmall?.color,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${community?.totalMembers ?? 0} Community Members',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            loading: () => const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            error: (_, _) => const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 24),

                    // Members Section (Only for non-community)
                    Text(
                      'Send Request to Join Group (${_selectedIds.length} selected)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),

                    if (_isLoadingContacts)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_contacts.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            children: [
                              Icon(
                                LucideIcons.users,
                                size: 48,
                                color: theme.disabledColor,
                              ),
                              const SizedBox(height: 16),
                              const Text('No contacts found'),
                              Text(
                                'Start chatting with people to add them.',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ..._contacts.map((contact) {
                        final userId = contact.uid;
                        final isSelected = _selectedIds.contains(userId);

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                if (userId == null) return;
                                if (isSelected) {
                                  _selectedIds.remove(userId);
                                } else {
                                  _selectedIds.add(userId);
                                }
                              });
                            },
                            child: Stack(
                              children: [
                                UserCardView(user: contact, isStatic: true),
                                if (isSelected)
                                  Positioned.fill(
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ), // Match card margin
                                      decoration: BoxDecoration(
                                        color: const Color(0x14888888),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }),
                  ],
                ],
              ),
            ),
          ),

          // Fixed Footer
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: theme.scaffoldBackgroundColor),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : () => context.pop(),
                      style: OutlinedButton.styleFrom(side: BorderSide.none),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed:
                          (_isLoading ||
                              _nameController.text.isEmpty ||
                              ((kCommunityId == null) &&
                                  _selectedIds.isEmpty) ||
                              (kCommunityId != null &&
                                  _selectedCategory == null) ||
                              _groupImage == null)
                          ? null
                          : () {
                              if (kCommunityId != null) {
                                final communityName =
                                    communityAsync.value?.name ??
                                    'this community';
                                _showExclusivityDialog(communityName);
                              } else {
                                _createGroup();
                              }
                            },
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              kCommunityId != null
                                  ? 'Create Group'
                                  : 'Create Group',
                            ),
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
}
