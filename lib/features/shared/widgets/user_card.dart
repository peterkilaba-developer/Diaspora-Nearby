import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:diaspora_nearby/models/profile_data.dart';
import 'package:diaspora_nearby/data/countries.dart' as country_data;
import 'package:diaspora_nearby/features/shared/ui/glass_container.dart';

class UserCardView extends StatefulWidget {
  final ProfileData user;
  final VoidCallback? onNameTap;
  final VoidCallback? onChatTap;
  final String? searchQuery; // Optional search query for highlighting
  final double? distanceKm; // Optional distance override for search results
  final File? localImage; // Optional local image override
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
  });

  @override
  State<UserCardView> createState() => _UserCardViewState();
}

class _UserCardViewState extends State<UserCardView> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
    if (query == null || query.isEmpty) {
      return Text(
        name,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final lowerName = name.toLowerCase();
    final lowerQuery = query.toLowerCase();
    if (!lowerName.contains(lowerQuery)) {
      return Text(name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold));
    }

    final startIndex = lowerName.indexOf(lowerQuery);
    final endIndex = startIndex + lowerQuery.length;

    return RichText(
      text: TextSpan(
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.textTheme.titleMedium?.color,
        ),
        children: [
          TextSpan(text: name.substring(0, startIndex)),
          TextSpan(
            text: name.substring(startIndex, endIndex),
            style: TextStyle(
              backgroundColor: theme.colorScheme.primaryContainer,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          TextSpan(text: name.substring(endIndex)),
        ],
      ),
    );
  }

  String _getProximityLevel(double distanceKm) {
    if (widget.isStatic) return 'City';
    if (distanceKm <= 10) return 'Nearby';
    if (distanceKm <= 50) return 'Far';
    if (distanceKm <= 200) return 'Farther';
    return 'Farthest';
  }
  
  Color _getProximityColor(String level, bool isDark, ThemeData theme) {
    if (widget.isStatic) return isDark ? Colors.white70 : Colors.black87;
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
    double meters = km * 1000;
    return km >= 1 ? '${km.toStringAsFixed(1)} km' : '${meters.round()} m';
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
    
    // Bottom bar flag - priority: currentLocation country â hostLocation country
    String bottomFlag = '';
    if (widget.user.currentLocation?.countryCode != null) {
      bottomFlag = _getCountryFlag(widget.user.currentLocation!.countryCode);
    }
    if (bottomFlag.isEmpty || bottomFlag == 'ð') {
      bottomFlag = hostFlag;
    }
    
    // Calculate distance and proximity
    final distance = widget.distanceKm ?? 0.0;
    final proximityLevel = _getProximityLevel(distance);
    final proximityColor = _getProximityColor(proximityLevel, isDark, theme);
    
    // Format current city display
    String? currentCityDisplay;
    final city = widget.user.currentLocation?.city;
    if (city != null && city.isNotEmpty) {
      final state = widget.user.currentLocation?.state;
      final countryCode = widget.user.currentLocation?.countryCode;
      
      // Check if it's a 3-level country and has state
      if (countryCode != null && 
          country_data.hasStateLevelHierarchyFromData(countryCode) &&
          state != null &&
          state.isNotEmpty) {
        final country = country_data.getCountryByCode(countryCode);
        currentCityDisplay = '$city, $state, ${country?.name ?? countryCode}';
      } else {
        final country = country_data.getCountryByCode(countryCode ?? '');
        currentCityDisplay = '$city, ${country?.name ?? countryCode ?? ''}';
      }
    } else if (widget.user.hostLocation.formattedAddress.isNotEmpty) {
      // Fallback to host location city
      final parts = widget.user.hostLocation.formattedAddress.split(',');
      currentCityDisplay = parts.isNotEmpty ? parts[0].trim() : null;
    }

    return GlassContainer(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      padding: EdgeInsets.zero, // No padding on container - handled by inner Padding
      child: Column(
        children: [
          // Main content row with padding
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 8, top: 16, bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: Profile Photo (80x96, 10px radius)
                GestureDetector(
                onTap: () {
                  if (widget.user.profileImage.isNotEmpty && widget.user.profileImage.startsWith('http')) {
                    _showFullScreenImage(context);
                  } else if (widget.onNameTap != null) {
                    widget.onNameTap!();
                  }
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 80,
                    height: 96,
                    color: theme.colorScheme.surfaceVariant,
                    child: widget.localImage != null
                      ? Image.file(
                          widget.localImage!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildInitials(theme),
                        )
                      : (widget.user.profileImage.isNotEmpty && widget.user.profileImage.startsWith('http'))
                        ? Image.network(
                            widget.user.profileImage,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  value: loadingProgress.expectedTotalBytes != null
                                      ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                      : null,
                                ),
                              );
                            },
                            errorBuilder: (_, error, ___) {
                              return _buildInitials(theme);
                            },
                          )
                        : _buildInitials(theme),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              
              // Right: Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name row with chat button
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: widget.onNameTap,
                            child: _buildHighlightedName(
                              '${widget.user.firstName} ${widget.user.lastName}',
                              widget.searchQuery,
                              theme,
                            ),
                          ),
                        ),
                        // Chat button with online indicator
                        GestureDetector(
                          onTap: widget.onChatTap,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.transparent,
                                ),
                                child: Icon(
                                  LucideIcons.messageCircle,
                                  size: 20,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              // Online status dot
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
                    
                    // Home location: Flag + "From" + address
                    Row(
                      children: [
                        Text(homeFlag, style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 8),
                        Text(
                          'From',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            widget.user.homeLocation.formattedAddress,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface.withOpacity(0.9),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Host location: Flag + "Lives in" + address
                    Row(
                      children: [
                        Text(hostFlag, style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 8),
                        Text(
                          'Lives in', // â FIXED: was "Living in"
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            () {
                               final loc = widget.user.hostLocation;
                               // hostLocation is required in ProfileData
                               final countryCode = widget.user.hostCountryCode;
                               if (countryCode != null && country_data.hasStateLevelHierarchyFromData(countryCode)) {
                                  // We should try to extract city, state, country from formattedAddress or use components if we had them.
                                  // For now, if it's already a full address, we might need a helper to format it.
                                  // If the formattedAddress contains country, we are good.
                                  return loc.formattedAddress;
                               }
                               return (loc.city?.isNotEmpty ?? false) ? '${loc.city}, ${loc.country}' : loc.formattedAddress;
                            }(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface.withOpacity(0.9),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          ),  // End Padding
          // Bottom Status Bar - Full width, flush with card edges
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(8),
                bottomRight: Radius.circular(8),
                topLeft: Radius.zero,
                topRight: Radius.zero,
              ), // Top radius 0 for seamless integration
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Left side - Flag, proximity, and current location
                Expanded(
                  child: Row(
                    children: [
                      // Country flag
                      Text(bottomFlag, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      
                      // Proximity and current location column
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Proximity level
                            Text(
                              proximityLevel,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: proximityColor,
                              ),
                            ),
                            // Current location with GPS icon
                            if (currentCityDisplay != null) ...[
                              const SizedBox(height: 4),
                                Row(
                                  children: [
                                    GestureDetector(
                                      onTap: () {
                                          if (widget.user.currentLocation != null) {
                                              final lat = widget.user.currentLocation!.geometry.location.lat;
                                              final lng = widget.user.currentLocation!.geometry.location.lng;
                                              _launchMaps(lat, lng);
                                          }
                                      },
                                      child: Row(
                                        children: [
                                           widget.isStatic
                                                ? Icon(
                                                    LucideIcons.mapPin,
                                                    size: 14,
                                                    color: theme.colorScheme.primary,
                                                  )
                                                : ScaleTransition(
                                                    scale: _animation,
                                                    child: Icon(
                                                      LucideIcons.mapPin,
                                                      size: 14,
                                                      color: theme.colorScheme.primary,
                                                    ),
                                                  ),
                                            const SizedBox(width: 6),
                                            Text(
                                              currentCityDisplay,
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                fontSize: 12,
                                                color: widget.isStatic 
                                                    ? theme.colorScheme.onSurface 
                                                    : theme.colorScheme.onSurfaceVariant,
                                                // [REQUEST] Remove underline
                                                decoration: TextDecoration.none, 
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Right side - Distance and navigation
                Row(
                  children: [
                    // Distance info column
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatDistanceImperial(distance),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          _formatDistanceMetric(distance),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 6),
                    
                    // "away" text
                    Text(
                      'away',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 6),
                    
                    // Navigation button
                    GestureDetector(
                      onTap: () {
                         if (widget.user.currentLocation != null) {
                            final lat = widget.user.currentLocation!.geometry.location.lat;
                            final lng = widget.user.currentLocation!.geometry.location.lng;
                            _launchMaps(lat, lng);
                         }
                      },
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.transparent,
                        ),
                        child: Icon(
                          LucideIcons.navigation,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}



