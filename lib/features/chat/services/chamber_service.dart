import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final chamberServiceProvider = Provider<ChamberService>((ref) {
  return ChamberService();
});

class ChamberService {
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'us-central1',
  );

  Future<String?> ensureSignupChamber() async {
    final result = await _functions.httpsCallable('ensureSignupChamber').call();
    final data = Map<String, dynamic>.from(result.data as Map);
    return data['chatId'] as String?;
  }

  Future<void> joinChamber(String chatId) async {
    await _functions.httpsCallable('joinChamber').call({'chatId': chatId});
  }

  Future<void> joinDdiDiscussion(String chatId) async {
    await _functions.httpsCallable('joinDdiDiscussion').call({
      'chatId': chatId,
    });
  }

  Future<void> manageChamber(
    String chatId, {
    String? description,
    List<String> addMemberIds = const [],
    List<String> removeMemberIds = const [],
  }) async {
    await _functions.httpsCallable('manageChamber').call({
      'chatId': chatId,
      'description': ?description,
      if (addMemberIds.isNotEmpty) 'addMemberIds': addMemberIds,
      if (removeMemberIds.isNotEmpty) 'removeMemberIds': removeMemberIds,
    });
  }
}
