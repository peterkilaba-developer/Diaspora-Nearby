import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/core/providers/global_feature_provider.dart';

enum ViewMode { home, global }

// Notifier for managing view mode state
class ViewModeNotifier extends Notifier<ViewMode> {
  @override
  ViewMode build() {
    final isUnlocked = ref.watch(isGlobalUnlockedSyncProvider);
    if (!isUnlocked) return ViewMode.home;
    return ViewMode.home;
  }

  // Default to home view
  void toggleView() {
    final isUnlocked = ref.read(isGlobalUnlockedSyncProvider);
    if (!isUnlocked) {
      state = ViewMode.home;
      return;
    }
    state = state == ViewMode.home ? ViewMode.global : ViewMode.home;
  }

  void setHome() => state = ViewMode.home;

  void setGlobal() {
    final isUnlocked = ref.read(isGlobalUnlockedSyncProvider);
    if (!isUnlocked) {
      state = ViewMode.home;
      return;
    }
    state = ViewMode.global;
  }

  bool get isGlobal => state == ViewMode.global;
  bool get isHome => state == ViewMode.home;
}

// Providers for screen-specific view modes
final nearbyViewModeProvider = NotifierProvider<ViewModeNotifier, ViewMode>(() {
  return ViewModeNotifier();
});

final eventsViewModeProvider = NotifierProvider<ViewModeNotifier, ViewMode>(() {
  return ViewModeNotifier();
});

final communitiesViewModeProvider =
    NotifierProvider<ViewModeNotifier, ViewMode>(() {
      return ViewModeNotifier();
    });

final radioViewModeProvider = NotifierProvider<ViewModeNotifier, ViewMode>(() {
  return ViewModeNotifier();
});

final chatsViewModeProvider = NotifierProvider<ViewModeNotifier, ViewMode>(() {
  return ViewModeNotifier();
});

