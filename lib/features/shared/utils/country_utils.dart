/// Utilities for country-related operations
class CountryUtils {
  /// Returns the emoji flag for a given ISO 3166-1 alpha-2 country code.
  /// Falls back to a white flag if the code is null or invalid.
  static String getCountryFlag(String? countryCode) {
    if (countryCode == null) return '🏳️';
    String country = countryCode.toUpperCase();
    if (country.length != 2) return '🏳️';

    // Regional Indicator Symbol Letters (A = 0x1F1E6, B = 0x1F1E7, etc.)
    int flagOffset = 0x1F1E6;
    int asciiOffset = 0x41; // 'A'

    int firstChar = country.codeUnitAt(0) - asciiOffset + flagOffset;
    int secondChar = country.codeUnitAt(1) - asciiOffset + flagOffset;

    return String.fromCharCode(firstChar) + String.fromCharCode(secondChar);
  }
}
