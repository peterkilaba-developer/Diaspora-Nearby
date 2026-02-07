import 'package:flutter/material.dart';

class BannedScreen extends StatelessWidget {
  const BannedScreen({
    super.key,
    this.child,
    this.initialOrgId,
    this.orgId,
    this.initialData,
    this.verificationId,
    this.phoneNumber,
    this.chatId,
    this.groupName,
    this.groupImage,
    this.currentUserId,
    this.otherUserId,
    this.navigationShell,
    this.eventToEdit,
  });

  final Widget? child;
  final dynamic navigationShell;
  final String? initialOrgId;
  final String? orgId;
  final Map? initialData;
  final String? verificationId;
  final String? phoneNumber;
  final String? chatId;
  final String? groupName;
  final String? groupImage;
  final String? currentUserId;
  final String? otherUserId;
  final dynamic eventToEdit;

  @override
  Widget build(BuildContext context) {
    if (navigationShell != null) {
      // Wrapper for StatefulShellRoute
      return Scaffold(
        body: navigationShell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: (idx) => navigationShell.goBranch(idx),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.message), label: 'Chats'),
            NavigationDestination(icon: Icon(Icons.map), label: 'Nearby'),
            NavigationDestination(icon: Icon(Icons.event), label: 'Events'),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('BannedScreen (Stub)')),
      body: const Center(child: Text('Coming Soon: BannedScreen')),
    );
  }
}
