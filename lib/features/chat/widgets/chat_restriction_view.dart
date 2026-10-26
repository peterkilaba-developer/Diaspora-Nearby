import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
// Assuming the Chat model is at this path, adjustment might be needed
// import 'package:diaspora_nearby/features/chat/models/chat.dart';

/// View shown when a user is not a participant of a chat
/// and is restricted from sending messages.
class ChatRestrictionView extends StatelessWidget {
  final bool isCommunity;
  final bool isOrganization;
  final bool isEvent;
  final bool isListingChat;
  final String chatName;
  final String chatType;
  final VoidCallback? onJoin;
  final bool isJoining;

  const ChatRestrictionView({
    super.key,
    required this.isCommunity,
    required this.isOrganization,
    required this.isEvent,
    this.isListingChat = false,
    required this.chatName,
    required this.chatType,
    this.onJoin,
    this.isJoining = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // If it's a joinable group
    if (chatType == 'group' && onJoin != null) {
      return SafeArea(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: FilledButton.icon(
            onPressed: isJoining ? null : onJoin,
            icon: isJoining
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(LucideIcons.plus),
            label: Text(
              isJoining
                  ? 'Joining...'
                  : (isListingChat ? 'Join Shop' : 'Join Group'),
            ),
          ),
        ),
      );
    }

    // Default "Locked" view for other types (or restricted)
    return SafeArea(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        decoration: BoxDecoration(color: theme.colorScheme.surface),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.lock,
              size: 20,
              color: theme.colorScheme.secondary,
            ),
            const SizedBox(height: 8),
            Text(
              isCommunity
                  ? 'Only members of the $chatName community can post here.'
                  : isOrganization
                  ? 'Only authorized participants can post to this organization board.'
                  : isEvent
                  ? 'Only attendees can post to this event chat.'
                  : 'You are not a participant of this group.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.secondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
