import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'package:diaspora_nearby/config/env.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

/// Static cache for downloaded map image bytes, keyed by "lat,lng".
/// Survives widget rebuilds, message ID changes, and key remounts.
final Map<String, Uint8List> _mapImageCache = {};

class LocationMessageContent extends StatefulWidget {
  final Message message;
  final bool isOwn;

  const LocationMessageContent({
    super.key,
    required this.message,
    required this.isOwn,
  });

  @override
  State<LocationMessageContent> createState() => _LocationMessageContentState();
}

class _LocationMessageContentState extends State<LocationMessageContent>
    with AutomaticKeepAliveClientMixin {
  late final double _lat;
  late final double _lng;
  late final String _cacheKey;
  Uint8List? _imageBytes;
  bool _loading = true;
  bool _error = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _lat = widget.message.location?.lat ?? 0.0;
    _lng = widget.message.location?.lng ?? 0.0;
    _cacheKey = '${_lat.toStringAsFixed(6)},${_lng.toStringAsFixed(6)}';

    // Check static cache first
    if (_mapImageCache.containsKey(_cacheKey)) {
      _imageBytes = _mapImageCache[_cacheKey];
      _loading = false;
    } else {
      _fetchMapImage();
    }
  }

  Future<void> _fetchMapImage() async {
    final apiKey = Env.googleMapsApiKey;
    final mapUrl =
        'https://maps.googleapis.com/maps/api/staticmap?'
        'center=$_lat,$_lng&'
        'zoom=15&'
        'size=600x300&'
        'scale=2&'
        'maptype=roadmap&'
        'markers=color:red%7C$_lat,$_lng&'
        'key=$apiKey';

    try {
      final response = await http.get(Uri.parse(mapUrl));
      if (response.statusCode == 200 &&
          response.headers['content-type']?.contains('image') == true) {
        final bytes = response.bodyBytes;
        // Store in static cache
        _mapImageCache[_cacheKey] = bytes;
        if (mounted) {
          setState(() {
            _imageBytes = bytes;
            _loading = false;
          });
        }
      } else {
        debugPrint(
          '[LocationMsg] Bad response: ${response.statusCode} '
          'content-type: ${response.headers['content-type']}',
        );
        if (mounted)
          setState(() {
            _loading = false;
            _error = true;
          });
      }
    } catch (e) {
      debugPrint('[LocationMsg] Fetch error: $e');
      if (mounted)
        setState(() {
          _loading = false;
          _error = true;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final address = widget.message.location?.address ?? '';

    return GestureDetector(
      onTap: () => _openInMaps(_lat, _lng),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Map preview
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: SizedBox(
              width: double.infinity,
              height: 160,
              child: _buildMapView(theme, isDark),
            ),
          ),

          // Location info bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  LucideIcons.mapPin,
                  size: 14,
                  color: widget.isOwn
                      ? Colors.white.withValues(alpha: 0.8)
                      : AppTheme.accent,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    address.isNotEmpty
                        ? address
                        : widget.message.content.isNotEmpty
                        ? widget.message.content
                        : '${_lat.toStringAsFixed(4)}, ${_lng.toStringAsFixed(4)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: widget.isOwn
                          ? Colors.white.withValues(alpha: 0.9)
                          : theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  LucideIcons.externalLink,
                  size: 12,
                  color: widget.isOwn
                      ? Colors.white.withValues(alpha: 0.5)
                      : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapView(ThemeData theme, bool isDark) {
    if (_imageBytes != null) {
      return Image.memory(
        _imageBytes!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _buildMapPlaceholder(theme, isDark),
      );
    }
    if (_error) {
      return _buildMapPlaceholder(theme, isDark);
    }
    // Loading state
    return _buildMapPlaceholder(theme, isDark, isLoading: true);
  }

  /// Styled fallback when static map image fails to load
  Widget _buildMapPlaceholder(
    ThemeData theme,
    bool isDark, {
    bool isLoading = false,
  }) {
    return Container(
      width: double.infinity,
      height: 160,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A2E1A) : const Color(0xFFE8F0E8),
      ),
      child: Stack(
        children: [
          // Grid lines to simulate map
          CustomPaint(
            size: const Size(double.infinity, 160),
            painter: _MapGridPainter(isDark: isDark),
          ),

          // Center pin
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade600,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    LucideIcons.mapPin,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
                Container(
                  width: 8,
                  height: 4,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),

          // Loading indicator
          if (isLoading)
            Positioned(
              bottom: 8,
              right: 8,
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: isDark ? Colors.white38 : Colors.black26,
                ),
              ),
            ),

          // Coordinates label
          Positioned(
            bottom: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${_lat.toStringAsFixed(4)}, ${_lng.toStringAsFixed(4)}',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ),
          ),

          // "Tap to open" hint
          if (!isLoading)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.navigation,
                      size: 10,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Open in Maps',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openInMaps(double lat, double lng) async {
    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      debugPrint('Could not launch Maps');
    }
  }
}

/// Custom painter that draws subtle grid lines to simulate a map background
class _MapGridPainter extends CustomPainter {
  final bool isDark;

  _MapGridPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.black.withValues(alpha: 0.06)
      ..strokeWidth = 0.5;

    const spacing = 20.0;
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    final centerPaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.1)
          : Colors.black.withValues(alpha: 0.08)
      ..strokeWidth = 1.0;

    final cx = size.width / 2;
    final cy = size.height / 2;
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), centerPaint);
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), centerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
