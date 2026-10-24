import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'package:diaspora_nearby/features/shared/services/content_share_service.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/chat/screens/forward_chat_selection_screen.dart';
import 'package:diaspora_nearby/features/shared/widgets/bottom_sheet_item.dart';
import 'package:diaspora_nearby/features/trust/widgets/trust_slider_widget.dart';
import 'package:diaspora_nearby/features/profile/repository/relationship_repository.dart';
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';

/// Bottom sheet for message actions (Reactions, Reply, Forward, etc.)
class ChatMessageActionSheet extends ConsumerWidget {
  final Message message;
  final bool isOwn;
  final String? currentUserId;
  final Function(Message message)? onReply;
  final Function(Message message, String emoji)? onReaction;
  final Function(Message message)? onReportMessage;
  final Function(String userId, String userName)? onBlockUser;
  final Function(String userId, String userName)? onReportUser;
  final Function(Message message)? onVerifySolution;
  final Function(Message message)? onDelete;

  const ChatMessageActionSheet({
    super.key,
    required this.message,
    required this.isOwn,
    this.currentUserId,
    this.onReply,
    this.onReaction,
    this.onReportMessage,
    this.onBlockUser,
    this.onReportUser,
    this.onVerifySolution,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Reaction Bar
            SizedBox(
              height: 60,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: ['❤️', '😂', '👍', '👎', '😮', '😢', '🙏'].map((
                  emoji,
                ) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        onReaction?.call(message, emoji);
                      },
                      child: Text(emoji, style: const TextStyle(fontSize: 32)),
                    ),
                  );
                }).toList(),
              ),
            ),
            const Divider(),

            // Scrollable action list
            Flexible(
              child: SingleChildScrollView(
                child: Builder(
                  builder: (context) {
                    final theme = Theme.of(context);
                    final isFamilySender =
                        !isOwn &&
                        currentUserId != null &&
                        ((ref
                                    .watch(
                                      userRelationshipsProvider(currentUserId!),
                                    )
                                    .value
                                    ?.any(
                                      (r) =>
                                          r.id == message.senderId &&
                                          r.status == 'active' &&
                                          TrustSliderWidget.isFamilyRelationshipType(
                                            r.type,
                                          ),
                                    ) ??
                                false) ||
                            TrustSliderWidget.isFamilyRelationshipType(
                              ref
                                  .watch(userTrustProvider(currentUserId!))
                                  .value
                                  ?.relationshipTypes[message.senderId],
                            ));
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Inline Trust Slider — visible immediately for non-family other users' messages
                        if (!isOwn &&
                            currentUserId != null &&
                            !isFamilySender) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            child: TrustSliderWidget(
                              targetUserId: message.senderId,
                              currentUserId: currentUserId!,
                              displayName: message.senderName,
                            ),
                          ),
                          const Divider(height: 1),
                        ],

                        AppBottomSheetItem(
                          icon: LucideIcons.reply,
                          iconColor: theme.colorScheme.primary,
                          iconBgColor: theme.colorScheme.primaryContainer
                              .withValues(alpha: 0.5),
                          title: 'Reply',
                          subtitle: 'Reply to this message',
                          onTap: () {
                            Navigator.pop(context);
                            onReply?.call(message);
                          },
                        ),
                        AppBottomSheetItem(
                          icon: LucideIcons.forward,
                          iconColor: Colors.blue.shade700,
                          iconBgColor: Colors.blue.shade50,
                          title: 'Forward',
                          subtitle: 'Send to another chat',
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ForwardChatSelectionScreen(
                                  message: message,
                                ),
                              ),
                            );
                          },
                        ),
                        AppBottomSheetItem(
                          icon: LucideIcons.copy,
                          iconColor: Colors.grey.shade700,
                          iconBgColor: Colors.grey.shade100,
                          title: 'Copy',
                          subtitle: 'Copy text to clipboard',
                          onTap: () {
                            Navigator.pop(context);
                            Clipboard.setData(
                              ClipboardData(text: message.content),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Message copied')),
                            );
                          },
                        ),
                        AppBottomSheetItem(
                          icon: LucideIcons.share2,
                          iconColor: Colors.blue.shade700,
                          iconBgColor: Colors.blue.shade50,
                          title: 'Share',
                          subtitle: 'Share outside the app',
                          onTap: () {
                            Navigator.pop(context);
                            ref
                                .read(contentShareServiceProvider)
                                .shareMessage(context, message);
                          },
                        ),
                        if (!isOwn) ...[
                          AppBottomSheetItem(
                            icon: LucideIcons.ban,
                            iconColor: Colors.grey.shade700,
                            iconBgColor: Colors.grey.shade100,
                            title: 'Block Sender',
                            subtitle: 'Stop receiving messages from this user',
                            onTap: () {
                              Navigator.pop(context);
                              onBlockUser?.call(
                                message.senderId,
                                message.senderName,
                              );
                            },
                          ),
                          AppBottomSheetItem(
                            icon: LucideIcons.flag,
                            iconColor: AppTheme.error,
                            iconBgColor: AppTheme.error.withValues(alpha: 0.1),
                            title: 'Report Sender',
                            subtitle: 'Earn 100 DSP for reporting violations',
                            isDestructive: true,
                            onTap: () {
                              Navigator.pop(context);
                              onReportUser?.call(
                                message.senderId,
                                message.senderName,
                              );
                            },
                          ),
                          AppBottomSheetItem(
                            icon: LucideIcons.flag,
                            iconColor: AppTheme.error,
                            iconBgColor: AppTheme.error.withValues(alpha: 0.1),
                            title: 'Report Message',
                            subtitle: 'Earn 100 DSP for reporting violations',
                            isDestructive: true,
                            onTap: () {
                              Navigator.pop(context);
                              onReportMessage?.call(message);
                            },
                          ),
                          AppBottomSheetItem(
                            icon: LucideIcons.checkCircle2,
                            iconColor: Colors.green.shade700,
                            iconBgColor: Colors.green.shade50,
                            title: 'Mark as Verified Solution',
                            subtitle: 'Earn 1,000 DSP · Boost sender\'s PCT',
                            onTap: () {
                              Navigator.pop(context);
                              onVerifySolution?.call(message);
                            },
                          ),
                        ],
                        if (isOwn)
                          AppBottomSheetItem(
                            icon: LucideIcons.trash2,
                            iconColor: AppTheme.error,
                            iconBgColor: AppTheme.error.withValues(alpha: 0.1),
                            title: 'Delete',
                            subtitle: 'Remove this message for everyone',
                            isDestructive: true,
                            onTap: () {
                              Navigator.pop(context);
                              onDelete?.call(message);
                            },
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
