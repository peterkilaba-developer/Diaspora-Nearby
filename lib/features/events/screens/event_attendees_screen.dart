import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diaspora_nearby/features/events/models/event_data.dart';
import 'package:diaspora_nearby/features/events/repository/event_repository.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/shared/widgets/user_card.dart';
import 'package:diaspora_nearby/core/utils/location_utils.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

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
    final profileRepo = ref.read(profileRepositoryProvider);
    final eventRepo = ref.read(eventRepositoryProvider);
    final currentUserId = ref.watch(authRepositoryProvider).currentUser?.uid;
    final currentUserProfile =
        ref.watch(userProfileProvider).value ??
        (currentUserId != null
            ? profileRepo.getCachedProfile(currentUserId)
            : null);

    final fallbackAttendeeIds =
        widget.event?.attendees ??
        eventRepo.getCachedEvent(widget.eventId)?.attendees;

    return Scaffold(
      appBar: AppBar(title: const Text('Attendees')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('events')
            .doc(widget.eventId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData &&
              fallbackAttendeeIds == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data?.data();
          final attendeeIds =
              (data?['attendees'] as List?)?.whereType<String>().toList() ??
              fallbackAttendeeIds ??
              const <String>[];
          if (attendeeIds.isEmpty) {
            return const Center(child: Text('No attendees yet.'));
          }

          final cachedProfiles = attendeeIds
              .map((uid) => profileRepo.getCachedProfile(uid))
              .toList();
          final hasCachedProfiles = cachedProfiles.any((p) => p != null);

          // Fetch profiles for all attendees with synchronous cache seed
          return FutureBuilder<List<ProfileData?>>(
            initialData: hasCachedProfiles ? cachedProfiles : null,
            future: Future.wait(
              attendeeIds.map((uid) => profileRepo.getUserProfile(uid)),
            ),
            builder: (context, profileSnapshot) {
              final rawProfiles =
                  profileSnapshot.data ??
                  (hasCachedProfiles ? cachedProfiles : null);
              if (profileSnapshot.connectionState == ConnectionState.waiting &&
                  rawProfiles == null) {
                return const Center(child: CircularProgressIndicator());
              }

              final profiles =
                  (rawProfiles?.whereType<ProfileData>().toList() ?? [])
                      .map(
                        (p) => p.copyWith(
                          distance: calculateProfileDistanceKm(
                            currentUserProfile,
                            p,
                          ),
                        ),
                      )
                      .toList()
                    ..sort((a, b) {
                      final dA = a.distance ?? double.infinity;
                      final dB = b.distance ?? double.infinity;
                      return dA.compareTo(dB);
                    });

              if (profiles.isEmpty) {
                return const Center(
                  child: Text('No attendees (profiles not found).'),
                );
              }

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
                  return UserCardView(
                    user: profile,
                    distanceKm: profile.distance,
                    onNameTap: () => context.push(
                      '/profile/${profile.uid}',
                      extra: {'distance': profile.distance},
                    ),
                    onChatTap: (profile.uid == currentUserId)
                        ? null
                        : () => context.push('/chat/direct/${profile.uid}'),
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
