import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:lucide_icons/lucide_icons.dart';

class VideoMessagePlayer extends StatefulWidget {
  final String videoUrl;
  final bool isOwn;

  const VideoMessagePlayer({
    super.key,
    required this.videoUrl,
    required this.isOwn,
  });

  @override
  State<VideoMessagePlayer> createState() => _VideoMessagePlayerState();
}

class _VideoMessagePlayerState extends State<VideoMessagePlayer>
    with AutomaticKeepAliveClientMixin {
  late VideoPlayerController _videoController;
  ChewieController? _chewieController;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      if (widget.videoUrl.startsWith('http') ||
          widget.videoUrl.startsWith('blob:') ||
          kIsWeb) {
        _videoController = VideoPlayerController.networkUrl(
          Uri.parse(widget.videoUrl),
        );
      } else {
        // Local file (Optimistic UI)
        String filePath = widget.videoUrl;
        if (filePath.startsWith('file://')) {
          filePath = filePath.substring(7);
        }
        _videoController = VideoPlayerController.file(File(filePath));
      }
      await _videoController.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoController,
        aspectRatio: _videoController.value.aspectRatio,
        autoPlay: false,
        looping: false,
        placeholder: Container(
          color: Colors.black,
          child: const Center(child: CircularProgressIndicator()),
        ),
        errorBuilder: (context, errorMessage) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.alertCircle, color: Colors.white),
                SizedBox(height: 8),
                Text(
                  'Error loading video',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          );
        },
      );

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('❌ Error initializing video: $e');
      if (mounted) {
        setState(() => _hasError = true);
      }
    }
  }

  @override
  void dispose() {
    _videoController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Crucial for KeepAlive

    if (_hasError) {
      return Container(
        width: double.infinity,
        height: 200,
        color: Colors.black12,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.videoOff,
                color: widget.isOwn ? Colors.white70 : Colors.black54,
              ),
              const SizedBox(height: 8),
              Text(
                'Video unavailable',
                style: TextStyle(
                  color: widget.isOwn ? Colors.white70 : Colors.black54,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized) {
      return Container(
        width: double.infinity,
        height: 200,
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    if (_videoController.value.aspectRatio == 0.0) {
      return const SizedBox(width: double.infinity, height: 200);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double aspectRatio = _videoController.value.aspectRatio;
        // Force full width
        final double width = constraints.maxWidth;
        // Calculate height based on aspect ratio
        double height = width / aspectRatio;

        // If height exceeds max constraint (e.g. 400 from parent), clamp it
        // Note: parent has maxHeight: 400 constraint usually.
        // If we just let it grow, it might be clipped or overflow.
        // We want it to be AT LEAST full width.
        // If the video is tall (portrait), height will be large.
        // We probably want to limit height to avoid super long messages.
        // If height exceeds max constraint, clamp it.
        // Increased to 600 to better accommodate portrait videos (9:16 on typical screens)
        if (height > 600) {
          height = 600;
        }

        return Container(
          width: width,
          height: height,
          color: Colors.black,
          child: Chewie(controller: _chewieController!),
        );
      },
    );
  }
}
