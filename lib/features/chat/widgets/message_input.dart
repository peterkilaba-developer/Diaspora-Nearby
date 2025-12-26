import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:diaspora_nearby/models/message.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:just_audio/just_audio.dart' as ja; // Alias to avoid conflict with record


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
  });

  @override
  ConsumerState<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends ConsumerState<MessageInput> {
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
  
  // Playback State
  bool _isPlaying = false;
  Duration _playbackPosition = Duration.zero;
  Duration _playbackDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    
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

  void _onTextChanged() {
    setState(() {
      _canSend = _controller.text.trim().isNotEmpty;
    });
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
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
        
        // Auto-focus triggering keyboard
        if (mounted) {
             _focusNode.requestFocus();
        }
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

  Future<void> _sendRecordedAudio() async {
    if (_recordedFile != null && await _recordedFile!.exists()) {
      // Use current text as caption if any
      final caption = _controller.text.trim().isNotEmpty ? _controller.text.trim() : null;
      widget.onSendAudio(_recordedFile!, _recordDurationSeconds, caption: caption);
      
      _controller.clear();
      _cancelRecording(deleteFile: false); // Reset state but keep file for upload
    }
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
    final picker = ImagePicker();
    List<File> files = [];

    if (type == 'image') {
      if (source == ImageSource.camera) {
         final photo = await picker.pickImage(source: source);
         if (photo != null) files.add(File(photo.path));
      } else {
         final images = await picker.pickMultiImage();
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
      });
      _focusNode.requestFocus();
    }
  }

  Future<void> _pickDocument() async {
    Navigator.pop(context);
    final result = await fp.FilePicker.platform.pickFiles(
      type: fp.FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'txt', 'xls', 'xlsx'],
    );
    if (result != null && result.files.single.path != null && mounted) {
      setState(() {
        _pendingAttachments = [File(result.files.single.path!)];
        _pendingAttachmentType = 'document';
      });
      _focusNode.requestFocus();
    }
  }

  Future<void> _pickAudio() async {
    Navigator.pop(context);
    final result = await fp.FilePicker.platform.pickFiles(type: fp.FileType.audio);
    if (result != null && result.files.single.path != null && mounted) {
      setState(() {
        _pendingAttachments = [File(result.files.single.path!)];
        // Distinguish picked audio file from voice recording if needed, or treat same?
        // Method signature is onSendAudioFile vs onSendAudio(voice).
        // Let's use 'audio_file' to distinguish internally if needed, or just 'audio' and check context?
        // To be safe, let's use 'audio_file'.
        _pendingAttachmentType = 'audio_file';
      });
      _focusNode.requestFocus();
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(top: BorderSide(color: theme.dividerColor, width: 0.5)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.reply, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replying to',
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
                ),
                Text(
                  widget.replyingTo?.content ?? 'Media',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: widget.onCancelReply,
            icon: const Icon(LucideIcons.x, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
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
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 8),
          Text(label, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}
