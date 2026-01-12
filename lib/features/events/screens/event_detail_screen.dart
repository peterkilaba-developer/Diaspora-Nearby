import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:diaspora_nearby/models/event_data.dart';
import 'package:diaspora_nearby/features/events/repository/event_repository.dart';


import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:uuid/uuid.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/organization/repository/organization_repository.dart';

class EventDetailScreen extends ConsumerStatefulWidget {
  final String eventId;
  final Event? event;

  const EventDetailScreen({super.key, required this.eventId, this.event});

  @override
  ConsumerState<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends ConsumerState<EventDetailScreen> {
  bool _isRsvpLoading = false;

  void _openDirections(String location) async {
    final query = Uri.encodeComponent(location);
    final googleMapsUrl = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$query');
    final appleMapsUrl = Uri.parse('http://maps.apple.com/?daddr=$query');

    if (await canLaunchUrl(googleMapsUrl)) {
      await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
    } else if (await canLaunchUrl(appleMapsUrl)) {
      await launchUrl(appleMapsUrl, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventRepo = ref.watch(eventRepositoryProvider);
    final theme = Theme.of(context);


    final asyncEvent = ref.watch(eventDetailsProvider(widget.eventId));
    final event = asyncEvent.value ?? widget.event;

    if (event == null) {
       if (asyncEvent.isLoading) {
         return const Scaffold(body: Center(child: CircularProgressIndicator()));
       }
       return Scaffold(
         appBar: AppBar(),
         body: const Center(child: Text('Event not found')),
       );
    }
    
    // Parse Dates (Robustly, handling potentials)
    DateTime? startDate;
    try {
      startDate = DateTime.parse('${event.startDate} ${event.startTime}');
    } catch (_) {
      try { startDate = DateTime.parse(event.startDate); } catch (_) {}
    }

    final dateStr = startDate != null ? DateFormat('EEE, MMM d, y').format(startDate) : event.startDate;
    
    // Determine Display Time (Am/Pm)
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
    
    final displayStartTime = formatToAmPm(event.startTime);
    String? displayEndTime;
    String? endDateStr;

    if (event.endDate != null && event.endTime != null) {
       try {
          final end = DateTime.parse('${event.endDate!} ${event.endTime!}');
          endDateStr = DateFormat('EEE, MMM d, y').format(end);
          displayEndTime = formatToAmPm(event.endTime!);
       } catch (_) {
          // Fallback
          endDateStr = event.endDate;
          displayEndTime = event.endTime;
       }
    } else {
        // Fallback default end (3h later) logic from card? 
        // Details page should explicitly show what IS there.
        // If null, we might show "Until Late" or calculate it.
        // For consistency with card "starts in", we kept that logic in model.
        // Visual consistency:
        endDateStr = endDateStr ?? dateStr; // Same day default
        
        if (startDate != null) {
           final end = startDate.add(const Duration(hours: 3));
           displayEndTime = DateFormat('h:mm a').format(end); 
        } else {
           displayEndTime = 'Late';
        }
    }

    return Scaffold(
      body: SafeArea(
            top: false, // SliverAppBar handles top notch
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: 200,
                  pinned: true,
                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            theme.colorScheme.primary.withValues(alpha: 0.8),
                            theme.colorScheme.primaryContainer,
                          ],
                        ),
                      ),
                      child: Center(
                        child: Hero(
                          tag: 'event_image_${event.id}',
                          child: CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.white,
                            backgroundImage: event.imageUrl != null 
                                ? CachedNetworkImageProvider(event.imageUrl!) 
                                : null,
                            child: event.imageUrl == null
                                ? Icon(LucideIcons.calendar, size: 40, color: theme.colorScheme.primary)
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                  leading: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: CircleAvatar(
                      backgroundColor: Colors.black.withValues(alpha: 0.4),
                      child: IconButton(
                        icon: const Icon(LucideIcons.arrowLeft, color: Colors.white, size: 20),
                        onPressed: () => context.pop(),
                      ),
                    ),
                  ),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: CircleAvatar(
                        backgroundColor: Colors.black.withValues(alpha: 0.4),
                        child: IconButton(
                          icon: const Icon(LucideIcons.share2, color: Colors.white, size: 20),
                          onPressed: () {}, 
                        ),
                      ),
                    ),
                  ],
                ),

                // Content
                SliverToBoxAdapter(
                  child: Transform.translate(
                    offset: const Offset(0, -30),
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Category & Status row
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                child: Text(
                                  event.category.toUpperCase(),
                                  style: TextStyle(
                                    color: theme.colorScheme.primary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              if (event.getStatusBadgeInfo()['text'] != null)
                                Text(
                                  (event.getStatusBadgeInfo()['text'] as String).toUpperCase(),
                                  style: TextStyle(
                                    color: event.getStatusBadgeInfo()['color'] == 'green' 
                                        ? Colors.green 
                                        : theme.colorScheme.primary, 
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Title
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              event.title,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.5,
                                fontSize: 17,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Organizer Section (Moved from bottom)
                          Consumer(
                             builder: (context, ref, _) {
                              final currentUserId = ref.watch(authRepositoryProvider).currentUser?.uid;

                              // [NEW] Organization Display Logic
                              if (event.organizationId != null) {
                                final orgAsync = ref.watch(organizationByIdProvider(event.organizationId!));
                                return orgAsync.when(
                                  data: (org) {
                                    if (org == null) return const SizedBox.shrink();
                                    return InkWell(
                                      onTap: () {
                                         // TODO: Navigate to Org Profile if needed
                                      },
                                      borderRadius: BorderRadius.circular(16),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        child: Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 18,
                                              backgroundImage: (org['logoUrl'] ?? org['profileImage']) != null
                                                  ? CachedNetworkImageProvider(org['logoUrl'] ?? org['profileImage'])
                                                  : null,
                                              child: (org['logoUrl'] ?? org['profileImage']) == null
                                                  ? const Icon(LucideIcons.building2, size: 18)
                                                  : null,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Organized by',
                                                    style: theme.textTheme.labelSmall?.copyWith(
                                                      color: theme.colorScheme.primary,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                  Text(
                                                    org['name'] ?? org['businessName'] ?? event.organizationName ?? 'Organization',
                                                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                  loading: () => const SizedBox(height: 40, child: Center(child: LinearProgressIndicator())),
                                  error: (_, __) => const SizedBox.shrink(),
                                );
                              }

                              final creatorProfileAsync = ref.watch(userProfileByIdProvider(event.creatorId));
                              
                              return creatorProfileAsync.when(
                                data: (profile) {
                                  return InkWell(
                                    onTap: () => context.push('/profile/${event.creatorId}'),
                                    borderRadius: BorderRadius.circular(16),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Column(
                                        children: [
                                          Row(
                                            children: [
                                              CircleAvatar(
                                                radius: 18,
                                                backgroundImage: profile?.profileImage != null
                                                    ? CachedNetworkImageProvider(profile!.profileImage!)
                                                    : null,
                                                child: profile?.profileImage == null
                                                    ? const Icon(LucideIcons.user, size: 18)
                                                    : null,
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Organized by',
                                                      style: theme.textTheme.labelSmall?.copyWith(
                                                        color: theme.colorScheme.primary,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                    Text(
                                                      '${profile?.firstName ?? 'Event'} ${profile?.lastName ?? 'Organizer'}',
                                                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              if (currentUserId != event.creatorId)
                                                IconButton(
                                                  icon: const Icon(LucideIcons.messageCircle, size: 20),
                                                  onPressed: () => context.push('/chat/direct/${event.creatorId}'),
                                                  color: theme.colorScheme.primary,
                                                  visualDensity: VisualDensity.compact,
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                                loading: () => const SizedBox(height: 40, child: Center(child: LinearProgressIndicator())),
                                error: (_, __) => const SizedBox.shrink(),
                              );
                            },
                          ),
                          
                          const SizedBox(height: 8),

                          // Stats (Going • Interested) - Synced with EventCard
                          Padding(
                            padding: const EdgeInsets.only(left: 8, right: 8, top: 8, bottom: 24), // Added 16px extra bottom padding
                            child: Row(
                              children: [
                                 Icon(LucideIcons.users, size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                                 const SizedBox(width: 8),
                                 Text(
                                   '${event.attendeeCount ?? event.attendees?.length ?? 0} going • ${event.interested?.length ?? 0} interested',
                                   style: theme.textTheme.bodyMedium?.copyWith(
                                     color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                     fontWeight: FontWeight.w500,
                                   ),
                                 ),
                              ],
                            ),
                          ),

                          // Logistics Cards
                          // Split Date & Time
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Start', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 10)),
                                      Text(dateStr, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 2), // Tighter spacing like card
                                      Row(
                                        children: [
                                          Icon(LucideIcons.clock, size: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              displayStartTime, 
                                              style: theme.textTheme.labelSmall?.copyWith(
                                                color: theme.colorScheme.onSurface.withValues(alpha: 0.6), 
                                                fontWeight: FontWeight.w600
                                              ),
                                              maxLines: 1, 
                                              overflow: TextOverflow.ellipsis
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8), // 8px spacer like card (was 12)
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(12), // 12px radius like card (was 16)
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('End', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 10)),
                                      Text(endDateStr ?? '', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Icon(LucideIcons.clock, size: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              displayEndTime ?? '', 
                                              style: theme.textTheme.labelSmall?.copyWith(
                                                color: theme.colorScheme.onSurface.withValues(alpha: 0.6), 
                                                fontWeight: FontWeight.w600
                                              ),
                                              maxLines: 1, 
                                              overflow: TextOverflow.ellipsis
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
                          
                          // [NEW] 16px padding
                          const SizedBox(height: 16),
                          
                          // Two-Row Address Card (Restructured)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Left: Icon
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(LucideIcons.mapPin, color: Colors.orange, size: 20),
                                ),
                                const SizedBox(width: 12),
                                // Right: Content Column (Name, Address, City, Distance, Directions)
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Venue Name
                                      Text(
                                        (event.venueName != null && event.venueName!.isNotEmpty) 
                                            ? event.venueName! 
                                            : 'Event Location',
                                        style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 4),
                                      
                                      // Address (Cleaned: Remove City/State/Country duplication)
                                      if (event.venueAddress != null && event.venueAddress!.isNotEmpty)
                                        Text(
                                          event.venueAddress!.split(',').first.trim(),
                                          style: TextStyle(
                                            fontSize: 12, 
                                            color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                                            height: 1.3,
                                          ),
                                        )
                                      else if (event.location.isNotEmpty)
                                        Text(
                                          event.location.split(',').first.trim(),
                                            style: TextStyle(
                                            fontSize: 12, 
                                            color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                                            height: 1.3,
                                          ),
                                        ),
                                      
                                      // City/State (Full Standard Display)
                                      const SizedBox(height: 4),
                                      Text(
                                        [
                                          event.venueCity,
                                          event.venueState,
                                          event.venueCountry
                                        ].where((e) => e != null && e.isNotEmpty).join(', '),
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                          fontSize: 10,
                                        ),
                                      ),

                                      const SizedBox(height: 16),
                                      const Divider(height: 1), 
                                      const SizedBox(height: 12),

                                      // Bottom Nav Bar: Distance (Left) | Directions (Right)
                                      // Now inside this column, so it matches indentation
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          // Left: Distance
                                          if (event.distance != null)
                                            Text(
                                              '${event.distance!.toStringAsFixed(1)}km Away',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.orange,
                                              ),
                                            )
                                          else
                                            const SizedBox.shrink(),

                                          // Right: Navigation Action
                                          InkWell(
                                            onTap: () => _openDirections(event.location),
                                            borderRadius: BorderRadius.circular(8),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    'Get Directions', 
                                                    style: theme.textTheme.labelMedium?.copyWith(
                                                      color: Colors.orange,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  const Icon(LucideIcons.navigation, size: 14, color: Colors.orange),
                                                ],
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
                          ),
                          const SizedBox(height: 24),

                          // About Section
                          Text(
                            'About this event',
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            event.description,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                              height: 1.6,
                            ),
                          ),
                          
                          // Business Details (If verified)
                          Consumer(
                             builder: (context, ref, _) {
                              final creatorProfileAsync = ref.watch(userProfileByIdProvider(event.creatorId));
                              return creatorProfileAsync.maybeWhen(
                                data: (profile) {
                                  if (profile?.businessProfile?.isBusinessVerified == true) {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 24),
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              theme.colorScheme.primary.withOpacity(0.05),
                                              theme.colorScheme.secondary.withOpacity(0.05),
                                            ],
                                          ),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: theme.colorScheme.primary.withOpacity(0.1)),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(LucideIcons.building2, size: 16, color: theme.colorScheme.primary),
                                                const SizedBox(width: 8),
                                                Text(
                                                  profile?.businessProfile?.businessName ?? 'Verified Business',
                                                  style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                                                ),
                                                const Spacer(),
                                                const Icon(LucideIcons.checkCircle2, size: 16, color: Colors.green),
                                              ],
                                            ),
                                            if (profile?.businessProfile?.businessDescription != null) ...[
                                              const SizedBox(height: 8),
                                              Text(
                                                profile!.businessProfile!.businessDescription,
                                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                                orElse: () => const SizedBox.shrink(),
                              );
                             },
                          ),
                          const SizedBox(height: 120), // Padding for FAB
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
      ),
      bottomNavigationBar: _buildStickyActionBar(context, event),
    );
  }



  Widget _buildStickyActionBar(BuildContext context, Event event) {
    final theme = Theme.of(context);
    final userAsync = ref.watch(authStateProvider);
    // Fallback to synchronous currentUser if stream is loading
    final currentUserId = userAsync.value?.uid ?? ref.read(authRepositoryProvider).currentUser?.uid;
    
    // DEBUG LOG
    print('DEBUG: StickyBar Build - Loading: $_isRsvpLoading, UserId: $currentUserId, AsyncLoading: ${userAsync.isLoading}');

    final isAttending = event.attendees?.contains(currentUserId) ?? false;
    final isFull = event.maxAttendees != null && (event.attendeeCount ?? 0) >= event.maxAttendees!;
    final isPast = DateTime.parse(event.startDate).isBefore(DateTime.now());

    // Chat Navigation Logic
    // We navigate to the specific chat based on event.chatId
    // If it doesn't exist, we might need to create it or handle it.
    // Assuming backend/creation ensures chatId exists.
    
    return Container(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
           BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5)),
        ],
      ),
      child: Row(
        children: [
           Column(
             mainAxisSize: MainAxisSize.min,
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
                Text(
                  event.isPaid == true ? '\$${event.ticketPrice}' : 'Free',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                   event.isPaid == true ? 'per person' : 'entry',
                   style: theme.textTheme.bodySmall,
                ),
             ],
           ),
           const Spacer(),
           
           // Chat Button (Only if attending or if chat exists)
           if (isAttending || currentUserId == event.creatorId)
             Padding(
               padding: const EdgeInsets.only(right: 12.0),
               child: IconButton.filledTonal(
                  onPressed: () {
                     // Check if chatId is present, if not use event.id as fallback for now or handle creation
                     final chatId = event.chatId ?? event.id;
                     context.push('/chats/$chatId');
                  },
                  icon: const Icon(LucideIcons.messageCircle),
                  tooltip: 'Event Chat',
               ),
             ),

           // RSVP Button
           Expanded(
             flex: 2,
             child: FilledButton.icon(
                onPressed: (_isRsvpLoading || currentUserId == null) 
                  ? null 
                   : () async {
                    setState(() => _isRsvpLoading = true);
                    
                    try {
                      final repo = ref.read(eventRepositoryProvider);
                      // Use the same fallback logic for profile/user
                      final userAsync = ref.read(authStateProvider);
                      final uid = userAsync.value?.uid ?? ref.read(authRepositoryProvider).currentUser?.uid;
                      
                      if (uid == null) {
                         print('DEBUG: User ID is null in onPressed');
                         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please log in to RSVP.')));
                         setState(() => _isRsvpLoading = false);
                         return;
                      }

                      if (isAttending) {
                        await repo.leaveEvent(event.id, uid);
                      } else {
                        await repo.joinEvent(event.id, uid);
                      }
                      
                      // Force refresh and WAIT for new data
                      print('RSVP: Refreshing data...');
                      await ref.refresh(eventDetailsProvider(event.id).future);
                      print('RSVP: Data refreshed.');
                      
                      if (mounted) setState(() => _isRsvpLoading = false);
                    } catch (e) {
                      print('RSVP Error: $e');
                      if (mounted) setState(() => _isRsvpLoading = false);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                },
                style: FilledButton.styleFrom(
                   backgroundColor: isAttending 
                      ? theme.colorScheme.surfaceContainerHighest 
                      : (isFull ? theme.colorScheme.secondary : theme.colorScheme.primary),
                   foregroundColor: isAttending 
                      ? theme.colorScheme.onSurface 
                      : theme.colorScheme.onPrimary,
                   padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: _isRsvpLoading 
                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: isAttending ? theme.colorScheme.primary : theme.colorScheme.onPrimary))
                  : Icon(isAttending ? LucideIcons.check : (isFull ? LucideIcons.ban : LucideIcons.ticket)),
                label: Text(
                   isAttending ? 'Going' : (isFull ? 'Sold Out' : (event.isPaid == true ? 'Buy Ticket' : 'RSVP Now')),
                   style: const TextStyle(fontWeight: FontWeight.bold),
                ),
             ),
           ),
        ],
      ),
    );
  }
}
