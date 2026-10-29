import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:diaspora_nearby/core/services/background_location_service.dart';
import 'package:diaspora_nearby/features/chat/screens/create_group_screen.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:share_plus/share_plus.dart'; // [NEW]
import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'package:diaspora_nearby/features/chat/models/chat.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/chat/utils/community_chat_utils.dart'; // [NEW] Parity utils
import 'package:diaspora_nearby/features/chat/widgets/message_bubble.dart';
import 'package:diaspora_nearby/features/chat/widgets/message_input.dart';
import 'package:diaspora_nearby/features/chat/widgets/message_action_sheet.dart';

import 'package:diaspora_nearby/features/chat/widgets/chat_header_title.dart';
import 'package:diaspora_nearby/features/organization/repository/organization_repository.dart';
import 'package:diaspora_nearby/core/data/countries.dart' as country_data;
import 'package:diaspora_nearby/features/community/repository/community_repository.dart'; // [NEW]
import 'package:diaspora_nearby/theme/app_theme.dart'; // [FIXED]

import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';
import 'package:diaspora_nearby/core/providers/global_feature_provider.dart';
import 'package:diaspora_nearby/features/trust/repository/trust_repository.dart'; // [NEW]
// [FIXED]
import 'package:diaspora_nearby/features/dsp/services/points_service.dart';
import 'package:diaspora_nearby/features/dsp/widgets/exploration_tracker.dart'; // [NEW]
import 'package:diaspora_nearby/features/community/models/community_data.dart';

import 'package:diaspora_nearby/features/chat/screens/media_preview_screen.dart'; // [NEW]
import 'package:diaspora_nearby/features/events/repository/event_repository.dart';
import 'package:diaspora_nearby/features/events/models/event_data.dart';
import 'package:diaspora_nearby/features/chat/repository/report_repository.dart'; // [NEW]
// [NEW]
import 'package:diaspora_nearby/features/chat/providers/chat_identity_provider.dart'; // [NEW]
import 'package:diaspora_nearby/features/profile/repository/relationship_repository.dart'; // [NEW]
import 'package:diaspora_nearby/features/profile/widgets/relationship_selection_modal.dart';
import 'package:diaspora_nearby/features/profile/widgets/relationship_response_modal.dart';
import 'package:diaspora_nearby/features/profile/widgets/profile_qr_code_dialog.dart';
import 'package:diaspora_nearby/features/profile/models/relationship.dart';
import 'package:diaspora_nearby/features/profile/models/relationship_request.dart'; // [NEW]
import 'package:diaspora_nearby/features/chat/providers/pending_message_provider.dart';
// [NEW]
// [NEW]
import 'package:diaspora_nearby/features/chat/widgets/chat_more_menu_sheet.dart';
import 'package:diaspora_nearby/features/trust/widgets/profile_verification_modal.dart'; // [NEW]
import 'package:diaspora_nearby/features/trust/widgets/trust_vouch_modal.dart'; // [NEW] Trust Vouch Modal
import 'package:diaspora_nearby/features/trust/widgets/trust_slider_widget.dart';
import 'package:diaspora_nearby/features/trust/widgets/verification_alert_modal.dart'; // [NEW]
import 'package:diaspora_nearby/features/governance/repository/governance_repository.dart'; // [NEW]

import 'package:diaspora_nearby/features/governance/screens/leader_selection_screen.dart'; // [NEW]
import 'package:diaspora_nearby/features/governance/models/governance_unit.dart'; // [NEW]
// [NEW]
import 'package:diaspora_nearby/features/more/widgets/business_registration_modal.dart'; // [NEW]
import 'package:diaspora_nearby/features/community/widgets/share_community_dialog.dart'; // [NEW]
import 'package:diaspora_nearby/features/dsp/screens/ddi_loans_screen.dart'; // [NEW]
import 'package:diaspora_nearby/features/organization/screens/organization_detail_screen.dart'; // [NEW]
import 'package:diaspora_nearby/features/dsp/screens/gvi_corridor_list_screen.dart'; // [NEW]

import 'package:diaspora_nearby/features/chat/widgets/chat_report_sheet.dart';
import 'package:diaspora_nearby/features/chat/widgets/chat_confirmation_sheet.dart';
import 'package:diaspora_nearby/features/chat/widgets/chat_date_separator.dart';
import 'package:diaspora_nearby/features/chat/widgets/chat_empty_state.dart';
import 'package:diaspora_nearby/features/chat/widgets/chat_restriction_view.dart';
import 'package:diaspora_nearby/features/chat/providers/chat_providers.dart'; // [NEW] Shared Providers
import 'package:diaspora_nearby/features/shared/utils/whatsapp_utils.dart';
import 'package:diaspora_nearby/features/chat/widgets/chat_scroll_to_bottom_fab.dart';
import 'package:diaspora_nearby/features/chat/widgets/chat_typing_indicator.dart';
import 'package:diaspora_nearby/features/notifications/services/push_notification_service.dart';

// Local providers removed (moved to chat_providers.dart)

/// Chat Screen
/// Displays messages in a conversation with input
/// Supports both existing chats (via chatId) and pending DMs (before first message)
class ChatScreen extends ConsumerStatefulWidget {
  /// For existing chats
  final String? chatId;

  /// For pending DMs (chat not created yet)
  final String? pendingUserId;
  final String? pendingUserName;
  final String? pendingUserImage;

  /// Constructor for existing chat
  const ChatScreen({super.key, required this.chatId})
    : pendingUserId = null,
      pendingUserName = null,
      pendingUserImage = null;

  /// Constructor for pending DM (chat to be created on first message)
  const ChatScreen.pendingDM({
    super.key,
    required this.pendingUserId,
    required this.pendingUserName,
    this.pendingUserImage,
  }) : chatId = null;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController =
      TextEditingController(); // [NEW]
  bool _isNearBottom = true;
  // _scrollPositionRestored removed

  /// The actual chatId (either from props or created after first message)
  String? _activeChatId;

  /// Partner user ID when this conversation is a 1-on-1 direct chat or pending DM
  String? _activePartnerUserId;

  /// Cached reference to PushNotificationService for safe cleanup in dispose()
  PushNotificationService? _pushNotificationService;

  /// Message being replied to (null if not replying)
  Message? _replyingTo;

  /// Tracks message IDs that have become visible and need to be marked as read
  final Set<String> _visibleUnreadMessageIds = {};

  /// Debounce timer for batching read receipt updates
  Timer? _readReceiptDebounceTimer;

  /// Whether this is a pending DM that hasn't been created yet
  bool get _isPendingDM =>
      widget.chatId == null && widget.pendingUserId != null;

  /// Key used in `pendingMessagesProvider` before a pending DM has a server chatId
  String get _pendingDmCacheKey =>
      _activeChatId ?? 'pending_dm_${widget.pendingUserId ?? "unknown"}';

  /// Global keys for each message to support "Jump to Message"
  final Map<String, GlobalKey> _messageKeys = {};

  /// Current message ID being highlighted (from "Jump to Message")
  String? _highlightedMessageId;

  /// Guard to prevent duplicate "More" menu opens during async loading
  bool _isShowingMoreMenu = false;

  void _syncActiveChatNotificationState() {
    final pushService = _pushNotificationService;
    if (pushService != null) {
      unawaited(
        pushService.setActiveChat(
          chatId: _activeChatId,
          partnerUserId: _activePartnerUserId,
        ),
      );
    } else {
      ActiveChatTracker.instance.setActiveChat(
        chatId: _activeChatId,
        partnerUserId: _activePartnerUserId,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _activeChatId = widget.chatId;
    _activePartnerUserId = widget.pendingUserId;
    _pushNotificationService = ref.read(pushNotificationServiceProvider);
    _scrollController.addListener(_onScroll);

    final chatRepo = ref.read(chatRepositoryProvider);
    final currentUserId = chatRepo.currentUserId;

    // [PERF] If opened as pendingDM, synchronously check if direct chat already exists in cache
    if (_activeChatId == null && widget.pendingUserId != null) {
      final existingCached = chatRepo.getCachedDirectChatWith(
        widget.pendingUserId!,
      );
      if (existingCached != null) {
        _activeChatId = existingCached.id;
      }
    }

    // Synchronously resolve partnerUserId from cached chat if available
    if (_activeChatId != null && currentUserId != null) {
      final cachedChat = chatRepo.getCachedChat(_activeChatId!);
      if (cachedChat != null && cachedChat.isDirect) {
        final otherId = cachedChat.participants.firstWhere(
          (id) => id != currentUserId,
          orElse: () => '',
        );
        if (otherId.isNotEmpty) {
          _activePartnerUserId = otherId;
        }
      }
    }
    _syncActiveChatNotificationState();

    // LOGGING TO DEBUG "NOTHING HAPPENS"
    debugPrint('📩 ChatScreen INIT:');
    debugPrint('   - chatId: ${widget.chatId}');
    debugPrint('   - pendingUserId: ${widget.pendingUserId}');
    debugPrint('   - pendingUserName: ${widget.pendingUserName}');
    debugPrint('   - currentUserId: $currentUserId');

    // Mark as read and pre-warm secondary caches in background
    if (_activeChatId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final chatRepo = ref.read(chatRepositoryProvider);
        final currentUserId = chatRepo.currentUserId;
        if (currentUserId == null) return;

        // Fetch chat once to check participation and type
        final chat =
            chatRepo.getCachedChat(_activeChatId!) ??
            await chatRepo.getChat(_activeChatId!);
        if (chat != null) {
          if (chat.isDirect) {
            final otherId = chat.participants.firstWhere(
              (id) => id != currentUserId,
              orElse: () => '',
            );
            if (otherId.isNotEmpty) {
              if (_activePartnerUserId != otherId) {
                _activePartnerUserId = otherId;
                if (mounted) {
                  _syncActiveChatNotificationState();
                }
              }
              // Pre-warm partner profile, relationship & verification status in background
              unawaited(
                ref.read(profileRepositoryProvider).getUserProfile(otherId),
              );
              unawaited(
                ref
                    .read(relationshipRepositoryProvider)
                    .getRelationship(
                      userId: currentUserId,
                      relatedUserId: otherId,
                    ),
              );
              unawaited(
                ref
                    .read(trustRepositoryProvider)
                    .hasVerifiedUser(currentUserId, otherId),
              );
            }
          }
          if (chat.isCommunity && chat.communityId != null) {
            unawaited(
              ref
                  .read(communityRepositoryProvider)
                  .getCommunity(chat.communityId!),
            );
            unawaited(
              ref
                  .read(governanceRepositoryProvider)
                  .getGovernanceUnitByCommunityId(chat.communityId!),
            );
          }
          final isParticipant = chat.participants.contains(currentUserId);

          if (isParticipant) {
            // [FIX] Only mark as read if the user is a member.
            // This avoids auto-joining if the user is just previewing from discovery.
            unawaited(chatRepo.markChatAsRead(_activeChatId!));
            unawaited(chatRepo.clearChatMentions(_activeChatId!));

            // [NEW] Award exploration DSP for opening community chats
            if (chat.type == 'community' && mounted) {
              final actionId = 'action_open_community_chat_${chat.id}';
              try {
                final rewarded = await ref
                    .read(pointsServiceProvider)
                    .trackExplorationReward(currentUserId, actionId);
                if (rewarded && mounted) {
                  showExplorationRewardToast(
                    context,
                    message: 'Explored ${chat.name}',
                    points: 100,
                  );
                }
              } catch (e) {
                debugPrint('Error tracking chat exploration: $e');
              }
            }
          }
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _pushNotificationService?.setLifecycleState(state);
    if (state == AppLifecycleState.resumed && mounted) {
      _syncActiveChatNotificationState();
      if (_activeChatId != null) {
        ref.read(chatRepositoryProvider).markChatAsRead(_activeChatId!);
      }
    }
  }

  // Scroll persistence methods removed

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pushNotificationService?.clearActiveChat(
      chatId: _activeChatId,
      partnerUserId: _activePartnerUserId,
    );

    // [FIX] Flush pending read receipts before disposing
    if (_visibleUnreadMessageIds.isNotEmpty) {
      final ids = _visibleUnreadMessageIds.toList();
      _visibleUnreadMessageIds.clear();
      // Fire and forget - we can't await in dispose
      final chatRepo = ref.read(chatRepositoryProvider);
      if (_activeChatId != null) {
        chatRepo.markMessagesAsRead(_activeChatId!, ids);
      }
    }
    _readReceiptDebounceTimer?.cancel();

    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _messageController.dispose(); // [NEW]
    super.dispose();
  }

  void _onScroll() {
    final isNearBottom =
        _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 100;
    if (isNearBottom != _isNearBottom) {
      setState(() => _isNearBottom = isNearBottom);
    }
  }

  void _scrollToBottom([bool animate = true]) {
    if (!_scrollController.hasClients) return;

    // With reverse: true, Bottom is 0.0
    // We schedule it to ensure frame readiness, though 0.0 should be safe.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      const position = 0.0;
      if (animate) {
        _scrollController.animateTo(
          position,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(position);
      }
    });
  }

  /// Scroll to a specific message by ID
  void _scrollToMessage(String messageId) {
    setState(() => _highlightedMessageId = messageId);

    final key = _messageKeys[messageId];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        alignment: 0.5, // Center the item
      );

      // Clear highlight after delay
      Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _highlightedMessageId = null);
      });
    } else {
      debugPrint('⚠️ Target message $messageId not found in rendered list');
      // In a production app, we would fetch more messages or use search
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message too far back to jump to')),
        );
      }
    }
  }

  // Duplicates removed

  /// Set message to reply to
  void _setReplyTo(Message message) {
    setState(() => _replyingTo = message);
  }

  /// Clear reply
  void _clearReply() {
    setState(() => _replyingTo = null);
  }

  Future<void> _sendMessage(
    String text, {
    Map<String, dynamic>? metadata,
  }) async {
    debugPrint('📩 _sendMessage called with content: "$text"');
    if (text.trim().isEmpty) return;

    final chatRepo = ref.read(chatRepositoryProvider);
    final replyToId = _replyingTo?.id;
    final replyToSenderId = _replyingTo?.senderId;

    // Clear reply immediately
    _clearReply();

    final identity = ref.read(chatIdentityProvider);
    String? senderIdOverride;
    String? senderNameOverride;
    String? senderImageOverride;

    if (identity != null) {
      senderIdOverride = identity['id'];
      senderNameOverride = identity['businessName'] ?? identity['name'];
      senderImageOverride = identity['profileImage'];
    }

    final currentUserId = chatRepo.currentUserId;
    final now = DateTime.now().millisecondsSinceEpoch;
    final tempId = 'temp_${now}_${currentUserId ?? "me"}';

    // If this is a pending DM, insert optimistic bubble in 0ms before creating the chat
    if (_isPendingDM && _activeChatId == null) {
      final pendingKey = _pendingDmCacheKey;
      final optimisticMessage = Message(
        id: tempId,
        chatId: pendingKey,
        senderId: senderIdOverride ?? (currentUserId ?? ''),
        senderName: senderNameOverride ?? 'Me',
        senderImage: senderImageOverride,
        content: text.trim(),
        type: 'text',
        timestamp: now,
        status: 'sending',
        replyTo: replyToId,
      );

      ref
          .read(pendingMessagesProvider.notifier)
          .addMessage(pendingKey, optimisticMessage);
      _scrollToBottom(false);

      debugPrint('📍 Creating DM chat on first message...');
      final chat = await chatRepo.createDirectChatWithMessage(
        widget.pendingUserId!,
        text,
      );

      ref
          .read(pendingMessagesProvider.notifier)
          .removeMessage(pendingKey, tempId);

      if (chat != null) {
        if (mounted) {
          setState(() {
            _activeChatId = chat.id;
          });
        }
        _syncActiveChatNotificationState();
        debugPrint('✅ Chat created: ${chat.id}');
      } else {
        debugPrint(
          '❌ Failed to create chat with user ${widget.pendingUserId}',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Failed to start chat. User might not exist or network error.',
              ),
              backgroundColor: Theme.of(context).colorScheme.error,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } else if (_activeChatId != null) {
      final activeChatId = _activeChatId!;
      if (currentUserId != null) {
        final optimisticMessage = Message(
          id: tempId,
          chatId: activeChatId,
          senderId: senderIdOverride ?? currentUserId,
          senderName: senderNameOverride ?? 'Me',
          senderImage: senderImageOverride,
          content: text.trim(),
          type: 'text',
          timestamp: now,
          status: 'sending',
          replyTo: replyToId,
        );

        ref
            .read(pendingMessagesProvider.notifier)
            .addMessage(activeChatId, optimisticMessage);
        _scrollToBottom(false);

        // [PERF] Read cached participants synchronously without blocking on getChat
        final participants = chatRepo.getCachedChat(activeChatId)?.participants;

        try {
          await chatRepo.sendTextMessage(
            activeChatId,
            text,
            replyToMessageId: replyToId,
            senderIdOverride: senderIdOverride,
            senderNameOverride: senderNameOverride,
            senderImageOverride: senderImageOverride,
            participants: participants,
            mentions: (metadata?['mentions'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList(),
            richContent: metadata?['richContent'] as String?,
            replyToSenderId: replyToSenderId,
          );
        } catch (e) {
          debugPrint('❌ Error sending message: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Failed to send message: ${e.toString().replaceAll('Exception: ', '')}',
                ),
                backgroundColor: Theme.of(context).colorScheme.error,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        } finally {
          ref
              .read(pendingMessagesProvider.notifier)
              .removeMessage(activeChatId, tempId);
        }
      } else {
        await chatRepo.sendTextMessage(
          activeChatId,
          text,
          replyToMessageId: replyToId,
          senderIdOverride: senderIdOverride,
          senderNameOverride: senderNameOverride,
          senderImageOverride: senderImageOverride,
          mentions: (metadata?['mentions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList(),
          richContent: metadata?['richContent'] as String?,
        );
      }
    }

    _scrollToBottom();
  }

  /// Synchronously get cached participants when available
  List<String>? _getParticipantsSync([String? chatId]) {
    final targetId = chatId ?? _activeChatId;
    if (targetId == null) return null;
    return ref.read(chatRepositoryProvider).getCachedChat(targetId)?.participants;
  }

  /// Helper to ensure chat exists (creates it if pending)
  Future<String?> _ensureChatCreated() async {
    if (_activeChatId != null) return _activeChatId;
    if (!_isPendingDM) return null;

    final chatRepo = ref.read(chatRepositoryProvider);
    final existingCached = chatRepo.getCachedDirectChatWith(
      widget.pendingUserId!,
    );
    if (existingCached != null) {
      setState(() {
        _activeChatId = existingCached.id;
      });
      _syncActiveChatNotificationState();
      return existingCached.id;
    }

    debugPrint('📍 Creating DM chat for media/file...');
    final chat = await chatRepo.createDirectChat(widget.pendingUserId!);

    if (chat != null) {
      if (mounted) {
        setState(() {
          _activeChatId = chat.id;
        });
      }
      _syncActiveChatNotificationState();
      debugPrint('✅ Chat created: ${chat.id}');
      return chat.id;
    } else {
      debugPrint('❌ Failed to create chat with user ${widget.pendingUserId}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Failed to start chat. User might not exist or network error.',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return null;
    }
  }

  Future<void> _onMediaPicked(
    List<XFile> files,
    String type,
    String caption,
  ) async {
    // Show preview screen
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MediaPreviewScreen(
          files: files,
          type: type,
          initialCaption: caption, // [NEW] Pass context
          onSend: (processedFiles, finalCaption) {
            _sendMedia(
              processedFiles,
              type,
              finalCaption,
            ); // Send with confirmed caption
            _messageController.clear(); // [NEW] Clear input after sending
          },
        ),
      ),
    );
  }

  Future<void> _sendMedia(
    List<XFile> files,
    String type,
    String? caption,
  ) async {
    final chatRepo = ref.read(chatRepositoryProvider);
    final currentUserId = chatRepo.currentUserId;
    final replyToId = _replyingTo?.id;
    final replyToSenderId = _replyingTo?.senderId;
    final identity = ref.read(chatIdentityProvider);

    // Clear reply immediately
    _clearReply();

    // [PERF] Insert optimistic media bubbles on frame 0 BEFORE any await
    final initialKey = _pendingDmCacheKey;
    final now = DateTime.now().millisecondsSinceEpoch;
    final tempIds = <String>[];

    if (currentUserId != null) {
      for (int i = 0; i < files.length; i++) {
        final file = files[i];
        final tempId = 'temp_media_${now}_$i';
        tempIds.add(tempId);
        final optimisticMessage = Message(
          id: tempId,
          chatId: initialKey,
          senderId: identity?['id'] ?? currentUserId,
          senderName: identity?['name'] ?? 'Me',
          senderImage: identity?['profileImage'],
          content: caption?.trim() ?? '',
          type: type, // 'image' or 'video'
          imageUrl: type == 'image' ? file.path : null,
          documentUrl: file.path,
          timestamp: now + i,
          status: 'sending',
          replyTo: replyToId,
        );
        ref
            .read(pendingMessagesProvider.notifier)
            .addMessage(initialKey, optimisticMessage);
      }
      _scrollToBottom(false);
    }

    final chatId = await _ensureChatCreated();
    if (chatId == null) {
      for (final tempId in tempIds) {
        ref
            .read(pendingMessagesProvider.notifier)
            .removeMessage(initialKey, tempId);
      }
      return;
    }

    final participants = _getParticipantsSync(chatId);

    await Future.wait(
      List.generate(files.length, (index) async {
        final file = files[index];
        final tempId = index < tempIds.length ? tempIds[index] : null;
        try {
          if (type == 'video') {
            await chatRepo.sendVideoMessage(
              chatId,
              file,
              caption: caption,
              replyToMessageId: replyToId,
              senderIdOverride: identity?['id'],
              senderNameOverride: identity?['name'],
              senderImageOverride: identity?['profileImage'],
              participants: participants,
              replyToSenderId: replyToSenderId,
            );
          } else {
            await chatRepo.sendImageMessage(
              chatId,
              file,
              caption: caption,
              replyToMessageId: replyToId,
              senderIdOverride: identity?['id'],
              senderNameOverride: identity?['name'],
              senderImageOverride: identity?['profileImage'],
              participants: participants,
              replyToSenderId: replyToSenderId,
            );
          }
        } catch (e) {
          debugPrint('Error sending media: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to send media: ${e.toString()}')),
            );
          }
        } finally {
          if (tempId != null && mounted) {
            ref
                .read(pendingMessagesProvider.notifier)
                .removeMessage(initialKey, tempId);
            if (chatId != initialKey) {
              ref
                  .read(pendingMessagesProvider.notifier)
                  .removeMessage(chatId, tempId);
            }
          }
        }
      }),
    );

    _scrollToBottom();
  }

  Future<MessageLocation?> _pickLocation() async {
    // [PERF] Return cached last known position in 0ms if available!
    final cachedPos = BackgroundLocationService.cachedLastKnownPosition;
    if (cachedPos != null) {
      return MessageLocation(
        lat: cachedPos.latitude,
        lng: cachedPos.longitude,
        address: '',
      );
    }

    // Permission check
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied')),
          );
        }
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Location permission permanently denied. Enable in settings.',
            ),
          ),
        );
      }
      return null;
    }

    try {
      // Check OS lastKnownPosition before waiting for fresh GPS fix
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        BackgroundLocationService.cachedLastKnownPosition = lastKnown;
        return MessageLocation(
          lat: lastKnown.latitude,
          lng: lastKnown.longitude,
          address: '',
        );
      }

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Location services are disabled. Please enable them.',
              ),
              action: SnackBarAction(
                label: 'SETTINGS',
                onPressed: Geolocator.openLocationSettings,
              ),
            ),
          );
        }
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: 10,
        ),
      ).timeout(const Duration(seconds: 5));

      BackgroundLocationService.cachedLastKnownPosition = position;

      return MessageLocation(
        lat: position.latitude,
        lng: position.longitude,
        address: '',
      );
    } on TimeoutException catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not get location. Signal is weak.'),
          ),
        );
      }
      return null;
    } catch (e) {
      debugPrint('Error getting location: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to get location')));
      }
      return null;
    }
  }

  Future<void> _sendLocationMessage(
    MessageLocation location,
    String? caption,
  ) async {
    final chatRepo = ref.read(chatRepositoryProvider);
    final currentUserId = chatRepo.currentUserId;
    final replyToId = _replyingTo?.id;
    final replyToSenderId = _replyingTo?.senderId;
    final identity = ref.read(chatIdentityProvider);

    // Clear reply immediately
    _clearReply();

    // [PERF] Insert optimistic location message on frame 0 BEFORE any await
    final initialKey = _pendingDmCacheKey;
    final now = DateTime.now().millisecondsSinceEpoch;
    final tempId = 'temp_loc_$now';

    if (currentUserId != null) {
      final optimisticMessage = Message(
        id: tempId,
        chatId: initialKey,
        senderId: identity?['id'] ?? currentUserId,
        senderName: identity?['name'] ?? 'Me',
        senderImage: identity?['profileImage'],
        content: caption?.trim() ?? '',
        type: 'location',
        timestamp: now,
        status: 'sending',
        replyTo: replyToId,
        location: location,
      );

      ref
          .read(pendingMessagesProvider.notifier)
          .addMessage(initialKey, optimisticMessage);
      _scrollToBottom(false);
    }

    final chatId = await _ensureChatCreated();
    if (chatId == null) {
      if (currentUserId != null) {
        ref
            .read(pendingMessagesProvider.notifier)
            .removeMessage(initialKey, tempId);
      }
      return;
    }

    final participants = _getParticipantsSync(chatId);

    // Resolve reverse geocoding in background if address is empty
    String resolvedAddress = location.address;
    if (resolvedAddress.isEmpty) {
      try {
        final placemarks = await placemarkFromCoordinates(
          location.lat,
          location.lng,
        ).timeout(const Duration(seconds: 2));
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          resolvedAddress = [
            place.street,
            place.locality,
            place.administrativeArea,
            place.country,
          ].where((s) => s != null && s.isNotEmpty).join(', ');
        }
      } catch (_) {}
    }

    try {
      await chatRepo.sendLocationMessage(
        chatId,
        latitude: location.lat,
        longitude: location.lng,
        address: resolvedAddress,
        caption: caption,
        replyToMessageId: replyToId,
        senderIdOverride: identity?['id'],
        senderNameOverride: identity?['name'],
        senderImageOverride: identity?['profileImage'],
        participants: participants,
        replyToSenderId: replyToSenderId,
      );
    } catch (e) {
      debugPrint('Error sending location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send location: ${e.toString()}')),
        );
      }
    } finally {
      if (currentUserId != null && mounted) {
        ref
            .read(pendingMessagesProvider.notifier)
            .removeMessage(initialKey, tempId);
        if (chatId != initialKey) {
          ref
              .read(pendingMessagesProvider.notifier)
              .removeMessage(chatId, tempId);
        }
      }
    }

    _scrollToBottom();
  }

  Future<void> _sendAudioFile(XFile file, String? caption) async {
    final chatRepo = ref.read(chatRepositoryProvider);
    final currentUserId = chatRepo.currentUserId;
    final replyToId = _replyingTo?.id;
    final replyToSenderId = _replyingTo?.senderId;
    final identity = ref.read(chatIdentityProvider);

    // Clear reply immediately
    _clearReply();

    // [PERF] Insert optimistic audio file bubble on frame 0 BEFORE any await
    final initialKey = _pendingDmCacheKey;
    final now = DateTime.now().millisecondsSinceEpoch;
    final tempId = 'temp_audiofile_$now';

    if (currentUserId != null) {
      final optimisticMessage = Message(
        id: tempId,
        chatId: initialKey,
        senderId: identity?['id'] ?? currentUserId,
        senderName: identity?['name'] ?? 'Me',
        senderImage: identity?['profileImage'],
        content: caption?.trim() ?? '',
        type: 'audio_file',
        documentUrl: file.path,
        timestamp: now,
        status: 'sending',
        replyTo: replyToId,
      );

      ref
          .read(pendingMessagesProvider.notifier)
          .addMessage(initialKey, optimisticMessage);
      _scrollToBottom(false);
    }

    final chatId = await _ensureChatCreated();
    if (chatId == null) {
      if (currentUserId != null) {
        ref
            .read(pendingMessagesProvider.notifier)
            .removeMessage(initialKey, tempId);
      }
      return;
    }

    final participants = _getParticipantsSync(chatId);

    try {
      await chatRepo.sendAudioFileMessage(
        chatId,
        file,
        caption: caption,
        replyToMessageId: replyToId,
        senderIdOverride: identity?['id'],
        senderNameOverride: identity?['name'],
        senderImageOverride: identity?['profileImage'],
        participants: participants,
        replyToSenderId: replyToSenderId,
      );
    } catch (e) {
      debugPrint('Error sending audio file: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send audio file: ${e.toString()}')),
        );
      }
    } finally {
      if (currentUserId != null && mounted) {
        ref
            .read(pendingMessagesProvider.notifier)
            .removeMessage(initialKey, tempId);
        if (chatId != initialKey) {
          ref
              .read(pendingMessagesProvider.notifier)
              .removeMessage(chatId, tempId);
        }
      }
    }

    _scrollToBottom();
  }

  Future<void> _sendAudio(XFile file, int duration, {String? caption}) async {
    final chatRepo = ref.read(chatRepositoryProvider);
    final currentUserId = chatRepo.currentUserId;
    final replyToId = _replyingTo?.id;
    final replyToSenderId = _replyingTo?.senderId;
    final identity = ref.read(chatIdentityProvider);

    // Clear reply immediately
    _clearReply();

    // [PERF] Insert optimistic voice bubble on frame 0 BEFORE any await
    final initialKey = _pendingDmCacheKey;
    final now = DateTime.now().millisecondsSinceEpoch;
    final tempId = 'temp_voice_$now';

    if (currentUserId != null) {
      final optimisticMessage = Message(
        id: tempId,
        chatId: initialKey,
        senderId: identity?['id'] ?? currentUserId,
        senderName: identity?['name'] ?? 'Me',
        senderImage: identity?['profileImage'],
        content: caption?.trim() ?? '',
        type: 'audio',
        documentUrl: file.path,
        audioDuration: duration,
        timestamp: now,
        status: 'sending',
        replyTo: replyToId,
      );

      ref
          .read(pendingMessagesProvider.notifier)
          .addMessage(initialKey, optimisticMessage);
      _scrollToBottom(false);
    }

    final chatId = await _ensureChatCreated();
    if (chatId == null) {
      if (currentUserId != null) {
        ref
            .read(pendingMessagesProvider.notifier)
            .removeMessage(initialKey, tempId);
      }
      return;
    }

    final participants = _getParticipantsSync(chatId);

    try {
      await chatRepo.sendAudioMessage(
        chatId,
        file,
        durationSeconds: duration,
        caption: caption,
        replyToMessageId: replyToId,
        senderIdOverride: identity?['id'],
        senderNameOverride: identity?['name'],
        senderImageOverride: identity?['profileImage'],
        participants: participants,
        replyToSenderId: replyToSenderId,
      );
    } catch (e) {
      debugPrint('Error sending audio: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send voice message: ${e.toString()}'),
          ),
        );
      }
    } finally {
      if (currentUserId != null && mounted) {
        ref
            .read(pendingMessagesProvider.notifier)
            .removeMessage(initialKey, tempId);
        if (chatId != initialKey) {
          ref
              .read(pendingMessagesProvider.notifier)
              .removeMessage(chatId, tempId);
        }
      }
    }

    _scrollToBottom();
  }

  Future<void> _sendDocument(XFile file, String? caption) async {
    final chatRepo = ref.read(chatRepositoryProvider);
    final currentUserId = chatRepo.currentUserId;
    final replyToId = _replyingTo?.id;
    final replyToSenderId = _replyingTo?.senderId;
    final identity = ref.read(chatIdentityProvider);

    // Clear reply immediately
    _clearReply();

    // [PERF] Insert optimistic document bubble on frame 0 BEFORE any await
    final initialKey = _pendingDmCacheKey;
    final now = DateTime.now().millisecondsSinceEpoch;
    final tempId = 'temp_doc_$now';

    if (currentUserId != null) {
      final optimisticMessage = Message(
        id: tempId,
        chatId: initialKey,
        senderId: identity?['id'] ?? currentUserId,
        senderName: identity?['name'] ?? 'Me',
        senderImage: identity?['profileImage'],
        content: caption?.trim() ?? '',
        type: 'document',
        documentUrl: file.path,
        documentName: file.path.split('/').last,
        timestamp: now,
        status: 'sending',
        replyTo: replyToId,
      );

      ref
          .read(pendingMessagesProvider.notifier)
          .addMessage(initialKey, optimisticMessage);
      _scrollToBottom(false);
    }

    final chatId = await _ensureChatCreated();
    if (chatId == null) {
      if (currentUserId != null) {
        ref
            .read(pendingMessagesProvider.notifier)
            .removeMessage(initialKey, tempId);
      }
      return;
    }

    final participants = _getParticipantsSync(chatId);

    try {
      await chatRepo.sendDocumentMessage(
        chatId,
        file,
        caption: caption,
        replyToMessageId: replyToId,
        senderIdOverride: identity?['id'],
        senderNameOverride: identity?['name'],
        senderImageOverride: identity?['profileImage'],
        participants: participants,
        replyToSenderId: replyToSenderId,
      );
    } catch (e) {
      debugPrint('Error sending document: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send document: ${e.toString()}')),
        );
      }
    } finally {
      if (currentUserId != null && mounted) {
        ref
            .read(pendingMessagesProvider.notifier)
            .removeMessage(initialKey, tempId);
        if (chatId != initialKey) {
          ref
              .read(pendingMessagesProvider.notifier)
              .removeMessage(chatId, tempId);
        }
      }
    }

    _scrollToBottom();
  }

  /// Retry sending a failed message
  Future<void> _retryMessage(Message failedMessage) async {
    if (_activeChatId == null) return;

    debugPrint('🔄 Retrying failed message: ${failedMessage.id}');
    final chatRepo = ref.read(chatRepositoryProvider);

    // For text messages, resend with the same content
    if (failedMessage.type == 'text') {
      await chatRepo.sendTextMessage(
        _activeChatId!,
        failedMessage.content,
        replyToMessageId: failedMessage.replyTo,
      );
    }
    // For other types, we'd need to handle differently since we may not have the file
    // For now, show a snackbar for non-text messages
    else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot retry media messages. Please send again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUserId = ref.watch(chatRepositoryProvider).currentUserId ?? '';

    // For pending DM, show special UI
    if (_isPendingDM && _activeChatId == null) {
      return _buildPendingDMScreen(theme, currentUserId);
    }

    // For existing chat, show normal UI with messages
    return _buildChatScreen(theme, currentUserId);
  }

  /// Build screen for pending DM (no messages yet, or optimistic pending messages)
  Widget _buildPendingDMScreen(ThemeData theme, String currentUserId) {
    final pendingMessages =
        ref.watch(pendingMessagesProvider)[_pendingDmCacheKey] ?? const [];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/chats'),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.pendingUserName ?? 'New Chat',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          if (widget.pendingUserId != null)
            ref
                .watch(userProfileByIdProvider(widget.pendingUserId!))
                .when(
                  data: (profile) {
                    if (profile?.phone != null && profile!.phone.isNotEmpty) {
                      return IconButton(
                        icon: const Icon(
                          LucideIcons.phone,
                          color: Colors.green,
                        ),
                        tooltip: 'Call on WhatsApp',
                        onPressed: () async {
                          final success = await WhatsAppUtils.launchWhatsApp(
                            profile.phone,
                          );
                          if (!success && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Could not launch WhatsApp'),
                              ),
                            );
                          }
                        },
                      );
                    }
                    return const SizedBox.shrink();
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                ),
          IconButton(
            icon: const Icon(LucideIcons.moreVertical),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          // Show optimistic messages immediately if sent in pending DM
          Expanded(
            child: pendingMessages.isEmpty
                ? _buildEmptyState(theme)
                : ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 30),
                    itemCount: pendingMessages.length,
                    itemBuilder: (context, index) {
                      final message =
                          pendingMessages[pendingMessages.length - 1 - index];
                      return MessageBubble(
                        key: ValueKey(message.id),
                        message: message,
                        isOwn: true,
                        showAvatar: false,
                        onReply: () => _setReplyTo(message),
                      );
                    },
                  ),
          ),
          // Message input
          MessageInput(
            chatId: '', // Empty for pending DM
            participantIds: widget.pendingUserId != null
                ? [widget.pendingUserId!]
                : [],
            recipientUserId: widget.pendingUserId,
            controller: _messageController, // [NEW] Inject controller
            onSendMessage: (text, {type, metadata}) =>
                _sendMessage(text, metadata: metadata),
            onSendMedia: _sendMedia,
            onSendAudio: _sendAudio,
            onSendAudioFile: _sendAudioFile,
            onSendDocument: _sendDocument,
            // [UPDATED] Split location logic
            onPickLocation: _pickLocation,
            onSendLocation: _sendLocationMessage,
            onSendToken: _sendToken,
            onSendFiat: _sendFiat,
            onMediaSelected: _onMediaPicked, // [NEW] Callback for preview
            replyingTo: _replyingTo,
            onCancelReply: _clearReply,
          ),
        ],
      ),
    );
  }

  /// Open Direct Chat partner action (profile for family, TrustVouchModal otherwise) in 0ms using cached relationship
  void _handleDirectChatHeaderTap({
    required String currentUserId,
    required String targetUid,
    required String displayName,
    String? photoUrl,
  }) {
    if (targetUid.isEmpty || currentUserId.isEmpty) return;

    final rel = ref
        .read(relationshipRepositoryProvider)
        .getCachedRelationship(currentUserId, targetUid);
    final trustRelType =
        ref
            .read(userTrustProvider(currentUserId))
            .value
            ?.relationshipTypes[targetUid] ??
        ref
            .read(trustRepositoryProvider)
            .getCachedTrustData(currentUserId)
            ?.relationshipTypes[targetUid];

    final isFamily =
        (rel != null &&
            rel.status == 'active' &&
            TrustSliderWidget.isFamilyRelationshipType(rel.type)) ||
        TrustSliderWidget.isFamilyRelationshipType(trustRelType);

    if (isFamily) {
      context.push('/profile/$targetUid');
      return;
    }

    TrustVouchModal.show(
      context: context,
      targetUserId: targetUid,
      currentUserId: currentUserId,
      displayName: displayName,
      photoUrl: photoUrl,
    );
  }

  /// Build screen for existing chat with messages
  Widget _buildChatScreen(ThemeData theme, String currentUserId) {
    final isGlobalUnlocked = ref.watch(isGlobalUnlockedSyncProvider);
    if (!isGlobalUnlocked &&
        (_activeChatId == 'global_community' ||
            widget.chatId == 'global_community' ||
            _activeChatId == 'chat_global_community' ||
            widget.chatId == 'chat_global_community')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Global Community Chat')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  LucideIcons.globe,
                  size: 56,
                  color: theme.colorScheme.primary.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'Global Features Coming Soon',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Global community chat will unlock once members from all countries in our network have joined.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () =>
                      context.canPop() ? context.pop() : context.go('/chats'),
                  child: const Text('Back to My Chats'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final chatRepo = ref.read(chatRepositoryProvider);
    final cachedChat = chatRepo.getCachedChat(_activeChatId!);
    final cachedMessages = chatRepo.getCachedMessagesSync(_activeChatId!);
    final displayNameAsync = ref.watch(chatDisplayNameProvider(_activeChatId!));
    final rawChatAsync = ref.watch(chatProvider(_activeChatId!));
    final chatAsync = rawChatAsync.isLoading && cachedChat != null
        ? AsyncData<Chat?>(cachedChat)
        : rawChatAsync;
    final rawMessagesAsync = ref.watch(messagesStreamProvider(_activeChatId!));
    final messagesAsync = rawMessagesAsync.isLoading && cachedMessages != null
        ? AsyncData<List<Message>>(cachedMessages)
        : rawMessagesAsync;
    final typingAsync = ref.watch(typingIndicatorsProvider(_activeChatId!));

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leadingWidth: 40,
        elevation: 1,
        shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.1),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/chats'),
        ),
        title: chatAsync.when(
          skipLoadingOnReload: true,
          skipLoadingOnRefresh: true,
          loading: () => Text(
            cachedChat?.name ?? widget.pendingUserName ?? 'Chat',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          error: (_, _) => Text(
            cachedChat?.name ?? widget.pendingUserName ?? 'Chat',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          data: (chat) {
            if (chat != null && chat.isDirect) {
              final profileAsync = ref.watch(
                chatScreenUserProfileProvider(chat),
              );
              final otherUid = chat.getOtherParticipantId(currentUserId);
              final cachedPartnerProfile = otherUid != null
                  ? ref.read(profileRepositoryProvider).getCachedProfile(
                      otherUid,
                    )
                  : null;
              final resolvedProfile =
                  profileAsync.value ?? cachedPartnerProfile;

              return ChatHeaderTitle(
                profile: resolvedProfile,
                fallbackTitle: displayNameAsync.value ?? chat.name,
                onTap: () {
                  final targetUid = resolvedProfile?.uid ?? otherUid ?? '';
                  if (targetUid.isEmpty) return;
                  _handleDirectChatHeaderTap(
                    currentUserId: currentUserId,
                    targetUid: targetUid,
                    displayName: displayNameAsync.value ?? chat.name,
                    photoUrl: resolvedProfile?.profileImage ?? chat.photoUrl,
                  );
                },
              );
            }

            // Fallback for non-direct chats
            final resolvedDisplayName =
                displayNameAsync.value ??
                chat?.name ??
                widget.pendingUserName ??
                'Chat';

            // [NEW] Fetch live community or event details (with synchronous cache fallback)
            Community? community;
            Event? event;
            Widget? communityAvatar;
            String? eventStatus;
            final viewerHomeCountryCode =
                ref.watch(userProfileProvider).value?.homeCountryCode ??
                ref
                    .read(profileRepositoryProvider)
                    .getCachedProfile(currentUserId)
                    ?.homeCountryCode;

            if (chat?.type == 'community' && chat?.communityId != null) {
              final communityAsync = ref.watch(
                communityDetailsProvider(chat!.communityId!),
              );
              community =
                  communityAsync.value ??
                  ref
                      .read(communityRepositoryProvider)
                      .getCachedCommunity(chat.communityId!);

              // Use live community data if available
              if (community != null) {
                communityAvatar = CommunityChatUtils.getCommunityAvatar(
                  context: context,
                  chat: chat,
                  communityId: community.id,
                  type: community.type,
                  locationType: community.locationType,
                  homeCountryCode: community.homeCountryCode,
                  hostCountryCode: community.hostCountryCode,
                  viewerHomeCountryCode: viewerHomeCountryCode,
                  profileImage: community.profileImage,
                  flag: community.flag,
                  size: 36, // Header specific size
                );
              } else {
                communityAvatar = CommunityChatUtils.getCommunityAvatar(
                  context: context,
                  chat: chat,
                  viewerHomeCountryCode: viewerHomeCountryCode,
                  size: 36,
                );
              }
            } else if (chat?.type == 'community') {
              communityAvatar = CommunityChatUtils.getCommunityAvatar(
                context: context,
                chat: chat,
                viewerHomeCountryCode: viewerHomeCountryCode,
                size: 36,
              );
            } else if (chat?.isEvent == true) {
              final effectiveEventId =
                  chat?.eventId ??
                  ((chat?.id ?? '').startsWith('event_')
                      ? chat!.id.substring('event_'.length)
                      : null);
              if (effectiveEventId != null) {
                // Fetch Event Details with synchronous cache fallback
                final eventAsync = ref.watch(
                  eventDetailsProvider(effectiveEventId),
                );
                event =
                    eventAsync.value ??
                    ref
                        .read(eventRepositoryProvider)
                        .getCachedEvent(effectiveEventId);

                if (event != null) {
                  // Calculate Status using Shared Logic
                  final statusInfo = event.getStatusBadgeInfo();
                  if (statusInfo['text'] != null) {
                    eventStatus = statusInfo['text'];
                  }
                }
              }
            }

            // [UPDATED] Show live member count for all community types
            final showMemberInfo =
                (chat?.type == 'community' || chat?.type == 'group');

            // Corridor chamber dual-flag avatar — render BEFORE the
            // family-group branch so chamber chats get the merged-flag
            // visual in the chat header (matching the chats list).
            if (chat?.type == 'organization' &&
                (chat?.id ?? '').startsWith('org_chamber_')) {
              final host = chat?.hostCountryCode;
              final home = chat?.homeCountryCode;
              if (host != null && home != null) {
                final hostFlag = country_data.getCountryByCode(host)?.flag;
                final homeFlag = country_data.getCountryByCode(home)?.flag;
                if (hostFlag != null && homeFlag != null) {
                  communityAvatar = SizedBox(
                    width: 36,
                    height: 36,
                    child: Stack(
                      children: [
                        Positioned(
                          left: 0,
                          bottom: 0,
                          child: Text(
                            hostFlag,
                            style: const TextStyle(fontSize: 22),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Text(
                            homeFlag,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  );
                }
              }
            }

            // Family group chat avatar
            final isFamilyGroup = chat?.metadata?['isFamilyGroup'] == true;
            Widget? headerAvatar = communityAvatar;
            if (isFamilyGroup && headerAvatar == null) {
              headerAvatar = Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  LucideIcons.heartHandshake,
                  color: Colors.blue.shade600,
                  size: 20,
                ),
              );
            }

            return ChatHeaderTitle(
              profile: null,
              // [FIX] Use consistent community naming logic with live community data preference
              fallbackTitle: (chat?.type == 'community')
                  ? CommunityChatUtils.generateCommunityNameFromParts(
                      name: community?.name ?? chat!.name,
                      locationType:
                          community?.locationType ??
                          chat?.locationType ??
                          'home',
                      id: chat?.id ?? '',
                      homeCountryCode:
                          community?.homeCountryCode ?? chat?.homeCountryCode,
                      hostCountryCode:
                          community?.hostCountryCode ?? chat?.hostCountryCode,
                      viewerHomeCountryCode: viewerHomeCountryCode,
                    )
                  : resolvedDisplayName,
              imageUrl: (chat?.isEvent == true)
                  ? (event?.imageUrl ?? chat?.photoUrl)
                  : chat?.photoUrl,
              // Prioritize pre-rendered widget from utils
              customAvatarWidget: headerAvatar,
              titlePrefixIcon: (chat?.isEvent == true)
                  ? const Icon(
                      LucideIcons.calendar,
                      size: 16,
                      color: Colors.orange,
                    )
                  : (chat?.isOrganization == true)
                  ? const Icon(
                      LucideIcons.building2,
                      size: 16,
                      color: Colors.blue,
                    )
                  : (chat?.type == 'community' &&
                        CommunityChatUtils.isBilateral(
                          chat: chat,
                          id: community?.id ?? chat?.id,
                          locationType:
                              community?.locationType ?? chat?.locationType,
                        ))
                  ? const Icon(
                      LucideIcons.heartHandshake,
                      size: 16,
                      color: AppTheme.accent,
                    )
                  : (chat?.isListingChat == true)
                  ? Icon(
                      LucideIcons.shoppingCart,
                      size: 16,
                      color: Colors.green.shade700,
                    )
                  : (chat?.isGroup == true)
                  ? Icon(
                      isFamilyGroup
                          ? LucideIcons.heartHandshake
                          : LucideIcons.users,
                      size: 16,
                      color: isFamilyGroup
                          ? Colors.blue.shade600
                          : Colors.green,
                    )
                  : null,
              // Legacy fallback
              customImage:
                  null, // [FIXED] Type mismatch, handled by customAvatarWidget above
              // Show count if available
              memberCount: showMemberInfo
                  ? (community?.totalMembers ??
                        ((chat?.type == 'group')
                            ? chat?.participants.length
                            : chat?.memberCount))
                  : null,
              memberLabel: (chat?.isListingChat == true)
                  ? 'shoppers'
                  : 'members',
              // [NEW] Event Status
              eventStatus: eventStatus,
              onTap: () {
                if (chat?.type == 'organization' &&
                    (chat?.id ?? '').startsWith('org_chamber_')) {
                  final orgId = chat!.id.replaceFirst('org_', '');
                  context.push('/organization/$orgId');
                } else if (chat?.isListingChat == true &&
                    chat?.metadata?['listingId'] != null) {
                  context.push(
                    '/marketplace/listing/${chat!.metadata!['listingId']}',
                  );
                } else if (chat?.type == 'group' ||
                    chat?.type == 'organization') {
                  context.push(
                    '/chats/${chat!.id}/info',
                    extra: {
                      'name': chat.name,
                      'image': chat.photoUrl,
                      'type': chat.type,
                    },
                  );
                } else if (chat?.type == 'direct') {
                  final currentUid =
                      ref.read(authRepositoryProvider).currentUser?.uid ??
                      currentUserId;
                  final otherId = chat?.participants.firstWhere(
                    (id) => id != currentUid,
                    orElse: () => '',
                  );
                  if (otherId != null &&
                      otherId.isNotEmpty &&
                      currentUid.isNotEmpty) {
                    _handleDirectChatHeaderTap(
                      currentUserId: currentUid,
                      targetUid: otherId,
                      displayName: resolvedDisplayName,
                      photoUrl: chat?.photoUrl,
                    );
                  }
                } else if (chat?.type == 'community' && community != null) {
                  context.push(
                    '/communities/${community.id}/members',
                    extra: community,
                  );
                } else if (chat?.isEvent == true) {
                  final effectiveEventId =
                      chat?.eventId ??
                      ((chat?.id ?? '').startsWith('event_')
                          ? chat!.id.substring('event_'.length)
                          : null);
                  if (effectiveEventId != null) {
                    context.push(
                      '/events/$effectiveEventId?fromChat=true',
                      extra: event,
                    );
                  }
                }
              },
            );
          },
        ),
        actions: [
          // WhatsApp Call Button
          if (chatAsync.value?.isDirect == true)
            ref
                .watch(chatScreenUserProfileProvider(chatAsync.value!))
                .when(
                  data: (profile) {
                    if (profile?.phone != null && profile!.phone.isNotEmpty) {
                      return IconButton(
                        icon: const Icon(
                          LucideIcons.phone,
                          color: Colors.green,
                        ),
                        tooltip: 'Call on WhatsApp',
                        onPressed: () async {
                          final success = await WhatsAppUtils.launchWhatsApp(
                            profile.phone,
                          );
                          if (!success && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Could not launch WhatsApp'),
                              ),
                            );
                          }
                        },
                      );
                    }
                    return const SizedBox.shrink();
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                ),

          // More Options Menu (Only if member)
          Builder(
            builder: (context) {
              final chat = chatAsync.value;
              // Basic participant check
              var isParticipant =
                  chat?.participants.contains(currentUserId) ?? false;

              // Extended check for Events (Creator/Attendee)
              if (chat?.isEvent == true && !isParticipant) {
                final effectiveEventId =
                    chat?.eventId ??
                    ((chat?.id ?? '').startsWith('event_')
                        ? chat!.id.substring('event_'.length)
                        : null);
                if (effectiveEventId != null) {
                  final eventAsync = ref.watch(
                    eventDetailsProvider(effectiveEventId),
                  );
                  final event =
                      eventAsync.value ??
                      ref
                          .read(eventRepositoryProvider)
                          .getCachedEvent(effectiveEventId);
                  if (event != null) {
                    final isCreator = event.creatorId == currentUserId;
                    final isAttendee =
                        event.attendees?.contains(currentUserId) ?? false;
                    if (isCreator || isAttendee) {
                      isParticipant = true;
                    }
                  }
                }
              }

              if (chat != null && isParticipant) {
                return IconButton(
                  icon: const Icon(LucideIcons.moreVertical),
                  onPressed: () {
                    _showMoreMenu(context, chat, ref);
                  },
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      resizeToAvoidBottomInset: !kIsWeb,
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: messagesAsync.when(
              skipLoadingOnReload: true,
              skipLoadingOnRefresh: true,
              // Show cache/optimistic immediately if avail, otherwise loading if empty & loading
              loading: () {
                final pending =
                    ref.watch(pendingMessagesProvider)[_activeChatId!] ?? [];
                if (pending.isNotEmpty) {
                  return ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 30),
                    itemCount: pending.length,
                    itemBuilder: (context, index) {
                      final message = pending[pending.length - 1 - index];
                      return MessageBubble(
                        key: ValueKey(message.id),
                        message: message,
                        isOwn: message.isOwnMessage(currentUserId),
                        showAvatar: chatAsync.value?.type != 'direct',
                        onReply: () => _setReplyTo(message),
                      );
                    },
                  );
                }
                return const Center(child: CircularProgressIndicator());
              },
              error: (error, stack) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      LucideIcons.alertCircle,
                      size: 48,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    const Text('Error loading messages'),
                    TextButton(
                      onPressed: () => ref.invalidate(
                        messagesStreamProvider(_activeChatId!),
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (streamMessages) {
                // [NEW] Merge with pending messages
                final pendingMessages =
                    ref.watch(pendingMessagesProvider)[_activeChatId!] ?? [];

                // Merge strategies:
                // Deduplicate: if a stream message matches a pending message
                // (same sender + similar timestamp), skip the stream copy.
                final filteredStream = pendingMessages.isEmpty
                    ? streamMessages
                    : streamMessages.where((sm) {
                        return !pendingMessages.any(
                          (pm) =>
                              pm.senderId == sm.senderId &&
                              pm.type == sm.type &&
                              (sm.timestamp - pm.timestamp).abs() < 5000 &&
                              (pm.content == sm.content ||
                                  pm.content.isEmpty ||
                                  sm.content.isEmpty),
                        );
                      }).toList();

                final allMessages = [...pendingMessages, ...filteredStream];
                allMessages.sort((a, b) => b.timestamp.compareTo(a.timestamp));

                if (allMessages.isEmpty) {
                  return _buildEmptyState(
                    theme,
                    chat: chatAsync.value,
                    currentUserId: currentUserId,
                  );
                }

                // Initial scroll is bottom (offset 0) by default in reverse mode.

                return Stack(
                  children: [
                    ListView.builder(
                      controller: _scrollController,
                      reverse: true, // [NEW] Bottom is index 0
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 30),
                      itemCount: allMessages.length,
                      itemBuilder: (context, index) {
                        final message = allMessages[index];
                        final isOwn = message.isOwnMessage(currentUserId);

                        // Date Separator Logic (Reverse)
                        // Show separator if this is the TOP message (last index)
                        // OR if the NEXT message (index+1, which is OLDER) has different date.
                        bool showDateSeparator = false;
                        if (index == allMessages.length - 1) {
                          showDateSeparator = true;
                        } else {
                          // Ensure index+1 is valid
                          if (index + 1 < allMessages.length) {
                            final nextMessage = allMessages[index + 1];
                            showDateSeparator = _shouldShowDateSeparator(
                              nextMessage.timestamp,
                              message.timestamp,
                            );
                          }
                        }

                        // For Reply logic: find message in full list
                        Message? repliedMessage;
                        if (message.replyTo != null) {
                          repliedMessage = allMessages.firstWhere(
                            (m) => m.id == message.replyTo,
                            orElse: () => const Message(
                              id: '',
                              chatId: '',
                              senderId: '',
                              senderName: 'Unknown',
                              content: 'Message not found',
                              type: 'text',
                              timestamp: 0,
                            ),
                          );
                          if (repliedMessage.id.isEmpty) {
                            repliedMessage = null;
                          }
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // In reverse list, item N is ABOVE item N-1.
                            // But within item N, we want DateSeparator ABOVE the bubble.
                            if (showDateSeparator)
                              _buildDateSeparator(message.timestamp, theme),

                            VisibilityDetector(
                              key: Key('msg_visibility_${message.id}'),
                              onVisibilityChanged: (info) =>
                                  _onMessageVisibilityChanged(
                                    info,
                                    message,
                                    currentUserId,
                                  ),
                              child: MessageBubble(
                                key: _messageKeys.putIfAbsent(
                                  message.id,
                                  () => GlobalKey(),
                                ),
                                message: message,
                                isOwn: isOwn,
                                showAvatar: chatAsync.value?.type != 'direct',
                                sellerRole: _getSellerRoleForMessage(
                                  chatAsync.value,
                                  message,
                                  currentUserId,
                                ),
                                onReply: () => _setReplyTo(message),
                                onReplyTap: _scrollToMessage,
                                onLongPress: () =>
                                    _handleMessageAction(context, message, ref),
                                onRetry: message.status == 'error'
                                    ? () => _retryMessage(message)
                                    : null,
                                repliedMessage: repliedMessage,
                                isHighlighted:
                                    message.id == _highlightedMessageId,
                              ),
                            ),
                          ],
                        );
                      },
                    ),

                    // WhatsApp-style Scroll to Bottom FAB
                    ChatScrollToBottomFAB(
                      onTap: () => _scrollToBottom(),
                      visible: !_isNearBottom,
                    ),
                  ],
                );
              },
            ),
          ),

          // Typing indicator (above input)
          typingAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (typingUsers) =>
                ChatTypingIndicator(typingUsers: typingUsers),
          ),
          // Message input or restriction message
          Builder(
            builder: (context) {
              final chat = chatAsync.value;
              var isParticipant =
                  chat?.participants.contains(currentUserId) ?? false;

              // [FIX] For Event Chats, also check Firestore Event Attendees (Source of Truth)
              if (chat?.isEvent == true &&
                  chat?.eventId != null &&
                  !isParticipant) {
                final eventAsync = ref.watch(
                  eventDetailsProvider(chat!.eventId!),
                );
                final event =
                    eventAsync.value ??
                    ref
                        .read(eventRepositoryProvider)
                        .getCachedEvent(chat.eventId!);
                if (event != null) {
                  final isCreator = event.creatorId == currentUserId;
                  final isAttendee =
                      event.attendees?.contains(currentUserId) ?? false;
                  if (isCreator || isAttendee) {
                    isParticipant = true;
                  }
                }
              }

              // Corridor chamber: followers can read but not post.
              // Substitute the input with an upgrade banner when accessLevel
              // is anything other than 'member' on the user's userChats doc.
              final isChamberChat =
                  chat != null &&
                  chat.type == 'organization' &&
                  chat.id.startsWith('org_chamber_');

              // [MODIFIED] Only allow messaging if participant OR it's a direct chat
              if (chat != null &&
                  !isParticipant &&
                  chat.type != 'direct' &&
                  !isChamberChat) {
                return ChatRestrictionView(
                  isCommunity: chat.isCommunity,
                  isOrganization: chat.isOrganization,
                  isEvent: chat.isEvent,
                  isListingChat: chat.isListingChat,
                  chatName: chat.name,
                  chatType: chat.type,
                  onJoin: (chat.type == 'group')
                      ? () {
                          final repo = ref.read(chatRepositoryProvider);
                          // [PERF] Optimistically add currentUserId to participants in 0ms
                          if (currentUserId.isNotEmpty) {
                            final updatedChat = chat.copyWith(
                              participants: {
                                ...chat.participants,
                                currentUserId,
                              }.toList(),
                            );
                            repo.upsertChatInCache(updatedChat);
                            ref.invalidate(chatProvider(chat.id));
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                chat.isListingChat
                                    ? 'Joined shop!'
                                    : 'Joined group!',
                              ),
                            ),
                          );
                          unawaited(
                            repo.joinGroup(chat.id).then((_) {
                              if (mounted) {
                                ref.invalidate(chatProvider(chat.id));
                                ref.invalidate(messagesStreamProvider(chat.id));
                              }
                            }).catchError((Object e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Failed to join: $e')),
                                );
                              }
                            }),
                          );
                        }
                      : null,
                );
              }

              if (isChamberChat) {
                return _ChamberFollowerGate(
                  chatId: chat.id,
                  orgId: chat.id.replaceFirst('org_', ''),
                  uid: currentUserId,
                  fullInput: SafeArea(
                    child: MessageInput(
                      controller: _messageController,
                      chatId: _activeChatId!,
                      participantIds: chat.participants
                          .where((id) => id != currentUserId)
                          .toList(),
                      recipientUserId: null,
                      onSendMessage: (text, {type, metadata}) =>
                          _sendMessage(text, metadata: metadata),
                      onSendMedia: _sendMedia,
                      onSendAudio: _sendAudio,
                      onSendAudioFile: _sendAudioFile,
                      onSendDocument: _sendDocument,
                      onPickLocation: _pickLocation,
                      onSendLocation: _sendLocationMessage,
                      onSendToken: _sendToken,
                      onSendFiat: _sendFiat,
                      onMediaSelected: _onMediaPicked,
                      onCancelReply: _clearReply,
                      replyingTo: _replyingTo,
                    ),
                  ),
                );
              }

              return SafeArea(
                child: MessageInput(
                  controller: _messageController, // [NEW] Inject controller
                  chatId: _activeChatId!,
                  participantIds:
                      chat?.participants
                          .where((id) => id != currentUserId)
                          .toList() ??
                      [],
                  // [NEW] Pass recipient ID for transfers (only valid for Direct chats)
                  recipientUserId: (chat?.isDirect == true)
                      ? chat?.participants
                            .where((id) => id != currentUserId)
                            .firstOrNull
                      : null,
                  onSendMessage: (text, {type, metadata}) =>
                      _sendMessage(text, metadata: metadata),
                  onSendMedia: _sendMedia,
                  onSendAudio: _sendAudio,
                  onSendAudioFile: _sendAudioFile,
                  onSendDocument: _sendDocument,
                  // [UPDATED] Split location logic
                  onPickLocation: _pickLocation,
                  onSendLocation: _sendLocationMessage,
                  onSendToken: _sendToken,
                  onSendFiat: _sendFiat,
                  onMediaSelected: _onMediaPicked, // [NEW] Callback for preview
                  onCancelReply: _clearReply,
                  replyingTo: _replyingTo,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  bool _shouldShowDateSeparator(int prevTimestamp, int currTimestamp) {
    final prevDate = DateTime.fromMillisecondsSinceEpoch(prevTimestamp);
    final currDate = DateTime.fromMillisecondsSinceEpoch(currTimestamp);
    return prevDate.day != currDate.day ||
        prevDate.month != currDate.month ||
        prevDate.year != currDate.year;
  }

  /// Returns the seller role badge text for listing chats, or null for
  /// non-listing chats or the buyer's own messages.
  String? _getSellerRoleForMessage(
    dynamic chat,
    Message message,
    String currentUserId,
  ) {
    if (chat == null) return null;
    final metadata = chat.metadata;
    if (metadata == null || metadata['isListingChat'] != true) return null;

    // Only show the role badge on the *seller's* messages (not the buyer's)
    // The seller is the "other" participant (the one who received the chat)
    final isMessageFromSeller = message.senderId != currentUserId;
    if (!isMessageFromSeller) return null;

    return metadata['sellerRole'] as String?;
  }

  Widget _buildDateSeparator(int timestamp, ThemeData theme) {
    return ChatDateSeparator(timestamp: timestamp);
  }

  Widget _buildEmptyState(
    ThemeData theme, {
    Chat? chat,
    String? currentUserId,
  }) {
    final isListing = chat?.isListingChat == true;
    final isSeller =
        isListing &&
        currentUserId != null &&
        (chat?.createdBy == currentUserId ||
            (chat?.admins?.contains(currentUserId) ?? false));
    return ChatEmptyState(
      isListingChat: isListing,
      listingType: chat?.metadata?['listingType']?.toString(),
      isSeller: isSeller,
      onQuickPromptTap: isListing ? (prompt) => _sendMessage(prompt) : null,
    );
  }

  void _onMessageVisibilityChanged(
    VisibilityInfo info,
    Message message,
    String currentUserId,
  ) {
    // Only mark as read if:
    // 1. It's visible (visibleFraction > 0.5)
    // 2. It's NOT our own message
    // 3. It's not already read
    // 4. We haven't already queued it
    if (info.visibleFraction > 0.5 &&
        message.senderId != currentUserId &&
        message.status != 'read' &&
        !_visibleUnreadMessageIds.contains(message.id)) {
      _visibleUnreadMessageIds.add(message.id);

      // Debounce the update
      if (_readReceiptDebounceTimer?.isActive ?? false) {
        _readReceiptDebounceTimer!.cancel();
      }
      _readReceiptDebounceTimer = Timer(
        const Duration(milliseconds: 500),
        _processVisibleMessages,
      );
    }
  }

  Future<void> _processVisibleMessages() async {
    if (_visibleUnreadMessageIds.isEmpty || _activeChatId == null) return;

    final ids = _visibleUnreadMessageIds.toList();
    _visibleUnreadMessageIds
        .clear(); // Clear immediately to prevent double processing

    debugPrint('👀 Marking ${ids.length} messages as read');
    try {
      await ref
          .read(chatRepositoryProvider)
          .markMessagesAsRead(_activeChatId!, ids);
    } catch (e) {
      debugPrint('Error marking messages as read: $e');
    }
  }

  Future<void> _showMoreMenu(
    BuildContext context,
    Chat chat,
    WidgetRef ref,
  ) async {
    if (_isShowingMoreMenu) return;
    _isShowingMoreMenu = true;

    final repo = ref.read(chatRepositoryProvider);
    final currentUserId = repo.currentUserId ?? '';
    final isDirect = chat.isDirect;
    final isCommunity = chat.isCommunity;

    // [PERF] Resolve all initial state synchronously from memory caches in 0ms!
    String displayName =
        ref.read(chatDisplayNameProvider(chat.id)).value ?? chat.name;
    final otherUserId = isDirect && currentUserId.isNotEmpty
        ? chat.getOtherParticipantId(currentUserId)
        : null;
    if (displayName.isEmpty && otherUserId != null) {
      displayName =
          ref
              .read(profileRepositoryProvider)
              .getCachedProfile(otherUserId)
              ?.fullName ??
          chat.name;
    }

    final relRepo = ref.read(relationshipRepositoryProvider);
    Relationship? existingRelationship = otherUserId != null
        ? relRepo.getCachedRelationship(currentUserId, otherUserId)
        : null;
    RelationshipRequest? pendingSentRequest =
        (existingRelationship == null && otherUserId != null)
        ? relRepo.getCachedPendingSentRequest(
            fromUserId: currentUserId,
            toUserId: otherUserId,
          )
        : null;
    RelationshipRequest? pendingIncomingRequest =
        (existingRelationship == null &&
            pendingSentRequest == null &&
            otherUserId != null)
        ? relRepo.getCachedPendingIncomingRequest(
            userId: currentUserId,
            fromUserId: otherUserId,
          )
        : null;

    final effectiveEventId = chat.isEvent
        ? (chat.eventId ??
              (chat.id.startsWith('event_')
                  ? chat.id.substring('event_'.length)
                  : null))
        : null;
    Event? event = effectiveEventId != null
        ? (ref.read(eventDetailsProvider(effectiveEventId)).value ??
              ref.read(eventRepositoryProvider).getCachedEvent(effectiveEventId))
        : null;

    Community? community = (isCommunity && chat.communityId != null)
        ? (ref.read(communityDetailsProvider(chat.communityId!)).value ??
              ref
                  .read(communityRepositoryProvider)
                  .getCachedCommunity(chat.communityId!))
        : null;
    GovernanceUnit? governanceUnit = (isCommunity && chat.communityId != null)
        ? ref
              .read(governanceRepositoryProvider)
              .getCachedGovernanceUnit(chat.communityId!)
        : null;

    final myCachedProfile =
        ref.read(userProfileProvider).value ??
        (currentUserId.isNotEmpty
            ? ref
                  .read(profileRepositoryProvider)
                  .getCachedProfile(currentUserId)
            : null);
    bool hasAnyProfileField = myCachedProfile != null
        ? myCachedProfile.completedMilestoneFieldCount > 0
        : true;
    bool hasVerifiedTarget = (otherUserId != null && currentUserId.isNotEmpty)
        ? (ref
                  .read(trustRepositoryProvider)
                  .getCachedHasVerifiedUser(currentUserId, otherUserId) ??
              false)
        : false;

    final outerContext = context;
    void Function(void Function())? setModalState;

    // Kick off non-blocking background refresh so any uncached fields update live in the open sheet
    unawaited(() async {
      bool changed = false;
      try {
        final resolvedName = await repo.getDisplayNameForChat(chat);
        if (resolvedName.isNotEmpty && resolvedName != displayName) {
          displayName = resolvedName;
          changed = true;
        }
      } catch (_) {}

      if (isDirect && currentUserId.isNotEmpty && otherUserId != null) {
        final results = await Future.wait<Object?>([
          relRepo.getRelationship(
            userId: currentUserId,
            relatedUserId: otherUserId,
          ),
          ref.read(profileRepositoryProvider).getUserProfile(currentUserId),
          ref
              .read(trustRepositoryProvider)
              .hasVerifiedUser(currentUserId, otherUserId),
        ]);
        final rel = results[0] as Relationship?;
        if (rel != existingRelationship) {
          existingRelationship = rel;
          changed = true;
        }
        if (existingRelationship == null) {
          final reqResults = await Future.wait([
            relRepo.getPendingSentRequest(
              fromUserId: currentUserId,
              toUserId: otherUserId,
            ),
            relRepo.getPendingIncomingRequest(
              userId: currentUserId,
              fromUserId: otherUserId,
            ),
          ]);
          if (reqResults[0] != pendingSentRequest ||
              reqResults[1] != pendingIncomingRequest) {
            pendingSentRequest = reqResults[0];
            pendingIncomingRequest = reqResults[1];
            changed = true;
          }
        }
        final myProfile = results[1];
        if (myProfile != null) {
          final nextHasField =
              (myProfile as dynamic).completedMilestoneFieldCount > 0;
          if (nextHasField != hasAnyProfileField) {
            hasAnyProfileField = nextHasField;
            changed = true;
          }
        }
        final nextVerified = results[2] as bool? ?? false;
        if (nextVerified != hasVerifiedTarget) {
          hasVerifiedTarget = nextVerified;
          changed = true;
        }
      }

      if (effectiveEventId != null && event == null) {
        try {
          final fetchedEvent = await ref
              .read(eventRepositoryProvider)
              .getEvent(effectiveEventId);
          if (fetchedEvent != null) {
            event = fetchedEvent;
            changed = true;
          }
        } catch (_) {}
      }

      if (isCommunity && chat.communityId != null) {
        final commResults = await Future.wait<Object?>([
          if (governanceUnit == null)
            ref
                .read(governanceRepositoryProvider)
                .getGovernanceUnitByCommunityId(chat.communityId!)
          else
            Future.value(governanceUnit),
          if (community == null)
            ref
                .read(communityRepositoryProvider)
                .getCommunity(chat.communityId!)
          else
            Future.value(community),
        ]);
        final nextGov = commResults[0] as GovernanceUnit?;
        final nextComm = commResults[1] as Community?;
        if (nextGov != governanceUnit || nextComm != community) {
          governanceUnit = nextGov;
          community = nextComm;
          changed = true;
        }
      }

      if (changed && setModalState != null) {
        try {
          setModalState!(() {});
        } catch (_) {}
      }
    }());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: StatefulBuilder(
          builder: (context, setSheetState) {
            setModalState = setSheetState;
            return ChatMoreMenuSheet(
              chat: chat,
              displayName: displayName,
              existingRelationship: existingRelationship,
              pendingSentRequest: pendingSentRequest,
              pendingIncomingRequest: pendingIncomingRequest,
              community: community,
              event: event,
              governanceUnit: governanceUnit,
              hasAnyProfileField: hasAnyProfileField,
              hasVerifiedTarget: hasVerifiedTarget,
              onAddRelationship: () {
                Navigator.pop(context);
                _showRelationshipPicker(
                  outerContext,
                  ref,
                  chat.getOtherParticipantId(currentUserId),
                  displayName,
                );
              },
              onAcceptRelationshipRequest: pendingIncomingRequest == null
                  ? null
                  : () {
                      final req = pendingIncomingRequest!;
                      Navigator.pop(context);
                      showModalBottomSheet(
                        context: outerContext,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: RelationshipResponseModal(request: req),
                        ),
                      );
                    },
              onQRExchange: () async {
                final user = ref.read(authRepositoryProvider).currentUser;
                if (user == null) return;
                final profileRepo = ref.read(profileRepositoryProvider);
                final myProfile =
                    ref.read(userProfileProvider).value ??
                    profileRepo.getCachedProfile(user.uid) ??
                    await profileRepo.getUserProfile(user.uid);
                if (myProfile != null && outerContext.mounted) {
                  showDialog(
                    context: outerContext,
                    useRootNavigator: true,
                    builder: (_) => BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: ProfileQRCodeDialog(profile: myProfile),
                    ),
                  );
                } else if (outerContext.mounted) {
                  ScaffoldMessenger.of(outerContext).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Unable to load your profile for QR exchange.',
                      ),
                    ),
                  );
                }
              },
              onVerifyUser: () {
                Navigator.pop(context);
                _handleVerifyChatUser(outerContext, ref, chat);
              },
              onVouchUser: () {
                Navigator.pop(context);
                final currentUid =
                    ref.read(authRepositoryProvider).currentUser?.uid;
                final otherId = chat.getOtherParticipantId(currentUid ?? '');
                if (otherId != null && currentUid != null) {
                  TrustVouchModal.show(
                    context: outerContext,
                    targetUserId: otherId,
                    currentUserId: currentUid,
                    displayName: displayName,
                    photoUrl: chat.photoUrl,
                  );
                }
              },
              onClearChat: () {
                Navigator.pop(context);
                _showClearConfirmation(
                  outerContext,
                  repo,
                  chat.id,
                  displayName,
                );
              },
              onDeleteChat: () {
                Navigator.pop(context);
                _showDeleteConfirmation(
                  outerContext,
                  repo,
                  chat.id,
                  displayName,
                  isLeave: false,
                );
              },
              onLeaveChat: () {
                Navigator.pop(context);
                _showDeleteConfirmation(
                  outerContext,
                  repo,
                  chat.id,
                  displayName,
                  isLeave: true,
                  titleOverride: chat.isListingChat
                      ? 'Leave Shop?'
                      : chat.isGroup
                      ? 'Leave Group?'
                      : chat.isEvent
                      ? 'Leave Event?'
                      : 'Unfollow Organization?',
                );
              },
              onBlockUser: () async {
                Navigator.pop(context);
                final otherId = chat.getOtherParticipantId(currentUserId);
                if (otherId == null) return;

                final confirm = await showDialog<bool>(
                  context: outerContext,
                  builder: (context) => BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: AlertDialog(
                      insetPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 24,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide.none,
                      ),
                      title: const Text('Block User?'),
                      content: const Text(
                        'They will not be able to message you or see your profile.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.error,
                          ),
                          child: const Text('Block'),
                        ),
                      ],
                    ),
                  ),
                );

                if (confirm == true) {
                  // [PERF] Pop screen & show snackbar immediately in 0ms
                  if (outerContext.mounted) {
                    outerContext.pop();
                    ScaffoldMessenger.of(outerContext).showSnackBar(
                      const SnackBar(
                        content: Text('User blocked'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                  unawaited(
                    ref
                        .read(relationshipRepositoryProvider)
                        .blockUser(userId: currentUserId, relatedUserId: otherId)
                        .catchError((Object e) {
                          debugPrint('Error blocking user: $e');
                        }),
                  );
                }
              },
              onReportUser: () {
                Navigator.pop(context);
                final otherId = chat.getOtherParticipantId(currentUserId);
                if (otherId != null) {
                  _handleReportUser(outerContext, ref, otherId, displayName);
                }
              },
              onUnblockUser: () {
                Navigator.pop(context);
                final otherId = chat.getOtherParticipantId(currentUserId);
                if (otherId == null) return;
                // [PERF] Show snackbar immediately in 0ms
                if (outerContext.mounted) {
                  ScaffoldMessenger.of(outerContext).showSnackBar(
                    const SnackBar(
                      content: Text('User unblocked'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
                unawaited(
                  ref
                      .read(relationshipRepositoryProvider)
                      .unblockUser(userId: currentUserId, relatedUserId: otherId)
                      .catchError((Object e) {
                        if (outerContext.mounted) {
                          ScaffoldMessenger.of(outerContext).showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
                        }
                      }),
                );
              },
              onStartGroupChat: () {
                Navigator.pop(context);
                final otherId = chat.getOtherParticipantId(currentUserId);
                Navigator.of(outerContext).push(
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (context) =>
                        CreateGroupScreen(initialParticipantId: otherId),
                  ),
                );
              },
              onCreateGroupEvent: () {
                Navigator.pop(context);
                outerContext.push(
                  Uri(
                    path: '/events/create',
                    queryParameters: {'groupId': chat.id},
                  ).toString(),
                );
              },
              onShareCommunity: () {
                Navigator.pop(context);
                if (community != null) {
                  showDialog(
                    context: outerContext,
                    builder: (context) => BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: ShareCommunityDialog(community: community!),
                    ),
                  );
                }
              },
              onCreateCommunityGroup: () {
                Navigator.pop(context);
                Navigator.push(
                  outerContext,
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (context) =>
                        CreateGroupScreen(communityId: chat.communityId),
                  ),
                );
              },
              onCreateCommunityEvent: () {
                Navigator.pop(context);
                outerContext.push(
                  Uri(
                    path: '/events/create',
                    queryParameters: {
                      if (chat.communityId != null)
                        'communityId': chat.communityId,
                    },
                  ).toString(),
                );
              },
              onCreateCommunityOrg: () {
                Navigator.pop(context);
                showModalBottomSheet(
                  context: outerContext,
                  isScrollControlled: true,
                  useSafeArea: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: BusinessRegistrationModal(
                      communityId: chat.communityId,
                    ),
                  ),
                );
              },
              onDDILoans: () {
                Navigator.pop(context);
                Navigator.push(
                  outerContext,
                  MaterialPageRoute(
                    builder: (context) => DdiLoansScreen(
                      communityId: chat.communityId,
                      community: community,
                    ),
                  ),
                );
              },
              onChamberOfCommerce: () {
                Navigator.pop(context);
                final profile =
                    ref.read(userProfileProvider).value ??
                    ref
                        .read(profileRepositoryProvider)
                        .getCachedProfile(currentUserId);
                final homeCode = profile?.homeCountryCode;
                final hostCode =
                    community?.hostCountryCode ??
                    community?.homeCountryCode ??
                    chat.hostCountryCode ??
                    profile?.hostCountryCode;

                if (homeCode != null &&
                    hostCode != null &&
                    homeCode.toUpperCase() != hostCode.toUpperCase()) {
                  final chamberId =
                      'chamber_${hostCode.toLowerCase()}_${homeCode.toLowerCase()}';
                  final reverseChamberId =
                      'chamber_${homeCode.toLowerCase()}_${hostCode.toLowerCase()}';
                  final orgRepo = ref.read(organizationRepositoryProvider);
                  final targetOrgId =
                      orgRepo.getCachedOrganization(chamberId) != null
                      ? chamberId
                      : (orgRepo.getCachedOrganization(reverseChamberId) != null
                            ? reverseChamberId
                            : chamberId);

                  if (outerContext.mounted) {
                    Navigator.push(
                      outerContext,
                      MaterialPageRoute(
                        builder: (context) =>
                            OrganizationDetailScreen(orgId: targetOrgId),
                      ),
                    );
                  }
                } else {
                  if (outerContext.mounted) {
                    Navigator.push(
                      outerContext,
                      MaterialPageRoute(
                        builder: (context) =>
                            GviCorridorListScreen(homeCountry: hostCode ?? ''),
                      ),
                    );
                  }
                }
              },
              onChambersOfCommerce: () {
                Navigator.pop(context);
                final homeCode =
                    community?.homeCountryCode ??
                    community?.hostCountryCode ??
                    chat.homeCountryCode ??
                    ref.read(userProfileProvider).value?.homeCountryCode ??
                    '';
                Navigator.push(
                  outerContext,
                  MaterialPageRoute(
                    builder: (context) =>
                        GviCorridorListScreen(homeCountry: homeCode),
                  ),
                );
              },
              onLeaderElections: () {
                Navigator.pop(context);
                _handleLeaderElections(
                  outerContext,
                  chat,
                  governanceUnit,
                  community,
                );
              },
            );
          },
        ),
      ),
    ).then((_) {
      setModalState = null;
      _isShowingMoreMenu = false;
    });
  }

  void _handleLeaderElections(
    BuildContext context,
    Chat chat,
    GovernanceUnit? governanceUnit,
    Community? community,
  ) {
    String? unitId = governanceUnit?.id;

    if (unitId == null && community != null) {
      if (community.type == 'global') {
        unitId = 'global';
      } else if (community.type == 'continent') {
        final continentName = community.name
            .replaceAll(' Community', '')
            .toLowerCase()
            .replaceAll(' ', '_');
        unitId = 'continent_$continentName';
      } else if (community.type == 'country') {
        final countryCode =
            community.homeCountryCode?.toLowerCase() ??
            (community.location?['countryCode']?.toString().toLowerCase()) ??
            (community.name.replaceAll(' Community', '').toLowerCase());
        unitId = 'country_$countryCode';
      } else {
        unitId = chat.communityId;
      }
    }

    if (unitId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              LeaderSelectionScreen(unitId: unitId!, community: community),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Governance not initialized for this community.'),
        ),
      );
    }
  }

  // $DIASPORA Token Transfer Logic (Smart Wallet) — 0ms Optimistic Bubble
  Future<void> _sendToken(int amount, String? caption) async {
    final chatRepo = ref.read(chatRepositoryProvider);
    final currentUserId = chatRepo.currentUserId;
    if (currentUserId == null) return;

    String? toUserId = widget.pendingUserId ?? _activePartnerUserId;
    if (toUserId == null && _activeChatId != null) {
      final cachedChat = chatRepo.getCachedChat(_activeChatId!);
      toUserId = cachedChat?.getOtherParticipantId(currentUserId);
    }

    final identity = ref.read(chatIdentityProvider);
    final initialKey = _pendingDmCacheKey;
    final now = DateTime.now().millisecondsSinceEpoch;
    final tempId = 'temp_token_$now';
    final displayContent = caption?.isNotEmpty == true
        ? caption!
        : 'Sent $amount \$DIASPORA';

    // [PERF] Insert optimistic token transfer bubble on frame 0
    final optimisticMessage = Message(
      id: tempId,
      chatId: initialKey,
      senderId: identity?['id'] ?? currentUserId,
      senderName: identity?['businessName'] ?? identity?['name'] ?? 'Me',
      senderImage: identity?['profileImage'],
      content: displayContent,
      type: 'dsp_transfer',
      timestamp: now,
      status: 'sending',
      metadata: {
        'amount': amount,
        'currency': 'DIASPORA',
        'assetType': 'token',
      },
    );

    ref
        .read(pendingMessagesProvider.notifier)
        .addMessage(initialKey, optimisticMessage);
    _scrollToBottom(false);

    final chatId = await _ensureChatCreated();
    if (chatId == null) {
      ref
          .read(pendingMessagesProvider.notifier)
          .removeMessage(initialKey, tempId);
      return;
    }

    if (toUserId == null) {
      final chat =
          chatRepo.getCachedChat(chatId) ?? await chatRepo.getChat(chatId);
      toUserId = chat?.getOtherParticipantId(currentUserId);
    }

    if (toUserId == null || toUserId.isEmpty) {
      ref
          .read(pendingMessagesProvider.notifier)
          .removeMessage(initialKey, tempId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              r'$DIASPORA token transfer currently only supported in Direct Messages.',
            ),
          ),
        );
      }
      return;
    }

    final participants = _getParticipantsSync(chatId);

    try {
      await ref
          .read(pointsServiceProvider)
          .transferAsset(
            fromUserId: currentUserId,
            toUserId: toUserId,
            amount: amount,
            assetType: 'token',
          );

      await chatRepo.sendTextMessage(
        chatId,
        displayContent,
        type: 'dsp_transfer',
        senderIdOverride: identity?['id'],
        senderNameOverride: identity?['businessName'] ?? identity?['name'],
        senderImageOverride: identity?['profileImage'],
        metadata: {
          'amount': amount,
          'currency': 'DIASPORA',
          'assetType': 'token',
        },
        participants: participants,
      );
    } catch (e) {
      debugPrint('TOKEN_TRANSFER: Error transferring token: $e');
      if (mounted) {
        final cleanMsg = e
            .toString()
            .split('\n')
            .first
            .replaceFirst(RegExp(r'^\[firebase_functions/[^\]]+\]\s*'), '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Transfer failed: $cleanMsg')),
        );
      }
    } finally {
      if (mounted) {
        ref
            .read(pendingMessagesProvider.notifier)
            .removeMessage(initialKey, tempId);
        if (chatId != initialKey) {
          ref
              .read(pendingMessagesProvider.notifier)
              .removeMessage(chatId, tempId);
        }
      }
    }
  }

  // Fiat Remittance Send Logic — 0ms Optimistic Bubble
  Future<void> _sendFiat(
    double amount,
    String currency,
    double convertedAmount,
    String receiverCurrency,
    double exchangeRate,
    String? caption,
  ) async {
    final chatRepo = ref.read(chatRepositoryProvider);
    final currentUserId = chatRepo.currentUserId;
    if (currentUserId == null) return;

    String? toUserId = widget.pendingUserId ?? _activePartnerUserId;
    if (toUserId == null && _activeChatId != null) {
      final cachedChat = chatRepo.getCachedChat(_activeChatId!);
      toUserId = cachedChat?.getOtherParticipantId(currentUserId);
    }

    final identity = ref.read(chatIdentityProvider);
    final formattedAmount = amount.toStringAsFixed(
      amount.truncateToDouble() == amount ? 0 : 2,
    );
    final formattedConverted = convertedAmount.toStringAsFixed(
      convertedAmount.truncateToDouble() == convertedAmount ? 0 : 2,
    );
    final defaultCaption = currency != receiverCurrency && convertedAmount > 0
        ? 'Sent $formattedAmount $currency (≈ $formattedConverted $receiverCurrency)'
        : 'Sent $formattedAmount $currency';
    final displayContent = caption?.isNotEmpty == true
        ? caption!
        : defaultCaption;

    final initialKey = _pendingDmCacheKey;
    final now = DateTime.now().millisecondsSinceEpoch;
    final tempId = 'temp_fiat_$now';
    final txMetadata = <String, dynamic>{
      'amount': amount,
      'currency': currency,
      'convertedAmount': convertedAmount,
      'convertedCurrency': receiverCurrency,
      'exchangeRate': exchangeRate,
      'deliveryMethod': 'Mobile Money / Bank Settlement',
      'fee': 0.0,
      'status': 'Completed',
      'assetType': 'fiat',
      'recipientId': ?toUserId,
      'timestamp': now,
    };

    // [PERF] Insert optimistic fiat transfer bubble on frame 0
    final optimisticMessage = Message(
      id: tempId,
      chatId: initialKey,
      senderId: identity?['id'] ?? currentUserId,
      senderName: identity?['businessName'] ?? identity?['name'] ?? 'Me',
      senderImage: identity?['profileImage'],
      content: displayContent,
      type: 'money-transfer',
      timestamp: now,
      status: 'sending',
      metadata: txMetadata,
    );

    ref
        .read(pendingMessagesProvider.notifier)
        .addMessage(initialKey, optimisticMessage);
    _scrollToBottom(false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Remittance of $formattedAmount $currency sent successfully!',
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    final chatId = await _ensureChatCreated();
    if (chatId == null) {
      ref
          .read(pendingMessagesProvider.notifier)
          .removeMessage(initialKey, tempId);
      return;
    }

    if (toUserId == null) {
      final chat =
          chatRepo.getCachedChat(chatId) ?? await chatRepo.getChat(chatId);
      toUserId = chat?.getOtherParticipantId(currentUserId);
      if (toUserId != null) {
        txMetadata['recipientId'] = toUserId;
      }
    }

    if (toUserId == null || toUserId.isEmpty) {
      ref
          .read(pendingMessagesProvider.notifier)
          .removeMessage(initialKey, tempId);
      return;
    }

    final participants = _getParticipantsSync(chatId);

    try {
      await chatRepo.sendTextMessage(
        chatId,
        displayContent,
        type: 'money-transfer',
        senderIdOverride: identity?['id'],
        senderNameOverride: identity?['businessName'] ?? identity?['name'],
        senderImageOverride: identity?['profileImage'],
        metadata: txMetadata,
        participants: participants,
      );
    } catch (e) {
      debugPrint('FIAT_TRANSFER: Error sending fiat remittance: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Remittance failed: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        ref
            .read(pendingMessagesProvider.notifier)
            .removeMessage(initialKey, tempId);
        if (chatId != initialKey) {
          ref
              .read(pendingMessagesProvider.notifier)
              .removeMessage(chatId, tempId);
        }
      }
    }
  }

  void _showClearConfirmation(
    BuildContext context,
    ChatRepository repo,
    String chatId,
    String name,
  ) {
    final outerContext = context;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: ChatConfirmationSheet(
          title: 'Clear Chat?',
          message:
              'Are you sure you want to clear your chat history with $name? This cannot be undone.',
          actionTitle: 'Clear Chat',
          subtitle: 'Delete all messages for you',
          icon: LucideIcons.eraser,
          onAction: () {
            Navigator.pop(sheetContext); // Close sheet in 0ms
            if (outerContext.mounted) {
              ScaffoldMessenger.of(
                outerContext,
              ).showSnackBar(const SnackBar(content: Text('Chat cleared')));
            }
            unawaited(
              repo.clearChat(chatId).catchError((Object e) {
                if (outerContext.mounted) {
                  ScaffoldMessenger.of(outerContext).showSnackBar(
                    SnackBar(content: Text('Error clearing chat: $e')),
                  );
                }
              }),
            );
          },
        ),
      ),
    );
  }

  void _showDeleteConfirmation(
    BuildContext context,
    ChatRepository repo,
    String chatId,
    String name, {
    bool isLeave = false,
    String? titleOverride,
  }) {
    final title = titleOverride ?? (isLeave ? 'Leave Group?' : 'Delete Chat?');
    final message = isLeave
        ? 'Are you sure you want to leave $name?'
        : (titleOverride == 'Unfollow Organization?')
        ? 'Are you sure you want to unfollow $name?'
        : 'Are you sure you want to delete your chat with $name? This action cannot be undone.';
    final actionTitle = isLeave
        ? (titleOverride?.contains('Unfollow') == true ? 'Unfollow' : 'Leave')
        : 'Delete';
    final subtitle = isLeave
        ? 'You will no longer be a participant'
        : 'Remove conversation and all history';

    final outerContext = context;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: ChatConfirmationSheet(
          title: title,
          message: message,
          actionTitle: actionTitle,
          subtitle: subtitle,
          icon: isLeave ? LucideIcons.logOut : LucideIcons.trash2,
          onAction: () {
            Navigator.pop(sheetContext); // Close confirmation sheet in 0ms
            if (outerContext.mounted) {
              Navigator.of(outerContext).pop(); // Pop chat screen in 0ms
            }
            unawaited(
              (isLeave ? repo.leaveChat(chatId) : repo.deleteChat(chatId))
                  .catchError((Object e) {
                    debugPrint('Error deleting/leaving chat: $e');
                  }),
            );
          },
        ),
      ),
    );
  }

  void _handleMessageAction(
    BuildContext context,
    Message message,
    WidgetRef ref,
  ) {
    if (message.isDeletedForEveryone) return;

    final currentUserId = ref.read(chatRepositoryProvider).currentUserId;
    final isOwn = message.senderId == currentUserId;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: ChatMessageActionSheet(
          message: message,
          isOwn: isOwn,
          currentUserId: currentUserId,
          onReply: (m) => _setReplyTo(m),
          onReaction: (m, emoji) => _handleReaction(m, emoji),
          onReportMessage: (m) => _showReportDialog(context, ref, m),
          onBlockUser: (uid, name) => _handleBlockUser(context, ref, uid, name),
          onReportUser: (uid, name) =>
              _handleReportUser(context, ref, uid, name),
          onVerifySolution: (m) => _handleVerifySolution(m),
          onDelete: (m) => _handleDeleteMessage(m),
        ),
      ),
    );
  }

  void _handleVerifySolution(Message message) {
    final chatRepo = ref.read(chatRepositoryProvider);
    final currentUserId = chatRepo.currentUserId;
    if (currentUserId == null) return;

    // [PERF] Show reward feedback immediately in 0ms and run verification in background
    if (mounted) {
      showExplorationRewardToast(
        context,
        message: 'Verified solution! +1,000 DSP for you.',
        points: 1000,
      );
    }

    unawaited(
      ref
          .read(trustServiceProvider)
          .markAsVerifiedSolution(
            senderId: message.senderId,
            messageId: message.id,
            chatId: _activeChatId ?? '',
            reporterId: currentUserId,
          )
          .then((success) {
            if (!success && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Already marked as solution or error occurred.',
                  ),
                ),
              );
            }
          }),
    );
  }

  // [NEW] Handle Reaction
  void _handleReaction(Message message, String emoji) {
    final currentUserId = ref.read(chatRepositoryProvider).currentUserId;
    if (currentUserId == null) return;

    // Check if user already reacted with this emoji
    bool isRemoved = false;
    final reactions = message.reactions ?? [];

    for (final reaction in reactions) {
      if (reaction.emoji == emoji && reaction.userIds.contains(currentUserId)) {
        isRemoved = true;
        break;
      }
    }

    if (isRemoved) {
      ref
          .read(chatRepositoryProvider)
          .removeReaction(message.chatId, message.id, emoji);
    } else {
      ref
          .read(chatRepositoryProvider)
          .addReaction(message.chatId, message.id, emoji, message.senderId);
    }
  }

  // [NEW] Handle Delete
  void _handleDeleteMessage(Message message) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: ChatConfirmationSheet(
          title: 'Delete Message',
          message:
              'Are you sure you want to delete this message? This action cannot be undone.',
          actionTitle: 'Delete Message',
          subtitle: 'This will permanently remove the message from this chat',
          onAction: () {
            Navigator.pop(context);
            unawaited(
              ref
                  .read(chatRepositoryProvider)
                  .deleteMessage(message.chatId, message.id),
            );
          },
        ),
      ),
    );
  }

  void _showReportDialog(BuildContext context, WidgetRef ref, Message message) {
    final outerContext = context;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: ChatReportSheet(
          title: 'Report Message',
          entityName: 'this message',
          reasons: ChatReportSheet.messageReasons,
          onReport: (reason) {
            Navigator.pop(sheetContext); // Close sheet in 0ms

            final currentUserId = ref
                .read(authRepositoryProvider)
                .currentUser
                ?.uid;
            if (currentUserId == null) return;

            // [PERF] Show confirmation immediately in 0ms and submit in background
            if (outerContext.mounted) {
              showExplorationRewardToast(
                outerContext,
                message: 'Report submitted. Thank you!',
                points: 100,
              );
            }

            unawaited(() async {
              try {
                final result = await ref
                    .read(reportRepositoryProvider)
                    .reportMessage(
                      reporterId: currentUserId,
                      chatId: widget.chatId ?? _activeChatId ?? '',
                      messageId: message.id,
                      senderId: message.senderId,
                      reason: reason,
                    );

                if (result == ReportResult.success) {
                  try {
                    await ref
                        .read(pointsServiceProvider)
                        .awardPoints(
                          userId: currentUserId,
                          amount: 100,
                          reason: 'report_message',
                        );
                  } catch (e) {
                    debugPrint('Error awarding report DSP: $e');
                  }
                } else if (result == ReportResult.duplicate &&
                    outerContext.mounted) {
                  ScaffoldMessenger.of(outerContext).showSnackBar(
                    const SnackBar(
                      content: Text('You have already reported this message.'),
                    ),
                  );
                } else if (result == ReportResult.failed &&
                    outerContext.mounted) {
                  ScaffoldMessenger.of(outerContext).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Failed to submit report. Please try again.',
                      ),
                      backgroundColor: AppTheme.error,
                    ),
                  );
                }
              } catch (e) {
                debugPrint('Error reporting message: $e');
              }
            }());
          },
        ),
      ),
    );
  }

  // [NEW] Handle Verify User from Chat — 0ms Cached Fast-Path + Parallel Checks
  Future<void> _handleVerifyChatUser(
    BuildContext context,
    WidgetRef ref,
    Chat chat,
  ) async {
    final currentUserId = ref.read(authRepositoryProvider).currentUser?.uid;
    if (currentUserId == null) return;

    final otherUserId = chat.participants.firstWhere(
      (id) => id != currentUserId,
      orElse: () => '',
    );

    if (otherUserId.isEmpty) return;

    final profileRepo = ref.read(profileRepositoryProvider);
    final relRepo = ref.read(relationshipRepositoryProvider);

    // 1. Check cached relationship synchronously first
    final cachedRel = relRepo.getCachedRelationship(currentUserId, otherUserId);
    if (cachedRel != null &&
        cachedRel.status == 'active' &&
        TrustSliderWidget.isFamilyRelationshipType(cachedRel.type)) {
      if (context.mounted) {
        VerificationAlertModal.show(
          context,
          type: VerificationAlertType.conflict,
          title: 'Conflict of Interest',
          message:
              'You cannot verify a family member. Verification must be performed by independent community members.',
        );
      }
      return;
    }

    // 2. Run profile, relationship, and eligibility checks in parallel
    try {
      final cachedProfile = profileRepo.getCachedProfile(otherUserId);
      final results = await Future.wait<Object?>([
        cachedProfile != null
            ? Future.value(cachedProfile)
            : profileRepo.getUserProfile(otherUserId),
        cachedRel != null
            ? Future.value(cachedRel)
            : relRepo.getRelationship(
                userId: currentUserId,
                relatedUserId: otherUserId,
              ),
        ref
            .read(trustServiceProvider)
            .checkVerificationEligibility(currentUserId, otherUserId),
      ]);

      final profile = results[0] as dynamic;
      if (profile == null) return;

      final rel = results[1] as Relationship?;
      if (rel != null &&
          rel.status == 'active' &&
          TrustSliderWidget.isFamilyRelationshipType(rel.type)) {
        if (context.mounted) {
          VerificationAlertModal.show(
            context,
            type: VerificationAlertType.conflict,
            title: 'Conflict of Interest',
            message:
                'You cannot verify a family member. Verification must be performed by independent community members.',
          );
        }
        return;
      }

      final eligibilityError = results[2] as String?;
      if (eligibilityError != null) {
        if (context.mounted) {
          VerificationAlertType type = VerificationAlertType.error;
          if (eligibilityError.contains('already verified')) {
            type = VerificationAlertType.alreadyVerified;
          } else if (eligibilityError.contains('limit reached')) {
            type = VerificationAlertType.limit;
          } else if (eligibilityError.contains('complete your profile') ||
              eligibilityError.contains('Verified User') ||
              eligibilityError.contains('acquired at least')) {
            type = VerificationAlertType.requirements;
          }

          VerificationAlertModal.show(
            context,
            type: type,
            title: type == VerificationAlertType.requirements
                ? 'Requirements Not Met'
                : 'Action Restricted',
            message: eligibilityError,
          );
        }
        return;
      }

      if (context.mounted) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (c) => BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: ProfileVerificationModal(
              targetUser: profile,
              currentUserId: currentUserId,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error in verify flow: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _showRelationshipPicker(
    BuildContext context,
    WidgetRef ref,
    String? otherUserId,
    String? displayName,
  ) {
    if (otherUserId == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: RelationshipSelectionModal(
          otherUserId: otherUserId,
          otherUserName: displayName ?? 'User',
        ),
      ),
    );
  }

  void _handleBlockUser(
    BuildContext context,
    WidgetRef ref,
    String userId,
    String userName,
  ) {
    final outerContext = context;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: ChatConfirmationSheet(
          title: 'Block User',
          message:
              'Are you sure you want to block $userName? They will not be able to message you.',
          actionTitle: 'Block User',
          subtitle: 'You can unblock them later from your profile settings',
          onAction: () {
            Navigator.pop(sheetContext); // Close sheet in 0ms

            final currentUserId = ref
                .read(authRepositoryProvider)
                .currentUser
                ?.uid;
            if (currentUserId == null) return;

            if (outerContext.mounted) {
              ScaffoldMessenger.of(
                outerContext,
              ).showSnackBar(const SnackBar(content: Text('User blocked')));
            }

            unawaited(
              ref
                  .read(relationshipRepositoryProvider)
                  .blockUser(userId: currentUserId, relatedUserId: userId)
                  .catchError((Object e) {
                    if (outerContext.mounted) {
                      ScaffoldMessenger.of(outerContext).showSnackBar(
                        SnackBar(content: Text('Error blocking user: $e')),
                      );
                    }
                  }),
            );
          },
        ),
      ),
    );
  }

  void _handleReportUser(
    BuildContext context,
    WidgetRef ref,
    String userId,
    String userName,
  ) {
    final outerContext = context;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: ChatReportSheet(
          title: 'Report $userName',
          entityName: userName,
          reasons: ChatReportSheet.userReasons,
          onReport: (reason) {
            Navigator.pop(sheetContext); // Close sheet in 0ms

            final currentUserId = ref
                .read(authRepositoryProvider)
                .currentUser
                ?.uid;
            if (currentUserId == null) return;

            // [PERF] Show confirmation immediately in 0ms and run report in background
            if (outerContext.mounted) {
              showExplorationRewardToast(
                outerContext,
                message: 'Report submitted. Thank you!',
                points: 100,
              );
            }

            unawaited(() async {
              try {
                final result = await ref
                    .read(reportRepositoryProvider)
                    .reportUser(
                      reporterId: currentUserId,
                      reportedUserId: userId,
                      reason: reason,
                    );

                if (result == ReportResult.success) {
                  try {
                    await ref
                        .read(pointsServiceProvider)
                        .awardPoints(
                          userId: currentUserId,
                          amount: 100,
                          reason: 'report_sender',
                        );
                  } catch (e) {
                    debugPrint('Error awarding report DSP: $e');
                  }
                } else if (result == ReportResult.duplicate &&
                    outerContext.mounted) {
                  ScaffoldMessenger.of(outerContext).showSnackBar(
                    const SnackBar(
                      content: Text('You have already reported this user.'),
                    ),
                  );
                } else if (result == ReportResult.failed &&
                    outerContext.mounted) {
                  ScaffoldMessenger.of(outerContext).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Failed to submit report. Please try again.',
                      ),
                      backgroundColor: AppTheme.error,
                    ),
                  );
                }
              } catch (e) {
                debugPrint('Error reporting user: $e');
              }
            }());
          },
        ),
      ),
    );
  }
}

/// Gates the chamber chat input on the user's `accessLevel` field in their
/// userChats subcollection entry:
///   - `member`  → render [fullInput] (full posting affordance)
///   - anything else (typically `follower`) → render a read-only banner
///     with a Join Chamber CTA.
class _ChamberFollowerGate extends ConsumerStatefulWidget {
  final String chatId;
  final String orgId;
  final String uid;
  final Widget fullInput;

  const _ChamberFollowerGate({
    required this.chatId,
    required this.orgId,
    required this.uid,
    required this.fullInput,
  });

  @override
  ConsumerState<_ChamberFollowerGate> createState() =>
      _ChamberFollowerGateState();
}

class _ChamberFollowerGateState extends ConsumerState<_ChamberFollowerGate> {
  bool _optimisticJoined = false;

  @override
  Widget build(BuildContext context) {
    if (_optimisticJoined) return widget.fullInput;

    final cachedChat = ref
        .read(chatRepositoryProvider)
        .getCachedChat(widget.chatId);
    final isCachedAdminOrMember =
        (cachedChat?.admins?.contains(widget.uid) ?? false) ||
        (cachedChat?.metadata?['accessLevel'] == 'member');
    if (isCachedAdminOrMember) return widget.fullInput;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .collection('userChats')
          .doc(widget.chatId)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting &&
            (cachedChat?.participants.contains(widget.uid) ?? false)) {
          return widget.fullInput;
        }
        final data = snap.data?.data() ?? const <String, dynamic>{};
        final accessLevel = data['accessLevel'] as String?;
        if (accessLevel == 'member' || _optimisticJoined) {
          return widget.fullInput;
        }

        final theme = Theme.of(context);
        return SafeArea(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: theme.colorScheme.surface),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      LucideIcons.eye,
                      size: 18,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Read-only access. Join the chamber to post.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(LucideIcons.userPlus, size: 16),
                    label: const Text('Join Chamber'),
                    onPressed: () {
                      // [PERF] Unlock input in 0ms on tap
                      final messenger = ScaffoldMessenger.of(context);
                      setState(() => _optimisticJoined = true);
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Joined the chamber.')),
                      );
                      unawaited(
                        ref
                            .read(organizationRepositoryProvider)
                            .joinChamber(
                              orgId: widget.orgId,
                              userId: widget.uid,
                            )
                            .then((_) {
                              if (mounted) {
                                ref.invalidate(chatProvider(widget.chatId));
                                ref.invalidate(
                                  messagesStreamProvider(widget.chatId),
                                );
                              }
                            })
                            .catchError((Object e) {
                              if (mounted) {
                                setState(() => _optimisticJoined = false);
                                messenger.showSnackBar(
                                  SnackBar(content: Text('Couldn\'t join: $e')),
                                );
                              }
                            }),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
