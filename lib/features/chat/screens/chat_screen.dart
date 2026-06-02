import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
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
import 'package:diaspora_nearby/features/chat/widgets/bilateral_flag_avatar.dart';
import 'package:diaspora_nearby/features/community/repository/community_repository.dart'; // [NEW]
import 'package:diaspora_nearby/theme/app_theme.dart'; // [FIXED]

import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/trust/services/trust_service.dart';
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
import 'package:diaspora_nearby/features/profile/models/relationship.dart';
import 'package:diaspora_nearby/features/profile/models/relationship_request.dart'; // [NEW]
import 'package:diaspora_nearby/features/chat/providers/pending_message_provider.dart';
// [NEW]
// [NEW]
import 'package:diaspora_nearby/features/chat/widgets/chat_more_menu_sheet.dart';
import 'package:diaspora_nearby/features/trust/widgets/profile_verification_modal.dart'; // [NEW]
import 'package:diaspora_nearby/features/trust/widgets/trust_vouch_modal.dart'; // [NEW] Trust Vouch Modal
import 'package:diaspora_nearby/features/trust/widgets/verification_alert_modal.dart'; // [NEW]
import 'package:diaspora_nearby/features/governance/repository/governance_repository.dart'; // [NEW]

import 'package:diaspora_nearby/features/governance/screens/leader_selection_screen.dart'; // [NEW]
import 'package:diaspora_nearby/features/governance/models/governance_unit.dart'; // [NEW]
// [NEW]
import 'package:diaspora_nearby/features/more/widgets/business_registration_modal.dart'; // [NEW]
import 'package:diaspora_nearby/features/community/widgets/share_community_dialog.dart'; // [NEW]
import 'package:diaspora_nearby/features/dsp/screens/ddi_loans_screen.dart'; // [NEW]

import 'package:diaspora_nearby/features/chat/widgets/chat_report_sheet.dart';
import 'package:diaspora_nearby/features/chat/widgets/chat_confirmation_sheet.dart';
import 'package:diaspora_nearby/features/chat/widgets/chat_date_separator.dart';
import 'package:diaspora_nearby/features/chat/widgets/chat_empty_state.dart';
import 'package:diaspora_nearby/features/chat/widgets/chat_restriction_view.dart';
import 'package:diaspora_nearby/features/chat/providers/chat_providers.dart'; // [NEW] Shared Providers
import 'package:diaspora_nearby/features/shared/utils/country_utils.dart'; // [NEW]
import 'package:diaspora_nearby/features/shared/utils/whatsapp_utils.dart';
import 'package:diaspora_nearby/features/chat/widgets/chat_scroll_to_bottom_fab.dart';
import 'package:diaspora_nearby/features/chat/widgets/chat_typing_indicator.dart';

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

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController =
      TextEditingController(); // [NEW]
  bool _isNearBottom = true;
  // _scrollPositionRestored removed

  /// The actual chatId (either from props or created after first message)
  String? _activeChatId;

  /// Message being replied to (null if not replying)
  Message? _replyingTo;

  /// Tracks message IDs that have become visible and need to be marked as read
  final Set<String> _visibleUnreadMessageIds = {};

  /// Debounce timer for batching read receipt updates
  Timer? _readReceiptDebounceTimer;

  /// Whether this is a pending DM that hasn't been created yet
  bool get _isPendingDM =>
      widget.chatId == null && widget.pendingUserId != null;

  /// Global keys for each message to support "Jump to Message"
  final Map<String, GlobalKey> _messageKeys = {};

  /// Current message ID being highlighted (from "Jump to Message")
  String? _highlightedMessageId;

  /// Guard to prevent duplicate "More" menu opens during async loading
  bool _isShowingMoreMenu = false;

  @override
  void initState() {
    super.initState();
    _activeChatId = widget.chatId;
    _scrollController.addListener(_onScroll);

    // LOGGING TO DEBUG "NOTHING HAPPENS"
    final currentUserId = ref.read(chatRepositoryProvider).currentUserId;
    debugPrint('ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã‚Â© ChatScreen INIT:');
    debugPrint('   - chatId: ${widget.chatId}');
    debugPrint('   - pendingUserId: ${widget.pendingUserId}');
    debugPrint('   - pendingUserName: ${widget.pendingUserName}');
    debugPrint('   - currentUserId: $currentUserId');

    // Mark as read when entering (only for joined participants)
    if (_activeChatId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final chatRepo = ref.read(chatRepositoryProvider);
        final currentUserId = chatRepo.currentUserId;
        if (currentUserId == null) return;

        // Fetch chat once to check participation and type
        final chat = await chatRepo.getChat(_activeChatId!);
        if (chat != null) {
          final isParticipant = chat.participants.contains(currentUserId);

          if (isParticipant) {
            // [FIX] Only mark as read if the user is a member.
            // This avoids auto-joining if the user is just previewing from discovery.
            chatRepo.markChatAsRead(_activeChatId!);
            chatRepo.clearChatMentions(_activeChatId!);

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

  // Scroll persistence methods removed

  @override
  void dispose() {
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
          duration: const Duration(milliseconds: 300),
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
      debugPrint(
        'ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â Target message $messageId not found in rendered list',
      );
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
    debugPrint('ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã‚Â© _sendMessage called with content: "$text"');
    if (text.trim().isEmpty) return;

    final chatRepo = ref.read(chatRepositoryProvider);
    final replyToId = _replyingTo?.id;

    // Clear reply immediately
    _clearReply();

    // If this is a pending DM, create the chat first
    if (_isPendingDM && _activeChatId == null) {
      debugPrint('ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã‚Â Creating DM chat on first message...');
      final chat = await chatRepo.createDirectChatWithMessage(
        widget.pendingUserId!,
        text,
      );

      // If mentions exist, we might need to update the message after creation or update createDirectChatWithMessage to support mentions
      // mentions are rare in initial DM? But possible.
      // createDirectChatWithMessage sends the message internally using sendTextMessage.
      // I should update createDirectChatWithMessage signature too if I want full support.
      // For now, assume pending DM doesn't strictly need mentions support immediately or I'll implement it later.
      // Actually, createDirectChatWithMessage in repo calls sendTextMessage(chat.id, initialMessage).
      // I can't pass mentions there easily without refactor.
      // Given mentions are mostly for group chats, this is acceptable for now.

      if (chat != null) {
        setState(() {
          _activeChatId = chat.id;
        });
        debugPrint('ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Chat created: ${chat.id}');
      } else {
        debugPrint(
          'ÃƒÆ’Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒâ€šÃ…â€™ Failed to create chat with user ${widget.pendingUserId}',
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
      // Existing chat - send the message with optional reply

      // [NEW] Check for Identity Override
      final identity = ref.read(chatIdentityProvider);
      String? senderIdOverride;
      String? senderNameOverride;
      String? senderImageOverride;

      if (identity != null) {
        senderIdOverride = identity['id'];
        senderNameOverride = identity['businessName'] ?? identity['name'];
        senderImageOverride = identity['profileImage'];
      }

      // [FIX] Add optimistic message FIRST, before any async calls
      final currentUserId = ref.read(chatRepositoryProvider).currentUserId;
      final now = DateTime.now().millisecondsSinceEpoch;
      final tempId = 'temp_${now}_$currentUserId';

      if (currentUserId != null) {
        final optimisticMessage = Message(
          id: tempId,
          chatId: _activeChatId!,
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
            .addMessage(_activeChatId!, optimisticMessage);

        final participants = chatRepo
            .getCachedChat(_activeChatId!)
            ?.participants;

        try {
          await chatRepo.sendTextMessage(
            _activeChatId!,
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
            replyToSenderId: _replyingTo?.senderId,
          );
        } catch (e) {
          debugPrint('ÃƒÂ¢Ã‚ÂÃ…â€™ Error sending message: $e');
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
              .removeMessage(_activeChatId!, tempId);
        }
      } else {
        // Fallback if no user id (shouldn't happen)
        await chatRepo.sendTextMessage(
          _activeChatId!,
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

    // Double scroll to ensure it catches layout updates and keyboard movement
    Future.delayed(const Duration(milliseconds: 300), () => _scrollToBottom());
    Future.delayed(const Duration(milliseconds: 600), () => _scrollToBottom());
  }

  /// Helper to get participants for optimistic updates
  Future<List<String>?> _getParticipants() async {
    if (_activeChatId == null) return null;
    try {
      final chatRepo = ref.read(chatRepositoryProvider);
      final chat = await chatRepo.getChat(_activeChatId!);
      return chat?.participants;
    } catch (e) {
      debugPrint('Error fetching participants: $e');
      return null;
    }
  }

  /// Helper to ensure chat exists (creates it if pending)
  Future<String?> _ensureChatCreated() async {
    if (_activeChatId != null) return _activeChatId;
    if (!_isPendingDM) return null;

    debugPrint('ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã‚Â Creating DM chat for media/file...');
    final chatRepo = ref.read(chatRepositoryProvider);

    // Show loading?
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Starting conversation...')));
    }

    final chat = await chatRepo.createDirectChat(widget.pendingUserId!);

    if (chat != null) {
      setState(() {
        _activeChatId = chat.id;
      });
      debugPrint('ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Chat created: ${chat.id}');
      return chat.id;
    } else {
      debugPrint(
        'ÃƒÆ’Ã‚Â¢Ãƒâ€šÃ‚ÂÃƒâ€šÃ…â€™ Failed to create chat with user ${widget.pendingUserId}',
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
    final chatId = await _ensureChatCreated();
    if (chatId == null) return;

    final chatRepo = ref.read(chatRepositoryProvider);
    final replyToId = _replyingTo?.id;
    final identity = ref.read(chatIdentityProvider);

    // Clear reply immediately
    _clearReply();

    // Fetch participants for instant update
    final participants = await _getParticipants();

    for (final file in files) {
      // [NEW] Optimistic Message
      final currentUserId = ref.read(chatRepositoryProvider).currentUserId;
      final now = DateTime.now().millisecondsSinceEpoch;
      final tempId = 'temp_media_${now}_${files.indexOf(file)}';

      if (currentUserId != null) {
        final optimisticMessage = Message(
          id: tempId,
          chatId: chatId,
          senderId: identity?['id'] ?? currentUserId,
          senderName: identity?['name'] ?? 'Me',
          senderImage: identity?['profileImage'],
          content: caption?.trim() ?? '',
          type: type, // 'image' or 'video'
          documentUrl: file.path, // Helper to show local file
          timestamp: now,
          status: 'sending',
          replyTo: replyToId,
          // Add local file indicator if needed by MessageBubble
          // usually MessageBubble checks if startsWith http, else treats as file
        );

        ref
            .read(pendingMessagesProvider.notifier)
            .addMessage(chatId, optimisticMessage);
      }

      try {
        if (type == 'video') {
          await chatRepo.sendVideoMessage(
            chatId,
            file,
            caption: caption, // No caption support in multi-upload yet
            replyToMessageId: replyToId,
            senderIdOverride: identity?['id'],
            senderNameOverride: identity?['name'],
            senderImageOverride: identity?['profileImage'],

            participants: participants,
            replyToSenderId: _replyingTo?.senderId,
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
            replyToSenderId: _replyingTo?.senderId,
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
        if (currentUserId != null) {
          // Delay removal to allow stream to catch up and prevent flicker
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) {
              ref
                  .read(pendingMessagesProvider.notifier)
                  .removeMessage(chatId, tempId);
            }
          });
        }
      }
    }

    // Scroll to bottom after sending
    Future.delayed(const Duration(milliseconds: 300), () => _scrollToBottom());
    Future.delayed(const Duration(milliseconds: 600), () => _scrollToBottom());
  }

  Future<MessageLocation?> _pickLocation() async {
    // Permission check first
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

    if (!mounted) return null;
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Getting accurate location...'),
              ],
            ),
          ),
        ),
      );

      // Check service status
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context); // Close loader
        }
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

      // Get current position with timeout
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).timeout(const Duration(seconds: 10));

      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context); // Close loader
      }

      // Reverse geocode to get address
      String? address;
      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          address = [
            place.street,
            place.locality,
            place.administrativeArea,
            place.country,
          ].where((s) => s != null && s.isNotEmpty).join(', ');
        }
      } catch (e) {
        debugPrint('Reverse geocoding failed: $e');
      }

      return MessageLocation(
        lat: position.latitude,
        lng: position.longitude,
        address: address ?? '',
      );
    } on TimeoutException catch (_) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
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
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
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
    final chatId = await _ensureChatCreated();
    if (chatId == null) return;

    final chatRepo = ref.read(chatRepositoryProvider);
    final replyToId = _replyingTo?.id;
    final identity = ref.read(chatIdentityProvider);

    // Clear reply immediately
    _clearReply();

    // Fetch participants
    final participants = await _getParticipants();

    // [NEW] Optimistic Location
    final currentUserId = ref.read(chatRepositoryProvider).currentUserId;
    final now = DateTime.now().millisecondsSinceEpoch;
    final tempId = 'temp_loc_$now';

    if (currentUserId != null) {
      final optimisticMessage = Message(
        id: tempId,
        chatId: chatId,
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
          .addMessage(chatId, optimisticMessage);
    }

    try {
      await chatRepo.sendLocationMessage(
        chatId,
        latitude: location.lat,
        longitude: location.lng,
        address: location.address,
        caption: caption,
        replyToMessageId: replyToId,
        senderIdOverride: identity?['id'],
        senderNameOverride: identity?['name'],
        senderImageOverride: identity?['profileImage'],
        participants: participants,
        replyToSenderId: _replyingTo?.senderId,
      );
    } catch (e) {
      debugPrint('Error sending location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send location: ${e.toString()}')),
        );
      }
    } finally {
      if (currentUserId != null) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            ref
                .read(pendingMessagesProvider.notifier)
                .removeMessage(chatId, tempId);
          }
        });
      }
    }

    // Scroll to bottom after sending
    Future.delayed(const Duration(milliseconds: 100), () {
      _scrollToBottom();
    });
  }

  Future<void> _sendAudioFile(XFile file, String? caption) async {
    final chatId = await _ensureChatCreated();
    if (chatId == null) return;

    final chatRepo = ref.read(chatRepositoryProvider);
    final replyToId = _replyingTo?.id;
    final identity = ref.read(chatIdentityProvider);

    // Clear reply immediately
    _clearReply();

    // Fetch participants
    final participants = await _getParticipants();

    // [NEW] Optimistic Audio File
    final currentUserId = ref.read(chatRepositoryProvider).currentUserId;
    final now = DateTime.now().millisecondsSinceEpoch;
    final tempId = 'temp_audiofile_$now';

    if (currentUserId != null) {
      final optimisticMessage = Message(
        id: tempId,
        chatId: chatId,
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
          .addMessage(chatId, optimisticMessage);
    }

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
        replyToSenderId: _replyingTo?.senderId,
      );
    } catch (e) {
      debugPrint('Error sending audio file: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send audio file: ${e.toString()}')),
        );
      }
    } finally {
      if (currentUserId != null) {
        // Delay removal to allow stream to catch up
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            ref
                .read(pendingMessagesProvider.notifier)
                .removeMessage(chatId, tempId);
          }
        });
      }
    }

    // Scroll to bottom after sending
    Future.delayed(const Duration(milliseconds: 300), () => _scrollToBottom());
    Future.delayed(const Duration(milliseconds: 600), () => _scrollToBottom());
  }

  Future<void> _sendAudio(XFile file, int duration, {String? caption}) async {
    final chatId = await _ensureChatCreated();
    if (chatId == null) return;

    final chatRepo = ref.read(chatRepositoryProvider);
    final replyToId = _replyingTo?.id;
    final identity = ref.read(chatIdentityProvider);

    // Clear reply immediately
    _clearReply();

    // Fetch participants
    final participants = await _getParticipants();

    // [NEW] Optimistic Audio (Voice)
    final currentUserId = ref.read(chatRepositoryProvider).currentUserId;
    final now = DateTime.now().millisecondsSinceEpoch;
    final tempId = 'temp_voice_$now';

    if (currentUserId != null) {
      final optimisticMessage = Message(
        id: tempId,
        chatId: chatId,
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
          .addMessage(chatId, optimisticMessage);
    }

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
        replyToSenderId: _replyingTo?.senderId,
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
      if (currentUserId != null) {
        // Delay removal to allow stream to catch up
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            ref
                .read(pendingMessagesProvider.notifier)
                .removeMessage(chatId, tempId);
          }
        });
      }
    }

    // Scroll to bottom after sending
    Future.delayed(const Duration(milliseconds: 300), () => _scrollToBottom());
    Future.delayed(const Duration(milliseconds: 600), () => _scrollToBottom());
  }

  Future<void> _sendDocument(XFile file, String? caption) async {
    final chatId = await _ensureChatCreated();
    if (chatId == null) return;

    final chatRepo = ref.read(chatRepositoryProvider);
    final replyToId = _replyingTo?.id;
    final identity = ref.read(chatIdentityProvider);

    // Clear reply immediately
    _clearReply();

    // Fetch participants
    final participants = await _getParticipants();

    // [NEW] Optimistic Document
    final currentUserId = ref.read(chatRepositoryProvider).currentUserId;
    final now = DateTime.now().millisecondsSinceEpoch;
    final tempId = 'temp_doc_$now';

    if (currentUserId != null) {
      final optimisticMessage = Message(
        id: tempId,
        chatId: chatId,
        senderId: identity?['id'] ?? currentUserId,
        senderName: identity?['name'] ?? 'Me',
        senderImage: identity?['profileImage'],
        content: caption?.trim() ?? '',
        type: 'document',
        documentUrl: file.path,
        documentName: file.path.split('/').last, // rough estimate
        timestamp: now,
        status: 'sending',
        replyTo: replyToId,
      );

      ref
          .read(pendingMessagesProvider.notifier)
          .addMessage(chatId, optimisticMessage);
    }

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
        replyToSenderId: _replyingTo?.senderId,
      );
    } catch (e) {
      debugPrint('Error sending document: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send document: ${e.toString()}')),
        );
      }
    } finally {
      if (currentUserId != null) {
        // Delay removal to allow stream to catch up
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            ref
                .read(pendingMessagesProvider.notifier)
                .removeMessage(chatId, tempId);
          }
        });
      }
    }

    // Scroll to bottom after sending
    Future.delayed(const Duration(milliseconds: 300), () => _scrollToBottom());
    Future.delayed(const Duration(milliseconds: 600), () => _scrollToBottom());
  }

  /// Retry sending a failed message
  Future<void> _retryMessage(Message failedMessage) async {
    if (_activeChatId == null) return;

    debugPrint(
      'ÃƒÆ’Ã‚Â°Ãƒâ€šÃ…Â¸Ãƒâ€šÃ¢â‚¬ÂÃƒâ€šÃ¢â‚¬Å¾ Retrying failed message: ${failedMessage.id}',
    );
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

  /// Build screen for pending DM (no messages yet)
  Widget _buildPendingDMScreen(ThemeData theme, String currentUserId) {
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
          IconButton(
            icon: const Icon(LucideIcons.moreVertical),
            onPressed: () {
              // TODO: Show chat options menu
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Empty state for new chat
          Expanded(child: _buildEmptyState(theme)),
          // Message input
          MessageInput(
            chatId: '', // Empty for pending DM
            participantIds: widget.pendingUserId != null
                ? [widget.pendingUserId!]
                : [],
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
            onSendDSP: _sendDSP,
            onMediaSelected: _onMediaPicked, // [NEW] Callback for preview
            replyingTo: _replyingTo,
            onCancelReply: _clearReply,
          ),
        ],
      ),
    );
  }

  /// Build screen for existing chat with messages
  Widget _buildChatScreen(ThemeData theme, String currentUserId) {
    final displayNameAsync = ref.watch(chatDisplayNameProvider(_activeChatId!));
    final chatAsync = ref.watch(chatProvider(_activeChatId!));
    final messagesAsync = ref.watch(messagesStreamProvider(_activeChatId!));
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
          loading: () => Text(
            widget.pendingUserName ?? 'Loading...',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          error: (_, _) => Text(
            widget.pendingUserName ?? 'Chat',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          data: (chat) {
            if (chat != null && chat.isDirect) {
              final profileAsync = ref.watch(
                chatScreenUserProfileProvider(chat),
              );

              return profileAsync.when(
                data: (profile) => ChatHeaderTitle(
                  profile: profile,
                  fallbackTitle: displayNameAsync.value ?? chat.name,
                  onTap: () {
                    if (profile?.uid != null) {
                      TrustVouchModal.show(
                        context: context,
                        targetUserId: profile!.uid!,
                        currentUserId: currentUserId,
                        displayName: displayNameAsync.value ?? chat.name,
                      );
                    }
                  },
                ),
                loading: () => Text(
                  displayNameAsync.value ?? chat.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                error: (_, _) => Text(
                  displayNameAsync.value ?? chat.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }

            // Fallback for non-direct chats
            return displayNameAsync.when(
              loading: () => Text(widget.pendingUserName ?? 'Loading...'),
              error: (_, _) => Text(widget.pendingUserName ?? 'Chat'),
              data: (displayName) {
                // [NEW] Fetch live community or event details
                Community? community;
                Event? event;
                Widget? communityAvatar;
                String? eventStatus;

                if (chat?.type == 'community' && chat?.communityId != null) {
                  final communityAsync = ref.watch(
                    communityDetailsProvider(chat!.communityId!),
                  );
                  community = communityAsync.value;

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
                      profileImage: community.profileImage,
                      flag: community.flag,
                      size: 36, // Header specific size
                    );
                  } else {
                    communityAvatar = CommunityChatUtils.getCommunityAvatar(
                      context: context,
                      chat: chat,
                      size: 36,
                    );
                  }
                } else if (chat?.isEvent == true && chat?.eventId != null) {
                  // Fetch Event Details
                  final eventAsync = ref.watch(
                    eventDetailsProvider(chat!.eventId!),
                  );
                  event = eventAsync.value;

                  if (event != null) {
                    // Calculate Status using Shared Logic
                    final statusInfo = event.getStatusBadgeInfo();
                    if (statusInfo['text'] != null) {
                      eventStatus = statusInfo['text'];
                    }
                  }
                }

                // [UPDATED] Show live member count for all community types
                final showMemberInfo =
                    (chat?.type == 'community' || chat?.type == 'group');

                // Family group chat avatar
                final isFamilyGroup = chat?.metadata?['isFamilyGroup'] == true;
                Widget? headerAvatar = communityAvatar;
                if (chat?.isChamber == true) {
                  headerAvatar = BilateralFlagAvatar(
                    homeCountryCode: chat?.homeCountryCode,
                    hostCountryCode: chat?.hostCountryCode,
                    size: 36,
                  );
                }
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
                        )
                      : displayName,
                  imageUrl: (chat?.isEvent == true)
                      ? (event?.imageUrl ?? chat?.photoUrl)
                      : chat?.photoUrl,
                  // Prioritize pre-rendered widget from utils
                  customAvatarWidget: headerAvatar,
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
                  // [NEW] Event Status
                  eventStatus: eventStatus,
                  onTap: () async {
                    if (chat?.type == 'group' || chat?.type == 'organization') {
                      context.push(
                        '/chats/${chat!.id}/info',
                        extra: {
                          'name': chat.name,
                          'image': chat.photoUrl,
                          'type': chat.type,
                        },
                      );
                    } else if (chat?.type == 'direct') {
                      // [CHANGED] Open Trust Vouch Modal instead of profile
                      final currentUid = ref
                          .read(authRepositoryProvider)
                          .currentUser
                          ?.uid;
                      final otherId = chat?.participants.firstWhere(
                        (id) => id != currentUid,
                        orElse: () => '',
                      );
                      if (otherId != null &&
                          otherId.isNotEmpty &&
                          currentUid != null) {
                        TrustVouchModal.show(
                          context: context,
                          targetUserId: otherId,
                          currentUserId: currentUid,
                          displayName: displayName,
                          photoUrl: chat?.photoUrl,
                        );
                      }
                    } else if (chat?.type == 'community' && community != null) {
                      context.push(
                        '/communities/${community.id}/members',
                        extra: community,
                      );
                    } else if (chat?.isEvent == true && chat?.eventId != null) {
                      // [NEW] Go to Event Details
                      context.push('/events/${chat!.eventId}?fromChat=true');
                    }
                  },
                );
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

          // More Options Menu
          // More Options Menu (Only if member)
          Builder(
            builder: (context) {
              final chat = chatAsync.value;
              // Basic participant check
              var isParticipant =
                  chat?.participants.contains(currentUserId) ?? false;

              // Extended check for Events (Creator/Attendee)
              if (chat?.isEvent == true &&
                  chat?.eventId != null &&
                  !isParticipant) {
                // We need to resolve the event here.
                // Since we are in the actions list, we can rely on the fact that if we are here, the chat is loaded.
                // But we need the event data.
                final eventAsync = ref.watch(
                  eventDetailsProvider(chat!.eventId!),
                );
                final event = eventAsync.value;
                if (event != null) {
                  final isCreator = event.creatorId == currentUserId;
                  final isAttendee =
                      event.attendees?.contains(currentUserId) ?? false;
                  if (isCreator || isAttendee) {
                    isParticipant = true;
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
              // Show cache/optimistic immediately if avail, otherwise loading if empty & loading
              loading: () => const Center(child: CircularProgressIndicator()),
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
                  return _buildEmptyState(theme);
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
                // We need to check the event data.
                final eventAsync = ref.watch(
                  eventDetailsProvider(chat!.eventId!),
                );
                final event = eventAsync.value;
                if (event != null) {
                  final isCreator = event.creatorId == currentUserId;
                  final isAttendee =
                      event.attendees?.contains(currentUserId) ?? false;
                  if (isCreator || isAttendee) {
                    isParticipant = true;
                  }
                  // BOARD DISCLOSURE (Restriction Message)
                  // Use chat.isCommunity to show town community specific message
                  // [FIXED] Removed invalid Positioned dead code that was never returned
                }
              }

              // [MODIFIED] Only allow messaging if participant OR it's a direct chat
              if (chat != null && !isParticipant && chat.type != 'direct') {
                return ChatRestrictionView(
                  isCommunity: chat.isCommunity,
                  isOrganization: chat.isOrganization,
                  isEvent: chat.isEvent,
                  chatName: chat.name,
                  chatType: chat.type,
                  onJoin: (chat.type == 'group')
                      ? () async {
                          try {
                            await ref
                                .read(chatRepositoryProvider)
                                .joinGroup(chat.id);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Joined group!')),
                              );
                              ref.invalidate(chatProvider(chat.id));
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed to join: $e')),
                              );
                            }
                          }
                        }
                      : null,
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
                  recipientUserId: (chat?.type == 'direct')
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
                  onSendDSP: _sendDSP,
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

  Widget _buildEmptyState(ThemeData theme) {
    return const ChatEmptyState();
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

    debugPrint('ÃƒÂ°Ã…Â¸Ã¢â‚¬ËœÃ¢â€šÂ¬ Marking ${ids.length} messages as read');
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
    // Prevent duplicate opens while async data is loading
    if (_isShowingMoreMenu) return;
    _isShowingMoreMenu = true;

    final repo = ref.read(chatRepositoryProvider);
    final currentUserId = repo.currentUserId ?? '';
    final isDirect = chat.isDirect;
    final isCommunity = chat.isCommunity;

    // Fetch display name contextually
    String displayName = chat.name;
    try {
      displayName = await repo.getDisplayNameForChat(chat);
    } catch (_) {}

    // Fetch relationship status and pending requests for DMs
    Relationship? existingRelationship;
    RelationshipRequest? pendingSentRequest;
    RelationshipRequest? pendingIncomingRequest;

    if (isDirect && currentUserId.isNotEmpty) {
      final otherUserId = chat.getOtherParticipantId(currentUserId);
      if (otherUserId != null) {
        final relRepo = ref.read(relationshipRepositoryProvider);
        existingRelationship = await relRepo.getRelationship(
          userId: currentUserId,
          relatedUserId: otherUserId,
        );

        if (existingRelationship == null) {
          pendingSentRequest = await relRepo.getPendingSentRequest(
            fromUserId: currentUserId,
            toUserId: otherUserId,
          );

          if (pendingSentRequest == null) {
            pendingIncomingRequest = await relRepo.getPendingIncomingRequest(
              userId: currentUserId,
              fromUserId: otherUserId,
            );
          }
        }
      }
    }

    // Fetch Governance Unit & Community for Community Chats
    GovernanceUnit? governanceUnit;
    Community? community;

    if (isCommunity && chat.communityId != null) {
      try {
        governanceUnit = await ref
            .read(governanceRepositoryProvider)
            .getGovernanceUnitByCommunityId(chat.communityId!);
      } catch (e) {
        debugPrint('Error fetching governance: $e');
      }
      try {
        community = await ref
            .read(communityRepositoryProvider)
            .getCommunity(chat.communityId!);
      } catch (e) {
        debugPrint('Error fetching community: $e');
      }
    }

    // Check profile completeness for Verify/Vouch gate
    // Show "Verify & Vouch" if the user has ANY profile field filled
    // (not all 12 ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â that was too strict and hid the menu item)
    bool hasAnyProfileField = false;
    bool hasVerifiedTarget = false;
    if (isDirect && currentUserId.isNotEmpty) {
      try {
        final myProfile = await ref
            .read(profileRepositoryProvider)
            .getUserProfile(currentUserId);
        if (myProfile != null && myProfile.completedMilestoneFieldCount > 0) {
          hasAnyProfileField = true;
        }
        // Check if already verified this user
        final otherUserId = chat.getOtherParticipantId(currentUserId);
        if (otherUserId != null) {
          hasVerifiedTarget = await ref
              .read(trustRepositoryProvider)
              .hasVerifiedUser(currentUserId, otherUserId);
        }
      } catch (e) {
        debugPrint('Error fetching profile for verify gate: $e');
      }
    }

    if (!context.mounted) {
      _isShowingMoreMenu = false;
      return;
    }

    final outerContext = context;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ChatMoreMenuSheet(
        chat: chat,
        displayName: displayName,
        existingRelationship: existingRelationship,
        pendingSentRequest: pendingSentRequest,
        pendingIncomingRequest: pendingIncomingRequest,
        community: community,
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
        onVerifyUser: () {
          Navigator.pop(context);
          _handleVerifyChatUser(outerContext, ref, chat);
        },
        onVouchUser: () {
          Navigator.pop(context);
          // Open TrustVouchModal for continuous vouching (already verified)
          final currentUid = ref.read(authRepositoryProvider).currentUser?.uid;
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
          _showClearConfirmation(outerContext, repo, chat.id, displayName);
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
            titleOverride: chat.isGroup
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
            builder: (context) => AlertDialog(
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
                  style: TextButton.styleFrom(foregroundColor: AppTheme.error),
                  child: const Text('Block'),
                ),
              ],
            ),
          );

          if (confirm == true) {
            try {
              await ref
                  .read(relationshipRepositoryProvider)
                  .blockUser(userId: currentUserId, relatedUserId: otherId);
              if (outerContext.mounted) {
                outerContext.pop(); // Go back to chat list
                ScaffoldMessenger.of(outerContext).showSnackBar(
                  const SnackBar(
                    content: Text('User blocked'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            } catch (e) {
              if (outerContext.mounted) {
                ScaffoldMessenger.of(
                  outerContext,
                ).showSnackBar(SnackBar(content: Text('Error block: $e')));
              }
            }
          }
        },
        onReportUser: () {
          Navigator.pop(context);
          final otherId = chat.getOtherParticipantId(currentUserId);
          if (otherId != null) {
            _handleReportUser(outerContext, ref, otherId, displayName);
          }
        },
        onUnblockUser: () async {
          Navigator.pop(context);
          final otherId = chat.getOtherParticipantId(currentUserId);
          if (otherId == null) return;
          try {
            await ref
                .read(relationshipRepositoryProvider)
                .unblockUser(userId: currentUserId, relatedUserId: otherId);
            if (outerContext.mounted) {
              ScaffoldMessenger.of(outerContext).showSnackBar(
                const SnackBar(
                  content: Text('User unblocked'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          } catch (e) {
            if (outerContext.mounted) {
              ScaffoldMessenger.of(
                outerContext,
              ).showSnackBar(SnackBar(content: Text('Error: $e')));
            }
          }
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
              builder: (context) => ShareCommunityDialog(community: community!),
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
                if (chat.communityId != null) 'communityId': chat.communityId,
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
            builder: (context) =>
                BusinessRegistrationModal(communityId: chat.communityId),
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
        onLeaderElections: () {
          Navigator.pop(context);
          _handleLeaderElections(outerContext, chat, governanceUnit, community);
        },
      ),
    ).then((_) {
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

  // [NEW] DSP Transfer Logic
  Future<void> _sendDSP(int amount, String assetType, String? caption) async {
    final chatId = await _ensureChatCreated();
    if (chatId == null) return;

    // We need the recipient ID. In DM, it's the other user.
    // In Group, we might need to ask "Who to send to?" or if 1-on-1 is assumed.
    // The requirement implies 1-on-1 or "user from DM".
    // Let's assume DM for now strictly or handle single recipient.

    final currentUserId = ref.read(chatRepositoryProvider).currentUserId;
    if (currentUserId == null) return;

    String? toUserId;
    if (_isPendingDM) {
      toUserId = widget.pendingUserId;
    } else {
      final chat = await ref.read(chatRepositoryProvider).getChat(chatId);
      if (chat == null) return;
      // Find other user: Assuming DM logic for now as per feature spec context
      if (chat.participants.length >= 2) {
        toUserId = chat.participants.firstWhere(
          (id) => id != currentUserId,
          orElse: () => '',
        );
        if (toUserId.isEmpty) toUserId = null;
      }
    }

    if (toUserId == null) {
      // It's a group or invalid.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'DSP transfer currently only supported in Direct Messages.',
            ),
          ),
        );
      }
      return;
    }

    try {
      // Show loading
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) =>
              const Center(child: CircularProgressIndicator()),
        );
      }

      // Execute Transfer
      final transferResult = await ref
          .read(pointsServiceProvider)
          .transferAsset(
            fromUserId: currentUserId,
            toUserId: toUserId,
            amount: amount,
            assetType: assetType, // Use the selected asset type
          );

      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context); // Close loader
      }

      // Send a system message or a special "transfer" message type?
      // Requirement: "Beautiful little card in bubble"
      // So we send a message of type 'dsp_transfer' with amount metadata.

      final identity = ref.read(chatIdentityProvider);
      final participants = await _getParticipants();

      await ref
          .read(chatRepositoryProvider)
          .sendTextMessage(
            chatId,
            caption?.isNotEmpty == true
                ? caption!
                : 'Sent $amount ${assetType == 'token' ? '\$DIASPORA' : 'DSP'}', // Use caption if available
            type: 'dsp_transfer',
            senderIdOverride: identity?['id'],
            senderNameOverride: identity?['businessName'] ?? identity?['name'],
            senderImageOverride: identity?['profileImage'],
            metadata: {
              'amount': amount,
              'currency': assetType == 'token' ? 'DIASPORA' : 'DSP',
              'assetType': assetType,
              if (transferResult['settlementMode'] != null)
                'settlementMode': transferResult['settlementMode'],
              if (transferResult['txHash'] != null)
                'txHash': transferResult['txHash'],
            },
            participants: participants,
            // We should also set push notification payload if needed here via metadata or server function?
            // Cloud function triggers on message create usually handles push.
            // We will ensure push_notification_service handles this type locally or via FCM.
          );
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      debugPrint('DSP_TRANSFER: Error transferring $assetType: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Transfer failed: ${e.toString()}')),
        );
      }
    }
  }

  void _showClearConfirmation(
    BuildContext context,
    ChatRepository repo,
    String chatId,
    String name,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ChatConfirmationSheet(
        title: 'Clear Chat?',
        message:
            'Are you sure you want to clear your chat history with $name? This cannot be undone.',
        actionTitle: 'Clear Chat',
        subtitle: 'Delete all messages for you',
        icon: LucideIcons.eraser,
        onAction: () async {
          Navigator.pop(context); // Close sheet
          try {
            await repo.clearChat(chatId);
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Chat cleared')));
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error clearing chat: $e')),
              );
            }
          }
        },
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ChatConfirmationSheet(
        title: title,
        message: message,
        actionTitle: actionTitle,
        subtitle: subtitle,
        icon: isLeave ? LucideIcons.logOut : LucideIcons.trash2,
        onAction: () async {
          Navigator.pop(context); // Close sheet
          try {
            if (isLeave) {
              await repo.leaveChat(chatId);
            } else {
              await repo.deleteChat(chatId);
            }
            if (context.mounted) {
              // Handle post-deletion navigation
              Navigator.of(context).pop();
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Error: $e')));
            }
          }
        },
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
      builder: (sheetContext) => ChatMessageActionSheet(
        message: message,
        isOwn: isOwn,
        currentUserId: currentUserId,
        onReply: (m) => _setReplyTo(m),
        onReaction: (m, emoji) => _handleReaction(m, emoji),
        onReportMessage: (m) => _showReportDialog(context, ref, m),
        onBlockUser: (uid, name) => _handleBlockUser(context, ref, uid, name),
        onReportUser: (uid, name) => _handleReportUser(context, ref, uid, name),
        onVerifySolution: (m) => _handleVerifySolution(m),
        onDelete: (m) => _handleDeleteMessage(m),
      ),
    );
  }

  void _handleVerifySolution(Message message) async {
    final chatRepo = ref.read(chatRepositoryProvider);
    final currentUserId = chatRepo.currentUserId;
    if (currentUserId == null) return;

    final success = await ref
        .read(trustServiceProvider)
        .markAsVerifiedSolution(
          senderId: message.senderId,
          messageId: message.id,
          chatId: _activeChatId ?? '',
          reporterId: currentUserId,
        );

    if (mounted) {
      if (success) {
        showExplorationRewardToast(
          context,
          message: 'Verified solution! +1,000 DSP for you.',
          points: 1000,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Already marked as solution or error occurred.'),
          ),
        );
      }
    }
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
      builder: (context) => ChatConfirmationSheet(
        title: 'Delete Message',
        message:
            'Are you sure you want to delete this message? This action cannot be undone.',
        actionTitle: 'Delete Message',
        subtitle: 'This will permanently remove the message from this chat',
        onAction: () {
          Navigator.pop(context);
          ref
              .read(chatRepositoryProvider)
              .deleteMessage(message.chatId, message.id);
        },
      ),
    );
  }

  void _showReportDialog(BuildContext context, WidgetRef ref, Message message) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ChatReportSheet(
        title: 'Report Message',
        entityName: 'this message',
        reasons: ChatReportSheet.messageReasons,
        onReport: (reason) async {
          Navigator.pop(context); // Close sheet

          // Show loading
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Submitting report...')));

          try {
            final currentUserId = ref
                .read(authRepositoryProvider)
                .currentUser
                ?.uid;
            if (currentUserId == null) return;

            final success = await ref
                .read(reportRepositoryProvider)
                .reportMessage(
                  reporterId: currentUserId,
                  messageId: message.id,
                  senderId: message.senderId,
                  reason: reason,
                );

            // [NEW] Award 100 DSP for reporting a message
            if (success) {
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
            }

            if (context.mounted) {
              if (success) {
                showExplorationRewardToast(
                  context,
                  message: 'Report submitted. Thank you!',
                  points: 100,
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to submit report. Please try again.'),
                    backgroundColor: AppTheme.error,
                  ),
                );
              }
            }
          } catch (e) {
            debugPrint('Error reporting message: $e');
          }
        },
      ),
    );
  }

  // [NEW] Handle Verify User from Chat
  Future<void> _handleVerifyChatUser(
    BuildContext context,
    WidgetRef ref,
    Chat chat,
  ) async {
    final currentUserId = ref.read(authRepositoryProvider).currentUser?.uid;
    if (currentUserId == null) return;

    // Identify other user
    final otherUserId = chat.participants.firstWhere(
      (id) => id != currentUserId,
      orElse: () => '',
    );

    if (otherUserId.isEmpty) return;

    // Fetch profile
    try {
      final profile = await ref
          .read(profileRepositoryProvider)
          .getUserProfile(otherUserId);
      if (profile == null) return;

      // 1. Check existing relationship ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â only block family (Conflict of Interest)
      final relRepo = ref.read(relationshipRepositoryProvider);
      final rel = await relRepo.getRelationship(
        userId: currentUserId,
        relatedUserId: otherUserId,
      );

      if (rel != null && rel.status == 'active') {
        const Set<String> familyTypes = {
          'wife',
          'husband',
          'daughter',
          'son',
          'mother',
          'father',
          'sister',
          'brother',
          'aunt',
          'uncle',
          'nephew',
          'niece',
          'cousin',
        };
        if (familyTypes.contains(rel.type.toLowerCase())) {
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
      }

      // 2. Check eligibility
      final trustService = ref.read(trustServiceProvider);
      final eligibilityError = await trustService.checkVerificationEligibility(
        currentUserId,
        otherUserId,
      );

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

      // 3. Show Verification Modal directly (no relationship selection needed)
      // Relationships are added separately via "Add Relationship" in the menu.
      if (context.mounted) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (c) => ProfileVerificationModal(
            targetUser: profile,
            currentUserId: currentUserId,
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
      builder: (context) => RelationshipSelectionModal(
        otherUserId: otherUserId,
        otherUserName: displayName ?? 'User',
        onSelected: (type) async {
          Navigator.pop(context);
          final repo = ref.read(relationshipRepositoryProvider);
          final myProfile = ref.read(userProfileProvider).value;

          if (myProfile == null) return;

          try {
            await repo.sendRelationshipRequest(
              fromUserId: myProfile.uid!,
              fromUserName: myProfile.fullName,
              fromUserFlag: CountryUtils.getCountryFlag(
                myProfile.homeCountryCode,
              ),
              fromUserPhoto: myProfile.profileImage,
              toUserId: otherUserId,
              toUserName: displayName ?? 'User',
              relationshipType: type,
            );

            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Relationship request sent')),
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error sending request: $e')),
              );
            }
          }
        },
      ),
    );
  }

  void _handleBlockUser(
    BuildContext context,
    WidgetRef ref,
    String userId,
    String userName,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ChatConfirmationSheet(
        title: 'Block User',
        message:
            'Are you sure you want to block $userName? They will not be able to message you.',
        actionTitle: 'Block User',
        subtitle: 'You can unblock them later from your profile settings',
        onAction: () async {
          Navigator.pop(context); // Close sheet

          final currentUserId = ref
              .read(authRepositoryProvider)
              .currentUser
              ?.uid;
          if (currentUserId == null) return;

          try {
            await ref
                .read(relationshipRepositoryProvider)
                .blockUser(userId: currentUserId, relatedUserId: userId);

            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('User blocked')));
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error blocking user: $e')),
              );
            }
          }
        },
      ),
    );
  }

  void _handleReportUser(
    BuildContext context,
    WidgetRef ref,
    String userId,
    String userName,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ChatReportSheet(
        title: 'Report $userName',
        entityName: userName,
        reasons: ChatReportSheet.userReasons,
        onReport: (reason) async {
          Navigator.pop(context);

          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Submitting report...')));

          try {
            final currentUserId = ref
                .read(authRepositoryProvider)
                .currentUser
                ?.uid;
            if (currentUserId == null) return;

            final success = await ref
                .read(reportRepositoryProvider)
                .reportUser(
                  reporterId: currentUserId,
                  reportedUserId: userId,
                  reason: reason,
                );

            if (success) {
              // Award 100 DSP for reporting a sender (new report only)
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

              if (context.mounted) {
                showExplorationRewardToast(
                  context,
                  message: 'Report submitted. Thank you!',
                  points: 100,
                );
              }
            } else {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('You have already reported this user.'),
                  ),
                );
              }
            }
          } catch (e) {
            debugPrint('Error reporting user: $e');
          }
        },
      ),
    );
  }
}

// End of file or removed classes
