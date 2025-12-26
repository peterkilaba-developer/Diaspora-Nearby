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


    return Scaffold(
      body: FutureBuilder<Event?>(
        initialData: widget.event,
        future: widget.event == null ? eventRepo.getEvent(widget.eventId) : null,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && widget.event == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final event = snapshot.data;
          if (event == null) {
            return Scaffold(
              appBar: AppBar(),
              body: const Center(child: Text('Event not found')),
            );
          }

          // Date formatting
          DateTime? startDate;
          try {
            startDate = DateTime.parse(event.startDate);
          } catch (_) {}
          
          
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

          return CustomScrollView(
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
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Title
                        Text(
                          event.title,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Logistics Cards
                        // Split Date & Time
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.1)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Start', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 8),
                                    Text(dateStr, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                                    Text(timeStr, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.1)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('End', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 8),
                                    Text(endDateStr, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                                    Text(endTimeStr, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        
                        // Two-Row Address Card
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.1)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(LucideIcons.mapPin, color: Colors.orange, size: 24),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (event.venueName != null && event.venueName!.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 4),
                                        child: Text(
                                          event.venueName!,
                                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    if (event.venueAddress != null && event.venueAddress!.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 4),
                                        child: Text(
                                          event.venueAddress!,
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
                                            height: 1.4,
                                          ),
                                        ),
                                      )
                                    else if (event.location.isNotEmpty)
                                       Padding(
                                        padding: const EdgeInsets.only(bottom: 4),
                                        child: Text(
                                          event.location,
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    Text(
                                      [
                                        event.venueCity,
                                        event.venueState,
                                        event.venueCountry
                                      ].where((e) => e != null && e.isNotEmpty).join(', '),
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(LucideIcons.navigation, color: Colors.orange),
                                onPressed: () => _openDirections(event.location),
                                style: IconButton.styleFrom(
                                   backgroundColor: Colors.orange.withValues(alpha: 0.1),
                                   padding: const EdgeInsets.all(8),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),

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
                        const SizedBox(height: 32),

                        // Organizer Section with Business Details
                        Consumer(
                           builder: (context, ref, _) {
                            final currentUserId = ref.watch(authRepositoryProvider).currentUser?.uid;
                            final creatorProfileAsync = ref.watch(userProfileByIdProvider(event.creatorId));
                            
                            return creatorProfileAsync.when(
                              data: (profile) {
                                final isVerifiedBusiness = profile?.businessProfile?.isBusinessVerified == true;
                                
                                return Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 24,
                                            backgroundImage: profile?.profileImage != null
                                                ? CachedNetworkImageProvider(profile!.profileImage!)
                                                : null,
                                            child: profile?.profileImage == null
                                                ? const Icon(LucideIcons.user, color: Colors.white)
                                                : null,
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Organized by',
                                                  style: theme.textTheme.labelMedium?.copyWith(
                                                    color: theme.colorScheme.primary,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                Text(
                                                  '${profile?.firstName ?? 'Event'} ${profile?.lastName ?? 'Organizer'}',
                                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (currentUserId != event.creatorId)
                                            IconButton(
                                              icon: const Icon(LucideIcons.messageCircle),
                                              onPressed: () => context.push('/chat/direct/${event.creatorId}'),
                                              color: theme.colorScheme.primary,
                                            ),
                                        ],
                                      ),
                                    ),
                                    
                                    // Business Expansion (Legacy Feature)
                                    if (isVerifiedBusiness) ...[
                                      const SizedBox(height: 12),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              theme.colorScheme.primary.withValues(alpha: 0.05),
                                              theme.colorScheme.secondary.withValues(alpha: 0.05),
                                            ],
                                          ),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.1)),
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
                                    ],
                                  ],
                                );
                              },
                              loading: () => const Center(child: CircularProgressIndicator()),
                              error: (_, __) => const SizedBox.shrink(),
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
          );
        },
      ),
      bottomNavigationBar: widget.event != null 
          ? _buildStickyActionBar(context, widget.event!)
          : FutureBuilder<Event?>(
              future: eventRepo.getEvent(widget.eventId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox.shrink();
                return _buildStickyActionBar(context, snapshot.data!);
              }
            ),
    );
  }



  Widget _buildStickyActionBar(BuildContext context, Event event) {
    final theme = Theme.of(context);
    final authRepo = ref.watch(authRepositoryProvider);
    final currentUserId = authRepo.currentUser?.uid;
    
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
           if (event.chatId != null && (isAttending || currentUserId == event.creatorId))
             Padding(
               padding: const EdgeInsets.only(right: 12.0),
               child: IconButton.filledTonal(
                  onPressed: () {
                     context.push('/chat/community/${event.chatId}?name=${Uri.encodeComponent(event.title)}&type=event');
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
                    if (isPast) return;
                    setState(() => _isRsvpLoading = true);
                    
                    try {
                      final repo = ref.read(eventRepositoryProvider);
                      final profile = ref.read(userProfileProvider).value;
                      if (profile == null) return;

                      if (isAttending) {
                        await repo.leaveEvent(event.id, currentUserId!);
                      } else {
                        await repo.joinEvent(event.id, currentUserId!);
                      }
                      
                      if (mounted) setState(() => _isRsvpLoading = false);
                    } catch (e) {
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
