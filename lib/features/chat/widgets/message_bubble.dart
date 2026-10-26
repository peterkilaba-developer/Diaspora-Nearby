import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/core/data/countries.dart' as country_data;
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/marketplace/widgets/marketplace_card_helpers.dart';

import 'message_content/text_message_content.dart';
import 'message_content/image_message_content.dart';
import 'message_content/video_message_content.dart';
import 'message_content/audio_message_content.dart';
import 'message_content/document_message_content.dart';
import 'message_content/location_message_content.dart';
import 'message_content/dsp_transfer_message_content.dart'; // [NEW]
import 'message_content/money_transfer_message_content.dart';
import 'message_content/hosting_request_message_content.dart'; // [NEW] Hosting
import 'message_content/hosting_arrangement_message_content.dart'; // [NEW] Hosting DM

/// Message Bubble Widget
/// Displays a single message in the chat
class MessageBubble extends ConsumerWidget {
  final Message message;
  final bool isOwn;
  final String? senderName;
  final VoidCallback? onReply;
  final Function(String)? onReplyTap; // Callback to jump to message
  final VoidCallback? onLongPress; // Add callback for long press
  final VoidCallback? onRetry; // Callback to retry sending failed messages
  final Message?
  repliedMessage; // The message being replied to (if replyTo is set)
  final bool
  isHighlighted; // Whether the message is currently highlighted (from "Jump to Message")
  final bool showAvatar; // Show avatar for group chats, hide for DMs
  final String? sellerRole; // Seller/Provider/Employer role for listing chats

  const MessageBubble({
    super.key,
    required this.message,
    required this.isOwn,
    this.senderName,
    this.onReply,
    this.onReplyTap,
    this.onLongPress,
    this.onRetry,
    this.repliedMessage,
    this.isHighlighted = false,
    this.showAvatar = true, // Default to true for backwards compatibility
    this.sellerRole,
  });

  String _formatTime(int timestamp) {
    final time = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateFormat('h:mm a').format(time);
  }

  String _getCountryFlag(String? countryCode) {
    if (countryCode == null || countryCode.isEmpty) return '';
    final country = country_data.getCountryByCode(countryCode);
    return country?.flag ?? '';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // Handle deleted for everyone
    if (message.isDeletedForEveryone) {
      return _buildDeletedMessage(theme);
    }

    // [NEW] Hosting request system messages render as standalone cards
    if (message.type == 'system' &&
        message.metadata?['systemType'] == 'hosting_request') {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: HostingRequestMessageContent(message: message, isOwn: isOwn),
        ),
      );
    }

    // [NEW] Hosting arrangement messages render as standalone green cards
    if (message.type == 'system' &&
        message.metadata?['systemType'] == 'hosting_arrangement') {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Align(
          alignment: Alignment.center,
          child: HostingArrangementMessageContent(
            message: message,
            isOwn: isOwn,
          ),
        ),
      );
    }

    return Dismissible(
      key: Key('message_${message.id}'),
      direction: DismissDirection.startToEnd,
      confirmDismiss: (direction) async {
        if (onReply != null) {
          onReply!();
          return false;
        }
        return false;
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: Icon(LucideIcons.reply, color: theme.colorScheme.primary),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          top: 4,
          bottom: message.reactions != null && message.reactions!.isNotEmpty
              ? 24
              : 4,
          left: isOwn ? 0 : 8,
          right: isOwn ? 8 : 0,
        ),
        child: Consumer(
          builder: (context, ref, child) {
            // [FIX] Fetch profile data at the top level of the bubble
            final profileAsync = ref.watch(
              userProfileByIdProvider(message.senderId),
            );
            final profile = profileAsync.value;

            return Row(
              mainAxisAlignment: isOwn
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              crossAxisAlignment:
                  CrossAxisAlignment.start, // [FIX] Align avatar to top
              children: [
                // Avatar for incoming messages (only in group chats, not DMs)
                // Now uses fetched profile data
                if (!isOwn && showAvatar) ...[
                  _buildAvatar(context, theme, profile),
                  const SizedBox(width: 8),
                ],

                Flexible(
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Message Bubble Container (Interactive)
                            GestureDetector(
                              onLongPress: onLongPress,
                              child: Stack(
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    padding: EdgeInsets
                                        .zero, // [FIX] Ensure full bleed for media
                                    clipBehavior: Clip
                                        .antiAlias, // Clip children to border radius
                                    decoration: BoxDecoration(
                                      color: isHighlighted
                                          ? theme.colorScheme.primary
                                                .withValues(alpha: 0.4)
                                          : (isOwn
                                                ? theme.colorScheme.primary
                                                : theme.cardColor),
                                      borderRadius: BorderRadius.only(
                                        topLeft: const Radius.circular(16),
                                        topRight: const Radius.circular(16),
                                        bottomLeft: Radius.circular(
                                          isOwn ? 16 : 4,
                                        ),
                                        bottomRight: Radius.circular(
                                          isOwn ? 4 : 16,
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize
                                          .min, // Ensure it hugs content
                                      children: [
                                        // [FIX] Name and Flag INSIDE the bubble, above content
                                        if (!isOwn && showAvatar) ...[
                                          _buildNameAndFlag(
                                            context,
                                            theme,
                                            profile,
                                          ),
                                        ],

                                        // Forwarded indicator
                                        if (message.forwarded == true)
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              12,
                                              8,
                                              12,
                                              4,
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  LucideIcons.cornerUpRight,
                                                  size: 12,
                                                  color: isOwn
                                                      ? theme
                                                            .colorScheme
                                                            .onPrimary
                                                            .withValues(
                                                              alpha: 0.7,
                                                            )
                                                      : theme
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Forwarded',
                                                  style: theme
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: isOwn
                                                            ? theme
                                                                  .colorScheme
                                                                  .onPrimary
                                                                  .withValues(
                                                                    alpha: 0.7,
                                                                  )
                                                            : theme
                                                                  .colorScheme
                                                                  .onSurfaceVariant,
                                                        fontStyle:
                                                            FontStyle.italic,
                                                        fontSize: 11,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),

                                        // Reply preview
                                        if (repliedMessage != null)
                                          GestureDetector(
                                            onTap: () => onReplyTap?.call(
                                              repliedMessage!.id,
                                            ),
                                            child: Container(
                                              margin: const EdgeInsets.fromLTRB(
                                                12,
                                                8,
                                                12,
                                                4,
                                              ),
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: isOwn
                                                    ? theme
                                                          .colorScheme
                                                          .onPrimary
                                                          .withValues(
                                                            alpha: 0.15,
                                                          )
                                                    : theme.colorScheme.primary
                                                          .withValues(
                                                            alpha: 0.1,
                                                          ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: IntrinsicHeight(
                                                child: Row(
                                                  children: [
                                                    // Vertical bar
                                                    Container(
                                                      width: 3,
                                                      decoration: BoxDecoration(
                                                        color: theme
                                                            .colorScheme
                                                            .primary,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              2,
                                                            ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            repliedMessage!
                                                                .senderName,
                                                            style: theme
                                                                .textTheme
                                                                .bodySmall
                                                                ?.copyWith(
                                                                  color: isOwn
                                                                      ? theme
                                                                            .colorScheme
                                                                            .onPrimary
                                                                      : theme
                                                                            .colorScheme
                                                                            .primary,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                          ),
                                                          const SizedBox(
                                                            height: 2,
                                                          ),
                                                          _buildReplyContentSnippet(
                                                            theme,
                                                            repliedMessage!,
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    // Optional small image thumbnail
                                                    if (repliedMessage!
                                                            .imageUrl !=
                                                        null) ...[
                                                      const SizedBox(width: 8),
                                                      ClipRRect(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              4,
                                                            ),
                                                        child: Image.network(
                                                          repliedMessage!
                                                              .imageUrl!,
                                                          width: 30,
                                                          height: 30,
                                                          fit: BoxFit.cover,
                                                          errorBuilder:
                                                              (
                                                                context,
                                                                error,
                                                                stackTrace,
                                                              ) => const Icon(
                                                                LucideIcons
                                                                    .image,
                                                                size: 16,
                                                              ),
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),

                                        // Content
                                        _buildMessageContent(context),

                                        // [NEW] Verified Solution Badge
                                        if (message
                                                .metadata?['isVerifiedSolution'] ==
                                            true)
                                          const Padding(
                                            padding: EdgeInsets.fromLTRB(
                                              12,
                                              4,
                                              12,
                                              0,
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  LucideIcons.badgeCheck,
                                                  size: 13,
                                                  color: AppTheme.accent,
                                                ),
                                                SizedBox(width: 4),
                                                Text(
                                                  'Verified Solution',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppTheme.accent,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                        const SizedBox(height: 4),

                                        // Footer (Time, Edits, Status)
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            12,
                                            0,
                                            12,
                                            8,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (message.edited == true) ...[
                                                Text(
                                                  'edited',
                                                  style: theme
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: isOwn
                                                            ? theme
                                                                  .colorScheme
                                                                  .onPrimary
                                                                  .withValues(
                                                                    alpha: 0.7,
                                                                  )
                                                            : theme
                                                                  .colorScheme
                                                                  .onSurfaceVariant,
                                                        fontSize: 10,
                                                        fontStyle:
                                                            FontStyle.italic,
                                                      ),
                                                ),
                                                const SizedBox(width: 4),
                                              ],
                                              Text(
                                                _formatTime(message.timestamp),
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                      color: isOwn
                                                          ? theme
                                                                .colorScheme
                                                                .onPrimary
                                                                .withValues(
                                                                  alpha: 0.7,
                                                                )
                                                          : theme
                                                                .colorScheme
                                                                .onSurfaceVariant,
                                                      fontSize: 11,
                                                    ),
                                              ),
                                              if (isOwn &&
                                                  message.status != null) ...[
                                                const SizedBox(width: 4),
                                                _buildStatusIcon(
                                                  context,
                                                  message.status!,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Loading Overlay
                                  if (message.status == 'sending')
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        ignoring: false, // Catch touches
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(
                                              alpha: 0.3,
                                            ),
                                            borderRadius: BorderRadius.only(
                                              topLeft: const Radius.circular(
                                                16,
                                              ),
                                              topRight: const Radius.circular(
                                                16,
                                              ),
                                              bottomLeft: Radius.circular(
                                                isOwn ? 16 : 4,
                                              ),
                                              bottomRight: Radius.circular(
                                                isOwn ? 4 : 16,
                                              ),
                                            ),
                                          ),
                                          alignment: Alignment.center,
                                          child: const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 3,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    Colors.white,
                                                  ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        // Reactions Display
                        if (message.reactions != null &&
                            message.reactions!.isNotEmpty)
                          _buildReactions(theme),

                        // Retry Button
                        if (isOwn &&
                            message.status == 'error' &&
                            onRetry != null)
                          _buildRetryButton(),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // [FIX] Helper to build name and flag inside bubble
  Widget _buildNameAndFlag(
    BuildContext context,
    ThemeData theme,
    dynamic profile,
  ) {
    final countryCode =
        profile?.currentLocation?.countryCode ??
        profile?.hostCountryCode ??
        profile?.hostLocation.countryCode;

    final flag = _getCountryFlag(countryCode);
    final displayName = profile?.fullName ?? senderName ?? 'Unknown';

    return GestureDetector(
      onTap: () {
        context.push('/profile/${message.senderId}');
      },
      child: Container(
        // [FIX] Removed width: double.infinity to allow bubble to hug content
        decoration: const BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
          ),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 6,
        ), // [FIX] Adjusted padding
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (flag.isNotEmpty) ...[
              Text(flag, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 4),
            ],
            // Use Flexible to prevent overflow
            Flexible(
              child: Text(
                displayName,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isOwn
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Seller role badge
            if (sellerRole != null && !isOwn) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _getRoleBadgeColor(
                    sellerRole!,
                  ).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  sellerRole!,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: _getRoleBadgeColor(sellerRole!),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Returns a color for the seller role badge
  Color _getRoleBadgeColor(String role) {
    switch (role.toLowerCase()) {
      case 'employer':
        return const Color(0xFF3B82F6); // Blue
      case 'provider':
        return const Color(0xFF8B5CF6); // Purple
      case 'seller':
        return marketplaceSageGreen; // Sage green
      default:
        return marketplaceSageGreen;
    }
  }

  Widget _buildAvatar(BuildContext context, ThemeData theme, dynamic profile) {
    final imageUrl = profile?.profileImage ?? message.senderImage;
    if (imageUrl == null) return const SizedBox(width: 32, height: 32);

    return GestureDetector(
      onTap: () {
        context.push('/profile/${message.senderId}');
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundImage: NetworkImage(imageUrl),
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            onBackgroundImageError: (exception, stackTrace) {},
            child: null,
          ),
          if (message.adminImage != null)
            Positioned(
              bottom: -2,
              right: -2,
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0x14888888),
                  shape: BoxShape.circle,
                ),
                child: CircleAvatar(
                  radius: 8,
                  backgroundImage: NetworkImage(message.adminImage!),
                  backgroundColor: theme.colorScheme.primaryContainer,
                  onBackgroundImageError: (exception, stackTrace) {},
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageContent(BuildContext context) {
    switch (message.type) {
      case 'image':
        return ImageMessageContent(message: message, isOwn: isOwn);
      case 'video':
        return VideoMessageContent(message: message, isOwn: isOwn);
      case 'audio':
      case 'audio_file':
        return AudioMessageContent(message: message, isOwn: isOwn);
      case 'location':
        return LocationMessageContent(message: message, isOwn: isOwn);
      case 'document':
        return DocumentMessageContent(message: message, isOwn: isOwn);
      case 'dsp_transfer': // [NEW]
        return DSPTransferMessageContent(message: message, isOwn: isOwn);
      case 'money-transfer':
        return MoneyTransferMessageContent(message: message, isOwn: isOwn);
      case 'system':
        // Check for hosting request system messages
        if (message.metadata?['systemType'] == 'hosting_request') {
          return HostingRequestMessageContent(message: message, isOwn: isOwn);
        }
        return TextMessageContent(message: message, isOwn: isOwn);
      default:
        return TextMessageContent(message: message, isOwn: isOwn);
    }
  }

  Widget _buildStatusIcon(BuildContext context, String status) {
    final theme = Theme.of(context);
    IconData icon;
    Color color = isOwn
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurfaceVariant;

    switch (status) {
      case 'sending':
        icon = LucideIcons.clock;
        break;
      case 'sent':
        icon = LucideIcons.check;
        break;
      case 'delivered':
        icon = LucideIcons.checkCheck;
        break;
      case 'read':
        icon = LucideIcons.checkCheck;
        color = const Color(0xFF40C4FF); // Vibrant light blue for read status
        break;
      case 'error':
        icon = LucideIcons.alertCircle;
        color = theme.colorScheme.error;
        break;
      default:
        icon = LucideIcons.clock;
    }

    return Icon(icon, size: 12, color: color.withValues(alpha: 0.8));
  }

  Widget _buildDeletedMessage(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.trash2,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            'This message was deleted',
            style: TextStyle(
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReactions(ThemeData theme) {
    return Positioned(
      bottom: -20,
      right: isOwn ? null : 0,
      left: isOwn ? 0 : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: message.reactions!.map((r) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                '${r.emoji} ${showAvatar ? r.userIds.length : (r.userIds.length > 1 ? r.userIds.length : '')}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontSize: 12,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildRetryButton() {
    return Positioned(
      left: -40,
      top: 0,
      bottom: 0,
      child: Center(
        child: GestureDetector(
          onTap: onRetry,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              LucideIcons.refreshCw,
              size: 16,
              color: Colors.red.shade700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReplyContentSnippet(ThemeData theme, Message repliedMessage) {
    IconData? mediaIcon;
    String contentText = repliedMessage.content;

    switch (repliedMessage.type) {
      case 'image':
        mediaIcon = LucideIcons.image;
        contentText = 'Photo';
        break;
      case 'video':
        mediaIcon = LucideIcons.video;
        contentText = 'Video';
        break;
      case 'audio':
      case 'audio_file':
        mediaIcon = LucideIcons.mic;
        contentText = 'Voice message';
        break;
      case 'location':
        mediaIcon = LucideIcons.mapPin;
        contentText = 'Location';
        break;
      case 'document':
        mediaIcon = LucideIcons.fileText;
        contentText = repliedMessage.documentName ?? 'Document';
        break;
    }

    return Row(
      children: [
        if (mediaIcon != null) ...[
          Icon(
            mediaIcon,
            size: 10,
            color: isOwn
                ? theme.colorScheme.onPrimary.withValues(alpha: 0.7)
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Text(
            contentText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isOwn
                  ? theme.colorScheme.onPrimary.withValues(alpha: 0.8)
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
