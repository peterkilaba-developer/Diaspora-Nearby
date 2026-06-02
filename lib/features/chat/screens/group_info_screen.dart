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
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/chat/services/chat_messaging_service.dart';
import 'package:diaspora_nearby/features/chat/providers/chat_providers.dart'; // [NEW] Shared Providers
import 'package:diaspora_nearby/features/chat/widgets/bilateral_flag_avatar.dart';
import 'package:diaspora_nearby/core/data/countries.dart' as country_data;

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
  bool _isMuted = false; // [NEW] Mute State
  bool _isFamilyGroup = false; // [NEW] Family Group Detection
  bool _isChamber = false;
  bool _isDdiDiscussion = false;
  bool _isPlatformAdmin = false;
  String? _homeCountryCode;
  String? _hostCountryCode;

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
          final currentProfile = await profileRepo.getUserProfile(
            widget.currentUserId,
          );
          final isChamber = chat.isChamber;
          final isDdiDiscussion = chat.isDdiDiscussion;
          final isPlatformAdmin = currentProfile?.isAdmin == true;

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
            _isFamilyGroup = chat.metadata?['isFamilyGroup'] == true;
            _isChamber = isChamber;
            _isDdiDiscussion = isDdiDiscussion;
            _isPlatformAdmin = isPlatformAdmin;
            _homeCountryCode = chat.homeCountryCode;
            _hostCountryCode = chat.hostCountryCode;

            _isAdmin = isChamber
                ? isPlatformAdmin
                : isDdiDiscussion
                ? false
                : (chat.admins?.contains(widget.currentUserId) ?? false) ||
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

    // Add +100 DSP to user and inviter
    if (_inviterId != null) {
      await pointsService.awardPoints(
        userId: _inviterId!,
        amount: 100,
        reason: 'Group Invite Accepted',
      );
    }
    await pointsService.awardPoints(
      userId: widget.currentUserId,
      amount: 100,
      reason: 'Joined Group',
    );

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

  Future<void> _joinManagedPublicGroup() async {
    setState(() => _isLoading = true);
    try {
      if (_isChamber) {
        final profileRepo = ref.read(profileRepositoryProvider);
        final myProfile = await profileRepo.getUserProfile(
          widget.currentUserId,
        );
        if (myProfile != null) {
          final isHomeDiaspora =
              myProfile.homeCountryCode?.toUpperCase() ==
              _homeCountryCode?.toUpperCase();
          if (isHomeDiaspora && !_hasLivedInHostCountry(myProfile)) {
            setState(() => _isLoading = false);
            final hostCountry = _hostCountryCode != null
                ? country_data.getCountryByCode(_hostCountryCode!)
                : null;
            final hostName = hostCountry?.name ?? 'Host Country';

            if (mounted) {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Row(
                    children: [
                      Icon(LucideIcons.shieldAlert, color: Colors.amber),
                      SizedBox(width: 8),
                      Text('Corridor Rep Gate'),
                    ],
                  ),
                  content: Text(
                    'To join the bilateral chamber as a representative of the home country diaspora, you must have lived in the host country ($hostName).\n\nPlease verify your past locations in your Profile settings.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => context.pop(),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            }
            return;
          }
        }
      }

      await ref.read(chatRepositoryProvider).joinGroup(widget.chatId);
      ref.invalidate(chatProvider(widget.chatId));
      await _loadGroupData();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unable to join group: $e')));
      }
    }
  }

  Future<void> _rejectInvitation() async {
    setState(() => _isLoading = true);
    final pointsService = ref.read(pointsServiceProvider);

    // +100 DSP to user, -100 DSP to inviter
    await pointsService.awardPoints(
      userId: widget.currentUserId,
      amount: 100,
      reason: 'Rejected Group Invite',
    );
    if (_inviterId != null) {
      await pointsService.deductPoints(
        userId: _inviterId!,
        amount: 100,
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
    if (_isChamber || _isDdiDiscussion) return false;
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

    if (_isChamber) {
      final homeCountry = _homeCountryCode;
      final hostCountry = _hostCountryCode;
      final hostCountryModel = hostCountry != null
          ? country_data.getCountryByCode(hostCountry)
          : null;
      final hostName = hostCountryModel?.name ?? 'Host Country';

      if (homeCountry != null && hostCountry != null) {
        for (final userId in _selectedContactIds) {
          final contactProfile = _chatContacts.firstWhere(
            (c) => c.uid == userId,
          );
          final isHomeDiaspora =
              contactProfile.homeCountryCode?.toUpperCase() ==
              homeCountry.toUpperCase();
          if (isHomeDiaspora && !_hasLivedInHostCountry(contactProfile)) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: Theme.of(context).colorScheme.error,
                content: Text(
                  'Gate Enforced: ${contactProfile.fullName} has not lived in $hostName and cannot be invited as a rep.',
                ),
              ),
            );
            return;
          }
        }
      }
    }

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

      if (_isChamber) {
        // Enforce representative gate:
        // Any added member who is home diaspora MUST have lived in the host country!
        final homeCountry = _homeCountryCode;
        final hostCountry = _hostCountryCode;
        final hostCountryModel = hostCountry != null
            ? country_data.getCountryByCode(hostCountry)
            : null;
        final hostName = hostCountryModel?.name ?? 'Host Country';

        if (homeCountry != null && hostCountry != null) {
          for (final userId in _membersToAdd) {
            final contactProfile = _chatContacts.firstWhere(
              (c) => c.uid == userId,
            );
            final isHomeDiaspora =
                contactProfile.homeCountryCode?.toUpperCase() ==
                homeCountry.toUpperCase();
            if (isHomeDiaspora && !_hasLivedInHostCountry(contactProfile)) {
              setState(() => _isSaving = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  content: Text(
                    'Gate Enforced: ${contactProfile.fullName} is from the $homeCountry diaspora but has not lived in $hostName. They cannot join as a representative.',
                  ),
                ),
              );
              return;
            }
          }
        }

        await repo.manageChamber(
          widget.chatId,
          description: _descriptionController.text.trim(),
          addMemberIds: _membersToAdd.toList(),
          removeMemberIds: _membersToRemove.toList(),
        );
      } else if (!_isDdiDiscussion) {
        // 1. Update Group Info if changed
        String? finalImageUrl;
        if (_newGroupImageFile != null) {
          finalImageUrl = await repo.uploadGroupImage(
            widget.chatId,
            _newGroupImageFile!,
          );
        }

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
    if (_isChamber || _isDdiDiscussion) return;
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
                              if (_isChamber)
                                BilateralFlagAvatar(
                                  homeCountryCode: _homeCountryCode,
                                  hostCountryCode: _hostCountryCode,
                                  size: 96,
                                )
                              else
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
                                                  LucideIcons.heartHandshake,
                                                  color: Colors.blue.shade600,
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
                              if (_isEditing &&
                                  !_isChamber &&
                                  !_isDdiDiscussion)
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
                          if (_isEditing && !_isChamber && !_isDdiDiscussion)
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
                              _nameController.text,
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
                                  '${_members.length} member${_members.length == 1 ? '' : 's'}',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          if (_isChamber)
                            const Padding(
                              padding: EdgeInsets.only(top: 10),
                              child: Chip(
                                avatar: Icon(LucideIcons.badgeCheck, size: 16),
                                label: Text(
                                  'Official platform-managed chamber',
                                ),
                              ),
                            ),
                          if (_isDdiDiscussion)
                            const Padding(
                              padding: EdgeInsets.only(top: 10),
                              child: Chip(
                                avatar: Icon(LucideIcons.vote, size: 16),
                                label: Text('Official DDI loan discussion'),
                              ),
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

                    if (_isChamber) ...[
                      _buildChamberGuide(theme),
                      const SizedBox(height: 32),
                    ],

                    if (_isChamber || _isDdiDiscussion)
                      ListTile(
                        leading: Icon(
                          LucideIcons.bellOff,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        title: const Text('Quiet by default'),
                        subtitle: const Text(
                          'Routine discussion messages are muted; mentions notify you.',
                        ),
                      )
                    else
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
                          'MEMBERS & CONTACTS',
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
                        'Group Members (${_regularMembers.length})',
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
                  border: Border(
                    top: BorderSide(color: theme.dividerColor, width: 0.5),
                  ),
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
                      if (_isChamber || _isDdiDiscussion) {
                        return SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _joinManagedPublicGroup,
                            icon: const Icon(LucideIcons.landmark, size: 18),
                            label: Text(
                              _isChamber
                                  ? 'Join Chamber'
                                  : 'Join DDI Discussion',
                            ),
                          ),
                        );
                      }
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
                                    side: BorderSide(
                                      color: theme.colorScheme.error,
                                    ),
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

                    if (_isChamber || _isDdiDiscussion) {
                      return const SizedBox.shrink();
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
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.5),
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

  bool _hasLivedInHostCountry(ProfileData member) {
    if (_hostCountryCode == null) return false;

    // Check current host country code
    if (member.hostCountryCode?.toUpperCase() ==
        _hostCountryCode!.toUpperCase()) {
      return true;
    }

    // Check past locations ("Also lived in" variable)
    if (member.pastLocations != null) {
      for (final past in member.pastLocations!) {
        if (past.location.countryCode?.toUpperCase() ==
            _hostCountryCode!.toUpperCase()) {
          return true;
        }
      }
    }

    return false;
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
            !_isChamber &&
            !_isDdiDiscussion &&
            (_adminIds.contains(member.uid) ||
                (_members.indexOf(member) == 0 && _adminIds.isEmpty));

        Widget? chamberRoleBadge;
        if (_isChamber) {
          final isHomeDiaspora =
              member.homeCountryCode?.toUpperCase() ==
              _homeCountryCode?.toUpperCase();
          final isHostNative =
              member.hostCountryCode?.toUpperCase() ==
              _hostCountryCode?.toUpperCase();
          final hasLived = _hasLivedInHostCountry(member);
          final hostCountryModel = _hostCountryCode != null
              ? country_data.getCountryByCode(_hostCountryCode!)
              : null;
          final hostName = hostCountryModel?.name ?? 'Host Country';

          if (isHomeDiaspora) {
            if (hasLived) {
              chamberRoleBadge = Container(
                margin: const EdgeInsets.only(left: 8, bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.5),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.checkCircle2,
                      size: 10,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Verified Rep',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              );
            } else {
              chamberRoleBadge = Container(
                margin: const EdgeInsets.only(left: 8, bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.5),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.alertTriangle,
                      size: 10,
                      color: Colors.amber,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Ineligible Rep (Not lived in $hostName)',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.amber.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              );
            }
          } else if (isHostNative) {
            chamberRoleBadge = Container(
              margin: const EdgeInsets.only(left: 8, bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.5),
                  width: 0.5,
                ),
              ),
              child: Text(
                'Native B2B Member',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            );
          }
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onLongPress: () {
                    if (_isAdmin &&
                        !_isChamber &&
                        !_isDdiDiscussion &&
                        !isMe &&
                        !_isEditing) {
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
                      border:
                          (_isEditing && _membersToRemove.contains(member.uid))
                          ? Border.all(color: theme.colorScheme.error, width: 2)
                          : null,
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
                          ?chamberRoleBadge,
                          Builder(
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
    if (_isDdiDiscussion) return [];
    if (_isChamber && (!_isPlatformAdmin || !_isEditing)) return [];
    if (!isMember && !(_isChamber && _isPlatformAdmin)) return [];

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
        Widget? chamberRoleBadge;
        if (_isChamber) {
          final isHomeDiaspora =
              contact.homeCountryCode?.toUpperCase() ==
              _homeCountryCode?.toUpperCase();
          final isHostNative =
              contact.hostCountryCode?.toUpperCase() ==
              _hostCountryCode?.toUpperCase();
          final hasLived = _hasLivedInHostCountry(contact);
          final hostCountryModel = _hostCountryCode != null
              ? country_data.getCountryByCode(_hostCountryCode!)
              : null;
          final hostName = hostCountryModel?.name ?? 'Host Country';

          if (isHomeDiaspora) {
            if (hasLived) {
              chamberRoleBadge = Container(
                margin: const EdgeInsets.only(left: 8, bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.5),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.checkCircle2,
                      size: 10,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Verified Rep',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              );
            } else {
              chamberRoleBadge = Container(
                margin: const EdgeInsets.only(left: 8, bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.5),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.alertTriangle,
                      size: 10,
                      color: Colors.amber,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Ineligible Rep (Not lived in $hostName)',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.amber.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              );
            }
          } else if (isHostNative) {
            chamberRoleBadge = Container(
              margin: const EdgeInsets.only(left: 8, bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.5),
                  width: 0.5,
                ),
              ),
              child: Text(
                'Native B2B Member',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            );
          }
        }

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
                      border:
                          ((_isEditing &&
                                  _membersToAdd.contains(contact.uid)) ||
                              (_isSelectingContacts &&
                                  _selectedContactIds.contains(contact.uid)))
                          ? Border.all(
                              color: theme
                                  .colorScheme
                                  .primary, // [FIX] Use theme primary
                              width: 2,
                            )
                          : null,
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

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ?chamberRoleBadge,
                            UserCardView(
                              user: contact,
                              distanceKm: distanceKm,
                              onNameTap: (_isEditing || _isSelectingContacts)
                                  ? null
                                  : () =>
                                        context.push('/profile/${contact.uid}'),
                              onChatTap: (_isEditing || _isSelectingContacts)
                                  ? null
                                  : () => context.push(
                                      '/chat/direct/${contact.uid}',
                                    ),
                              isStatic: _isEditing || _isSelectingContacts,
                            ),
                          ],
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

  Widget _buildChamberGuide(ThemeData theme) {
    final homeCountry = _homeCountryCode != null
        ? country_data.getCountryByCode(_homeCountryCode!)
        : null;
    final hostCountry = _hostCountryCode != null
        ? country_data.getCountryByCode(_hostCountryCode!)
        : null;

    final homeName = homeCountry?.name ?? 'Diaspora Home';
    final hostName = hostCountry?.name ?? 'Host Country';
    final homeFlag = homeCountry?.flag ?? '🌍';
    final hostFlag = hostCountry?.flag ?? '📍';

    return Container(
      decoration: AppTheme.cardDecoration(context),
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.landmark,
                color: theme.colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Bilateral Chamber Guidelines',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'This official chamber governs bilateral trade and community collaboration between the home diaspora and host country communities.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, thickness: 0.5),
          const SizedBox(height: 16),

          _buildGuideItem(
            theme: theme,
            icon: LucideIcons.globe,
            title: 'Bilateral Corridor Link',
            description:
                'Connects the $homeFlag $homeName Diaspora Chamber directly with the local businesses/natives and Diaspora members of $hostFlag $hostName.',
          ),
          const SizedBox(height: 16),

          _buildGuideItem(
            theme: theme,
            icon: LucideIcons.users,
            title: 'Lived-Experience Representation',
            description:
                'The $homeName Diaspora Chamber houses dedicated, active representatives who have physically lived in $hostName to ensure first-hand understanding of both business cultures.',
          ),
          const SizedBox(height: 16),

          _buildGuideItem(
            theme: theme,
            icon: LucideIcons.briefcase,
            title: 'Native & B2B Host Access',
            description:
                'Native individuals, local businesses, and corporate entities in $hostName have full, unrestricted access to register and participate in the $homeName bilateral chamber for direct trading, partnership, and cross-border commerce.',
          ),
          const SizedBox(height: 16),

          _buildGuideItem(
            theme: theme,
            icon: LucideIcons.shieldCheck,
            title: 'Unified Governance (Ex-Officio)',
            description:
                'Elected Community Leaders (President, Treasurer, Secretary) of the Diaspora in $hostName serve as the ex-officio leaders of this Chamber of Commerce to ensure complete alignment on decentralized identity (DDI/FDDI) verification and zero-fee escrows.',
          ),
        ],
      ),
    );
  }

  Widget _buildGuideItem({
    required ThemeData theme,
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
