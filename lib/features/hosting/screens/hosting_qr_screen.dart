import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:diaspora_nearby/features/hosting/services/hosting_service.dart';
import 'package:diaspora_nearby/features/hosting/models/hosting_session.dart';
import 'package:diaspora_nearby/features/chat/services/chat_messaging_service.dart';
import 'package:diaspora_nearby/features/shared/ui/glass_container.dart';
import 'package:diaspora_nearby/features/notifications/models/notification_item.dart';
import 'package:diaspora_nearby/features/notifications/repository/notifications_repository.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

/// QR Check-in / Check-out screen for hosting sessions.
///
/// **Host** → shows a QR code containing the session ID.
/// **Traveler** → scans the QR code to activate check-in.
class HostingQRScreen extends ConsumerStatefulWidget {
  final HostingSession session;
  final bool isHost;

  const HostingQRScreen({
    super.key,
    required this.session,
    required this.isHost,
  });

  @override
  ConsumerState<HostingQRScreen> createState() => _HostingQRScreenState();
}

class _HostingQRScreenState extends ConsumerState<HostingQRScreen> {
  late bool _isScanning;
  String? _qrData;
  String? _scanError;
  String? _scanSuccess;
  bool _isProcessing = false;
  StreamSubscription<DocumentSnapshot>? _sessionListener;

  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  @override
  void initState() {
    super.initState();
    // Host shows QR by default, traveler scans by default
    _isScanning = !widget.isHost;
    _generateQR();

    // If host is showing QR, listen for session status changes
    // so we can detect when the traveler scans and checks in
    if (widget.isHost) {
      _startSessionListener();
    }
  }

  /// Listens to the Firestore session document for status changes.
  /// When traveler scans the QR, the session status changes to 'active'
  /// and this listener fires so the host sees confirmation + auto-dismiss.
  void _startSessionListener() {
    _sessionListener = FirebaseFirestore.instance
        .collection('hosting_sessions')
        .doc(widget.session.id)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      if (!snapshot.exists) return;

      final data = snapshot.data();
      if (data == null) return;

      final status = data['status'] as String?;
      if (status == 'active' && _scanSuccess == null) {
        // Traveler checked in — show confirmation on host's screen
        setState(() {
          _scanSuccess = 'Check-in Confirmed!';
          _isProcessing = false;
        });

        // Auto-dismiss after 2 seconds
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.of(context).pop();
        });
      }
    });
  }

  void _generateQR() {
    // Encode session data into the QR code
    final qrPayload = jsonEncode({
      'type': 'hosting_checkin',
      'sessionId': widget.session.id,
      'hostId': widget.session.hostId,
      'travelerId': widget.session.travelerId,
    });
    setState(() {
      _qrData = qrPayload;
    });
  }

  Future<void> _handleScan(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final barcodes = capture.barcodes;

    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        // Stop scanning to prevent re-triggers
        _controller.stop();
        setState(() {
          _isScanning = false;
          _isProcessing = true;
          _scanSuccess = 'Verifying...';
          _scanError = null;
        });

        try {
          // Parse QR data
          final raw = barcode.rawValue!;
          Map<String, dynamic> payload;
          try {
            payload = jsonDecode(raw) as Map<String, dynamic>;
          } catch (_) {
            _showError('Invalid QR code. Please scan the host\'s hosting QR.');
            return;
          }

          // Validate the QR type
          if (payload['type'] != 'hosting_checkin') {
            _showError('Wrong QR code type. Please scan the hosting QR.');
            return;
          }

          // Validate session ID matches
          final scannedSessionId = payload['sessionId'] as String?;
          if (scannedSessionId == null ||
              scannedSessionId != widget.session.id) {
            _showError(
                'This QR code is for a different hosting session.');
            return;
          }

          // Perform the check-in
          final hostingService = ref.read(hostingServiceProvider);
          final success = await hostingService.checkIn(scannedSessionId);

          if (!mounted) return;

          if (success) {
            // Send a system message to the DM
            await _sendCheckInMessage();

            // Mark hosting-selected notification as completed
            await _markNotificationsCompleted();

            setState(() {
              _scanSuccess = 'Check-in Confirmed!';
              _isProcessing = false;
            });

            // Auto-dismiss after 2 seconds
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) Navigator.of(context).pop();
            });
          } else {
            _showError('Check-in failed. Please try again.');
          }
        } catch (e) {
          _showError('Error during check-in. Please try again.');
        }
        break; // Only process first barcode
      }
    }
  }

  /// Sends a system message to the DM indicating check-in.
  Future<void> _sendCheckInMessage() async {
    final chatId = widget.session.chatId;
    if (chatId == null || chatId.isEmpty) return;

    try {
      final messagingService = ref.read(chatMessagingServiceProvider);
      await messagingService.sendTextMessage(
        chatId,
        'Check-in confirmed! The hosting session is now active. Enjoy your stay!',
        type: 'system',
        senderIdOverride: 'system',
        senderNameOverride: 'Hosting',
      );
    } catch (e) {
      debugPrint('[Hosting] Failed to send check-in message: $e');
    }
  }

  /// Mark any hosting-selected/interest notifications for this session as completed.
  Future<void> _markNotificationsCompleted() async {
    try {
      // Current user is the traveler (scanning) or host (showing QR)
      final userId = widget.isHost
          ? widget.session.hostId
          : widget.session.travelerId;

      final repo = ref.read(notificationsRepositoryProvider);
      final notifications = await repo.getNotificationsOnce(userId);

      for (final n in notifications) {
        final matchesSession = n.payload['sessionId'] == widget.session.id;
        final matchesRequest = n.payload['requestId'] == widget.session.requestId;

        if ((n.type == NotificationType.hostingSelected && matchesSession) ||
            (n.type == NotificationType.hostingInterest && matchesRequest)) {
          if (n.actionRequired && !n.actionCompleted) {
            await repo.markActionCompleted(userId, n.id);
          }
        }
      }
    } catch (e) {
      debugPrint('[Hosting] Failed to mark notifications completed: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _scanError = message;
      _scanSuccess = null;
      _isProcessing = false;
    });
  }

  void _toggleMode() {
    setState(() {
      _isScanning = !_isScanning;
      _scanError = null;
      _scanSuccess = null;
      _isProcessing = false;

      if (_isScanning) {
        _controller.start();
      } else {
        _controller.stop();
      }
    });
  }

  @override
  void dispose() {
    _sessionListener?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          widget.isHost ? 'Host Check-in Code' : 'Scan to Check In',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: const BackButton(),
        actions: [
          IconButton(
            icon: Icon(
              _isScanning ? LucideIcons.qrCode : LucideIcons.camera,
              color: onSurface,
            ),
            tooltip: _isScanning ? 'Show Code' : 'Scan Code',
            onPressed: _toggleMode,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [Colors.black, const Color(0xFF0A1A0A)]
                    : [const Color(0xFFFAFAFA), Colors.white],
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Error banner
                if (_scanError != null)
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(12),
                    decoration: AppTheme.cardDecoration(context),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.alertCircle,
                            color: AppTheme.error, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _scanError!,
                            style: GoogleFonts.outfit(
                              color: AppTheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Session info card
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: AppTheme.cardDecoration(context),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.plane,
                          size: 18, color: AppTheme.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.session.communityName,
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              widget.isHost
                                  ? 'Guest: ${widget.session.travelerName}'
                                  : 'Host: ${widget.session.hostName}',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                color: onSurface.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Main content
                Expanded(
                  child: Center(
                    child: _isScanning
                        ? _buildScannerView()
                        : _buildQRCodeView(context),
                  ),
                ),

                // Footer instructions
                Padding(
                  padding:
                      const EdgeInsets.only(bottom: 32, left: 24, right: 24),
                  child: Text(
                    _isScanning
                        ? 'Align the host\'s QR code within the frame to check in.'
                        : widget.isHost
                            ? 'Show this code to your guest when they arrive.'
                            : 'Ask your host to show their QR code, then scan it.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      color: onSurface.withValues(alpha: 0.5),
                      fontSize: 13,
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

  Widget _buildScannerView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: AspectRatio(
          aspectRatio: 1,
          child: Stack(
            children: [
              MobileScanner(
                controller: _controller,
                onDetect: _handleScan,
              ),
              // Scanner overlay frame
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.5),
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
                      color: AppTheme.accent,
                      width: 2.5,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQRCodeView(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: GlassContainer(
          borderRadius: BorderRadius.circular(32),
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Success state
              if (_scanSuccess != null && !_isProcessing) ...[
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: AppTheme.cardDecoration(context),
                  child: Column(
                    children: [
                      const Icon(
                        LucideIcons.checkCircle,
                        size: 80,
                        color: AppTheme.accent,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _scanSuccess!,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your hosting session is now active',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          color: onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ]
              // QR code display
              else if (_qrData != null) ...[
                Text(
                  'Hosting Check-in',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.isHost
                      ? 'Let your guest scan this code'
                      : 'Show this to verify your identity',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: _qrData!,
                    version: QrVersions.auto,
                    size: 220.0,
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
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(LucideIcons.shieldCheck,
                        size: 16, color: AppTheme.accent),
                    const SizedBox(width: 6),
                    Text(
                      'Verified Hosting Code',
                      style: GoogleFonts.outfit(
                        color: AppTheme.accent,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),

                // Host-specific: waiting indicator
                if (widget.isHost) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: AppTheme.innerDecoration(context),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Waiting for guest to scan...',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ]
              // Loading state
              else
                const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
