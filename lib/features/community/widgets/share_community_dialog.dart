import 'dart:async';
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
  Future<String?>? _preCapturedImageFuture;
  Future<String>? _preFetchedShareUrlFuture;

  @override
  void initState() {
    super.initState();
    _preFetchedShareUrlFuture = _resolveShareUrl();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _preCapturedImageFuture = _captureCardImage();
      }
    });
  }

  Future<String> _resolveShareUrl() async {
    const baseUrl = 'https://diasporanearby.com/invite';
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

        return '$baseUrl?code=$code';
      }
    } catch (e) {
      debugPrint('Error getting referral code: $e');
    }
    return baseUrl;
  }

  Future<String?> _captureCardImage() async {
    try {
      final boundary =
          _globalKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final directory = await getTemporaryDirectory();
      final imagePath =
          '${directory.path}/community_share_${widget.community.id}.png';
      final imageFile = File(imagePath);
      await imageFile.writeAsBytes(pngBytes);
      return imagePath;
    } catch (e) {
      debugPrint('Error pre-capturing community card: $e');
      return null;
    }
  }

  Future<void> _captureAndShare() async {
    if (_isSharing) return;
    setState(() {
      _isSharing = true;
    });

    try {
      final imageFuture = _preCapturedImageFuture ?? _captureCardImage();
      final urlFuture = _preFetchedShareUrlFuture ?? _resolveShareUrl();

      final results = await Future.wait([imageFuture, urlFuture]);
      final imagePath = results[0] ?? await _captureCardImage();
      final shareUrl = results[1] ?? 'https://diasporanearby.com/invite';

      if (mounted) {
        Navigator.pop(context);
      }

      final shareText =
          'Join me in the ${widget.community.name} on Diaspora Nearby!';

      if (imagePath != null) {
        unawaited(
          SharePlus.instance.share(
            ShareParams(
              files: [XFile(imagePath)],
              text: '$shareText\n\n$shareUrl',
              subject: 'Join ${widget.community.name}',
            ),
          ),
        );
      } else {
        unawaited(
          SharePlus.instance.share(
            ShareParams(
              text: '$shareText\n\n$shareUrl',
              subject: 'Join ${widget.community.name}',
            ),
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
    return BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FloatingActionButton.extended(
                  onPressed: _isSharing ? null : _captureAndShare,
                  backgroundColor: AppTheme.accent,
                  icon: const Icon(LucideIcons.share2),
                  label: const Text('Share Community'),
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
