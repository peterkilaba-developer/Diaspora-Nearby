/**
 * ISO country-to-continent mapping shared by canonical community creation.
 * Keep this aligned with lib/core/data/countries.dart.
 */
const CONTINENT_CODES = {
  africa: new Set([
    "DZ", "AO", "BJ", "BW", "BF", "BI", "CM", "CV", "CF", "TD", "KM", "CG",
    "CD", "CI", "DJ", "EG", "GQ", "ER", "ET", "GA", "GM", "GH", "GN", "GW",
    "KE", "LS", "LR", "LY", "MG", "MW", "ML", "MR", "MU", "MA", "MZ", "NA",
    "NE", "NG", "RW", "ST", "SN", "SC", "SL", "SO", "ZA", "SS", "SD", "SZ",
    "TZ", "TG", "TN", "UG", "ZM", "ZW", "AC", "EH", "RE", "SH", "TA", "YT",
  ]),
  asia: new Set([
    "AF", "AM", "AZ", "BH", "BD", "BT", "BN", "KH", "CN", "CY", "GE", "HK",
    "IN", "ID", "IR", "IQ", "IL", "JP", "JO", "KZ", "KW", "KG", "LA", "LB",
    "MO", "MY", "MV", "MN", "MM", "NP", "KP", "OM", "PK", "PS", "PH", "QA",
    "SA", "SG", "KR", "LK", "SY", "TW", "TJ", "TH", "TL", "TR", "TM", "AE",
    "UZ", "VN", "YE", "IO",
  ]),
  caribbean: new Set([
    "AI", "AG", "AW", "BS", "BB", "KY", "CU", "DM", "DO", "GD", "HT", "JM",
    "MS", "PR", "KN", "LC", "VC", "TT", "VI", "BL", "BQ", "CW", "GP", "MF",
    "MQ", "SX", "TC", "VG",
  ]),
  europe: new Set([
    "AL", "AD", "AT", "BY", "BE", "BA", "BG", "HR", "CZ", "DK", "EE", "FI",
    "FR", "DE", "GR", "HU", "IS", "IE", "IT", "LV", "LI", "LT", "LU", "MK",
    "MT", "MD", "MC", "ME", "NL", "NO", "PL", "PT", "RO", "RU", "SM", "RS",
    "SK", "SI", "ES", "SE", "CH", "UA", "GB", "GB-ENG", "GB-SCT", "GB-WLS",
    "GB-NIR", "AX", "FO", "GG", "GI", "IM", "JE", "SJ", "VA", "XK",
  ]),
  northAmerica: new Set([
    "BZ", "BM", "CA", "CR", "SV", "GT", "HN", "MX", "NI", "PA", "US", "GL", "PM",
  ]),
  oceania: new Set([
    "AS", "AU", "CK", "FJ", "GU", "KI", "MH", "FM", "NR", "NZ", "PW", "PG",
    "WS", "SB", "TO", "TV", "VU", "CC", "CX", "MP", "NC", "NF", "NU", "PF",
    "TK", "WF",
  ]),
  southAmerica: new Set([
    "AR", "BO", "BR", "CL", "CO", "EC", "GY", "PY", "PE", "SR", "UY", "VE", "FK", "GF",
  ]),
};

const CONTINENT_NAMES = {
  africa: "Africa",
  asia: "Asia",
  caribbean: "Caribbean",
  europe: "Europe",
  northAmerica: "North America",
  oceania: "Oceania",
  southAmerica: "South America",
};

function continentForCountry(countryCode) {
  const code = String(countryCode || "").trim().toUpperCase();
  return Object.keys(CONTINENT_CODES)
      .find((continent) => CONTINENT_CODES[continent].has(code)) || null;
}

module.exports = {continentForCountry, CONTINENT_NAMES};
