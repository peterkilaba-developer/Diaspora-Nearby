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
      appBar: AppBar(title: const Text('Account Suspended')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.block_outlined, size: 56),
              SizedBox(height: 16),
              Text(
                'Your account has been suspended.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text(
                'Please contact support@diasporanearby.com if you believe this is a mistake.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
