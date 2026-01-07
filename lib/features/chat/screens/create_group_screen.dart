import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/models/profile_data.dart';
import 'package:diaspora_nearby/features/shared/widgets/user_card.dart';

class CreateGroupScreen extends ConsumerStatefulWidget {
  final String? initialParticipantId;
  
  const CreateGroupScreen({super.key, this.initialParticipantId});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final TextEditingController _nameController = TextEditingController();
  final Set<String> _selectedIds = {};
  File? _groupImage;
  bool _isLoading = false;
  bool _isLoadingContacts = true;
  List<ProfileData> _contacts = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialParticipantId != null) {
      _selectedIds.add(widget.initialParticipantId!);
    }
    _loadContacts();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    setState(() => _isLoadingContacts = true);
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
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _groupImage = File(picked.path);
      });
    }
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (_groupImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a group photo')));
      return;
    }
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a group name')));
      return;
    }
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select at least one member')));
      return;
    }

    setState(() => _isLoading = true);
    final repo = ref.read(chatRepositoryProvider);
    
    // Create logic
    final chatId = await repo.createGroup(name, _selectedIds.toList(), groupImage: _groupImage);
    
    if (mounted) {
      setState(() => _isLoading = false);
      if (chatId != null) {
        // Pop this screen and replace with chat screen
        if (context.canPop()) context.pop();
        context.pushReplacement('/chats/$chatId');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to create group')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.x),
          onPressed: () => context.pop(),
        ),
        title: const Text('Create New Group'),
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
                                    ? DecorationImage(image: FileImage(_groupImage!), fit: BoxFit.cover)
                                    : null,
                              ),
                              child: _groupImage == null
                                  ? Center(
                                      child: _nameController.text.isNotEmpty
                                          ? Text(
                                              _nameController.text.substring(0, 1).toUpperCase(),
                                              style: theme.textTheme.titleLarge?.copyWith(
                                                  color: theme.colorScheme.onPrimaryContainer
                                              ),
                                            )
                                          : Icon(LucideIcons.users, color: theme.colorScheme.onPrimaryContainer),
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
                                  border: Border.all(color: theme.scaffoldBackgroundColor, width: 2),
                                ),
                                child: const Icon(LucideIcons.camera, size: 12, color: Colors.white),
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
                          decoration: const InputDecoration(
                            labelText: 'Group Name',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          onChanged: (val) => setState(() {}), // rebuild for avatar preview
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // Members Section
                  Text(
                    'Add Members (${_selectedIds.length} selected)',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  
                  if (_isLoadingContacts)
                    const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
                  else if (_contacts.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(LucideIcons.users, size: 48, color: theme.disabledColor),
                            const SizedBox(height: 16),
                            const Text('No contacts found'),
                            Text('Start chatting with people to add them.', style: theme.textTheme.bodySmall),
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
                          child: UserCardView(
                            user: contact,
                            isStatic: true,
                            backgroundColor: isSelected
                                ? theme.colorScheme.primaryContainer.withOpacity(0.5)
                                : null,
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
          
          // Fixed Footer
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                border: Border(top: BorderSide(color: theme.dividerColor)),
              ),
             child: Row(
               children: [
                 Expanded(
                   child: OutlinedButton(
                     onPressed: _isLoading ? null : () => context.pop(),
                     child: const Text('Cancel'),
                   ),
                 ),
                 const SizedBox(width: 16),
                 Expanded(
                   child: FilledButton(
                     onPressed: (_isLoading ||
                                  _nameController.text.isEmpty ||
                                  _selectedIds.isEmpty ||
                                  _groupImage == null)
                         ? null
                         : _createGroup,
                     child: _isLoading
                         ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                         : const Text('Create Group'),
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
