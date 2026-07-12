import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/events/repository/event_repository.dart';
import 'package:diaspora_nearby/features/shared/ui/glass_container.dart';

class QRAttendanceScreen extends ConsumerStatefulWidget {
  final String eventId;
  final String eventTitle;
  final bool isCreator;

  const QRAttendanceScreen({
    super.key,
    required this.eventId,
    required this.eventTitle, // Passed for context but verifying against eventId
    required this.isCreator,
  });

  @override
  ConsumerState<QRAttendanceScreen> createState() => _QRAttendanceScreenState();
}

class _QRAttendanceScreenState extends ConsumerState<QRAttendanceScreen> {
  // Default to scanning for attendees, showing code for creators
  late bool _isScanning;
  String? _generatedCode;
  String? _scanError;
  String? _scanSuccess;

  // MobileScanner controller
  final MobileScannerController controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  @override
  void initState() {
    super.initState();
    _isScanning = kIsWeb
        ? false
        : !widget.isCreator; // Creator shows code by default

    if (widget.isCreator) {
      _generateCode();
    }
  }

  Future<void> _generateCode() async {
    final repo = ref.read(eventRepositoryProvider);
    try {
      final code = await repo.generateAttendanceCode(widget.eventId);
      if (mounted) {
        setState(() {
          _generatedCode = code;
          _scanError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanError = 'Failed to generate code. Please try again.';
        });
      }
    }
  }

  Future<void> _handleScan(BarcodeCapture capture) async {
    final List<Barcode> barcodes = capture.barcodes;

    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        final rawValue = barcode.rawValue!;

        // Stop scanning immediately to prevent multiple triggers
        controller.stop();
        setState(() => _isScanning = false);

        String attendanceCode = rawValue;

        // Try parsing JSON if applicable (legacy support or rigorous format)
        try {
          if (rawValue.trim().startsWith('{')) {
            final map = jsonDecode(rawValue);
            if (map is Map && map.containsKey('code')) {
              attendanceCode = map['code'].toString();
            }
          }
        } catch (_) {
          // Fallback to raw value
        }

        try {
          final repo = ref.read(eventRepositoryProvider);
          final user = ref.read(authStateProvider).value;

          if (user == null) {
            _showError('User not logged in');
            return;
          }

          // Optimistic UI Update
          setState(() => _scanSuccess = 'Verifying...');

          final result = await repo.verifyAndMarkAttendance(
            widget.eventId,
            user.uid,
            attendanceCode,
          );

          if (mounted) {
            switch (result) {
              case VerificationResult.success:
                setState(() => _scanSuccess = 'Check-in Confirmed! +100 DSP');
                break;
              case VerificationResult.alreadyCheckedIn:
                // Show as success state but with different message
                setState(() => _scanSuccess = 'You\'re already checked in!');
                break;
              case VerificationResult.invalidCode:
                _showError(
                  'Invalid Event Code. Please scan the official event QR.',
                );
                break;
              case VerificationResult.error:
                _showError('Error verifying attendance. Please try again.');
                break;
            }
          }
        } catch (e) {
          _showError('Error verifying attendance. Please try again.');
        }
        break; // Process only first valid barcode
      }
    }
  }

  void _showError(String message) {
    setState(() {
      _scanError = message;
      _scanSuccess = null;
    });
    // Can optionally restart scanner here if desired, but user might want to see error
  }

  // Toggle between modes
  void _toggleMode() {
    setState(() {
      _isScanning = !_isScanning;
      _scanError = null;
      _scanSuccess = null;

      if (_isScanning) {
        controller.start();
      } else {
        controller.stop();
        // If switching to show code mode and it's missing (e.g. valid for attendees to show code? No, primarily creator)
        // Attendees likely scan. Creators show.
        if (widget.isCreator && _generatedCode == null) {
          _generateCode();
        }
      }
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Theme colors
    final primaryColor = Theme.of(context).primaryColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(widget.isCreator ? 'Organizer Code' : 'Attendance Scan'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: const BackButton(),
        actions: [
          IconButton(
            icon: Icon(
              _isScanning ? LucideIcons.qrCode : LucideIcons.camera,
              color: isDark ? Colors.white : Colors.black,
            ),
            tooltip: _isScanning ? 'Show Code' : 'Scan Code',
            onPressed: _toggleMode,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Background Gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [Colors.black, const Color(0xFF1A1A1A)]
                    : [const Color(0xFFF5F9FF), Colors.white],
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Status Indicators
                if (_scanError != null)
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          LucideIcons.alertCircle,
                          color: Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _scanError!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ),

                if (_scanSuccess != null && widget.isCreator)
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.green.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          LucideIcons.checkCircle,
                          color: Colors.green,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _scanSuccess!,
                            style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Main Content
                Expanded(
                  child: Center(
                    child: _isScanning
                        ? Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: Stack(
                                  children: [
                                    MobileScanner(
                                      controller: controller,
                                      onDetect: _handleScan,
                                    ),
                                    // Scanner Overlay (Frame)
                                    Container(
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.5,
                                          ),
                                          width: 2,
                                        ),
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                    ),
                                    Center(
                                      child: Container(
                                        width: 200,
                                        height: 200,
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: primaryColor,
                                            width: 2,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        : SingleChildScrollView(
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: GlassContainer(
                                borderRadius: BorderRadius.circular(32),
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      widget.eventTitle,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Scan to check in',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(color: Colors.grey),
                                    ),
                                    const SizedBox(height: 24),
                                    if (!widget.isCreator &&
                                        _scanSuccess != null)
                                      Container(
                                        padding: const EdgeInsets.all(24),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            24,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.green.withValues(
                                                alpha: 0.1,
                                              ),
                                              blurRadius: 20,
                                              offset: const Offset(0, 10),
                                            ),
                                          ],
                                        ),
                                        child: Column(
                                          children: [
                                            const Icon(
                                              LucideIcons.checkCircle,
                                              size: 80,
                                              color: Colors.green,
                                            ),
                                            const SizedBox(height: 16),
                                            Text(
                                              _scanSuccess?.contains(
                                                        'already',
                                                      ) ==
                                                      true
                                                  ? 'You\'re already checked in!'
                                                  : 'You\'re checked in!',
                                              textAlign: TextAlign.center,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.green,
                                                  ),
                                            ),
                                            if (_scanSuccess?.contains(
                                                  'already',
                                                ) ==
                                                false) ...[
                                              const SizedBox(height: 8),
                                              const Text(
                                                '+100 DSP Awarded',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.black54,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      )
                                    else if (_generatedCode != null)
                                      Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            24,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.1,
                                              ),
                                              blurRadius: 20,
                                              offset: const Offset(0, 10),
                                            ),
                                          ],
                                        ),
                                        child: QrImageView(
                                          data: _generatedCode!,
                                          version: QrVersions.auto,
                                          size: 220.0,
                                          backgroundColor: Colors.white,
                                          eyeStyle: const QrEyeStyle(
                                            eyeShape: QrEyeShape.square,
                                            color: Colors.black,
                                          ),
                                          dataModuleStyle:
                                              const QrDataModuleStyle(
                                                dataModuleShape:
                                                    QrDataModuleShape.square,
                                                color: Colors.black87,
                                              ),
                                        ),
                                      )
                                    else if (_scanError != null &&
                                        !widget.isCreator)
                                      Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            LucideIcons.alertCircle,
                                            size: 64,
                                            color: Colors.red,
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            'Scan Failed',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.red,
                                                ),
                                          ),
                                          const SizedBox(height: 24),
                                          ElevatedButton.icon(
                                            onPressed: () {
                                              setState(() {
                                                _isScanning = true;
                                                _scanError = null;
                                                controller.start();
                                              });
                                            },
                                            icon: const Icon(
                                              LucideIcons.refreshCcw,
                                            ),
                                            label: const Text('Retry Scan'),
                                          ),
                                        ],
                                      )
                                    else
                                      const SizedBox(
                                        height: 200,
                                        child: Center(
                                          child: CircularProgressIndicator(),
                                        ),
                                      ),
                                    const SizedBox(height: 24),
                                    if (widget.isCreator)
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            LucideIcons.shieldCheck,
                                            size: 16,
                                            color: Colors.blue,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Official Event Code',
                                            style: TextStyle(
                                              color: Colors.blue.shade700,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
                // Footer instructions
                Padding(
                  padding: const EdgeInsets.only(
                    bottom: 32.0,
                    left: 24,
                    right: 24,
                  ),
                  child: Text(
                    _isScanning
                        ? 'Align the QR code within the frame to check in.'
                        : 'Show this code to attendees at the venue entrance.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
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
