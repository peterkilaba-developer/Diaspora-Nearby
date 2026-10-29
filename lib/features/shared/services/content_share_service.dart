import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'package:diaspora_nearby/features/events/models/event_data.dart';
import 'package:diaspora_nearby/features/events/widgets/share_event_dialog.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart';

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
      }
    }

    if (content.isEmpty) return;

    // Build referral invite link synchronously in 0ms from cache
    String inviteLink = 'https://diasporanearby.com/invite';
    try {
      final user = _ref.read(authRepositoryProvider).currentUser;
      if (user != null) {
        final pointsRepo = _ref.read(pointsRepositoryProvider);
        String? code = pointsRepo.getCachedReferralCode(user.uid);
        if (code != null && code.isNotEmpty) {
          inviteLink = '$inviteLink?code=$code';
        } else {
          // Warm cache in background for subsequent shares without blocking the share sheet
          unawaited(() async {
            try {
              var fetched = await pointsRepo.getReferralCode(user.uid);
              if (fetched == null) {
                final userProfile =
                    _ref
                        .read(profileRepositoryProvider)
                        .getCachedProfile(user.uid) ??
                    await _ref
                        .read(profileRepositoryProvider)
                        .getUserProfile(user.uid);
                if (userProfile != null) {
                  final countryCode = userProfile.homeCountryCode ?? 'US';
                  await pointsRepo.generateReferralCode(
                    user.uid,
                    userProfile.firstName,
                    countryCode,
                  );
                }
              }
            } catch (_) {}
          }());
        }
      }
    } catch (e) {
      debugPrint('Error getting referral code for share: $e');
    }

    // Add App Footer with referral link
    content += '\n\nSent via Diaspora Nearby $inviteLink';

    // Show share sheet immediately in 0ms
    try {
      await SharePlus.instance.share(ShareParams(text: content));

      // Award points in background
      unawaited(() async {
        final rewarded = await _awardPoints('message_share');
        if (rewarded && context.mounted) {
          showExplorationRewardToast(
            context,
            message: 'Personal Stake increased!',
            points: 100,
          );
        }
      }());
    } catch (e) {
      debugPrint('Error sharing message: $e');
    }
  }

  /// Share an event as a visual card image via native share sheet
  Future<void> shareEvent(BuildContext context, Event event) async {
    showDialog(
      context: context,
      builder: (_) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: ShareEventDialog(event: event),
      ),
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
