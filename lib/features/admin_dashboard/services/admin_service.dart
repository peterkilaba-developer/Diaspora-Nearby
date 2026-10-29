import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/admin_dashboard/repository/admin_repository.dart';
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';
import 'package:diaspora_nearby/features/trust/repository/trust_repository.dart';

final adminServiceProvider = Provider(
  (ref) => AdminService(
    ref.read(adminRepositoryProvider),
    ref.read(trustServiceProvider),
    ref.read(trustRepositoryProvider),
  ),
);

class AdminService {
  final AdminRepository _repository;
  final TrustService _trustService;
  final TrustRepository _trustRepository;

  AdminService(this._repository, this._trustService, this._trustRepository);

  Future<void> banUser(String userId, bool ban) async {
    // 1. Update Banned Status
    await _repository.banUser(userId, ban);

    // 2. Run trust recalculations in parallel in the background so admin UI returns immediately
    unawaited(() async {
      try {
        final tasks = <Future<void>>[_trustService.updateTrustForUser(userId)];
        if (ban) {
          final vouches = await _trustRepository.getVouchesForUser(userId);
          tasks.addAll(
            vouches.map((v) => _trustService.updateTrustForUser(v.fromUserId)),
          );
        }
        await Future.wait(tasks);
      } catch (_) {}
    }());
  }
}
