import 'dart:ui';
import 'package:universal_io/io.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/core/data/countries.dart' as country_data;
import 'package:diaspora_nearby/core/services/google_places_service.dart';
import 'package:diaspora_nearby/core/utils/location_utils.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/shared/ui/glass_container.dart';
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';
import 'package:diaspora_nearby/features/trust/models/trust_data.dart';
import 'package:diaspora_nearby/features/shared/utils/search_highlight_utils.dart';
import 'package:diaspora_nearby/features/shared/widgets/shimmer_effect.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/core/localization/app_localizations.dart';

class UserCardView extends ConsumerStatefulWidget {
  final ProfileData user;
  final VoidCallback? onNameTap;
  final VoidCallback? onChatTap;
  final String? searchQuery;
  final double? distanceKm;
  final XFile? localImage;
  final bool isStatic;
  final String? titleSuffix;
  final Color? backgroundColor;
  final VoidCallback? onImageTap;
  final List<String> flaggedFields;
  final bool showCurrentLocation;
  final BorderRadius? borderRadius;

  const UserCardView({
    super.key,
    required this.user,
    this.onNameTap,
    this.onChatTap,
    this.searchQuery,
    this.distanceKm,
    this.localImage,
    this.isStatic = false,
    this.titleSuffix,
    this.backgroundColor,
    this.onImageTap,
    this.flaggedFields = const [],
    this.showCurrentLocation = true,
    this.borderRadius,
  });

  @override
  ConsumerState<UserCardView> createState() => _UserCardViewState();
}

class _UserCardViewState extends ConsumerState<UserCardView> {
  static final Map<String, Map<String, dynamic>> _coordGeocodeCache = {};
  static final Map<String, Future<Map<String, dynamic>?>>
  _coordGeocodeInFlight = {};
  Map<String, dynamic>? _resolvedCoordLocation;
  String? _resolvedCoordKey;

  @override
  void initState() {
    super.initState();
  }

  void _ensureCoordinateSubLocality(ProfileData user) {
    if (user.showCurrentLocationName == false) return;
    final sub = user.currentLocation?.subLocality?.trim();
    final adm2 = user.currentLocation?.adminArea2?.trim();
    final cc =
        user.currentLocation?.countryCode ??
        user.hostCountryCode ??
        user.hostLocation.countryCode;
    final isThreeTier = country_data.hasStateLevelForCountry(
      countryCode: cc,
      countryName: user.hostCountry ?? user.hostLocation.country,
    );
    // In 3-tier countries (e.g. US), if subLocality matches adminArea2 (legacy county-as-sublocality bug),
    // reverse-geocode the live coordinates so we always display true neighborhood/town hierarchy.
    final subLooksLikeLegacyCounty =
        isThreeTier &&
        sub != null &&
        sub.isNotEmpty &&
        adm2 != null &&
        adm2.isNotEmpty &&
        isSameOrRedundantLocationPart(sub, adm2);
    if (sub != null && sub.isNotEmpty && !subLooksLikeLegacyCounty) return;

    final coords = extractProfileCoords(user);
    if (coords == null) return;

    final key =
        '${coords.$1.toStringAsFixed(3)},${coords.$2.toStringAsFixed(3)}';
    final cached = _coordGeocodeCache[key];
    if (cached != null) {
      if (_resolvedCoordKey != key) {
        _resolvedCoordKey = key;
        _resolvedCoordLocation = cached;
      }
      return;
    }

    if (_resolvedCoordKey != key) {
      _resolvedCoordLocation = null;
    }

    Future<Map<String, dynamic>?>? future = _coordGeocodeInFlight[key];
    if (future == null) {
      final places = ref.read(googlePlacesServiceProvider);
      future = places
          .reverseGeocode(coords.$1, coords.$2)
          .then((res) {
            _coordGeocodeInFlight.remove(key);
            if (res != null) {
              _coordGeocodeCache[key] = res;
            }
            return res;
          })
          .catchError((_) {
            _coordGeocodeInFlight.remove(key);
            return null;
          });
      _coordGeocodeInFlight[key] = future;
    }

    future.then((res) {
      if (res != null && mounted && _resolvedCoordKey != key) {
        setState(() {
          _resolvedCoordKey = key;
          _resolvedCoordLocation = res;
        });
      }
    });
  }

  // ... (keep all helper methods same) ...

  String _getCountryFlag(String? countryCode) {
    if (countryCode == null || countryCode.isEmpty) return '';
    final country = country_data.getCountryByCode(countryCode);
    return country?.flag ?? '';
  }

  Widget _buildInitials(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Text(
        (widget.user.firstName.isNotEmpty ? widget.user.firstName[0] : '?')
                .toUpperCase() +
            (widget.user.lastName.isNotEmpty ? widget.user.lastName[0] : '')
                .toUpperCase(),
        style: theme.textTheme.titleLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildHighlightedName(String name, String? query, ThemeData theme) {
    return NoTranslate(
      child: SearchHighlightUtils.highlightText(
        name,
        query,
        theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        context,
      ),
    );
  }

  String _getProximityLevel(double? distanceKm) {
    if (distanceKm == null) return 'Unknown';
    if (distanceKm <= 10) return 'Nearby';
    if (distanceKm <= 50) return 'Far';
    if (distanceKm <= 200) return 'Farther';
    return 'Farthest';
  }

  Color _getProximityColor(String level, bool isDark, ThemeData theme) {
    switch (level) {
      case 'Nearby':
        return theme.colorScheme.primary;
      case 'Far':
        return isDark ? Colors.yellow[400]! : Colors.yellow[600]!;
      case 'Farther':
        return isDark ? Colors.orange[400]! : Colors.orange[600]!;
      case 'Unknown':
        return theme.colorScheme.onSurfaceVariant;
      default:
        return isDark ? Colors.red[400]! : Colors.red[600]!;
    }
  }

  /// Returns ('value', 'unit') for the distance row. Caller decides how to
  /// style each. `null` distance → ('—', '') so the row stays balanced.
  /// Sub-kilometer → ('< 1', 'km').
  (String, String) _formatDistanceMetric(double? km) {
    if (km == null) return ('—', '');
    if (km < 1) return ('< 1', 'km');
    return (NumberFormat('#,###').format(km.round()), 'km');
  }

  Future<void> _launchMaps(double lat, double lng) async {
    // [REQUEST] Start navigation (Directions) instead of search
    final Uri url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
    );
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch user location map');
    }
  }

  void _showFullScreenImage(BuildContext context) {
    showDialog(
      context: context,
      useSafeArea: false,
      barrierColor: Colors.black.withValues(alpha: 0.9), // Darker background
      builder: (dialogContext) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Tap outside the image to dismiss
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(dialogContext).pop(),
              ),
            ),
            // Centered Interactive User Image
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 16,
                ),
                child: Center(
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    child: InteractiveViewer(
                      panEnabled: true,
                      boundaryMargin: const EdgeInsets.all(20),
                      minScale: 0.5,
                      maxScale: 4,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          16,
                        ), // Standardized rounding
                        child: Image.network(
                          widget.user.profileImage,
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const CircularProgressIndicator(
                              color: Colors.white,
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            if (kIsWeb) {
                              debugPrint(
                                'âŒ Image failed to load on Web: $error (URL: ${widget.user.profileImage})',
                              );
                              if (widget.user.profileImage.contains(
                                'firebasestorage.googleapis.com',
                              )) {
                                debugPrint(
                                  'ðŸ’¡ Suggestion: If this is a CORS error, use --web-renderer html or configure CORS for Storage.',
                                );
                              }
                            }
                            return const Icon(
                              LucideIcons.imageOff,
                              color: Colors.white,
                              size: 50,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Close button (always in front of the image for easy dismissal)
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12, right: 16),
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: IconButton(
                      icon: const Icon(
                        LucideIcons.x,
                        color: Colors.white,
                        size: 24,
                      ),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getLevelColor(TrustLevel level) {
    switch (level) {
      case TrustLevel.lowTrust:
        return AppTheme.error;
      case TrustLevel.basicTrust:
        return Colors.deepOrange;
      case TrustLevel.mediumTrust:
        return Colors.amber;
      case TrustLevel.standardTrust:
        return Colors.lightGreen;
      case TrustLevel.highTrust:
        return AppTheme.accent;
    }
  }

  Widget _buildTrustBadge(TrustData? trust) {
    if (trust == null) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (trust.isVerified)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Tooltip(
              message:
                  'Verified Member • Trust Score: ${trust.trustScore.toInt()} (${trust.level.displayName})',
              triggerMode: TooltipTriggerMode.tap,
              child: Icon(
                LucideIcons.badgeCheck,
                size: 18,
                color: _getLevelColor(trust.level),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Tooltip(
              message:
                  'Trust Score: ${trust.trustScore.toInt()} (${trust.level.displayName})',
              triggerMode: TooltipTriggerMode.tap,
              child: Icon(
                LucideIcons.shieldCheck,
                size: 14,
                color: _getLevelColor(trust.level),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Watch live Firestore profile for this user when a UID is present,
    // falling back to widget.user while the stream initializes.
    final liveTarget = (widget.user.uid != null && widget.user.uid!.isNotEmpty)
        ? (ref.watch(userProfileByIdProvider(widget.user.uid!)).value ??
              widget.user)
        : widget.user;
    final effectiveUser =
        liveTarget.currentLocation == null &&
            widget.user.currentLocation != null
        ? liveTarget.copyWith(
            currentLocation: widget.user.currentLocation,
            distance: widget.user.distance,
          )
        : liveTarget.copyWith(
            distance: liveTarget.distance ?? widget.user.distance,
          );

    final homeFlag = _getCountryFlag(effectiveUser.homeCountryCode);
    final hostFlag = _getCountryFlag(effectiveUser.hostCountryCode);

    // Bottom bar flag - priority: currentLocation country -> hostLocation country
    String bottomFlag = '';
    if (effectiveUser.currentLocation?.countryCode != null) {
      bottomFlag = _getCountryFlag(effectiveUser.currentLocation!.countryCode);
    }
    if (bottomFlag.isEmpty) {
      bottomFlag = hostFlag;
    }

    // Local status logic
    final isLocal =
        effectiveUser.homeCountryCode != null &&
        effectiveUser.hostCountryCode != null &&
        effectiveUser.homeCountryCode == effectiveUser.hostCountryCode;

    // Calculate distance and proximity in real time relative to the logged-in
    // viewer's live GPS stream + profile coordinates (falling back to caller-supplied
    // distanceKm or server-computed user.distance when coordinates are unavailable).
    final livePos = ref.watch(liveUserPositionProvider).value;
    final viewer = ref.watch(userProfileProvider).value;
    double? distance;
    if (viewer != null &&
        effectiveUser.uid != null &&
        viewer.uid == effectiveUser.uid) {
      distance = 0.0;
    } else if (livePos != null &&
        livePos.latitude.isFinite &&
        livePos.longitude.isFinite &&
        (livePos.latitude != 0 || livePos.longitude != 0)) {
      final theirCoords = extractProfileCoords(effectiveUser);
      if (theirCoords != null) {
        distance = calculateDistance(
          livePos.latitude,
          livePos.longitude,
          theirCoords.$1,
          theirCoords.$2,
        );
      }
    }
    distance ??= calculateProfileDistanceKm(
      viewer,
      effectiveUser,
      fallbackDistanceKm: widget.distanceKm ?? effectiveUser.distance,
    );
    final proximityLevel = _getProximityLevel(distance);
    final proximityColor = _getProximityColor(proximityLevel, isDark, theme);
    final (distanceValue, distanceUnit) = _formatDistanceMetric(distance);

    // Trigger client-side coordinate reverse-geocoding if subLocality is not yet populated
    // so peers see sub-locality + locality + abbreviated state immediately in real time.
    _ensureCoordinateSubLocality(effectiveUser);

    // Format current location display:
    // - Smallest town/neighborhood designation -> higher town/city
    // - Plus abbreviated State/Province for the 20 three-tier countries in countries.dart
    String? currentCityDisplay;
    final effectiveCountryCode =
        effectiveUser.currentLocation?.countryCode ??
        (_resolvedCoordLocation?['countryCode'] as String?) ??
        effectiveUser.hostCountryCode ??
        effectiveUser.hostLocation.countryCode;
    final effectiveCountryName =
        (_resolvedCoordLocation?['country'] as String?) ??
        effectiveUser.hostCountry ??
        effectiveUser.hostLocation.country;
    final isThreeTier = country_data.hasStateLevelForCountry(
      countryCode: effectiveCountryCode,
      countryName: effectiveCountryName,
    );

    final rawStoredSub = effectiveUser.currentLocation?.subLocality?.trim();
    final rawStoredAdm2 = effectiveUser.currentLocation?.adminArea2?.trim();
    final storedSubIsLegacyCounty =
        isThreeTier &&
        rawStoredSub != null &&
        rawStoredSub.isNotEmpty &&
        rawStoredAdm2 != null &&
        rawStoredAdm2.isNotEmpty &&
        isSameOrRedundantLocationPart(rawStoredSub, rawStoredAdm2);

    final subLocality =
        (!storedSubIsLegacyCounty &&
            rawStoredSub != null &&
            rawStoredSub.isNotEmpty)
        ? rawStoredSub
        : (_resolvedCoordLocation?['subLocality'] as String?)?.trim();
    final adminArea2 = (rawStoredAdm2 != null && rawStoredAdm2.isNotEmpty)
        ? rawStoredAdm2
        : (_resolvedCoordLocation?['adminArea2'] as String?)?.trim();
    final city =
        (effectiveUser.currentLocation?.city?.trim().isNotEmpty == true)
        ? effectiveUser.currentLocation!.city!.trim()
        : (_resolvedCoordLocation?['city'] as String?)?.trim();

    String buildDisplayParts({
      String? smallestArea,
      String? primaryTown,
      String? districtOrCounty,
      String? rawState,
      String? rawStateCode,
      String? countryCode,
      String? countryName,
      required bool threeTier,
    }) {
      final parts = <String>[];
      void addPart(String? p) {
        if (p == null) return;
        final trimmed = p.trim();
        if (trimmed.isEmpty) return;
        if (parts.any((e) => isSameOrRedundantLocationPart(e, trimmed))) return;
        parts.add(trimmed);
      }

      addPart(smallestArea);
      addPart(primaryTown);

      if (threeTier) {
        final abbrState = abbreviateStateForCountry(
          state: rawState,
          stateCode: rawStateCode,
          city: primaryTown ?? smallestArea,
          countryCode: countryCode,
          countryName: countryName,
        );
        addPart(abbrState);
      } else {
        // For non-3-tier countries, if only one town part was found and a distinct
        // higher municipal district/adminArea2 exists (smaller town -> higher district),
        // append it after the town so two levels show cleanly.
        if (parts.length == 1 &&
            districtOrCounty != null &&
            districtOrCounty.trim().isNotEmpty) {
          addPart(districtOrCounty);
        }
      }

      return parts.join(', ');
    }

    if ((subLocality != null && subLocality.isNotEmpty) ||
        (city != null && city.isNotEmpty) ||
        (adminArea2 != null && adminArea2.isNotEmpty)) {
      final formatted = buildDisplayParts(
        smallestArea: subLocality,
        primaryTown: city ?? (!isThreeTier ? adminArea2 : null),
        districtOrCounty: adminArea2,
        rawState:
            effectiveUser.currentLocation?.state ??
            (_resolvedCoordLocation?['state'] as String?),
        rawStateCode:
            effectiveUser.currentLocation?.stateCode ??
            (_resolvedCoordLocation?['stateCode'] as String?),
        countryCode: effectiveCountryCode,
        countryName: effectiveCountryName,
        threeTier: isThreeTier,
      );
      if (formatted.isNotEmpty) {
        currentCityDisplay = formatted;
      }
    }

    if (currentCityDisplay == null &&
        effectiveUser.hostLocation.formattedAddress.isNotEmpty) {
      final loc = effectiveUser.hostLocation;
      final hostCc = loc.countryCode ?? effectiveUser.hostCountryCode;
      final hostCn = loc.country ?? effectiveUser.hostCountry;
      final hostThreeTier = country_data.hasStateLevelForCountry(
        countryCode: hostCc,
        countryName: hostCn,
      );
      if (loc.city != null && loc.city!.isNotEmpty) {
        final formatted = buildDisplayParts(
          primaryTown: loc.city,
          rawState: loc.state,
          countryCode: hostCc,
          countryName: hostCn,
          threeTier: hostThreeTier,
        );
        currentCityDisplay = formatted.isNotEmpty ? formatted : loc.city;
      } else {
        currentCityDisplay = formatFullAddress(
          effectiveUser.hostLocation.formattedAddress,
        ).split(',').first;
      }
    }

    final trustAsync = ref.watch(userTrustProvider(widget.user.uid!));

    return GlassContainer(
      color: widget.backgroundColor,
      borderRadius: widget.borderRadius,
      margin:
          EdgeInsets.zero, // 0px margins - parent container controls spacing
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: AppTheme
                  .pageHorizontalPadding, // 8px horizontal padding for card content
              right: AppTheme.pageHorizontalPadding,
              top: 16,
              bottom: 8,
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      GestureDetector(
                        onTap: () {
                          // [MODIFIED] Check custom handler first (e.g. for Edit Profile)
                          if (widget.onImageTap != null) {
                            widget.onImageTap!();
                            return;
                          }
                          // Default behavior: specific check for full screen
                          if (widget.user.profileImage.isNotEmpty &&
                              widget.user.profileImage.startsWith('http')) {
                            _showFullScreenImage(context);
                          } else if (widget.onNameTap != null) {
                            widget.onNameTap!();
                          }
                        },
                        child: Hero(
                          tag: 'user-avatar-${widget.user.uid}',
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: const Color(0x14888888),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    width: 80,
                                    height: 96,
                                    color: theme
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    child: widget.localImage != null
                                        ? (kIsWeb
                                              ? Image.network(
                                                  widget.localImage!.path,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, _, _) =>
                                                      _buildInitials(theme),
                                                )
                                              : Image.file(
                                                  File(widget.localImage!.path),
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, _, _) =>
                                                      _buildInitials(theme),
                                                ))
                                        : (widget
                                                  .user
                                                  .profileImage
                                                  .isNotEmpty &&
                                              widget.user.profileImage
                                                  .startsWith('http'))
                                        ? CachedNetworkImage(
                                            imageUrl: widget.user.profileImage,
                                            fit: BoxFit.cover,
                                            placeholder: (context, url) =>
                                                const ShimmerEffect(
                                                  width: 80,
                                                  height: 96,
                                                ),
                                            errorWidget: (context, url, error) {
                                              // Debug print using the error object
                                              if (kDebugMode) {
                                                debugPrint(
                                                  'UserCardView Image Error for ${widget.user.uid}: $error',
                                                );
                                                debugPrint(
                                                  'URL: ${widget.user.profileImage}',
                                                );
                                              }
                                              return _buildInitials(theme);
                                            },
                                            fadeInDuration: const Duration(
                                              milliseconds: 300,
                                            ),
                                          )
                                        : _buildInitials(theme),
                                  ),
                                ),
                              ),
                              if (widget.flaggedFields.contains(
                                'Profile Photo',
                              ))
                                Positioned(
                                  top: -6,
                                  right: -6,
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: const BoxDecoration(
                                      color: AppTheme.error,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      LucideIcons.alertTriangle,
                                      size: 12,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (isLocal)
                        Positioned(
                          bottom: -4,
                          right: -4,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: theme.colorScheme.surface,
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(2),
                            child: Container(
                              width: 24,
                              height: 24,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                              ),
                              child: Text(
                                homeFlag,
                                style: const TextStyle(fontSize: 16),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: widget.onNameTap,
                                child: Row(
                                  children: [
                                    Flexible(
                                      child: _buildHighlightedName(
                                        '${widget.user.firstName} ${widget.user.lastName}',
                                        widget.searchQuery,
                                        theme,
                                      ),
                                    ),
                                    if (widget.flaggedFields.contains(
                                          'First Name',
                                        ) ||
                                        widget.flaggedFields.contains(
                                          'Last Name',
                                        ))
                                      const Padding(
                                        padding: EdgeInsets.only(left: 6.0),
                                        child: Tooltip(
                                          message: 'Name flagged as incorrect',
                                          child: Icon(
                                            Icons.warning_amber_rounded,
                                            color: AppTheme.error,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            trustAsync.when(
                              data: (trust) => _buildTrustBadge(trust),
                              loading: () => const SizedBox.shrink(),
                              error: (_, _) => const SizedBox.shrink(),
                            ),
                            if (widget.titleSuffix != null)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Text(
                                  '(${widget.titleSuffix})',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),

                            if (widget.onChatTap != null)
                              if (widget.user.uid !=
                                  ref
                                      .read(authRepositoryProvider)
                                      .currentUser
                                      ?.uid)
                                GestureDetector(
                                  onTap: widget.onChatTap,
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.transparent,
                                        ),
                                        child: Icon(
                                          LucideIcons.messageCircle,
                                          size: 20,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                      Positioned(
                                        top: 4,
                                        right: 4,
                                        child: Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme.primary,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                          ],
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (homeFlag.isNotEmpty && !isLocal) ...[
                                  Text(
                                    homeFlag,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Text(
                                  'From',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: SearchHighlightUtils.highlightText(
                                    () {
                                      final loc = widget.user.homeLocation;
                                      final countryCode =
                                          widget.user.homeCountryCode;
                                      if (countryCode != null &&
                                          country_data
                                              .hasStateLevelHierarchyFromData(
                                                countryCode,
                                              )) {
                                        return formatFullAddress(
                                          loc.formattedAddress,
                                        );
                                      }
                                      if (loc.city?.isNotEmpty ?? false) {
                                        final fullCountry = formatLocationName(
                                          loc.country ??
                                              widget.user.homeCountry,
                                        );
                                        if (fullCountry.isNotEmpty) {
                                          return '${loc.city}, $fullCountry';
                                        }
                                        return loc.city!;
                                      }
                                      return formatFullAddress(
                                        loc.formattedAddress,
                                      );
                                    }(),
                                    widget.searchQuery,
                                    theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                    context,
                                  ),
                                ),
                                if (widget.flaggedFields.contains(
                                  'Home Country',
                                ))
                                  const Padding(
                                    padding: EdgeInsets.only(left: 4),
                                    child: Icon(
                                      Icons.warning_amber_rounded,
                                      color: AppTheme.error,
                                      size: 14,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                if (hostFlag.isNotEmpty && !isLocal) ...[
                                  Text(
                                    hostFlag,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Text(
                                  'Lives in',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: SearchHighlightUtils.highlightText(
                                    () {
                                      final loc = widget.user.hostLocation;
                                      final countryCode =
                                          widget.user.hostCountryCode;
                                      if (countryCode != null &&
                                          country_data
                                              .hasStateLevelHierarchyFromData(
                                                countryCode,
                                              )) {
                                        return formatFullAddress(
                                          loc.formattedAddress,
                                        );
                                      }
                                      if (loc.city?.isNotEmpty ?? false) {
                                        final fullCountry = formatLocationName(
                                          loc.country,
                                        );
                                        return '${loc.city}, $fullCountry';
                                      }
                                      return formatFullAddress(
                                        loc.formattedAddress,
                                      );
                                    }(),
                                    widget.searchQuery,
                                    theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                    context,
                                  ),
                                ),
                                if (widget.flaggedFields.contains(
                                  'Host Country',
                                ))
                                  const Padding(
                                    padding: EdgeInsets.only(left: 4),
                                    child: Icon(
                                      Icons.warning_amber_rounded,
                                      color: AppTheme.error,
                                      size: 14,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (widget.showCurrentLocation)
            GestureDetector(
              onTap: () {
                final targetCoords = extractProfileCoords(effectiveUser);
                if (targetCoords != null) {
                  _launchMaps(targetCoords.$1, targetCoords.$2);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.pageHorizontalPadding,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: widget.borderRadius != null
                      ? BorderRadius.only(
                          bottomLeft: widget.borderRadius!.bottomLeft,
                          bottomRight: widget.borderRadius!.bottomRight,
                        )
                      : const BorderRadius.only(
                          bottomLeft: Radius.circular(16),
                          bottomRight: Radius.circular(16),
                        ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Fixed 80px width + 12px gap matching the avatar column above
                    // so the moving app logo sits on the exact vertical line of
                    // the "From" / "Lives in" flags (X = 8 + 80 + 12 = 100px).
                    SizedBox(
                      width: 80,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (bottomFlag.isNotEmpty) ...[
                            Text(
                              bottomFlag,
                              style: const TextStyle(fontSize: 15),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Flexible(
                            child: Text(
                              proximityLevel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: proximityColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (effectiveUser.showCurrentLocationName != false &&
                        currentCityDisplay != null) ...[
                      Expanded(
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 16,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: _MovingLogo(),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                currentCityDisplay,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
                                  decoration: TextDecoration.none,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        width: 1,
                        height: 12,
                        color: theme.hintColor.withValues(alpha: 0.2),
                      ),
                      const SizedBox(width: 6),
                    ] else
                      const Spacer(),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: distanceValue,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF74A383),
                                ),
                              ),
                              if (distanceUnit.isNotEmpty)
                                TextSpan(
                                  text: ' $distanceUnit',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              if (distance != null)
                                TextSpan(
                                  text: ' away',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          LucideIcons.navigation,
                          size: 14,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MovingLogo extends StatefulWidget {
  const _MovingLogo();

  @override
  State<_MovingLogo> createState() => _MovingLogoState();
}

class _MovingLogoState extends State<_MovingLogo>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _animation,
      child: Image.asset(
        'assets/icons/logo-transparent-24.png',
        width: 14,
        height: 14,
      ),
    );
  }
}
