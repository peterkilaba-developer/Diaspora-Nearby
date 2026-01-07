import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:diaspora_nearby/models/message.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:just_audio/just_audio.dart' as ja; // Alias to avoid conflict with record
import 'package:diaspora_nearby/features/chat/repository/chat_repository.dart';

import 'package:diaspora_nearby/features/profile/repository/profile_repository.dart'; 
import 'package:diaspora_nearby/models/profile_data.dart'; // [New]


class MessageInput extends ConsumerStatefulWidget {
  final String chatId;
  final Function(String, {String? type, Map<String, dynamic>? metadata}) onSendMessage;
  final Function(List<File>, String type, String? caption) onSendMedia;
  final Function(File, int duration, {String? caption}) onSendAudio;
  final Function(File, String? caption) onSendAudioFile;
  final Function(File, String? caption) onSendDocument;
  final VoidCallback onSendLocation;
  final Message? replyingTo;
  final VoidCallback onCancelReply;
  final bool isEnabled;

  const MessageInput({
    super.key,
    required this.chatId,
    required this.onSendMessage,
    required this.onSendMedia,
    required this.onSendAudio,
    required this.onSendAudioFile,
    required this.onSendDocument,
    required this.onSendLocation,
    this.replyingTo,
    required this.onCancelReply,
    this.isEnabled = true,
    this.participantIds = const [],
  });

  final List<String> participantIds;

  @override
  ConsumerState<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends ConsumerState<MessageInput> with WidgetsBindingObserver {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _canSend = false;

  // Voice Recording State
  final AudioRecorder _audioRecorder = AudioRecorder();
  final ja.AudioPlayer _audioPlayer = ja.AudioPlayer();
  
  bool _isRecording = false;
  File? _recordedFile; // Kept for immediate recording access
  Timer? _recordTimer;
  int _recordDurationSeconds = 0;
  
  // Pending Attachment State (Inline Preview)
  List<File> _pendingAttachments = [];
  String? _pendingAttachmentType; // 'image', 'video', 'audio', 'document'
  int _pendingAudioDuration = 0;
  bool _isProcessingAttachment = false; // [NEW] Loading state for files
  
  // Playback State
  bool _isPlaying = false;
  Duration _playbackPosition = Duration.zero;
  Duration _playbackDuration = Duration.zero;

  Timer? _typingTimer;
  bool? _lastTypingStatus;



  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Add observer
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
    
    // Listen to player state
    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
          if (state.processingState == ja.ProcessingState.completed) {
            _isPlaying = false;
            _audioPlayer.pause();
            _audioPlayer.seek(Duration.zero);
          }
        });
      }
    });

    _audioPlayer.positionStream.listen((pos) {
      if (mounted) setState(() => _playbackPosition = pos);
    });
    
    _audioPlayer.durationStream.listen((d) {
      if (mounted && d != null) setState(() => _playbackDuration = d);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _setTyping(false);
    }
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _setTyping(false);
    }
  }

  void _onTextChanged() {
    final text = _controller.text;

    
    // Mention Detection Removed

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




  void _setTyping(bool isTyping) {
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
        final directory = await getApplicationDocumentsDirectory();
        final path = '${directory.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        
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
        final file = File(path);
        // Initialize player for review
        await _audioPlayer.setFilePath(path);

        setState(() {
          _isRecording = false;
          _recordedFile = file;
          
          // Set as pending attachment for inline preview
          _pendingAttachments = [file];
          _pendingAttachmentType = 'audio';
          _pendingAudioDuration = _recordDurationSeconds;
          
          _playbackDuration = Duration(seconds: _recordDurationSeconds);
        });
        
        // Auto-focus triggering keyboard removed
      } else {
        // Failed
        setState(() => _isRecording = false);
      }
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      setState(() => _isRecording = false);
    }
  }

  Future<void> _cancelRecording({bool deleteFile = true}) async {
    _recordTimer?.cancel();
    if (_isRecording) {
       await _audioRecorder.stop();
    }
    await _audioPlayer.stop();
    
    // Delete file if exists and requested
    if (deleteFile && _recordedFile != null && await _recordedFile!.exists()) {
      await _recordedFile!.delete();
    }

    setState(() {
      _isRecording = false;
      _recordedFile = null;
      _recordDurationSeconds = 0;
      _playbackPosition = Duration.zero;
      
      // Clear pending
      _pendingAttachments = [];
      _pendingAttachmentType = null;
      _pendingAudioDuration = 0;
    });
  }



  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play();
    }
  }

  Future<void> _seek(double value) async {
    await _audioPlayer.seek(Duration(seconds: value.toInt()));
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // --- Send Logic ---

  void _handleSend() {
    // Check pending attachments first
    if (_pendingAttachments.isNotEmpty) {
      final text = _controller.text.trim();
      final caption = text.isNotEmpty ? text : null;

      if (_pendingAttachmentType == 'audio') {
         // Voice message
         widget.onSendAudio(_pendingAttachments.first, _pendingAudioDuration, caption: caption);
      } else if (_pendingAttachmentType == 'audio_file') {
         // Audio File
         widget.onSendAudioFile(_pendingAttachments.first, caption);
      } else if (_pendingAttachmentType == 'document') {
         widget.onSendDocument(_pendingAttachments.first, caption);
      } else {
         // Image/Video
         // Ensure type is not null, default to 'image' if unclear
         widget.onSendMedia(_pendingAttachments, _pendingAttachmentType ?? 'image', caption);
      }
      
      // Clear state but don't delete file if it was voice (repo handles upload)
      // Actually _cancelRecording(deleteFile: false) serves well here to reset UI
      _cancelRecording(deleteFile: false);
      _controller.clear();
      return;
    }

    if (!_canSend) return;
    
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    widget.onSendMessage(text, type: 'text');
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
      backgroundColor: Colors.transparent,
      builder: (context) => _AttachmentPickerModal(
        onPickImage: () => _pickMedia(ImageSource.gallery, 'image'),
        onPickCamera: () => _pickMedia(ImageSource.camera, 'image'),
        onPickVideo: () => _pickMedia(ImageSource.gallery, 'video'),
        onPickDocument: _pickDocument,
        onPickAudio: _pickAudio,
        onPickLocation: () {
          Navigator.pop(context);
          widget.onSendLocation();
        },
      ),
    );
  }

  Future<void> _pickMedia(ImageSource source, String type) async {
    Navigator.pop(context); // Close modal
    
    setState(() => _isProcessingAttachment = true);
    
    final picker = ImagePicker();
    List<File> files = [];

    try {
      if (type == 'image') {
        if (source == ImageSource.camera) {
           final photo = await picker.pickImage(
             source: source,
             imageQuality: 70,
             maxWidth: 1920,
           );
           if (photo != null) files.add(File(photo.path));
        } else {
           final images = await picker.pickMultiImage(
             imageQuality: 70,
             maxWidth: 1920,
           );
           files.addAll(images.map((i) => File(i.path)));
        }
      } else {
        final video = await picker.pickVideo(source: source);
        if (video != null) files.add(File(video.path));
      }

      if (files.isNotEmpty && mounted) {
        setState(() {
          _pendingAttachments = files;
          _pendingAttachmentType = type;
          _isProcessingAttachment = false; // Done
        });
      } else {
        if (mounted) setState(() => _isProcessingAttachment = false);
      }
    } catch (e) {
      debugPrint('Error picking media: $e');
      if (mounted) setState(() => _isProcessingAttachment = false);
    }

    if (files.isNotEmpty && mounted) {
      setState(() {
        _pendingAttachments = files;
        _pendingAttachmentType = type;
      });
    }
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
          _pendingAttachments = [File(result.files.single.path!)];
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
      final result = await fp.FilePicker.platform.pickFiles(type: fp.FileType.audio);
      if (result != null && result.files.single.path != null && mounted) {
        setState(() {
          _pendingAttachments = [File(result.files.single.path!)];
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
    final showSend = _canSend || hasAttachment;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.replyingTo != null) _buildReplyPreview(theme),
        if (hasAttachment) _buildAttachmentPreview(theme),

        
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            border: Border(top: BorderSide(color: theme.dividerColor, width: 0.5)),
          ),
          child: SafeArea(
            child: Row(
              children: [
                IconButton(
                  onPressed: widget.isEnabled ? _showAttachmentModal : null,
                  icon: Icon(LucideIcons.plus, color: theme.colorScheme.primary),
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: hasAttachment 
                        ? null 
                        : BoxDecoration(
                            color: theme.cardColor,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: theme.dividerColor),
                          ),
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      enabled: widget.isEnabled,
                      maxLines: 5,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: hasAttachment ? TextInputAction.send : TextInputAction.newline,
                      onSubmitted: hasAttachment ? (_) => _handleSend() : null,
                      decoration: InputDecoration(
                        hintText: hasAttachment ? 'Add a caption...' : 'Type a message...',
                        border: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        filled: true,
                        fillColor: Colors.transparent,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Send or Mic Button
                IconButton(
                  onPressed: widget.isEnabled 
                      ? (showSend ? _handleSend : _toggleRecording)
                      : null,
                  icon: Icon(
                    showSend ? LucideIcons.send : LucideIcons.mic,
                    color: showSend ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: theme.scaffoldBackgroundColor,
        child: SafeArea(
          child: Row(
            children: [
               // Blinking red dot or icon
               const Icon(LucideIcons.mic, color: Colors.red),
               const SizedBox(width: 12),
               Text(
                 'Recording... ${_formatDuration(_recordDurationSeconds)}',
                 style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.red,
                    fontWeight: FontWeight.bold
                 ),
               ),
               const Spacer(),
               TextButton(
                 onPressed: _cancelRecording,
                 child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
               ),
               const SizedBox(width: 8),
               // Stop Button
               IconButton(
                 onPressed: _stopRecording,
                 style: IconButton.styleFrom(
                   backgroundColor: Colors.red.withOpacity(0.1),
                   foregroundColor: Colors.red,
                 ),
                 icon: const Icon(LucideIcons.square, size: 20), // Square for stop
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
        color: theme.cardColor,
        border: Border(top: BorderSide(color: theme.dividerColor, width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Builder(
              builder: (context) {
                switch (_pendingAttachmentType) {
                  case 'audio':
                  case 'audio_file':
                    return _buildInlineAudioPlayer(theme);
                  case 'document':
                    return _buildInlineDocumentPreview(theme);
                  case 'image':
                  case 'video':
                    return _buildInlineMediaPreview(theme);
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
              icon: Icon(LucideIcons.x, size: 20, color: theme.colorScheme.onSurfaceVariant),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Remove attachment',
            ),
        ],
      ),
    );
  }

  Widget _buildInlineAudioPlayer(ThemeData theme) {
    return Row(
      children: [
        GestureDetector(
          onTap: _togglePlayback,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isPlaying ? LucideIcons.pause : LucideIcons.play,
              color: theme.colorScheme.primary,
              size: 20,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  trackHeight: 2,
                  thumbColor: theme.colorScheme.primary,
                  activeTrackColor: theme.colorScheme.primary,
                  inactiveTrackColor: theme.colorScheme.primary.withValues(alpha: 0.2),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                ),
                child: Slider(
                  value: _playbackPosition.inSeconds.toDouble().clamp(0.0, _playbackDuration.inSeconds.toDouble()),
                  max: _playbackDuration.inSeconds.toDouble() > 0 ? _playbackDuration.inSeconds.toDouble() : 1.0,
                  onChanged: (v) {
                    _seek(v);
                  },
                ),
              ),
              Padding(
                 padding: const EdgeInsets.only(left: 4),
                 child: Text(
                  '${_formatDuration(_playbackPosition.inSeconds)} / ${_formatDuration(_playbackDuration.inSeconds)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 10, 
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: [const FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

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
                       child: const Icon(LucideIcons.play, size: 24, color: Colors.white),
                     )
                   else
                     Image.file(
                       file,
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
                      child: const Icon(LucideIcons.play, size: 12, color: Colors.white),
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
    final file = _pendingAttachments.first;
    final name = file.path.split('/').last;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.fileText, color: theme.colorScheme.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Document',
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
                           Icon(LucideIcons.reply, size: 14, color: theme.colorScheme.primary),
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
                              Icon(mediaIcon, size: 14, color: theme.colorScheme.onSurfaceVariant),
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
                     child: Image.network(imageUrl, width: 36, height: 36, fit: BoxFit.cover),
                   ),
                ),
            IconButton(
              icon: Icon(LucideIcons.x, size: 16, color: theme.colorScheme.onSurfaceVariant),
              onPressed: widget.onCancelReply,
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentPickerModal extends StatelessWidget {
  final VoidCallback onPickImage;
  final VoidCallback onPickCamera;
  final VoidCallback onPickVideo;
  final VoidCallback onPickDocument;
  final VoidCallback onPickAudio;
  final VoidCallback onPickLocation;

  const _AttachmentPickerModal({
    required this.onPickImage,
    required this.onPickCamera,
    required this.onPickVideo,
    required this.onPickDocument,
    required this.onPickAudio,
    required this.onPickLocation,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40), // Added bottom padding for extra safety
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Upload', style: theme.textTheme.titleLarge),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildButton(context, LucideIcons.camera, 'Camera', onPickCamera),
                _buildButton(context, LucideIcons.image, 'Photo', onPickImage),
                _buildButton(context, LucideIcons.video, 'Video', onPickVideo),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildButton(context, LucideIcons.music, 'Audio', onPickAudio),
                _buildButton(context, LucideIcons.fileText, 'Document', onPickDocument),
                _buildButton(context, LucideIcons.mapPin, 'Location', onPickLocation),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton(BuildContext context, IconData icon, String label, VoidCallback onTap) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 8),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

// [NEW] Mention List Item
class _MentionListItem extends ConsumerWidget {
  final String userId;
  final String query;
  final Function(String) onTap;
  final ProfileData? profileOverride; // [NEW]

  const _MentionListItem({
    required this.userId, 
    required this.query, 
    required this.onTap,
    this.profileOverride,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (profileOverride != null) {
       return _buildTile(profileOverride!);
    }

    final profileAsync = ref.watch(userProfileByIdProvider(userId));
    
    return profileAsync.when(
       data: (profile) => _buildTile(profile),
       error: (_,__) => const SizedBox.shrink(),
       loading: () => const SizedBox.shrink(), 
    );
  }

  Widget _buildTile(ProfileData? profile) {
      final name = '${profile?.firstName ?? ''} ${profile?.lastName ?? ''}'.trim();
      final displayName = name.isEmpty ? 'User' : name;
      
      // Filter here if using local ID list and no server search
      // Assuming server search handles filtering if active
      // But if falling back to IDs, we need to filter.
      // However logic has moved to _filterParticipants somewhat, but previously logic relied on this check.
      // We'll keep it for local ID mode.
      
      if (profileOverride == null && query.isNotEmpty && !displayName.toLowerCase().contains(query.toLowerCase())) {
         return const SizedBox.shrink(); 
      }

      return ListTile(
        leading: CircleAvatar(
          radius: 16,
          backgroundImage: (profile?.profileImage != null) ? NetworkImage(profile!.profileImage!) : null,
          child: (profile?.profileImage == null) ? Text(displayName.isNotEmpty ? displayName[0].toUpperCase() : '?') : null,
        ),
        title: Text(displayName),
        onTap: () => onTap(displayName), // Pass name back
      );
  }
}

// Ensure proper imports are added if missing.
// userProfileProvider needs to be found.
