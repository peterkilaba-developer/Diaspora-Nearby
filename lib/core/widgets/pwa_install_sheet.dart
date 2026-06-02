import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:diaspora_nearby/core/services/pwa_install_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A full-screen bottom sheet shown once after login on web to prompt
/// PWA installation.
///
/// • **Android/Chrome** — one-tap install via `beforeinstallprompt`
/// • **iOS Safari** — guided step-by-step "Add to Home Screen" instructions
class PwaInstallSheet extends StatelessWidget {
  final bool isIos;
  const PwaInstallSheet._({required this.isIos});

  static const _prefKey = 'pwa_install_dismissed';

  /// Shows the install sheet if:
  ///  1. Running on web
  ///  2. Not previously dismissed/installed
  ///  3. Not already running as standalone PWA
  static Future<void> maybeShow(BuildContext context, WidgetRef ref) async {
    if (!kIsWeb) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefKey) == true) return;

    // Don't show if already installed as PWA
    final notifier = ref.read(pwaInstallServiceProvider.notifier);
    if (notifier.isPwaStandalone()) return;

    // Small delay so the main UI settles first
    await Future.delayed(const Duration(milliseconds: 800));
    if (!context.mounted) return;

    // Detect platform
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;

    // For non-iOS, check if browser install prompt is available
    if (!isIos) {
      final isAvailable = ref.read(pwaInstallServiceProvider);
      if (!isAvailable) return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PwaInstallSheet._(isIos: isIos),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.88),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // App Icon
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.3,
                          ),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset(
                        'assets/icons/logo-transparent.png',
                        width: 80,
                        height: 80,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Title
                  Text(
                    'Install Diaspora Nearby',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),

                  // Subtitle
                  Text(
                    isIos
                        ? 'Add to your home screen in 2 easy steps'
                        : 'Add to your home screen for the best experience',
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),

                  // Platform-specific content
                  if (isIos) ...[
                    _buildIosInstructions(theme),
                  ] else ...[
                    _buildAndroidFeatures(),
                  ],

                  const SizedBox(height: 32),

                  // Action button
                  if (isIos) ...[
                    // iOS: "Got it" button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: () async {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool(_prefKey, true);
                          if (context.mounted) Navigator.of(context).pop();
                        },
                        icon: const Icon(LucideIcons.checkCircle, size: 20),
                        label: const Text(
                          'Got it!',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    // Android: One-tap install button
                    Consumer(
                      builder: (context, ref, _) {
                        return SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton.icon(
                            onPressed: () async {
                              final notifier = ref.read(
                                pwaInstallServiceProvider.notifier,
                              );
                              final accepted = await notifier.promptInstall();

                              if (context.mounted) {
                                final prefs =
                                    await SharedPreferences.getInstance();
                                await prefs.setBool(_prefKey, true);
                                Navigator.of(context).pop();

                                if (accepted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      behavior: SnackBarBehavior.floating,
                                      backgroundColor: const Color(0xFF2A2A2A),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      content: const Row(
                                        children: [
                                          Icon(
                                            LucideIcons.checkCircle,
                                            size: 18,
                                            color: Color(0xFF9CAF88),
                                          ),
                                          SizedBox(width: 12),
                                          Text(
                                            'App installed! Check your home screen 🎉',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                            icon: const Icon(LucideIcons.download, size: 20),
                            label: const Text(
                              'Install App',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 12),

                  // Dismiss
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: TextButton(
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool(_prefKey, true);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                      child: Text(
                        'Maybe later',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Android: Feature highlights ──────────────────────────────
  Widget _buildAndroidFeatures() {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FeatureRow(
          icon: LucideIcons.zap,
          title: 'Instant Access',
          subtitle: 'Launch directly from your home screen',
          color: Color(0xFFFFB800),
        ),
        SizedBox(height: 16),
        _FeatureRow(
          icon: LucideIcons.bellRing,
          title: 'Notifications',
          subtitle: 'Never miss a message or community update',
          color: Color(0xFF4CAF50),
        ),
        SizedBox(height: 16),
        _FeatureRow(
          icon: LucideIcons.wifiOff,
          title: 'Works Offline',
          subtitle: 'Browse cached content without internet',
          color: Color(0xFF2196F3),
        ),
        SizedBox(height: 16),
        _FeatureRow(
          icon: LucideIcons.maximize,
          title: 'Full Screen',
          subtitle: 'No browser bars — feels like a native app',
          color: Color(0xFFE040FB),
        ),
      ],
    );
  }

  // ── iOS: Step-by-step instructions ───────────────────────────
  Widget _buildIosInstructions(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Step 1
        _InstructionStep(
          stepNumber: '1',
          icon: LucideIcons.share,
          title: 'Tap the Share button',
          subtitle: 'Find the Share icon at the bottom of Safari',
          theme: theme,
        ),
        const SizedBox(height: 20),

        // Arrow
        Icon(
          LucideIcons.arrowDown,
          size: 20,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.25),
        ),
        const SizedBox(height: 20),

        // Step 2
        _InstructionStep(
          stepNumber: '2',
          icon: LucideIcons.plusSquare,
          title: 'Tap "Add to Home Screen"',
          subtitle: 'Scroll down in the share menu to find it',
          theme: theme,
        ),
        const SizedBox(height: 20),

        // Arrow
        Icon(
          LucideIcons.arrowDown,
          size: 20,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.25),
        ),
        const SizedBox(height: 20),

        // Done!
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  LucideIcons.checkCircle,
                  size: 22,
                  color: Color(0xFF4CAF50),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'That\'s it!',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      'Diaspora Nearby will appear on your home screen',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.55,
                        ),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Shared Widgets ─────────────────────────────────────────────

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 22, color: color),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InstructionStep extends StatelessWidget {
  final String stepNumber;
  final IconData icon;
  final String title;
  final String subtitle;
  final ThemeData theme;

  const _InstructionStep({
    required this.stepNumber,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        children: [
          // Step number badge
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                stepNumber,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Icon
          Icon(icon, size: 24, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          // Text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
