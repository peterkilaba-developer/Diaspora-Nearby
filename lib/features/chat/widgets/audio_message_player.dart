import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lucide_icons/lucide_icons.dart';

class AudioMessagePlayer extends StatefulWidget {
  final String audioUrl;
  final int durationSeconds;
  final bool isOwn;

  const AudioMessagePlayer({
    super.key,
    required this.audioUrl,
    required this.durationSeconds,
    required this.isOwn,
  });

  @override
  State<AudioMessagePlayer> createState() => _AudioMessagePlayerState();
}

class _AudioMessagePlayerState extends State<AudioMessagePlayer> with AutomaticKeepAliveClientMixin {
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  bool _isLoading = false;

  @override
  Duration _totalDuration = Duration.zero;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _totalDuration = Duration(seconds: widget.durationSeconds);
    _initAudio();
  }

  Future<void> _initAudio() async {
    try {
      // Listen to player state
      _audioPlayer.playerStateStream.listen((state) {
        if (mounted) {
          setState(() {
            _isPlaying = state.playing;
            if (state.processingState == ProcessingState.completed) {
              _position = Duration.zero;
              _audioPlayer.pause();
              _audioPlayer.seek(Duration.zero);
            }
          });
        }
      });

      // Listen to position
      _audioPlayer.positionStream.listen((position) {
        if (mounted) {
          setState(() => _position = position);
        }
      });

      // Listen to duration
      _audioPlayer.durationStream.listen((duration) {
        if (mounted && duration != null && duration.inSeconds > 0) {
           // Update if we currently have 0 duration (uploaded file case)
           // or if the stream gives us a more accurate one.
           if (_totalDuration.inSeconds == 0 || duration != _totalDuration) {
             setState(() => _totalDuration = duration);
           }
        }
      });
    } catch (e) {
      debugPrint('Error init audio listener: $e');
    }
  }

  Future<void> _togglePlay() async {
    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        if (_audioPlayer.processingState == ProcessingState.idle) {
          setState(() => _isLoading = true);
      if (widget.audioUrl.startsWith('http') || widget.audioUrl.startsWith('file://')) {
             await _audioPlayer.setUrl(widget.audioUrl);
          } else {
             // Local file path (raw)
             await _audioPlayer.setFilePath(widget.audioUrl);
          }
          setState(() => _isLoading = false);
        }
        await _audioPlayer.play();
      }
    } catch (e) {
      debugPrint('Error playing audio: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Crucial for KeepAlive

    final theme = Theme.of(context);
    final contentColor = widget.isOwn
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;

    // Ensure position doesn't exceed total (visual glitch prevention)
    final currentPos = _position.inSeconds > _totalDuration.inSeconds
        ? _totalDuration
        : _position;

    return Container(
      width: 250,
      padding: const EdgeInsets.only(left: 12, right: 8, top: 16, bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Play/Pause Button
          GestureDetector(
            onTap: _togglePlay,
            child: _isLoading
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: contentColor,
                    ),
                  )
                : Icon(
                    _isPlaying ? LucideIcons.pause : LucideIcons.play,
                    color: contentColor,
                    size: 24,
                  ),
          ),
          const SizedBox(width: 8),
          
          // Slider
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: contentColor,
                inactiveTrackColor: contentColor.withValues(alpha: 0.3),
                thumbColor: contentColor,
                overlayColor: contentColor.withValues(alpha: 0.1),
              ),
              child: Slider(
                value: currentPos.inSeconds.toDouble(),
                max: _totalDuration.inSeconds.toDouble() > 0
                    ? _totalDuration.inSeconds.toDouble()
                    : 1.0,
                onChanged: (value) async {
                  final position = Duration(seconds: value.toInt());
                  await _audioPlayer.seek(position);
                },
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Duration Text (Current / Total)
          Text(
            '${_formatDuration(currentPos)} / ${_formatDuration(_totalDuration)}',
            style: TextStyle(
              color: contentColor,
              fontSize: 12,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
