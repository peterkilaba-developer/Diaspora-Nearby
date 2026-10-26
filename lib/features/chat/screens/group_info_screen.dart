import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/shared/widgets/user_card.dart';
import 'package:diaspora_nearby/core/utils/location_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/chat/services/chat_messaging_service.dart';
import 'package:diaspora_nearby/features/chat/providers/chat_providers.dart'; // [NEW] Shared Providers

class GroupInfoScreen extends ConsumerStatefulWidget {
  final String chatId;
  final String groupName;
  final String? groupImage;
  final String currentUserId;
  final bool initialEdit;

  const GroupInfoScreen({
    super.key,
    required this.chatId,
    required this.groupName,
    this.groupImage,
    required this.currentUserId,
    this.initialEdit = false,
  });

  @override
  ConsumerState<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends ConsumerState<GroupInfoScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  bool _isEditing = false;
  bool _isLoading = true;
  bool _isSaving = false;
  List<ProfileData> _members = [];
  List<ProfileData> _chatContacts = [];
  bool _isAdmin = false;
  String? _currentGroupImage;
  List<String> _adminIds = []; // Track admins separately
  String? _inviterId; // [NEW]
  bool _isMuted = false; // [NEW] Mute State
  bool _isFamilyGroup = false; // [NEW] Family Group Detection
  bool _isImmediateFamilyGroup = false; // [NEW] Immediate vs Extended
  bool _isListingChat = false; // [NEW] Marketplace Shop / Listing Chat

  // For Batch Editing
  final Set<String> _membersToRemove = {};
  final Set<String> _membersToAdd = {};
  XFile? _newGroupImageFile;

  @override
  void initState() {
    super.initState();
    _currentGroupImage = widget.groupImage;
    _nameController.text = widget.groupName;
    _isListingChat = widget.chatId.startsWith('listing_');
    _loadGroupData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadGroupData() async {
    setState(() => _isLoading = true);
    try {
      final chatRepo = ref.read(chatRepositoryProvider);
      final profileRepo = ref.read(profileRepositoryProvider);

      final chat = await chatRepo.getChat(widget.chatId);

      // Check for invitation metadata in Firestore userChats
      String? foundInviterId;
      try {
        final userChatDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.currentUserId)
            .collection('userChats')
            .doc(widget.chatId)
            .get();
        if (userChatDoc.exists) {
          final data = userChatDoc.data();
          final metadata = data?['lastMessage']?['metadata'];
          if (metadata is Map) {
            foundInviterId = metadata['inviterId'] as String?;
          }
          // Fetch Mute Status
          if (data?['muted'] == true) {
            _isMuted = true;
          } else {
            _isMuted = false;
          }
        }
      } catch (e) {
        debugPrint('Error fetching userChat data: $e');
      }

      // [FIX] Force fetch description removed - Schema updated

      if (mounted) {
        if (chat != null) {
          // Fetch Member Profiles
          // [MODIFIED] Always fetch members so invitees can see who is in the group
          var members = await profileRepo.getProfiles(chat.participants);

          // Sort Members: Creator -> Admins -> Others
          members.sort((a, b) {
            if (a.uid == chat.createdBy) return -1;
            if (b.uid == chat.createdBy) return 1;

            final aIsAdmin = chat.admins?.contains(a.uid) ?? false;
            final bIsAdmin = chat.admins?.contains(b.uid) ?? false;

            if (aIsAdmin && !bIsAdmin) return -1;
            if (!aIsAdmin && bIsAdmin) return 1;

            return 0; // Keep original order (roughly join time) for others
          });

          // Fetch Available Contacts (excluding current members)
          final allContacts = await chatRepo.getChatContacts();
          final potentialMembers = allContacts
              .where((c) => !chat.participants.contains(c.uid))
              .toList();

          // [NEW] Logic to check if user is ALREADY joined
          final isMember = chat.participants.contains(widget.currentUserId);

          // If inviterID is found BUT user is already a member, clear inviterId (edge case fix)
          if (isMember) {
            foundInviterId = null;
          }

          setState(() {
            _members = members;
            _chatContacts = potentialMembers;
            _currentGroupImage = chat.photoUrl;
            _nameController.text = chat.name;
            _descriptionController.text = chat.description ?? '';
            _adminIds = chat.admins ?? [];
            _inviterId = foundInviterId; // [NEW]
            _isFamilyGroup =
                chat.metadata?['isFamilyGroupImmediate'] == true ||
                chat.metadata?['isFamilyGroupExtended'] == true;
            _isImmediateFamilyGroup =
                chat.metadata?['isFamilyGroupImmediate'] == true;
            _isListingChat = chat.isListingChat;

            _isAdmin =
                chat.createdBy == widget.currentUserId ||
                (chat.admins?.contains(widget.currentUserId) ?? false) ||
                (chat.participants.isNotEmpty &&
                    chat.participants.first == widget.currentUserId);

            if (_isAdmin && widget.initialEdit) {
              _isEditing = true;
            }

            _isLoading = false;
          });
        } else {
          // Chat not found or error
          if (mounted) {
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Error: Chat not found')),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading group data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _acceptInvitation() async {
    setState(() => _isLoading = true);
    final repo = ref.read(chatRepositoryProvider);
    final profileRepo = ref.read(profileRepositoryProvider);

    await repo.addGroupMember(widget.chatId, widget.currentUserId);

    // [FIX] Manually update local cache so ChatScreen sees updated participant list immediately
    final currentChat = await repo.getChat(widget.chatId);
    if (currentChat != null) {
      final updatedParticipants = List<String>.from(currentChat.participants);
      if (!updatedParticipants.contains(widget.currentUserId)) {
        updatedParticipants.add(widget.currentUserId);
        final updatedChat = currentChat.copyWith(
          participants: updatedParticipants,
        );
        await repo.updateChatLocally(updatedChat);
      }
    }

    // Invalidate chat provider to unlock ChatScreen
    ref.invalidate(chatProvider(widget.chatId));

    // Optimistically update UI
    if (mounted) {
      setState(() {
        // 1. Hide inviter info
        _inviterId = null;
      });

      // 3. Add to members list manually if not present
      try {
        final myProfile = await profileRepo.getUserProfile(
          widget.currentUserId,
        );
        if (myProfile != null && mounted) {
          setState(() {
            if (!_members.any((m) => m.uid == widget.currentUserId)) {
              _members.add(myProfile);
              // Resort
              _members.sort((a, b) {
                // (Copy existing sort logic or simplfied)
                // Creator -> Admin -> Others
                // We don't have creatorId handy unless we store it.
                // But effectively just appending is better than missing.
                return 0;
              });
            }
            _isLoading = false;
          });
          // Reload fully to ensure sort order
          await _loadGroupData();

          // [NEW] Send System Message
          try {
            final messaging = ref.read(chatMessagingServiceProvider);
            await messaging.sendTextMessage(
              widget.chatId,
              '${myProfile.firstName} ${myProfile.lastName} joined the group.',
              type: 'system',
            );
          } catch (e) {
            debugPrint('Failed to send system message: $e');
          }
        }
      } catch (e) {
        debugPrint('Error optimistic update: $e');
        await _loadGroupData();
      }
    }
  }

  Future<void> _rejectInvitation() async {
    setState(() => _isLoading = true);
    // Remove from userChats (hide invitation)
    final repo = ref.read(chatRepositoryProvider);
    await repo.deleteChat(widget.chatId);

    if (mounted) {
      context.go('/chats');
    }
  }

  // [NEW] Invitation Selection State
  final Set<String> _selectedContactIds = {};
  bool get _isSelectingContacts => _selectedContactIds.isNotEmpty;

  // [NEW] Helper to split members
  bool _isMemberAdmin(ProfileData member) {
    return _adminIds.contains(member.uid) ||
        (_members.isNotEmpty &&
            _members.first.uid == member.uid &&
            _adminIds.isEmpty);
  }

  List<ProfileData> get _admins => _members.where(_isMemberAdmin).toList();
  List<ProfileData> get _regularMembers =>
      _members.where((m) => !_isMemberAdmin(m)).toList();

  Future<void> _inviteSelectedMembers() async {
    if (_selectedContactIds.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final messagingService = ref.read(chatMessagingServiceProvider);
      await messagingService.sendGroupInvitation(
        widget.chatId,
        widget.groupName,
        _selectedContactIds.toList(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Invitations sent to ${_selectedContactIds.length} users',
            ),
          ),
        );
        setState(() {
          _selectedContactIds.clear();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error inviting members: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to invite members: $e')));
      }
    }
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);
    try {
      final repo = ref.read(chatRepositoryProvider);

      // 1. Update Group Info if changed
      String? finalImageUrl;
      if (_newGroupImageFile != null) {
        finalImageUrl = await repo.uploadGroupImage(
          widget.chatId,
          _newGroupImageFile!,
        );
      }

      // Always update group info when saving changes in edit mode
      // optimizing by strictly checking against previous values is good but
      // the previous logic was flawed. Simplest is to just update.
      await repo.updateGroupInfo(
        widget.chatId,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        image: finalImageUrl,
      );

      // 2. Remove members
      for (final userId in _membersToRemove) {
        await repo.removeGroupMember(widget.chatId, userId);
      }

      // 3. Add members
      for (final userId in _membersToAdd) {
        await repo.addGroupMember(widget.chatId, userId);
      }

      if (mounted) {
        setState(() {
          _isEditing = false;
          _membersToRemove.clear();
          _membersToAdd.clear();
          _newGroupImageFile = null;
        });
        _loadGroupData();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isListingChat
                  ? 'Shop updated successfully'
                  : 'Group updated successfully',
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving changes: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving changes: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (image == null) return;

    setState(() {
      _newGroupImageFile = image;
    });
  }

  Future<void> _promoteToAdmin(String userId) async {
    final repo = ref.read(chatRepositoryProvider);
    final success = await repo.promoteToAdmin(widget.chatId, userId);
    if (success) _loadGroupData();
  }

  // Method _addMember removed (unused)

  Future<void> _leaveGroup() async {
    if (!await _showConfirmation(
      _isListingChat ? 'Leave Shop' : 'Leave Group',
      _isListingChat
          ? 'Are you sure you want to leave this shop?'
          : 'Are you sure you want to leave this group?',
    )) {
      return;
    }

    final repo = ref.read(chatRepositoryProvider);
    // Check if last admin/member logic (Simplified for now)

    final success = await repo.removeGroupMember(
      widget.chatId,
      widget.currentUserId,
    );
    if (success && mounted) {
      context.pop(); // Close info
      context.pop(); // Close chat
    }
  }

  Future<bool> _showConfirmation(String title, String content) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(content),
            actions: [
              TextButton(
                onPressed: () => context.pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => context.pop(true),
                child: const Text(
                  'Confirm',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
        title: Text(_isListingChat ? 'Shop Info' : 'Group Info'),
        actions: [
          if (_isAdmin && !_isLoading && _isEditing && _isSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          if (_isAdmin && !_isLoading && _isEditing && !_isSaving) ...[
            TextButton(
              onPressed: () {
                setState(() {
                  _isEditing = false;
                  _nameController.text = widget.groupName;
                  _loadGroupData();
                  _membersToRemove.clear();
                  _membersToAdd.clear();
                  _newGroupImageFile = null;
                });
              },
              child: Text(
                'Cancel',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
            TextButton(
              onPressed: _saveChanges,
              child: const Text(
                'Save',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
          if (_isAdmin && !_isLoading && !_isEditing)
            IconButton(
              icon: const Icon(LucideIcons.edit3),
              onPressed: () => setState(() => _isEditing = true),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_isLoading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.pageHorizontalPadding,
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    // Header (Image + Name)
                    Center(
                      child: Column(
                        children: [
                          // Image
                          Stack(
                            children: [
                              Container(
                                width: 96,
                                height: 96,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: theme.colorScheme.primaryContainer,
                                  image: _newGroupImageFile != null
                                      ? DecorationImage(
                                          image:
                                              (kIsWeb
                                                      ? NetworkImage(
                                                          _newGroupImageFile!
                                                              .path,
                                                        )
                                                      : FileImage(
                                                          File(
                                                            _newGroupImageFile!
                                                                .path,
                                                          ),
                                                        ))
                                                  as ImageProvider,
                                          fit: BoxFit.cover,
                                        )
                                      : _currentGroupImage != null
                                      ? DecorationImage(
                                          image: CachedNetworkImageProvider(
                                            _currentGroupImage!,
                                          ),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                                ),
                                child:
                                    (_newGroupImageFile == null &&
                                        _currentGroupImage == null)
                                    ? Center(
                                        child: _isFamilyGroup
                                            ? Icon(
                                                _isImmediateFamilyGroup
                                                    ? LucideIcons.heartHandshake
                                                    : LucideIcons.trees,
                                                color: _isImmediateFamilyGroup
                                                    ? Colors.blue.shade600
                                                    : Colors.teal.shade600,
                                                size: 42,
                                              )
                                            : Text(
                                                _nameController.text.isEmpty
                                                    ? '?'
                                                    : _nameController.text[0]
                                                          .toUpperCase(),
                                                style: theme
                                                    .textTheme
                                                    .displayMedium,
                                              ),
                                      )
                                    : null,
                              ),
                              if (_isEditing)
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: GestureDetector(
                                    onTap: _pickImage,
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        LucideIcons.camera,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Name
                          if (_isEditing)
                            SizedBox(
                              width: double.infinity,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: TextField(
                                  controller: _nameController,
                                  textAlign: TextAlign.center,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  decoration: InputDecoration(
                                    hintText: _isListingChat
                                        ? 'Enter shop name'
                                        : 'Enter group name',
                                    border: const UnderlineInputBorder(),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  style: theme.textTheme.headlineSmall,
                                ),
                              ),
                            )
                          else
                            Text(
                              widget.groupName,
                              style: theme.textTheme.headlineSmall,
                              textAlign: TextAlign.center,
                            ),
                          if (!_isLoading)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  LucideIcons.heartHandshake,
                                  size: 14,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _isListingChat
                                      ? '${_members.length} shopper${_members.length == 1 ? '' : 's'}'
                                      : '${_members.length} member${_members.length == 1 ? '' : 's'}',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),

                          // Invitation Banner Removed explicitly by user request
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Description Section
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(
                        children: [
                          if (_isEditing)
                            TextField(
                              controller: _descriptionController,
                              textAlign: TextAlign.center,
                              textCapitalization: TextCapitalization.sentences,
                              maxLines: 4,
                              minLines: 3,
                              maxLength: 200,
                              decoration: InputDecoration(
                                hintText: _isListingChat
                                    ? 'Add shop description'
                                    : 'Add group description',
                                border: const OutlineInputBorder(),
                                contentPadding: const EdgeInsets.all(12),
                                labelText: 'Description',
                              ),
                              style: theme.textTheme.bodyMedium,
                            )
                          else if (_descriptionController.text.isNotEmpty)
                            Text(
                              _descriptionController.text,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // [NEW] Mute Notifications Switch
                    SwitchListTile(
                      value: _isMuted,
                      onChanged: (value) async {
                        setState(() => _isMuted = value);
                        await ref
                            .read(chatRepositoryProvider)
                            .toggleMute(widget.chatId, value);
                      },
                      title: const Text('Mute Notifications'),
                      secondary: Icon(
                        _isMuted ? LucideIcons.bellOff : LucideIcons.bell,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      activeThumbColor: theme.colorScheme.primary,
                    ),

                    // Members Section (Always Show)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          _isListingChat
                              ? 'SHOPPERS & CONTACTS'
                              : 'MEMBERS & CONTACTS',
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                    ),
                    if (_isLoading) ...[
                      const SizedBox(height: 24),
                    ] else ...[
                      // 1. Admins
                      ..._buildMembersList(
                        theme,
                        _admins,
                        'Admins (${_admins.length})',
                      ),

                      // 2. Invite Section (Sandwidth)
                      ..._buildContactsList(theme),

                      // 3. Regular Members
                      ..._buildMembersList(
                        theme,
                        _regularMembers,
                        _isListingChat
                            ? 'Shoppers (${_regularMembers.length})'
                            : 'Group Members (${_regularMembers.length})',
                      ),

                      const SizedBox(height: 32),
                    ],
                  ],
                ),
              ),
            ),

            // Sticky Bottom Leave Group Button
            // Sticky Bottom Bar
            if (!_isLoading)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: Builder(
                  builder: (context) {
                    final isMember = _members.any(
                      (m) => m.uid == widget.currentUserId,
                    );

                    // Invitation View
                    if (!isMember) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'You have been invited to join this group',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_inviterId !=
                              null) // Optional: show inviter name if fetched
                            // We could query inviter name but simplified for now
                            const SizedBox(height: 8),

                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _rejectInvitation,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: theme.colorScheme.error,
                                    side: BorderSide.none,
                                  ),
                                  child: const Text('Reject'),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: FilledButton(
                                  onPressed: _acceptInvitation,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: theme
                                        .colorScheme
                                        .primary, // Use theme primary
                                  ),
                                  child: const Text('Accept'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    }

                    if (_isSelectingContacts) {
                      return SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _inviteSelectedMembers,
                          icon: const Icon(LucideIcons.send, size: 18),
                          label: Text(
                            'Invite ${_selectedContactIds.length} People',
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                theme.colorScheme.primary, // Use theme primary
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      );
                    }

                    // Member View (Leave Group / Leave Shop)
                    return SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _leaveGroup,
                        icon: const Icon(LucideIcons.logOut, size: 18),
                        label: Text(
                          _isListingChat ? 'Leave Shop' : 'Leave Group',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                          side: BorderSide.none,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminBadge(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(left: 8, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Admin',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }

  List<Widget> _buildMembersList(
    ThemeData theme,
    List<ProfileData> membersList,
    String title,
  ) {
    if (membersList.isEmpty) return [];

    return [
      Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
      ...membersList.map((member) {
        final isMe = member.uid == widget.currentUserId;
        final isMemberAdmin =
            _adminIds.contains(member.uid) ||
            (_members.indexOf(member) == 0 && _adminIds.isEmpty);

        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onLongPress: () {
                    if (_isAdmin && !isMe && !_isEditing) {
                      if (!isMemberAdmin) {
                        _promoteToAdmin(member.uid!);
                      }
                    }
                  },
                  onTap: () {
                    if (_isEditing && !isMe) {
                      setState(() {
                        if (_membersToRemove.contains(member.uid)) {
                          _membersToRemove.remove(member.uid);
                        } else {
                          if (member.uid != null) {
                            _membersToRemove.add(member.uid!);
                          }
                        }
                      });
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0x14888888),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(4), // Add padding for border
                    child: Opacity(
                      opacity: _membersToRemove.contains(member.uid)
                          ? 0.5
                          : 1.0,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isMemberAdmin) _buildAdminBadge(theme),
                          Builder(
                            builder: (context) {
                              final currentUserProfile = ref
                                  .watch(userProfileProvider)
                                  .value;
                              final distanceKm = calculateProfileDistanceKm(
                                currentUserProfile,
                                member,
                              );

                              return UserCardView(
                                user: member,
                                distanceKm: distanceKm,
                                onNameTap: () =>
                                    context.push('/profile/${member.uid}'),
                                onChatTap: isMe
                                    ? null
                                    : () => context.push(
                                        '/chat/direct/${member.uid}',
                                      ),
                                isStatic:
                                    true, // Disable internal tapping to allow parent GestureDetector
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Member Icon Removed as per request
            ],
          ),
        );
      }),
    ];
  }

  List<Widget> _buildContactsList(ThemeData theme) {
    // Only show contacts if user is a member (not just invited)
    final isMember = _members.any((m) => m.uid == widget.currentUserId);
    if (!isMember) return [];

    if (_chatContacts.isEmpty) return [];

    return [
      const SizedBox(height: 24),
      Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Text(
            'People You Can Invite (${_chatContacts.length})',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
      ..._chatContacts.map((contact) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onLongPress: () {
                    // Start selection mode if not editing
                    if (!_isEditing && !_isSelectingContacts) {
                      setState(() {
                        if (contact.uid != null) {
                          _selectedContactIds.add(contact.uid!);
                        }
                      });
                    }
                  },
                  onTap: () {
                    if (_isSelectingContacts) {
                      setState(() {
                        if (_selectedContactIds.contains(contact.uid)) {
                          _selectedContactIds.remove(contact.uid);
                        } else {
                          if (contact.uid != null) {
                            _selectedContactIds.add(contact.uid!);
                          }
                        }
                      });
                      return;
                    }

                    if (_isEditing) {
                      setState(() {
                        if (_membersToAdd.contains(contact.uid)) {
                          _membersToAdd.remove(contact.uid);
                        } else {
                          if (contact.uid != null) {
                            _membersToAdd.add(contact.uid!);
                          }
                        }
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0x14888888),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Builder(
                      builder: (context) {
                        double? distanceKm;
                        final currentUserProfile = ref
                            .watch(userProfileProvider)
                            .value;
                        if (currentUserProfile
                                    ?.currentLocation
                                    ?.geometry
                                    .location !=
                                null &&
                            contact.hostLocation.geometry?.location != null) {
                          distanceKm = calculateDistance(
                            currentUserProfile!
                                .currentLocation!
                                .geometry
                                .location
                                .lat,
                            currentUserProfile
                                .currentLocation!
                                .geometry
                                .location
                                .lng,
                            contact.hostLocation.geometry!.location.lat,
                            contact.hostLocation.geometry!.location.lng,
                          );
                        }

                        return UserCardView(
                          user: contact,
                          distanceKm: distanceKm,
                          onNameTap: (_isEditing || _isSelectingContacts)
                              ? null
                              : () => context.push('/profile/${contact.uid}'),
                          onChatTap: (_isEditing || _isSelectingContacts)
                              ? null
                              : () =>
                                    context.push('/chat/direct/${contact.uid}'),
                          isStatic: _isEditing || _isSelectingContacts,
                        );
                      },
                    ),
                  ),
                ),
              ),
              // Add Icon Removed as per request
            ],
          ),
        );
      }),
    ];
  }
}
