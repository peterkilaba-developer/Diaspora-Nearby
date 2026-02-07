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
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:diaspora_nearby/features/chat/services/chat_messaging_service.dart';
import 'package:diaspora_nearby/features/chat/providers/chat_providers.dart'; // [NEW] Shared Providers

class GroupInfoScreen extends ConsumerStatefulWidget {
  final String chatId;
  final String groupName;
  final String? groupImage;
  final String currentUserId;

  const GroupInfoScreen({
    super.key,
    required this.chatId,
    required this.groupName,
    this.groupImage,
    required this.currentUserId,
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

  // For Batch Editing
  final Set<String> _membersToRemove = {};
  final Set<String> _membersToAdd = {};
  XFile? _newGroupImageFile;

  @override
  void initState() {
    super.initState();
    _currentGroupImage = widget.groupImage;
    _nameController.text = widget.groupName;
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

      // Check for invitation metadata in RTDB
      String? foundInviterId;
      try {
        final snapshot = await FirebaseDatabase.instance
            .ref('userChats/${widget.currentUserId}/${widget.chatId}/lastMessage/metadata')
            .get();
        if (snapshot.exists && snapshot.value != null && snapshot.value is Map) {
          final data = Map<String, dynamic>.from(snapshot.value as Map);
          foundInviterId = data['inviterId'] as String?;
        }
      } catch (e) {
        debugPrint('Error fetching invitation metadata: $e');
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

            _isAdmin = (chat.admins?.contains(widget.currentUserId) ?? false) ||
                (chat.participants.isNotEmpty &&
                    chat.participants.first == widget.currentUserId);

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
    final pointsService = ref.read(pointsServiceProvider);
    final repo = ref.read(chatRepositoryProvider);
    final profileRepo = ref.read(profileRepositoryProvider);

    // Add +10 DSP to user and inviter
    if (_inviterId != null) {
      await pointsService.awardPoints(
        userId: _inviterId!,
        amount: 10,
        reason: 'Group Invite Accepted',
      );
    }
    await pointsService.awardPoints(
      userId: widget.currentUserId,
      amount: 10,
      reason: 'Joined Group',
    );

    await repo.addGroupMember(widget.chatId, widget.currentUserId);
    
    // [FIX] Manually update local cache so ChatScreen sees updated participant list immediately
    final currentChat = await repo.getChat(widget.chatId);
    if (currentChat != null) {
      final updatedParticipants = List<String>.from(currentChat.participants);
      if (!updatedParticipants.contains(widget.currentUserId)) {
        updatedParticipants.add(widget.currentUserId);
        final updatedChat = currentChat.copyWith(participants: updatedParticipants);
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
        final myProfile = await profileRepo.getUserProfile(widget.currentUserId);
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
    final pointsService = ref.read(pointsServiceProvider);
    
    // +10 DSP to user, -10 DSP to inviter
    await pointsService.awardPoints(
      userId: widget.currentUserId,
      amount: 10,
      reason: 'Rejected Group Invite',
    );
     if (_inviterId != null) {
      await pointsService.deductPoints(
        userId: _inviterId!,
        amount: 10,
        reason: 'Group Invite Rejected',
      );
    }

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
           (_members.isNotEmpty && _members.first.uid == member.uid && _adminIds.isEmpty);
  }

  List<ProfileData> get _admins => _members.where(_isMemberAdmin).toList();
  List<ProfileData> get _regularMembers => _members.where((m) => !_isMemberAdmin(m)).toList();

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
           SnackBar(content: Text('Invitations sent to ${_selectedContactIds.length} users')),
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
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Failed to invite members: $e')),
        );
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
          const SnackBar(content: Text('Group updated successfully')),
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
      'Leave Group',
      'Are you sure you want to leave this group?',
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
        title: const Text('Group Info'),
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
                padding: const EdgeInsets.symmetric(horizontal: 8),
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
                                        child: Text(
                                          _nameController.text.isEmpty
                                              ? '?'
                                              : _nameController.text[0]
                                                    .toUpperCase(),
                                          style: theme.textTheme.displayMedium,
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
                                        border: Border.all(
                                          color: theme.scaffoldBackgroundColor,
                                          width: 2,
                                        ),
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
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: TextField(
                                  controller: _nameController,
                                  textAlign: TextAlign.center,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  decoration: const InputDecoration(
                                    hintText: 'Enter group name',
                                    border: UnderlineInputBorder(),
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
                                  Icons.handshake_outlined,
                                  size: 14,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${_members.length} member${_members.length == 1 ? '' : 's'}',
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
                              decoration: const InputDecoration(
                                hintText: 'Add group description',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.all(12),
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
                    // Members Section (Always Show)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          'MEMBERS & CONTACTS',
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                    ),
                    if (_isLoading) ...[
                      const SizedBox(height: 24),
                    ] else ...[
                      // 1. Admins
                      ..._buildMembersList(theme, _admins, 'Admins (${_admins.length})'),
                      
                      // 2. Invite Section (Sandwidth)
                      ..._buildContactsList(theme),
                      
                      // 3. Regular Members
                      ..._buildMembersList(theme, _regularMembers, 'Group Members (${_regularMembers.length})'),
                      
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
                  border: Border(
                    top: BorderSide(color: theme.dividerColor, width: 0.5),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: Builder(
                  builder: (context) {
                    final isMember = _members.any((m) => m.uid == widget.currentUserId);
                    
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
                          if (_inviterId != null) // Optional: show inviter name if fetched
                             // We could query inviter name but simplified for now
                             const SizedBox(height: 8),
                          
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _rejectInvitation,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: theme.colorScheme.error,
                                    side: BorderSide(color: theme.colorScheme.error),
                                  ),
                                  child: const Text('Reject'),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: FilledButton(
                                  onPressed: _acceptInvitation,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: theme.colorScheme.primary, // Use theme primary
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
                          label: Text('Invite ${_selectedContactIds.length} People'),
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary, // Use theme primary
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      );
                    }

                    // Member View (Leave Group)
                    return SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _leaveGroup,
                        icon: const Icon(LucideIcons.logOut, size: 18),
                        label: const Text('Leave Group'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                          side: BorderSide(color: theme.colorScheme.error),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    );
                  }
                ),
              )
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
        color: theme.colorScheme.primaryContainer.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withOpacity(0.5),
          width: 0.5,
        ),
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

  List<Widget> _buildMembersList(ThemeData theme, List<ProfileData> membersList, String title) {
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
        final isMemberAdmin = _adminIds.contains(member.uid) ||
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
                      border: (_isEditing && _membersToRemove.contains(member.uid)) 
                          ? Border.all(color: theme.colorScheme.error, width: 2)
                          : null,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(4), // Add padding for border
                    child: Opacity(
                      opacity:
                          _membersToRemove.contains(member.uid) ? 0.5 : 1.0,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isMemberAdmin) _buildAdminBadge(theme),
                          Builder(
                            builder: (context) {
                              double? distanceKm;
                              final currentUserProfile =
                                  ref.watch(userProfileProvider).value;
                              if (currentUserProfile
                                          ?.currentLocation
                                          ?.geometry
                                          .location !=
                                      null &&
                                  member.hostLocation.geometry?.location !=
                                      null) {
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
                                  member.hostLocation.geometry!.location.lat,
                                  member.hostLocation.geometry!.location.lng,
                                );
                              }

                              return UserCardView(
                                user: member,
                                distanceKm: distanceKm,
                                onNameTap: () =>
                                    context.push('/profile/${member.uid}'),
                                onChatTap: isMe
                                    ? null
                                    : () => context
                                        .push('/chat/direct/${member.uid}'),
                                isStatic: true, // Disable internal tapping to allow parent GestureDetector
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
                      border: ((_isEditing && _membersToAdd.contains(contact.uid)) ||
                              (_isSelectingContacts && _selectedContactIds.contains(contact.uid)))
                          ? Border.all(
                              color: theme.colorScheme.primary, // [FIX] Use theme primary
                              width: 2,
                            )
                          : null,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Builder(
                      builder: (context) {
                        double? distanceKm;
                        final currentUserProfile =
                            ref.watch(userProfileProvider).value;
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
                              : () => context.push('/chat/direct/${contact.uid}'),
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
