import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

class DiasporaScaffold extends StatefulWidget {
  final Widget child;

  const DiasporaScaffold({super.key, required this.child});

  @override
  State<DiasporaScaffold> createState() => _DiasporaScaffoldState();
}

class _DiasporaScaffoldState extends State<DiasporaScaffold> {
  int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/nearby')) return 0;
    if (location.startsWith('/events')) return 1;
    if (location.startsWith('/chats')) return 2;
    if (location.startsWith('/profile')) return 3;
    return 0;
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        context.go('/nearby');
        break;
      case 1:
        context.go('/events');
        break;
      case 2:
        context.go('/chats');
        break;
      case 3:
        // Use a default user ID or current user ID logic handled by router redirect usually
        // But here we assume /profile navigates to current user
        // We'll go to /profile/me or handle in router.
        // If router expects /profile/:uid, we need uid.
        // For safe nav, let's go to /profile-setup if logic missing or just /profile if redirect works.
        // Let's assume /profile endpoint redirects to user id or is the list.
        // Actually router often has /profile pointing to self.
        context.go('/profile/me');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _calculateSelectedIndex(context),
        onDestinationSelected: (idx) => _onItemTapped(idx, context),
        destinations: const [
          NavigationDestination(
            icon: Icon(LucideIcons.mapPin),
            label: 'Nearby',
          ),
          NavigationDestination(
            icon: Icon(LucideIcons.calendar),
            label: 'Events',
          ),
          NavigationDestination(
            icon: Icon(LucideIcons.messageCircle),
            label: 'Chats',
          ),
          NavigationDestination(icon: Icon(LucideIcons.user), label: 'Profile'),
        ],
      ),
    );
  }
}
