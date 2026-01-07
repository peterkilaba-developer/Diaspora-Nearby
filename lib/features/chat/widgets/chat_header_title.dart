import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as material show Text;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/models/profile_data.dart';
import 'package:diaspora_nearby/data/countries.dart' as country_data;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:diaspora_nearby/models/chat.dart';
import 'package:diaspora_nearby/config/env.dart';

class ChatHeaderTitle extends StatefulWidget {
  final ProfileData? profile;
  final String fallbackTitle;
  final String? imageUrl;
  final ChatProfileImage? customImage;
  final Widget? customAvatarWidget;
  final int? memberCount;
  final String? eventStatus;
  final VoidCallback? onTap;

  const ChatHeaderTitle({
    super.key,
    this.profile,
    required this.fallbackTitle,
    this.imageUrl,
    this.customImage,
    this.customAvatarWidget,
    this.memberCount,
    this.eventStatus,
    this.onTap,
  });

  @override
  State<ChatHeaderTitle> createState() => _ChatHeaderTitleState();
}

class _ChatHeaderTitleState extends State<ChatHeaderTitle> {
  String? _localTimeStr;
  String? _locationName;
  String? _countryFlag;
  Timer? _timer;
  int? _rawOffset;
  int? _dstOffset;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void didUpdateWidget(ChatHeaderTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile != widget.profile) {
      _initData();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _initData() {
    _updateLocationInfo();
    _fetchTimezone();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _updateTime());
  }

  void _updateLocationInfo() {
    if (widget.profile == null) return;

    final profile = widget.profile!;
    String? state;
    String? city;

    // 1. Determine City/State
    // Try Current Location First
    if (profile.currentLocation != null && profile.currentLocation!.city != null) {
      city = profile.currentLocation!.city;
      state = profile.currentLocation!.state;
    } 
    
    // Fallback to Host Location
    if (city == null || city.isEmpty) {
      city = profile.hostLocation.city;
      state = profile.hostLocation.state;
    }

    // 2. Determine Country Code (for Flag)
    // Fallback chain: Current GPS -> Top-level Host Country -> Host Location Object
    final countryCode = profile.currentLocation?.countryCode 
        ?? profile.hostCountryCode 
        ?? profile.hostLocation.countryCode;

    _countryFlag = _getFlag(countryCode);
    _locationName = _formatLocationName(city, countryCode, state);
  }

  String _formatLocationName(String? city, String? countryCode, String? state) {
    final displayCity = city != null && city.isNotEmpty ? city : '';
    final isThreeLevel = countryCode == 'US' || countryCode == 'CA';

    if (isThreeLevel && displayCity.isNotEmpty && state != null && state.isNotEmpty) {
      return '$displayCity, $state';
    }

    if (displayCity.isNotEmpty) {
      return displayCity;
    }

    if (state != null && state.isNotEmpty) {
      return state;
    }

    return '';
  }

  String? _getFlag(String? countryCode) {
    if (countryCode == null) return null;
    return country_data.getCountryByCode(countryCode)?.flag;
  }

  Future<void> _fetchTimezone() async {
    if (widget.profile == null) return;

    double? lat;
    double? lng;

    if (widget.profile!.currentLocation != null) {
      lat = widget.profile!.currentLocation!.geometry.location.lat;
      lng = widget.profile!.currentLocation!.geometry.location.lng;
    } else {
      lat = widget.profile!.hostLocation.geometry?.location.lat;
      lng = widget.profile!.hostLocation.geometry?.location.lng;
    }

    if (lat == null || lng == null) return;

    try {
      final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).round();
      const apiKey = Env.googleMapsApiKey;
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/timezone/json?location=$lat,$lng&timestamp=$timestamp&key=$apiKey',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          if (mounted) {
            setState(() {
              _rawOffset = (data['rawOffset'] as num?)?.toInt();
              _dstOffset = (data['dstOffset'] as num?)?.toInt();
            });
            _updateTime();
          }
        }
      }
    } catch (e) {
      // Silently fail
    }
  }

  void _updateTime() {
    if (_rawOffset == null || _dstOffset == null) return;

    final nowUtc = DateTime.now().toUtc();
    final totalOffsetSeconds = _rawOffset! + _dstOffset!;
    final userTime = nowUtc.add(Duration(seconds: totalOffsetSeconds));
    final timeFormatter = DateFormat('h:mm a');
    final formattedTime = timeFormatter.format(userTime).toLowerCase();

    if (mounted) {
      setState(() {
        _localTimeStr = formattedTime;
      });
    }
  }

  Widget _buildAvatar(ThemeData theme) {
    if (widget.customAvatarWidget != null) {
      return widget.customAvatarWidget!;
    }

    if (widget.customImage != null) {
      final img = widget.customImage!;
      if (img.type == 'flag' || img.type == 'emoji') {
        return Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.transparent,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: material.Text(img.value, style: const TextStyle(fontSize: 18)),
        );
      } else if (img.type == 'icon' || img.type == 'gradient-icon') {
        return Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: img.gradientFrom != null && img.gradientTo != null
                ? LinearGradient(
                    colors: [
                      Color(int.parse(img.gradientFrom!.replaceAll('#', '0xFF'))),
                      Color(int.parse(img.gradientTo!.replaceAll('#', '0xFF'))),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: img.backgroundColor != null
                ? Color(int.parse(img.backgroundColor!.replaceAll('#', '0xFF')))
                : theme.colorScheme.primary,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Icon(LucideIcons.users, color: Colors.white, size: 18),
        );
      }
    }

    final photoUrl = widget.imageUrl ?? widget.profile?.profileImage;
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.transparent,
        ),
        clipBehavior: Clip.antiAlias,
        child: CachedNetworkImage(
          imageUrl: photoUrl,
          fit: BoxFit.cover,
          placeholder: (context, url) => Center(
            child: material.Text(
              (widget.profile?.firstName ?? widget.fallbackTitle)[0].toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          errorWidget: (context, url, error) => const Icon(LucideIcons.user),
        ),
      );
    }

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.transparent,
      ),
      alignment: Alignment.center,
      child: material.Text(
        (widget.profile?.firstName ?? widget.fallbackTitle)[0].toUpperCase(),
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.profile == null &&
        widget.imageUrl == null &&
        widget.customImage == null &&
        widget.customAvatarWidget == null) {
      return material.Text(
        widget.fallbackTitle,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      );
    }

    final fullName = widget.profile != null
        ? '${widget.profile!.firstName} ${widget.profile!.lastName}'
        : widget.fallbackTitle;

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: _buildAvatar(theme),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                material.Text(
                  fullName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    height: 1.1,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if ((_localTimeStr != null || (_locationName != null && _locationName!.isNotEmpty))) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (_countryFlag != null) ...[
                        material.Text(
                          _countryFlag!,
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: material.Text(
                          _localTimeStr != null && _locationName != null && _locationName!.isNotEmpty
                              ? '$_localTimeStr in $_locationName'
                              : (_locationName ?? ''),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color?.withAlpha(204),
                            fontSize: 12,
                            height: 1.1,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                if (widget.eventStatus != null) ...[
                  const SizedBox(height: 2),
                  material.Text(
                    widget.eventStatus!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      height: 1.1,
                    ),
                  ),
                ] else if (widget.memberCount != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.handshake_outlined, size: 12, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      material.Text(
                        '${widget.memberCount} members',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          height: 1.1,
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
    );
  }
}
