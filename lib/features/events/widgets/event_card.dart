import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:diaspora_nearby/models/event_data.dart';
import 'package:diaspora_nearby/features/shared/ui/glass_container.dart';
import 'package:geolocator/geolocator.dart';

// Helper for status text is not needed anymore as per new design


class EventCard extends StatelessWidget {
  final Event event;
  final bool isAttending;
  final Position? userLocation;
  final Widget? extraContent;
  final VoidCallback? onTap;

  const EventCard({
    super.key,
    required this.event,
    this.isAttending = false,
    this.userLocation,
    this.extraContent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Date parsing
    DateTime? startDate;
    try {
      startDate = DateTime.parse(event.startDate);
    } catch (_) {}

    final monthStr = startDate != null ? DateFormat('MMM').format(startDate).toUpperCase() : '';
    final dayStr = startDate != null ? DateFormat('d').format(startDate) : '';
    
    final dateStr = startDate != null ? DateFormat('EEE, MMM d, y').format(startDate) : event.startDate;
    final timeStr = event.startTime;

    // End Date Parsing
    DateTime? endDate;
    if (event.endDate != null) {
        try {
          endDate = DateTime.parse(event.endDate!);
        } catch (_) {}
    }
    final endDateStr = endDate != null ? DateFormat('EEE, MMM d, y').format(endDate) : dateStr;
    final endTimeStr = event.endTime ?? timeStr;

    return GestureDetector(
      onTap: onTap ?? () => context.push('/events/${event.id}', extra: event),
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
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
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image Section
            Stack(
              children: [
                Hero(
                  tag: 'event_image_${event.id}',
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
                              child: Icon(LucideIcons.image, size: 50, color: theme.colorScheme.outline),
                            ),
                          )
                        : Center(child: Icon(LucideIcons.image, size: 50, color: theme.colorScheme.outline)),
                  ),
                ),

                // Date Badge Overlay (Calendar Sheet Style)
                Positioned(
                  top: 16,
                  left: 16,
                  child: GlassContainer(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    borderRadius: BorderRadius.circular(12),
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

                // Price/Status Badge
                Positioned(
                  top: 16,
                  right: 16,
                  child: GlassContainer(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    borderRadius: BorderRadius.circular(30),
                    child: Text(
                      event.status == 'draft' 
                        ? 'DRAFT' 
                        : (event.isPaid == true ? '\$${event.ticketPrice?.toStringAsFixed(0)}' : 'FREE'),
                      style: TextStyle(
                        color: event.status == 'draft' ? theme.colorScheme.error : theme.colorScheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Content Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category & Split Time
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                       Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.1)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Start', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 10)),
                                  const SizedBox(height: 4),
                                  Text(dateStr, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  Text(timeStr, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline), maxLines: 1, overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.1)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('End', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 10)),
                                  const SizedBox(height: 4),
                                  Text(endDateStr, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  Text(endTimeStr, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline), maxLines: 1, overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Title
                  Text(
                    event.title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),

                  // Location Display (Premium 3-row layout)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(LucideIcons.mapPin, size: 16, color: theme.colorScheme.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (event.venueName != null && event.venueName!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Text(
                                    event.venueName!,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              if (event.venueAddress != null && event.venueAddress!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Text(
                                    event.venueAddress!,
                                    style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                )
                              else if (event.location.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Text(
                                    event.location,
                                    style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              Text(
                                [
                                  event.venueCity,
                                  event.venueState,
                                  event.venueCountry
                                ].where((e) => e != null && e.isNotEmpty).join(', '),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.outline.withValues(alpha: 0.8),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (event.distance != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Column(
                              children: [
                                Icon(LucideIcons.navigation, size: 16, color: theme.colorScheme.primary),
                                const SizedBox(height: 2),
                                Text(
                                  '${event.distance!.toStringAsFixed(1)} km',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                           Icon(LucideIcons.chevronRight, size: 16, color: theme.colorScheme.outline),
                      ],
                    ),
                  ),

                  // Extra Content (e.g. Action Buttons)
                  if (extraContent != null) ...[
                    const SizedBox(height: 20),
                    extraContent!,
                  ]
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
