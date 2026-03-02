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

    // 2. If banning, trigger trust recalculations for the vauch chain penalty
    if (ban) {
      // Find everyone who vouched for this user
      final vouches = await _trustRepository.getVouchesForUser(userId);
      for (final v in vouches) {
        // Recalculating their score will now find this banned vouchee and apply the deduction
        await _trustService.updateTrustForUser(v.fromUserId);
      }
    }

    // 3. Update the banned user's own trust score
    await _trustService.updateTrustForUser(userId);
  }
}
