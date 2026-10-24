import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:diaspora_nearby/features/chat/models/chat.dart';
import 'package:diaspora_nearby/core/data/countries.dart';

/// Community Chat Utilities
/// Handles dynamic naming and avatar rendering for community chats
/// to ensure parity with React application logic.
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
      if (isBilateral(chat: chat)) {
        type = 'bilateral';
      } else if (chat.id.contains('_host_')) {
        type = 'host';
      } else if (chat.id.contains('_past_')) {
        type = 'past';
      } else {
        type = 'home';
      }
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
    // [FIX] Strip existing "Community" suffix (case-insensitive) to avoid duplications
    // e.g. "Africa Community" -> "Africa"
    final cleanName = rawName
        .replaceAll(RegExp(r'\s+Community$', caseSensitive: false), '')
        .trim();

    // Safety check for empty or unknown names
    if (cleanName.isEmpty || cleanName == 'Unknown') return 'Community';

    // 1. Global Community
    if (locationType == 'global' ||
        cleanName.toLowerCase().contains('global')) {
      return 'Global Community';
    }

    // 2. Continent Communities
    // Check if it's a continent community (usually name is just the continent)
    final lowerName = cleanName.toLowerCase();
    final isContinent = _continentNames.values.any(
      (c) => c.toLowerCase() == lowerName,
    );

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

      // Apply Home vs Host Logic
      // Host: noun form (e.g., "Africa Community")
      // Home: adjective form (e.g., "African Community")
      if (locationType == 'host' || locationType == 'past') {
        const Map<String, String> reverseAdjectiveMap = {
          'african': 'Africa',
          'asian': 'Asia',
          'european': 'Europe',
          'north american': 'North America',
          'south american': 'South America',
          'oceanian': 'Oceania',
          'antarctic': 'Antarctica',
          'caribbean': 'Caribbean',
        };
        final noun = reverseAdjectiveMap[continent.toLowerCase()] ?? continent;
        return '$noun Community';
      } else {
        const Map<String, String> adjectiveMap = {
          'africa': 'African',
          'asia': 'Asian',
          'europe': 'European',
          'north america': 'North American',
          'south america': 'South American',
          'oceania': 'Oceanian',
          'antarctica': 'Antarctic',
          'caribbean': 'Caribbean',
        };
        const Map<String, String> reverseAdjectiveMap = {
          'african': 'Africa',
          'asian': 'Asia',
          'european': 'Europe',
          'north american': 'North America',
          'south american': 'South America',
          'oceanian': 'Oceania',
          'antarctic': 'Antarctica',
          'caribbean': 'Caribbean',
        };
        final canonicalNoun =
            reverseAdjectiveMap[continent.toLowerCase()] ?? continent;

        final adj = adjectiveMap[canonicalNoun.toLowerCase()] ?? canonicalNoun;
        return '$adj Community';
      }
    }

    // 3. Country/State/City Communities
    return '$cleanName Community';
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

    var effectiveType = type;
    if (effectiveType == null) {
      final parts = effectiveId.split('_');
      if (parts.contains('global')) {
        effectiveType = 'global';
      } else if (parts.contains('continent')) {
        effectiveType = 'continent';
      } else if (parts.contains('country')) {
        effectiveType = 'country';
      } else if (parts.contains('city')) {
        // Prioritize city check (most specific)
        effectiveType = 'city';
      } else if (parts.contains('state')) {
        effectiveType = 'state';
      } else {
        effectiveType = 'unknown';
      }
    }

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
