import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/chat/screens/chat_screen.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/relationship_repository.dart';
import 'package:diaspora_nearby/features/profile/widgets/relationship_selection_modal.dart';

/// Screen that handles starting a direct chat with a user.
///
/// Flow:
/// 1. If a DM chat already exists → navigate directly to it.
/// 2. If a relationship already exists → open pending DM (chat created on first message).
/// 3. If NO relationship → show RelationshipSelectionModal first.
///    - After the user selects a type the modal sends a request and closes.
///    - We go back and inform the user that the chat will open when the request is accepted.
///    - On acceptance (handled by `acceptRequest`), a DM chat is auto-created and
///      the sender is navigated there via the sync listener / push notification.
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

      // 1. Check if a chat already exists with this user
      final existingChat = await chatRepo.getExistingDirectChat(
        widget.otherUserId,
      );

      if (!mounted) return;

      if (existingChat != null) {
        // Chat exists - navigate directly to it
        context.go('/chats/$existingChat');
        return;
      }

      // 2. Fetch user info
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

      // 3. Check if a relationship already exists between users
      if (currentUser != null) {
        final relRepo = ref.read(relationshipRepositoryProvider);
        final existingRel = await relRepo.getRelationship(
          userId: currentUser.uid,
          relatedUserId: widget.otherUserId,
        );

        if (!mounted) return;

        // No relationship exists — prompt relationship selection first
        if (existingRel == null) {
          // Also check if there's already a pending request between them
          final pendingRequest = await _checkPendingRequest(
            currentUser.uid,
            widget.otherUserId,
          );

          if (!mounted) return;

          if (pendingRequest != null) {
            // Already have a pending request — inform and go back
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  pendingRequest == 'sent'
                      ? 'Relationship request already sent. Chat will open when $userName accepts.'
                      : 'You have a pending request from $userName. Check your notifications.',
                ),
                duration: const Duration(seconds: 4),
              ),
            );
            context.pop();
            return;
          }

          setState(() => _isLoading = false);

          // Show relationship selection modal
          await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (modalContext) => RelationshipSelectionModal(
              otherUserId: widget.otherUserId,
              otherUserName: userName,
              includeFriend: true,
            ),
          );

          if (!mounted) return;

          // The modal handles sending the request internally via _saveRelationship.
          // After the modal closes (either by selecting or dismissing):
          // - If a request was sent, the snackbar from the modal already shows.
          // - We inform the user about the next step and go back.
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Chat with $userName will open when the relationship request is accepted.',
              ),
              duration: const Duration(seconds: 4),
            ),
          );
          context.pop();
          return;
        }
      }

      // 4. Relationship exists → Navigate to chat screen with pending DM info
      // The actual chat will be created when the first message is sent
      if (!mounted) return;
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

  /// Check if there's already a pending relationship request between the two users.
  /// Returns 'sent' if current user sent one, 'received' if they received one, or null.
  Future<String?> _checkPendingRequest(
    String currentUserId,
    String otherUserId,
  ) async {
    try {
      // Check if I already sent a request
      final sentQuery = await FirebaseFirestore.instance
          .collection('relationship_requests')
          .where('fromUserId', isEqualTo: currentUserId)
          .where('toUserId', isEqualTo: otherUserId)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();

      if (sentQuery.docs.isNotEmpty) return 'sent';

      // Check if they sent me a request
      final receivedQuery = await FirebaseFirestore.instance
          .collection('relationship_requests')
          .where('fromUserId', isEqualTo: otherUserId)
          .where('toUserId', isEqualTo: currentUserId)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();

      if (receivedQuery.docs.isNotEmpty) return 'received';

      return null;
    } catch (e) {
      debugPrint('Error checking pending requests: $e');
      return null;
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
