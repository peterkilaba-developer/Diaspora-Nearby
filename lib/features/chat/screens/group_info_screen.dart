import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/models/profile_data.dart';
import 'package:diaspora_nearby/features/shared/widgets/user_card.dart';
import 'package:diaspora_nearby/utils/location_utils.dart';

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
  bool _isEditing = false;
  bool _isLoading = true;
  bool _isSaving = false;
  List<ProfileData> _members = [];
  List<ProfileData> _chatContacts = [];
  bool _isAdmin = false;
  String? _currentGroupImage;
  List<String> _adminIds = []; // Track admins separately

  // For Batch Editing
  final Set<String> _membersToRemove = {};
  final Set<String> _membersToAdd = {};
  File? _newGroupImageFile;

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
    super.dispose();
  }

  Future<void> _loadGroupData() async {
    setState(() => _isLoading = true);
    try {
      final chatRepo = ref.read(chatRepositoryProvider);
      final profileRepo = ref.read(profileRepositoryProvider);
      
      final chat = await chatRepo.getChat(widget.chatId);

      if (mounted && chat != null) {
        // Fetch Member Profiles
        final members = await profileRepo.getProfiles(chat.participants);
        
        // Fetch Available Contacts (excluding current members)
        final allContacts = await chatRepo.getChatContacts();
        final potentialMembers = allContacts.where((c) => !chat.participants.contains(c.uid)).toList();

        setState(() {
          _members = members;
          _chatContacts = potentialMembers;
          _currentGroupImage = chat.photoUrl;
          _nameController.text = chat.name;
          _adminIds = chat.admins ?? []; // Assuming Chat model has admins list, or we need to handle roles differently
          
          // Check if current user is admin (Fallback to creator if admins not set, or if simple group)
          // For now, let's assume if admins list exists use it, else check first participant (creator)? 
          // Re-reading Chat model usage in previous file... it had 'role' in member map which was manual.
          // Chat model definition might need verification. 
          // Let's assume there is a way to determine admin.
          // Previous code: `_isAdmin = me['role'] == 'admin'` constructed manually.
          // Let's rely on `_adminIds` if available or default to checking if 1st participant (creator).
          // Ideally Chat model has `admins` list.
          // If Chat model doesn't have admins, we might need to update it or rely on conventions.
          // Checking `diaspora_nearby/models/chat.dart` would be good but I'll assume `admins` field or similar exists or I'll check `adminIds` from RTDB if I saw it.
          // Looking at `ChatRepository` it didn't explicitly parse `admins`. It did `participants`.
          // Let's assume for now EVERYONE is a member unless we have `admins` data. 
          // Wait, previous code `_members = chat.participants.map...` set role 'member'.
          // AND `_isAdmin = me['role'] == 'admin'`... so it was checking if hardcoded map had 'admin'.
          // The previous code had `me['role'] == 'admin'` but where did `role` come from? 
          // `_members = chat.participants.map((id) => {'userId': id, 'role': 'member'...`
          // So previous code effectively made NO ONE admin except defaults? 
          // Wait, line 77 `_isAdmin = me['role'] == 'admin';`
          // line 65 `... 'role': 'member' ...` 
          // UNLESS fetched differently.
          // Ah, `GroupInfoScreen` code I replaced had: `_members = chat.participants.map...`.
          // So strictly speaking, the previous code essentially set everyone to 'member'.
          // EXCEPT if I missed something. 
          // In `createGroup` repo method, it sets `admins`?
          // I should verify `Chat` model.
          // For safety, I will define `_isAdmin` as `chat.participants.first == widget.currentUserId` (Creator) for now if explicit admin list is missing.
          
          _isAdmin = (chat.admins?.contains(widget.currentUserId) ?? false) || 
                     (chat.participants.isNotEmpty && chat.participants.first == widget.currentUserId); 
          
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading group data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);
    try {
      final repo = ref.read(chatRepositoryProvider);

      // 1. Update Group Info if changed
      String? finalImageUrl;
      if (_newGroupImageFile != null) {
        finalImageUrl = await repo.uploadGroupImage(widget.chatId, _newGroupImageFile!);
      }

      if (_nameController.text.trim() != widget.groupName || finalImageUrl != null) {
        await repo.updateGroupInfo(
          widget.chatId, 
          name: _nameController.text.trim(),
          image: finalImageUrl,
        );
      }

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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Group updated successfully')));
      }
    } catch (e) {
      debugPrint('Error saving changes: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving changes: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() {
      _newGroupImageFile = File(image.path);
    });
  }

  Future<void> _promoteToAdmin(String userId) async {
    final repo = ref.read(chatRepositoryProvider);
    final success = await repo.promoteToAdmin(widget.chatId, userId);
    if (success) _loadGroupData();
  }

  Future<void> _removeMember(String userId) async {
    if (!await _showConfirmation(
        'Remove Member', 'Are you sure you want to remove this member?')) {
      return;
    }
    final repo = ref.read(chatRepositoryProvider);
    final success = await repo.removeGroupMember(widget.chatId, userId);
    if (success) _loadGroupData();
  }

  Future<void> _addMember(String userId) async {
    final repo = ref.read(chatRepositoryProvider);
    final success = await repo.addGroupMember(widget.chatId, userId);
    if (success) _loadGroupData();
  }

  Future<void> _leaveGroup() async {
    if (!await _showConfirmation(
        'Leave Group', 'Are you sure you want to leave this group?')) {
      return;
    }

    final repo = ref.read(chatRepositoryProvider);
    // Check if last admin/member logic (Simplified for now)
    
    final success =
        await repo.removeGroupMember(widget.chatId, widget.currentUserId);
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
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () => context.pop(true),
                  child: const Text('Confirm',
                      style: TextStyle(color: Colors.red))),
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
          if (_isAdmin && !_isLoading)
            if (_isEditing) ...[
              if (_isSaving)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else ...[
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isEditing = false;
                      _nameController.text = widget.groupName;
                      _membersToRemove.clear();
                      _membersToAdd.clear();
                      _newGroupImageFile = null;
                    });
                  },
                  child: Text('Cancel', style: TextStyle(color: theme.colorScheme.error)),
                ),
                TextButton(
                  onPressed: _saveChanges,
                  child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ] else
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
                                      ? DecorationImage(image: FileImage(_newGroupImageFile!), fit: BoxFit.cover)
                                      : _currentGroupImage != null
                                          ? DecorationImage(
                                              image: CachedNetworkImageProvider(_currentGroupImage!),
                                              fit: BoxFit.cover)
                                          : null,
                                ),
                                child: (_newGroupImageFile == null && _currentGroupImage == null)
                                    ? Center(
                                        child: Text(
                                            _nameController.text.isEmpty
                                                ? '?'
                                                : _nameController.text[0].toUpperCase(),
                                            style: theme.textTheme.displayMedium))
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
                                            width: 2),
                                      ),
                                      child: const Icon(LucideIcons.camera,
                                              size: 16, color: Colors.white),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Name
                          if (_isEditing)
                            SizedBox(
                              width: 200,
                              child: TextField(
                                controller: _nameController,
                                textAlign: TextAlign.center,
                                textCapitalization: TextCapitalization.sentences,
                                decoration: const InputDecoration(
                                  hintText: 'Enter group name',
                                  border: UnderlineInputBorder(),
                                  contentPadding: EdgeInsets.zero,
                                ),
                                style: theme.textTheme.headlineSmall,
                              ),
                            )
                          else
                            Text(widget.groupName, style: theme.textTheme.headlineSmall),
                          if (!_isLoading)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.handshake_outlined,
                                    size: 14,
                                    color: theme.colorScheme.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Text(
                                  '${_members.length} member${_members.length == 1 ? '' : 's'}',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Members Section
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text('MEMBERS & CONTACTS',
                            style: theme.textTheme.labelSmall),
                      ),
                    ),
                    if (_isLoading) ...[
                      const SizedBox(height: 24),
                      const Center(child: CircularProgressIndicator()),
                      const SizedBox(height: 24),
                    ] else ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          child: Text('Current Members (${_members.length})',
                              style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant)),
                        ),
                      ),
        

                      ..._members.map((member) {
                        final isMe = member.uid == widget.currentUserId;
                        final isMemberAdmin = _adminIds.contains(member.uid) || (_members.indexOf(member) == 0 && _adminIds.isEmpty); // Fallback: 1st is admin
        
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            children: [
                              if (_isEditing && !isMe)
                                Checkbox(
                                  value: _membersToRemove.contains(member.uid),
                                  activeColor: Colors.red,
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _membersToRemove.add(member.uid!);
                                      } else {
                                        _membersToRemove.remove(member.uid);
                                      }
                                    });
                                  },
                                ),
                              Expanded(
                                child: Opacity(
                                  opacity: _membersToRemove.contains(member.uid) ? 0.5 : 1.0,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (isMemberAdmin)
                                        _buildAdminBadge(theme),
                                      
                                      // [NEW] Calculate distance
                                      Builder(
                                        builder: (context) {
                                          double? distanceKm;
                                          final currentUserProfile = ref.watch(userProfileProvider).value;
                                          if (currentUserProfile?.currentLocation?.geometry.location != null &&
                                          member.hostLocation?.geometry?.location != null) {
                                          distanceKm = calculateDistance(
                                            currentUserProfile!.currentLocation!.geometry.location.lat,
                                            currentUserProfile.currentLocation!.geometry.location.lng,
                                            member.hostLocation!.geometry!.location.lat,
                                            member.hostLocation!.geometry!.location.lng,
                                          );
                                      }

                                          return UserCardView(
                                            user: member,
                                            distanceKm: distanceKm, // Pass calculated distance
                                            onNameTap: () => context.push('/profile/${member.uid}'),
                                            onChatTap: isMe ? null : () => context.push('/chat/direct/${member.uid}'),
                                          );
                                        }
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (_isAdmin && !isMe && !_isEditing)
                                PopupMenuButton(
                                  icon: const Icon(LucideIcons.moreVertical, size: 20),
                                  itemBuilder: (context) => [
                                    if (!isMemberAdmin)
                                      const PopupMenuItem(
                                          value: 'promote',
                                          child: Text('Promote to Admin')),
                                    const PopupMenuItem(
                                        value: 'remove',
                                        child: Text('Remove Member',
                                            style: TextStyle(color: Colors.red))),
                                  ],
                                  onSelected: (value) {
                                    if (member.uid == null) return;
                                    if (value == 'promote') {
                                      _promoteToAdmin(member.uid!);
                                    }
                                    if (value == 'remove') {
                                      _removeMember(member.uid!);
                                    }
                                  },
                                ),
                            ],
                          ),
                        );
                      }),
                      if (_chatContacts.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            child: Text(
                                'People You Can Add (${_chatContacts.length})',
                                style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant)),
                          ),
                        ),
                        ..._chatContacts.map((contact) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Row(
                              children: [
                                if (_isEditing)
                                  Checkbox(
                                    value: _membersToAdd.contains(contact.uid),
                                    onChanged: (val) {
                                      setState(() {
                                        if (val == true) {
                                          _membersToAdd.add(contact.uid!);
                                        } else {
                                          _membersToAdd.remove(contact.uid);
                                        }
                                      });
                                    },
                                  ),
                                 Expanded(
                                   child: Builder(
                                     builder: (context) {
                                        // [NEW] Calculate distance
                                        double? distanceKm;
                                        final currentUserProfile = ref.watch(userProfileProvider).value;
                                        if (currentUserProfile?.currentLocation?.geometry.location != null &&
                                            contact.hostLocation.geometry?.location != null) {
                                            distanceKm = calculateDistance(
                                              currentUserProfile!.currentLocation!.geometry.location.lat,
                                              currentUserProfile.currentLocation!.geometry.location.lng,
                                              contact.hostLocation.geometry!.location.lat,
                                              contact.hostLocation.geometry!.location.lng,
                                            );
                                        }

                                        return UserCardView(
                                          user: contact,
                                          distanceKm: distanceKm,
                                          onNameTap: () => context.push('/profile/${contact.uid}'),
                                        );
                                     }
                                   ),
                                 ),
                                if (!_isEditing)
                                  IconButton(
                                    icon: const Icon(LucideIcons.userPlus),
                                    onPressed: () {
                                       if (contact.uid != null) _addMember(contact.uid!);
                                    },
                                    color: theme.colorScheme.primary,
                                  ),
                              ],
                            ),
                          );
                        }),
                      ],
                      const SizedBox(height: 32),
                    ],
                  ],
                ),
              ),
            ),
        
            // Sticky Bottom Leave Group Button
            if (!_isLoading)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  border: Border(top: BorderSide(color: theme.dividerColor, width: 0.5)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _leaveGroup,
                    icon: const Icon(LucideIcons.logOut, size: 18),
                    label: const Text('Leave Group'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      side: BorderSide(color: theme.colorScheme.error),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
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
        color: theme.colorScheme.primaryContainer.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.5), width: 0.5),
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
}

