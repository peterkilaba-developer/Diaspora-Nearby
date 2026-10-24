import 'package:diaspora_nearby/features/marketplace/utils/exchange_rate_service.dart';

/// Utility for mapping country codes to local currencies and converting DSP
/// to local currency equivalents.
///
/// Uses live exchange rates from [ExchangeRateService] when available,
/// falling back to hardcoded static rates.
///
/// The DSP→USD base rate is a static placeholder during the pre-TGE phase.
/// Post-TGE, this should be replaced by the live `ValuationService.calculateInternalPrice`.
class CurrencyHelper {
  CurrencyHelper._();

  // ─── Pre-TGE static base rate (1 DSP ≈ this many USD) ──────────────────
  // This will eventually be sourced from the ValuationService.
  static const double _baseDspToUsd = 0.001;

  /// Complete map of ISO-3166 country code → (currency code, symbol, rough USD rate).
  /// The USD rate represents how many units of local currency equal 1 USD.
  /// Covers all 200+ countries in our countries.dart list.
  static final Map<String, _CurrencyInfo> _currencyMap = {
    // ─── AFRICA ───────────────────────────────────────────────────────────
    'DZ': const _CurrencyInfo('DZD', 'DA', 135), // Algeria
    'AO': const _CurrencyInfo('AOA', 'Kz', 830), // Angola
    'BJ': const _CurrencyInfo('XOF', 'CFA', 610), // Benin (WAEMU)
    'BW': const _CurrencyInfo('BWP', 'P', 13.5), // Botswana
    'BF': const _CurrencyInfo('XOF', 'CFA', 610), // Burkina Faso (WAEMU)
    'BI': const _CurrencyInfo('BIF', 'FBu', 2850), // Burundi
    'CM': const _CurrencyInfo('XAF', 'FCFA', 610), // Cameroon (CEMAC)
    'CV': const _CurrencyInfo('CVE', 'Esc', 102), // Cape Verde
    'CF': const _CurrencyInfo(
      'XAF',
      'FCFA',
      610,
    ), // Central African Republic (CEMAC)
    'TD': const _CurrencyInfo('XAF', 'FCFA', 610), // Chad (CEMAC)
    'KM': const _CurrencyInfo('KMF', 'CF', 455), // Comoros
    'CG': const _CurrencyInfo('XAF', 'FCFA', 610), // Congo (CEMAC)
    'CD': const _CurrencyInfo('CDF', 'FC', 2800), // Congo DRC
    'CI': const _CurrencyInfo('XOF', 'CFA', 610), // Côte d'Ivoire (WAEMU)
    'DJ': const _CurrencyInfo('DJF', 'Fdj', 178), // Djibouti
    'EG': const _CurrencyInfo('EGP', 'E£', 49), // Egypt
    'GQ': const _CurrencyInfo('XAF', 'FCFA', 610), // Equatorial Guinea (CEMAC)
    'ER': const _CurrencyInfo('ERN', 'Nfk', 15), // Eritrea
    'ET': const _CurrencyInfo('ETB', 'Br', 56), // Ethiopia
    'GA': const _CurrencyInfo('XAF', 'FCFA', 610), // Gabon (CEMAC)
    'GM': const _CurrencyInfo('GMD', 'D', 67), // Gambia
    'GH': const _CurrencyInfo('GHS', 'GH₵', 15), // Ghana
    'GN': const _CurrencyInfo('GNF', 'FG', 8600), // Guinea
    'GW': const _CurrencyInfo('XOF', 'CFA', 610), // Guinea-Bissau (WAEMU)
    'KE': const _CurrencyInfo('KES', 'KSh', 155), // Kenya
    'LS': const _CurrencyInfo('LSL', 'L', 18), // Lesotho
    'LR': const _CurrencyInfo('LRD', 'L\$', 192), // Liberia
    'LY': const _CurrencyInfo('LYD', 'LD', 4.8), // Libya
    'MG': const _CurrencyInfo('MGA', 'Ar', 4500), // Madagascar
    'MW': const _CurrencyInfo('MWK', 'MK', 1700), // Malawi
    'ML': const _CurrencyInfo('XOF', 'CFA', 610), // Mali (WAEMU)
    'MR': const _CurrencyInfo('MRU', 'UM', 39), // Mauritania
    'MU': const _CurrencyInfo('MUR', '₨', 45), // Mauritius
    'MA': const _CurrencyInfo('MAD', 'MAD', 10), // Morocco
    'MZ': const _CurrencyInfo('MZN', 'MT', 64), // Mozambique
    'NA': const _CurrencyInfo('NAD', 'N\$', 18), // Namibia
    'NE': const _CurrencyInfo('XOF', 'CFA', 610), // Niger (WAEMU)
    'NG': const _CurrencyInfo('NGN', '₦', 1500), // Nigeria
    'RW': const _CurrencyInfo('RWF', 'RF', 1300), // Rwanda
    'ST': const _CurrencyInfo('STN', 'Db', 23), // São Tomé and Príncipe
    'SN': const _CurrencyInfo('XOF', 'CFA', 610), // Senegal (WAEMU)
    'SC': const _CurrencyInfo('SCR', '₨', 14), // Seychelles
    'SL': const _CurrencyInfo('SLE', 'Le', 22), // Sierra Leone
    'SO': const _CurrencyInfo('SOS', 'Sh', 570), // Somalia
    'ZA': const _CurrencyInfo('ZAR', 'R', 18), // South Africa
    'SS': const _CurrencyInfo('SSP', '£', 1300), // South Sudan
    'SD': const _CurrencyInfo('SDG', 'LS', 600), // Sudan
    'SZ': const _CurrencyInfo('SZL', 'E', 18), // Eswatini (Swaziland)
    'TZ': const _CurrencyInfo('TZS', 'TSh', 2700), // Tanzania
    'TG': const _CurrencyInfo('XOF', 'CFA', 610), // Togo (WAEMU)
    'TN': const _CurrencyInfo('TND', 'DT', 3.1), // Tunisia
    'UG': const _CurrencyInfo('UGX', 'USh', 3800), // Uganda
    'ZM': const _CurrencyInfo('ZMW', 'ZK', 26), // Zambia
    'ZW': const _CurrencyInfo('ZWL', 'Z\$', 13500), // Zimbabwe
    // ─── CARIBBEAN ────────────────────────────────────────────────────────
    'AI': const _CurrencyInfo('XCD', 'EC\$', 2.70), // Anguilla (OECS)
    'AG': const _CurrencyInfo(
      'XCD',
      'EC\$',
      2.70,
    ), // Antigua and Barbuda (OECS)
    'AW': const _CurrencyInfo('AWG', 'ƒ', 1.79), // Aruba
    'BS': const _CurrencyInfo('BSD', 'B\$', 1.0), // Bahamas
    'BB': const _CurrencyInfo('BBD', 'Bds\$', 2.0), // Barbados
    'BZ': const _CurrencyInfo('BZD', 'BZ\$', 2.0), // Belize
    'BM': const _CurrencyInfo('BMD', '\$', 1.0), // Bermuda
    'KY': const _CurrencyInfo('KYD', 'CI\$', 0.82), // Cayman Islands
    'CU': const _CurrencyInfo('CUP', '\$', 24), // Cuba
    'DM': const _CurrencyInfo('XCD', 'EC\$', 2.70), // Dominica (OECS)
    'DO': const _CurrencyInfo('DOP', 'RD\$', 57), // Dominican Republic
    'GD': const _CurrencyInfo('XCD', 'EC\$', 2.70), // Grenada (OECS)
    'HT': const _CurrencyInfo('HTG', 'G', 132), // Haiti
    'JM': const _CurrencyInfo('JMD', 'J\$', 155), // Jamaica
    'MS': const _CurrencyInfo('XCD', 'EC\$', 2.70), // Montserrat (OECS)
    'PR': const _CurrencyInfo('USD', '\$', 1.0), // Puerto Rico
    'KN': const _CurrencyInfo('XCD', 'EC\$', 2.70), // Saint Kitts and Nevis
    'LC': const _CurrencyInfo('XCD', 'EC\$', 2.70), // Saint Lucia
    'VC': const _CurrencyInfo('XCD', 'EC\$', 2.70), // Saint Vincent
    'TT': const _CurrencyInfo('TTD', 'TT\$', 6.8), // Trinidad and Tobago
    'VI': const _CurrencyInfo('USD', '\$', 1.0), // U.S. Virgin Islands
    // ─── NORTH AMERICA ────────────────────────────────────────────────────
    'CA': const _CurrencyInfo('CAD', 'CA\$', 1.37), // Canada
    'CR': const _CurrencyInfo('CRC', '₡', 510), // Costa Rica
    'SV': const _CurrencyInfo('USD', '\$', 1.0), // El Salvador (dollarised)
    'GT': const _CurrencyInfo('GTQ', 'Q', 7.8), // Guatemala
    'HN': const _CurrencyInfo('HNL', 'L', 25), // Honduras
    'MX': const _CurrencyInfo('MXN', 'MX\$', 17), // Mexico
    'NI': const _CurrencyInfo('NIO', 'C\$', 36.5), // Nicaragua
    'PA': const _CurrencyInfo('PAB', 'B/', 1.0), // Panama (dollarised)
    'US': const _CurrencyInfo('USD', '\$', 1), // United States
    // ─── SOUTH AMERICA ────────────────────────────────────────────────────
    'AR': const _CurrencyInfo('ARS', 'AR\$', 900), // Argentina
    'BO': const _CurrencyInfo('BOB', 'Bs', 6.9), // Bolivia
    'BR': const _CurrencyInfo('BRL', 'R\$', 5.0), // Brazil
    'CL': const _CurrencyInfo('CLP', 'CLP\$', 900), // Chile
    'CO': const _CurrencyInfo('COP', 'COL\$', 4000), // Colombia
    'EC': const _CurrencyInfo('USD', '\$', 1.0), // Ecuador (dollarised)
    'GY': const _CurrencyInfo('GYD', 'GY\$', 209), // Guyana
    'PY': const _CurrencyInfo('PYG', '₲', 7300), // Paraguay
    'PE': const _CurrencyInfo('PEN', 'S/', 3.7), // Peru
    'SR': const _CurrencyInfo('SRD', 'SRD', 36), // Suriname
    'UY': const _CurrencyInfo('UYU', '\$U', 40), // Uruguay
    'VE': const _CurrencyInfo('VES', 'Bs.D', 36), // Venezuela
    // ─── EUROPE ───────────────────────────────────────────────────────────
    'AL': const _CurrencyInfo('ALL', 'L', 95), // Albania
    'AD': const _CurrencyInfo('EUR', '€', 0.92), // Andorra
    'AT': const _CurrencyInfo('EUR', '€', 0.92), // Austria
    'BY': const _CurrencyInfo('BYN', 'Br', 3.3), // Belarus
    'BE': const _CurrencyInfo('EUR', '€', 0.92), // Belgium
    'BA': const _CurrencyInfo('BAM', 'KM', 1.8), // Bosnia and Herzegovina
    'BG': const _CurrencyInfo('BGN', 'лв', 1.8), // Bulgaria
    'HR': const _CurrencyInfo('EUR', '€', 0.92), // Croatia
    'CY': const _CurrencyInfo('EUR', '€', 0.92), // Cyprus
    'CZ': const _CurrencyInfo('CZK', 'Kč', 23), // Czechia
    'DK': const _CurrencyInfo('DKK', 'kr', 6.9), // Denmark
    'EE': const _CurrencyInfo('EUR', '€', 0.92), // Estonia
    'FI': const _CurrencyInfo('EUR', '€', 0.92), // Finland
    'FR': const _CurrencyInfo('EUR', '€', 0.92), // France
    'GE': const _CurrencyInfo('GEL', '₾', 2.7), // Georgia
    'DE': const _CurrencyInfo('EUR', '€', 0.92), // Germany
    'GR': const _CurrencyInfo('EUR', '€', 0.92), // Greece
    'HU': const _CurrencyInfo('HUF', 'Ft', 360), // Hungary
    'IS': const _CurrencyInfo('ISK', 'kr', 138), // Iceland
    'IE': const _CurrencyInfo('EUR', '€', 0.92), // Ireland
    'IT': const _CurrencyInfo('EUR', '€', 0.92), // Italy
    'LV': const _CurrencyInfo('EUR', '€', 0.92), // Latvia
    'LI': const _CurrencyInfo('CHF', 'CHF', 0.88), // Liechtenstein
    'LT': const _CurrencyInfo('EUR', '€', 0.92), // Lithuania
    'LU': const _CurrencyInfo('EUR', '€', 0.92), // Luxembourg
    'MK': const _CurrencyInfo('MKD', 'ден', 57), // North Macedonia
    'MT': const _CurrencyInfo('EUR', '€', 0.92), // Malta
    'MD': const _CurrencyInfo('MDL', 'L', 17.7), // Moldova
    'MC': const _CurrencyInfo('EUR', '€', 0.92), // Monaco
    'ME': const _CurrencyInfo('EUR', '€', 0.92), // Montenegro
    'NL': const _CurrencyInfo('EUR', '€', 0.92), // Netherlands
    'NO': const _CurrencyInfo('NOK', 'kr', 10.8), // Norway
    'PL': const _CurrencyInfo('PLN', 'zł', 4.0), // Poland
    'PT': const _CurrencyInfo('EUR', '€', 0.92), // Portugal
    'RO': const _CurrencyInfo('RON', 'lei', 4.6), // Romania
    'RU': const _CurrencyInfo('RUB', '₽', 92), // Russia
    'SM': const _CurrencyInfo('EUR', '€', 0.92), // San Marino
    'RS': const _CurrencyInfo('RSD', 'din', 108), // Serbia
    'SK': const _CurrencyInfo('EUR', '€', 0.92), // Slovakia
    'SI': const _CurrencyInfo('EUR', '€', 0.92), // Slovenia
    'ES': const _CurrencyInfo('EUR', '€', 0.92), // Spain
    'SE': const _CurrencyInfo('SEK', 'kr', 10.5), // Sweden
    'CH': const _CurrencyInfo('CHF', 'CHF', 0.88), // Switzerland
    'UA': const _CurrencyInfo('UAH', '₴', 41), // Ukraine
    'GB': const _CurrencyInfo('GBP', '£', 0.79), // United Kingdom
    'GB-ENG': const _CurrencyInfo('GBP', '£', 0.79), // England
    'GB-SCT': const _CurrencyInfo('GBP', '£', 0.79), // Scotland
    'GB-WLS': const _CurrencyInfo('GBP', '£', 0.79), // Wales
    'GB-NIR': const _CurrencyInfo('GBP', '£', 0.79), // Northern Ireland
    // ─── ASIA ─────────────────────────────────────────────────────────────
    'AF': const _CurrencyInfo('AFN', '؋', 70), // Afghanistan
    'AM': const _CurrencyInfo('AMD', '֏', 390), // Armenia
    'AZ': const _CurrencyInfo('AZN', '₼', 1.7), // Azerbaijan
    'BH': const _CurrencyInfo('BHD', 'BD', 0.376), // Bahrain
    'BD': const _CurrencyInfo('BDT', '৳', 110), // Bangladesh
    'BT': const _CurrencyInfo('BTN', 'Nu', 83), // Bhutan
    'BN': const _CurrencyInfo('BND', 'B\$', 1.34), // Brunei
    'KH': const _CurrencyInfo('KHR', '៛', 4100), // Cambodia
    'CN': const _CurrencyInfo('CNY', '¥', 7.2), // China
    'HK': const _CurrencyInfo('HKD', 'HK\$', 7.82), // Hong Kong
    'IN': const _CurrencyInfo('INR', '₹', 83), // India
    'ID': const _CurrencyInfo('IDR', 'Rp', 15700), // Indonesia
    'IR': const _CurrencyInfo('IRR', '﷼', 42000), // Iran
    'IQ': const _CurrencyInfo('IQD', 'ع.د', 1310), // Iraq
    'IL': const _CurrencyInfo('ILS', '₪', 3.7), // Israel
    'JP': const _CurrencyInfo('JPY', '¥', 150), // Japan
    'JO': const _CurrencyInfo('JOD', 'JD', 0.71), // Jordan
    'KZ': const _CurrencyInfo('KZT', '₸', 460), // Kazakhstan
    'KW': const _CurrencyInfo('KWD', 'KD', 0.31), // Kuwait
    'KG': const _CurrencyInfo('KGS', 'сом', 89), // Kyrgyzstan
    'LA': const _CurrencyInfo('LAK', '₭', 20800), // Laos
    'LB': const _CurrencyInfo('LBP', 'LL', 89500), // Lebanon
    'MO': const _CurrencyInfo('MOP', 'MOP\$', 8.1), // Macau
    'MY': const _CurrencyInfo('MYR', 'RM', 4.7), // Malaysia
    'MV': const _CurrencyInfo('MVR', 'Rf', 15.4), // Maldives
    'MN': const _CurrencyInfo('MNT', '₮', 3400), // Mongolia
    'MM': const _CurrencyInfo('MMK', 'K', 2100), // Myanmar
    'NP': const _CurrencyInfo('NPR', '₨', 133), // Nepal
    'KP': const _CurrencyInfo('KPW', '₩', 900), // North Korea
    'OM': const _CurrencyInfo('OMR', 'OMR', 0.385), // Oman
    'PK': const _CurrencyInfo('PKR', '₨', 278), // Pakistan
    'PS': const _CurrencyInfo('ILS', '₪', 3.7), // Palestine
    'PH': const _CurrencyInfo('PHP', '₱', 56), // Philippines
    'QA': const _CurrencyInfo('QAR', 'QR', 3.64), // Qatar
    'SA': const _CurrencyInfo('SAR', 'SAR', 3.75), // Saudi Arabia
    'SG': const _CurrencyInfo('SGD', 'S\$', 1.34), // Singapore
    'KR': const _CurrencyInfo('KRW', '₩', 1330), // South Korea
    'LK': const _CurrencyInfo('LKR', 'Rs', 310), // Sri Lanka
    'SY': const _CurrencyInfo('SYP', 'LS', 13000), // Syria
    'TW': const _CurrencyInfo('TWD', 'NT\$', 31.5), // Taiwan
    'TJ': const _CurrencyInfo('TJS', 'SM', 10.9), // Tajikistan
    'TH': const _CurrencyInfo('THB', '฿', 35), // Thailand
    'TL': const _CurrencyInfo('USD', '\$', 1.0), // Timor-Leste (dollarised)
    'TR': const _CurrencyInfo('TRY', '₺', 32), // Turkey
    'TM': const _CurrencyInfo('TMT', 'T', 3.5), // Turkmenistan
    'AE': const _CurrencyInfo('AED', 'AED', 3.67), // United Arab Emirates
    'UZ': const _CurrencyInfo('UZS', 'сўм', 12500), // Uzbekistan
    'VN': const _CurrencyInfo('VND', '₫', 25000), // Vietnam
    'YE': const _CurrencyInfo('YER', '﷼', 250), // Yemen
    // ─── OCEANIA ──────────────────────────────────────────────────────────
    'AS': const _CurrencyInfo('USD', '\$', 1.0), // American Samoa
    'AU': const _CurrencyInfo('AUD', 'A\$', 1.54), // Australia
    'CK': const _CurrencyInfo('NZD', 'NZ\$', 1.67), // Cook Islands
    'FJ': const _CurrencyInfo('FJD', 'FJ\$', 2.26), // Fiji
    'GU': const _CurrencyInfo('USD', '\$', 1.0), // Guam
    'KI': const _CurrencyInfo('AUD', 'A\$', 1.54), // Kiribati
    'MH': const _CurrencyInfo('USD', '\$', 1.0), // Marshall Islands
    'FM': const _CurrencyInfo('USD', '\$', 1.0), // Micronesia
    'NR': const _CurrencyInfo('AUD', 'A\$', 1.54), // Nauru
    'NZ': const _CurrencyInfo('NZD', 'NZ\$', 1.67), // New Zealand
    'PW': const _CurrencyInfo('USD', '\$', 1.0), // Palau
    'PG': const _CurrencyInfo('PGK', 'K', 3.7), // Papua New Guinea
    'WS': const _CurrencyInfo('WST', 'T', 2.75), // Samoa
    'SB': const _CurrencyInfo('SBD', 'SI\$', 8.4), // Solomon Islands
    'TO': const _CurrencyInfo('TOP', 'T\$', 2.37), // Tonga
    'TV': const _CurrencyInfo('AUD', 'A\$', 1.54), // Tuvalu
    'VU': const _CurrencyInfo('VUV', 'VT', 119), // Vanuatu
  };

  /// Returns the currency symbol for a country code, or '$' as fallback.
  static String currencySymbol(String? countryCode) {
    if (countryCode == null) return '\$';
    return _currencyMap[countryCode.toUpperCase()]?.symbol ?? '\$';
  }

  /// Whether two country codes use the same currency (e.g. US & PR both use USD).
  static bool isSameCurrency(String? countryA, String? countryB) {
    if (countryA == null || countryB == null) return false;
    return currencyCode(countryA) == currencyCode(countryB);
  }

  /// Resolve the USD rate for a country code.
  /// Prefers live rates from [ExchangeRateService], falls back to hardcoded.
  static double _resolveRate(String countryCode) {
    final info = _currencyMap[countryCode.toUpperCase()];
    if (info == null) return 1.0;

    // Try live rate first (keyed by currency code, e.g. "KES", "GBP")
    final live = ExchangeRateService.instance.getRate(info.code);
    if (live != null) return live;

    // Fallback to hardcoded
    return info.usdRate;
  }

  /// Convert an amount from one country's local currency to another's.
  /// Uses USD as the bridge: local₁ → USD → local₂.
  /// Prefers live exchange rates when available.
  static double convertCurrency(
    double amount,
    String? fromCountry,
    String? toCountry,
  ) {
    if (fromCountry == null || toCountry == null) return amount;
    final fromRate = _resolveRate(fromCountry);
    final toRate = _resolveRate(toCountry);
    if (fromRate == 0) return amount;
    // amount in fromCurrency ÷ fromRate = USD, × toRate = toCurrency
    return (amount / fromRate) * toRate;
  }

  /// Converts a local-currency amount to its USD equivalent.
  ///
  /// Used for Fiat GDP tracking — every completed economic transaction
  /// records its fiat value in USD via this method.
  ///
  /// [amount] — the price in the seller's / transaction's local currency.
  /// [countryCode] — ISO-3166 country code of the local currency.
  ///
  /// Returns `0.0` when [countryCode] is null or unrecognised.
  static double toUsd(double amount, String? countryCode) {
    if (countryCode == null || amount <= 0) return 0.0;
    final rate = _resolveRate(countryCode);
    if (rate <= 0) return 0.0;
    return amount / rate;
  }

  /// Format a price that has been converted into the viewer's local currency.
  /// Shows symbol + compact number, e.g. "≈ ₦ 1.2M" or "≈ $ 85".
  static String formatConvertedPrice(
    double originalAmount,
    String? fromCountry,
    String? toCountry,
  ) {
    final converted = convertCurrency(originalAmount, fromCountry, toCountry);
    return formatLocalPrice(converted, toCountry);
  }

  /// Returns the currency code (e.g. 'NGN') for a country code.
  static String currencyCode(String? countryCode) {
    if (countryCode == null) return 'USD';
    return _currencyMap[countryCode.toUpperCase()]?.code ?? 'USD';
  }

  /// Returns the full currency name string, e.g. "Tanzania Shillings (TSh)"
  /// by combining the code with the symbol.
  static String currencyLabel(String? countryCode) {
    if (countryCode == null) return 'USD';
    final info = _currencyMap[countryCode.toUpperCase()];
    if (info == null) return 'USD';
    return '${info.code} (${info.symbol})';
  }

  /// Converts a DSP amount to its approximate local currency equivalent.
  ///
  /// Steps:
  ///   1. DSP → USD:   dspAmount × baseDspToUsd
  ///   2. USD → Local:  usdAmount × localPerUsd
  static double dspToLocal(double dspAmount, String? countryCode) {
    final usd = dspAmount * _baseDspToUsd;
    final rate = countryCode != null ? _resolveRate(countryCode) : 1.0;
    return usd * rate;
  }

  /// Formats a local-currency value with symbol and compact notation.
  ///   e.g. "₦ 1.5K", "£ 0.79", "$ 1.2M"
  static String formatLocalEquivalent(double dspAmount, String? countryCode) {
    final localAmount = dspToLocal(dspAmount, countryCode);
    final symbol = currencySymbol(countryCode);

    if (localAmount >= 1000000) {
      return '$symbol ${(localAmount / 1000000).toStringAsFixed(1)}M';
    } else if (localAmount >= 1000) {
      return '$symbol ${(localAmount / 1000).toStringAsFixed(localAmount % 1000 == 0 ? 0 : 1)}K';
    } else if (localAmount >= 1) {
      return '$symbol ${localAmount.toStringAsFixed(localAmount == localAmount.roundToDouble() ? 0 : 2)}';
    } else if (localAmount > 0) {
      return '$symbol ${localAmount.toStringAsFixed(4)}';
    }
    return '$symbol 0';
  }

  /// Formats a raw local-currency price amount (not DSP) with its symbol.
  /// Used to display item prices which are stored in the seller's local currency.
  ///   e.g. "TSh 2,700,000" or "₦ 500,000"
  static String formatLocalPrice(double amount, String? countryCode) {
    final symbol = currencySymbol(countryCode);

    if (amount >= 1000000) {
      return '$symbol ${(amount / 1000000).toStringAsFixed(1)}M';
    } else if (amount >= 1000) {
      return '$symbol ${(amount / 1000).toStringAsFixed(amount % 1000 == 0 ? 0 : 1)}K';
    } else if (amount >= 1) {
      return '$symbol ${amount.toStringAsFixed(amount == amount.roundToDouble() ? 0 : 2)}';
    } else if (amount > 0) {
      return '$symbol ${amount.toStringAsFixed(2)}';
    }
    return '$symbol 0';
  }

  /// Compact formatting of a raw numeric price (no currency symbol).
  /// e.g. 2500 → "2.5K", 1500000 → "1.5M"
  static String formatCompact(double price) {
    if (price >= 1000000000) {
      return '${(price / 1000000000).toStringAsFixed(1)}B';
    } else if (price >= 1000000) {
      return '${(price / 1000000).toStringAsFixed(1)}M';
    } else if (price >= 1000) {
      return '${(price / 1000).toStringAsFixed(price % 1000 == 0 ? 0 : 1)}K';
    }
    return price.toStringAsFixed(price == price.roundToDouble() ? 0 : 2);
  }

  /// Converts a local-currency amount to its `$DIASPORA` token equivalent
  /// using the dynamic price floor ([dspPriceFloorUsd], fallback [_baseDspToUsd]).
  static double localToDiasporaToken(
    double amount,
    String? countryCode, {
    double dspPriceFloorUsd = _baseDspToUsd,
  }) {
    final usd = toUsd(amount, countryCode ?? 'US');
    final floor = dspPriceFloorUsd > 0 ? dspPriceFloorUsd : _baseDspToUsd;
    return usd / floor;
  }

  /// Formats a local-currency price into a compact `$DIASPORA` token string.
  /// e.g. "85K $DIASPORA" or "1.2M $DIASPORA"
  static String formatDiasporaTokenPrice(
    double amount,
    String? countryCode, {
    double dspPriceFloorUsd = _baseDspToUsd,
  }) {
    final tokens = localToDiasporaToken(
      amount,
      countryCode,
      dspPriceFloorUsd: dspPriceFloorUsd,
    );
    return '${formatCompact(tokens)} \$DIASPORA';
  }
}

class _CurrencyInfo {
  final String code;
  final String symbol;
  final double usdRate; // How many units of this currency equal 1 USD

  const _CurrencyInfo(this.code, this.symbol, this.usdRate);
}
