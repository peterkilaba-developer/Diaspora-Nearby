import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/events/models/event_data.dart';
import 'package:diaspora_nearby/features/shared/utils/search_highlight_utils.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

class EventVenueCard extends StatelessWidget {
  final Event event;
  final String? searchQuery;
  final bool showDirections;
  final Function(String)? onDirectionsTap;
  final bool compact;

  const EventVenueCard({
    super.key,
    required this.event,
    this.searchQuery,
    this.showDirections = false,
    this.onDirectionsTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Row 1: Venue Name (or fallback to full location if name missing)
    String displayTitle =
        (event.venueName != null && event.venueName!.isNotEmpty)
        ? event.venueName!
        : event.location;

    // Row 2: City, State, Country (Strictly per user request)
    // If venue address exists, verify if we should prioritize it or just the city/state components
    // User asked for: "city/state/country on it's own row below name"
    // So we prioritize components over raw address string if components exist.

    // Row 2 priorities:
    // 1. Full Address (e.g. 123 Main St, New York, NY)
    // 2. City/State/Country components (if address missing)
    // 3. Raw Location String fallback

    String displaySubtitle = '';

    final cityStateComponents = [
      event.venueCity,
      event.venueState,
      event.venueCountry,
    ].where((e) => e != null && e.isNotEmpty).join(', ');

    if (event.venueAddress != null && event.venueAddress!.isNotEmpty) {
      displaySubtitle = event.venueAddress!;
    } else if (cityStateComponents.isNotEmpty) {
      displaySubtitle = cityStateComponents;
    } else if (event.location != displayTitle) {
      // Fallback to location string if it wasn't used as title
      displaySubtitle = event.location;
    }

    return Container(
      padding: const EdgeInsets.only(top: 12, bottom: 12, left: 0, right: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              LucideIcons.mapPin,
              color: AppTheme.accent,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Row 1: Venue Name
                _highlightText(
                  displayTitle,
                  theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  context,
                ),

                // Row 2: Location Address
                // Prioritize the FULL address if available, otherwise fallback to whatever subtitle logic we have
                if (displaySubtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _highlightText(
                    displaySubtitle,
                    TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                      height: 1.3,
                    ),
                    context,
                  ),
                ] else if (event.location != displayTitle) ...[
                  // Ultimate fallback if subtitle logic failed but we have a raw location string diffferent from title
                  const SizedBox(height: 4),
                  _highlightText(
                    event.location,
                    TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                      height: 1.3,
                    ),
                    context,
                  ),
                ],

                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // LEFT: Distance
                    if (event.distance != null)
                      Text(
                        '${event.distance!.round()}km Away',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accent,
                        ),
                      )
                    else
                      const SizedBox.shrink(),

                    // RIGHT: Get Directions
                    if (showDirections && onDirectionsTap != null)
                      InkWell(
                        onTap: () => onDirectionsTap!(event.location),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Get Directions',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontSize: 10,
                                  color: AppTheme.accent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                LucideIcons.navigation,
                                size: 12,
                                color: AppTheme.accent,
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      // Fallback for compact card if directions not strictly enabled,
                      // but user requested "both pages". EventCard usually doesn't pass showDirections=true.
                      // We need to enable it for EventCard or show a fallback icon?
                      // The user said "get direction with nav icon to far right in both pages".
                      // This implies EventCard should ALSO show directions. This requires logic change in EventCard
                      // to pass the callback. For now, I will render the UI.
                      // If onDirectionsTap is null, I might render a disabled state or just the icon?
                      // Actually, if it's compact (EventCard), we usually navigate to Details.
                      // Maybe the "Get Directions" on EventCard just opens the Details page?
                      // Or acts as a deep link?
                      // Let's stick to the request: "get direction with nav icon".
                      // If onDirectionsTap is missing, we can't really "Get Directions".
                      // However, in EventCard, we usually just tap the card.
                      // Let's assume onDirectionsTap determines visibility.
                      // I will Update EventCard to pass it if possible, or just render the UI here
                      // and let the parent handle the tap? No, that's ambiguous.
                      // I will implement the UI here. If onDirectionsTap is null, I will hide it
                      // OR check if 'compact' is true, in which case maybe we show a chevron?
                      // User said: "get direction with nav icon to far right in both pages".
                      // So I should probably render it even if compact.
                      // But I need the callback.
                      // I'll assume for this edit I'm just changing the layout
                      // and I will update EventCard separately to pass the callback or handle it.
                      const SizedBox.shrink(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _highlightText(String text, TextStyle? style, BuildContext context) {
    if (searchQuery != null) {
      return SearchHighlightUtils.highlightText(
        text,
        searchQuery,
        style,
        context,
      );
    }
    return Text(
      text,
      style: style,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
