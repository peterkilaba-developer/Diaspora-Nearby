import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';

/// A widget that displays the list of users currently typing in a chat.
class ChatTypingIndicator extends ConsumerWidget {
  final List<String> typingUsers;

  const ChatTypingIndicator({super.key, required this.typingUsers});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (typingUsers.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildTypingDots(theme),
          const SizedBox(width: 12),
          Expanded(child: _buildTypingText(context, ref, theme)),
        ],
      ),
    );
  }

  Widget _buildTypingText(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
  ) {
    if (typingUsers.length == 1) {
      final profileAsync = ref.watch(
        userProfileByIdProvider(typingUsers.first),
      );
      return profileAsync.when(
        data: (profile) => Text(
          '${profile?.firstName ?? 'Someone'} is typing...',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w500,
          ),
        ),
        loading: () =>
            Text('Someone is typing...', style: theme.textTheme.bodySmall),
        error: (_, _) =>
            Text('Someone is typing...', style: theme.textTheme.bodySmall),
      );
    }

    return Text(
      '${typingUsers.length} people are typing...',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildTypingDots(ThemeData theme) {
    return _TypingDots(color: theme.colorScheme.primary);
  }
}

class _TypingDots extends StatefulWidget {
  final Color color;

  const _TypingDots({required this.color});

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      3,
      (index) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      ),
    );

    _animations = _controllers.map((controller) {
      return Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).animate(CurvedAnimation(parent: controller, curve: Curves.easeInOut));
    }).toList();

    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 200), () {
        if (mounted) {
          _controllers[i].repeat(reverse: true);
        }
      });
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _animations[index],
          builder: (context, child) {
            return Container(
              width: 4,
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: widget.color.withValues(
                  alpha: 0.2 + (0.8 * _animations[index].value),
                ),
                shape: BoxShape.circle,
              ),
            );
          },
        );
      }),
    );
  }
}
