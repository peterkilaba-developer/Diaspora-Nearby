import 'dart:async';
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
/// a PNG image, and opens the device native share sheet via [SharePlus.instance.share].
/// Follows the same pattern as [ShareCommunityDialog].
class ShareEventDialog extends ConsumerStatefulWidget {
  final Event event;

  const ShareEventDialog({super.key, required this.event});

  @override
  ConsumerState<ShareEventDialog> createState() => _ShareEventDialogState();
}

class _ShareEventDialogState extends ConsumerState<ShareEventDialog> {
  static final Map<String, String> _cachedReferralCodes = {};

  final GlobalKey _globalKey = GlobalKey();
  bool _isSharing = false;
  String? _prewarmedReferralCode;
  String? _preCapturedImagePath;
  Future<String?>? _captureInFlight;

  @override
  void initState() {
    super.initState();
    _prewarmReferralCode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _captureInFlight = _preCaptureImage();
    });
  }

  Future<void> _prewarmReferralCode() async {
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null) return;

    if (_cachedReferralCodes.containsKey(user.uid)) {
      _prewarmedReferralCode = _cachedReferralCodes[user.uid];
      return;
    }

    try {
      final pointsRepo = ref.read(pointsRepositoryProvider);
      String? code = await pointsRepo.getReferralCode(user.uid);
      if (code == null) {
        final userProfile =
            ref.read(userProfileProvider).value ??
            ref.read(profileRepositoryProvider).getCachedProfile(user.uid) ??
            await ref.read(profileRepositoryProvider).getUserProfile(user.uid);
        if (userProfile != null) {
          final countryCode = userProfile.homeCountryCode ?? 'US';
          code = await pointsRepo.generateReferralCode(
            user.uid,
            userProfile.firstName,
            countryCode,
          );
        }
      }
      if (code != null) {
        _cachedReferralCodes[user.uid] = code;
        _prewarmedReferralCode = code;
      }
    } catch (_) {}
  }

  Future<String?> _preCaptureImage() async {
    try {
      if (!mounted) return null;
      final boundary =
          _globalKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;
      final pngBytes = byteData.buffer.asUint8List();

      final directory = await getTemporaryDirectory();
      final imagePath = '${directory.path}/event_share_${widget.event.id}.png';
      final imageFile = File(imagePath);
      await imageFile.writeAsBytes(pngBytes);
      _preCapturedImagePath = imagePath;
      return imagePath;
    } catch (_) {
      return null;
    }
  }

  Future<void> _captureAndShare() async {
    if (_isSharing) return;
    setState(() {
      _isSharing = true;
    });

    try {
      String? imagePath =
          _preCapturedImagePath ??
          await (_captureInFlight ?? _preCaptureImage());
      if (imagePath == null) {
        throw Exception('Could not capture event card image');
      }

      final user = ref.read(authRepositoryProvider).currentUser;
      final code =
          _prewarmedReferralCode ??
          (user != null ? _cachedReferralCodes[user.uid] : null);

      String eventUrl = 'https://diasporanearby.com/invite';
      if (code != null && code.isNotEmpty) {
        eventUrl = '$eventUrl?code=$code';
      }
      final shareText =
          'Join me at ${widget.event.title}!\n\nLocation: ${widget.event.venueName ?? widget.event.location}\n\nView Event: $eventUrl';

      if (mounted) {
        Navigator.pop(context);
      }

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(imagePath)],
          text: shareText,
          subject: widget.event.title,
        ),
      );

      // Award points in the background
      if (user != null) {
        unawaited(
          ref
              .read(pointsServiceProvider)
              .trackExternalShare(user.uid, 'event_share')
              .then((rewarded) {
                if (rewarded && mounted) {
                  showExplorationRewardToast(
                    context,
                    message: 'Personal Stake increased!',
                    points: 100,
                  );
                }
              })
              .catchError((_) {}),
        );
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
    return BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Dialog(
        backgroundColor: Colors.black.withValues(alpha: 0.8),
        insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
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
                    icon: const Icon(LucideIcons.share2),
                    label: const Text('Share Event'),
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
      ),
    );
  }
}
