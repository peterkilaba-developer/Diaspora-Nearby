import 'package:diaspora_nearby/features/shared/widgets/confetti_overlay.dart';
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

void showExplorationRewardToast(
  BuildContext context, {
  String? message,
  int points = 10,
}) {
  // Trigger Confetti Globally
  confettiOverlayKey.currentState?.play();

  // Ensure we are mounted and have a ScaffoldMessenger
  if (!context.mounted) return;

  try {
    ScaffoldMessenger.of(
      context,
    ).clearSnackBars(); // Clear existing to prevent overlap
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            // Premium DSP Icon/Circle
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(
                  0xFFFFD700,
                ).withValues(alpha: 0.2), // Gold with opacity
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFFFD700), width: 1),
              ),
              child: const Icon(
                LucideIcons.coins,
                color: Color(0xFFFFD700),
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message ?? 'Exploration Reward!',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '+$points DSP added to your wallet',
                    style: const TextStyle(fontSize: 14, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2C2C2C), // Slightly lighter dark grey
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF3C3C3C), width: 1),
        ),
        margin: const EdgeInsets.all(16),
        elevation: 10,
      ),
    );
  } catch (e) {
    debugPrint('Error showing exploration toast: $e');
  }
}
