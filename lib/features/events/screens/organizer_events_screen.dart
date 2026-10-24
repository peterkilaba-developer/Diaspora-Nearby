import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:diaspora_nearby/features/events/repository/event_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/events/widgets/event_card.dart';

class OrganizerEventsScreen extends StatelessWidget {
  const OrganizerEventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Events')),
      body: const OrganizerEventsList(),
    );
  }
}

class OrganizerEventsList extends ConsumerWidget {
  final EdgeInsetsGeometry padding;
  const OrganizerEventsList({
    super.key,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authRepositoryProvider).currentUser;
    if (user == null) {
      return const Center(child: Text('Please Log In'));
    }

    // Use userEventsProvider to get ALL events created by this user (past + future)
    final userEventsAsync = ref.watch(userEventsProvider(user.uid));

    return userEventsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error loading events: $e')),
      data: (myEvents) {
        if (myEvents.isEmpty) {
          return const Center(child: Text('You have not created any events.'));
        }

        // Sort upcoming events first (soonest first), then expired events (most recent first)
        final now = DateTime.now();
        myEvents.sort((a, b) {
          final aExpired = EventRepository.isEventExpired(a, now);
          final bExpired = EventRepository.isEventExpired(b, now);
          if (aExpired != bExpired) {
            return aExpired ? 1 : -1;
          }
          if (!aExpired) {
            final dateCmp = a.startDate.compareTo(b.startDate);
            if (dateCmp != 0) return dateCmp;
            return a.startTime.compareTo(b.startTime);
          } else {
            final dateCmp = b.startDate.compareTo(a.startDate);
            if (dateCmp != 0) return dateCmp;
            return b.startTime.compareTo(a.startTime);
          }
        });

        return ListView.separated(
          padding: padding.add(
            EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
          ),
          itemCount: myEvents.length,
          separatorBuilder: (_, _) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final event = myEvents[index];
            return EventCard(
              event: event,
              isAttending: true,
              isCreator: true,
              onTap: () {
                context.push('/events/${event.id}', extra: event);
              },
              onEditTap: () {
                context.push('/events/edit/${event.id}', extra: event);
              },
            );
          },
        );
      },
    );
  }
}
