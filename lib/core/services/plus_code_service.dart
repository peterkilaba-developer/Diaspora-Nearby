/// Service for validating, encoding, and decoding Google Plus Codes (Open Location Code).
/// Open Location Code is a location encoding system for encoding latitude/longitude into
/// short alphanumeric strings (e.g., "8FVC9G8F+6W" or "9G8F+6W, Nairobi").
class PlusCodeService {
  static const String _codeAlphabet = '23456789CFGHJMPQRVWX';
  static const String _separator = '+';
  static const int _separatorPosition = 8;

  /// Returns true if the string is a valid Plus Code format.
  static bool isValidPlusCode(String code) {
    final clean = code.trim().toUpperCase();
    if (!clean.contains(_separator)) return false;

    // Split by separator
    final parts = clean.split(_separator);
    if (parts.length != 2) return false;

    final head = parts[0];
    final tail = parts[1];

    // Head length must be even and <= 8
    if (head.isEmpty ||
        head.length > _separatorPosition ||
        head.length % 2 != 0) {
      return false;
    }

    // Check valid characters
    for (int i = 0; i < head.length; i++) {
      final char = head[i];
      if (char != '0' && !_codeAlphabet.contains(char)) {
        return false;
      }
    }

    for (int i = 0; i < tail.length; i++) {
      final char = tail[i];
      if (!_codeAlphabet.contains(char)) {
        return false;
      }
    }

    return true;
  }

  /// Encodes a latitude and longitude into a full Plus Code (10 characters + '+').
  static String encode(
    double latitude,
    double longitude, {
    int codeLength = 10,
  }) {
    double lat = latitude.clamp(-90.0, 90.0);
    double lng = longitude;

    // Normalize longitude to [-180, 180)
    while (lng < -180.0) {
      lng += 360.0;
    }
    while (lng >= 180.0) {
      lng -= 360.0;
    }

    // Adjust latitude if at max edge
    if (lat == 90.0) {
      lat = 89.9999999;
    }

    // Shift to positive scale: lat -> [0, 180], lng -> [0, 360]
    double latVal = lat + 90.0;
    double lngVal = lng + 180.0;

    StringBuffer code = StringBuffer();

    // Compute pair digits
    double latResolution = 20.0;
    double lngResolution = 20.0;

    for (int i = 0; i < 5; i++) {
      int latIdx = (latVal / latResolution).floor();
      int lngIdx = (lngVal / lngResolution).floor();

      latVal -= latIdx * latResolution;
      lngVal -= lngIdx * lngResolution;

      code.write(_codeAlphabet[latIdx.clamp(0, 19)]);
      code.write(_codeAlphabet[lngIdx.clamp(0, 19)]);

      if (code.length == _separatorPosition) {
        code.write(_separator);
      }

      latResolution /= 20.0;
      lngResolution /= 20.0;
    }

    if (!code.toString().contains(_separator)) {
      code.write(_separator);
    }

    return code.toString();
  }

  /// Decodes a full Plus Code into [lat, lng] coordinates.
  /// Returns null if the code is invalid or a short code without reference location.
  static Map<String, double>? decode(String code) {
    if (!isValidPlusCode(code)) return null;

    final clean = code.trim().toUpperCase();
    final parts = clean.split(_separator);
    final head = parts[0];
    final tail = parts[1];

    final fullString = head + tail;
    if (fullString.length < 2) return null;

    double latVal = 0.0;
    double lngVal = 0.0;

    double latResolution = 20.0;
    double lngResolution = 20.0;

    for (int i = 0; i < fullString.length; i += 2) {
      final latChar = fullString[i];
      final lngChar = (i + 1 < fullString.length) ? fullString[i + 1] : '2';

      int latIdx = _codeAlphabet.indexOf(latChar);
      int lngIdx = _codeAlphabet.indexOf(lngChar);

      if (latIdx == -1) latIdx = 0;
      if (lngIdx == -1) lngIdx = 0;

      latVal += latIdx * latResolution;
      lngVal += lngIdx * lngResolution;

      if (i + 2 < fullString.length) {
        latResolution /= 20.0;
        lngResolution /= 20.0;
      }
    }

    // Adjust back to [-90, 90] and [-180, 180] (center of the bounding box)
    double lat = latVal - 90.0 + (latResolution / 2.0);
    double lng = lngVal - 180.0 + (lngResolution / 2.0);

    return {'latitude': lat.clamp(-90.0, 90.0), 'longitude': lng};
  }

  /// Formats a raw location or Plus Code for UI display.
  static String formatPlusCode(String code) {
    if (code.isEmpty) return '';
    final clean = code.trim().toUpperCase();
    if (isValidPlusCode(clean)) {
      return clean;
    }
    return code;
  }
}
