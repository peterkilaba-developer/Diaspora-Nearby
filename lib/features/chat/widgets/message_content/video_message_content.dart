import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'package:diaspora_nearby/features/chat/widgets/video_message_player.dart'; // Assume this exists as used in original
import 'top_level_text_content.dart';

class VideoMessageContent extends StatelessWidget {
  final Message message;
  final bool isOwn;

  const VideoMessageContent({
    super.key,
    required this.message,
    required this.isOwn,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final videoUrl = message.documentUrl ?? message.imageUrl;
    final isSending = message.status == 'sending';

    if (videoUrl == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.video,
            color: isOwn
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface,
          ),
          const SizedBox(width: 8),
          Text(
            'Video',
            style: TextStyle(
              color: isOwn
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurface,
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
            SizedBox(
              width: double.infinity,
              child: VideoMessagePlayer(videoUrl: videoUrl, isOwn: isOwn),
            ),
            if (isSending)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.5),
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
          TopLevelTextContent(message: message, isOwn: isOwn),
      ],
    );
  }
}
