import 'dart:async';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:diaspora_nearby/features/chat/models/message.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
// Alias to avoid conflict with record
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';
import 'package:diaspora_nearby/features/chat/widgets/audio_message_player.dart';
import 'package:diaspora_nearby/features/dsp/repository/points_repository.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';

import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart';
import 'package:diaspora_nearby/features/profile/models/profile_data.dart'; // [New]
import 'package:diaspora_nearby/features/dsp/models/user_points.dart'; // [New]

class MessageInput extends ConsumerStatefulWidget {
  final String chatId;
  final Function(String, {String? type, Map<String, dynamic>? metadata})
  onSendMessage;
  final Function(List<XFile>, String type, String? caption) onSendMedia;
  final Function(XFile, int duration, {String? caption}) onSendAudio;
  final Function(XFile, String? caption) onSendAudioFile;
  final Function(XFile, String? caption) onSendDocument;
  final Future<MessageLocation?> Function()?
  onPickLocation; // [NEW] Returns location data
  final Function(MessageLocation)?
  onSendLocation; // [UPDATED] Sends location data
  final Function(int, String, String?) onSendDSP;
  final Function(List<XFile>, String type, String caption)? onMediaSelected;
  final Message? replyingTo;
  final VoidCallback onCancelReply;
  final bool isEnabled;
  final TextEditingController? controller;
  final bool showAttachmentButton;
  final bool showAudioRecording;
  final String? hintText;
  final Color? inputBackgroundColor; // [NEW] Style
  final BoxBorder? inputBorder; // [NEW] Style
  final BorderRadius? inputBorderRadius; // [NEW] Style
  final bool canAlwaysSend; // [NEW]

  const MessageInput({
    super.key,
    required this.chatId,
    required this.onSendMessage,
    required this.onSendMedia,
    required this.onSendAudio,
    required this.onSendAudioFile,
    required this.onSendDocument,
    this.onSendLocation, // Made optional
    this.onPickLocation, // [NEW]
    required this.onSendDSP,
    this.onMediaSelected,
    this.replyingTo,
    required this.onCancelReply,
    this.isEnabled = true,
    this.participantIds = const [],
    this.controller,
    this.showAttachmentButton = true,
    this.showAudioRecording = true,
    this.hintText,
    this.inputBackgroundColor,
    this.inputBorder,
    this.inputBorderRadius,
    this.canAlwaysSend = false, // [NEW] Force enable send button
    this.recipientUserId, // [NEW] For transfers
  });

  // ... (Keep existing fields)

  final List<String> participantIds;
  final String? recipientUserId; // [NEW]

  @override
  ConsumerState<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends ConsumerState<MessageInput>
    with WidgetsBindingObserver {
  // ... (Keep existing state)
  late TextEditingController
  _controller; // [UPDATED] Late init for external support
  final FocusNode _focusNode = FocusNode();
  bool _canSend = false;

  // Voice Recording State
  final AudioRecorder _audioRecorder = AudioRecorder();

  bool _isRecording = false;
  XFile? _recordedFile; // Kept for immediate recording access
  Timer? _recordTimer;
  int _recordDurationSeconds = 0;

  // Pending Attachment State (Inline Preview)
  List<XFile> _pendingAttachments = [];
  String? _pendingAttachmentType; // 'image', 'video', 'audio', 'document'
  int _pendingAudioDuration = 0;

  bool _isProcessingAttachment = false; // [NEW] Loading state for files
  int? _pendingDSPAmount; // [NEW] For transfer preview using attachment logic
  String _pendingDSPAssetType = 'points'; // [NEW] 'points' or 'token'
  MessageLocation? _pendingLocation; // [NEW]

  // Playback State (Removed internal player, delegating to AudioMessagePlayer widget)
  // bool _isPlaying = false;
  // Duration _playbackPosition = Duration.zero;
  // Duration _playbackDuration = Duration.zero;

  Timer? _typingTimer;

  bool? _lastTypingStatus;

  // Mention System
  List<ProfileData> _cachedParticipants = [];
  List<ProfileData> _mentionSuggestions = [];
  bool _showMentions = false;
  String _mentionQuery = '';
  int _mentionTriggerIndex = -1;
  final Map<String, String> _mentionMappings = {}; // Display Name -> UID

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Add observer
    _controller =
        widget.controller ??
        TextEditingController(); // [UPDATED] Use external if provided
    _controller.addListener(_onTextChanged);
    if (widget.controller != null && widget.controller!.text.isNotEmpty) {
      _canSend = true;
    }
    _focusNode.addListener(_onFocusChanged);

    // Fetch participants initially
    if (widget.participantIds.isNotEmpty) {
      _fetchParticipants();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onTextChanged);
    if (widget.controller == null) {
      _controller.dispose();
    }
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();

    _audioRecorder.dispose();
    _recordTimer?.cancel();
    _typingTimer?.cancel();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _setTyping(false);
      if (_isRecording) {
        _stopRecording();
      }
    }
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _setTyping(false);
    }
  }

  @override
  void didUpdateWidget(MessageInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(widget.participantIds, oldWidget.participantIds)) {
      _fetchParticipants();
    }
  }

  Future<void> _fetchParticipants() async {
    if (widget.participantIds.isEmpty) return;

    try {
      final repo = ref.read(profileRepositoryProvider);
      // Fetch concurrently
      final futures = widget.participantIds.map(
        (id) => repo.getUserProfile(id),
      );
      final profiles = await Future.wait(futures);

      if (mounted) {
        setState(() {
          _cachedParticipants = profiles.whereType<ProfileData>().toList();
        });
      }
    } catch (e) {
      debugPrint('Error fetching participants for mentions: $e');
    }
  }

  void _onTextChanged() {
    final text = _controller.text;
    final selection = _controller.selection;

    // Check for mentions
    if (selection.isValid && selection.isCollapsed) {
      _checkMentions(text, selection.baseOffset);
    } else {
      setState(() => _showMentions = false);
    }

    // 3. Normal Typing Status Logic
    final isNotEmpty = text.trim().isNotEmpty;
    if (_canSend != isNotEmpty) {
      setState(() => _canSend = isNotEmpty);
    }

    if (isNotEmpty && _focusNode.hasFocus) {
      _setTyping(true);

      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 3), () {
        _setTyping(false);
      });
    } else {
      _setTyping(false);
    }
  }

  void _checkMentions(String text, int cursorPosition) {
    // Find the word being typed
    int start = cursorPosition - 1;
    while (start >= 0 &&
        text[start] != '@' &&
        text[start] != ' ' &&
        text[start] != '\n') {
      start--;
    }

    if (start >= 0 && text[start] == '@') {
      _mentionTriggerIndex = start;
      _mentionQuery = text.substring(start + 1, cursorPosition).toLowerCase();

      // Filter suggestions
      final matches = _cachedParticipants.where((p) {
        final name = '${p.firstName} ${p.lastName}'.trim().toLowerCase();
        return name.contains(_mentionQuery);
      }).toList();

      setState(() {
        _showMentions = matches.isNotEmpty;
        _mentionSuggestions = matches;
      });
    } else {
      if (_showMentions) setState(() => _showMentions = false);
    }
  }

  void _insertMention(ProfileData user) {
    final text = _controller.text;
    final selection = _controller.selection;

    if (_mentionTriggerIndex >= 0 && _mentionTriggerIndex < text.length) {
      final name = '${user.firstName} ${user.lastName}'.trim();
      final replaceEnd = selection.baseOffset;

      final newText = text.replaceRange(
        _mentionTriggerIndex,
        replaceEnd,
        '@$name ',
      );

      _controller.text = newText;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _mentionTriggerIndex + name.length + 2),
      );

      // Store mapping for sending
      if (user.uid != null) {
        _mentionMappings[name] = user.uid!;
      }

      setState(() {
        _showMentions = false;
      });
    }
  }

  Widget _buildMentionSuggestions(ThemeData theme) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _mentionSuggestions.length,
        itemBuilder: (context, index) {
          final user = _mentionSuggestions[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundImage: NetworkImage(user.profileImage),
              radius: 16,
              child: null,
            ),
            title: Text('${user.firstName} ${user.lastName}'),
            onTap: () => _insertMention(user),
            dense: true,
          );
        },
      ),
    );
  }

  void _setTyping(bool isTyping) {
    if (!mounted) return; // [FIX] Prevent using ref after dispose
    if (_lastTypingStatus == isTyping) return;
    _lastTypingStatus = isTyping;
    ref.read(chatRepositoryProvider).setTypingStatus(widget.chatId, isTyping);
  }

  // --- Voice Recording Logic ---

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        String path;
        if (kIsWeb) {
          path = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        } else {
          final directory = await getApplicationDocumentsDirectory();
          path =
              '${directory.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        }

        await _audioRecorder.start(const RecordConfig(), path: path);

        // Start Timer
        _recordDurationSeconds = 0;
        _recordTimer?.cancel();
        _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          setState(() {
            _recordDurationSeconds++;
          });
        });

        setState(() {
          _isRecording = true;
          _recordedFile = null;
          // Clear any previous pending attachments when starting new recording
          _pendingAttachments = [];
          _pendingAttachmentType = null;
        });
      }
    } catch (e) {
      debugPrint('Error starting recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      _recordTimer?.cancel();

      if (path != null) {
        final file = XFile(path);

        // Note: MessageInput's internal _audioPlayer is not used for the preview widget (AudioMessagePlayer),
        // so we don't strictly need to set it up here.
        // If legacy code needs it, we wrap in try-catch to not break the UI flow.
        // Internal player setup removed to avoid file locking with AudioMessagePlayer
        // _audioPlayer.setFilePath(path);

        if (mounted) {
          setState(() {
            _isRecording = false;
            _recordedFile = file;

            // Set as pending attachment for inline preview
            _pendingAttachments = [file];
            _pendingAttachmentType = 'audio';
            _pendingAudioDuration = _recordDurationSeconds;

            // _playbackDuration removed
          });
        }
      } else {
        if (mounted) setState(() => _isRecording = false);
      }
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      if (mounted) setState(() => _isRecording = false);
    }
  }

  Future<void> _cancelRecording({bool deleteFile = true}) async {
    _recordTimer?.cancel();
    if (_isRecording) {
      await _audioRecorder.stop();
    }

    // Delete file if exists and requested (Native only)
    if (!kIsWeb && deleteFile && _recordedFile != null) {
      final file = File(_recordedFile!.path);
      if (await file.exists()) {
        await file.delete();
      }
    }

    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordedFile = null;
        _recordDurationSeconds = 0;
        // _playbackPosition removed

        // Clear pending
        _pendingAttachments = [];
        _pendingAttachmentType = null;
        _pendingAudioDuration = 0;
        _pendingDSPAmount = null;
        _pendingLocation = null;
      });
    }
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _handleContentInsertion(KeyboardInsertedContent content) async {
    if (content.mimeType.startsWith('image/') ||
        content.mimeType.startsWith('video/')) {
      final type = content.mimeType.startsWith('video/') ? 'video' : 'image';
      XFile? file;

      setState(() => _isProcessingAttachment = true);

      try {
        if (content.data != null) {
          final tempDir = await getTemporaryDirectory();
          final ext = content.mimeType.split('/').last;
          final path =
              '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.$ext';
          final f = File(path);
          await f.writeAsBytes(content.data!);
          file = XFile(path);
        } else if (content.uri.isNotEmpty) {
          final uri = Uri.parse(content.uri);
          if (uri.scheme == 'http' || uri.scheme == 'https') {
            final response = await http.get(uri);
            if (response.statusCode == 200) {
              final tempDir = await getTemporaryDirectory();
              final ext = content.mimeType.split('/').last;
              final path =
                  '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.$ext';
              final f = File(path);
              await f.writeAsBytes(response.bodyBytes);
              file = XFile(path);
            }
          } else {
            debugPrint(
              'Unsupported URI scheme for keyboard content: ${uri.scheme}',
            );
          }
        }

        if (file != null && mounted) {
          if (widget.onMediaSelected != null) {
            widget.onMediaSelected!([file], type, _controller.text);
            setState(() => _isProcessingAttachment = false);
          } else {
            setState(() {
              _pendingAttachments = [file!];
              _pendingAttachmentType = type;
              _isProcessingAttachment = false;
            });
          }
        } else {
          if (mounted) setState(() => _isProcessingAttachment = false);
        }
      } catch (e) {
        debugPrint('Error handling keyboard content: $e');
        if (mounted) setState(() => _isProcessingAttachment = false);
      }
    }
  }

  // --- Send Logic ---

  void _handleSend() {
    // Check pending attachments first
    if (_pendingAttachments.isNotEmpty) {
      final text = _controller.text.trim();
      final caption = text.isNotEmpty ? text : null;

      // Capture state for async handling
      final attachments = List<XFile>.from(_pendingAttachments);
      final type = _pendingAttachmentType;
      final audioDuration = _pendingAudioDuration;
      final dspAmount = _pendingDSPAmount;
      final location = _pendingLocation;

      // Optimistic UI Reset: Clear input immediately
      // Do not delete file here, repository needs it.
      _cancelRecording(deleteFile: false);
      _controller.clear();

      // Yield to UI thread to prevent freeze
      Future.delayed(Duration.zero, () {
        if (!mounted) return;

        if (type == 'audio') {
          // Voice message
          widget.onSendAudio(
            attachments.first,
            audioDuration,
            caption: caption,
          );
        } else if (type == 'audio_file') {
          // Audio File
          widget.onSendAudioFile(attachments.first, caption);
        } else if (type == 'document') {
          widget.onSendDocument(attachments.first, caption);
        } else if (type == 'dsp_transfer' && dspAmount != null) {
          widget.onSendDSP(dspAmount, _pendingDSPAssetType, caption);
        } else if (type == 'location' && location != null) {
          if (widget.onSendLocation != null) {
            widget.onSendLocation!(location);
          }
        } else {
          // Image/Video
          // Ensure type is not null, default to 'image' if unclear
          widget.onSendMedia(attachments, type ?? 'image', caption);
        }
      });
      return;
    }

    if (!_canSend && !widget.canAlwaysSend) return;

    final text = _controller.text.trim();
    if (text.isEmpty && !widget.canAlwaysSend) return;

    // Construct mention data
    List<String>? mentionIds;
    String? richContent;

    if (_mentionMappings.isNotEmpty) {
      String processedText = text;
      final Set<String> ids = {};

      _mentionMappings.forEach((name, uid) {
        if (processedText.contains('@$name')) {
          ids.add(uid);
          // Format: @{uid:Name}
          processedText = processedText.replaceAll('@$name', '@{$uid:$name}');
        }
      });

      if (ids.isNotEmpty) {
        mentionIds = ids.toList();
        richContent = processedText;
      }
    }

    widget.onSendMessage(
      text,
      type: 'text',
      metadata: {
        'mentions': ?mentionIds,
        'richContent': ?richContent,
      },
    );

    _mentionMappings.clear();
    setState(() => _showMentions = false);
    _controller.clear();

    _typingTimer?.cancel();
    _setTyping(false);
    if (widget.replyingTo != null) {
      widget.onCancelReply();
    }
  }

  void _showAttachmentModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // [Fix] Allow modal to resize with keyboard
      backgroundColor: Colors.transparent,
      builder: (context) => _AttachmentPickerModal(
        recipientUserId: widget.recipientUserId, // [NEW]
        onPickImage: () => _pickMedia(ImageSource.gallery, 'image'),
        onPickCamera: () => _pickMedia(ImageSource.camera, 'image'),
        onPickVideo: () => _pickMedia(ImageSource.gallery, 'video'),
        onPickDocument: _pickDocument,
        onPickAudio: _pickAudio,
        onPickLocation: () async {
          Navigator.pop(context);
          if (widget.onPickLocation != null) {
            setState(() => _isProcessingAttachment = true);
            final loc = await widget.onPickLocation!();
            if (loc != null && mounted) {
              setState(() {
                _pendingLocation = loc;
                _pendingAttachmentType = 'location';
                _pendingAttachments = [XFile('')]; // Dummy for hasAttachment
                _isProcessingAttachment = false;
              });
            } else {
              if (mounted) setState(() => _isProcessingAttachment = false);
            }
          }
        },
        onPickDSP: (amount, assetType) {
          Navigator.pop(context);
          setState(() {
            _pendingAttachments = [
              XFile(''),
            ]; // Dummy file to satisfy hasAttachment logic
            _pendingAttachmentType = 'dsp_transfer';
            _pendingDSPAmount = amount;
            _pendingDSPAssetType = assetType;
            _isProcessingAttachment = false;
          });
        },
      ),
    );
  }

  Future<void> _pickMedia(ImageSource source, String type) async {
    Navigator.pop(context); // Close modal

    setState(() => _isProcessingAttachment = true);

    final picker = ImagePicker();
    List<XFile> files = [];

    try {
      if (type == 'image') {
        if (source == ImageSource.camera) {
          final photo = await picker.pickImage(
            source: source,
            imageQuality: 85,
            maxWidth: 1024,
            maxHeight: 1024,
          );
          if (photo != null) files.add(photo);
        } else {
          final images = await picker.pickMultiImage(
            imageQuality: 85,
            maxWidth: 1024,
            maxHeight: 1024,
          );
          files.addAll(images);
        }
      } else {
        final video = await picker.pickVideo(source: source);
        if (video != null) files.add(video);
      }

      if (files.isNotEmpty && mounted) {
        if (widget.onMediaSelected != null) {
          widget.onMediaSelected!(
            files,
            type,
            _controller.text,
          ); // Pass caption
          setState(() => _isProcessingAttachment = false);
        } else {
          setState(() {
            _pendingAttachments = files;
            _pendingAttachmentType = type;
            _isProcessingAttachment = false;
          });
        }
      } else {
        if (mounted) setState(() => _isProcessingAttachment = false);
      }
    } catch (e) {
      debugPrint('Error picking media: $e');
      if (mounted) setState(() => _isProcessingAttachment = false);
    }
    // Logic for direct state update was here, removed duplicate check
  }

  Future<void> _pickDocument() async {
    Navigator.pop(context);
    setState(() => _isProcessingAttachment = true);

    try {
      final result = await fp.FilePicker.platform.pickFiles(
        type: fp.FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'txt', 'xls', 'xlsx'],
      );
      if (result != null && result.files.single.path != null && mounted) {
        setState(() {
          // Handle web (bytes) vs native (path)
          if (kIsWeb && result.files.single.bytes != null) {
            _pendingAttachments = [
              XFile.fromData(
                result.files.single.bytes!,
                name: result.files.single.name,
              ),
            ];
          } else {
            _pendingAttachments = [
              XFile(result.files.single.path!, name: result.files.single.name),
            ];
          }
          _pendingAttachmentType = 'document';
          _isProcessingAttachment = false;
        });
      } else {
        if (mounted) setState(() => _isProcessingAttachment = false);
      }
    } catch (e) {
      debugPrint('Error picking document: $e');
      if (mounted) setState(() => _isProcessingAttachment = false);
    }
  }

  Future<void> _pickAudio() async {
    Navigator.pop(context);
    setState(() => _isProcessingAttachment = true);

    try {
      final result = await fp.FilePicker.platform.pickFiles(
        type: fp.FileType.audio,
      );
      if (result != null && result.files.single.path != null && mounted) {
        setState(() {
          if (kIsWeb && result.files.single.bytes != null) {
            _pendingAttachments = [
              XFile.fromData(
                result.files.single.bytes!,
                name: result.files.single.name,
              ),
            ];
          } else {
            _pendingAttachments = [
              XFile(result.files.single.path!, name: result.files.single.name),
            ];
          }
          _pendingAttachmentType = 'audio_file';
          _isProcessingAttachment = false;
        });
      } else {
        if (mounted) setState(() => _isProcessingAttachment = false);
      }
    } catch (e) {
      debugPrint('Error picking audio: $e');
      if (mounted) setState(() => _isProcessingAttachment = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Determine UI Mode
    if (_isRecording) {
      return _buildRecordingUI(theme);
    }
    // _isReviewing removed, now using inline preview

    final hasAttachment = _pendingAttachments.isNotEmpty;
    final showSend = _canSend || hasAttachment || widget.canAlwaysSend;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.replyingTo != null) _buildReplyPreview(theme),

        if (hasAttachment) _buildAttachmentPreview(theme),
        if (_showMentions) _buildMentionSuggestions(theme),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            border: Border(
              top: BorderSide(color: theme.dividerColor, width: 0.5),
            ),
          ),
          child: SafeArea(
            child: Row(
              children: [
                if (widget.showAttachmentButton)
                  IconButton(
                    onPressed: widget.isEnabled ? _showAttachmentModal : null,
                    icon: Icon(
                      LucideIcons.plus,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: hasAttachment
                        ? null
                        : BoxDecoration(
                            color:
                                widget.inputBackgroundColor ?? theme.cardColor,
                            borderRadius:
                                widget.inputBorderRadius ??
                                BorderRadius.circular(24),
                            border:
                                widget.inputBorder ??
                                Border.all(color: theme.dividerColor),
                          ),
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      enabled: widget.isEnabled,
                      maxLines: 5,
                      minLines: 1,
                      autofocus: false, // [FIX] Disable auto-focus
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: hasAttachment
                          ? TextInputAction.send
                          : TextInputAction.newline,
                      onSubmitted: hasAttachment ? (_) => _handleSend() : null,
                      decoration: InputDecoration(
                        hintText:
                            widget.hintText ??
                            (hasAttachment
                                ? 'Add a caption...'
                                : 'Type a message...'),
                        border: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        filled: true,
                        fillColor: Colors.transparent,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 10,
                        ),
                      ),
                      contentInsertionConfiguration:
                          ContentInsertionConfiguration(
                            allowedMimeTypes: const <String>[
                              'image/png',
                              'image/jpeg',
                              'image/gif',
                              'video/mp4',
                            ],
                            onContentInserted: _handleContentInsertion,
                          ),
                      style: theme.textTheme.bodyMedium,
                      onChanged: (text) {
                        // Keep cursor in view
                      },
                      onTapOutside: (event) {
                        // Optional: unfocus
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Send or Mic Button
                IconButton(
                  onPressed: widget.isEnabled
                      ? (showSend
                            ? _handleSend
                            : (widget.showAudioRecording
                                  ? _toggleRecording
                                  : null))
                      : null,
                  icon: Icon(
                    showSend
                        ? LucideIcons.send
                        : (widget.showAudioRecording
                              ? LucideIcons.mic
                              : LucideIcons
                                    .send), // Force send icon if no audio
                    color: showSend
                        ? theme.colorScheme.primary
                        : (widget.showAudioRecording
                              ? theme.colorScheme.primary
                              : theme.disabledColor),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecordingUI(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.red.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(LucideIcons.mic, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Recording... ${_formatDuration(_recordDurationSeconds)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: _cancelRecording,
                      child: Text('Cancel', style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Stop Button
            IconButton(
              onPressed: _stopRecording,
              style: IconButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(12),
              ),
              icon: const Icon(
                LucideIcons.square,
                size: 16,
                fill: 1,
              ), // Square for stop
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentPreview(ThemeData theme) {
    if (_pendingAttachments.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.cardColor, // [FIX] Use card color as requested
        border: Border(top: BorderSide(color: theme.dividerColor, width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Builder(
              builder: (context) {
                switch (_pendingAttachmentType) {
                  case 'dsp_transfer':
                    return _buildInlineDSPPreview(theme);
                  case 'image':
                  case 'video':
                    return _buildInlineMediaPreview(theme);
                  case 'audio':
                  case 'audio_file':
                    // [FIX] Ensure URI format for local files if needed, mostly logic is fine but path matters
                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: AudioMessagePlayer(
                        messageId: _pendingAttachments
                            .first
                            .path, // Use path as unique ID for preview
                        audioUrl: _pendingAttachments.first.path,
                        durationSeconds: _pendingAudioDuration,
                        isOwn: true,
                        // foregroundColor: No longer needed, logic uses onPrimary when isOwn=true
                      ),
                    );
                  case 'location':
                    return _buildInlineLocationPreview(theme);
                  case 'document':
                    return _buildInlineDocumentPreview(theme);
                  default:
                    return const SizedBox.shrink();
                }
              },
            ),
          ),
          const SizedBox(width: 12),
          if (_isProcessingAttachment)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            )
          else
            IconButton(
              onPressed: () => _cancelRecording(deleteFile: true),
              icon: Icon(
                LucideIcons.x,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Remove attachment',
            ),
        ],
      ),
    );
  }

  Widget _buildInlineDSPPreview(ThemeData theme) {
    if (_pendingDSPAmount == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(LucideIcons.coins, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sending $_pendingDSPAmount ${_pendingDSPAssetType == 'points' ? 'DSP' : r'$DIASPORA'}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Transfer ready',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // _buildInlineAudioPlayer removed (replaced by AudioMessagePlayer widget)

  Widget _buildInlineMediaPreview(ThemeData theme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _pendingAttachments.map((file) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_pendingAttachmentType == 'video')
                    Container(
                      width: 60,
                      height: 60,
                      color: Colors.black,
                      child: const Icon(
                        LucideIcons.play,
                        size: 24,
                        color: Colors.white,
                      ),
                    )
                  else
                    kIsWeb
                        ? Image.network(
                            file.path,
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                          )
                        : Image.file(
                            File(file.path),
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                          ),
                  if (_pendingAttachmentType == 'video')
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        LucideIcons.play,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInlineDocumentPreview(ThemeData theme) {
    // ... (existing implementation)
    final file = _pendingAttachments.first;
    final name = file.path.split('/').last;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface, // Better contrast inside the preview
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.fileText,
            color: theme.colorScheme.primary,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Document',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineLocationPreview(ThemeData theme) {
    if (_pendingLocation == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              LucideIcons.mapPin,
              color: Colors.green,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Location',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_pendingLocation!.address.isNotEmpty)
                  Text(
                    _pendingLocation!.address,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyPreview(ThemeData theme) {
    final replyingTo = widget.replyingTo;
    if (replyingTo == null) return const SizedBox.shrink();

    String contentText = replyingTo.content;
    IconData? mediaIcon;
    String? imageUrl;

    if (replyingTo.type == 'image') {
      contentText = 'Photo';
      mediaIcon = LucideIcons.image;
      imageUrl = replyingTo.imageUrl;
    } else if (replyingTo.type == 'video') {
      contentText = 'Video';
      mediaIcon = LucideIcons.video;
    } else if (replyingTo.type == 'audio' || replyingTo.type == 'audio_file') {
      contentText = 'Voice message';
      mediaIcon = LucideIcons.mic;
    } else if (replyingTo.type == 'location') {
      contentText = 'Location';
      mediaIcon = LucideIcons.mapPin;
    } else if (replyingTo.type == 'document') {
      contentText = replyingTo.documentName ?? 'Document';
      mediaIcon = LucideIcons.fileText;
    } else if (replyingTo.type == 'dsp_transfer') {
      contentText = 'DSP Transfer';
      mediaIcon = LucideIcons.coins;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: theme.cardColor.withOpacity(0.8),
        border: Border(top: BorderSide(color: theme.dividerColor, width: 0.5)),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Vertical accent bar
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        LucideIcons.reply,
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Replying to ${replyingTo.senderName}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (mediaIcon != null) ...[
                        Icon(
                          mediaIcon,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          contentText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (imageUrl != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.network(
                    imageUrl,
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            IconButton(
              icon: Icon(
                LucideIcons.x,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              onPressed: widget.onCancelReply,
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentPickerModal extends ConsumerStatefulWidget {
  final VoidCallback onPickImage;
  final VoidCallback onPickCamera;
  final VoidCallback onPickVideo;
  final VoidCallback onPickDocument;
  final VoidCallback onPickAudio;
  final VoidCallback onPickLocation;
  final Function(int, String)
  onPickDSP; // Renamed to ensure clarity it's just picking

  const _AttachmentPickerModal({
    required this.onPickImage,
    required this.onPickCamera,
    required this.onPickVideo,
    required this.onPickDocument,
    required this.onPickAudio,
    required this.onPickLocation,
    required this.onPickDSP,
    this.recipientUserId, // [NEW]
  });

  final String? recipientUserId; // [NEW]

  @override
  ConsumerState<_AttachmentPickerModal> createState() =>
      _AttachmentPickerModalState();
}

class _AttachmentPickerModalState
    extends ConsumerState<_AttachmentPickerModal> {
  final TextEditingController _amountController = TextEditingController();

  String _selectedAssetType = 'points'; // 'points' or 'token'
  int _inputAmount = 0;

  @override
  void initState() {
    super.initState();
    _amountController.addListener(() {
      final val = int.tryParse(_amountController.text) ?? 0;
      if (mounted) setState(() => _inputAmount = val);
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  // Removed _fetchBalance in favor of ref.watch in build

  void _handlePickDSP(int currentBalance) {
    if (_inputAmount <= 0) return;

    if (_inputAmount > currentBalance) {
      // Optionally show error, but UI handles disabled button
      return;
    }

    widget.onPickDSP(_inputAmount, _selectedAssetType);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isToken = _selectedAssetType == 'token';
    final activeColor = isToken ? Colors.orange : theme.colorScheme.primary;

    // [Refactor] Reactive Balance Fetching
    final authState = ref.watch(authStateProvider);
    final authUser = authState.asData?.value;

    // Watch points if user is logged in
    final pointsAsync = authUser != null
        ? ref.watch(userPointsProvider(authUser.uid))
        : const AsyncValue<UserPoints?>.loading();

    final pointsBalance = pointsAsync.asData?.value?.availablePoints ?? 0;
    // TODO: Implement token balance provider
    final tokenBalance = 0;

    final currentBalance = _selectedAssetType == 'points'
        ? pointsBalance
        : tokenBalance;
    final isLoadingBalance = pointsAsync.isLoading;

    // Projected balance calculation
    final remaining = currentBalance - _inputAmount;
    final isError = _inputAmount > currentBalance;
    final isZero = _inputAmount <= 0;

    // [Fix] Handle keyboard
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        // Add bottomInset to padding to push content up
        padding: EdgeInsets.fromLTRB(8, 20, 8, 20 + bottomInset),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildButton(
                    context,
                    LucideIcons.camera,
                    'Camera',
                    widget.onPickCamera,
                  ),
                  _buildButton(
                    context,
                    LucideIcons.image,
                    'Photo',
                    widget.onPickImage,
                  ),
                  _buildButton(
                    context,
                    LucideIcons.video,
                    'Video',
                    widget.onPickVideo,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildButton(
                    context,
                    LucideIcons.music,
                    'Audio',
                    widget.onPickAudio,
                  ),
                  _buildButton(
                    context,
                    LucideIcons.fileText,
                    'Document',
                    widget.onPickDocument,
                  ),
                  _buildButton(
                    context,
                    LucideIcons.mapPin,
                    'Location',
                    widget.onPickLocation,
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // [NEW] Recipient Address Row (Only for Token)
              if (widget.recipientUserId != null &&
                  isToken) // [FIX] Hide for DSP
                Consumer(
                  builder: (context, ref, _) {
                    final recipientAsync = ref.watch(
                      userProfileByIdProvider(widget.recipientUserId!),
                    );
                    final recipient = recipientAsync.asData?.value;
                    final walletAddress = recipient?.walletAddress;
                    final displayAddress = walletAddress != null
                        ? '${walletAddress.substring(0, 6)}...${walletAddress.substring(walletAddress.length - 4)}'
                        : (recipientAsync.isLoading
                              ? 'Loading...'
                              : 'No address linked');

                    return Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withOpacity(
                          0.2,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.5),
                        ), // [FIX] Orange border
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(
                                0.1,
                              ), // [FIX] Orange background
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              LucideIcons.wallet, // [FIX] Wallet icon
                              color: Colors.orange, // [FIX] Orange icon
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'To: ${recipient?.firstName ?? 'Recipient'} ${recipient?.lastName ?? ''}',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  displayAddress,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

              // [REMOVED] Sender Layout as per request
              const SizedBox(height: 20),
              Divider(color: theme.dividerColor, height: 1),
              const SizedBox(height: 16),

              // [New] Asset Type Toggle
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withOpacity(
                    0.5,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _selectedAssetType = 'points'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _selectedAssetType == 'points'
                                ? theme.colorScheme.surface
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: _selectedAssetType == 'points'
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 4,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Text(
                            'Points (DSP)',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: _selectedAssetType == 'points'
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: _selectedAssetType == 'points'
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _selectedAssetType = 'token'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _selectedAssetType == 'token'
                                ? theme.colorScheme.surface
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: _selectedAssetType == 'token'
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 4,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Text(
                            'Token (\$DIASPORA)',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: _selectedAssetType == 'token'
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: _selectedAssetType == 'token'
                                  ? Colors
                                        .orange // [FIX] Orange for Token
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // [New] Bottom DSP Row - Wrapped in Light Background
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withOpacity(
                    0.3,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    // Layout: 3 Columns
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.stretch, // Match heights
                        children: [
                          // LEFT: Balance
                          Expanded(
                            flex: 2,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Balance',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontSize: 10,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  isLoadingBalance ? '...' : '$remaining',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: isError
                                        ? theme.colorScheme.error
                                        : theme.colorScheme.onSurface,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _selectedAssetType == 'points'
                                      ? 'DSP'
                                      : r'$DIASPORA',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontSize: 8,
                                    color: activeColor, // [FIX] Dynamic color
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(width: 8),

                          // CENTER: Input (Styled Box)
                          Expanded(
                            flex: 3,
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface, // Input BG
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: TextField(
                                controller: _amountController,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: activeColor, // [FIX] Dynamic color
                                ),
                                decoration: InputDecoration(
                                  hintText: '0',
                                  hintStyle: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant
                                        .withOpacity(0.3),
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ), // Minimal padding
                                  isDense: true,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 8),

                          // RIGHT: Action
                          Expanded(
                            flex: 2,
                            child: Center(
                              child: Material(
                                color: (isZero || isError || isLoadingBalance)
                                    ? theme.disabledColor
                                    : activeColor, // [FIX] Dynamic color
                                shape: const CircleBorder(),
                                child: InkWell(
                                  onTap: (isZero || isError || isLoadingBalance)
                                      ? null
                                      : () => _handlePickDSP(currentBalance),
                                  customBorder: const CircleBorder(),
                                  child: Container(
                                    width: 48,
                                    height: 48,
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      LucideIcons.arrowRight,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),
                    // Label centered at bottom
                    Text(
                      'Enter Amount of ${_selectedAssetType == 'points' ? 'DSP' : r'$DIASPORA'} to Send',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        color: activeColor, // [FIX] Dynamic color
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildButton(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    Color? color,
  }) {
    final theme = Theme.of(context);
    final iconColor = color ?? theme.colorScheme.primary;

    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

// [NEW] Mention List Item

// Ensure proper imports are added if missing.
// userProfileProvider needs to be found.
