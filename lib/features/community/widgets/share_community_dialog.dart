import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/community/models/community_data.dart';
import 'package:diaspora_nearby/features/community/widgets/community_share_card.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';

class ShareCommunityDialog extends ConsumerStatefulWidget {
  final Community community;

  const ShareCommunityDialog({super.key, required this.community});

  @override
  ConsumerState<ShareCommunityDialog> createState() =>
      _ShareCommunityDialogState();
}

class _ShareCommunityDialogState extends ConsumerState<ShareCommunityDialog> {
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

      // Wait a bit to ensure rendering is complete if needed (usually frame end)
      // ui.Image image = await boundary.toImage(pixelRatio: 3.0);

      // Attempt generic capture
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      // 2. Save to Temp File
      final directory = await getTemporaryDirectory();
      final imagePath =
          '${directory.path}/community_share_${widget.community.id}.png';
      final imageFile = File(imagePath);
      await imageFile.writeAsBytes(pngBytes);

      // 3. Share
      if (mounted) {
        Navigator.pop(context);

        String shareText =
            'Join me in the ${widget.community.name} on Diaspora Nearby!';
        String shareUrl = 'https://diasporanearby.com/invite';

        try {
          final user = ref.read(authRepositoryProvider).currentUser;
          if (user != null) {
            final pointsRepo = ref.read(pointsRepositoryProvider);
            String? code = await pointsRepo.getReferralCode(user.uid);

            if (code == null) {
              final userPoints = await pointsRepo.getUserPoints(user.uid);
              final firstName = user.displayName?.split(' ').first ?? 'Friend';
              final countryCode = userPoints?.homeCountryCode ?? 'GLO';
              code = await pointsRepo.generateReferralCode(
                user.uid,
                firstName,
                countryCode,
              );
            }

            shareUrl = '$shareUrl?code=$code';
          }
        } catch (e) {
          debugPrint('Error getting referral code: $e');
          // Continue sharing without code
        }

        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(imagePath)],
            text: '$shareText\n\n$shareUrl',
            subject: 'Join ${widget.community.name}',
          ),
        );
      }
    } catch (e) {
      debugPrint('Error sharing community: $e');
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
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Preview container
          Center(
            child: RepaintBoundary(
              key: _globalKey,
              child: CommunityShareCard(
                community: widget.community,
                memberCount: widget.community.memberCount,
              ),
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
                label: Text(_isSharing ? 'Preparing...' : 'Share Community'),
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
    );
  }
}
