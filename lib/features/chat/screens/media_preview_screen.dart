import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:diaspora_nearby/features/chat/widgets/message_input.dart'; // [NEW]

class MediaPreviewScreen extends ConsumerStatefulWidget {
  final List<XFile> files;
  final String type; // 'image' or 'video'
  final String? initialCaption; // [NEW]
  final Function(List<XFile> files, String? caption) onSend;

  const MediaPreviewScreen({
    super.key,
    required this.files,
    required this.type,
    this.initialCaption, // [NEW]
    required this.onSend,
  });

  @override
  ConsumerState<MediaPreviewScreen> createState() => _MediaPreviewScreenState();
}

class _MediaPreviewScreenState extends ConsumerState<MediaPreviewScreen>
    with WidgetsBindingObserver {
  final TextEditingController _captionController = TextEditingController();
  late PageController _pageController;
  int _currentIndex = 0;
  VideoPlayerController? _videoController;
  bool _isPlaying = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController();
    _captionController.text = widget.initialCaption ?? ''; // [NEW] Pre-fill

    if (widget.type == 'video' && widget.files.isNotEmpty) {
      _initializeVideo(widget.files.first);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_videoController != null && _videoController!.value.isPlaying) {
        _videoController!.pause();
        setState(() => _isPlaying = false);
      }
    }
  }

  Future<void> _initializeVideo(XFile file) async {
    if (kIsWeb) {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(file.path));
    } else {
      _videoController = VideoPlayerController.file(File(file.path));
    }

    try {
      await _videoController!.initialize();
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      debugPrint('Error initializing video: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _captionController.dispose();
    _pageController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  void _handleSend() {
    widget.onSend(widget.files, _captionController.text.trim());
    Navigator.pop(context); // Close preview
  }

  void _toggleVideo() {
    if (_videoController == null || !_isInitialized) return;

    setState(() {
      if (_videoController!.value.isPlaying) {
        _videoController!.pause();
        _isPlaying = false;
      } else {
        _videoController!.play();
        _isPlaying = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isVideo = widget.type == 'video';

    return Scaffold(
      backgroundColor:
          theme.scaffoldBackgroundColor, // [FIX] Use theme background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            LucideIcons.x,
            color: theme.colorScheme.onSurface,
          ), // [FIX] Use theme color
          onPressed: () => Navigator.pop(context),
        ),
        actions: const [
          // Crop/Edit tools could go here
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Content
          Center(
            child: isVideo
                ? _buildVideoPlayer()
                : PageView.builder(
                    controller: _pageController,
                    itemCount: widget.files.length,
                    onPageChanged: (index) =>
                        setState(() => _currentIndex = index),
                    itemBuilder: (context, index) {
                      final file = widget.files[index];
                      return kIsWeb
                          ? Image.network(file.path, fit: BoxFit.contain)
                          : Image.file(File(file.path), fit: BoxFit.contain);
                    },
                  ),
          ),

          // Indicators for multiple images
          if (!isVideo && widget.files.length > 1)
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.files.length, (index) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _currentIndex == index
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withValues(
                              alpha: 0.2,
                            ), // [FIX] Visible on white
                    ),
                  );
                }),
              ),
            ),

          // Caption and Send Bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: MessageInput(
              // [FIX] Removed redundant SafeArea (MessageInput handles it)
              chatId: 'preview', // Dummy ID
              controller: _captionController,
              onSendMessage: (text, {type, metadata}) {
                // [FIX] Use `text` directly — it was captured by MessageInput
                // BEFORE clearing the shared controller. Re-reading
                // _captionController here would return '' due to the race.
                widget.onSend(
                    widget.files, text.isNotEmpty ? text : null);
                Navigator.pop(context);
              },
              onSendMedia: (_, _, _) {}, // Disabled here
              onSendAudio: (_, _, {caption}) {}, // Disabled
              onSendAudioFile: (_, _) {},
              onSendDocument: (_, _) {},
              // onSendLocation: null, // Optional now
              onSendDSP: (_, _, _) {},
              onCancelReply: () {},
              showAttachmentButton: false, // Hide attachments
              showAudioRecording: false, // Hide audio
              canAlwaysSend: true, // [NEW] Always enable send button
              hintText: 'Add a caption...',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPlayer() {
    if (!_isInitialized || _videoController == null) {
      return const CircularProgressIndicator(color: Colors.white);
    }

    return AspectRatio(
      aspectRatio: _videoController!.value.aspectRatio,
      child: Stack(
        alignment: Alignment.center,
        children: [
          VideoPlayer(_videoController!),
          // Play/Pause Overlay
          GestureDetector(
            onTap: _toggleVideo,
            child: Container(
              color: Colors.transparent, // Hit area
              width: double.infinity,
              height: double.infinity,
              child: Center(
                child: !_isPlaying
                    ? Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          LucideIcons.play,
                          color: Colors.white,
                          size: 48,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
