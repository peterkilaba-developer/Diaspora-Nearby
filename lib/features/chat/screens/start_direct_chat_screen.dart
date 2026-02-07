import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/chat/screens/chat_screen.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';

/// Screen that handles starting a direct chat with a user
/// First checks if chat already exists, if so navigates to it
/// Otherwise shows pending DM state - the actual chat is created when first message is sent
class StartDirectChatScreen extends ConsumerStatefulWidget {
  final String otherUserId;

  const StartDirectChatScreen({super.key, required this.otherUserId});

  @override
  ConsumerState<StartDirectChatScreen> createState() =>
      _StartDirectChatScreenState();
}

class _StartDirectChatScreenState extends ConsumerState<StartDirectChatScreen> {
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadChatOrUser();
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

      // First check if a chat already exists with this user
      final existingChat = await chatRepo.getExistingDirectChat(
        widget.otherUserId,
      );

      if (!mounted) return;

      if (existingChat != null) {
        // Chat exists - navigate directly to it
        context.go('/chats/$existingChat');
        return;
      }

      // No existing chat - fetch user info for pending DM state
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.otherUserId)
          .get();

      if (!mounted) return;

      if (!userDoc.exists) {
        setState(() {
          _error = 'User not found';
          _isLoading = false;
        });
        return;
      }

      final userData = userDoc.data()!;
      final firstName = userData['firstName'] as String? ?? 'Unknown';
      final lastName = userData['lastName'] as String? ?? '';
      final userName = '$firstName $lastName'.trim();
      final profileImage = userData['profileImage'] as String?;

      // Navigate to chat screen with pending DM info
      // The actual chat will be created when the first message is sent
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => ChatScreen.pendingDM(
            pendingUserId: widget.otherUserId,
            pendingUserName: userName,
            pendingUserImage: profileImage,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
