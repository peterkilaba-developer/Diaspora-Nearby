import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:sms_autofill/sms_autofill.dart';
import 'auth_controller.dart';

class OTPVerificationScreen extends ConsumerStatefulWidget {
  final String verificationId;
  final String phoneNumber;

  const OTPVerificationScreen({
    super.key,
    required this.verificationId,
    required this.phoneNumber,
  });

  @override
  ConsumerState<OTPVerificationScreen> createState() =>
      _OTPVerificationScreenState();
}

class _OTPVerificationScreenState extends ConsumerState<OTPVerificationScreen>
    with CodeAutoFill {
  String _otpCode = '';
  bool _isListening = false;
  bool _autoDetected = false;

  @override
  void initState() {
    super.initState();
    _startListeningForCode();
  }

  @override
  void dispose() {
    cancel();
    unregisterListener();
    super.dispose();
  }

  @override
  void codeUpdated() {
    // This is called when SMS is detected
    if (code != null && code!.length == 6) {
      if (!mounted) return;
      setState(() {
        _otpCode = code!;
        _autoDetected = true;
        _isListening = false;
      });
      // Auto-verify
      _verify();
    }
  }

  Future<void> _startListeningForCode() async {
    try {
      setState(() => _isListening = true);
      // Start listening for incoming SMS
      await SmsAutoFill().listenForCode();
      // Get app signature for SMS format (useful for debugging)
      final signature = await SmsAutoFill().getAppSignature;
      print('OTPVerificationScreen: App Signature for SMS: $signature');
      
      // Auto-stop listening after 60 seconds
      Future.delayed(const Duration(seconds: 60), () {
        if (mounted && _isListening) {
          setState(() => _isListening = false);
        }
      });
    } catch (e) {
      print('OTPVerificationScreen: Failed to start listening: $e');
      setState(() => _isListening = false);
    }
  }

  void _verify() {
    if (_otpCode.length == 6) {
      final isLoading = ref.read(authControllerProvider);
      if (isLoading) return; // Prevent double submission

      ref.read(authControllerProvider.notifier).verifyOTP(
            context,
            widget.verificationId,
            _otpCode,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authControllerProvider);
    final theme = Theme.of(context);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: const Text('Verify Phone')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 24.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom -
                  kToolbarHeight -
                  48,
            ),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  // Icon
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        LucideIcons.lock,
                        size: 32,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
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
                    'We sent a 6-digit code to ${widget.phoneNumber}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  // Auto-detection status
                  if (_isListening || _autoDetected)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_isListening && !_autoDetected) ...[
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Listening for SMS...',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ] else if (_autoDetected) ...[
                            const Icon(
                              LucideIcons.check,
                              size: 16,
                              color: Colors.green,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Code auto-detected!',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: 48),
                  // OTP Input
                  PinFieldAutoFill(
                    decoration: BoxLooseDecoration(
                      strokeColorBuilder: FixedColorBuilder(
                        theme.colorScheme.primary,
                      ),
                      bgColorBuilder: FixedColorBuilder(
                        theme.colorScheme.surface,
                      ),
                      textStyle: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                      radius: const Radius.circular(8),
                    ),
                    currentCode: _otpCode,
                    codeLength: 6,
                    onCodeChanged: (code) {
                      setState(() {
                        _otpCode = code ?? '';
                      });
                      if (code?.length == 6) {
                        _verify();
                      }
                    },
                    onCodeSubmitted: (code) {
                      setState(() {
                        _otpCode = code;
                      });
                      _verify();
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
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: isLoading
                          ? SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                color: theme.colorScheme.onPrimary,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Verify',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Retry button
                  if (!_isListening)
                    TextButton.icon(
                      onPressed: _startListeningForCode,
                      icon: const Icon(LucideIcons.refreshCw, size: 16),
                      label: const Text('Retry SMS detection'),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
