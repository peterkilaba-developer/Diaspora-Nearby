import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

import 'package:intl/intl.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/core/data/countries.dart' as country_data;
import 'package:cloud_firestore/cloud_firestore.dart';

class OrganizationChatPreview extends ConsumerStatefulWidget {
  final String chatId;
  final String title;

  const OrganizationChatPreview({
    super.key,
    required this.chatId,
    this.title = 'Community Chat',
  });

  @override
  ConsumerState<OrganizationChatPreview> createState() =>
      _OrganizationChatPreviewState();
}

class _OrganizationChatPreviewState
    extends ConsumerState<OrganizationChatPreview> {
  final TextEditingController _messageController = TextEditingController();

  void _showSendMessageDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 8.0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ), // Use rounded corners if we have margins
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.zero,
          decoration: AppTheme.cardDecoration(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Send Message',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(LucideIcons.x, size: 20),
                    ),
                  ],
                ),
              ),

              // Content
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _messageController,
                  decoration: const InputDecoration(
                    hintText: 'Type your message...',
                    border: OutlineInputBorder(),
                    filled: true,
                  ),
                  maxLines: 4,
                ),
              ),

              // Footer Actions
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: FilledButton(
                  onPressed: () {
                    final text = _messageController.text.trim();
                    if (text.isNotEmpty) {
                      _sendMessage(text);
                      Navigator.pop(context);
                      _messageController.clear();
                    }
                  },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Send Message'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendMessage(String text) async {
    try {
      await ref
          .read(chatRepositoryProvider)
          .sendTextMessage(widget.chatId, text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            FutureBuilder<bool>(
              future: _canPost(ref),
              builder: (context, snapshot) {
                if (snapshot.data == true) {
                  return IconButton(
                    onPressed: _showSendMessageDialog,
                    icon: const Icon(LucideIcons.edit),
                    tooltip: 'Write Message',
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 300,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
            borderRadius: BorderRadius.circular(12),
            color: Colors.grey.withValues(alpha: 0.05),
          ),
          child: StreamBuilder<List<Message>>(
            stream: ref
                .read(chatRepositoryProvider)
                .subscribeToMessages(widget.chatId),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }

              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final messages = snapshot.data!;
              if (messages.isEmpty) {
                return const Center(
                  child: Text('No messages yet. Be the first to say hello!'),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                reverse: true, // Show newest at bottom (standard chat) or top?
                // Usually chat lists are reverse: true invalidating standard list assumptions.
                // But `subscribeToMessages` returns simpler list sorted by timestamp desc (newest first).
                // If we want "Feed style" (newest at top), we use standard ListView.
                // If we want "Chat style" (newest at bottom), we use reverse: true.
                // Let's stick to standard Feed style for a "Preview" widget, showing newest at top.
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final msg = messages[index];
                  return _buildMessageTile(msg);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// Returns true iff the current user is allowed to post into this chat.
  ///
  /// For chamber chats, posting is restricted to users whose userChats
  /// entry has `accessLevel == 'member'` — followers and visitors must NOT
  /// see the Write button (otherwise Firestore Security Rules will reject
  /// the message at send time and the user sees a confusing error).
  ///
  /// For regular chats, the legacy participant check applies.
  Future<bool> _canPost(WidgetRef ref) async {
    final currentUserId = ref.read(chatRepositoryProvider).currentUserId;
    if (currentUserId == null) return false;

    try {
      final chatDoc = await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .get();
      if (!chatDoc.exists) return false;
      final data = chatDoc.data() ?? {};
      final participants = List<String>.from(data['participants'] ?? []);
      final isParticipant = participants.contains(currentUserId);
      if (!isParticipant) return false;

      // Chamber-of-commerce chats require member-level access to post.
      // Other chat types: participant alone is enough.
      final isChamberChat = data['subtype'] == 'corridor_chamber';
      if (!isChamberChat) return true;

      final userChatDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .collection('userChats')
          .doc(widget.chatId)
          .get();
      final accessLevel = userChatDoc.data()?['accessLevel'] as String?;
      return accessLevel == 'member';
    } catch (e) {
      debugPrint('Error checking can-post status: $e');
    }
    return false;
  }

  String _getCountryFlag(String? countryCode) {
    if (countryCode == null || countryCode.isEmpty) return '';
    final country = country_data.getCountryByCode(countryCode);
    return country?.flag ?? '';
  }

  Widget _buildMessageTile(Message msg) {
    final isMe = msg.senderId == ref.read(chatRepositoryProvider).currentUserId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundImage:
                  (msg.senderImage != null && msg.senderImage!.isNotEmpty)
                  ? NetworkImage(msg.senderImage!)
                  : null,
              child: (msg.senderImage == null || msg.senderImage!.isEmpty)
                  ? Text(msg.senderName.isNotEmpty ? msg.senderName[0] : '?')
                  : null,
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isMe
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(12),
                  topRight: const Radius.circular(12),
                  bottomLeft: isMe ? const Radius.circular(12) : Radius.zero,
                  bottomRight: isMe ? Radius.zero : const Radius.circular(12),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMe)
                    Consumer(
                      builder: (context, ref, _) {
                        final profileAsync = ref.watch(
                          userProfileByIdProvider(msg.senderId),
                        );
                        return profileAsync.maybeWhen(
                          data: (profile) {
                            final countryCode =
                                profile?.currentLocation?.countryCode ??
                                profile?.hostCountryCode ??
                                profile?.hostLocation.countryCode;
                            final flag = _getCountryFlag(countryCode);

                            if (flag.isNotEmpty) {
                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    flag,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    msg.senderName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              );
                            }
                            return Text(
                              msg.senderName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            );
                          },
                          orElse: () => Text(
                            msg.senderName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        );
                      },
                    ),
                  if (!isMe) const SizedBox(height: 4),
                  if (msg.type == 'text')
                    Text(msg.content)
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getIconForType(msg.type),
                          size: 16,
                          color: Colors.grey[700],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _getTextForType(msg.type),
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(msg.timestamp),
                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays > 0) {
      return DateFormat.yMMMd().format(date); // e.g., Oct 23, 2023
    } else if (diff.inHours > 0) {
      return '${diff.inHours}h ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  IconData _getIconForType(String type) {
    switch (type) {
      case 'image':
        return LucideIcons.image;
      case 'video':
        return LucideIcons.video;
      case 'audio':
        return LucideIcons.mic;
      case 'audio_file':
        return LucideIcons.music;
      case 'document':
        return LucideIcons.file;
      case 'location':
        return LucideIcons.mapPin;
      default:
        return LucideIcons.fileText;
    }
  }

  String _getTextForType(String type) {
    switch (type) {
      case 'image':
        return 'Image';
      case 'video':
        return 'Video';
      case 'audio':
        return 'Voice Message';
      case 'audio_file':
        return 'Audio File';
      case 'document':
        return 'Document';
      case 'location':
        return 'Location';
      default:
        return 'Attachment';
    }
  }
}
