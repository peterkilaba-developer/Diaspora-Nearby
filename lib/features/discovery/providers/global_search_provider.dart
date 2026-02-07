import 'package:flutter_riverpod/flutter_riverpod.dart';

class GlobalSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void update(String query) {
    state = query;
  }

  void clear() {
    state = '';
  }
}

/// Provider for the global search query used in the top AppBar
final globalSearchProvider = NotifierProvider<GlobalSearchNotifier, String>(
  GlobalSearchNotifier.new,
);
