import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';

class AiAgentActionsSection extends ConsumerStatefulWidget {
  final Message message;

  const AiAgentActionsSection({super.key, required this.message});

  @override
  ConsumerState<AiAgentActionsSection> createState() =>
      _AiAgentActionsSectionState();
}

class _AiAgentActionsSectionState extends ConsumerState<AiAgentActionsSection> {
  final Set<String> _executingIds = <String>{};
  final Map<String, String> _localCompletedRoutes = <String, String>{};

  Future<void> _executeDraftAction(Map<String, dynamic> action) async {
    final actionId = (action['id'] ?? action['draftType'] ?? 'draft')
        .toString();
    if (_executingIds.contains(actionId)) return;

    setState(() {
      _executingIds.add(actionId);
    });

    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('executeAiAgentAction')
          .call<Map<String, dynamic>>({
            'chatId': widget.message.chatId,
            'messageId': widget.message.id,
            'actionId': actionId,
            'draftType': action['draftType'],
            'payload': action['payload'] ?? const <String, dynamic>{},
          });

      final createdRoute = res.data['createdRoute']?.toString();
      if (mounted) {
        setState(() {
          _executingIds.remove(actionId);
          if (createdRoute != null && createdRoute.isNotEmpty) {
            _localCompletedRoutes[actionId] = createdRoute;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Published live on Diaspora Nearby!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _executingIds.remove(actionId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not publish: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _sendQuickPrompt(String promptText) async {
    var chatId = widget.message.chatId;
    if (chatId.isEmpty || promptText.trim().isEmpty) return;
    try {
      if (chatId.startsWith('ai_agent_')) {
        final ensureRes = await FirebaseFunctions.instance
            .httpsCallable('ensureDirectChat')
            .call<Map<String, dynamic>>({
              'otherUserId': 'diaspora_ai_agent',
              'isAiAgentWelcome': true,
            });
        final realChatId = ensureRes.data['chatId']?.toString();
        if (realChatId != null &&
            realChatId.isNotEmpty &&
            !realChatId.startsWith('ai_agent_')) {
          chatId = realChatId;
        }
      }
      await ref
          .read(chatRepositoryProvider)
          .sendTextMessage(
            chatId,
            promptText.trim(),
            participants: const <String>['diaspora_ai_agent'],
          );
    } catch (e) {
      debugPrint('Error sending AI quick prompt: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final rawActions = widget.message.metadata?['aiActions'];
    if (rawActions is! List || rawActions.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final actions = rawActions
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    if (actions.isEmpty) return const SizedBox.shrink();

    final draftActions = actions
        .where((a) => a['type'] == 'execute_draft')
        .toList();
    final quickActions = actions
        .where((a) => a['type'] != 'execute_draft')
        .toList();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final draft in draftActions)
            _buildDraftCard(context, theme, draft),
          if (quickActions.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final action in quickActions)
                  _buildQuickActionPill(context, theme, action),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildDraftCard(
    BuildContext context,
    ThemeData theme,
    Map<String, dynamic> action,
  ) {
    final actionId = (action['id'] ?? action['draftType'] ?? 'draft')
        .toString();
    final isExecuting = _executingIds.contains(actionId);
    final isCompleted =
        action['status'] == 'completed' ||
        _localCompletedRoutes.containsKey(actionId);
    final createdRoute =
        _localCompletedRoutes[actionId] ??
        action['createdRoute']?.toString() ??
        action['fallbackRoute']?.toString() ??
        '/marketplace';
    final summaryTitle = (action['summaryTitle'] ?? 'Ready to Publish')
        .toString();
    final label = (action['label'] ?? 'Publish Listing').toString();
    final rowsRaw = action['summaryRows'];
    final summaryRows = rowsRaw is List
        ? rowsRaw
              .whereType<Map>()
              .map((r) => Map<String, dynamic>.from(r))
              .toList()
        : const <Map<String, dynamic>>[];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.innerDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 15, color: AppTheme.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  summaryTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (summaryRows.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final row in summaryRows)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${row['label'] ?? ''}: ',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        (row['value'] ?? '').toString(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: Material(
              color: isCompleted
                  ? AppTheme.accent.withValues(alpha: 0.16)
                  : AppTheme.accent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: isExecuting
                    ? null
                    : () {
                        if (isCompleted) {
                          context.push(createdRoute);
                        } else {
                          _executeDraftAction(action);
                        }
                      },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isExecuting) ...[
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Publishing...',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ] else if (isCompleted) ...[
                        const Icon(
                          LucideIcons.checkCircle2,
                          size: 16,
                          color: AppTheme.accent,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Published - View Listing',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: AppTheme.accent,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ] else ...[
                        const Icon(
                          Icons.auto_awesome,
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            label,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionPill(
    BuildContext context,
    ThemeData theme,
    Map<String, dynamic> action,
  ) {
    final label = (action['label'] ?? 'Open').toString();
    final type = (action['type'] ?? 'navigate').toString();
    final route = action['route']?.toString();
    final prompt = action['prompt']?.toString();

    return Material(
      color: AppTheme.accent.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          if (type == 'prompt' && prompt != null && prompt.isNotEmpty) {
            _sendQuickPrompt(prompt);
          } else if (route != null && route.isNotEmpty) {
            context.push(route);
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppTheme.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                type == 'prompt'
                    ? LucideIcons.sparkles
                    : LucideIcons.arrowUpRight,
                size: 13,
                color: AppTheme.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
