import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/models/message.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:diaspora_nearby/features/chat/widgets/document_viewer_screen.dart';
import 'package:diaspora_nearby/config/env.dart';

/// Message Bubble Widget
/// Displays a single message in the chat
class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isOwn;
  final String? senderName;
  final VoidCallback? onReply;
  final VoidCallback? onLongPress; // Add callback for long press
  final VoidCallback? onRetry; // Callback to retry sending failed messages
  final Message? repliedMessage; // The message being replied to (if replyTo is set)
  final bool showAvatar; // Show avatar for group chats, hide for DMs

  const MessageBubble({
    super.key,
    required this.message,
    required this.isOwn,
    this.senderName,
    this.onReply,
    this.onLongPress,
    this.onRetry,
    this.repliedMessage,
    this.showAvatar = true, // Default to true for backwards compatibility
  });

  String _formatTime(int timestamp) {
    final time = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateFormat('h:mm a').format(time);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Handle deleted for everyone
    if (message.isDeletedForEveryone) {
      return _buildDeletedMessage(theme);
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
        child: Icon(
          LucideIcons.reply,
          color: theme.colorScheme.primary,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          top: 4,
          bottom: message.reactions != null && message.reactions!.isNotEmpty ? 24 : 4,
          left: isOwn ? 0 : 8,
          right: isOwn ? 8 : 0,
        ),
        child: Row(
          mainAxisAlignment: isOwn ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Avatar for incoming messages (only in group chats, not DMs)
            if (!isOwn && showAvatar) ...[
               _buildAvatar(theme),
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
                        // Sender name (for non-own messages in group chats)
                        if (!isOwn && senderName != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 12, bottom: 4),
                            child: Text(
                              senderName!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          
                        // Message Bubble Container (Interactive)
                        GestureDetector(
                          onLongPress: onLongPress, // Use passed callback
                          child: Container(
                            // padding: const EdgeInsets.zero, // Default is 0, explicit for flush content
                            clipBehavior: Clip.antiAlias, // Clip children to border radius
                            decoration: BoxDecoration(
                              color: isOwn
                                  ? theme.colorScheme.primary // Uses global accent from theme
                                  : theme.cardColor, // Use theme card bg for incoming bubbles
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16),
                                topRight: const Radius.circular(16),
                                bottomLeft: Radius.circular(isOwn ? 16 : 4),
                                bottomRight: Radius.circular(isOwn ? 4 : 16),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min, // Ensure it hugs content
                              children: [
                                // Forwarded indicator
                                if (message.forwarded == true)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          LucideIcons.cornerUpRight,
                                          size: 12,
                                          color: isOwn
                                              ? theme.colorScheme.onPrimary.withValues(alpha: 0.7)
                                              : theme.colorScheme.onSurfaceVariant,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Forwarded',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: isOwn
                                                ? theme.colorScheme.onPrimary.withValues(alpha: 0.7)
                                                : theme.colorScheme.onSurfaceVariant,
                                            fontStyle: FontStyle.italic,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                
                                // Reply preview
                                if (repliedMessage != null)
                                  Container(
                                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isOwn
                                          ? theme.colorScheme.onPrimary.withValues(alpha: 0.15)
                                          : theme.colorScheme.primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border(
                                        left: BorderSide(
                                          color: theme.colorScheme.primary,
                                          width: 3,
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          repliedMessage!.senderName,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: theme.colorScheme.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          repliedMessage!.content,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: isOwn
                                                ? theme.colorScheme.onPrimary.withValues(alpha: 0.8)
                                                : theme.colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  
                                // Content
                                _buildMessageContent(context, theme),
                                const SizedBox(height: 4),
                                
                                // Footer (Time, Edits, Status)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                  children: [
                                    /* Not handling starred just yet to keep UI clean, can add later */
                                    if (message.edited == true) ...[
                                      Text(
                                        'edited',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: isOwn
                                              ? theme.colorScheme.onPrimary.withValues(alpha: 0.7)
                                              : theme.colorScheme.onSurfaceVariant,
                                          fontSize: 10,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                    ],
                                    Text(
                                      _formatTime(message.timestamp),
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: isOwn
                                            ? theme.colorScheme.onPrimary.withValues(alpha: 0.7)
                                            : theme.colorScheme.onSurfaceVariant,
                                        fontSize: 11,
                                      ),
                                    ),
                                    if (isOwn && message.status != null) ...[
                                      const SizedBox(width: 4),
                                      _buildStatusIcon(message.status!),
                                    ],
                                  ],
                                ),
                              ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    // Reactions Display
                    if (message.reactions != null && message.reactions!.isNotEmpty)
                      Positioned(
                        bottom: -20,
                        right: isOwn ? null : 0, 
                        left: isOwn ? 0 : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: theme.colorScheme.surface, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 2,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: message.reactions!.map((r) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: Text(
                                   '${r.emoji} ${r.userIds.length > 1 ? r.userIds.length : ''}',
                                   style: const TextStyle(fontSize: 12),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      
                    // Retry Button
                    if (isOwn && message.status == 'error' && onRetry != null)
                      Positioned(
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
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Icon(
                                LucideIcons.refreshCw,
                                size: 16,
                                color: Colors.red.shade700,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build avatar with optional admin overlay
  Widget _buildAvatar(ThemeData theme) {
     if (message.senderImage == null) return const SizedBox(width: 32, height: 32);

     return Stack(
       clipBehavior: Clip.none, // Allow admin overlay to go outside slightly if needed
       children: [
         // Main Avatar (Sender/Org)
         CircleAvatar(
           radius: 16,
           backgroundImage: NetworkImage(message.senderImage!),
           backgroundColor: theme.colorScheme.surfaceContainerHighest,
           onBackgroundImageError: (_, __) {},
           child: null,
         ),

         // Admin Overlay (if present)
         if (message.adminImage != null)
           Positioned(
             bottom: -2,
             right: -2,
             child: Container(
               decoration: BoxDecoration(
                 shape: BoxShape.circle,
                 border: Border.all(
                   color: theme.colorScheme.surface,
                   width: 1.5,
                 ),
               ),
               child: CircleAvatar(
                 radius: 8, // Small overlay
                 backgroundImage: NetworkImage(message.adminImage!),
                 backgroundColor: theme.colorScheme.primaryContainer,
                 onBackgroundImageError: (_, __) {},
               ),
             ),
           ),
       ],
     );
  }

  Widget _buildMessageContent(BuildContext context, ThemeData theme) {
    switch (message.type) {
      case 'image':
        return _buildImageContent(context, theme);
      case 'video':
        return _buildVideoContent(theme);
      case 'audio':
        return _buildAudioContent(theme);
      case 'location':
        return _buildLocationContent(theme);
      case 'document':
        return _buildDocumentContent(context, theme);
      case 'money-transfer':
        return _buildMoneyTransferContent(theme);
      case 'system':
        return _buildSystemContent(theme);
      default:
        return Padding(
          padding: const EdgeInsets.only(top: 6, left: 12, right: 12),
          child: _buildTextContent(theme),
        );
    }
  }

  Widget _buildTextContent(ThemeData theme) {
    return Text(
      message.content,
      textAlign: TextAlign.left, // Ensure text starts at the left
      style: theme.textTheme.bodyMedium?.copyWith(
        color: isOwn ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
      ),
    );
  }

  void _showFullScreenImage(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.95),
      builder: (context) => Stack(
        children: [
          // Close button
          Positioned(
            top: 40,
            right: 20,
            child: Material(
              color: Colors.transparent,
              child: IconButton(
                icon: const Icon(LucideIcons.x, color: Colors.white, size: 30),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          // Interactive Image
          Center(
            child: InteractiveViewer(
              panEnabled: true,
              boundaryMargin: const EdgeInsets.all(20),
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const CircularProgressIndicator(color: Colors.white);
                },
                errorBuilder: (context, error, stackTrace) {
                  return const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.imageOff, color: Colors.white, size: 48),
                      SizedBox(height: 16),
                      Text(
                        'Could not load image',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            decoration: TextDecoration.none),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageContent(BuildContext context, ThemeData theme) {
    final imageUrl = message.imageUrl;
    final isSending = message.status == 'sending';
    final isLocalFile = imageUrl?.startsWith('file://') ?? false;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (imageUrl != null)
          GestureDetector(
            onTap: isSending ? null : () => _showFullScreenImage(context, imageUrl),
            child: Stack(
              children: [
                Hero(
                  tag: imageUrl,
                  child: isLocalFile
                      ? Image.file(
                          File(imageUrl.replaceFirst('file://', '')),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (_, __, ___) => Container(
                            width: 200,
                            height: 150,
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(LucideIcons.imageOff),
                          ),
                        )
                      : Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              width: 200,
                              height: 150,
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: Center(
                                child: CircularProgressIndicator(
                                  value: loadingProgress.expectedTotalBytes != null
                                      ? loadingProgress.cumulativeBytesLoaded /
                                          loadingProgress.expectedTotalBytes!
                                      : null,
                                ),
                              ),
                            );
                          },
                          errorBuilder: (_, __, ___) => Container(
                            width: 200,
                            height: 150,
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(LucideIcons.imageOff),
                          ),
                        ),
                ),
                // Upload overlay for sending status
                if (isSending)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.4),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Uploading...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

        if (message.content.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12, right: 12, bottom: 6),
            child: _buildTextContent(theme),
          ),
      ],
    );
  }

  Widget _buildVideoContent(ThemeData theme) {
    final videoUrl = message.imageUrl;
    final isSending = message.status == 'sending';
    
    if (videoUrl == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.video,
              color: isOwn ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface),
          const SizedBox(width: 8),
          Text(
            'Video',
            style: TextStyle(
              color: isOwn ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: 400,
              ),
              child: VideoMessagePlayer(
                videoUrl: videoUrl,
                isOwn: isOwn,
              ),
            ),
            // Upload overlay for sending status
            if (isSending)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.5),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 3,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Uploading video...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (message.content.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12, right: 12, bottom: 6),
            child: _buildTextContent(theme),
          ),
      ],
    );
  }

  Widget _buildDocumentContent(BuildContext context, ThemeData theme) {
    final fileName = message.documentName ?? 'Document';
    final isSending = message.status == 'sending';
    
    return InkWell(
      onTap: isSending ? null : () async {
        if (message.imageUrl != null) {
          final url = message.imageUrl!;
          final isPdf = message.documentName?.toLowerCase().endsWith('.pdf') ?? 
                        url.toLowerCase().contains('.pdf') ?? false;

          if (isPdf) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DocumentViewerScreen(
                  url: url,
                  fileName: message.documentName ?? 'Document',
                ),
                fullscreenDialog: true,
              ),
            );
          } else {
            // Non-PDF files open externally
            final uri = Uri.parse(url);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } else {
              debugPrint('Could not launch $url');
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Could not open document')),
                );
              }
            }
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: isSending
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.orange,
                      ),
                    )
                  : const Icon(
                      LucideIcons.fileText,
                      color: Colors.orange,
                      size: 24,
                    ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isOwn ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isSending ? 'Uploading...' : 'Tap to open',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isOwn 
                          ? theme.colorScheme.onPrimary.withValues(alpha: 0.7) 
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioContent(ThemeData theme) {
    // If no audio URL (legacy or error), show placeholder
    if (message.imageUrl == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.mic,
              color: isOwn ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface),
          const SizedBox(width: 8),
          const Text('Audio unavailable'),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AudioMessagePlayer(
          audioUrl: message.imageUrl!,
          durationSeconds: message.audioDuration ?? 0,
          isOwn: isOwn,
        ),
        if (message.content.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12, right: 12, bottom: 6),
            child: _buildTextContent(theme),
          ),
      ],
    );
  }

  Widget _buildLocationContent(ThemeData theme) {
    // Basic coordinates
    final lat = message.location?.lat ?? 0.0;
    final lng = message.location?.lng ?? 0.0;
    
    // Google Maps Static API Key (reusing the one from ChatHeader)
    final apiKey = Env.googleMapsApiKey;
    
    // Construct Static Map URL
    final mapUrl = 'https://maps.googleapis.com/maps/api/staticmap?'
        'center=$lat,$lng&'
        'zoom=15&'
        'size=600x300&'
        'maptype=roadmap&'
        'markers=color:red%7C$lat,$lng&'
        'key=$apiKey';

    return GestureDetector(
      onTap: () async {
        // Open Google Maps Directions
        // Origin: Implicit (Current Device Location)
        // Destination: Shared Location
        final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        } else {
          debugPrint('Could not launch Maps');
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 250,
            height: 150,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              // Border/Shadow for visual pop
              border: Border.all(
                color: theme.colorScheme.outline.withOpacity(0.1),
                width: 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 1. Static Map Image
                  Image.network(
                    mapUrl,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!
                              : null,
                        ),
                      );
                    },
                    errorBuilder: (_, __, ___) => Center(
                      child: Icon(
                        LucideIcons.mapPin,
                        size: 40,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  
                  // 2. Info Overlay (Bottom)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withOpacity(0.9),
                        border: Border(
                          top: BorderSide(
                            color: theme.colorScheme.outline.withOpacity(0.1),
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (message.location?.placeName != null && message.location!.placeName!.isNotEmpty)
                            Text(
                              message.location!.placeName!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (message.location?.address != null)
                            Text(
                              message.location!.address,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (message.location?.placeName == null && message.location?.address == null)
                             Text(
                              'Shared Location',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
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


  Widget _buildMoneyTransferContent(ThemeData theme) {
    final transfer = message.moneyTransfer;
    if (transfer == null) {
      return _buildTextContent(theme);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.dollarSign, color: Colors.green.shade700),
              const SizedBox(width: 8),
              Text(
                'Money Transfer',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${transfer.currencySymbol}${transfer.amount.toStringAsFixed(2)} ${transfer.currency}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemContent(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message.content,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildDeletedMessage(ThemeData theme) {
    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.ban,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              'This message was deleted',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(String status) {
    switch (status) {
      case 'read':
        // Double blue check - message was read
        return const Icon(
          LucideIcons.checkCheck,
          size: 14,
          color: Colors.blue,
        );
      case 'delivered':
        // Double grey check - message delivered but not read
        return Icon(
          LucideIcons.checkCheck,
          size: 14,
          color: Colors.grey.shade400,
        );
      case 'sent':
        // Single check - message reached server
        return Icon(
          LucideIcons.check,
          size: 14,
          color: Colors.grey.shade400,
        );
      case 'sending':
        // Clock icon - optimistic message still being sent
        return Icon(
          LucideIcons.clock,
          size: 12,
          color: Colors.grey.shade400,
        );
      case 'error':
        // Red warning - message failed to send
        return const Icon(
          LucideIcons.alertCircle,
          size: 14,
          color: Colors.red,
        );
      default:
        return const Icon(
          LucideIcons.check,
          size: 14,
          color: Colors.white70,
        );
    }
  }
}

class VideoMessagePlayer extends StatefulWidget {
  final String videoUrl;
  final bool isOwn;

  const VideoMessagePlayer({
    super.key,
    required this.videoUrl,
    required this.isOwn,
  });

  @override
  State<VideoMessagePlayer> createState() => _VideoMessagePlayerState();
}

class _VideoMessagePlayerState extends State<VideoMessagePlayer> with AutomaticKeepAliveClientMixin {
  late VideoPlayerController _videoController;
  ChewieController? _chewieController;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      await _videoController.initialize();
      
      _chewieController = ChewieController(
        videoPlayerController: _videoController,
        aspectRatio: _videoController.value.aspectRatio,
        autoPlay: false,
        looping: false,
        placeholder: Container(
          color: Colors.black,
          child: const Center(child: CircularProgressIndicator()),
        ),
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(LucideIcons.alertCircle, color: Colors.white),
                const SizedBox(height: 8),
                Text(
                  'Error loading video',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          );
        },
      );

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('❌ Error initializing video: $e');
      if (mounted) {
        setState(() => _hasError = true);
      }
    }
  }

  @override
  void dispose() {
    _videoController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Crucial for KeepAlive

    if (_hasError) {
      return Container(
        width: 200,
        height: 150,
        color: Colors.black12,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.videoOff,
                color: widget.isOwn ? Colors.white70 : Colors.black54,
              ),
              const SizedBox(height: 8),
              Text(
                'Video unavailable',
                style: TextStyle(
                  color: widget.isOwn ? Colors.white70 : Colors.black54,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized) {
      return Container(
        width: 200,
        height: 150,
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return AspectRatio(
      aspectRatio: _videoController.value.aspectRatio,
      child: Chewie(controller: _chewieController!),
    );
  }
}

class AudioMessagePlayer extends StatefulWidget {
  final String audioUrl;
  final int durationSeconds;
  final bool isOwn;

  const AudioMessagePlayer({
    super.key,
    required this.audioUrl,
    required this.durationSeconds,
    required this.isOwn,
  });

  @override
  State<AudioMessagePlayer> createState() => _AudioMessagePlayerState();
}

class _AudioMessagePlayerState extends State<AudioMessagePlayer> with AutomaticKeepAliveClientMixin {
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  bool _isLoading = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _initAudio();
  }

  Future<void> _initAudio() async {
    try {
      // Listen to player state
      _audioPlayer.playerStateStream.listen((state) {
        if (mounted) {
          setState(() {
            _isPlaying = state.playing;
            if (state.processingState == ProcessingState.completed) {
              _position = Duration.zero;
              _audioPlayer.pause();
              _audioPlayer.seek(Duration.zero);
            }
          });
        }
      });

      // Listen to position
      _audioPlayer.positionStream.listen((position) {
        if (mounted) {
          setState(() => _position = position);
        }
      });
    } catch (e) {
      debugPrint('Error init audio listener: $e');
    }
  }

  Future<void> _togglePlay() async {
    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        if (_audioPlayer.processingState == ProcessingState.idle) {
          setState(() => _isLoading = true);
          await _audioPlayer.setUrl(widget.audioUrl);
          setState(() => _isLoading = false);
        }
        await _audioPlayer.play();
      }
    } catch (e) {
      debugPrint('Error playing audio: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _seekRelative(int seconds) async {
    final newPosition = _position + Duration(seconds: seconds);
    if (newPosition.isNegative) {
      await _audioPlayer.seek(Duration.zero);
    } else {
      await _audioPlayer.seek(newPosition);
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Crucial for KeepAlive

    final theme = Theme.of(context);
    final contentColor = widget.isOwn
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;

    final totalDuration = Duration(seconds: widget.durationSeconds);
    // Ensure position doesn't exceed total (visual glitch prevention)
    final currentPos = _position.inSeconds > totalDuration.inSeconds
        ? totalDuration
        : _position;

    return Container(
      width: 250,
      padding: const EdgeInsets.only(left: 12, right: 8, top: 16, bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Play/Pause Button
          GestureDetector(
            onTap: _togglePlay,
            child: _isLoading
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: contentColor,
                    ),
                  )
                : Icon(
                    _isPlaying ? LucideIcons.pause : LucideIcons.play,
                    color: contentColor,
                    size: 24,
                  ),
          ),
          const SizedBox(width: 8),
          
          // Slider
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: contentColor,
                inactiveTrackColor: contentColor.withValues(alpha: 0.3),
                thumbColor: contentColor,
                overlayColor: contentColor.withValues(alpha: 0.1),
              ),
              child: Slider(
                value: currentPos.inSeconds.toDouble(),
                max: totalDuration.inSeconds.toDouble() > 0
                    ? totalDuration.inSeconds.toDouble()
                    : 1.0,
                onChanged: (value) async {
                  final position = Duration(seconds: value.toInt());
                  await _audioPlayer.seek(position);
                },
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Duration Text (Current / Total)
          Text(
            '${_formatDuration(currentPos)} / ${_formatDuration(totalDuration)}',
            style: TextStyle(
              color: contentColor,
              fontSize: 12,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
