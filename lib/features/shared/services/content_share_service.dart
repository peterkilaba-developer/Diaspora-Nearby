import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'package:diaspora_nearby/features/events/models/event_data.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart'; // [NEW]
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart'; // [NEW]
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

  /// Share an event
  Future<void> shareEvent(BuildContext context, Event event) async {
    final user = _ref.read(authRepositoryProvider).currentUser;
    String eventUrl = 'https://diasporanearby.app/events/${event.id}';

    if (user != null) {
      try {
        String? code = await _ref.read(pointsRepositoryProvider).getReferralCode(user.uid);
        if (code == null) {
            // Try to fetch profile to get country code
            // Note: This relies on the provider having a value, might need to fetch if null
            // For simplicity and to avoid blocking too long, we might default or try quick fetch
            // But let's try to be consistent.
             try {
                 final userProfile = await _ref.read(profileRepositoryProvider).getUserProfile(user.uid);
                 if (userProfile != null) {
                     final countryCode = userProfile.homeCountryCode ?? 'US';
                     code = await _ref.read(pointsRepositoryProvider).generateReferralCode(
                       user.uid, 
                       userProfile.firstName, 
                       countryCode
                     );
                 }
             } catch (_) {
                 // Ignore profile fetch error
             }
        }
        
        if (code != null) {
          eventUrl = '$eventUrl?code=$code';
        }
      } catch (e) {
        debugPrint('Error attaching referral code: $e');
      }
    }

    final content =
        '📅 Join me at ${event.title}!\n\n${event.description}\n\n📍 ${event.venueName ?? event.location}\nStarting: ${event.startDate.toString()}\n\nView Event: $eventUrl';

    try {
      await Share.share(content, subject: 'Diaspora Nearby Event');

      final rewarded = await _awardPoints('event_share');
      if (rewarded && context.mounted) {
        showExplorationRewardToast(
          context,
          message: 'Personal Stake increased!',
          points: 100,
        );
      }
    } catch (e) {
      debugPrint('Error sharing event: $e');
    }
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
