import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cross_file/cross_file.dart'; // [NEW]
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:diaspora_nearby/theme/app_theme.dart';
import 'package:diaspora_nearby/features/chat/services/chat_messaging_service.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/chat/screens/chats_list_screen.dart'; // For userChatsStreamProvider
import 'package:diaspora_nearby/features/chat/widgets/chat_card.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

class ShareChatSelectionScreen extends ConsumerStatefulWidget {
  final List<SharedMediaFile> sharedFiles;

  const ShareChatSelectionScreen({super.key, required this.sharedFiles});

  @override
  ConsumerState<ShareChatSelectionScreen> createState() =>
      _ShareChatSelectionScreenState();
}

class _ShareChatSelectionScreenState
    extends ConsumerState<ShareChatSelectionScreen> {
  final Set<String> _selectedChatIds = {};
  bool _isSelectionMode = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  bool _isSending = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSelection(String chatId) {
    setState(() {
      if (_selectedChatIds.contains(chatId)) {
        _selectedChatIds.remove(chatId);
        if (_selectedChatIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedChatIds.add(chatId);
      }
    });
  }

  Future<void> _handleSend() async {
    if (_isSending) return;

    final messagingService = ref.read(chatMessagingServiceProvider);
    final currentUser = ref.read(authRepositoryProvider).currentUser;

    if (currentUser == null) return;

    final targetChatIds = List<String>.from(_selectedChatIds);
    final filesToSend = List<SharedMediaFile>.from(widget.sharedFiles);
    if (targetChatIds.isEmpty || filesToSend.isEmpty) return;

    setState(() => _isSending = true);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Sent successfully!')),
    );
    context.go('/chats');

    unawaited(() async {
      try {
        await Future.wait(
          targetChatIds.map((chatId) async {
            for (final file in filesToSend) {
              final metadata = {'isShared': true};

              switch (file.type) {
                case SharedMediaType.image:
                  await messagingService.sendImageMessage(
                    chatId,
                    XFile(file.path),
                    caption: null,
                    metadata: metadata,
                  );
                  break;
                case SharedMediaType.video:
                  await messagingService.sendVideoMessage(
                    chatId,
                    XFile(file.path),
                    caption: null,
                    metadata: metadata,
                  );
                  break;
                case SharedMediaType.text:
                case SharedMediaType.url:
                  if (file.path.trim().isNotEmpty) {
                    await messagingService.sendTextMessage(
                      chatId,
                      file.path,
                      metadata: metadata,
                    );
                  }
                  break;
                case SharedMediaType.file:
                  final path = file.path.toLowerCase();
                  if (path.endsWith('.mp3') ||
                      path.endsWith('.m4a') ||
                      path.endsWith('.wav') ||
                      path.endsWith('.aac')) {
                    await messagingService.sendAudioFileMessage(
                      chatId,
                      XFile(file.path),
                      metadata: metadata,
                    );
                  } else {
                    await messagingService.sendDocumentMessage(
                      chatId,
                      XFile(file.path),
                      metadata: metadata,
                    );
                  }
                  break;
              }
            }
          }),
        );
      } catch (e) {
        debugPrint("Share Send Error: $e");
        messenger.showSnackBar(SnackBar(content: Text('Error sending: $e')));
      }
    }());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatsAsync = ref.watch(userChatsStreamProvider);
    final greenColor = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              color: theme.colorScheme.surface.withValues(alpha: 0.8),
            ),
          ),
        ),
        title: _isSelectionMode
            ? Text('${_selectedChatIds.length} selected')
            : const Text(
                'Send to...',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
        leading: IconButton(
          icon: const Icon(LucideIcons.x),
          onPressed: () {
            if (_isSelectionMode) {
              setState(() {
                _isSelectionMode = false;
                _selectedChatIds.clear();
              });
            } else {
              // Cancel share
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/chats');
              }
            }
          },
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.pageHorizontalPadding,
              vertical: 8,
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Search chats...',
                prefixIcon: const Icon(LucideIcons.search, size: 20),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 0,
                  horizontal: 16,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.3,
                ),
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          Builder(
            builder: (context) {
              final chats =
                  chatsAsync.asData?.value ??
                  ref.read(chatRepositoryProvider).cachedChats;
              if (chatsAsync.isLoading && chats.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              if (chatsAsync.hasError && chats.isEmpty) {
                return Center(child: Text('Error: ${chatsAsync.error}'));
              }
              final filteredChats =
                  (_searchQuery.isEmpty
                        ? List.of(chats)
                        : chats
                              .where(
                                (chat) => chat.name.toLowerCase().contains(
                                  _searchQuery.toLowerCase(),
                                ),
                              )
                              .toList())
                    ..sort(ChatRepository.compareChatsByLatest);

              if (filteredChats.isEmpty) {
                return const Center(child: Text('No chats found'));
              }

              return ListView.builder(
                padding: const EdgeInsets.only(
                  top: 144,
                  left: 8,
                  right: 8,
                  bottom: 136,
                ), // [FIX] Increased padding to 144px
                itemCount: filteredChats.length,
                itemBuilder: (context, index) {
                  final chat = filteredChats[index];
                  final isSelected = _selectedChatIds.contains(chat.id);

                  return GestureDetector(
                    onLongPress: () {
                      if (!_isSelectionMode) {
                        setState(() {
                          _isSelectionMode = true;
                          _selectedChatIds.add(chat.id);
                        });
                      }
                    },
                    onTap: () {
                      if (_isSelectionMode) {
                        _toggleSelection(chat.id);
                      } else {
                        // Single tap behavior: Confirm send to this chat?
                        // Or enter selection mode with this one selected?
                        // User asked: "tap other chats to select". Implies selection mode is primary for multi.
                        // But usually single tap = send.
                        // Let's implement Single Tap -> Confirm & Send
                        _showSendConfirmation(context, chat);
                      }
                    },
                    child: Stack(
                      children: [
                        AbsorbPointer(
                          child: ChatCard(
                            chat: chat,
                            searchQuery: _searchQuery.isNotEmpty
                                ? _searchQuery
                                : null,
                            onTap: () {},
                          ),
                        ),

                        if (isSelected)
                          Positioned.fill(
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              decoration: BoxDecoration(
                                color: greenColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),

                        // Selection Circle (Radio/Check style)
                        if (_isSelectionMode)
                          Positioned(
                            right: 16,
                            bottom: 18,
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected
                                    ? greenColor
                                    : Colors.transparent,
                              ),
                              child: isSelected
                                  ? const Icon(
                                      LucideIcons.check,
                                      size: 16,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),

          if (_selectedChatIds.isNotEmpty)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: ClipRRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    color: theme.colorScheme.surface.withValues(alpha: 0.8),
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.pageHorizontalPadding,
                          vertical: 12,
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isSending ? null : _handleSend,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: greenColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isSending
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(LucideIcons.share2, size: 20),
                                      SizedBox(width: 8),
                                      Text(
                                        'Share',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showSendConfirmation(BuildContext context, dynamic chat) {
    showDialog(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
          title: Text('Send to ${chat.name}?'),
          content: const Text('Do you want to send this content?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _selectedChatIds.clear();
                  _selectedChatIds.add(chat.id);
                  _handleSend();
                });
              },
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );
  }
}
