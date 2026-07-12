import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Detects native-only feature attempts on web and shows an email capture
/// dialog for TestFlight / Play Store beta invites.
///
/// • First native-only hit (no email submitted) → full dialog with email field
/// • Submitted email before → snackbar reminder
/// • Dismissed without submitting → re-prompt on next native-only hit
class NativeAppPrompt {
  static const _prefKey = 'native_app_email_submitted';

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

    final prefs = await SharedPreferences.getInstance();
    final alreadySubmitted = prefs.getBool(_prefKey) ?? false;

    if (!context.mounted) return true;

    if (alreadySubmitted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF2A2A2A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          content: Row(
            children: [
              const Icon(
                LucideIcons.smartphone,
                size: 18,
                color: Color(0xFF9CAF88),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$feature requires the native app. Check your email to download it 📱',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 4),
        ),
      );
      return true;
    }

    // Show full dialog
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

  /// Detect the user's mobile platform from web user agent
  static String detectPlatform() {
    // On web we detect in the dialog via user agent; this is a fallback
    return 'unknown';
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
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;
  String _detectedPlatform = 'unknown';

  @override
  void initState() {
    super.initState();
    _detectPlatform();
    _prefillEmail();
  }

  void _detectPlatform() {
    if (kIsWeb) {
      // Use defaultTargetPlatform which detects mobile browsers on web
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

  void _prefillEmail() {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email != null && user!.email!.isNotEmpty) {
      _emailController.text = user.email!;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;

      await FirebaseFirestore.instance.collection('app_requests').add({
        'email': _emailController.text.trim(),
        'feature': widget.feature,
        'platform': _detectedPlatform,
        'userId': userId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Mark as submitted
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(NativeAppPrompt._prefKey, true);

      if (mounted) {
        Navigator.of(context).pop();
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
                Expanded(
                  child: Text(
                    'Thanks! We\'ll send you the download link soon 🎉',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('NativeAppPrompt: Error saving: $e');
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
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
            child: Form(
              key: _formKey,
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

                  // Platform badge
                  if (_detectedPlatform != 'unknown')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _detectedPlatform == 'ios'
                                ? LucideIcons.apple
                                : _detectedPlatform == 'android'
                                ? LucideIcons.smartphone
                                : LucideIcons.monitor,
                            size: 14,
                            color: theme.hintColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _detectedPlatform == 'ios'
                                ? 'iOS TestFlight invite'
                                : _detectedPlatform == 'android'
                                ? 'Google Play beta invite'
                                : 'Download links coming soon',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.hintColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Email field
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Enter your email address';
                      }
                      if (!val.contains('@') || !val.contains('.')) {
                        return 'Enter a valid email address';
                      }
                      return null;
                    },
                    decoration: InputDecoration(
                      hintText: 'your@email.com',
                      prefixIcon: Icon(
                        LucideIcons.mail,
                        size: 18,
                        color: theme.hintColor,
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.colorScheme.outline.withValues(
                            alpha: 0.3,
                          ),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.colorScheme.outline.withValues(
                            alpha: 0.3,
                          ),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.colorScheme.primary,
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isSubmitting ? null : _submit,
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(LucideIcons.send, size: 16),
                      label: Text(
                        _isSubmitting
                            ? 'Sending...'
                            : _detectedPlatform == 'ios'
                            ? 'Send me the TestFlight Link'
                            : _detectedPlatform == 'android'
                            ? 'Send me the Play Store Link'
                            : 'Send me the Download Link',
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: theme.colorScheme.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

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
      ),
    );
  }
}
