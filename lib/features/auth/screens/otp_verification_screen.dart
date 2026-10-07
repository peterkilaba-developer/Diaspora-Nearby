import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:sms_autofill/sms_autofill.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'auth_controller.dart';

class OTPVerificationScreen extends ConsumerStatefulWidget {
  final String verificationId;
  final String phoneNumber;
  final bool isWhatsApp;

  const OTPVerificationScreen({
    super.key,
    required this.verificationId,
    required this.phoneNumber,
    this.isWhatsApp = false,
  });

  @override
  ConsumerState<OTPVerificationScreen> createState() =>
      _OTPVerificationScreenState();
}

class _OTPVerificationScreenState extends ConsumerState<OTPVerificationScreen>
    with CodeAutoFill, WidgetsBindingObserver, SingleTickerProviderStateMixin {
  String _otpCode = '';
  bool _isListening = false;
  bool _autoDetected = false;
  bool _isSubmitting = false;
  String _detectionSource = '';

  // Resend Countdown Timer
  Timer? _countdownTimer;
  int _countdownSeconds = 60;

  // Pulse Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Setup pulsing animation for the waiting icon
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _glowAnimation = Tween<double>(begin: 0.15, end: 0.35).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _startCountdown();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!widget.isWhatsApp) {
        _startListeningForCode();
      } else {
        // Check clipboard after first frame render in case user copied it from notification
        _checkClipboardForCode();
      }
    });
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownSeconds = 60;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdownSeconds > 0) {
        setState(() => _countdownSeconds--);
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // User may have switched to WhatsApp, tapped "Copy Code" or copied the SMS,
      // and switched back to the app. Check clipboard safely after frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _checkClipboardForCode();
        }
      });
    }
  }

  Future<void> _checkClipboardForCode() async {
    if (!mounted || _autoDetected || _otpCode.length == 6 || _isSubmitting) return;
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted) return;
      final text = clipboardData?.text?.trim();
      if (text == null || text.isEmpty) return;

      // Match 6 consecutive digits anywhere in clipboard string
      final match = RegExp(r'\b(\d{6})\b').firstMatch(text);
      if (match != null && mounted) {
        final extractedCode = match.group(1)!;
        debugPrint('📋 Code detected from clipboard: $extractedCode');

        // Always schedule state update and auto-verify after the current frame
        // to prevent "setState() or markNeedsBuild() called during build"
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _isSubmitting) return;
          setState(() {
            _otpCode = extractedCode;
            _autoDetected = true;
            _detectionSource = widget.isWhatsApp ? 'WhatsApp' : 'Clipboard';
          });

          // Automatically verify and proceed
          _verify();
        });
      }
    } catch (e) {
      debugPrint('Clipboard read skipped: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _pulseController.dispose();
    cancel();
    unregisterListener();
    super.dispose();
  }

  @override
  void codeUpdated() {
    // This is called when SMS is detected by sms_autofill
    if (code != null && code!.length == 6) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isSubmitting) return;
        setState(() {
          _otpCode = code!;
          _autoDetected = true;
          _isListening = false;
          _detectionSource = 'SMS';
        });
        // Auto-verify and proceed
        _verify();
      });
    }
  }

  Future<void> _startListeningForCode() async {
    try {
      setState(() => _isListening = true);
      // Start listening for incoming SMS
      await SmsAutoFill().listenForCode();
      final signature = await SmsAutoFill().getAppSignature;
      debugPrint('OTPVerificationScreen: App Signature for SMS: $signature');

      Future.delayed(const Duration(seconds: 60), () {
        if (mounted && _isListening) {
          setState(() => _isListening = false);
        }
      });
    } catch (e) {
      debugPrint('OTPVerificationScreen: Failed to start listening: $e');
      if (mounted) setState(() => _isListening = false);
    }
  }

  void _verify() {
    if (_isSubmitting || _otpCode.length != 6) return;
    final isLoading = ref.read(authControllerProvider);
    if (isLoading) return; // Prevent double submission

    _isSubmitting = true;
    if (widget.isWhatsApp) {
      ref
          .read(authControllerProvider.notifier)
          .verifyWhatsAppOTP(context, widget.phoneNumber, _otpCode);
    } else {
      ref
          .read(authControllerProvider.notifier)
          .verifyOTP(context, widget.verificationId, _otpCode);
    }
  }

  void _handleResend() {
    if (_countdownSeconds > 0) return;
    _startCountdown();
    if (widget.isWhatsApp) {
      ref
          .read(authControllerProvider.notifier)
          .signInWithWhatsApp(context, widget.phoneNumber);
    } else {
      _startListeningForCode();
      ref
          .read(authControllerProvider.notifier)
          .signInWithPhone(context, widget.phoneNumber);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Reset submission lock if loading ends (e.g. error received)
    ref.listen<bool>(authControllerProvider, (previous, next) {
      if (previous == true && next == false && mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    });

    final isLoading = ref.watch(authControllerProvider);
    final theme = Theme.of(context);
    final isWhatsApp = widget.isWhatsApp;
    final accentColor = isWhatsApp ? Colors.green : theme.colorScheme.primary;

    return Scaffold(
      resizeToAvoidBottomInset: !kIsWeb,
      appBar: AppBar(title: const Text('Verify Phone')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight:
                  MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom -
                  kToolbarHeight -
                  48,
            ),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  // Animated Pulsing Badge Icon
                  Center(
                    child: AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        final scale = _autoDetected ? 1.0 : _pulseAnimation.value;
                        final glowAlpha = _autoDetected ? 0.3 : _glowAnimation.value;

                        return Transform.scale(
                          scale: scale,
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accentColor.withValues(alpha: 0.12),
                              boxShadow: [
                                BoxShadow(
                                  color: accentColor.withValues(alpha: glowAlpha),
                                  blurRadius: _autoDetected ? 20 : 16 * scale,
                                  spreadRadius: _autoDetected ? 4 : (scale - 1.0) * 14,
                                ),
                              ],
                            ),
                            child: Icon(
                              _autoDetected
                                  ? LucideIcons.checkCheck
                                  : (isWhatsApp
                                      ? LucideIcons.messageCircle
                                      : LucideIcons.shieldCheck),
                              size: 38,
                              color: _autoDetected ? Colors.green : accentColor,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Enter Verification Code',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isWhatsApp
                        ? 'We sent a 6-digit WhatsApp message to\n${widget.phoneNumber}'
                        : 'We sent a 6-digit SMS to\n${widget.phoneNumber}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),

                  // Dynamic Real-time Status Badge
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _autoDetected
                            ? Colors.green.withValues(alpha: 0.12)
                            : accentColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _autoDetected
                              ? Colors.green.withValues(alpha: 0.3)
                              : accentColor.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_autoDetected) ...[
                            const Icon(
                              LucideIcons.checkCircle2,
                              size: 16,
                              color: Colors.green,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Code detected from $_detectionSource! Verifying...',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ] else if (isWhatsApp) ...[
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: accentColor,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Waiting for code... (Tap Copy Code in WhatsApp)',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: accentColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ] else if (_isListening) ...[
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: accentColor,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Listening for SMS code...',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: accentColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ] else ...[
                            Icon(
                              LucideIcons.clock,
                              size: 14,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Code expires in 5 minutes',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 36),

                  // PIN Input Field
                  PinFieldAutoFill(
                    decoration: BoxLooseDecoration(
                      strokeColorBuilder: FixedColorBuilder(accentColor),
                      bgColorBuilder: FixedColorBuilder(theme.colorScheme.surface),
                      textStyle: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                      radius: const Radius.circular(10),
                    ),
                    currentCode: _otpCode,
                    codeLength: 6,
                    onCodeChanged: (code) {
                      if (code != null && code != _otpCode) {
                        setState(() {
                          _otpCode = code;
                          _isSubmitting = false;
                        });
                      }
                      // Auto-verify as soon as 6 digits are typed or pasted
                      if (code?.length == 6 && !_isSubmitting) {
                        _verify();
                      }
                    },
                    onCodeSubmitted: (code) {
                      if (code.length == 6 && !_isSubmitting) {
                        setState(() {
                          _otpCode = code;
                        });
                        _verify();
                      }
                    },
                  ),

                  const Spacer(),

                  // Verify Button
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: isLoading || _otpCode.length != 6
                          ? null
                          : _verify,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: isLoading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Verify and Proceed',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Resend and Fallback Actions with Timer
                  Center(
                    child: _countdownSeconds > 0
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  LucideIcons.timer,
                                  size: 15,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Resend code in ${_countdownSeconds}s',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : TextButton.icon(
                            onPressed: _handleResend,
                            icon: Icon(
                              LucideIcons.refreshCw,
                              size: 16,
                              color: accentColor,
                            ),
                            label: Text(
                              isWhatsApp
                                  ? 'Resend WhatsApp Message'
                                  : 'Resend SMS Code',
                              style: TextStyle(
                                color: accentColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                  ),

                  if (!isWhatsApp) ...[
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton.icon(
                        onPressed: () {
                          ref
                              .read(authControllerProvider.notifier)
                              .signInWithWhatsApp(context, widget.phoneNumber);
                        },
                        icon: const Icon(
                          LucideIcons.messageCircle,
                          size: 16,
                          color: Colors.green,
                        ),
                        label: const Text(
                          'Didn\'t receive SMS? Send via WhatsApp',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
