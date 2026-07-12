import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

class ShareOptionsSheet extends StatelessWidget {
  final String referralCode;
  final String homeCountry;
  final String progressPercent;
  final String targetLabel;

  const ShareOptionsSheet({
    super.key,
    required this.referralCode,
    required this.homeCountry,
    this.progressPercent = '0.0',
    this.targetLabel = '1 Million',
  });

  /// Build a dynamic share card with the sender's referral code and live progress
  Future<File> _buildShareCard() async {
    const double w = 1080;
    const double h = 1200;

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

    final progressFraction = double.tryParse(progressPercent) ?? 0.0;
    final progressBarMaxW = w - 148;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, w, h));

    // Background gradient
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          const Offset(0, h),
          [
            const Color(0xFF0F1714),
            const Color(0xFF0A0A0A),
            const Color(0xFF0A0A0A),
          ],
          [0.0, 0.25, 1.0],
        ),
    );

    // Glow behind logo
    canvas.drawCircle(
      const Offset(w / 2, 175),
      280,
      Paint()
        ..shader = ui.Gradient.radial(const Offset(w / 2, 175), 280, [
          const Color(0xFF6B9B7A).withValues(alpha: 0.12),
          const Color(0xFF6B9B7A).withValues(alpha: 0.0),
        ]),
    );

    // Logo circle bg
    canvas.drawCircle(
      const Offset(w / 2, 175),
      110,
      Paint()..color = const Color(0xFF6B9B7A).withValues(alpha: 0.1),
    );

    // Logo image
    canvas.drawImageRect(
      logoImg,
      Rect.fromLTWH(0, 0, logoImg.width.toDouble(), logoImg.height.toDouble()),
      Rect.fromCenter(
        center: const Offset(w / 2, 175),
        width: 170,
        height: 170,
      ),
      Paint()..filterQuality = FilterQuality.high,
    );

    // Title
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

    // Subtitle
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

    // Progress card
    const cardMargin = 50.0;
    const cardRadius = 16.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(cardMargin, 520, w - cardMargin * 2, 145),
        const Radius.circular(cardRadius),
      ),
      Paint()..color = const Color(0xFF121212),
    );
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
      '$progressPercent%',
      w - cardMargin - 24,
      555,
      fontSize: 21,
      color: const Color(0xFF6B9B7A),
      fontWeight: FontWeight.bold,
      width: 120,
      textAlign: TextAlign.right,
      anchorCenter: false,
    );

    // Progress bar
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cardMargin + 24, 572, progressBarMaxW, 11),
        const Radius.circular(5),
      ),
      Paint()..color = Colors.grey.withValues(alpha: 0.1),
    );
    final fillW = (progressFraction / 100 * progressBarMaxW).clamp(
      11.0,
      progressBarMaxW,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cardMargin + 24, 572, fillW, 11),
        const Radius.circular(5),
      ),
      Paint()..color = const Color(0xFF6B9B7A),
    );
    _drawText(
      canvas,
      'The Race to $targetLabel is $progressPercent% complete!',
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

    // Referral code card
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(cardMargin, 700, w - cardMargin * 2, 135),
        const Radius.circular(cardRadius),
      ),
      Paint()..color = const Color(0xFF121212),
    );
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

    // CTA button
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(
          cardMargin + 25,
          868,
          w - (cardMargin + 25) * 2,
          85,
        ),
        const Radius.circular(14),
      ),
      Paint()..color = const Color(0xFF6B9B7A),
    );
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

    // Bottom branding
    _drawText(
      canvas,
      'diasporanearby.com',
      w / 2,
      h - 55,
      fontSize: 19,
      color: const Color(0xFF999999).withValues(alpha: 0.6),
      width: w - 100,
    );
    canvas.drawRect(
      const Rect.fromLTWH(0, h - 4, w, 4),
      Paint()..color = const Color(0xFF6B9B7A).withValues(alpha: 0.3),
    );

    // Render to image
    final picture = recorder.endRecording();
    final img = await picture.toImage(w.toInt(), h.toInt());
    final pngBytes = await img.toByteData(format: ui.ImageByteFormat.png);

    final tempDir = await getTemporaryDirectory();
    final cardFile = File('${tempDir.path}/diaspora_share_card.png');
    await cardFile.writeAsBytes(pngBytes!.buffer.asUint8List());
    return cardFile;
  }

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
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(textAlign: textAlign, maxLines: 10),
          )
          ..pushStyle(
            ui.TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: fontWeight,
              letterSpacing: letterSpacing > 0 ? letterSpacing : null,
            ),
          )
          ..addText(text);
    final p = builder.build()..layout(ui.ParagraphConstraints(width: width));
    canvas.drawParagraph(p, Offset(anchorCenter ? x - width / 2 : x, y));
  }

  /// Share with dynamically generated branded card
  Future<void> _shareWithLogo(BuildContext context, String message) async {
    if (context.mounted) Navigator.pop(context);

    final String link = 'https://diasporanearby.com/invite?code=$referralCode';
    final String fullMessage = '$message\n\nJoin here: $link';

    try {
      final cardFile = await _buildShareCard();
      await SharePlus.instance.share(
        ShareParams(text: fullMessage, files: [XFile(cardFile.path)]),
      );
    } catch (e) {
      debugPrint('Error sharing with logo: $e');
      await SharePlus.instance.share(ShareParams(text: fullMessage));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Share Invitation',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              IconButton(
                onPressed: () => context.pop(),
                icon: const Icon(LucideIcons.x),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Choose how you want to connect:',
            style: TextStyle(color: Theme.of(context).hintColor, fontSize: 14),
          ),
          const SizedBox(height: 20),

          // Grid of 4 options
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.1,
            children: [
              _buildOptionCard(
                context,
                icon: LucideIcons.home,
                title: 'Family Back Home',
                subtitle: 'Connect with family in $homeCountry',
                onTap: () => _shareWithLogo(
                  context,
                  'Join me on Diaspora Nearby! Stay connected with our family in $homeCountry and earn crypto tokens together.',
                ),
              ),
              _buildOptionCard(
                context,
                icon: LucideIcons.plane,
                title: 'Family Abroad',
                subtitle: 'Connect with family overseas',
                onTap: () => _shareWithLogo(
                  context,
                  'Join me on Diaspora Nearby! Connect with our family abroad and back home. Earn crypto tokens while doing it!',
                ),
              ),
              _buildOptionCard(
                context,
                icon: LucideIcons.users,
                title: 'Friends Back Home',
                subtitle: 'Connect with friends in $homeCountry',
                onTap: () => _shareWithLogo(
                  context,
                  'Join me on Diaspora Nearby! Stay connected with friends in $homeCountry. Earn crypto tokens while you connect!',
                ),
              ),
              _buildOptionCard(
                context,
                icon: LucideIcons.globe,
                title: 'Friends Abroad',
                subtitle: 'Connect with friends overseas',
                onTap: () => _shareWithLogo(
                  context,
                  'Join me on Diaspora Nearby! Connect with friends from your home country nearby or anywhere in the world. Earn crypto tokens while doing it!',
                ),
              ),
            ],
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 10),
        ],
      ),
    );
  }

  Widget _buildOptionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: AppTheme.cardDecoration(context).copyWith(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppTheme.accent.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppTheme.accent, size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).hintColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
