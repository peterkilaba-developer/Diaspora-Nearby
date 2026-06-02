import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

/// Detects native-only feature attempts on web and shows a direct
/// install prompt linking straight to Google Play (Android) or TestFlight (iOS).
///
/// Replaces the older email-capture flow — testers self-serve via the
/// Closed Testing opt-in URL, which auto-joins the public Google Group
/// `diaspora-nearby-testers@googlegroups.com` before sending them to the
/// Play Store listing.
class NativeAppPrompt {
  /// Public Play Store listing (Closed Testing track resolves to the same id;
  /// Play will route eligible testers to the testing build automatically).
  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.diasporanearby.diasporanearby';

  /// Call this from any native-only guard.
  /// Returns `true` if the user is on web (action was intercepted).
  /// Returns `false` on mobile (caller should proceed normally).
  static Future<bool> show(
    BuildContext context, {
    required String feature,
    required String description,
    required IconData icon,
  }) async {
    if (!kIsWeb) return false;
    if (!context.mounted) return true;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _NativeAppDialog(
        feature: feature,
        description: description,
        icon: icon,
      ),
    );

    return true;
  }
}

class _NativeAppDialog extends StatefulWidget {
  final String feature;
  final String description;
  final IconData icon;

  const _NativeAppDialog({
    required this.feature,
    required this.description,
    required this.icon,
  });

  @override
  State<_NativeAppDialog> createState() => _NativeAppDialogState();
}

class _NativeAppDialogState extends State<_NativeAppDialog> {
  String _detectedPlatform = 'unknown';

  @override
  void initState() {
    super.initState();
    _detectPlatform();
  }

  void _detectPlatform() {
    if (kIsWeb) {
      final tp = defaultTargetPlatform;
      if (tp == TargetPlatform.iOS || tp == TargetPlatform.macOS) {
        setState(() => _detectedPlatform = 'ios');
      } else if (tp == TargetPlatform.android) {
        setState(() => _detectedPlatform = 'android');
      } else {
        setState(() => _detectedPlatform = 'desktop');
      }
    }
  }

  Future<void> _openStore(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (mounted) Navigator.of(context).pop();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not open $url')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.15),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 32,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    'assets/icons/logo-transparent.png',
                    width: 64,
                    height: 64,
                  ),
                ),
                const SizedBox(height: 16),

                // Title
                Text(
                  'Get the Diaspora Nearby App',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),

                // Feature-specific message
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        widget.icon,
                        size: 22,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.feature,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.description,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.7,
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
                const SizedBox(height: 20),

                // Install CTA — platform-aware
                // iOS native app is not yet available; iOS users get the
                // PWA "Add to Home Screen" path via AppInstallCard instead,
                // so this dialog simply tells them so.
                if (_detectedPlatform == 'ios') ...[
                  Text(
                    'The native iOS app is coming soon. For now, install '
                    'Diaspora Nearby as a web app: tap the Share button in '
                    'Safari and choose "Add to Home Screen".',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.75,
                      ),
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ] else if (_detectedPlatform == 'android') ...[
                  _buildInstallButton(
                    theme: theme,
                    icon: LucideIcons.smartphone,
                    label: 'Install on Google Play',
                    onPressed: () => _openStore(NativeAppPrompt.playStoreUrl),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Opens Google Play — tap Install',
                    style: TextStyle(fontSize: 11, color: theme.hintColor),
                  ),
                ] else ...[
                  // Desktop / unknown — Android Play Store only
                  _buildInstallButton(
                    theme: theme,
                    icon: LucideIcons.smartphone,
                    label: 'Install on Google Play',
                    onPressed: () => _openStore(NativeAppPrompt.playStoreUrl),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Open this page on your Android phone to install',
                    style: TextStyle(fontSize: 11, color: theme.hintColor),
                  ),
                ],

                const SizedBox(height: 14),

                // Dismiss
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Not now',
                    style: TextStyle(color: theme.hintColor, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInstallButton({
    required ThemeData theme,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
