import 'package:flutter_riverpod/flutter_riverpod.dart';

final pendingMessagesProvider = Provider((ref) => PendingMessagesService());

class PendingMessagesService {
  void addMessage(dynamic message) {}
}

