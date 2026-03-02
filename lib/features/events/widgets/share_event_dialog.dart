import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/events/models/event_data.dart';
import 'package:diaspora_nearby/features/events/widgets/event_share_card.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';

/// A dialog that previews the event as a visual share card, captures it as
/// a PNG image, and opens the device native share sheet via [Share.shareXFiles].
/// Follows the same pattern as [ShareCommunityDialog].
class ShareEventDialog extends ConsumerStatefulWidget {
  final Event event;

  const ShareEventDialog({super.key, required this.event});

  @override
  ConsumerState<ShareEventDialog> createState() => _ShareEventDialogState();
}

class _ShareEventDialogState extends ConsumerState<ShareEventDialog> {
  final GlobalKey _globalKey = GlobalKey();
  bool _isSharing = false;

  Future<void> _captureAndShare() async {
    setState(() {
      _isSharing = true;
    });

    try {
      // 1. Capture Image
      final boundary =
          _globalKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('Could not find render boundary');
      }

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      // 2. Save to Temp File
      final directory = await getTemporaryDirectory();
      final imagePath = '${directory.path}/event_share_${widget.event.id}.png';
      final imageFile = File(imagePath);
      await imageFile.writeAsBytes(pngBytes);

      // 3. Build share text with referral code
      if (mounted) {
        Navigator.pop(context);

        String eventUrl =
            'https://diasporanearby.app/events/${widget.event.id}';
        String shareText =
            'Join me at ${widget.event.title}!\n\nLocation: ${widget.event.venueName ?? widget.event.location}';

        try {
          final user = ref.read(authRepositoryProvider).currentUser;
          if (user != null) {
            final pointsRepo = ref.read(pointsRepositoryProvider);
            String? code = await pointsRepo.getReferralCode(user.uid);

            if (code == null) {
              try {
                final userProfile = await ref
                    .read(profileRepositoryProvider)
                    .getUserProfile(user.uid);
                if (userProfile != null) {
                  final countryCode = userProfile.homeCountryCode ?? 'US';
                  code = await pointsRepo.generateReferralCode(
                    user.uid,
                    userProfile.firstName,
                    countryCode,
                  );
                }
              } catch (_) {
                // Ignore profile fetch error
              }
            }

            if (code != null) {
              eventUrl = '$eventUrl?code=$code';
            }
          }
        } catch (e) {
          debugPrint('Error getting referral code: $e');
        }

        shareText += '\n\nView Event: $eventUrl';

        await Share.shareXFiles(
          [XFile(imagePath)],
          text: shareText,
          subject: widget.event.title,
        );

        // Award points
        try {
          final user = ref.read(authRepositoryProvider).currentUser;
          if (user != null) {
            final rewarded = await ref
                .read(pointsServiceProvider)
                .trackExternalShare(user.uid, 'event_share');
            if (rewarded && mounted) {
              showExplorationRewardToast(
                context,
                message: 'Personal Stake increased!',
                points: 100,
              );
            }
          }
        } catch (e) {
          debugPrint('Error awarding points: $e');
        }
      }
    } catch (e) {
      debugPrint('Error sharing event: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to share: $e')));
        setState(() {
          _isSharing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black.withValues(alpha: 0.8),
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Preview container
            Center(
              child: RepaintBoundary(
                key: _globalKey,
                child: EventShareCard(event: widget.event),
              ),
            ),
            const SizedBox(height: 24),

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FloatingActionButton.extended(
                  onPressed: _isSharing ? null : _captureAndShare,
                  backgroundColor: AppTheme.accent,
                  icon: _isSharing
                      ? Container(
                          width: 24,
                          height: 24,
                          padding: const EdgeInsets.all(2),
                          child: const CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(LucideIcons.share2),
                  label: Text(_isSharing ? 'Preparing...' : 'Share Event'),
                ),
                const SizedBox(width: 16),
                FloatingActionButton(
                  onPressed: () => Navigator.pop(context),
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  mini: true,
                  child: const Icon(LucideIcons.x),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
