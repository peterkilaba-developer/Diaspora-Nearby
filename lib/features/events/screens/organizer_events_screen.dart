import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:diaspora_nearby/features/shared/widgets/diaspora_app_bar.dart';
import 'package:diaspora_nearby/features/events/repository/event_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/models/event_data.dart';
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

    final eventRepo = ref.watch(eventRepositoryProvider);
    
    return StreamBuilder<List<Event>>(
      stream: eventRepo.getEvents(
          isGlobal: true, 
          userCommunityMemberships: [],
          currentUserId: user.uid,
          homeCountryCode: null
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final events = snapshot.data ?? [];
        
        final myEvents = events.where((e) => e.creatorId == user.uid).toList();

        if (myEvents.isEmpty) {
          return const Center(child: Text('You have not created any events.'));
        }

        return ListView.separated(
          padding: padding,
          itemCount: myEvents.length,
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final event = myEvents[index];
            return EventCard(
              event: event, 
              isAttending: true,
              isCreator: true, // [NEW] Enable Edit Button
              onTap: () {
                 // Navigate to detail
                 context.push('/events/${event.id}', extra: event);
              },
              onEditTap: () {
                 // User requested "edit or republish... as new event"
                 // For now, we allow editing the EXISTING event. 
                 // If they want to "republish as new", we might need a separate "Clone" action later.
                 // But editing the date of an ended event effectively republishes it.
                 context.push('/events/edit/${event.id}', extra: event);
              },
            );
          },
        );
      },
    );
  }
}



