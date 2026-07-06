import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/dsp/services/epoch_service.dart';

class ShareInviteScreen extends ConsumerStatefulWidget {
  const ShareInviteScreen({super.key});

  @override
  ConsumerState<ShareInviteScreen> createState() => _ShareInviteScreenState();
}

class _ShareInviteScreenState extends ConsumerState<ShareInviteScreen> {
  @override
  Widget build(BuildContext context) {
    return const ShareInviteBody();
  }

  // Helper to re-fetch code if needed, but for now we trust FutureBuilder internal state or passed generic
  // Actually, we need the code available for the grid too.
  // Better approach: combine fetches or just pass code down if possible.

  // Reworking build to fetch code once and use it.
}

class ShareInviteBody extends ConsumerStatefulWidget {
  const ShareInviteBody({super.key});

  @override
  ConsumerState<ShareInviteBody> createState() => _ShareInviteBodyState();
}

class _ShareInviteBodyState extends ConsumerState<ShareInviteBody> {
  bool _isGenerating = false;
  // Cache the future so FutureBuilder doesn't reset on every rebuild.
  // A new future is only created once we know the user uid, and again
  // after generating a code so the freshly-created code is fetched.
  Future<String?>? _codeFuture;
  String? _lastUid;

  void _initCodeFuture(String uid) {
    if (_lastUid != uid || _codeFuture == null) {
      _lastUid = uid;
      _codeFuture = ref.read(pointsRepositoryProvider).getReferralCode(uid);
    }
  }

  Future<void> _generateCode(String userId) async {
    setState(() => _isGenerating = true);
    try {
      // Fetch profile for name/country
      final profile = await ref.read(userProfileByIdProvider(userId).future);
      if (profile != null) {
        final firstName = profile.firstName;
        final countryCode = profile.homeLocation.countryCode ?? 'US';

        await ref
            .read(pointsRepositoryProvider)
            .generateReferralCode(userId, firstName, countryCode);
        // Force re-fetch after generation
        setState(() {
          _codeFuture = ref
              .read(pointsRepositoryProvider)
              .getReferralCode(userId);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error generating code: $e")));
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authRepositoryProvider).currentUser;
    if (user == null) return const SizedBox.shrink();

    // Initialise once per uid; does not recreate on every build.
    _initCodeFuture(user.uid);

    return FutureBuilder<String?>(
      future: _codeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !_isGenerating) {
          return Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            appBar: AppBar(
              title: const Text("Share to your Community"),
              centerTitle: true,
              elevation: 0,
              backgroundColor: Colors.transparent,
              leading: IconButton(
                icon: const Icon(LucideIcons.x),
                onPressed: () => context.pop(),
              ),
            ),
            body: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Loading your invite code…',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          );
        }

        final code = snapshot.data;

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            title: const Text("Share to your Community"),
            centerTitle: true,
            elevation: 0,
            backgroundColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(LucideIcons.x),
              onPressed: () => context.pop(),
            ),
          ),
          body: Container(
            decoration: AppTheme.pageDecoration(context),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                AppTheme.pageHorizontalPadding,
                AppTheme.pageHorizontalPadding,
                AppTheme.pageHorizontalPadding,
                MediaQuery.of(context).padding.bottom + 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (snapshot.hasError)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Column(
                        children: [
                          const Icon(
                            LucideIcons.wifiOff,
                            size: 40,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Could not load your invite code.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Check your connection and try again.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton(
                            onPressed: () => setState(() {
                              _codeFuture = ref
                                  .read(pointsRepositoryProvider)
                                  .getReferralCode(user.uid);
                            }),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  else if (code != null) ...[
                    _buildReferralQR(context, code),
                    const SizedBox(height: 20),
                    _buildCodeCard(context, code),
                  ] else
                    _buildGenerateCard(context, user.uid),

                  const SizedBox(height: 24),
                  const Text(
                    "Share via",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),

                  if (code != null)
                    _buildDirectShareButtons(context, code)
                  else if (!snapshot.hasError)
                    const Center(
                      child: Text(
                        "Generate a code to start sharing!",
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── Dynamic share card builder ───────────────────────────────────────

  /// Build a dynamic share card with the sender's referral code and live progress
  Future<File> _buildShareCard(String referralCode) async {
    const double w = 1080;
    const double h = 1200;

    // Load the pre-processed transparent logo
    final logoBytes = await rootBundle.load(
      'assets/icons/logo-transparent.png',
    );
    final logoCodec = await ui.instantiateImageCodec(
      logoBytes.buffer.asUint8List(),
      targetWidth: 170,
      targetHeight: 170,
    );
    final logoFrame = await logoCodec.getNextFrame();
    final logoImg = logoFrame.image;

    // Get live progress data (inline — helper methods were removed)
    final supply = ref.read(globalSupplyProvider).value ?? 0;
    final members = ref.read(globalMemberCountProvider).value ?? 0;
    final epochService = ref.read(epochServiceProvider);
    final currentEpoch = epochService.getCurrentCommunityEpoch(supply, members);
    final progress = currentEpoch.calculateProgress(supply, members);
    final percent = (progress * 100).toStringAsFixed(1);
    final rawTarget = currentEpoch.dspTarget;
    final targetLabel = rawTarget >= 1000000000
        ? '${(rawTarget / 1000000000).round()} Billion'
        : rawTarget >= 1000000
        ? '${(rawTarget / 1000000).round()} Million'
        : rawTarget.toString();
    final progressFraction = double.tryParse(percent) ?? 0.0;
    final progressBarMaxW = w - 148; // card inner width minus padding

    // Create canvas
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, w, h));

    // ── Background gradient (matches AppTheme.pageDecoration dark)
    final bgPaint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        const Offset(0, h),
        [
          const Color(0xFF0F1714),
          const Color(0xFF0A0A0A),
          const Color(0xFF0A0A0A),
        ],
        [0.0, 0.25, 1.0],
      );
    canvas.drawRect(const Rect.fromLTWH(0, 0, w, h), bgPaint);

    // ── Subtle glow behind logo
    final glowPaint = Paint()
      ..shader = ui.Gradient.radial(const Offset(w / 2, 175), 280, [
        const Color(0xFF6B9B7A).withValues(alpha: 0.12),
        const Color(0xFF6B9B7A).withValues(alpha: 0.0),
      ]);
    canvas.drawCircle(const Offset(w / 2, 175), 280, glowPaint);

    // ── Logo circle background
    canvas.drawCircle(
      const Offset(w / 2, 175),
      110,
      Paint()..color = const Color(0xFF6B9B7A).withValues(alpha: 0.1),
    );

    // ── Logo image (centered in circle)
    final logoRect = Rect.fromCenter(
      center: const Offset(w / 2, 175),
      width: 170,
      height: 170,
    );
    canvas.drawImageRect(
      logoImg,
      Rect.fromLTWH(0, 0, logoImg.width.toDouble(), logoImg.height.toDouble()),
      logoRect,
      Paint()..filterQuality = FilterQuality.high,
    );

    // ── Title: "Share & Earn Together"
    _drawText(
      canvas,
      'Share & Earn Together',
      w / 2,
      350,
      fontSize: 46,
      color: const Color(0xFFF5F5F5),
      fontWeight: FontWeight.bold,
      width: w - 80,
    );

    // ── Subtitle (multi-line)
    _drawText(
      canvas,
      'Invite your family and friends—whether\nback home or abroad—to connect on\nDiaspora Nearby. Every person you bring\nearns you both crypto tokens!',
      w / 2,
      400,
      fontSize: 24,
      color: const Color(0xFF6B9B7A),
      fontWeight: FontWeight.w600,
      width: w - 100,
    );

    // ── Progress card
    const cardMargin = 50.0;
    const cardRadius = 16.0;
    final progressCardRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(cardMargin, 520, w - cardMargin * 2, 145),
      const Radius.circular(cardRadius),
    );
    canvas.drawRRect(
      progressCardRect,
      Paint()..color = const Color(0xFF121212),
    );

    // Progress header
    _drawText(
      canvas,
      'Global TGE Progress',
      cardMargin + 24,
      555,
      fontSize: 21,
      color: const Color(0xFFF5F5F5),
      fontWeight: FontWeight.bold,
      width: 400,
      textAlign: TextAlign.left,
      anchorCenter: false,
    );
    _drawText(
      canvas,
      '$percent%',
      w - cardMargin - 24,
      555,
      fontSize: 21,
      color: const Color(0xFF6B9B7A),
      fontWeight: FontWeight.bold,
      width: 120,
      textAlign: TextAlign.right,
      anchorCenter: false,
    );

    // Progress bar background
    final barY = 572.0;
    final barRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(cardMargin + 24, barY, progressBarMaxW, 11),
      const Radius.circular(5),
    );
    canvas.drawRRect(
      barRect,
      Paint()..color = Colors.grey.withValues(alpha: 0.1),
    );

    // Progress bar fill
    final fillW = (progressFraction / 100 * progressBarMaxW).clamp(
      11.0,
      progressBarMaxW,
    );
    final fillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(cardMargin + 24, barY, fillW, 11),
      const Radius.circular(5),
    );
    canvas.drawRRect(fillRect, Paint()..color = const Color(0xFF6B9B7A));

    // Progress description
    _drawText(
      canvas,
      'The Race to $targetLabel is $percent% complete!',
      w / 2,
      612,
      fontSize: 17,
      color: const Color(0xFF999999),
      width: w - 120,
    );
    _drawText(
      canvas,
      'Pulse TGE events occur as we grow.',
      w / 2,
      636,
      fontSize: 17,
      color: const Color(0xFF999999),
      width: w - 120,
    );

    // ── Referral code card
    final codeCardRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(cardMargin, 700, w - cardMargin * 2, 135),
      const Radius.circular(cardRadius),
    );
    canvas.drawRRect(codeCardRect, Paint()..color = const Color(0xFF121212));

    _drawText(
      canvas,
      'YOUR REFERRAL CODE',
      w / 2,
      738,
      fontSize: 17,
      color: const Color(0xFF999999),
      fontWeight: FontWeight.bold,
      width: w - 120,
      letterSpacing: 2.5,
    );
    _drawText(
      canvas,
      referralCode,
      w / 2,
      792,
      fontSize: 40,
      color: const Color(0xFFF5F5F5),
      fontWeight: FontWeight.bold,
      width: w - 120,
      letterSpacing: 4,
    );

    // ── CTA button
    final ctaRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(cardMargin + 25, 868, w - (cardMargin + 25) * 2, 85),
      const Radius.circular(14),
    );
    canvas.drawRRect(ctaRect, Paint()..color = const Color(0xFF6B9B7A));
    _drawText(
      canvas,
      'diasporanearby.com/invite?code=$referralCode',
      w / 2,
      910,
      fontSize: 22,
      color: Colors.white,
      fontWeight: FontWeight.bold,
      width: w - 200,
    );

    // ── Bottom branding
    _drawText(
      canvas,
      'diasporanearby.com',
      w / 2,
      h - 55,
      fontSize: 19,
      color: const Color(0xFF999999).withValues(alpha: 0.6),
      width: w - 100,
    );

    // Bottom accent bar
    canvas.drawRect(
      const Rect.fromLTWH(0, h - 4, w, 4),
      Paint()..color = const Color(0xFF6B9B7A).withValues(alpha: 0.3),
    );

    // ── Render to image
    final picture = recorder.endRecording();
    final img = await picture.toImage(w.toInt(), h.toInt());
    final pngBytes = await img.toByteData(format: ui.ImageByteFormat.png);

    final tempDir = await getTemporaryDirectory();
    final cardFile = File('${tempDir.path}/diaspora_share_card.png');
    await cardFile.writeAsBytes(pngBytes!.buffer.asUint8List());

    return cardFile;
  }

  /// Helper to draw centered text on canvas
  void _drawText(
    Canvas canvas,
    String text,
    double x,
    double y, {
    required double fontSize,
    required Color color,
    FontWeight fontWeight = FontWeight.normal,
    required double width,
    TextAlign textAlign = TextAlign.center,
    bool anchorCenter = true,
    double letterSpacing = 0,
  }) {
    final style = ui.ParagraphStyle(textAlign: textAlign, maxLines: 10);
    final builder = ui.ParagraphBuilder(style)
      ..pushStyle(
        ui.TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: letterSpacing > 0 ? letterSpacing : null,
        ),
      )
      ..addText(text);
    final paragraph = builder.build();
    paragraph.layout(ui.ParagraphConstraints(width: width));

    final dx = anchorCenter ? x - width / 2 : x;
    canvas.drawParagraph(paragraph, Offset(dx, y));
  }

  /// Share with dynamically generated branded card
  Future<void> _shareWithLogo(String message, String code) async {
    try {
      final String link = 'https://diasporanearby.com/invite?code=$code';
      final String fullMessage = '$message\n\nJoin here: $link';

      // Build dynamic share card with actual code + progress
      final cardFile = await _buildShareCard(code);

      await SharePlus.instance.share(
        ShareParams(text: fullMessage, files: [XFile(cardFile.path)]),
      );
    } catch (e) {
      debugPrint('Error sharing with logo: $e');
      final String link = 'https://diasporanearby.com/invite?code=$code';
      final String fullMessage = '$message\n\nJoin here: $link';
      await SharePlus.instance.share(ShareParams(text: fullMessage));
    }
  }

  Widget _buildDirectShareButtons(BuildContext context, String code) {
    final message =
        'Join me on Diaspora Nearby! Connect with people from your home country nearby or anywhere in the world. Connect with family and friends back home. Earn crypto tokens while doing it!';

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () => _shareWithLogo(message, code),
        icon: const Icon(LucideIcons.share2),
        label: const Text(
          'Share Invite',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildGenerateCard(BuildContext context, String userId) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.cardPadding),
      decoration: AppTheme.cardDecoration(context),
      child: Column(
        children: [
          const Icon(LucideIcons.sparkles, size: 40, color: AppTheme.accent),
          const SizedBox(height: 16),
          const Text(
            "No Invite Code Yet",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            "Invite family and friends from home and abroad to connect and earn.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _isGenerating ? null : () => _generateCode(userId),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accent,
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.pageHorizontalPadding,
                vertical: 12,
              ),
            ),
            child: _isGenerating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text("Generate Code"),
          ),
        ],
      ),
    );
  }

  Widget _buildReferralQR(BuildContext context, String code) {
    final qrData = 'https://diasporanearby.com/invite?code=$code';
    return Column(
      children: [
        const Text(
          'Show QR to Invite',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'New member scans this with their phone camera — referral code applies automatically.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Theme.of(context).hintColor),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: QrImageView(
            data: qrData,
            version: QrVersions.auto,
            size: 220,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Color(0xFF151515),
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Color(0xFF151515),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.qrCode, size: 14, color: AppTheme.accent),
            SizedBox(width: 6),
            Text(
              'Counts toward your 10 QR milestone',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCodeCard(BuildContext context, String code) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.cardPadding),
      decoration: AppTheme.cardDecoration(context),
      child: Column(
        children: [
          const Text(
            "YOUR REFERRAL CODE",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    code,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              IconButton(
                icon: const Icon(LucideIcons.copy, color: AppTheme.accent),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: code));
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text("Code copied!")));
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
