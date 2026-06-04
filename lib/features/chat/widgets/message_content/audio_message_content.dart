import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'package:diaspora_nearby/features/chat/widgets/audio_message_player.dart'; // Assume exists
import 'top_level_text_content.dart';

class AudioMessageContent extends StatelessWidget {
  final Message message;
  final bool isOwn;

  const AudioMessageContent({
    super.key,
    required this.message,
    required this.isOwn,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final audioUrl = message.documentUrl ?? message.imageUrl;

    if (audioUrl == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.mic,
            color: isOwn
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface,
          ),
          const SizedBox(width: 8),
          const Text('Audio unavailable'),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AudioMessagePlayer(
            messageId: message.id,
            audioUrl: audioUrl,
            durationSeconds: message.audioDuration ?? 0,
            isOwn: isOwn,
          ),
          if (message.content.isNotEmpty)
            TopLevelTextContent(message: message, isOwn: isOwn),
        ],
      ),
    );
  }
}
