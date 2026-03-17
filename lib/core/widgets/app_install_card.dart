import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/core/services/pwa_install_service.dart';

/// Combined PWA install + native-app tester signup widget.
/// Shown only on web and only when NOT running as a standalone PWA.
///
/// Platform is auto-detected (android / ios / both for desktop).
/// On Android the single submit button triggers PWA install AND tester signup.
/// On iOS the PWA section shows Safari "Add to Home Screen" steps.
class AppInstallCard extends ConsumerStatefulWidget {
  const AppInstallCard({super.key});

  @override
  ConsumerState<AppInstallCard> createState() => _AppInstallCardState();
}

class _AppInstallCardState extends ConsumerState<AppInstallCard> {
  final _emailController = TextEditingController();
  bool _testerSignedUp = false;
  bool _submitting = false;
  bool _isStandalone = false;
  bool _showEmailError = false;

  static const _testerSignedUpKey = 'tester_signed_up';

  /// Auto-detected platform written to Firestore — no manual picker.
  static String get _detectedPlatform {
    if (!kIsWeb) return 'both';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return 'both'; // desktop browsers
    }
  }

  bool get _isIOS => kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  bool get _isAndroidOrDesktop =>
      kIsWeb && defaultTargetPlatform != TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    bool standalone = false;
    if (kIsWeb) {
      try {
        final notifier = ref.read(pwaInstallServiceProvider.notifier);
        standalone = notifier.isPwaStandalone();
      } catch (_) {}
    }

    setState(() {
      _testerSignedUp = prefs.getBool(_testerSignedUpKey) ?? false;
      _isStandalone = standalone;
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  /// Single action: installs PWA (on Android/desktop) AND submits tester signup.
  Future<void> _installAndSignUp() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _showEmailError = true);
      return;
    }

    setState(() => _submitting = true);

    try {
      // 1. Trigger PWA install prompt on Android/desktop
      if (_isAndroidOrDesktop) {
        try {
          final notifier = ref.read(pwaInstallServiceProvider.notifier);
          await notifier.promptInstall();
        } catch (_) {}
      }

      // 2. Write tester signup to Firestore
      final userId =
          ref.read(authRepositoryProvider).currentUser?.uid ?? '';

      await FirebaseFirestore.instance
          .collection('app_testers')
          .doc(email)
          .set({
        'email': email,
        'platform': _detectedPlatform,
        'userId': userId,
        'signedUpAt': FieldValue.serverTimestamp(),
        'status': 'pending',
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_testerSignedUpKey, true);

      if (mounted) {
        setState(() {
          _testerSignedUp = true;
          _submitting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(LucideIcons.checkCircle,
                    color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('Signed up! We\'ll send an invite to $email'),
              ],
            ),
            backgroundColor: AppTheme.accent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
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
                Icon(LucideIcons.download,
                    color: Colors.white, size: 18),
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
                // ── iOS: Safari instructions ──
                if (_isIOS) ...[
                  _buildIosInstructions(theme),
                  const SizedBox(height: 12),
                  Divider(
                    color: theme.dividerColor.withValues(alpha: 0.3),
                    height: 1,
                  ),
                  const SizedBox(height: 12),
                ],

                // ── Tester signup ──
                _buildTesterSection(theme),
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
              _iosStep('2', 'Scroll down & tap "Add to Home Screen"',
                  LucideIcons.plusSquare),
              _iosStep('3', 'Tap "Add" to confirm', LucideIcons.check),
            ],
          ),
        ),
      ],
    );
  }

  // ── Tester signup section ──
  Widget _buildTesterSection(ThemeData theme) {
    // Subtitle varies by platform
    final platformHint = _isIOS
        ? 'Get early access to the iOS app via TestFlight'
        : _detectedPlatform == 'android'
            ? 'Get early access to the Android app via Google Play'
            : 'Get early access to the native app before public launch';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(LucideIcons.smartphone, size: 16, color: Colors.deepPurple),
            const SizedBox(width: 6),
            Text(
              'Become a Native App Tester',
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

        if (_testerSignedUp) ...[
          // ✅ Already signed up
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppTheme.accent.withValues(alpha: 0.3),
              ),
            ),
            child: const Row(
              children: [
                Icon(LucideIcons.checkCircle,
                    size: 18, color: AppTheme.accent),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You\'re signed up as a tester! We\'ll email your invite soon.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          // Email field
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(fontSize: 13),
            onChanged: (_) {
              if (_showEmailError) setState(() => _showEmailError = false);
            },
            decoration: InputDecoration(
              hintText: 'your@email.com',
              prefixIcon: const Icon(LucideIcons.mail, size: 16),
              filled: true,
              fillColor: AppTheme.elevationColor(context, 2),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: _showEmailError
                    ? const BorderSide(color: Colors.red, width: 1.5)
                    : BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: _showEmailError
                    ? const BorderSide(color: Colors.red, width: 1.5)
                    : const BorderSide(color: AppTheme.accent, width: 1.5),
              ),
              errorText: _showEmailError ? 'Please enter a valid email' : null,
              errorStyle: const TextStyle(fontSize: 11),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),

          // Combined submit button — triggers PWA install + tester signup
          SizedBox(
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
              icon: _submitting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(LucideIcons.download, size: 14),
              label: Text(
                _submitting
                    ? 'Setting Up...'
                    : 'Install PWA & Sign Me Up',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13),
              ),
              onPressed: _submitting ? null : _installAndSignUp,
            ),
          ),
        ],
      ],
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
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(icon, size: 14, color: theme.hintColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: theme.hintColor),
            ),
          ),
        ],
      ),
    );
  }
}
