import 'dart:async';

import 'package:flutter/services.dart' as io;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter/services.dart'; // [NEW] for Clipboard
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:share_plus/share_plus.dart'; // [NEW]
import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'package:diaspora_nearby/features/chat/models/chat.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/chat/utils/community_chat_utils.dart'; // [NEW] Parity utils
import 'package:diaspora_nearby/features/chat/widgets/message_bubble.dart';
import 'package:diaspora_nearby/features/chat/widgets/message_input.dart';
import 'package:diaspora_nearby/features/chat/widgets/chat_header_title.dart';
import 'package:diaspora_nearby/features/community/repository/community_repository.dart'; // [NEW]
import 'package:diaspora_nearby/theme/app_theme.dart'; // [FIXED]
import 'package:diaspora_nearby/features/chat/screens/create_group_screen.dart';
import 'package:diaspora_nearby/features/chat/screens/forward_chat_selection_screen.dart'; // [NEW]
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
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
import 'package:diaspora_nearby/features/shared/widgets/confetti_overlay.dart'; // [NEW]
import 'package:diaspora_nearby/features/shared/services/content_share_service.dart'; // [NEW]
import 'package:diaspora_nearby/features/governance/repository/governance_repository.dart'; // [NEW]
import 'package:diaspora_nearby/features/governance/screens/leader_selection_screen.dart'; // [NEW]
import 'package:diaspora_nearby/features/governance/models/governance_unit.dart'; // [NEW]
import 'package:diaspora_nearby/features/events/screens/create_event_screen.dart'; // [NEW]
import 'package:diaspora_nearby/features/more/widgets/business_registration_modal.dart'; // [NEW]

import 'package:diaspora_nearby/features/chat/providers/chat_providers.dart'; // [NEW] Shared Providers

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

  @override
  void initState() {
    super.initState();
    _activeChatId = widget.chatId;
    _scrollController.addListener(_onScroll);

    // LOGGING TO DEBUG "NOTHING HAPPENS"
    final currentUserId = ref.read(chatRepositoryProvider).currentUserId;
    debugPrint('📩 ChatScreen INIT:');
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

    // Clear reply immediately
    _clearReply();

    // If this is a pending DM, create the chat first
    if (_isPendingDM && _activeChatId == null) {
      debugPrint('📍 Creating DM chat on first message...');
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
        debugPrint('✅ Chat created: ${chat.id}');
      } else {
        debugPrint(
          'â Failed to create chat with user ${widget.pendingUserId}',
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

      // [NEW] Fetch participants for instant list update
      List<String>? participants;
      try {
        final chat = await chatRepo.getChat(_activeChatId!);
        participants = chat?.participants;
      } catch (e) {
        debugPrint('Error fetching chat for participants: $e');
      }

      // [NEW] Optimistic UI
      final currentUserId = ref.read(chatRepositoryProvider).currentUserId;
      if (currentUserId != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final tempId = 'temp_${now}_$currentUserId';

        final optimisticMessage = Message(
          id: tempId,
          chatId: _activeChatId!,
          senderId: senderIdOverride ?? currentUserId,
          senderName: senderNameOverride ?? 'Me', // Fallback, usually fetched
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
          debugPrint('Error sending message: $e');
          // Optionally mark as failed instead of removing?
          // For now, removing to avoid stuck 'sending' state if logic doesn't handle failures well
          // or we could update status to 'failed'
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
          participants: participants,
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

    debugPrint('📍 Creating DM chat for media/file...');
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
      debugPrint('✅ Chat created: ${chat.id}');
      return chat.id;
    } else {
      debugPrint('â Failed to create chat with user ${widget.pendingUserId}');
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
        if (Navigator.canPop(context)) Navigator.pop(context); // Close loader
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

      if (context.mounted && Navigator.canPop(context)) {
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

  Future<void> _sendLocationMessage(MessageLocation location) async {
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
        content: '',
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

    debugPrint('ð Retrying failed message: ${failedMessage.id}');
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
          error: (_, __) => Text(
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
                ),
                loading: () => Text(
                  displayNameAsync.value ?? chat.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                error: (_, __) => Text(
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
              error: (_, __) => Text(widget.pendingUserName ?? 'Chat'),
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
                  customAvatarWidget: communityAvatar,
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
                      // Original profile view logic
                      final otherId = chat?.participants.firstWhere(
                        (id) =>
                            id !=
                            ref.read(authRepositoryProvider).currentUser?.uid,
                        orElse: () => '',
                      );
                      if (otherId != null && otherId.isNotEmpty) {
                        context.push('/profile/$otherId');
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
                          final phone = profile.phone;
                          // Keep + for app scheme
                          final appPhone = phone.replaceAll(
                            RegExp(r'[^\d+]'),
                            '',
                          );
                          // Remove everything including + for web scheme
                          final webPhone = phone.replaceAll(RegExp(r'\D'), '');

                          final appUrl = Uri.parse(
                            'whatsapp://send?phone=$appPhone',
                          );
                          final webUrl = Uri.parse('https://wa.me/$webPhone');

                          try {
                            // Try app first
                            bool launched = false;
                            if (await canLaunchUrl(appUrl)) {
                              launched = await launchUrl(
                                appUrl,
                                mode: LaunchMode.externalApplication,
                              );
                            }

                            // Fallback to web if app fail
                            if (!launched) {
                              if (await canLaunchUrl(webUrl)) {
                                await launchUrl(
                                  webUrl,
                                  mode: LaunchMode.externalApplication,
                                );
                              } else {
                                throw 'Could not launch WhatsApp';
                              }
                            }
                          } catch (e) {
                            debugPrint('WhatsApp Launch Error: $e');
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Could not launch WhatsApp'),
                                ),
                              );
                            }
                          }
                        },
                      );
                    }
                    return const SizedBox.shrink();
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),

          // More Options Menu
          // More Options Menu (Only if member)
          Builder(builder: (context) {
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
          }),
        ],
      ),
      resizeToAvoidBottomInset: true,
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
                // Sort everything by timestamp DESC.
                final allMessages = [...pendingMessages, ...streamMessages];
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
                          if (repliedMessage.id.isEmpty ?? true) {
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
                                onReply: () => _setReplyTo(message),
                                onReplyTap: _scrollToMessage,
                                onLongPress: () => _handleMessageAction(context, message, ref),
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

                    // [NEW] WhatsApp-style Scroll to Bottom FAB
                    if (!_isNearBottom)
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: GestureDetector(
                          onTap: () => _scrollToBottom(),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                              border: Border.all(
                                color: theme.colorScheme.outline.withOpacity(
                                  0.1,
                                ),
                                width: 0.5,
                              ),
                            ),
                            child: Icon(
                              LucideIcons.chevronsDown,
                              size: 20,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),

          // Typing indicator (above input)
          typingAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (typingUsers) {
              if (typingUsers.isEmpty) return const SizedBox.shrink();

              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    _buildTypingDots(theme),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Consumer(
                        builder: (context, ref, child) {
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
                              loading: () => Text(
                                'Someone is typing...',
                                style: theme.textTheme.bodySmall,
                              ),
                              error: (_, __) => Text(
                                'Someone is typing...',
                                style: theme.textTheme.bodySmall,
                              ),
                            );
                          }
                          return Text(
                            '${typingUsers.length} people are typing...',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
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
                  if (!isParticipant && (chat?.isOrganization == true || chat?.isCommunity == true))
                    Positioned(
                      bottom: 80,
                      left: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.lock,
                              size: 24,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              chat?.isCommunity == true
                                  ? 'Only members of the ${chat?.name ?? 'this'} community can post here.'
                                  : 'Only authorized participants can post to this organization board.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                }
              }

              // [MODIFIED] Only allow messaging if participant OR it's a direct chat
              if (chat != null && !isParticipant && chat.type != 'direct') {
                // [NEW] Allow joining Groups
                if (chat.type == 'group') {
                  return SafeArea(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        border: Border(
                          top: BorderSide(color: theme.dividerColor),
                        ),
                        boxShadow: [
                           BoxShadow(
                             color: Colors.black.withOpacity(0.05),
                             blurRadius: 4,
                             offset: const Offset(0, -2),
                           )
                        ],
                      ),
                      child: FilledButton.icon(
                        onPressed: () async {
                           // Join Logic
                           try {
                             await ref.read(chatRepositoryProvider).joinGroup(chat.id);
                             if (context.mounted) {
                               ScaffoldMessenger.of(context).showSnackBar(
                                 const SnackBar(content: Text('Joined group!')),
                               );
                               // Force refresh
                               ref.invalidate(chatProvider(chat.id));
                             }
                           } catch (e) {
                             if (context.mounted) {
                               ScaffoldMessenger.of(context).showSnackBar(
                                 SnackBar(content: Text('Failed to join: $e')),
                               );
                             }
                           }
                        },
                        icon: const Icon(LucideIcons.plus),
                        label: const Text('Join Group'),
                      ),
                    ),
                  );
                }

                // Default "Locked" view for other types (or restricted)
                return SafeArea(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 20,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      border: Border(
                        top: BorderSide(color: theme.dividerColor),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.lock,
                          size: 20,
                          color: theme.colorScheme.secondary,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          chat.isCommunity
                              ? 'Only members of the ${chat.name} community can post here.'
                              : chat.isOrganization
                              ? 'Only authorized participants can post to this organization board.'
                              : chat.isEvent
                              ? 'Only attendees can post to this event chat.'
                              : 'You are not a participant of this group.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.secondary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
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

  /// Show context menu for message interactions
  void _showMessageContextMenu(
    BuildContext context,
    Message message,
    String currentUserId,
  ) {
    final theme = Theme.of(context);
    final chatRepo = ref.read(chatRepositoryProvider);
    final isOwn = message.senderId == currentUserId;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              // Drag handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // Reaction Row
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: ['❤️', '😂', '👍', '👎', '😮', '😢', '🙏', '🔥']
                      .map((emoji) {
                        final isSelected =
                            message.reactions?.any(
                              (r) =>
                                  r.emoji == emoji &&
                                  r.userIds.contains(currentUserId),
                            ) ??
                            false;

                        return GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                            if (isSelected) {
                              chatRepo.removeReaction(
                                message.chatId,
                                message.id,
                                emoji,
                              );
                            } else {
                              chatRepo.addReaction(
                                message.chatId,
                                message.id,
                                emoji,
                                message.senderId,
                              );
                            }
                          },
                          child: Container(
                            margin: const EdgeInsets.only(right: 12),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? theme.colorScheme.primaryContainer
                                  : theme.colorScheme.surfaceContainerHighest
                                        .withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              emoji,
                              style: const TextStyle(fontSize: 24),
                            ),
                          ),
                        );
                      })
                      .toList(),
                ),
              ),

              const SizedBox(height: 8),
              const Divider(),

              // Actions List
              ListTile(
                leading: const Icon(LucideIcons.reply),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.pop(context);
                  _setReplyTo(message);
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.forward),
                title: const Text('Forward'),
                onTap: () async {
                  Navigator.pop(context);
                  // Navigate to Forward Selection Screen
                  final selectedChatIds = await context.push<List<String>>(
                    '/chats/forward_selection',
                  );
                  if (selectedChatIds != null && selectedChatIds.isNotEmpty) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Forwarding message...'),
                          duration: Duration(
                            seconds: 1,
                          ), // Short duration as it updates quickly usually
                        ),
                      );
                    }

                    final identity = ref.read(chatIdentityProvider);
                    await chatRepo.forwardMessage(
                      message,
                      selectedChatIds,
                      senderIdOverride: identity?['id'],
                      senderNameOverride:
                          identity?['businessName'] ?? identity?['name'],
                      senderImageOverride: identity?['profileImage'],
                    );

                    if (mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).hideCurrentSnackBar(); // Hide "sending"
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Forwarded to ${selectedChatIds.length} chat${selectedChatIds.length > 1 ? 's' : ''}',
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  }
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.copy),
                title: const Text('Copy'),
                onTap: () async {
                  // Copy text logic
                  await io.Clipboard.setData(
                    io.ClipboardData(text: message.content),
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied to clipboard')),
                    );
                  }
                },
              ),
              if (isOwn)
                ListTile(
                  leading: Icon(
                    LucideIcons.trash2,
                    color: theme.colorScheme.error,
                  ),
                  title: Text(
                    'Delete',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showDeleteMessageConfirmation(context, message, chatRepo);
                  },
                ),

              if (!isOwn)
                ListTile(
                  leading: const Icon(LucideIcons.flag, color: Colors.orange),
                  title: const Text(
                    'Report',
                    style: TextStyle(color: Colors.orange),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    // Show Report Dialog
                    showDialog(
                      context: context,
                      builder: (c) {
                        // Simple dialog for now, can be expanded to select reason
                        return AlertDialog(
                          title: const Text('Report Message'),
                          content: const Text(
                            'Flag this message as containing unsolicited ads or spam?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () async {
                                Navigator.pop(c);
                                final currentUserId = ref
                                    .read(chatRepositoryProvider)
                                    .currentUserId;
                                if (currentUserId != null) {
                                  await ref
                                      .read(reportRepositoryProvider)
                                      .reportMessage(
                                        reporterId: currentUserId,
                                        messageId: message.id,
                                        senderId: message.senderId,
                                        reason: 'ad',
                                      );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Message reported. Thank you.',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                              child: const Text(
                                'Report',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),

              // [NEW] Share Option
              ListTile(
                leading: const Icon(LucideIcons.share2),
                title: const Text('Share'),
                onTap: () {
                  Navigator.pop(context);
                  ref
                      .read(contentShareServiceProvider)
                      .shareMessage(context, message);
                },
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteMessageConfirmation(
    BuildContext context,
    Message message,
    ChatRepository chatRepo,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message?'),
        content: const Text('Are you sure you want to delete this message?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              chatRepo.deleteMessage(
                message.chatId,
                message.id,
                deleteForEveryone: false,
              );
            },
            child: const Text('Delete for Me'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              chatRepo.deleteMessage(
                message.chatId,
                message.id,
                deleteForEveryone: true,
              );
            },
            child: Text(
              'Delete for Everyone',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
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

  Widget _buildDateSeparator(int timestamp, ThemeData theme) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final difference = now.difference(date);

    String dateText;
    if (difference.inDays == 0) {
      dateText = 'Today';
    } else if (difference.inDays == 1) {
      dateText = 'Yesterday';
    } else if (difference.inDays < 7) {
      dateText = _getDayName(date.weekday);
    } else {
      dateText = '${date.month}/${date.day}/${date.year}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            dateText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  String _getDayName(int weekday) {
    switch (weekday) {
      case 1:
        return 'Monday';
      case 2:
        return 'Tuesday';
      case 3:
        return 'Wednesday';
      case 4:
        return 'Thursday';
      case 5:
        return 'Friday';
      case 6:
        return 'Saturday';
      case 7:
        return 'Sunday';
      default:
        return '';
    }
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.messageCircle,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No messages yet',
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Send a message to start the conversation',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build animated typing dots
  Widget _buildTypingDots(ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return Padding(
          padding: EdgeInsets.only(left: index > 0 ? 3 : 0),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.7),
              shape: BoxShape.circle,
            ),
          ),
        );
      }),
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
    final theme = Theme.of(context);
    final repo = ref.read(chatRepositoryProvider);
    final isDirect = chat.isDirect;
    final isGroup = chat.isGroup;
    final isCommunity = chat.isCommunity;
    final isEvent = chat.isEvent;

    // Fetch display name contextually
    String displayName = chat.name;
    try {
      displayName = await repo.getDisplayNameForChat(chat);
    } catch (_) {}

    // Extract first name for DMs, keep full name for others
    final nameToUse = isDirect ? displayName.split(' ').first : displayName;

    // [FIX] Fetch relationship status and pending requests before showing menu
    Relationship? existingRelationship;
    RelationshipRequest? pendingSentRequest;
    RelationshipRequest? pendingIncomingRequest;

    if (isDirect) {
      final otherUserId = chat.getOtherParticipantId(repo.currentUserId ?? '');
      if (otherUserId != null && repo.currentUserId != null) {
        final relRepo = ref.read(relationshipRepositoryProvider);
        
        // 1. Check Active Relationship
        existingRelationship = await relRepo.getRelationship(
          userId: repo.currentUserId!,
          relatedUserId: otherUserId,
        );

        // 2. Check Pending Requests (only if no active relationship)
        if (existingRelationship == null) {
           pendingSentRequest = await relRepo.getPendingSentRequest(
             fromUserId: repo.currentUserId!,
             toUserId: otherUserId,
           );
           
           if (pendingSentRequest == null) {
             pendingIncomingRequest = await relRepo.getPendingIncomingRequest(
               userId: repo.currentUserId!,
               fromUserId: otherUserId,
             );
           }
        }
      }
    }

    // [NEW] Fetch Governance Unit for Community Chats
    // [NEW] Fetch Governance Unit & Community for Community Chats
    GovernanceUnit? governanceUnit;
    Community? community;

    if (isCommunity && chat.communityId != null) {
      try {
        // Fetch Governance Unit
        governanceUnit = await ref
            .read(governanceRepositoryProvider)
            .getGovernanceUnitByCommunityId(chat.communityId!);
            
        // Fetch Community (for fallback info)
        community = await ref
            .read(communityRepositoryProvider)
            .getCommunity(chat.communityId!);
      } catch (e) {
        debugPrint('Error fetching governance/community: $e');
      }
    }

    if (!context.mounted) return;

    // Use showDialog with column/spacer to position at top
    showDialog(
      context: context,
      barrierColor: Colors.black12, // Subtle barrier
      builder: (context) {
        return Stack(
          children: [
            Positioned(
              top:
                  kToolbarHeight +
                  MediaQuery.of(context).padding.top, // Below AppBar 0px
              left: 8,
              right: 8,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // [NEW] Relationship (Top Priority)
                      if (isDirect) ...[
                        if (existingRelationship != null)
                          _buildSheetItem(
                            context,
                            icon: LucideIcons.heart,
                            iconColor: Colors.pink.shade600,
                            iconBgColor: Colors.pink.shade50,
                            title: 'Relationship',
                            subtitle: existingRelationship.type,
                            onTap: () {
                              Navigator.pop(context);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'You are connected as ${existingRelationship!.type}',
                                    ),
                                  ),
                                );
                              }
                            },
                          )
                        else if (pendingSentRequest != null)
                          _buildSheetItem(
                            context,
                            icon: LucideIcons.clock,
                            iconColor: Colors.orange.shade600,
                            iconBgColor: Colors.orange.shade50,
                            title: 'Relationship request waiting',
                            subtitle: 'Request sent to $nameToUse',
                            onTap: () {
                              Navigator.pop(context);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Request is pending acceptance'),
                                  ),
                                );
                              }
                            },
                          )
                        else if (pendingIncomingRequest != null)
                           _buildSheetItem(
                            context,
                            icon: LucideIcons.bellRing,
                            iconColor: Colors.green.shade600,
                            iconBgColor: Colors.green.shade50,
                            title: 'Accept Request',
                            subtitle: '$nameToUse sent you a request',
                            onTap: () {
                              Navigator.pop(context);
                              // Navigate to notifications or show accept dialog?
                              // For simplicity/safety, just tell them to check notifications page
                              // or implement a quick accept dialog here?
                              // Implementing quick navigation to notification page logic or just a toast for now as 'Accept' logic is complex UI.
                              // Actually, let's just guide them.
                              if (context.mounted) {
                                 ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Please check your notifications to accept.'),
                                  ),
                                );
                              }
                            },
                          )
                        else
                          _buildSheetItem(
                            context,
                            icon: LucideIcons.heartHandshake,
                            iconColor: Colors.pink.shade600,
                            iconBgColor: Colors.pink.shade50,
                            title: 'Add Relationship',
                            subtitle:
                                'Define your relationship with $nameToUse',
                            onTap: () {
                              Navigator.pop(context);
                              _showRelationshipPicker(
                                context,
                                ref,
                                chat.getOtherParticipantId(
                                  repo.currentUserId ?? '',
                                ),
                                displayName,
                              );
                            },
                          ),
                        // Divider between relationship and other items
                        if (existingRelationship == null)
                          const Divider(height: 1),
                      ],

                      // Event Attendees
                      if (isEvent && chat.eventId != null)
                        _buildSheetItem(
                          context,
                          icon: LucideIcons.userCheck,
                          iconColor: Colors.blue.shade700,
                          iconBgColor: Colors.blue.shade50,
                          title: 'Event attendees',
                          subtitle: "View who's attending this event",
                          onTap: () {
                            Navigator.pop(context);
                            context.push('/events/${chat.eventId}/attendees');
                          },
                        ),

                      // New Group (Direct Only)
                      if (isDirect)
                        _buildSheetItem(
                          context,
                          icon: LucideIcons.users,
                          iconColor: Colors.blue.shade700,
                          iconBgColor: Colors.blue.shade50,
                          title: 'Start group chat',
                          subtitle: 'Create a group with $nameToUse',
                          onTap: () async {
                            Navigator.pop(context);
                            final otherId = chat.getOtherParticipantId(
                              repo.currentUserId ?? '',
                            );
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                fullscreenDialog: true,
                                builder: (context) => CreateGroupScreen(
                                  initialParticipantId: otherId,
                                ),
                              ),
                            );
                          },
                        ),

                      // Group Info (Groups Only - Profile is via Header)
                      if (!isCommunity && !isEvent && !isDirect)
                        _buildSheetItem(
                          context,
                          icon: LucideIcons.settings,
                          iconColor: Colors.grey.shade700,
                          iconBgColor: Colors.grey.shade100,
                          title: 'Group info',
                          subtitle: 'Manage group settings',
                          onTap: () {
                            Navigator.pop(context);
                            context.push(
                              '/chats/${chat.id}/info',
                              extra: {
                                'name': chat.name,
                                'image': chat.photoUrl,
                                'type': chat.type,
                              },
                            );
                          },
                        ),
                      
                      // Create Group Event
                      if (!isCommunity && !isEvent && !isDirect)
                        _buildSheetItem(
                          context,
                          icon: LucideIcons.calendarPlus,
                          iconColor: Colors.orange.shade700,
                          iconBgColor: Colors.orange.shade50,
                          title: 'Create Group Event',
                          subtitle: 'Host an event for this group',
                          onTap: () {
                            Navigator.pop(context);
                            context.push(
                              Uri(
                                path: '/events/create',
                                queryParameters: {
                                  'groupId': chat.id,
                                },
                              ).toString(),
                            );
                          },
                        ),

                      // Mute
                      _buildSheetItem(
                        context,
                        icon: LucideIcons.bell,
                        iconColor: Colors.purple.shade700,
                        iconBgColor: Colors.purple.shade50,
                        title: chat.isMuted ? 'Unmute' : 'Mute',
                        subtitle: chat.isMuted
                            ? 'Enable notifications'
                            : 'Stop receiving notifications',
                        onTap: () async {
                          Navigator.pop(context);
                          await repo.toggleMute(chat.id, !chat.isMuted);
                        },
                      ),

                      // ... inside _showMoreMenu ...

                      // Block/Unblock User (Direct Only)
                      if (isDirect)
                         Builder(
                          builder: (context) {
                            final profile = ref.read(userProfileProvider).value;
                            final otherId = chat.getOtherParticipantId(
                              repo.currentUserId ?? '',
                            );
                            
                            if (otherId == null) return const SizedBox.shrink();

                            final isBlocked = profile?.blockedUsers?.contains(otherId) ?? false;

                            return _buildSheetItem(
                              context,
                              icon: isBlocked ? LucideIcons.shieldCheck : LucideIcons.ban,
                              iconColor: isBlocked ? Colors.green.shade700 : Colors.red.shade700,
                              iconBgColor: isBlocked ? Colors.green.shade50 : Colors.red.shade50,
                              title: isBlocked ? 'Unblock User' : 'Block User',
                              subtitle: isBlocked ? 'Allow them to message you' : 'Block this user',
                              isDestructive: !isBlocked,
                              onTap: () async {
                                Navigator.pop(context);
                                if (isBlocked) {
                                  // Unblock Logic
                                  try {
                                    await ref
                                        .read(relationshipRepositoryProvider)
                                        .unblockUser(
                                          userId: repo.currentUserId!,
                                          relatedUserId: otherId,
                                        );
                                     if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('User unblocked'),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Error: $e')),
                                      );
                                    }
                                  }
                                } else {
                                  // Block Logic
                                  final confirm = await showDialog<bool>(
                                    context: context,
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
                                          style: TextButton.styleFrom(
                                            foregroundColor: AppTheme.error,
                                          ),
                                          child: const Text('Block'),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (confirm == true) {
                                    try {
                                      await ref
                                          .read(relationshipRepositoryProvider)
                                          .blockUser(
                                            userId: repo.currentUserId!,
                                            relatedUserId: otherId,
                                          );
                                      if (context.mounted) {
                                         context.pop(); // Go back to list
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('User blocked'),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Error: $e')),
                                        );
                                      }
                                    }
                                  }
                                }
                              },
                            );
                          }
                        ),

                      // existing items...
                      _buildSheetItem(
                        context,
                        icon: LucideIcons.eraser,
                        iconColor: Colors.orange.shade700,
                        iconBgColor: Colors.orange.shade50,
                        title: 'Clear chat',
                        subtitle: 'Clear messages for me',
                        onTap: () async {
                          Navigator.pop(context);
                          _showClearConfirmation(
                            context,
                            repo,
                            chat.id,
                            nameToUse,
                          );
                        },
                      ),

                      // Delete / Leave Chat (All types except community)
                      if (!isCommunity)
                        _buildSheetItem(
                          context,
                          icon: (isGroup || isEvent || chat.isOrganization)
                              ? LucideIcons.logOut
                              : LucideIcons.trash2,
                          iconColor: Colors.red.shade700,
                          iconBgColor: Colors.red.shade50,
                          title: isGroup
                              ? 'Leave group'
                              : isEvent
                              ? 'Leave event'
                              : chat.isOrganization
                              ? 'Unfollow Organization' // [UPDATED]
                              : 'Delete chat',
                          subtitle: (isGroup || isEvent || chat.isOrganization)
                              ? 'Remove from your list'
                              : 'Delete from your list',
                          isDestructive: true,
                          onTap: () async {
                            Navigator.pop(context);
                            // Unified delete/leave confirmation
                            String dialogTitle = 'Delete Chat?';
                            if (isGroup) dialogTitle = 'Leave Group?';
                            if (isEvent) dialogTitle = 'Leave Event?';
                            if (chat.isOrganization) dialogTitle = 'Unfollow Organization?'; // [UPDATED]

                            _showDeleteConfirmation(
                              context,
                              repo,
                              chat.id,
                              nameToUse,
                              isLeave: isGroup || isEvent || chat.isOrganization,
                              titleOverride: (isGroup || isEvent || chat.isOrganization) ? dialogTitle : null,
                            );
                          },
                        ),

                      // Share Community (Community Only)
                      if (isCommunity)
                        _buildSheetItem(
                          context,
                          icon: LucideIcons.share2,
                          iconColor: Colors.blue.shade700,
                          iconBgColor: Colors.blue.shade50,
                          title: 'Share Community',
                          subtitle: 'Share this community with others',
                          onTap: () {
                            Navigator.pop(context);
                            // Basic share implementation
                            Share.share(
                              'Check out $displayName on DiasporaNearby!',
                            );
                          },
                        ),

                      // Create Community Group
                      if (isCommunity)
                        _buildSheetItem(
                          context,
                          icon: LucideIcons.users,
                          iconColor: Colors.blue.shade700,
                          iconBgColor: Colors.blue.shade50,
                          title: 'Create Community Group',
                          subtitle: 'Start a public group in this community',
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                fullscreenDialog: true,
                                builder: (context) => CreateGroupScreen(
                                  communityId: chat.communityId,
                                ),
                              ),
                            );
                          },
                        ),

                      // Create Community Event
                      if (isCommunity)
                        _buildSheetItem(
                          context,
                          icon: LucideIcons.calendarDays,
                          iconColor: Colors.orange.shade700,
                          iconBgColor: Colors.orange.shade50,
                          title: 'Create Community Event',
                          subtitle: 'Host an event for this community',
                          onTap: () {
                            Navigator.pop(context);
                            context.push(
                              Uri(
                                path: '/events/create',
                                queryParameters: {
                                  if (chat.communityId != null)
                                    'communityId': chat.communityId,
                                },
                              ).toString(),
                            );
                          },
                        ),

                      // Create Community Org
                      if (isCommunity)
                        _buildSheetItem(
                          context,
                          icon: LucideIcons.briefcase,
                          iconColor: Colors.purple.shade700,
                          iconBgColor: Colors.purple.shade50,
                          title: 'Create Community Org/Business',
                          subtitle: 'Register a business in this community',
                          onTap: () {
                            Navigator.pop(context);
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              useSafeArea: true,
                              builder: (context) => BusinessRegistrationModal(
                                communityId: chat.communityId,
                              ),
                            );
                          },
                        ),

                      // Leader Elections (Community Only)
                      if (isCommunity)
                        _buildSheetItem(
                          context,
                          icon: LucideIcons.vote,
                          iconColor: AppTheme.accent,
                          iconBgColor: AppTheme.accent.withValues(alpha: 0.1),
                          title: 'Council of Community Leaders',
                          subtitle: (governanceUnit?.isActiveElection ?? false)
                              ? 'Active council election in progress' 
                              : 'Elect council members and treasury signers',
                          onTap: () {
                            Navigator.pop(context);
                            
                            // Determine Unit ID (Use Unit if available, else derive from Community)
                            String? unitId = governanceUnit?.id;
                            
                            if (unitId == null && community != null) {
                              if (community.type == 'global') {
                                unitId = 'global';
                              } else if (community.type == 'continent') {
                                // Standardize to continent_name_with_underscores
                                final continentName = community.name.replaceAll(' Community', '').toLowerCase().replaceAll(' ', '_');
                                unitId = 'continent_$continentName';
                              } else if (community.type == 'country') {
                                // Standardize to country_iso (e.g. country_tz)
                                final countryCode = community.homeCountryCode?.toLowerCase() ?? 
                                                 (community.location?['countryCode']?.toString().toLowerCase()) ??
                                                 (community.name.replaceAll(' Community', '').toLowerCase());
                                unitId = 'country_$countryCode';
                              } else {
                                // Fallback for local/other
                                unitId = chat.communityId;
                              }
                            }
                            
                            if (unitId != null) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => LeaderSelectionScreen(
                                    unitId: unitId!,
                                    community: community,
                                  ),
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Governance not initialized for this community.'),
                                ),
                              );
                            }
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // [NEW] DSP Transfer Logic
  Future<void> _sendDSP(int amount, String? caption) async {
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
      await ref
          .read(pointsServiceProvider)
          .transferPoints(
            fromUserId: currentUserId,
            toUserId: toUserId,
            amount: amount,
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
                : 'Sent $amount DSP', // Use caption if available
            type: 'dsp_transfer',
            senderIdOverride: identity?['id'],
            senderNameOverride:
                identity?['businessName'] ?? identity?['name'],
            senderImageOverride: identity?['profileImage'],
            metadata: {'amount': amount, 'currency': 'DSP'},
            participants: participants,
            // We should also set push notification payload if needed here via metadata or server function?
            // Cloud function triggers on message create usually handles push.
            // We will ensure push_notification_service handles this type locally or via FCM.
          );
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      debugPrint('DSP_TRANSFER: Error transferring DSP: $e');
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Chat?'),
        content: Text(
          'Are you sure you want to clear your chat history with $name? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            onPressed: () async {
              Navigator.pop(context);
              await repo.clearChat(chatId);
              // Stay in chat, messages will clear (handled by stream filtering ideally, or just UI clear)
            },
            child: const Text('Clear'),
          ),
        ],
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titleOverride ?? (isLeave ? 'Leave Group?' : 'Delete Chat?')),
        content: Text(
          isLeave
              ? 'Are you sure you want to leave $name?'
              : (titleOverride == 'Unfollow Organization?') // [UPDATED] 
                  ? 'Are you sure you want to unfollow $name?' 
                  : 'Are you sure you want to delete your chat with $name? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              if (isLeave) {
                await repo.leaveChat(chatId);
              } else {
                await repo.deleteChat(chatId);
              }
              if (context.mounted) {
                // Pop until home or chats list
                Navigator.of(context).pop();
              }
            },
            child: Text(isLeave ? 'Leave' : 'Delete'),
          ),
        ],
      ),
    );
  }

  void _handleMessageAction(BuildContext context, Message message, WidgetRef ref) {
    if (message.isDeletedForEveryone) return;
    
    final currentUserId = ref.read(chatRepositoryProvider).currentUserId;
    final isOwn = message.senderId == currentUserId;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // [NEW] Reaction Bar
              SizedBox(
                height: 60,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: ['❤️', '😂', '👍', '👎', '😮', '😢', '🙏'].map((emoji) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          _handleReaction(message, emoji);
                        },
                        child: Text(emoji, style: const TextStyle(fontSize: 32)),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const Divider(),

              // [NEW] Restored Actions
              ListTile(
                leading: const Icon(LucideIcons.reply),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.pop(context);
                  _setReplyTo(message);
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.forward),
                title: const Text('Forward'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ForwardChatSelectionScreen(message: message),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.copy),
                title: const Text('Copy'),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(ClipboardData(text: message.content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Message copied')),
                  );
                },
              ),
              // Delete only for own messages
              if (isOwn)
                ListTile(
                  leading: const Icon(LucideIcons.trash2, color: AppTheme.error),
                  title: const Text('Delete', style: TextStyle(color: AppTheme.error)),
                  onTap: () {
                    Navigator.pop(context);
                    _handleDeleteMessage(message);
                  },
                ),
              
              ListTile(
                leading: const Icon(LucideIcons.share2),
                title: const Text('Share'),
                onTap: () {
                  Navigator.pop(context);
                  Share.share(message.content); // SharePlus.instance.share is preferred but Share.share is also from share_plus
                },
              ),

              // Report only for others' messages
              if (!isOwn)
                ListTile(
                  leading: const Icon(LucideIcons.flag, color: AppTheme.error),
                  title: const Text('Report Message', style: TextStyle(color: AppTheme.error)),
                  onTap: () {
                    Navigator.pop(context);
                    _showReportDialog(context, ref, message);
                  },
                ),
            ],
          ),
        ),
      ),
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
       ref.read(chatRepositoryProvider).removeReaction(message.chatId, message.id, emoji);
    } else {
       ref.read(chatRepositoryProvider).addReaction(
         message.chatId, 
         message.id, 
         emoji,
         message.senderId,
       );
    }
  }

  // [NEW] Handle Delete
  void _handleDeleteMessage(Message message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text('Are you sure you want to delete this message? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(chatRepositoryProvider).deleteMessage(message.chatId, message.id);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showReportDialog(BuildContext context, WidgetRef ref, Message message) {
    final reasons = [
      'Spam or Scam',
      'Hate Speech',
      'Harassment or Bullying',
      'Nudity or Sexual Activity',
      'False Information',
      'Other',
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report Message'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: reasons.length,
            itemBuilder: (context, index) {
              return ListTile(
                title: Text(reasons[index]),
                onTap: () async {
                  Navigator.pop(context); // Close dialog
                  
                  // Show loading
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Submitting report...')),
                  );

                  try {
                    final currentUserId = ref.read(authRepositoryProvider).currentUser?.uid;
                    if (currentUserId == null) return;

                    final success = await ref.read(reportRepositoryProvider).reportMessage(
                      reporterId: currentUserId,
                      messageId: message.id,
                      senderId: message.senderId,
                      reason: reasons[index],
                    );

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(success 
                            ? 'Report submitted. Thank you for helping keep our community safe.' 
                            : 'Failed to submit report. Please try again.'),
                          backgroundColor: success ? Colors.green : AppTheme.error,
                        ),
                      );
                    }
                  } catch (e) {
                    debugPrint('Error reporting: $e');
                  }
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildSheetItem(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBgColor,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: isDestructive
                          ? Colors.red
                          : theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRelationshipPicker(
    BuildContext context,
    WidgetRef ref,
    String? otherUserId,
    String otherUserName,
  ) {
    if (otherUserId == null || otherUserId.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => RelationshipSelectionModal(
        otherUserId: otherUserId,
        otherUserName: otherUserName,
      ),
    );
  }
}

// End of file or removed classes
