import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:diaspora_nearby/config/env.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:diaspora_nearby/theme/app_theme.dart';

/// Data returned from the land survey screen.
class LandSurveyResult {
  final List<Map<String, double>> boundaryPoints;
  final double centerLat;
  final double centerLng;
  final double areaSqm;
  final String? address;
  final String? city;
  final String? state;
  final String? country;
  final String? countryCode;
  final String? subLocality;

  LandSurveyResult({
    required this.boundaryPoints,
    required this.centerLat,
    required this.centerLng,
    required this.areaSqm,
    this.address,
    this.city,
    this.state,
    this.country,
    this.countryCode,
    this.subLocality,
  });

  /// Convert area to user-friendly display in m² / ft²
  String get areaLabel {
    final sqft = areaSqm * 10.7639;
    return '${areaSqm.toStringAsFixed(0)} m\u00B2 / ${sqft.toStringAsFixed(0)} ft\u00B2';
  }
}

/// GPS Land Survey screen for capturing property boundary points.
///
/// Flow:
/// 1. User walks to each corner and taps "Mark Corner"
/// 2. After 4+ points, the polygon shape and area are shown
/// 3. Center point is auto-computed from the polygon centroid
/// 4. Location is auto-fetched via reverse geocoding
/// 5. Returns [LandSurveyResult] with all data
class LandSurveyScreen extends StatefulWidget {
  const LandSurveyScreen({super.key});

  @override
  State<LandSurveyScreen> createState() => _LandSurveyScreenState();
}

class _LandSurveyScreenState extends State<LandSurveyScreen>
    with SingleTickerProviderStateMixin {
  final List<Map<String, double>> _boundaryPoints = [];
  final List<double> _pointAccuracies = []; // accuracy for each captured point
  Map<String, double>? _centerPoint;
  double? _areaSqm;
  double? _currentAccuracy;
  bool _isCapturing = false;
  bool _isGeocodingCenter = false;
  bool _hasGeocodedCenter = false;
  String? _error;
  String? _geocodedAddress;
  String? _geocodedCity;
  String? _geocodedState;
  String? _geocodedCountry;
  String? _geocodedCountryCode;
  String? _geocodedSubLocality;
  int _aerialViewMode =
      0; // 0 = Property aerial, 1 = Location map, 2 = Neighborhood aerial

  // GPS averaging state
  int _sampleCount = 0;
  double? _liveBestAccuracy;
  StreamSubscription<Position>? _gpsSubscription;

  /// Duration to collect GPS samples (seconds)
  static const _gpsSampleDuration = 5;

  /// Max acceptable accuracy for a sample (meters)
  static const _maxAcceptableAccuracy = 20.0;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _checkPermissions();
  }

  @override
  void dispose() {
    _gpsSubscription?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    if (kIsWeb) return;
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(
        () => _error =
            'Location services are disabled.\n'
            'Please enable GPS in your device settings.',
      );
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(
        () => _error =
            'Location permission is required\n'
            'to survey land boundaries.',
      );
    }
  }

  /// Capture a corner using multi-sample GPS averaging for higher accuracy.
  ///
  /// Streams GPS readings for [_gpsSampleDuration] seconds, keeps only
  /// readings with accuracy ≤ [_maxAcceptableAccuracy], then averages
  /// the coordinates weighted by inverse accuracy (better readings
  /// contribute more). Typical result: 3-8 m in open sky vs 15-25 m single-shot.
  Future<void> _captureCorner() async {
    setState(() {
      _isCapturing = true;
      _sampleCount = 0;
      _liveBestAccuracy = null;
      _error = null;
    });

    final samples = <Position>[];

    try {
      final completer = Completer<void>();

      _gpsSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.best,
              distanceFilter: 0,
            ),
          ).listen(
            (pos) {
              if (pos.accuracy <= _maxAcceptableAccuracy) {
                samples.add(pos);
              }
              setState(() {
                _sampleCount = samples.length;
                if (_liveBestAccuracy == null ||
                    pos.accuracy < _liveBestAccuracy!) {
                  _liveBestAccuracy = pos.accuracy;
                }
              });
            },
            onError: (e) {
              if (!completer.isCompleted) completer.completeError(e);
            },
          );

      // Collect for the sampling duration
      await Future.delayed(const Duration(seconds: _gpsSampleDuration));
      await _gpsSubscription?.cancel();
      _gpsSubscription = null;

      if (samples.isEmpty) {
        // Fallback: take a single best-effort reading
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 0,
          ),
        );
        samples.add(pos);
      }

      // Weighted average: weight = 1 / accuracy (better accuracy → higher weight)
      double weightedLat = 0, weightedLng = 0, totalWeight = 0;
      double bestAcc = double.infinity;
      for (final s in samples) {
        final w = 1.0 / s.accuracy;
        weightedLat += s.latitude * w;
        weightedLng += s.longitude * w;
        totalWeight += w;
        if (s.accuracy < bestAcc) bestAcc = s.accuracy;
      }

      final avgLat = weightedLat / totalWeight;
      final avgLng = weightedLng / totalWeight;

      setState(() {
        _boundaryPoints.add({'lat': avgLat, 'lng': avgLng});
        _pointAccuracies.add(bestAcc);
        _currentAccuracy = bestAcc;
        _isCapturing = false;
        _sampleCount = 0;
        _liveBestAccuracy = null;
        if (_boundaryPoints.length >= 4) {
          _areaSqm = _calculateAreaSqm(_boundaryPoints);
          _computeCentroidAndGeocode();
        }
      });
    } catch (e) {
      await _gpsSubscription?.cancel();
      _gpsSubscription = null;
      setState(() {
        _error = 'GPS error: $e';
        _isCapturing = false;
        _sampleCount = 0;
        _liveBestAccuracy = null;
      });
    }
  }

  /// Compute the centroid of the boundary polygon and reverse-geocode it.
  Future<void> _computeCentroidAndGeocode() async {
    if (_boundaryPoints.length < 4) return;

    // Calculate centroid as the average of all boundary points
    double cLat = 0, cLng = 0;
    for (final p in _boundaryPoints) {
      cLat += p['lat']!;
      cLng += p['lng']!;
    }
    cLat /= _boundaryPoints.length;
    cLng /= _boundaryPoints.length;

    _centerPoint = {'lat': cLat, 'lng': cLng};

    // Only geocode once (or if center moved significantly)
    if (_hasGeocodedCenter) return;

    setState(() => _isGeocodingCenter = true);

    try {
      final placemarks = await placemarkFromCoordinates(cLat, cLng);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        _geocodedAddress = [
          p.street,
          p.name,
        ].where((s) => s != null && s.isNotEmpty).toSet().join(', ');
        _geocodedCity = p.locality ?? p.subAdministrativeArea;
        _geocodedState = p.administrativeArea;
        _geocodedCountry = p.country;
        _geocodedCountryCode = p.isoCountryCode;
        _geocodedSubLocality = p.subLocality;
        _hasGeocodedCenter = true;
      }
    } catch (e) {
      debugPrint('Geocoding error: $e');
      // Non-fatal — we still have the coordinates
    }

    if (mounted) setState(() => _isGeocodingCenter = false);
  }

  /// Re-geocode the auto-computed center (e.g. after undo/add changes polygon).
  Future<void> _refreshGeocode() async {
    _hasGeocodedCenter = false;
    _geocodedAddress = null;
    _geocodedCity = null;
    _geocodedState = null;
    _geocodedCountry = null;
    _geocodedCountryCode = null;
    _geocodedSubLocality = null;
    await _computeCentroidAndGeocode();
  }

  void _removeLastPoint() {
    if (_boundaryPoints.isEmpty) return;
    setState(() {
      _boundaryPoints.removeLast();
      if (_pointAccuracies.isNotEmpty) _pointAccuracies.removeLast();
      if (_boundaryPoints.length >= 4) {
        _areaSqm = _calculateAreaSqm(_boundaryPoints);
        _refreshGeocode();
      } else {
        _areaSqm = null;
        _centerPoint = null;
        _hasGeocodedCenter = false;
        _geocodedAddress = null;
        _geocodedCity = null;
        _geocodedState = null;
        _geocodedCountry = null;
        _geocodedCountryCode = null;
        _geocodedSubLocality = null;
      }
    });
  }

  void _resetAll() {
    _gpsSubscription?.cancel();
    _gpsSubscription = null;
    setState(() {
      _boundaryPoints.clear();
      _pointAccuracies.clear();
      _centerPoint = null;
      _areaSqm = null;
      _hasGeocodedCenter = false;
      _geocodedAddress = null;
      _geocodedCity = null;
      _geocodedState = null;
      _geocodedCountry = null;
      _geocodedCountryCode = null;
      _geocodedSubLocality = null;
      _error = null;
      _isCapturing = false;
      _sampleCount = 0;
      _liveBestAccuracy = null;
    });
  }

  void _confirmSurvey() {
    if (_boundaryPoints.length < 4 || _centerPoint == null) return;
    if (_isGeocodingCenter) return; // Wait for geocoding to finish

    Navigator.pop(
      context,
      LandSurveyResult(
        boundaryPoints: List.from(_boundaryPoints),
        centerLat: _centerPoint!['lat']!,
        centerLng: _centerPoint!['lng']!,
        areaSqm: _areaSqm ?? 0,
        address: _geocodedAddress,
        city: _geocodedCity,
        state: _geocodedState,
        country: _geocodedCountry,
        countryCode: _geocodedCountryCode,
        subLocality: _geocodedSubLocality,
      ),
    );
  }

  // ─── Area calculation using geodesic Shoelace formula ───────────────

  /// Calculate area of polygon in square meters using the geodesic method.
  /// Uses the Shoelace formula with Haversine distance to account for
  /// Earth's curvature.
  double _calculateAreaSqm(List<Map<String, double>> points) {
    if (points.length < 4) return 0;

    // Convert to radians
    final coords = points
        .map((p) => [p['lat']! * pi / 180, p['lng']! * pi / 180])
        .toList();

    // Spherical excess formula for geodesic polygons
    const earthRadius = 6371000.0; // meters
    double area = 0;
    final n = coords.length;

    for (int i = 0; i < n; i++) {
      final j = (i + 1) % n;
      area +=
          (coords[j][1] - coords[i][1]) *
          (2 + sin(coords[i][0]) + sin(coords[j][0]));
    }

    area = (area * earthRadius * earthRadius / 2).abs();
    return area;
  }

  // ─── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isReady =
        _boundaryPoints.length >= 4 &&
        _centerPoint != null &&
        !_isGeocodingCenter;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: const Text(
          'Land Survey',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_boundaryPoints.isNotEmpty)
            IconButton(
              icon: const Icon(LucideIcons.rotateCcw, size: 20),
              tooltip: 'Reset',
              onPressed: _resetAll,
            ),
          if (isReady)
            TextButton(
              onPressed: _confirmSurvey,
              child: const Text(
                'Done',
                style: TextStyle(
                  color: AppTheme.accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: AppTheme.pageHorizontalPadding,
          right: AppTheme.pageHorizontalPadding,
          bottom: MediaQuery.of(context).padding.bottom + 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Instructions
            _buildInstructionsCard(theme, isDark),
            const SizedBox(height: 16),

            // Error
            if (_error != null) ...[
              _buildErrorCard(theme),
              const SizedBox(height: 16),
            ],

            // Step 1: Boundary corners
            _buildSectionHeader(
              theme,
              '1',
              'Mark Boundary Corners',
              '${_boundaryPoints.length} points captured',
            ),
            const SizedBox(height: 8),

            // Captured points list
            if (_boundaryPoints.isNotEmpty) ...[
              _buildPointsList(theme, isDark),
              const SizedBox(height: 8),
            ],

            // Capture corner button
            if (_centerPoint == null)
              _buildCaptureButton(
                theme: theme,
                isDark: isDark,
                label: 'Mark Corner ${_boundaryPoints.length + 1}',
                subtitle: _boundaryPoints.isEmpty
                    ? 'Stand at the first corner of your property'
                    : 'Walk to the next corner',
                icon: LucideIcons.mapPin,
                onTap: _captureCorner,
                enabled: !_isCapturing,
              ),

            const SizedBox(height: 8),

            // Undo last point
            if (_boundaryPoints.isNotEmpty && _centerPoint == null)
              Center(
                child: TextButton.icon(
                  onPressed: _removeLastPoint,
                  icon: Icon(
                    LucideIcons.undo,
                    size: 16,
                    color: theme.colorScheme.error,
                  ),
                  label: Text(
                    'Undo Last Point',
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),

            // Land shape diagram
            if (_boundaryPoints.length >= 4) ...[
              const SizedBox(height: 16),
              _buildLandDiagram(theme, isDark),
            ],

            // Area display
            if (_areaSqm != null) ...[
              const SizedBox(height: 12),
              _buildAreaDisplay(theme, isDark),
            ],

            // Auto-detected location card
            if (_boundaryPoints.length >= 4) ...[
              const SizedBox(height: 16),
              if (_isGeocodingCenter)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.elevationColor(context, 1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppTheme.accent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.accent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Detecting location from survey points...',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else if (_centerPoint != null)
                _buildGeocodedLocationCard(theme, isDark),
            ],

            // Confirm
            if (isReady) ...[
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _confirmSurvey,
                  icon: const Icon(LucideIcons.check, size: 18),
                  label: const Text('Confirm Survey'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionsCard(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(LucideIcons.info, size: 16, color: AppTheme.accent),
              SizedBox(width: 8),
              Text(
                'How it works',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '1. Walk to each corner of the land and tap "Mark Corner"\n'
            '2. Mark at least 4 corners to define the boundary\n'
            '3. The boundary auto-closes, area is calculated, and\n'
            '   location is auto-detected from the survey points\n'
            '4. Tap "Confirm Survey" when done',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.shieldAlert,
                  size: 14,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Fraud prevention: Only GPS-verified locations can be listed. '
                    'Misrepresenting location results in 10 PCT deduction per violation.',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.error.withValues(alpha: 0.9),
                      height: 1.4,
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

  Widget _buildErrorCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.alertTriangle,
            size: 16,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: TextStyle(fontSize: 13, color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    ThemeData theme,
    String num,
    String title,
    String badge,
  ) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: AppTheme.accent,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            num,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            badge,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPointsList(ThemeData theme, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.elevationColor(context, 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: List.generate(_boundaryPoints.length, (i) {
          final p = _boundaryPoints[i];
          return ListTile(
            dense: true,
            leading: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '${i + 1}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.accent,
                ),
              ),
            ),
            title: Text(
              'Corner ${i + 1}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${p['lat']!.toStringAsFixed(6)}, ${p['lng']!.toStringAsFixed(6)}',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                fontFamily: 'monospace',
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (i < _pointAccuracies.length)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _pointAccuracies[i] <= 5
                          ? Colors.green.withValues(alpha: 0.15)
                          : _pointAccuracies[i] <= 10
                          ? Colors.orange.withValues(alpha: 0.12)
                          : Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '±${_pointAccuracies[i].toStringAsFixed(1)}m',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _pointAccuracies[i] <= 5
                            ? Colors.green.shade600
                            : _pointAccuracies[i] <= 10
                            ? Colors.orange.shade600
                            : Colors.red.shade500,
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                Icon(
                  LucideIcons.checkCircle,
                  size: 16,
                  color: Colors.green.shade400,
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCaptureButton({
    required ThemeData theme,
    required bool isDark,
    required String label,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    required bool enabled,
    bool isCenter = false,
  }) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final scale = 1.0 + (_pulseController.value * 0.03);
        return Transform.scale(scale: _isCapturing ? 1.0 : scale, child: child);
      },
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isCenter
                  ? [Colors.orange.shade400, Colors.deepOrange.shade500]
                  : [AppTheme.accent, AppTheme.accent.withValues(alpha: 0.8)],
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: (isCenter ? Colors.orange : AppTheme.accent).withValues(
                  alpha: 0.3,
                ),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: _isCapturing
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Averaging GPS signals...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$_sampleCount samples',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 12,
                          ),
                        ),
                        if (_liveBestAccuracy != null) ...[
                          Text(
                            '  ·  ',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            'best: ±${_liveBestAccuracy!.toStringAsFixed(1)}m',
                            style: TextStyle(
                              color: _liveBestAccuracy! <= 5
                                  ? Colors.greenAccent
                                  : _liveBestAccuracy! <= 10
                                  ? Colors.yellowAccent
                                  : Colors.white.withValues(alpha: 0.8),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(icon, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      LucideIcons.target,
                      color: Colors.white.withValues(alpha: 0.6),
                      size: 20,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildLandDiagram(ThemeData theme, bool isDark) {
    // Calculate center of boundary points for satellite URL
    double cLat = 0, cLng = 0;
    for (final p in _boundaryPoints) {
      cLat += p['lat']!;
      cLng += p['lng']!;
    }
    cLat /= _boundaryPoints.length;
    cLng /= _boundaryPoints.length;

    // Build satellite tile URL with polygon drawn by Google
    final pathPoints = _boundaryPoints
        .map(
          (p) =>
              '${p['lat']!.toStringAsFixed(6)},${p['lng']!.toStringAsFixed(6)}',
        )
        .join('|');
    final first = _boundaryPoints.first;
    final closedPath =
        '$pathPoints|${first['lat']!.toStringAsFixed(6)},${first['lng']!.toStringAsFixed(6)}';
    final centerStr = '${cLat.toStringAsFixed(6)},${cLng.toStringAsFixed(6)}';
    final satelliteUrl =
        'https://maps.googleapis.com/maps/api/staticmap'
        '?center=$centerStr'
        '&zoom=18'
        '&size=600x400'
        '&scale=2'
        '&maptype=satellite'
        '&path=color:0xFFFF6B35|weight:3|fillcolor:0x40FF6B35|$closedPath'
        '&markers=size:small|color:red|$centerStr'
        '&key=${Env.googleMapsApiKey}';

    // Neighborhood (zoomed out) URL
    final neighborhoodUrl =
        'https://maps.googleapis.com/maps/api/staticmap'
        '?center=$centerStr'
        '&zoom=15'
        '&size=600x400'
        '&scale=2'
        '&maptype=satellite'
        '&markers=color:red|label:P|$centerStr'
        '&key=${Env.googleMapsApiKey}';

    // Road-map URL with boundary polygon
    final mapUrl =
        'https://maps.googleapis.com/maps/api/staticmap'
        '?center=$centerStr'
        '&zoom=16'
        '&size=600x400'
        '&scale=2'
        '&maptype=roadmap'
        '&path=color:0xFFFF6B35|weight:3|fillcolor:0x30FF6B35|$closedPath'
        '&markers=size:small|color:red|$centerStr'
        '&key=${Env.googleMapsApiKey}';

    // Google Maps URL for opening externally
    final zoomLevel = _aerialViewMode == 2 ? 15 : 18;
    final googleMapsUrl =
        'https://www.google.com/maps/@$centerStr,${zoomLevel}z/data=!3m1!1e1';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // View mode toggle
        Row(
          children: [
            _aerialChip(theme, 0, 'Aerial', LucideIcons.satellite),
            const SizedBox(width: 8),
            _aerialChip(theme, 1, 'Map', LucideIcons.map),
            const SizedBox(width: 8),
            _aerialChip(theme, 2, 'Area', LucideIcons.maximize),
          ],
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => launchUrl(
            Uri.parse(googleMapsUrl),
            mode: LaunchMode.externalApplication,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 220,
              width: double.infinity,
              child: Stack(
                children: [
                  // Zoomable satellite / map image
                  InteractiveViewer(
                    minScale: 1.0,
                    maxScale: 4.0,
                    child: Image.network(
                      _aerialViewMode == 0
                          ? satelliteUrl
                          : _aerialViewMode == 1
                          ? mapUrl
                          : neighborhoodUrl,
                      width: double.infinity,
                      height: 220,
                      fit: BoxFit.cover,
                      loadingBuilder: (_, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          color: AppTheme.elevationColor(context, 1),
                          child: Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              value: progress.expectedTotalBytes != null
                                  ? progress.cumulativeBytesLoaded /
                                        progress.expectedTotalBytes!
                                  : null,
                              color: AppTheme.accent,
                            ),
                          ),
                        );
                      },
                      errorBuilder: (_, _, _) => Container(
                        color: AppTheme.elevationColor(context, 1),
                        child: CustomPaint(
                          painter: _LandShapePainter(
                            points: _boundaryPoints,
                            centerPoint: _centerPoint,
                            color: AppTheme.accent,
                            isDark: isDark,
                          ),
                          child: Center(
                            child: Text(
                              'Property Shape',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Google Earth badge + open hint
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            LucideIcons.satellite,
                            size: 10,
                            color: Colors.white70,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Tap to open in Google Maps',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Pinch to zoom hint
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.zoomIn,
                            size: 10,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'Pinch to zoom',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
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
      ],
    );
  }

  Widget _buildAreaDisplay(ThemeData theme, bool isDark) {
    final sqft = _areaSqm! * 10.7639;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.ruler, size: 16, color: Colors.green.shade600),
              const SizedBox(width: 8),
              Text(
                'Calculated Area',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.green.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _areaChip(theme, '${_areaSqm!.toStringAsFixed(0)} m\u00B2'),
              const SizedBox(width: 10),
              Text(
                '\u00B7',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade600,
                ),
              ),
              const SizedBox(width: 10),
              _areaChip(theme, '${sqft.toStringAsFixed(0)} ft\u00B2'),
            ],
          ),
          if (_currentAccuracy != null) ...[
            const SizedBox(height: 8),
            Text(
              'GPS accuracy: \u00B1${_currentAccuracy!.toStringAsFixed(1)}m',
              style: TextStyle(
                fontSize: 11,
                color: _currentAccuracy! <= 5
                    ? Colors.green.shade600
                    : _currentAccuracy! <= 15
                    ? Colors.orange.shade600
                    : theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _areaChip(ThemeData theme, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.green.shade700,
        ),
      ),
    );
  }

  /// Chip for switching between Property / Neighborhood aerial views.
  Widget _aerialChip(ThemeData theme, int mode, String label, IconData icon) {
    final selected = _aerialViewMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _aerialViewMode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.accent.withValues(alpha: 0.15)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppTheme.accent
                : theme.colorScheme.onSurface.withValues(alpha: 0.15),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: selected
                  ? AppTheme.accent
                  : theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected
                    ? AppTheme.accent
                    : theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeocodedLocationCard(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.elevationColor(context, 1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.checkCircle,
                size: 16,
                color: Colors.green.shade500,
              ),
              const SizedBox(width: 8),
              Text(
                'Auto-Detected from Survey',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.green.shade500,
                ),
              ),
              const Spacer(),
              Icon(
                LucideIcons.lock,
                size: 14,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_geocodedAddress != null && _geocodedAddress!.isNotEmpty)
            _locationRow(theme, 'Address', _geocodedAddress!),
          if (_geocodedSubLocality != null && _geocodedSubLocality!.isNotEmpty)
            _locationRow(theme, 'Area', _geocodedSubLocality!),
          if (_geocodedCity != null && _geocodedCity!.isNotEmpty)
            _locationRow(theme, 'City', _geocodedCity!),
          if (_geocodedState != null && _geocodedState!.isNotEmpty)
            _locationRow(theme, 'State', _geocodedState!),
          if (_geocodedCountry != null && _geocodedCountry!.isNotEmpty)
            _locationRow(theme, 'Country', _geocodedCountry!),
          const SizedBox(height: 6),
          Text(
            'Center: ${_centerPoint!['lat']!.toStringAsFixed(6)}, '
            '${_centerPoint!['lng']!.toStringAsFixed(6)}',
            style: TextStyle(
              fontSize: 10,
              fontFamily: 'monospace',
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _locationRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Polygon painter ────────────────────────────────────────────────────

class _LandShapePainter extends CustomPainter {
  final List<Map<String, double>> points;
  final Map<String, double>? centerPoint;
  final Color color;
  final bool isDark;

  _LandShapePainter({
    required this.points,
    this.centerPoint,
    required this.color,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    // Find bounds
    double minLat = double.infinity, maxLat = -double.infinity;
    double minLng = double.infinity, maxLng = -double.infinity;
    for (final p in points) {
      minLat = min(minLat, p['lat']!);
      maxLat = max(maxLat, p['lat']!);
      minLng = min(minLng, p['lng']!);
      maxLng = max(maxLng, p['lng']!);
    }
    if (centerPoint != null) {
      minLat = min(minLat, centerPoint!['lat']!);
      maxLat = max(maxLat, centerPoint!['lat']!);
      minLng = min(minLng, centerPoint!['lng']!);
      maxLng = max(maxLng, centerPoint!['lng']!);
    }

    final latRange = maxLat - minLat;
    final lngRange = maxLng - minLng;
    final pad = 30.0;
    final drawW = size.width - pad * 2;
    final drawH = size.height - pad * 2;

    Offset toScreen(double lat, double lng) {
      final x = lngRange == 0 ? drawW / 2 : ((lng - minLng) / lngRange) * drawW;
      // Invert Y because lat increases upward
      final y = latRange == 0 ? drawH / 2 : ((maxLat - lat) / latRange) * drawH;
      return Offset(pad + x, pad + y);
    }

    // Fill polygon
    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;
    final fillPath = Path();
    final firstPt = toScreen(points[0]['lat']!, points[0]['lng']!);
    fillPath.moveTo(firstPt.dx, firstPt.dy);
    for (int i = 1; i < points.length; i++) {
      final pt = toScreen(points[i]['lat']!, points[i]['lng']!);
      fillPath.lineTo(pt.dx, pt.dy);
    }
    fillPath.close();
    canvas.drawPath(fillPath, fillPaint);

    // Stroke polygon
    final strokePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(fillPath, strokePaint);

    // Draw corner dots
    final dotPaint = Paint()..color = color;
    for (int i = 0; i < points.length; i++) {
      final pt = toScreen(points[i]['lat']!, points[i]['lng']!);
      canvas.drawCircle(pt, 5, dotPaint);
      // Label
      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            color: isDark ? Colors.white60 : Colors.black54,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pt + const Offset(8, -6));
    }

    // Center point
    if (centerPoint != null) {
      final cp = toScreen(centerPoint!['lat']!, centerPoint!['lng']!);
      final centerDot = Paint()..color = Colors.orange;
      canvas.drawCircle(cp, 6, centerDot);
      final ring = Paint()
        ..color = Colors.orange.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(cp, 10, ring);
    }
  }

  @override
  bool shouldRepaint(covariant _LandShapePainter old) =>
      points.length != old.points.length || centerPoint != old.centerPoint;
}
