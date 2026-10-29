import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/chat/screens/chat_screen.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';

/// Screen that handles starting a direct chat with a user.
///
/// Flow:
/// 1. If a DM chat already exists → navigate directly to it.
/// 2. If no DM exists → open pending DM (chat created on first message).
///
/// Relationship selection is NOT required to start a chat.
/// Users can add relationships from the DM chat's "show more" menu.
class StartDirectChatScreen extends ConsumerStatefulWidget {
  final String otherUserId;

  const StartDirectChatScreen({super.key, required this.otherUserId});

  @override
  ConsumerState<StartDirectChatScreen> createState() =>
      _StartDirectChatScreenState();
}

class _StartDirectChatScreenState extends ConsumerState<StartDirectChatScreen> {
  String? _error;
  String? _resolvedChatId;
  String? _resolvedPendingName;
  String? _resolvedPendingImage;
  bool _resolvedAsPending = false;

  @override
  void initState() {
    super.initState();
    _trySynchronousResolution();
    if (_resolvedChatId == null && !_resolvedAsPending) {
      _loadChatOrUser();
    }
  }

  void _trySynchronousResolution() {
    final currentUser = ref.read(authRepositoryProvider).currentUser;
    if (currentUser != null && currentUser.uid == widget.otherUserId) {
      return;
    }

    final chatRepo = ref.read(chatRepositoryProvider);
    final cachedDirectChat = chatRepo.getCachedDirectChatWith(
      widget.otherUserId,
    );
    if (cachedDirectChat != null) {
      _resolvedChatId = cachedDirectChat.id;
      return;
    }

    // If user's chats are already cached in memory and no DM exists with this user,
    // and we have the target user's profile cached, open pending DM in 0ms!
    if (chatRepo.cachedChats.isNotEmpty) {
      final cachedProfile = ref
          .read(profileRepositoryProvider)
          .getCachedProfile(widget.otherUserId);
      if (cachedProfile != null) {
        final fullName =
            '${cachedProfile.firstName} ${cachedProfile.lastName}'.trim();
        _resolvedPendingName = fullName.isNotEmpty ? fullName : 'Unknown';
        _resolvedPendingImage = cachedProfile.profileImage;
        _resolvedAsPending = true;
      }
    }
  }

  Future<void> _loadChatOrUser() async {
    try {
      final chatRepo = ref.read(chatRepositoryProvider);

      final currentUser = ref.read(authRepositoryProvider).currentUser;
      if (currentUser != null && currentUser.uid == widget.otherUserId) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("You cannot chat with yourself")),
          );
          context.pop();
        }
        return;
      }

      // 1. Check if a chat already exists with this user
      final existingChat = await chatRepo.getExistingDirectChat(
        widget.otherUserId,
      );

      if (!mounted) return;

      if (existingChat != null) {
        // Chat exists - render or navigate directly to it
        setState(() {
          _resolvedChatId = existingChat;
        });
        return;
      }

      // 2. Fetch user info for the pending DM screen (check cache first)
      final cachedProfile = ref
          .read(profileRepositoryProvider)
          .getCachedProfile(widget.otherUserId);
      if (cachedProfile != null) {
        final fullName =
            '${cachedProfile.firstName} ${cachedProfile.lastName}'.trim();
        setState(() {
          _resolvedPendingName = fullName.isNotEmpty ? fullName : 'Unknown';
          _resolvedPendingImage = cachedProfile.profileImage;
          _resolvedAsPending = true;
        });
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.otherUserId)
          .get();

      if (!mounted) return;

      if (!userDoc.exists) {
        setState(() {
          _error = 'User not found';
        });
        return;
      }

      final userData = userDoc.data()!;
      final firstName = userData['firstName'] as String? ?? 'Unknown';
      final lastName = userData['lastName'] as String? ?? '';
      final userName = '$firstName $lastName'.trim();
      final profileImage = userData['profileImage'] as String?;

      // 3. No existing DM → Render pending DM chat directly
      if (!mounted) return;
      setState(() {
        _resolvedPendingName = userName;
        _resolvedPendingImage = profileImage;
        _resolvedAsPending = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_resolvedChatId != null) {
      return ChatScreen(chatId: _resolvedChatId!);
    }

    if (_resolvedAsPending) {
      return ChatScreen.pendingDM(
        pendingUserId: widget.otherUserId,
        pendingUserName: _resolvedPendingName ?? 'Unknown',
        pendingUserImage: _resolvedPendingImage,
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(_error!, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.go('/chats'),
                child: const Text('Go to Chats'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Loading...', style: theme.textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}
