import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart'; // [NEW]
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';

/// Wraps a widget (usually a button or list tile) to track taps for exploration rewards.
class ExplorationTracked extends ConsumerWidget {
  final String actionId;
  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;

  const ExplorationTracked({
    super.key,
    required this.actionId,
    required this.child,
    this.onTap,
    this.enabled = true,
  });

  Future<void> _handleTap(WidgetRef ref, BuildContext context) async {
    if (!enabled) return;

    // Execute the original action first to ensure responsiveness
    onTap?.call();

    try {
      final user = ref.read(authRepositoryProvider).currentUser;
      if (user == null) return;

      final pointsService = ref.read(pointsServiceProvider);

      // Fire and forget the tracking
      final rewarded = await pointsService.trackExplorationReward(
        user.uid,
        actionId,
      );

      if (rewarded && context.mounted) {
        showExplorationRewardToast(context);
      }
    } catch (e) {
      // Silently fail to not disrupt user experience
      debugPrint('Error tracking exploration: $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _handleTap(ref, context),
      behavior: HitTestBehavior.translucent,
      child: child,
    );
  }
}

/// Helper to wrap an existing OnTap callback if you can't wrap the widget easily.
/// Returns a new VoidCallback that tracks then calls original.
VoidCallback trackExplorationCallback(
  WidgetRef ref,
  BuildContext context,
  String actionId,
  VoidCallback? originalOnTap,
) {
  return () async {
    originalOnTap?.call();

    try {
      final user = ref.read(authRepositoryProvider).currentUser;
      if (user != null) {
        final rewarded = await ref
            .read(pointsServiceProvider)
            .trackExplorationReward(user.uid, actionId);
        if (rewarded && context.mounted) {
           showExplorationRewardToast(context);
        }
      }
    } catch (_) {}
  };
}

void showExplorationRewardToast(BuildContext context, {String? message, int points = 10}) {
  ScaffoldMessenger.of(context).clearSnackBars(); // Clear existing to prevent overlap
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          // Premium DSP Icon/Circle
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFFFFD700).withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(LucideIcons.coins, color: Color(0xFFFFD700), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message ?? 'Bonus Unlocked',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
                Text(
                  '+$points DSP Earned!',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF1E1E1E), // Professional Dark Grey
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.all(16),
      elevation: 8,
    ),
  );
}
