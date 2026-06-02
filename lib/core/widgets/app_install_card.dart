import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/core/services/pwa_install_service.dart';

/// Combined PWA install + native-app install widget.
/// Shown only on web and only when NOT running as a standalone PWA.
///
/// Email capture removed — testers self-serve through the public Closed
/// Testing opt-in link. Tapping "Install on Google Play" goes straight to
/// the Play Store listing; eligible testers (members of the public group
/// `diaspora-nearby-testers@googlegroups.com`) see the testing build.
class AppInstallCard extends ConsumerStatefulWidget {
  const AppInstallCard({super.key});

  @override
  ConsumerState<AppInstallCard> createState() => _AppInstallCardState();
}

class _AppInstallCardState extends ConsumerState<AppInstallCard> {
  bool _isStandalone = false;

  /// Public Play Store listing for the native Android app.
  static const String _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.diasporanearby.diasporanearby';

  bool get _isIOS => kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  bool get _isAndroid =>
      kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    if (!kIsWeb || !mounted) return;
    bool standalone = false;
    try {
      final notifier = ref.read(pwaInstallServiceProvider.notifier);
      standalone = notifier.isPwaStandalone();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _isStandalone = standalone);
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not open $url')));
    }
  }

  Future<void> _installPwa() async {
    try {
      final notifier = ref.read(pwaInstallServiceProvider.notifier);
      await notifier.promptInstall();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || _isStandalone) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Container(
      decoration: AppTheme.cardDecoration(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Accent header ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.accent, AppTheme.accentDark],
              ),
            ),
            child: const Row(
              children: [
                Icon(LucideIcons.download, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text(
                  'Get Diaspora Nearby on Your Device',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── iOS: Safari PWA instructions ──
                if (_isIOS) ...[
                  _buildIosInstructions(theme),
                  const SizedBox(height: 12),
                  Divider(
                    color: theme.dividerColor.withValues(alpha: 0.3),
                    height: 1,
                  ),
                  const SizedBox(height: 12),
                ],

                // ── Native app install ──
                _buildNativeInstallSection(theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── iOS PWA instructions ──
  Widget _buildIosInstructions(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(LucideIcons.globe, size: 16, color: AppTheme.accent),
            const SizedBox(width: 6),
            Text(
              'Install as App (PWA)',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.elevationColor(context, 2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add to Home Screen from Safari:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              _iosStep('1', 'Tap the Share button', LucideIcons.share2),
              _iosStep(
                '2',
                'Scroll down & tap "Add to Home Screen"',
                LucideIcons.plusSquare,
              ),
              _iosStep('3', 'Tap "Add" to confirm', LucideIcons.check),
            ],
          ),
        ),
      ],
    );
  }

  // ── Native install section (direct store links, no email) ──
  // iOS: hidden — iOS users are served by the Safari PWA instructions above.
  Widget _buildNativeInstallSection(ThemeData theme) {
    if (_isIOS) return const SizedBox.shrink();

    final platformHint = _isAndroid
        ? 'Install the Android app from Google Play'
        : 'Open this page on your Android phone to install, '
              'or install the web app below';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              LucideIcons.smartphone,
              size: 16,
              color: Colors.deepPurple,
            ),
            const SizedBox(width: 6),
            Text(
              'Install the Native App',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          platformHint,
          style: TextStyle(fontSize: 11, color: theme.hintColor),
        ),
        const SizedBox(height: 10),

        // Android primary CTA + PWA fallback. Desktop shows the same pair.
        _buildPrimaryButton(
          icon: LucideIcons.smartphone,
          label: _isAndroid
              ? 'Install on Google Play'
              : 'Install on Google Play (Android)',
          onPressed: () => _openUrl(_playStoreUrl),
        ),
        const SizedBox(height: 8),
        _buildSecondaryButton(
          theme: theme,
          icon: LucideIcons.globe,
          label: 'Install as Web App (PWA)',
          onPressed: _installPwa,
        ),
      ],
    );
  }

  Widget _buildPrimaryButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        icon: Icon(icon, size: 14),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildSecondaryButton({
    required ThemeData theme,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: theme.colorScheme.onSurface,
          padding: const EdgeInsets.symmetric(vertical: 10),
          side: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.4),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        icon: Icon(icon, size: 14),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        onPressed: onPressed,
      ),
    );
  }

  // ── iOS step row ──
  Widget _iosStep(String number, String text, IconData icon) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppTheme.accent,
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            icon,
            size: 14,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
