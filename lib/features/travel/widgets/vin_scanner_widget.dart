import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/core/widgets/native_app_prompt.dart';

/// Result from VIN scanning — either barcode or OCR.
class VinScanResult {
  final String vin;
  final String source; // 'barcode' or 'ocr'
  const VinScanResult({required this.vin, required this.source});
}

/// Shows a bottom sheet with camera for scanning VIN barcodes or OCR from
/// paperwork / door panel stickers.
///
/// Returns `null` if cancelled, or a [VinScanResult] on success.
Future<VinScanResult?> showVinScanner(BuildContext context) {
  if (kIsWeb) {
    NativeAppPrompt.show(
      context,
      feature: 'VIN Scanner',
      description: 'VIN barcode and OCR scanning requires the native app.',
      icon: LucideIcons.scan,
    );
    return Future.value(null);
  }
  return showModalBottomSheet<VinScanResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _VinScannerSheet(),
  );
}

class _VinScannerSheet extends StatefulWidget {
  const _VinScannerSheet();

  @override
  State<_VinScannerSheet> createState() => _VinScannerSheetState();
}

class _VinScannerSheetState extends State<_VinScannerSheet> {
  // 0 = barcode, 1 = OCR (photo)
  int _mode = 0;
  bool _processing = false;
  String? _statusText;
  MobileScannerController? _scannerController;
  bool _hasReturned = false;

  @override
  void initState() {
    super.initState();
    _initScanner();
  }

  void _initScanner() {
    _scannerController = MobileScannerController(
      // Accept ALL barcode formats — VINs can be encoded as Code 39,
      // Code 128, PDF417, Data Matrix, QR, Code 93, ITF, etc.
      // Don't restrict formats; let the scanner detect whatever it finds.
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    super.dispose();
  }

  // ── VIN validation ────────────────────────────────────────────────
  // Standard VIN: 17 alphanumeric chars, excluding I, O, Q
  static final _vinRegex = RegExp(r'[A-HJ-NPR-Z0-9]{17}');

  /// Cleans scanned/OCR text and tries to extract a valid 17-char VIN.
  /// Handles common OCR misreads (O→0, I→1, Q→0, etc.)
  String? _extractVin(String text) {
    // Remove spaces, dashes, tabs, newlines
    final cleaned = text
        .replaceAll(RegExp(r'[\s\-\t\n\r]'), '')
        .toUpperCase();

    // First try: exact match
    final exact = _vinRegex.firstMatch(cleaned);
    if (exact != null) return exact.group(0);

    // Second try: OCR-correction pass
    // VINs never contain I, O, Q — OCR sometimes reads:
    //   0 as O, 1 as I/l, 5 as S, 8 as B
    // We fix common OCR errors and re-match
    final ocrFixed = cleaned
        .replaceAll('O', '0')  // O → 0 (VINs don't use O)
        .replaceAll('I', '1')  // I → 1 (VINs don't use I)
        .replaceAll('Q', '0')  // Q → 0 (VINs don't use Q)
        .replaceAll('o', '0')
        .replaceAll('i', '1')
        .replaceAll('l', '1')  // lowercase L → 1
        .replaceAll('q', '0');

    final fixedMatch = _vinRegex.firstMatch(ocrFixed);
    if (fixedMatch != null) return fixedMatch.group(0);

    // Third try: look at each line separately (OCR text may have
    // the VIN on its own line among other text)
    for (final line in text.split(RegExp(r'[\n\r]+'))) {
      final lineCleaned = line
          .replaceAll(RegExp(r'[\s\-]'), '')
          .toUpperCase()
          .replaceAll('O', '0')
          .replaceAll('I', '1')
          .replaceAll('Q', '0');
      final lineMatch = _vinRegex.firstMatch(lineCleaned);
      if (lineMatch != null) return lineMatch.group(0);
    }

    return null;
  }

  /// Safely return with result — prevents double-pop
  void _returnResult(VinScanResult result) {
    if (_hasReturned || !mounted) return;
    _hasReturned = true;
    _scannerController?.stop();
    Navigator.pop(context, result);
  }

  // ── Barcode callback ──────────────────────────────────────────────
  void _onBarcodeDetected(BarcodeCapture capture) {
    if (_processing || _hasReturned) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue ?? barcode.displayValue;
      if (raw == null || raw.isEmpty) continue;

      debugPrint('[VIN Scanner] Barcode detected: $raw (format: ${barcode.format})');

      final vin = _extractVin(raw);
      if (vin != null) {
        setState(() => _processing = true);
        _returnResult(VinScanResult(vin: vin, source: 'barcode'));
        return;
      }
    }
  }



  /// Pick from gallery (useful for previously taken photos / scanned docs)
  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 100,
    );
    if (xfile == null || !mounted) return;

    setState(() {
      _processing = true;
      _statusText = 'Reading text from image...';
    });

    try {
      final file = File(xfile.path);
      final inputImage = InputImage.fromFile(file);
      final recognizer = TextRecognizer();
      final recognized = await recognizer.processImage(inputImage);
      await recognizer.close();

      final fullText = recognized.text;
      debugPrint('[VIN Scanner] Gallery OCR text: $fullText');

      if (!mounted) return;

      String? vin = _extractVin(fullText);
      if (vin == null) {
        for (final block in recognized.blocks) {
          vin = _extractVin(block.text);
          if (vin != null) break;
          for (final line in block.lines) {
            vin = _extractVin(line.text);
            if (vin != null) break;
          }
          if (vin != null) break;
        }
      }

      if (vin != null) {
        _returnResult(VinScanResult(vin: vin, source: 'ocr'));
      } else {
        setState(() {
          _processing = false;
          _statusText = fullText.isEmpty
              ? 'No text detected. Ensure VIN is clearly visible.'
              : 'No valid VIN found. Try a different image.';
        });
      }
    } catch (e) {
      debugPrint('[VIN Scanner] Gallery OCR error: $e');
      if (!mounted) return;
      setState(() {
        _processing = false;
        _statusText = 'OCR failed: ${e.toString().split('\n').first}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: AppTheme.elevationColor(context, 3),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // ── Handle ──
          const SizedBox(height: 8),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: theme.hintColor.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),

          // ── Title ──
          Text(
            'Scan VIN Number',
            style: TextStyle(
              fontSize: 17, fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _mode == 0
                ? 'Point camera at VIN barcode on door panel'
                : 'Take a photo of VIN on paperwork',
            style: TextStyle(fontSize: 12, color: theme.hintColor),
          ),
          const SizedBox(height: 12),

          // ── Mode toggle ──
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppTheme.elevationColor(context, 1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _modeTab(0, LucideIcons.focus, 'Barcode', isDark),
                const SizedBox(width: 4),
                _modeTab(1, LucideIcons.camera, 'Photo / OCR', isDark),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Unified camera preview ──
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    MobileScanner(
                      controller: _scannerController!,
                      onDetect: _onBarcodeDetected,
                      errorBuilder: (context, error) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(LucideIcons.cameraOff,
                                    size: 48, color: Colors.red),
                                const SizedBox(height: 12),
                                Text(
                                  'Camera error: ${error.errorDetails?.message ?? error.errorCode.name}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: Colors.red, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    // Viewfinder — wider for barcode, thinner for text
                    if (!_processing)
                      Center(
                        child: Container(
                          width: 280,
                          height: _mode == 0 ? 80 : 50,
                          decoration: BoxDecoration(
                            border:
                                Border.all(color: AppTheme.accent, width: 2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    // Bottom hint
                    if (!_processing)
                      Positioned(
                        bottom: 16,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              _mode == 0
                                  ? 'Align VIN barcode within the frame'
                                  : 'Position VIN text, then tap Capture',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11),
                            ),
                          ),
                        ),
                      ),
                    // Processing overlay
                    if (_processing)
                      Container(
                        color: Colors.black.withValues(alpha: 0.6),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(
                                  color: AppTheme.accent),
                              const SizedBox(height: 12),
                              Text(
                                _statusText ?? 'Processing...',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // ── OCR capture buttons (Photo mode only) ──
          if (_mode == 1 && !_processing)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickFromGallery,
                      icon: const Icon(LucideIcons.image,
                          size: 16, color: AppTheme.accent),
                      label: const Text('Gallery',
                          style: TextStyle(
                              color: AppTheme.accent, fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: AppTheme.accent.withValues(alpha: 0.4)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _captureForOcr,
                      icon: const Icon(LucideIcons.focus, size: 18),
                      label: const Text('Capture VIN',
                          style: TextStyle(fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── Status text ──
          if (_statusText != null && !_processing)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                _statusText!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: theme.hintColor),
              ),
            ),

          SizedBox(height: bottomPad + 8),
        ],
      ),
    );
  }

  Widget _modeTab(int index, IconData icon, String label, bool isDark) {
    final selected = _mode == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _mode = index;
            _statusText = null;
            _processing = false;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.accent.withValues(alpha: isDark ? 0.2 : 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16,
                  color: selected ? AppTheme.accent : Theme.of(context).hintColor),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? AppTheme.accent : Theme.of(context).hintColor,
              )),
            ],
          ),
        ),
      ),
    );
  }

  // ── Capture photo for OCR ──────────────────────────────────────────
  Future<void> _captureForOcr() async {
    // Stop scanner to release camera for image_picker
    await _scannerController?.stop();

    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
      imageQuality: 100,
    );

    if (xfile == null || !mounted) {
      // User cancelled — restart scanner
      if (mounted) {
        try {
          await _scannerController?.start();
        } catch (_) {}
      }
      return;
    }

    setState(() {
      _processing = true;
      _statusText = 'Reading VIN from image...';
    });

    try {
      final file = File(xfile.path);
      final inputImage = InputImage.fromFile(file);
      final recognizer = TextRecognizer();
      final recognized = await recognizer.processImage(inputImage);
      await recognizer.close();

      try {
        await file.delete();
      } catch (_) {}

      final fullText = recognized.text;
      debugPrint('[VIN Scanner] OCR text: $fullText');

      if (!mounted) return;

      String? vin = _extractVin(fullText);
      if (vin == null) {
        for (final block in recognized.blocks) {
          vin = _extractVin(block.text);
          if (vin != null) break;
          for (final line in block.lines) {
            vin = _extractVin(line.text);
            if (vin != null) break;
          }
          if (vin != null) break;
        }
      }

      if (vin != null) {
        _returnResult(VinScanResult(vin: vin, source: 'ocr'));
      } else {
        if (mounted) {
          try {
            await _scannerController?.start();
          } catch (_) {}
        }
        setState(() {
          _processing = false;
          _statusText = fullText.isEmpty
              ? 'No text detected. Ensure VIN is clearly visible and well-lit.'
              : 'No valid VIN found. Try a clearer photo with VIN centered.';
        });
      }
    } catch (e) {
      debugPrint('[VIN Scanner] OCR error: $e');
      if (mounted) {
        try {
          await _scannerController?.start();
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _processing = false;
        _statusText = 'OCR failed: ${e.toString().split('\n').first}';
      });
    }
  }
}
