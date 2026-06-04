import 'package:phone_numbers_parser/phone_numbers_parser.dart';

/// Result of attempting to normalize a phone number to E.164.
class NormalizedPhone {
  /// E.164 form including leading `+` (e.g. `+255712345678`). Null if the
  /// input could not be parsed at all.
  final String? e164;

  /// True if the parsed number is structurally valid for the inferred country
  /// (correct national-significant-number length, valid prefix). E.164 may be
  /// non-null while [isValid] is false when the user is mid-typing.
  final bool isValid;

  const NormalizedPhone({required this.e164, required this.isValid});
}

/// Normalize a user-entered phone number to E.164 using libphonenumber metadata.
///
/// Handles:
///   - leading national trunk prefix (`0712345678` in TZ → `+255712345678`)
///   - spaces, dashes, parentheses
///   - users who type the country code anyway (`+255712345678` or
///     `255712345678`) — those pass through unchanged
///   - Italian fixed-line numbers where the leading 0 is part of the NSN
///     (the library keeps it correctly)
///
/// [isoCountryCode] is the uppercase ISO 3166-1 alpha-2 of the country picker
/// (e.g. `TZ`, `US`). Used as the parsing hint when the user did not type a
/// `+` country code prefix.
NormalizedPhone normalizePhone({
  required String rawInput,
  required String isoCountryCode,
}) {
  final cleaned = rawInput.trim();
  if (cleaned.isEmpty) {
    return const NormalizedPhone(e164: null, isValid: false);
  }

  IsoCode? iso;
  try {
    iso = IsoCode.values.firstWhere(
      (c) => c.name.toUpperCase() == isoCountryCode.toUpperCase(),
    );
  } catch (_) {
    iso = null;
  }

  try {
    final parsed = iso == null
        ? PhoneNumber.parse(cleaned)
        : PhoneNumber.parse(cleaned, callerCountry: iso);
    return NormalizedPhone(
      e164: parsed.international,
      isValid: parsed.isValid(),
    );
  } catch (_) {
    return const NormalizedPhone(e164: null, isValid: false);
  }
}
