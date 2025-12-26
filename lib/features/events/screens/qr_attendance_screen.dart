import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/events/repository/event_repository.dart';

class QRAttendanceScreen extends ConsumerStatefulWidget {
  final String eventId;
  final String eventTitle;
  final bool isCreator;

  const QRAttendanceScreen({
    super.key,
    required this.eventId,
    required this.eventTitle,
    required this.isCreator,
  });

  @override
  ConsumerState<QRAttendanceScreen> createState() => _QRAttendanceScreenState();
}

class _QRAttendanceScreenState extends ConsumerState<QRAttendanceScreen> {
  bool _isScanning = true;
  String? _generatedCode;
  String? _scanError;
  String? _scanSuccess;
  
  final MobileScannerController controller = MobileScannerController();

  @override
  void initState() {
    super.initState();
    if (widget.isCreator) {
      _isScanning = false;
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
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanError = 'Failed to generate code';
        });
      }
    }
  }

  Future<void> _handleScan(BarcodeCapture capture) async {
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        final rawValue = barcode.rawValue!;
        controller.stop(); // Stop scanning immediately

        String attendanceCode = rawValue;
        
        // Try parsing JSON if applicable (based on existing logic hints)
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
             setState(() => _scanError = 'User not logged in');
             return;
          }

          final success = await repo.verifyAndMarkAttendance(widget.eventId, user.uid, attendanceCode);
          
          if (mounted) {
            if (success) {
              setState(() {
                _scanSuccess = 'Attendance Verified!';
                _isScanning = false;
              });
            } else {
              setState(() {
                _scanError = 'Invalid Code';
              });
              // Resume after delay
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) {
                  setState(() => _scanError = null);
                  controller.start();
                }
              });
            }
          }
        } catch (e) {
           if (mounted) {
             setState(() => _scanError = 'Error scanning code');
           }
        }
        break; // Process only first valid barcode
      }
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isCreator ? 'Event QR Code' : 'Scan Attendance'),
        actions: [
          IconButton(
            icon: Icon(_isScanning ? LucideIcons.qrCode : LucideIcons.camera),
            tooltip: _isScanning ? 'Show My Code' : 'Scan Code',
            onPressed: () {
              setState(() {
                _isScanning = !_isScanning;
                if (_isScanning) {
                  controller.start();
                } else {
                  controller.stop();
                  if (widget.isCreator && _generatedCode == null) {
                    _generateCode();
                  }
                }
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_scanError != null)
            Container(
              color: Colors.red.withOpacity(0.1),
              padding: const EdgeInsets.all(12),
              width: double.infinity,
              child: Text(
                _scanError!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
          if (_scanSuccess != null)
            Container(
              color: Colors.green.withOpacity(0.1),
              padding: const EdgeInsets.all(12),
              width: double.infinity,
              child: Text(
                _scanSuccess!,
                style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: _isScanning
                ? MobileScanner(
                    controller: controller,
                    onDetect: _handleScan,
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_generatedCode != null)
                          QrImageView(
                            data: _generatedCode!,
                            version: QrVersions.auto,
                            size: 250.0,
                            backgroundColor: Colors.white,
                          )
                        else if (widget.isCreator)
                          const CircularProgressIndicator()
                        else
                          const Text('You are not the creator of this event'),
                        
                        const SizedBox(height: 24),
                        if (_generatedCode != null)
                          Text(
                            'Code: $_generatedCode',
                            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          widget.eventTitle,
                          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

