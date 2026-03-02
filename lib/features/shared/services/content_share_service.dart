import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'package:diaspora_nearby/features/events/models/event_data.dart';
import 'package:diaspora_nearby/features/events/widgets/share_event_dialog.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
// [NEW]
// [NEW]
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart'; // [NEW]

final contentShareServiceProvider = Provider<ContentShareService>((ref) {
  return ContentShareService(ref);
});

class ContentShareService {
  final Ref _ref;

  ContentShareService(this._ref);

  /// Share a message text
  Future<void> shareMessage(BuildContext context, Message message) async {
    String content = message.content;

    // Enrich content based on type
    if (message.type != 'text') {
      if (message.type == 'location' && message.location != null) {
        content =
            'Location: ${message.location!.address}\nGoogle Maps: https://www.google.com/maps/search/?api=1&query=${message.location!.lat},${message.location!.lng}';
      } else {
        content = 'Shared a ${message.type} via Diaspora Nearby';
        // If file/image, we might want to share files, but for now specific requirement was "Share" option.
        // share_plus supports files too (XFile).
        // Given complexity of downloading and resharing message media, we'll start with text/links.
      }
    }

    if (content.isEmpty) return;

    // Add App Footer
    content += '\n\nSent via Diaspora Nearby';

    // Show share sheet
    try {
      await Share.share(content);

      // Award points (Assuming sheet opened successfully)
      final rewarded = await _awardPoints('message_share');

      if (rewarded && context.mounted) {
        // Show reward feedback
        showExplorationRewardToast(
          context,
          message: 'Personal Stake increased!',
          points: 100,
        );
      }
    } catch (e) {
      debugPrint('Error sharing message: $e');
    }
  }

  /// Share an event as a visual card image via native share sheet
  Future<void> shareEvent(BuildContext context, Event event) async {
    showDialog(
      context: context,
      builder: (_) => ShareEventDialog(event: event),
    );
  }

  Future<bool> _awardPoints(String contentType) async {
    final user = _ref.read(authRepositoryProvider).currentUser;
    if (user != null) {
      return await _ref
          .read(pointsServiceProvider)
          .trackExternalShare(user.uid, contentType);
    }
    return false;
  }
}
