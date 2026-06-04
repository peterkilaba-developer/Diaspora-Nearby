import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/events/models/event_data.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/events/repository/event_repository.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart'; // [FIX] Added import
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart'; // [FIX] Added LucideIcons import

class EventAttendeesScreen extends ConsumerStatefulWidget {
  final String eventId;
  final Event? event;

  const EventAttendeesScreen({super.key, required this.eventId, this.event});

  @override
  ConsumerState<EventAttendeesScreen> createState() =>
      _EventAttendeesScreenState();
}

class _EventAttendeesScreenState extends ConsumerState<EventAttendeesScreen> {
  @override
  Widget build(BuildContext context) {
    // If event is passed, use its attendees list directly or fetch fresh.
    // Fetching fresh is better.
    final eventRepo = ref.watch(eventRepositoryProvider);
    final profileRepo = ref.read(profileRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Attendees')),
      body: FutureBuilder<Event?>(
        future: eventRepo.getEvent(widget.eventId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final event = snapshot.data;
          if (event == null ||
              event.attendees == null ||
              event.attendees!.isEmpty) {
            return const Center(child: Text('No attendees yet.'));
          }

          final attendeeIds = event.attendees!;

          // Fetch profiles for all attendees
          return FutureBuilder<List<ProfileData?>>(
            future: Future.wait(
              attendeeIds.map((uid) => profileRepo.getUserProfile(uid)),
            ),
            builder: (context, profileSnapshot) {
              if (profileSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final profiles =
                  profileSnapshot.data?.whereType<ProfileData>().toList() ?? [];

              if (profiles.isEmpty) {
                return const Center(
                  child: Text('No attendees (profiles not found).'),
                );
              }

              // [NEW] Congratulatory Message
              final currentUserId = ref
                  .read(authRepositoryProvider)
                  .currentUser
                  ?.uid;
              if (profiles.length == 1 && profiles.first.uid == currentUserId) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.3),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            LucideIcons.partyPopper,
                            size: 48,
                            color: Colors.amber,
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Congratulations!',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'You are the first attendee of this event!\nShare it to bring more people.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.separated(
                padding: EdgeInsets.only(
                  left: 8,
                  right: 8,
                  top: 16,
                  bottom: 16 + MediaQuery.of(context).padding.bottom,
                ),
                itemCount: profiles.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final profile = profiles[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: CachedNetworkImageProvider(
                        profile.profileImage,
                      ),
                      child: null,
                    ),
                    title: Text('${profile.firstName} ${profile.lastName}'),
                    subtitle: Text(profile.bio ?? ''),
                    onTap: () => context.push('/profile/${profile.uid}'),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
