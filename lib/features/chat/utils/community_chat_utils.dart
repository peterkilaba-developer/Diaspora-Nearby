import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:diaspora_nearby/features/chat/models/chat.dart';
import 'package:diaspora_nearby/core/data/countries.dart';

/// Community Chat Utilities
/// Handles dynamic naming and avatar rendering for community chats and treasuries
/// as the single canonical source of truth across the application.
class CommunityChatUtils {
  /// Continent names mapping
  static const Map<String, String> _continentNames = {
    'africa': 'Africa',
    'asia': 'Asia',
    'europe': 'Europe',
    'north-america': 'North America',
    'south-america': 'South America',
    'oceania': 'Oceania',
    'antarctica': 'Antarctica',
    'caribbean': 'Caribbean',
  };

  static const Map<String, String> _adjectiveMap = {
    'africa': 'African',
    'asia': 'Asian',
    'europe': 'European',
    'north america': 'North American',
    'south america': 'South American',
    'oceania': 'Oceanian',
    'antarctica': 'Antarctic',
    'caribbean': 'Caribbean',
  };

  static const Map<String, String> _reverseAdjectiveMap = {
    'african': 'Africa',
    'asian': 'Asia',
    'european': 'Europe',
    'north american': 'North America',
    'south american': 'South America',
    'oceanian': 'Oceania',
    'antarctic': 'Antarctica',
    'caribbean': 'Caribbean',
  };

  /// Strips trailing community/treasury suffixes (e.g. "Community", "Sovereign Bond Treasury",
  /// "Continental Treasury", "Reserve Treasury", "DDI Treasury", "Treasury") so the raw
  /// geographic name is always clean regardless of which collection it came from.
  static String cleanBasePlaceName(String rawName) {
    var cleaned = rawName.trim();
    final suffixPattern = RegExp(
      r'\s+(?:Sovereign\s+Bond\s+Treasury|Continental\s+Treasury|Reserve\s+Treasury|DDI\s+Treasury|Sovereign\s+Bond|Continental|Reserve|DDI|Treasury|Community)$',
      caseSensitive: false,
    );
    while (suffixPattern.hasMatch(cleaned)) {
      cleaned = cleaned.replaceAll(suffixPattern, '').trim();
    }
    return cleaned;
  }

  /// Normalizes a continent string (including community or treasury suffixes, or adjective forms)
  /// to its lowercase canonical noun form (e.g. "African Sovereign Bond Treasury" -> "africa").
  static String normalizeContinentName(String name) {
    final cleaned = cleanBasePlaceName(name).toLowerCase();
    return (_reverseAdjectiveMap[cleaned] ?? cleaned).toLowerCase();
  }

  /// Canonical governance unit ID derived from a community ID.
  static String getCanonicalGovernanceUnitId(String communityId) {
    if (communityId == 'global_community' ||
        communityId == 'founders' ||
        communityId == 'liquidity' ||
        communityId == 'burn') {
      return communityId;
    }
    return communityId.contains('_')
        ? communityId.substring(communityId.indexOf('_') + 1)
        : communityId;
  }

  /// Infers canonical community/treasury type from explicit [type], [id], or [unitId].
  static String inferCommunityType({String? type, String? id, String? unitId}) {
    final rawType = type?.trim().toLowerCase() ?? '';
    if (rawType.isNotEmpty && rawType != 'unknown' && rawType != 'community') {
      if (rawType == 'province') return 'state';
      if (rawType == 'town') return 'city';
      return rawType;
    }
    final effectiveId = (id != null && id.isNotEmpty) ? id : (unitId ?? '');
    if (effectiveId == 'founders' ||
        effectiveId == 'liquidity' ||
        effectiveId == 'burn') {
      return effectiveId;
    }
    final parts = effectiveId.toLowerCase().split('_');
    if (parts.contains('global')) return 'global';
    if (parts.contains('continent')) return 'continent';
    if (parts.contains('country')) return 'country';
    if (parts.contains('city') || parts.contains('town')) return 'city';
    if (parts.contains('state') || parts.contains('province')) return 'state';
    return 'unknown';
  }

  /// Infers locationType ('home' | 'host' | 'past' | 'global' | 'bilateral') from [locationType] or [id].
  static String inferLocationType({String? locationType, String? id}) {
    final rawLoc = locationType?.trim().toLowerCase() ?? '';
    if (rawLoc.isNotEmpty) return rawLoc;
    final effectiveId = (id ?? '').toLowerCase();
    if (isBilateral(id: effectiveId)) return 'bilateral';
    if (effectiveId.contains('host_') || effectiveId.startsWith('host')) {
      return 'host';
    }
    if (effectiveId.contains('past_') || effectiveId.startsWith('past')) {
      return 'past';
    }
    if (effectiveId.contains('global')) return 'global';
    return 'home';
  }

  /// Canonical bilateral community ID (alphabetically sorted country codes)
  static String getBilateralCommunityId(String codeA, String codeB) {
    final sorted = [codeA.trim().toLowerCase(), codeB.trim().toLowerCase()]
      ..sort();
    return 'bilateral_country_${sorted[0]}_${sorted[1]}';
  }

  /// Canonical bilateral chat ID
  static String getBilateralChatId(String codeA, String codeB) {
    return 'chat_${getBilateralCommunityId(codeA, codeB)}';
  }

  /// Check whether a chat or ID represents a bilateral community chat
  static bool isBilateral({Chat? chat, String? id, String? locationType}) {
    final effectiveLocType = locationType ?? chat?.locationType ?? '';
    final effectiveId = id ?? chat?.id ?? '';
    final effectiveCommId = chat?.communityId ?? '';
    return effectiveLocType == 'bilateral' ||
        effectiveId.contains('bilateral_country_') ||
        effectiveCommId.contains('bilateral_country_') ||
        chat?.metadata?['isBilateral'] == true;
  }

  /// Extract [primaryCode, secondaryCode] ordered relative to [viewerHomeCountryCode]
  /// so the viewer's own home country ISO code and flag always start first.
  static List<String> resolveBilateralCountryCodes({
    Chat? chat,
    String? id,
    String? homeCountryCode,
    String? hostCountryCode,
    String? viewerHomeCountryCode,
  }) {
    String? code1;
    String? code2;

    final effectiveId = id ?? chat?.communityId ?? chat?.id ?? '';
    if (effectiveId.contains('bilateral_country_')) {
      final parts = effectiveId.split('_');
      final idx = parts.indexOf('country');
      if (idx != -1 && idx + 2 < parts.length) {
        code1 = parts[idx + 1].toUpperCase();
        code2 = parts[idx + 2].toUpperCase();
      }
    }

    code1 ??= (homeCountryCode ?? chat?.homeCountryCode)?.trim().toUpperCase();
    code2 ??= (hostCountryCode ?? chat?.hostCountryCode)?.trim().toUpperCase();

    if ((code1 == null || code1.isEmpty || code2 == null || code2.isEmpty) &&
        chat != null &&
        chat.name.isNotEmpty) {
      final match = RegExp(
        r'^([A-Za-z]{2})\s*-\s*([A-Za-z]{2})\b',
      ).firstMatch(chat.name.trim());
      if (match != null) {
        code1 ??= match.group(1)?.toUpperCase();
        code2 ??= match.group(2)?.toUpperCase();
      }
    }

    if (code1 == null || code1.isEmpty || code2 == null || code2.isEmpty) {
      return const [];
    }

    final viewerOwn = viewerHomeCountryCode?.trim().toUpperCase();
    if (viewerOwn != null &&
        viewerOwn.isNotEmpty &&
        code2 == viewerOwn &&
        code1 != viewerOwn) {
      return [code2, code1];
    }
    return [code1, code2];
  }

  /// Generate dynamic community name based on relation (Home vs Host vs Bilateral)
  /// Ports logic from React: `utils/communityLocationUtils.ts`
  static String generateCommunityName(
    Chat chat, {
    String? viewerHomeCountryCode,
  }) {
    if (!chat.isCommunity) return chat.name;

    // [FIX] Derive locationType from ID if not present on object
    String type = chat.locationType ?? '';
    if (type.isEmpty) {
      type = inferLocationType(id: chat.id);
    }

    return generateCommunityNameFromParts(
      name: chat.name,
      locationType: type,
      id: chat.id,
      homeCountryCode: chat.homeCountryCode,
      hostCountryCode: chat.hostCountryCode,
      viewerHomeCountryCode: viewerHomeCountryCode,
    );
  }

  /// Generate community name from raw parts
  /// specific for view models where Chat object might not exist yet
  static String generateCommunityNameFromParts({
    required String name,
    required String locationType,
    String id = '',
    String? homeCountryCode,
    String? hostCountryCode,
    String? viewerHomeCountryCode,
  }) {
    if (isBilateral(id: id, locationType: locationType)) {
      final codes = resolveBilateralCountryCodes(
        id: id,
        homeCountryCode: homeCountryCode,
        hostCountryCode: hostCountryCode,
        viewerHomeCountryCode: viewerHomeCountryCode,
      );
      if (codes.length == 2) {
        return '${codes[0]} - ${codes[1]} Community';
      }
    }
    final rawName = name;
    // [FIX] Strip existing "Community" or treasury suffixes (case-insensitive) to avoid duplications
    // e.g. "Africa Community" -> "Africa", "African Sovereign Bond Treasury" -> "African"
    final cleanName = cleanBasePlaceName(rawName);

    // 1. Global Community
    if (locationType == 'global' ||
        id == 'global_community' ||
        cleanName.toLowerCase().contains('global')) {
      return 'Global Community';
    }

    // 2. Continent Communities
    // Check if it's a continent community (usually name is just the continent)
    final lowerName = cleanName.toLowerCase();
    final isContinent =
        _continentNames.values.any((c) => c.toLowerCase() == lowerName) ||
        _reverseAdjectiveMap.containsKey(lowerName);

    // Also check if ID suggests it is a continent chat (e.g. chat_host_continent_africa)
    final isContinentById = id.contains('continent');

    if (isContinent || isContinentById) {
      // Find the continent name
      String continent = cleanName;

      // Extract continent from ID if possible for canonical Noun form
      // e.g. chat_host_continent_africa -> Africa
      if (id.isNotEmpty) {
        final idParts = id.split('_');
        // Look for part after 'continent'
        final continentIndex = idParts.indexOf('continent');
        if (continentIndex != -1 && continentIndex + 1 < idParts.length) {
          String slug = idParts[continentIndex + 1];
          // Convert slug to Title Case (e.g. north-america -> North America)
          continent = slug
              .split('-')
              .map(
                (word) => word.isNotEmpty
                    ? '${word[0].toUpperCase()}${word.substring(1)}'
                    : '',
              )
              .join(' ');
        }
      }

      if (continent.isEmpty || continent == 'Unknown') {
        return 'Community';
      }

      // Apply Home vs Host Logic
      // Host: noun form (e.g., "Africa Community")
      // Home: adjective form (e.g., "African Community")
      if (locationType == 'host' || locationType == 'past') {
        final noun = _reverseAdjectiveMap[continent.toLowerCase()] ?? continent;
        return '$noun Community';
      } else {
        final canonicalNoun =
            _reverseAdjectiveMap[continent.toLowerCase()] ?? continent;

        final adj = _adjectiveMap[canonicalNoun.toLowerCase()] ?? canonicalNoun;
        return '$adj Community';
      }
    }

    // Safety check for empty or unknown names
    if (cleanName.isEmpty || cleanName == 'Unknown') return 'Community';

    // 3. Country/State/City Communities
    return '$cleanName Community';
  }

  /// Returns the canonical base location name without trailing "Community" or treasury suffixes
  /// (e.g. "African" for home_continent_africa, "North America" for host_continent_north-america_tz,
  /// "Tanzania" for home_country_tz, "Iowa" for host_state_us_iowa_tz).
  static String getBaseLocationName({
    required String name,
    String? locationType,
    String id = '',
    String? homeCountryCode,
    String? hostCountryCode,
    String? viewerHomeCountryCode,
  }) {
    final effectiveLocType = inferLocationType(
      locationType: locationType,
      id: id,
    );
    final communityName = generateCommunityNameFromParts(
      name: name,
      locationType: effectiveLocType,
      id: id,
      homeCountryCode: homeCountryCode,
      hostCountryCode: hostCountryCode,
      viewerHomeCountryCode: viewerHomeCountryCode,
    );
    return communityName
        .replaceAll(RegExp(r'\s+Community$', caseSensitive: false), '')
        .trim();
  }

  /// Generates the canonical category title for a treasury tier (without geographic prefix).
  static String generateTreasuryCategoryTitle({
    String? type,
    String? id,
    String? unitId,
  }) {
    final effectiveType = inferCommunityType(
      type: type,
      id: id,
      unitId: unitId,
    );
    switch (effectiveType) {
      case 'founders':
        return 'Founders & Core Team';
      case 'liquidity':
        return 'Liquidity Treasury';
      case 'burn':
        return 'Natural Burn Pool';
      case 'global':
        return 'Global Reserve';
      case 'continent':
        return 'Sovereign Bond Treasury';
      case 'state':
        return 'Reserve Treasury';
      case 'country':
      case 'city':
        return 'DDI Treasury';
      default:
        return 'Reserve Treasury';
    }
  }

  /// Single canonical source of truth for treasury titles across all screens
  /// (PointsSystemScreen, DiasporaCryptoScreen, DdiTreasuryDetailScreen, etc.).
  static String generateTreasuryTitle({
    String? name,
    String? type,
    String? locationType,
    String? id,
    String? unitId,
    String? homeCountryCode,
    String? hostCountryCode,
    String? viewerHomeCountryCode,
  }) {
    final effectiveId = (id != null && id.isNotEmpty) ? id : (unitId ?? '');
    final effectiveType = inferCommunityType(
      type: type,
      id: id,
      unitId: unitId,
    );

    if (effectiveType == 'founders' ||
        effectiveType == 'liquidity' ||
        effectiveType == 'burn' ||
        effectiveType == 'global') {
      return generateTreasuryCategoryTitle(
        type: effectiveType,
        id: id,
        unitId: unitId,
      );
    }

    final baseName = getBaseLocationName(
      name: name ?? '',
      locationType: locationType,
      id: effectiveId,
      homeCountryCode: homeCountryCode,
      hostCountryCode: hostCountryCode,
      viewerHomeCountryCode: viewerHomeCountryCode,
    );

    final categorySuffix = generateTreasuryCategoryTitle(
      type: effectiveType,
      id: id,
      unitId: unitId,
    );

    if (baseName.isEmpty ||
        baseName.toLowerCase() == 'community' ||
        baseName.toLowerCase() == 'unknown') {
      return categorySuffix;
    }

    return '$baseName $categorySuffix';
  }

  /// Single canonical source of truth for treasury role descriptions (without match suffix).
  static String generateTreasuryRoleLabel({
    String? type,
    String? id,
    String? unitId,
  }) {
    final effectiveType = inferCommunityType(
      type: type,
      id: id,
      unitId: unitId,
    );
    switch (effectiveType) {
      case 'global':
        return 'Zero-fee transfers & remittances, chamber leadership, charities & protocol upkeep';
      case 'continent':
        return 'Funding Sovereign Bond Engine';
      case 'state':
        return 'State liquidity reserve & loan backstop';
      case 'country':
        return 'Large-scale sovereign investments (\$1M+)';
      case 'city':
        return 'Local community business loans (up to \$1M)';
      case 'founders':
        return 'Core Maintenance & Protocol Development';
      case 'liquidity':
        return 'DEX Liquidity & Market Access';
      case 'burn':
        return 'Fixed 10% Infrastructure Burn';
      default:
        return 'Diaspora Direct Investments & community wealth';
    }
  }

  /// Single canonical source of truth for treasury subtitles across all screens.
  static String generateTreasurySubtitle({
    String? type,
    String? id,
    String? unitId,
  }) {
    final effectiveType = inferCommunityType(
      type: type,
      id: id,
      unitId: unitId,
    );
    switch (effectiveType) {
      case 'global':
        return 'Zero-fee transfers & remittances, chamber leadership, charities & protocol upkeep · 10% Ubuntu community match';
      case 'continent':
        return 'Funding Sovereign Bond Engine · 10% Ubuntu community match';
      case 'state':
        return 'State liquidity reserve & loan backstop · 10% Ubuntu community match';
      case 'country':
        return 'Large-scale sovereign investments (\$1M+) · 10% Ubuntu community match';
      case 'city':
        return 'Local community business loans (up to \$1M) · 10% Ubuntu community match';
      case 'founders':
        return 'Core Maintenance (10%)';
      case 'liquidity':
        return 'DEX Liquidity & Market Access';
      case 'burn':
        return 'Protocol Deflationary Sink';
      default:
        return 'Diaspora Direct Investments & community wealth · 10% Ubuntu community match';
    }
  }

  /// Get appropriate avatar widget for community
  /// Ports logic from React: `utils/communityAvatarUtils.tsx`
  static Widget getCommunityAvatar({
    Chat? chat,
    String? type,
    String? locationType,
    String? homeCountryCode,
    String? hostCountryCode,
    String? viewerHomeCountryCode,
    String? flag,
    String? communityId,
    String? profileImage,
    double size = 48,
    required BuildContext context,
  }) {
    // 0. Use Profile Image if available
    if (profileImage != null &&
        profileImage.isNotEmpty &&
        profileImage != 'users' && // [FIX] Ignore legacy placeholder
        !profileImage.startsWith('assets/')) {
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(shape: BoxShape.circle),
        clipBehavior: Clip.antiAlias,
        child: CachedNetworkImage(
          imageUrl: profileImage,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(color: Colors.grey.shade200),
          errorWidget: (context, url, error) => const Icon(LucideIcons.users),
        ),
      );
    }

    // 1. Resolve effective values
    final effectiveId = communityId ?? chat?.id ?? '';
    var effectiveLocationType = locationType ?? chat?.locationType;
    if (effectiveLocationType == null) {
      if (isBilateral(chat: chat, id: effectiveId)) {
        effectiveLocationType = 'bilateral';
      } else if (effectiveId.contains('_host_')) {
        effectiveLocationType = 'host';
      } else if (effectiveId.contains('_past_')) {
        effectiveLocationType = 'past';
      } else if (effectiveId.contains('_home_')) {
        effectiveLocationType = 'home';
      } else if (effectiveId.contains('global')) {
        effectiveLocationType = 'global';
      } else {
        effectiveLocationType = 'home';
      }
    }

    // 1.5 Bilateral Dual-Flag Avatar — matches Corridor Chamber of Commerce design
    // (viewer's own country flag larger at bottom-left, partner country flag smaller at top-right)
    if (isBilateral(
      chat: chat,
      id: effectiveId,
      locationType: effectiveLocationType,
    )) {
      final codes = resolveBilateralCountryCodes(
        chat: chat,
        id: effectiveId,
        homeCountryCode: homeCountryCode,
        hostCountryCode: hostCountryCode,
        viewerHomeCountryCode: viewerHomeCountryCode,
      );
      if (codes.length == 2) {
        final ownFlag = getCountryByCode(codes[0])?.flag;
        final otherFlag = getCountryByCode(codes[1])?.flag;
        if (ownFlag != null && otherFlag != null) {
          final double leadingFontSize = size == 56
              ? 34
              : (size == 36 ? 22 : size * (34 / 56));
          final double secondaryFontSize = size == 56
              ? 26
              : (size == 36 ? 16 : size * (26 / 56));
          return SizedBox(
            width: size,
            height: size,
            child: Stack(
              children: [
                // Viewer's own country flag — bottom-left, larger (leads)
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: Text(
                    ownFlag,
                    style: TextStyle(fontSize: leadingFontSize),
                  ),
                ),
                // Partner country flag — top-right, smaller
                Positioned(
                  right: 0,
                  top: 0,
                  child: Text(
                    otherFlag,
                    style: TextStyle(fontSize: secondaryFontSize),
                  ),
                ),
              ],
            ),
          );
        }
      }
    }

    final effectiveType = inferCommunityType(type: type, id: effectiveId);

    // 2. Derive combined type
    final combinedType = effectiveType == 'global'
        ? 'global'
        : '${effectiveLocationType}_$effectiveType';

    // 3. Country Flag logic
    if (effectiveType == 'country') {
      final countryCode = () {
        // [FIX] Extract TARGET country from ID for ALL types (host, past, AND home)
        // ID format: host_country_[target]_[home] OR home_country_[target]
        if ((effectiveLocationType == 'host' ||
                effectiveLocationType == 'past' ||
                effectiveLocationType == 'home') &&
            effectiveId.contains('_country_')) {
          final parts = effectiveId.split('_');
          final countryIndex = parts.indexOf('country');
          if (countryIndex != -1 && countryIndex + 1 < parts.length) {
            return parts[countryIndex + 1].toUpperCase();
          }
        }
        return hostCountryCode ??
            homeCountryCode ??
            chat?.hostCountryCode ??
            chat?.homeCountryCode;
      }();
      final displayFlag = (flag != null && flag.isNotEmpty)
          ? flag
          : (chat?.flag != null && chat!.flag!.isNotEmpty)
          ? chat.flag
          : (countryCode != null ? getCountryByCode(countryCode)?.flag : null);

      if (displayFlag != null) {
        final isHome = effectiveLocationType == 'home';
        final overlayIcon = isHome ? LucideIcons.home : LucideIcons.mapPin;
        final iconColor = isHome
            ? Colors.orange.shade700
            : Colors.cyan.shade700;

        final theme = Theme.of(context);
        return Container(
          width: size,
          height: size,
          color: Colors.transparent,
          child: Stack(
            children: [
              Center(
                child: Text(
                  displayFlag,
                  style: TextStyle(fontSize: size * 0.7),
                ),
              ),
              Positioned(
                bottom: 2,
                right: 2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(
                      alpha: 0.8,
                    ), // Themed background for small overlay
                    shape: BoxShape.circle,
                  ),
                  child: Icon(overlayIcon, size: size * 0.25, color: iconColor),
                ),
              ),
            ],
          ),
        );
      }
    }

    // 4. Gradient logic for others
    final gradient = getCommunityGradient(combinedType);
    final isHome = effectiveLocationType == 'home';
    final icon = isHome ? LucideIcons.home : LucideIcons.mapPin;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: gradient),
      child: Center(
        child: Icon(
          combinedType == 'global' ? LucideIcons.globe : icon,
          color: Colors.white,
          size: size * 0.5,
        ),
      ),
    );
  }

  static LinearGradient? getCommunityGradient(String combinedType) {
    switch (combinedType) {
      case 'global':
        return const LinearGradient(
          colors: [Color(0xFF14B8A6), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'home_continent':
        return const LinearGradient(
          colors: [Color(0xFFF97316), Color(0xFFD97706)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'host_continent':
      case 'past_continent':
        return const LinearGradient(
          colors: [Color(0xFF06B6D4), Color(0xFF0284C7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'home_state':
        return const LinearGradient(
          colors: [Color(0xFF10B981), Color(0xFF0D9488)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'host_state':
      case 'past_state':
        return const LinearGradient(
          colors: [Color(0xFF8B5CF6), Color(0xFF9333EA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'home_city':
        return const LinearGradient(
          colors: [Color(0xFF22C55E), Color(0xFF059669)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'host_city':
      case 'past_city':
        return const LinearGradient(
          colors: [
            Color(0xFF6B9B7A),
            Color(0xFF557A63),
          ], // Sage Green (App Accent)
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      default:
        return null;
    }
  }
}
