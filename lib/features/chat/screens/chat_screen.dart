import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart' as io;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:diaspora_nearby/models/message.dart';
import 'package:diaspora_nearby/models/chat.dart';
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/chat/utils/community_chat_utils.dart'; // [NEW] Parity utils
import 'package:diaspora_nearby/features/chat/widgets/message_bubble.dart';
import 'package:diaspora_nearby/features/chat/widgets/message_input.dart';
import 'package:diaspora_nearby/features/chat/widgets/chat_header_title.dart';
import 'package:diaspora_nearby/features/chat/screens/create_group_screen.dart';
import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/models/profile_data.dart'; // [FIXED]
import 'package:diaspora_nearby/features/community/repository/community_repository.dart';
import 'package:diaspora_nearby/models/community_data.dart';
import 'package:diaspora_nearby/features/events/repository/event_repository.dart'; 
import 'package:diaspora_nearby/models/event_data.dart';
import 'package:diaspora_nearby/features/chat/repository/report_repository.dart'; // [NEW]
import 'package:diaspora_nearby/models/event_data.dart';
import 'package:diaspora_nearby/services/chat_scroll_position_service.dart';
import 'package:diaspora_nearby/features/chat/widgets/chat_identity_selector.dart'; // [NEW]
import 'package:diaspora_nearby/features/chat/providers/chat_identity_provider.dart'; // [NEW]
import 'package:diaspora_nearby/features/chat/providers/pending_message_provider.dart';


final communityDetailsProvider = FutureProvider.family<Community?, String>((ref, communityId) {
  return ref.read(communityRepositoryProvider).getCommunity(communityId);
});



/// Provider for messages stream
final messagesStreamProvider =
    StreamProvider.family<List<Message>, String>((ref, chatId) {
  final chatRepo = ref.watch(chatRepositoryProvider);
  final userProfileAsync = ref.watch(userProfileProvider);
  
  return chatRepo.subscribeToMessages(chatId).map((messages) {
    // Filter blocked users
    final blocked = userProfileAsync.value?.blockedUsers ?? [];
    if (blocked.isEmpty) return messages;
    
    return messages.where((m) => !blocked.contains(m.senderId)).toList();
  });
});

/// Provider for single chat
final chatProvider = FutureProvider.family<Chat?, String>((ref, chatId) async {
  final chatRepo = ref.watch(chatRepositoryProvider);
  return chatRepo.getChat(chatId);
});

/// Provider for chat display name (fetches correct name for DM chats)
final chatDisplayNameProvider = FutureProvider.family<String, String>((ref, chatId) async {
  final chatRepo = ref.watch(chatRepositoryProvider);
  final chat = await chatRepo.getChat(chatId);
  if (chat == null) return 'Chat';
  return chatRepo.getDisplayNameForChat(chat);
});

/// Provider for other user's profile in direct chats (Local to ChatScreen)
final chatScreenUserProfileProvider = FutureProvider.family<ProfileData?, Chat>((ref, chat) async {
  if (!chat.isDirect) return null;
  
  // Get the other participant's ID
  final currentUserId = ref.watch(authStateProvider).value?.uid;
  if (currentUserId == null) return null;
  
  final otherUserId = chat.participants.firstWhere(
    (id) => id != currentUserId,
    orElse: () => '',
  );
  
  if (otherUserId.isEmpty) return null;
  
  final profileRepo = ref.watch(profileRepositoryProvider);
  return profileRepo.getUserProfile(otherUserId);
});

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
  const ChatScreen({
    super.key,
    required this.chatId,
  })  : pendingUserId = null,
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
  bool _isNearBottom = true;
  bool _scrollPositionRestored = false;
  
  /// The actual chatId (either from props or created after first message)
  String? _activeChatId;
  
  /// Message being replied to (null if not replying)
  Message? _replyingTo;
  
  /// Tracks message IDs that have become visible and need to be marked as read
  final Set<String> _visibleUnreadMessageIds = {};
  
  /// Debounce timer for batching read receipt updates
  Timer? _readReceiptDebounceTimer;
  
  /// Whether this is a pending DM that hasn't been created yet
  bool get _isPendingDM => widget.chatId == null && widget.pendingUserId != null;

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
    
    // Mark as read when entering (only for existing chats)
    if (_activeChatId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _markAsRead();
        _restoreScrollPosition();
      });
    }
  }

  /// Restore scroll position from persistence
  void _restoreScrollPosition() {
    if (_activeChatId == null || _scrollPositionRestored) return;
    _scrollPositionRestored = true;
    
    final scrollService = ref.read(chatScrollPositionServiceProvider);
    final savedOffset = scrollService.getPosition(_activeChatId!);
    
    if (savedOffset != null && _scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          final maxExtent = _scrollController.position.maxScrollExtent;
          // Only restore if saved position is valid
          if (savedOffset <= maxExtent) {
            _scrollController.jumpTo(savedOffset);
            debugPrint('📍 Restored scroll position: $savedOffset');
          }
        }
      });
    }
  }

  /// Save scroll position before leaving
  void _saveScrollPosition() {
    if (_activeChatId == null || !_scrollController.hasClients) return;
    
    final scrollService = ref.read(chatScrollPositionServiceProvider);
    final offset = _scrollController.offset;
    scrollService.savePosition(_activeChatId!, offset);
    debugPrint('💾 Saved scroll position: $offset');
  }

  @override
  void dispose() {
    _saveScrollPosition(); // Save before leaving
    _readReceiptDebounceTimer?.cancel(); // Cancel pending read receipt updates
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final isNearBottom = _scrollController.position.pixels >=
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

  Future<void> _markAsRead() async {
    if (_activeChatId == null) return;
    final chatRepo = ref.read(chatRepositoryProvider);
    await chatRepo.markChatAsRead(_activeChatId!);
  }

  /// Handle message visibility change for scroll-based read receipts
  /// Only marks messages as read when they become visible (>50% visible)
  void _onMessageVisibilityChanged(VisibilityInfo info, Message message, String currentUserId) {
    // Only track messages from other users that aren't already read
    if (message.senderId == currentUserId) return;
    if (message.status == 'read') return;
    
    final isVisible = info.visibleFraction > 0.5;
    
    if (isVisible) {
      // Add to visible set
      if (_visibleUnreadMessageIds.add(message.id)) {
        // Schedule debounced update
        _scheduleReadReceiptUpdate();
      }
    }
  }

  /// Schedule a debounced update to mark visible messages as read
  void _scheduleReadReceiptUpdate() {
    _readReceiptDebounceTimer?.cancel();
    _readReceiptDebounceTimer = Timer(const Duration(milliseconds: 500), () async {
      if (_visibleUnreadMessageIds.isNotEmpty && _activeChatId != null) {
        debugPrint('👁️ Marking ${_visibleUnreadMessageIds.length} visible messages as read');
        
        final chatRepo = ref.read(chatRepositoryProvider);
        final idsToMark = List<String>.from(_visibleUnreadMessageIds);
        _visibleUnreadMessageIds.clear();

        // 1. Mark overall chat as read
        _markAsRead();

        // 2. Mark individual messages as read in database
        for (final messageId in idsToMark) {
          await chatRepo.markMessageAsRead(_activeChatId!, messageId);
        }
      }
    });
  }

  /// Set message to reply to
  void _setReplyTo(Message message) {
    setState(() => _replyingTo = message);
  }

  /// Clear reply
  void _clearReply() {
    setState(() => _replyingTo = null);
  }

  Future<void> _sendMessage(String text, {String? type, Map<String, dynamic>? metadata}) async {
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
        debugPrint('â Failed to create chat with user ${widget.pendingUserId}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Failed to start chat. User might not exist or network error.'),
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
         
         ref.read(pendingMessagesProvider.notifier).addMessage(_activeChatId!, optimisticMessage);
         
         try {
             await chatRepo.sendTextMessage(
              _activeChatId!, 
              text,
              replyToMessageId: replyToId,
              senderIdOverride: senderIdOverride,
              senderNameOverride: senderNameOverride,
              senderImageOverride: senderImageOverride,
              participants: participants, 
            );
         } catch (e) {
            debugPrint('Error sending message: $e');
            // Optionally mark as failed instead of removing?
            // For now, removing to avoid stuck 'sending' state if logic doesn't handle failures well
            // or we could update status to 'failed'
         } finally {
            ref.read(pendingMessagesProvider.notifier).removeMessage(_activeChatId!, tempId);
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Starting conversation...')),
      );
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
            content: const Text('Failed to start chat. User might not exist or network error.'),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return null;
    }
  }

  Future<void> _sendMedia(List<File> files, String type, String? caption) async {
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
           
           ref.read(pendingMessagesProvider.notifier).addMessage(chatId, optimisticMessage);
        }

       try {
         if (type == 'video') {
          await chatRepo.sendVideoMessage(
            chatId,
            file.path,
            caption: caption, // No caption support in multi-upload yet
            replyToMessageId: replyToId,
            senderIdOverride: identity?['id'],
            senderNameOverride: identity?['name'],
            senderImageOverride: identity?['profileImage'],
            participants: participants, // [NEW]
          );
        } else {
          await chatRepo.sendImageMessage(
            chatId,
            file.path,
            caption: caption,
            replyToMessageId: replyToId,
            senderIdOverride: identity?['id'],
            senderNameOverride: identity?['name'],
            senderImageOverride: identity?['profileImage'],
            participants: participants, // [NEW]
          );
        }
      } catch (e) {
         debugPrint('Error sending media: $e');
      } finally {
         if (currentUserId != null) {
            ref.read(pendingMessagesProvider.notifier).removeMessage(chatId, tempId);
         }
      }
    }

    // Scroll to bottom after sending
    Future.delayed(const Duration(milliseconds: 300), () => _scrollToBottom());
    Future.delayed(const Duration(milliseconds: 600), () => _scrollToBottom());
  }

  Future<void> _sendLocation() async {
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
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission permanently denied. Enable in settings.')),
        );
      }
      return;
    }

    final chatId = await _ensureChatCreated();
    if (chatId == null) return;

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                 const CircularProgressIndicator(),
                 const SizedBox(height: 16),
                 const Text('Getting accurate location...'),
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
               content: Text('Location services are disabled. Please enable them.'),
               action: SnackBarAction(label: 'SETTINGS', onPressed: Geolocator.openLocationSettings),
             ),
           );
        }
        return;
      }

      // Get current position with timeout
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).timeout(const Duration(seconds: 10));

      if (Navigator.canPop(context)) Navigator.pop(context); // Close loader

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
        debugPrint('â ï¸ Reverse geocoding failed: $e');
      }

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
             location: MessageLocation(
               lat: position.latitude,
               lng: position.longitude,
               address: address ?? '',
             ),
           ); // Removed the ..address cascade as it's not a field on Message and address is passed to MessageLocation
           
           ref.read(pendingMessagesProvider.notifier).addMessage(chatId, optimisticMessage);
      }
      
      try {
        await chatRepo.sendLocationMessage(
          chatId,
          latitude: position.latitude,
          longitude: position.longitude,
          address: address,
          replyToMessageId: replyToId,
          senderIdOverride: identity?['id'],
          senderNameOverride: identity?['name'],
          senderImageOverride: identity?['profileImage'],
          participants: participants, // [NEW]
        );
      } catch (e) {
         debugPrint('Error sending location: $e');
      } finally {
         if (currentUserId != null) {
           ref.read(pendingMessagesProvider.notifier).removeMessage(chatId, tempId);
         }
      }

      // Scroll to bottom after sending
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollToBottom();
      });
    } on TimeoutException catch (_) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get location. Signal is weak.')),
        );
      }
    } catch (e) {
      debugPrint('â Œ Error sending location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to get location')),
        );
      }
    }
  }

  Future<void> _sendAudioFile(File file, String? caption) async {
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
         
         ref.read(pendingMessagesProvider.notifier).addMessage(chatId, optimisticMessage);
    }

    try {
      await chatRepo.sendAudioFileMessage(
        chatId,
        file.path,
        caption: caption,
        replyToMessageId: replyToId,
        senderIdOverride: identity?['id'],
        senderNameOverride: identity?['name'],
        senderImageOverride: identity?['profileImage'],
        participants: participants, // [NEW]
      );
    } catch (e) {
       debugPrint('Error sending audio file: $e');
    } finally {
       if (currentUserId != null) {
          ref.read(pendingMessagesProvider.notifier).removeMessage(chatId, tempId);
       }
    }

    // Scroll to bottom after sending
    Future.delayed(const Duration(milliseconds: 300), () => _scrollToBottom());
    Future.delayed(const Duration(milliseconds: 600), () => _scrollToBottom());
  }

  Future<void> _sendAudio(File file, int duration, {String? caption}) async {
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
         
         ref.read(pendingMessagesProvider.notifier).addMessage(chatId, optimisticMessage);
    }

    try {
      await chatRepo.sendAudioMessage(
        chatId,
        file.path,
        durationSeconds: duration,
        caption: caption,
        replyToMessageId: replyToId,
        senderIdOverride: identity?['id'],
        senderNameOverride: identity?['name'],
        senderImageOverride: identity?['profileImage'],
        participants: participants, // [NEW]
      );
    } catch (e) {
       debugPrint('Error sending audio: $e');
    } finally {
       if (currentUserId != null) {
         ref.read(pendingMessagesProvider.notifier).removeMessage(chatId, tempId);
       }
    }

    // Scroll to bottom after sending
    Future.delayed(const Duration(milliseconds: 300), () => _scrollToBottom());
    Future.delayed(const Duration(milliseconds: 600), () => _scrollToBottom());
  }

  Future<void> _sendDocument(File file, String? caption) async {
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
         
         ref.read(pendingMessagesProvider.notifier).addMessage(chatId, optimisticMessage);
    }

    try {
      await chatRepo.sendDocumentMessage(
        chatId,
        file.path,
        caption: caption,
        replyToMessageId: replyToId,
        senderIdOverride: identity?['id'],
        senderNameOverride: identity?['name'],
        senderImageOverride: identity?['profileImage'],
        participants: participants, // [NEW]
      );
    } catch (e) {
       debugPrint('Error sending document: $e');
    } finally {
       if (currentUserId != null) {
          ref.read(pendingMessagesProvider.notifier).removeMessage(chatId, tempId);
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
          onPressed: () => context.canPop() ? context.pop() : context.go('/chats'),
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
              participantIds: widget.pendingUserId != null ? [widget.pendingUserId!] : [],
              onSendMessage: _sendMessage,
              onSendMedia: _sendMedia,
              onSendAudio: _sendAudio,
              onSendAudioFile: _sendAudioFile,
              onSendDocument: _sendDocument,
              onSendLocation: _sendLocation,
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
        shadowColor: theme.colorScheme.shadow.withOpacity(0.1),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () => context.canPop() ? context.pop() : context.go('/chats'),
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
              final profileAsync = ref.watch(chatScreenUserProfileProvider(chat));
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
                  final communityAsync = ref.watch(communityDetailsProvider(chat!.communityId!));
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
                   final eventAsync = ref.watch(eventDetailsProvider(chat!.eventId!));
                   event = eventAsync.value;
                   
                   if (event != null) {
                     // Calculate Status
                     final now = DateTime.now();
                     final start = DateTime.tryParse(event.startDate) ?? DateTime.now();
                     final diff = start.difference(now);
                     
                     if (diff.isNegative) {
                        // Already started
                        if (diff.inHours.abs() < 24) {
                           eventStatus = 'Happening now'; // simplified
                        } else {
                           eventStatus = 'Ended';
                        }
                     } else {
                        // Future
                        if (diff.inHours < 24) {
                           eventStatus = 'in ${diff.inHours} hours';
                        } else {
                           eventStatus = 'in ${diff.inDays} days';
                        }
                     }
                   }
                }
                
                // [UPDATED] Show live member count for all community types
                final showMemberInfo = (chat?.type == 'community' || chat?.type == 'group');

                return ChatHeaderTitle(
                  profile: null,
                  // [FIX] Use consistent community naming logic with live community data preference
                  fallbackTitle: (chat?.type == 'community') 
                      ? CommunityChatUtils.generateCommunityNameFromParts(
                          name: community?.name ?? chat!.name,
                          locationType: community?.locationType ?? chat?.locationType ?? 'home',
                          id: chat?.id ?? ''
                        )
                      : displayName,
                  imageUrl: (chat?.isEvent == true) ? (event?.imageUrl ?? chat?.photoUrl) : chat?.photoUrl,
                  // Prioritize pre-rendered widget from utils
                  customAvatarWidget: communityAvatar,
                  // Legacy fallback
                  customImage: null, // [FIXED] Type mismatch, handled by customAvatarWidget above
                  // Show count if available
                  memberCount: showMemberInfo 
                      ? (community?.totalMembers ?? 
                         ((chat?.type == 'group') ? chat?.participants.length : chat?.memberCount))
                      : null,
                  // [NEW] Event Status
                  eventStatus: eventStatus,
                   onTap: () async {
                    if (chat?.type == 'group' || chat?.type == 'organization') {
                       context.push('/chats/${chat!.id}/info', extra: {
                          'name': chat?.name,
                          'image': chat?.photoUrl,
                          'type': chat?.type,
                       });
                    } else if (chat?.type == 'direct') {
                      // Original profile view logic
                      final otherId = chat?.participants.firstWhere((id) => id != ref.read(authRepositoryProvider).currentUser?.uid, orElse: () => '');
                      if (otherId != null && otherId.isNotEmpty) {
                         context.push('/profile/$otherId');
                      }
                   } else if (chat?.type == 'community' && community != null) {
                      context.push(
                        '/communities/${community!.id}/members',
                        extra: community,
                      );
                   } else if (chat?.isEvent == true && chat?.eventId != null) {
                      // [NEW] Go to Event Details
                      context.push('/events/${chat!.eventId}?fromChat=true');
                   }
                  },
              );
            });
          },
        ),
        actions: [
          // WhatsApp Call Button
          if (chatAsync.value?.isDirect == true)
            ref.watch(chatScreenUserProfileProvider(chatAsync.value!)).when(
              data: (profile) {
                if (profile?.phone != null && profile!.phone.isNotEmpty) {
                  return IconButton(
                    icon: const Icon(LucideIcons.phone, color: Colors.green),
                    tooltip: 'Call on WhatsApp',
                    onPressed: () async {
                      final phone = profile.phone;
                      // Keep + for app scheme
                      final appPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
                      // Remove everything including + for web scheme
                      final webPhone = phone.replaceAll(RegExp(r'\D'), '');
                      
                      final appUrl = Uri.parse('whatsapp://send?phone=$appPhone');
                      final webUrl = Uri.parse('https://wa.me/$webPhone');
                      
                      try {
                        // Try app first
                        bool launched = false;
                        if (await canLaunchUrl(appUrl)) {
                           launched = await launchUrl(appUrl, mode: LaunchMode.externalApplication);
                        }
                        
                        // Fallback to web if app fail
                        if (!launched) {
                           if (await canLaunchUrl(webUrl)) {
                             await launchUrl(webUrl, mode: LaunchMode.externalApplication);
                           } else {
                             throw 'Could not launch WhatsApp';
                           }
                        }
                      } catch (e) {
                        debugPrint('WhatsApp Launch Error: $e');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Could not launch WhatsApp')),
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
          IconButton(
            icon: const Icon(LucideIcons.moreVertical),
            onPressed: () {
              final chat = chatAsync.value;
              if (chat != null) {
                _showMoreMenu(context, chat, ref);
              }
            },
          ),
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
                      onPressed: () => ref.invalidate(messagesStreamProvider(_activeChatId!)),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (streamMessages) {
                // [NEW] Merge with pending messages
                final pendingMessages = ref.watch(pendingMessagesProvider)[_activeChatId!] ?? [];
                
                // Merge strategies:
                // Sort everything by timestamp DESC.
                final allMessages = [...pendingMessages, ...streamMessages];
                allMessages.sort((a, b) => b.timestamp.compareTo(a.timestamp));

                if (allMessages.isEmpty) {
                   return _buildEmptyState(theme);
                }

                // Initial scroll is bottom (offset 0) by default in reverse mode.

                return ListView.builder(
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
                            message.timestamp
                         );
                       }
                    }

                    // For Reply logic: find message in full list
                     Message? repliedMessage;
                     if (message.replyTo != null) {
                        repliedMessage = allMessages.firstWhere(
                          (m) => m.id == message.replyTo,
                          orElse: () => Message(
                             id: '', chatId: '', senderId: '', senderName: 'Unknown',
                             content: 'Message not found', type: 'text', timestamp: 0,
                          ),
                        );
                        if (repliedMessage?.id.isEmpty ?? true) repliedMessage = null;
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
                           onVisibilityChanged: (info) => _onMessageVisibilityChanged(info, message, currentUserId),
                           child: MessageBubble(
                             key: _messageKeys.putIfAbsent(message.id, () => GlobalKey()),
                             message: message,
                             isOwn: isOwn,
                             showAvatar: chatAsync.value?.type != 'direct',
                             onReply: () => _setReplyTo(message),
                             onReplyTap: _scrollToMessage,
                             onLongPress: () => _showMessageContextMenu(context, message, currentUserId),
                             onRetry: message.status == 'error' ? () => _retryMessage(message) : null,
                             repliedMessage: repliedMessage,
                             isHighlighted: message.id == _highlightedMessageId,
                           ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          // Scroll to bottom button
          if (!_isNearBottom)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FloatingActionButton.small(
                onPressed: () => _scrollToBottom(),
                child: const Icon(LucideIcons.chevronDown),
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    _buildTypingDots(theme),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Consumer(
                        builder: (context, ref, child) {
                          if (typingUsers.length == 1) {
                            final profileAsync = ref.watch(userProfileByIdProvider(typingUsers.first));
                            return profileAsync.when(
                              data: (profile) => Text(
                                '${profile?.firstName ?? 'Someone'} is typing...',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              loading: () => Text('Someone is typing...', style: theme.textTheme.bodySmall),
                              error: (_, __) => Text('Someone is typing...', style: theme.textTheme.bodySmall),
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
              var isParticipant = chat?.participants.contains(currentUserId) ?? false;

              // [FIX] For Event Chats, also check Firestore Event Attendees (Source of Truth)
              if (chat?.isEvent == true && chat?.eventId != null && !isParticipant) {
                  // We need to check the event data. 
                  // Note: We can't easily ref.watch here dynamically without potentially rebuilding 
                  // the whole scaffold if we didn't plan for it. 
                  // However, we are inside a Consumer (State object) build method, so we CAN watch.
                  final eventAsync = ref.watch(eventDetailsProvider(chat!.eventId!));
                  final event = eventAsync.value;
                  if (event != null) {
                      final isCreator = event.creatorId == currentUserId;
                      final isAttendee = event.attendees?.contains(currentUserId) ?? false;
                      if (isCreator || isAttendee) {
                          isParticipant = true;
                      }
                  }
              }
              
              // Only allow messaging if participant OR it's a direct chat (where they are implied participants)
              if (chat != null && !isParticipant && chat.type != 'direct') {
                return SafeArea(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      border: Border(top: BorderSide(color: theme.dividerColor)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.lock, size: 20, color: theme.colorScheme.secondary),
                        const SizedBox(height: 8),
                        Text(
                          chat.isOrganization || chat.type == 'community'
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
                  chatId: _activeChatId!,
                  participantIds: chat?.participants.where((id) => id != currentUserId).toList() ?? [],
                  onSendMessage: _sendMessage,
                  onSendMedia: _sendMedia,
                  onSendAudio: _sendAudio,
                  onSendAudioFile: _sendAudioFile,
                  onSendDocument: _sendDocument,
                  onSendLocation: _sendLocation,
                  replyingTo: _replyingTo,
                  onCancelReply: _clearReply,
                ),
              );
            }
          ),
        ],
      ),
    );
  }

  /// Show context menu for message interactions
  void _showMessageContextMenu(BuildContext context, Message message, String currentUserId) {
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
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              
              // Reaction Row
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: ['❤️', '😂', '👍', '👎', '😮', '😢', '🙏', '🔥'].map((emoji) {
                    final isSelected = message.reactions?.any((r) => 
                        r.emoji == emoji && r.userIds.contains(currentUserId)) ?? false;
                        
                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        if (isSelected) {
                          chatRepo.removeReaction(message.chatId, message.id, emoji);
                        } else {
                          chatRepo.addReaction(message.chatId, message.id, emoji);
                        }
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 12),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSelected 
                              ? theme.colorScheme.primaryContainer 
                              : theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 24),
                        ),
                      ),
                    );
                  }).toList(),
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
                   final selectedChatIds = await context.push<List<String>>('/chats/forward_selection');
                   if (selectedChatIds != null && selectedChatIds.isNotEmpty) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                           const SnackBar(
                             content: Text('Forwarding message...'),
                             duration: Duration(seconds: 1), // Short duration as it updates quickly usually
                           ),
                        );
                      }
                      
                      final identity = ref.read(chatIdentityProvider);
                      await chatRepo.forwardMessage(
                        message, 
                        selectedChatIds,
                        senderIdOverride: identity?['id'],
                        senderNameOverride: identity?['businessName'] ?? identity?['name'],
                        senderImageOverride: identity?['profileImage'],
                      );
                      
                      if (mounted) {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar(); // Hide "sending"
                        ScaffoldMessenger.of(context).showSnackBar(
                           SnackBar(
                             content: Text('Forwarded to ${selectedChatIds.length} chat${selectedChatIds.length > 1 ? 's' : ''}'),
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
                  await io.Clipboard.setData(io.ClipboardData(text: message.content));
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
                  leading: Icon(LucideIcons.trash2, color: theme.colorScheme.error),
                  title: Text('Delete', style: TextStyle(color: theme.colorScheme.error)),
                  onTap: () {
                    Navigator.pop(context);
                    _showDeleteMessageConfirmation(context, message, chatRepo);
                  },
                ),
              
              if (!isOwn)
                ListTile(
                  leading: const Icon(LucideIcons.flag, color: Colors.orange),
                  title: const Text('Report', style: TextStyle(color: Colors.orange)),
                  onTap: () {
                     Navigator.pop(context);
                     // Show Report Dialog
                     showDialog(
                       context: context,
                       builder: (c) {
                          // Simple dialog for now, can be expanded to select reason
                          return AlertDialog(
                             title: const Text('Report Message'),
                             content: const Text('Flag this message as containing unsolicited ads or spam?'),
                             actions: [
                               TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
                               TextButton(
                                 onPressed: () async {
                                    Navigator.pop(c);
                                    final currentUserId = ref.read(chatRepositoryProvider).currentUserId;
                                    if (currentUserId != null) {
                                    await ref.read(reportRepositoryProvider).reportMessage(
                                          reporterId: currentUserId,
                                          messageId: message.id,
                                          senderId: message.senderId,
                                          reason: 'ad',
                                       );
                                       if (context.mounted) {
                                         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message reported. Thank you.')));
                                       }
                                    }
                                 }, 
                                 child: const Text('Report', style: TextStyle(color: Colors.red))
                               ),
                             ],
                          );
                       },
                     );
                  },
                ),
                
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }


  void _showDeleteMessageConfirmation(BuildContext context, Message message, ChatRepository chatRepo) {
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
              chatRepo.deleteMessage(message.chatId, message.id, deleteForEveryone: false);
            },
            child: const Text('Delete for Me'),
          ),
          TextButton(
             onPressed: () {
              Navigator.pop(context);
              chatRepo.deleteMessage(message.chatId, message.id, deleteForEveryone: true);
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
      case 1: return 'Monday';
      case 2: return 'Tuesday';
      case 3: return 'Wednesday';
      case 4: return 'Thursday';
      case 5: return 'Friday';
      case 6: return 'Saturday';
      case 7: return 'Sunday';
      default: return '';
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

  Future<void> _showMoreMenu(BuildContext context, Chat chat, WidgetRef ref) async {
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

    if (!context.mounted) return;

    // Use showDialog with column/spacer to position at top
    showDialog(
      context: context,
      barrierColor: Colors.black12, // Subtle barrier
      builder: (context) {
        return Stack(
          children: [
            Positioned(
              top: kToolbarHeight + MediaQuery.of(context).padding.top, // Below AppBar 0px
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
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                          }
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
                             final otherId = chat.getOtherParticipantId(repo.currentUserId ?? '');
                             Navigator.of(context).push(
                               MaterialPageRoute(
                                 fullscreenDialog: true,
                                 builder: (context) => CreateGroupScreen(
                                   initialParticipantId: otherId,
                                 ),
                               ),
                             );
                          }
                        ),

                      // Profile/Group Info
                      if (!isCommunity && !isEvent)
                        _buildSheetItem(
                          context,
                          icon: LucideIcons.settings,
                          iconColor: Colors.grey.shade700,
                          iconBgColor: Colors.grey.shade100,
                          title: isGroup ? 'Group info' : 'View profile',
                          subtitle: isGroup ? 'Manage group settings' : 'View profile details',
                          onTap: () {
                            Navigator.pop(context);
                            if (isDirect) {
                               final otherId = chat.getOtherParticipantId(repo.currentUserId ?? '');
                               if (otherId != null && otherId.isNotEmpty) {
                                 context.push('/profile/$otherId');
                               }
                            } else {
                               context.push('/chats/${chat.id}/info', extra: {
                                  'name': chat.name,
                                  'image': chat.photoUrl,
                                  'type': chat.type,
                               });
                            }
                          }
                        ),
                        
                       // Pin (Toggle)
                       _buildSheetItem(
                          context,
                          icon: LucideIcons.pin,
                          iconColor: Colors.blue.shade700,
                          iconBgColor: Colors.blue.shade50,
                          title: chat.isPinned ? 'Unpin' : 'Pin to top',
                          subtitle: chat.isPinned ? 'Remove from top' : 'Keep this chat at the top',
                          onTap: () async {
                            Navigator.pop(context);
                            await repo.togglePin(chat.id, !chat.isPinned);
                          }
                        ),

                      // Mute
                       _buildSheetItem(
                          context,
                          icon: LucideIcons.bell,
                          iconColor: Colors.purple.shade700,
                          iconBgColor: Colors.purple.shade50,
                          title: chat.isMuted ? 'Unmute' : 'Mute',
                          subtitle: chat.isMuted ? 'Enable notifications' : 'Stop receiving notifications',
                          onTap: () async {
                            Navigator.pop(context);
                            await repo.toggleMute(chat.id, !chat.isMuted);
                          }
                        ),

                      // Delete / Leave / Clear
                      // Clear Chat (All types except maybe community if huge, but we allow it)
                      // Enable Clear Chat for ALL chat types
                        _buildSheetItem(
                          context,
                          icon: LucideIcons.eraser,
                          iconColor: Colors.orange.shade700,
                          iconBgColor: Colors.orange.shade50,
                          title: 'Clear chat',
                          subtitle: 'Clear messages for me',
                          onTap: () async {
                             Navigator.pop(context);
                             _showClearConfirmation(context, repo, chat.id, nameToUse);
                          },
                        ),

                      // Delete / Leave Chat (All types except community)
                      if (!isCommunity)
                        _buildSheetItem(
                          context,
                          icon: (isGroup || isEvent) ? LucideIcons.logOut : LucideIcons.trash2,
                          iconColor: Colors.red.shade700,
                          iconBgColor: Colors.red.shade50,
                          title: isGroup 
                              ? 'Leave group' 
                              : isEvent 
                                  ? 'Leave event' 
                                  : 'Delete chat',
                          subtitle: (isGroup || isEvent) ? 'Remove from your list' : 'Delete from your list',
                          isDestructive: true,
                          onTap: () async {
                            Navigator.pop(context);
                            // Unified delete/leave confirmation
                            _showDeleteConfirmation(
                              context, 
                              repo, 
                              chat.id, 
                              nameToUse,
                              isLeave: isGroup || isEvent,
                            );
                          }
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

  void _showClearConfirmation(BuildContext context, ChatRepository repo, String chatId, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Chat?'),
        content: Text('Are you sure you want to clear your chat history with $name? This cannot be undone.'),
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

  void _showDeleteConfirmation(BuildContext context, ChatRepository repo, String chatId, String name, {bool isLeave = false}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isLeave ? 'Leave Group?' : 'Delete Chat?'),
        content: Text(isLeave 
          ? 'Are you sure you want to leave $name?'
          : 'Are you sure you want to delete your chat with $name? This action cannot be undone.'),
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
                      color: isDestructive ? Colors.red : theme.colorScheme.onSurface,
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
             // No chevron for popup style usually, but requested parity with previous which had it? 
             // Previous iteration had chevron. I'll keep it or remove based on UX. 
             // "Menu" usually doesn't have chevrons unless it navigates deep. 
             // But let's keep consistent with "modal" feel.
          ],
        ),
      ),
    );
  }
}
