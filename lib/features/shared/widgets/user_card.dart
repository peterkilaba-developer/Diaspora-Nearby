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
import 'package:diaspora_nearby/core/utils/location_utils.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/shared/ui/glass_container.dart';
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';
import 'package:diaspora_nearby/features/trust/models/trust_data.dart';
import 'package:diaspora_nearby/features/shared/utils/search_highlight_utils.dart';
import 'package:diaspora_nearby/features/shared/widgets/shimmer_effect.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

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
  @override
  void initState() {
    super.initState();
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
    return SearchHighlightUtils.highlightText(
      name,
      query,
      theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      context,
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
      barrierColor: Colors.black.withValues(alpha: 0.9), // Darker background
      builder: (context) => Stack(
        children: [
          // Close button (positioned safely)
          Positioned(
            top: 40,
            right: 20,
            child: Material(
              color: Colors.transparent,
              child: IconButton(
                icon: const Icon(LucideIcons.x, color: Colors.white, size: 30),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          // Centered Interactive User Image
          Center(
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
                    return const CircularProgressIndicator(color: Colors.white);
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
        ],
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
    // viewer's live coordinates (falling back to caller-supplied distanceKm or
    // server-computed user.distance when coordinates are unavailable).
    final viewer = ref.watch(userProfileProvider).value;
    final double? distance = calculateProfileDistanceKm(
      viewer,
      effectiveUser,
      fallbackDistanceKm: widget.distanceKm ?? effectiveUser.distance,
    );
    final proximityLevel = _getProximityLevel(distance);
    final proximityColor = _getProximityColor(proximityLevel, isDark, theme);
    final (distanceValue, distanceUnit) = _formatDistanceMetric(distance);

    // Format current city display
    String? currentCityDisplay;
    final city = effectiveUser.currentLocation?.city;
    if (city != null && city.isNotEmpty) {
      final state = effectiveUser.currentLocation?.state;
      final countryCode = effectiveUser.currentLocation?.countryCode;

      if (countryCode != null &&
          country_data.hasStateLevelHierarchyFromData(countryCode) &&
          state != null &&
          state.isNotEmpty) {
        final fullState = formatLocationName(state);
        currentCityDisplay = '$city, $fullState';
      } else {
        currentCityDisplay = city;
      }
    } else if (effectiveUser.hostLocation.formattedAddress.isNotEmpty) {
      final loc = effectiveUser.hostLocation;
      if (loc.city != null && loc.city!.isNotEmpty) {
        final state = loc.state;
        if (state != null && state.isNotEmpty) {
          currentCityDisplay = '${loc.city}, ${formatLocationName(state)}';
        } else {
          currentCityDisplay = loc.city;
        }
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
                  horizontal: 16,
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                if (bottomFlag.isNotEmpty) ...[
                                  Text(
                                    bottomFlag,
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Text(
                                  proximityLevel,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: proximityColor,
                                  ),
                                ),
                                // Show city when we have something to display —
                                // either a real currentLocation, or a fallback
                                // from hostLocation (city populated above on
                                // ~L300). Previously this row was gated on
                                // currentLocation != null, which hid the
                                // fallback for connections who haven't opened
                                // the app since location tracking shipped.
                                if (effectiveUser.showCurrentLocationName !=
                                        false &&
                                    currentCityDisplay != null) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 1,
                                    height: 12,
                                    color: theme.hintColor.withValues(
                                      alpha: 0.2,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const _MovingLogo(),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            currentCityDisplay,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  fontSize: 12,
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                  decoration:
                                                      TextDecoration.none,
                                                ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
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
