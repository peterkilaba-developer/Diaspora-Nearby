import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';
import 'package:diaspora_nearby/features/chat/models/message.dart';

class ChatMediaViewerScreen extends StatefulWidget {
  final Message message;
  final String videoUrl;

  const ChatMediaViewerScreen({
    super.key,
    required this.message,
    required this.videoUrl,
  });

  @override
  State<ChatMediaViewerScreen> createState() => _ChatMediaViewerScreenState();
}

class _ChatMediaViewerScreenState extends State<ChatMediaViewerScreen> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      final isLocal =
          widget.videoUrl.startsWith('/') ||
          widget.videoUrl.startsWith('file://');

      _videoPlayerController = isLocal
          ? VideoPlayerController.file(
              File(widget.videoUrl.replaceFirst('file://', '')),
            )
          : VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));

      await _videoPlayerController!.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: true,
        looping: false,
        showControls: true,
        aspectRatio: _videoPlayerController!.value.aspectRatio,
        allowFullScreen: true,
        allowMuting: true,
      );

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      extendBodyBehindAppBar: true,
      body: Center(
        child: _hasError
            ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.videoOff, color: Colors.white54, size: 48),
                  SizedBox(height: 16),
                  Text(
                    'Failed to load video',
                    style: TextStyle(color: Colors.white54),
                  ),
                ],
              )
            : _isInitialized && _chewieController != null
            ? Hero(
                tag: 'video_${widget.message.id}',
                child: Chewie(controller: _chewieController!),
              )
            : const CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}
