import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart';

class ShareDestinationScreen extends ConsumerStatefulWidget {
  final List<SharedMediaFile>? sharedFiles;
  final String? sharedText;

  const ShareDestinationScreen({super.key, this.sharedFiles, this.sharedText});

  @override
  ConsumerState<ShareDestinationScreen> createState() =>
      _ShareDestinationScreenState();
}

class _ShareDestinationScreenState
    extends ConsumerState<ShareDestinationScreen> {
  final TextEditingController _commentController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Share to Diaspora Nearby'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            // If we launched from cold start, maybe we should go to home?
            // usually 'pop' is fine.
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/dashboard');
            }
          },
        ),
      ),
      body: Column(
        children: [
          // Preview Section
          Container(
            padding: const EdgeInsets.all(AppTheme.pageHorizontalPadding),
            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
            child: Row(
              children: [
                if (widget.sharedFiles != null &&
                    widget.sharedFiles!.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 60,
                      height: 60,
                      child: _buildPreview(widget.sharedFiles!.first),
                    ),
                  )
                else if (widget.sharedText != null)
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(child: Icon(Icons.link)),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.sharedText != null
                            ? "Shared Link/Text"
                            : "${widget.sharedFiles?.length ?? 0} item(s) to share",
                        style: theme.textTheme.titleSmall,
                      ),
                      if (widget.sharedText != null)
                        Text(
                          widget.sharedText!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(AppTheme.pageHorizontalPadding),
            child: TextField(
              controller: _commentController,
              decoration: const InputDecoration(
                hintText: 'Write a message...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ),

          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.pageHorizontalPadding,
              vertical: 8,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Select Destination",
                style: theme.textTheme.titleMedium,
              ),
            ),
          ),

          Expanded(
            child: ListView(
              children: [
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.group)),
                  title: const Text('My Community'),
                  subtitle: const Text('Share to your main feed'),
                  onTap: () => _handleShare(context, 'community'),
                ),
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.send)),
                  title: const Text('Recent Chats'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // TODO: Show recent chats picker
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Chat picker coming soon")),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(SharedMediaFile file) {
    if (file.type == SharedMediaType.image) {
      return Image.file(File(file.path), fit: BoxFit.cover);
    } else if (file.type == SharedMediaType.video) {
      return const Center(child: Icon(Icons.videocam));
    } else if (file.type == SharedMediaType.file &&
        (file.path.endsWith('.mp3') ||
            file.path.endsWith('.wav') ||
            file.path.endsWith('.m4a') ||
            file.path.endsWith('.aac'))) {
      return const Center(child: Icon(Icons.audiotrack));
    } else {
      return const Center(child: Icon(Icons.description));
    }
  }

  Future<void> _handleShare(
    BuildContext context,
    String destinationType,
  ) async {
    // [NEW] Track Incoming Share Reward
    try {
      final pointsService = ref.read(pointsServiceProvider);
      await pointsService.trackIncomingShare(
        ref.read(authRepositoryProvider).currentUser?.uid ?? '',
        widget.sharedFiles != null ? 'media' : 'text',
      );
    } catch (e) {
      debugPrint("Error tracking share reward: $e");
    }

    // TODO: Implement actual sharing logic
    showExplorationRewardToast(
      context,
      message: 'Personal Stake increased!',
      points: 100,
    );

    // Delay pop to show snackbar
    Future.delayed(const Duration(seconds: 1), () {
      if (context.mounted) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/dashboard');
        }
      }
    });
  }
}
