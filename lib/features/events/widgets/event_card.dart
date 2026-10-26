import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:diaspora_nearby/features/events/models/event_data.dart';
import 'package:diaspora_nearby/features/shared/utils/search_highlight_utils.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:diaspora_nearby/features/events/widgets/event_venue_card.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/core/utils/location_utils.dart';

class EventCard extends ConsumerWidget {
  final Event event;
  final VoidCallback? onTap;
  final Widget? extraContent;
  final bool isAttending;
  final Position? userLocation;
  final bool isInterested;
  final VoidCallback? onInterestToggle;
  final bool isCreator;
  final VoidCallback? onEditTap;
  final String? searchQuery; // [NEW] for highlighting

  const EventCard({
    super.key,
    required this.event,
    this.isAttending = false,
    this.isInterested = false,
    this.userLocation,
    this.onTap,
    this.extraContent,
    this.onInterestToggle,
    this.isCreator = false,
    this.onEditTap,
    this.searchQuery,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Date parsing
    DateTime? startDate;
    try {
      startDate = DateTime.parse(event.startDate);
    } catch (_) {}

    final monthStr = startDate != null
        ? DateFormat('MMM').format(startDate).toUpperCase()
        : '';
    final dayStr = startDate != null ? DateFormat('d').format(startDate) : '';

    final dateStr = startDate != null
        ? DateFormat('EEE, MMM d, y').format(startDate)
        : event.startDate;
    final timeStr = event.startTime;

    // End Date Parsing
    DateTime? endDate;
    if (event.endDate != null) {
      try {
        endDate = DateTime.parse(event.endDate!);
      } catch (_) {}
    }
    final endDateStr = endDate != null
        ? DateFormat('EEE, MMM d, y').format(endDate)
        : dateStr;
    final endTimeStr = event.endTime ?? timeStr;

    // Time Formatting Helper
    String formatToAmPm(String time) {
      try {
        final parts = time.split(':');
        if (parts.length >= 2) {
          final hour = int.parse(parts[0]);
          final minute = int.parse(parts[1]);
          final dt = DateTime(2000, 1, 1, hour, minute);
          return DateFormat('h:mm a').format(dt);
        }
      } catch (_) {}
      return time;
    }

    final displayStartTime = formatToAmPm(timeStr);
    final displayEndTime = formatToAmPm(endTimeStr);

    // Compute distance dynamically in real time from GPS or logged-in user's profile
    final viewer = ref.watch(userProfileProvider).value;
    final livePos = ref.watch(liveUserPositionProvider).value ?? userLocation;
    event.distance = calculateEventDistanceKm(
      event,
      viewer: viewer,
      livePosition: livePos,
      fallbackDistanceKm: event.distance,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap:
              onTap ?? () => context.push('/events/${event.id}', extra: event),
          borderRadius: BorderRadius.circular(24),
          child: Ink(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image Section
                Stack(
                  children: [
                    Hero(
                      tag: 'event_image_${event.id}',
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                        child: Container(
                          height: 200,
                          width: double.infinity,
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: event.imageUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: event.imageUrl!,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                  errorWidget: (context, url, error) => Center(
                                    child: Icon(
                                      LucideIcons.image,
                                      size: 50,
                                      color: theme.colorScheme.outline,
                                    ),
                                  ),
                                )
                              : Center(
                                  child: Icon(
                                    LucideIcons.image,
                                    size: 50,
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                        ),
                      ),
                    ),

                    // Date Badge Overlay (Calendar Sheet Style)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              monthStr,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1,
                              ),
                            ),
                            Text(
                              dayStr,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                height: 1.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Entry Fee / Free Badge
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color:
                              event.isPaid == true &&
                                  (event.ticketPrice ?? 0) > 0
                              ? Colors.black.withValues(alpha: 0.65)
                              : Colors.green.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              event.isPaid == true &&
                                      (event.ticketPrice ?? 0) > 0
                                  ? LucideIcons.ticket
                                  : LucideIcons.sparkles,
                              size: 12,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              event.isPaid == true &&
                                      (event.ticketPrice ?? 0) > 0
                                  ? '\$${event.ticketPrice!.toStringAsFixed(event.ticketPrice! == event.ticketPrice!.roundToDouble() ? 0 : 2)}'
                                  : 'Free',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 0,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category & Status Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.1,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              event.category.toUpperCase(),
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          _buildStatusBadge(context),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Title
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: SearchHighlightUtils.highlightText(
                          event.title,
                          searchQuery,
                          theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                          context,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Stats (Going \u2022 Interested)
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 8,
                          top: 8,
                          bottom: 8,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              LucideIcons.users,
                              size: 14,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${event.attendeeCount ?? event.attendees?.length ?? 0}${event.maxAttendees != null ? " / ${event.maxAttendees}" : ""} going \u2022 ${event.interested?.length ?? 0} interested',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.6,
                                ),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Split Time
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Start',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                    ),
                                  ),
                                  Text(
                                    dateStr,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Row(
                                    children: [
                                      Icon(
                                        LucideIcons.clock,
                                        size: 10,
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: 0.6),
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          displayStartTime,
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: theme
                                                    .colorScheme
                                                    .onSurface
                                                    .withValues(alpha: 0.6),
                                                fontWeight: FontWeight.w600,
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
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'End',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                    ),
                                  ),
                                  Text(
                                    endDateStr,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Row(
                                    children: [
                                      Icon(
                                        LucideIcons.clock,
                                        size: 10,
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: 0.6),
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          displayEndTime,
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: theme
                                                    .colorScheme
                                                    .onSurface
                                                    .withValues(alpha: 0.6),
                                                fontWeight: FontWeight.w600,
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
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      EventVenueCard(
                        event: event,
                        searchQuery: searchQuery,
                        compact: true,
                        showDirections: true,
                        onDirectionsTap: (query) async {
                          final uri = Uri.parse(
                            'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}',
                          );
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri);
                          }
                        },
                      ),

                      // Creator Actions (Edit) vs Interested
                      if (isCreator && onEditTap != null) ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: onEditTap,
                            style: OutlinedButton.styleFrom(
                              side: BorderSide.none,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            icon: Icon(
                              LucideIcons.edit3,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                            label: Text(
                              'Edit Event',
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ] else if (onInterestToggle != null) ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: isAttending ? null : onInterestToggle,
                            style: OutlinedButton.styleFrom(
                              backgroundColor: isAttending
                                  ? Colors.green.withValues(alpha: 0.1)
                                  : (isInterested
                                        ? theme.colorScheme.primary.withValues(
                                            alpha: 0.1,
                                          )
                                        : null),
                              side: BorderSide.none,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            icon: Icon(
                              isAttending
                                  ? LucideIcons.checkCircle2
                                  : (isInterested
                                        ? LucideIcons.star
                                        : LucideIcons.star),
                              size: 16,
                              color: isAttending
                                  ? Colors.green
                                  : (isInterested
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurface),
                            ),
                            label: Text(
                              isAttending
                                  ? 'Going'
                                  : (isInterested
                                        ? 'Interested'
                                        : 'Interested?'),
                              style: TextStyle(
                                color: isAttending
                                    ? Colors.green
                                    : (isInterested
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurface),
                                fontWeight: (isAttending || isInterested)
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      ],

                      // Extra Content
                      if (extraContent != null) ...[
                        const SizedBox(height: 20),
                        extraContent!,
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context) {
    final theme = Theme.of(context);

    final statusInfo = event.getStatusBadgeInfo();
    final statusText = statusInfo['text'] as String?;
    final semanticColor = statusInfo['color'] as String?;

    if (statusText == null) return const SizedBox.shrink();

    // Map semantic color to Color
    Color badgeColor = theme.colorScheme.primary;
    if (semanticColor == 'green') badgeColor = Colors.green;

    // For default secondary, maybe orange?
    // Original code used theme.colorScheme.secondary mostly.

    return Text(
      statusText.toUpperCase(),
      style: TextStyle(
        color: badgeColor,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
      ),
    );
  }
}
