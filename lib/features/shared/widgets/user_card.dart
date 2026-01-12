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
import 'package:diaspora_nearby/models/profile_data.dart';
import 'package:diaspora_nearby/data/countries.dart' as country_data;
import 'package:diaspora_nearby/utils/location_utils.dart';
import 'package:diaspora_nearby/features/shared/ui/glass_container.dart';
import 'package:diaspora_nearby/features/shared/utils/search_highlight_utils.dart';
import 'package:diaspora_nearby/features/shared/widgets/shimmer_effect.dart';

class UserCardView extends ConsumerStatefulWidget {
  final ProfileData user;
  final VoidCallback? onNameTap;
  final VoidCallback? onChatTap;
  final String? searchQuery; // Optional search query for highlighting
  final double? distanceKm; // Optional distance override for search results
  final XFile? localImage; // Optional local image override
  final bool isStatic; // Static mode for community lists
  
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
    this.onImageTap, // [NEW] Allow overriding image tap (e.g. for picking new image)
  });

  final String? titleSuffix;
  final Color? backgroundColor;
  final VoidCallback? onImageTap;

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
    if (countryCode == null || countryCode.isEmpty) return 'ð';
    final country = country_data.getCountryByCode(countryCode);
    return country?.flag ?? 'ð';
  }

  Widget _buildInitials(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceVariant,
      alignment: Alignment.center,
      child: Text(
        (widget.user.firstName.isNotEmpty ? widget.user.firstName[0] : '?').toUpperCase() +
        (widget.user.lastName.isNotEmpty ? widget.user.lastName[0] : '').toUpperCase(),
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
      context
    );
  }

  String _getProximityLevel(double distanceKm) {
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
      default:
        return isDark ? Colors.red[400]! : Colors.red[600]!;
    }
  }
  
  String _formatDistanceImperial(double km) {
    double miles = km * 0.621371;
    double feet = km * 3280.84;
    return miles >= 1 ? '${miles.toStringAsFixed(1)} mi' : '${feet.round()} ft';
  }
  
  String _formatDistanceMetric(double km) {
    // Return whole numbers for cleaner UI and to save space. Minimum 1km.
    final value = km < 1 ? 1 : km.round();
    return '${NumberFormat("#,###").format(value)} km';
  }

  Future<void> _launchMaps(double lat, double lng) async {
    // [REQUEST] Start navigation (Directions) instead of search
    final Uri url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch user location map');
    }
  }

  void _showFullScreenImage(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.9), // Darker background
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
                borderRadius: BorderRadius.circular(8), // Slight rounding
                child: Image.network(
                  widget.user.profileImage,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const CircularProgressIndicator(color: Colors.white);
                  },
                  errorBuilder: (context, error, stackTrace) {
                     if (kIsWeb) {
                       debugPrint('❌ Image failed to load on Web: $error (URL: ${widget.user.profileImage})');
                       if (widget.user.profileImage.contains('firebasestorage.googleapis.com')) {
                         debugPrint('💡 Suggestion: If this is a CORS error, use --web-renderer html or configure CORS for Storage.');
                       }
                     }
                     return const Icon(LucideIcons.imageOff, color: Colors.white, size: 50);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final homeFlag = _getCountryFlag(widget.user.homeCountryCode);
    final hostFlag = _getCountryFlag(widget.user.hostCountryCode);
    
    // Bottom bar flag - priority: currentLocation country -> hostLocation country
    String bottomFlag = '';
    if (widget.user.currentLocation?.countryCode != null) {
      bottomFlag = _getCountryFlag(widget.user.currentLocation!.countryCode);
    }
    if (bottomFlag.isEmpty || bottomFlag == '📍') {
      bottomFlag = hostFlag;
    }
    
    // Local status logic
    final isLocal = widget.user.homeCountryCode != null && 
                    widget.user.hostCountryCode != null && 
                    widget.user.homeCountryCode == widget.user.hostCountryCode;
    
    // Calculate distance and proximity
    final distance = widget.distanceKm ?? widget.user.distance ?? 0.0;
    final proximityLevel = _getProximityLevel(distance);
    final proximityColor = _getProximityColor(proximityLevel, isDark, theme);
    
    // Format current city display
    String? currentCityDisplay;
    final city = widget.user.currentLocation?.city;
    if (city != null && city.isNotEmpty) {
      final state = widget.user.currentLocation?.state;
      final countryCode = widget.user.currentLocation?.countryCode;
      
      if (countryCode != null && 
          country_data.hasStateLevelHierarchyFromData(countryCode) &&
          state != null &&
          state.isNotEmpty) {
        final fullState = formatLocationName(state); 
        currentCityDisplay = '$city, $fullState';
      } else {
        currentCityDisplay = city;
      }
    } else if (widget.user.hostLocation.formattedAddress.isNotEmpty) {
      final loc = widget.user.hostLocation;
      if (loc.city != null && loc.city!.isNotEmpty) {
          final state = loc.state;
          if (state != null && state.isNotEmpty) {
             currentCityDisplay = '${loc.city}, ${formatLocationName(state)}';
          } else {
             currentCityDisplay = loc.city;
          }
      } else {
          currentCityDisplay = formatFullAddress(widget.user.hostLocation.formattedAddress).split(',').first;
      }
    }

    return GlassContainer(
      color: widget.backgroundColor,
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 8, top: 16, bottom: 8),
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
                          if (widget.user.profileImage.isNotEmpty && widget.user.profileImage.startsWith('http')) {
                            _showFullScreenImage(context);
                          } else if (widget.onNameTap != null) {
                            widget.onNameTap!();
                          }
                        },
                      child: Hero(
                        tag: 'user-avatar-${widget.user.uid}',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 80,
                            height: 96,
                            color: theme.colorScheme.surfaceVariant,
                            child: widget.localImage != null
                              ? (kIsWeb 
                                  ? Image.network(
                                      widget.localImage!.path,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => _buildInitials(theme),
                                    )
                                  : Image.file(
                                      File(widget.localImage!.path),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => _buildInitials(theme),
                                    )
                                )
                              : (widget.user.profileImage.isNotEmpty && widget.user.profileImage.startsWith('http'))
                                ? CachedNetworkImage(
                                    imageUrl: widget.user.profileImage,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => const ShimmerEffect(width: 80, height: 96),
                                    errorWidget: (context, url, error) {
                                       // Debug print using the error object
                                       if (kDebugMode) {
                                          print('UserCardView Image Error for ${widget.user.uid}: $error');
                                          print('URL: ${widget.user.profileImage}');
                                       }
                                       return _buildInitials(theme);
                                    },
                                    fadeInDuration: const Duration(milliseconds: 300),
                                  )
                                : _buildInitials(theme),
                          ),
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
                              )
                            ],
                          ),
                          padding: const EdgeInsets.all(2),
                          child: Container(
                             width: 24, 
                             height: 24,
                             alignment: Alignment.center,
                             decoration: BoxDecoration(
                                 shape: BoxShape.circle,
                                 color: theme.colorScheme.surfaceContainerHighest,
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
                                ],
                              ),
                            ),
                          ),
                          if (widget.onChatTap != null)
                            if (widget.user.uid != ref.read(authRepositoryProvider).currentUser?.uid)
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
                                        border: Border.all(
                                          color: theme.colorScheme.surface,
                                          width: 1,
                                        ),
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
                              if (!isLocal) ...[
                                 Text(homeFlag, style: const TextStyle(fontSize: 16)),
                                 const SizedBox(width: 8),
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
                                  isLocal 
                                    ? () {
                                        final loc = widget.user.homeLocation;
                                        if (loc.city?.isNotEmpty ?? false) {
                                            final state = loc.state;
                                            if (state?.isNotEmpty ?? false) {
                                               return '${loc.city}, ${formatLocationName(state)}';
                                            }
                                            return loc.city!;
                                        }
                                        return formatFullAddress(loc.formattedAddress);
                                      }()
                                    : formatFullAddress(widget.user.homeLocation.formattedAddress),
                                  widget.searchQuery,
                                  theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurface.withOpacity(0.9),
                                  ),
                                  context
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              if (!isLocal) ...[
                                 Text(hostFlag, style: const TextStyle(fontSize: 16)),
                                 const SizedBox(width: 8),
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
                                      final countryCode = widget.user.hostCountryCode;
                                      if (countryCode != null && country_data.hasStateLevelHierarchyFromData(countryCode)) {
                                         return formatFullAddress(loc.formattedAddress);
                                      }
                                      if (loc.city?.isNotEmpty ?? false) {
                                         final fullCountry = formatLocationName(loc.country);
                                         return '${loc.city}, $fullCountry';
                                      }
                                      return formatFullAddress(loc.formattedAddress);
                                  }(),
                                  widget.searchQuery,
                                  theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurface.withOpacity(0.9),
                                  ),
                                  context
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
          GestureDetector(
            onTap: () {
                if (widget.user.currentLocation != null) {
                    final lat = widget.user.currentLocation!.geometry.location.lat;
                    final lng = widget.user.currentLocation!.geometry.location.lng;
                    _launchMaps(lat, lng);
                }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(bottomFlag, style: const TextStyle(fontSize: 18)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Row(
                            children: [
                              Text(
                                proximityLevel,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: proximityColor,
                                ),
                              ),
                              if (widget.user.currentLocation != null) ...[
                                const SizedBox(width: 8),
                                Text('•', style: TextStyle(color: theme.hintColor.withOpacity(0.3), fontSize: 12)),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                       Image.asset(
                                         'assets/icons/logo-original.png',
                                         width: 14,
                                         height: 14,
                                       ),
                                       if (widget.user.showCurrentLocationName != false && currentCityDisplay != null) ...[
                                         const SizedBox(width: 4),
                                         Flexible(
                                           child: Text(
                                             currentCityDisplay!,
                                             style: theme.textTheme.bodySmall?.copyWith(
                                               fontSize: 12,
                                               color: widget.isStatic 
                                                   ? theme.colorScheme.onSurface 
                                                   : theme.colorScheme.onSurfaceVariant,
                                               decoration: TextDecoration.none, 
                                             ),
                                             maxLines: 1,
                                             overflow: TextOverflow.ellipsis,
                                           ),
                                         ),
                                       ],
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
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: _formatDistanceMetric(distance).split(' ').first,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF74A383),
                          ),
                        ),
                        TextSpan(
                          text: ' km',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        TextSpan(
                          text: ' away',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
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
}
