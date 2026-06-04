import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:diaspora_nearby/features/events/models/event_data.dart';

/// A self-contained, non-interactive event card designed for image capture
/// and sharing via the native share sheet. Mirrors the visual style of
/// [EventCard] but with a fixed width and branded footer.
class EventShareCard extends StatelessWidget {
  final Event event;

  const EventShareCard({super.key, required this.event});

  String _formatToAmPm(String time) {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
    final displayStartTime = _formatToAmPm(event.startTime);

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Event Image with Date Badge
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                child: Container(
                  height: 160,
                  width: double.infinity,
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: event.imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: event.imageUrl!,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Center(
                            child: Icon(
                              LucideIcons.image,
                              size: 50,
                              color: theme.colorScheme.outline,
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
                            LucideIcons.calendar,
                            size: 50,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                ),
              ),

              // Date Badge
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        monthStr,
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        dayStr,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Price Badge
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    event.isPaid == true
                        ? '\$${event.ticketPrice?.toStringAsFixed(0)}'
                        : 'FREE',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Content
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Category
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
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
                const SizedBox(height: 10),

                // Title
                Text(
                  event.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),

                // Date & Time Row
                Row(
                  children: [
                    Icon(
                      LucideIcons.calendar,
                      size: 14,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '$dateStr • $displayStartTime',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Location Row
                Row(
                  children: [
                    Icon(
                      LucideIcons.mapPin,
                      size: 14,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        event.venueName ?? event.location,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Attendees Row
                Row(
                  children: [
                    Icon(
                      LucideIcons.users,
                      size: 14,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${event.attendeeCount ?? event.attendees?.length ?? 0} going • ${event.interested?.length ?? 0} interested',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 12),

                // Branded Footer
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Image.asset(
                          'assets/icons/logo-sage-green-clean.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Join on Diaspora Nearby',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.hintColor,
                        fontWeight: FontWeight.bold,
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
