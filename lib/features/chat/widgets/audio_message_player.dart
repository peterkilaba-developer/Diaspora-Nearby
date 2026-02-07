import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'dart:async';
import 'package:diaspora_nearby/features/chat/services/audio_playback_service.dart';

class AudioMessagePlayer extends ConsumerStatefulWidget {
  final String messageId; // Unique ID for this audio (message ID or preview ID)
  final String audioUrl;
  final int durationSeconds;
  final bool isOwn;
  final Color? foregroundColor;

  const AudioMessagePlayer({
    super.key,
    required this.messageId,
    required this.audioUrl,
    required this.durationSeconds,
    required this.isOwn,
    this.foregroundColor,
  });

  @override
  ConsumerState<AudioMessagePlayer> createState() => _AudioMessagePlayerState();
}

class _AudioMessagePlayerState extends ConsumerState<AudioMessagePlayer>
    with AutomaticKeepAliveClientMixin {
  // Local state for UI updates
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _isLoading = false;

  StreamSubscription? _playerStateSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _idSub;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _totalDuration = Duration(seconds: widget.durationSeconds);
    // Defer initialization to after build to access ref
    WidgetsBinding.instance.addPostFrameCallback((_) => _initAudioListeners());
  }

  void _initAudioListeners() {
    final service = ref.read(audioPlaybackServiceProvider);

    // 1. Listen to active ID changes
    _idSub = service.currentIdStream.listen((activeId) {
      if (mounted) {
        final isMe = activeId == widget.messageId;
        if (isMe != _isPlaying) {
          // If I was playing and now I'm not (someone else started), stop UI
          // If I wasn't playing and now I am (started by me), start UI
          // But actually playing state comes from playerStateStream, this just tells us IF we are the one attached
          if (!isMe) {
            setState(() {
              _isPlaying = false;
              _position = Duration.zero;
            });
          }
        }
      }
    });

    // 2. Listen to player state
    _playerStateSub = service.player.playerStateStream.listen((state) {
      if (mounted && service.currentId == widget.messageId) {
        setState(() {
          _isPlaying = state.playing;
          // Reset on complete
          if (state.processingState == ProcessingState.completed) {
            _isPlaying = false;
            _position = Duration.zero;
          }
        });
      }
    });

    // 3. Listen to position
    _positionSub = service.player.positionStream.listen((pos) {
      if (mounted && service.currentId == widget.messageId) {
        setState(() => _position = pos);
      }
    });

    // 4. Listen to duration (optional, mostly for remote files)
    _durationSub = service.player.durationStream.listen((d) {
      if (mounted && service.currentId == widget.messageId && d != null) {
        if (_totalDuration.inSeconds == 0 || d != _totalDuration) {
          setState(() => _totalDuration = d);
        }
      }
    });
  }

  @override
  void didUpdateWidget(AudioMessagePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.audioUrl != oldWidget.audioUrl) {
      _totalDuration = Duration(seconds: widget.durationSeconds);
      // If URL changed, we should probably stop if we were playing.
      // The service will handle stop if we try to play new URL.
    }
  }

  Future<void> _togglePlay() async {
    final service = ref.read(audioPlaybackServiceProvider);
    try {
      setState(() => _isLoading = true);
      await service.togglePlay(widget.messageId, widget.audioUrl);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Playback failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _idSub?.cancel();
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
    final contentColor =
        widget.foregroundColor ??
        (widget.isOwn
            ? theme.colorScheme.onPrimary
            : theme.colorScheme.onSurface);

    // Background for play button (semitransparent play button bg)
    final playButtonBg = contentColor.withValues(alpha: 0.2);

    // Ensure position doesn't exceed total (visual glitch prevention)
    final currentPos = _position.inSeconds > _totalDuration.inSeconds
        ? _totalDuration
        : _position;

    // Countdown Timer Logic
    String displayTimeText;
    if (_isPlaying) {
      // Countdown: Total - Current
      final remaining = _totalDuration - currentPos;
      // Clamp to zero to avoid negative glitch at end
      final displayRemaining = remaining.isNegative ? Duration.zero : remaining;
      displayTimeText = _formatDuration(displayRemaining);
    } else {
      // Revert to Total Play Time when not playing
      displayTimeText = _formatDuration(_totalDuration);
    }

    return Container(
      width: 250,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center, // Align with play button in middle
        children: [
          // Play/Pause Button
          GestureDetector(
            onTap: _togglePlay,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: playButtonBg,
                shape: BoxShape.circle,
              ),
              child: _isLoading
                  ? Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: contentColor,
                      ),
                    )
                  : Icon(
                      _isPlaying ? LucideIcons.pause : LucideIcons.play,
                      color: contentColor,
                      size: 18,
                    ),
            ),
          ),
          const SizedBox(width: 8),

          // Slider aligned with button
          Expanded(
            child: SizedBox(
              height: 24, // Enough for touch target
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 0,
                  ),
                  activeTrackColor: contentColor,
                  inactiveTrackColor: contentColor.withValues(alpha: 0.3),
                  thumbColor: contentColor,
                  trackShape: _CustomTrackShape(),
                ),
                child: Slider(
                  value: currentPos.inSeconds.toDouble(),
                  max: _totalDuration.inSeconds.toDouble() > 0
                      ? _totalDuration.inSeconds.toDouble()
                      : 1.0,
                  onChanged: (value) async {
                    final service = ref.read(audioPlaybackServiceProvider);
                    if (service.currentId == widget.messageId) {
                      final position = Duration(seconds: value.toInt());
                      await service.player.seek(position);
                    }
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Timer at the end
          Text(
            displayTimeText,
            style: TextStyle(
              color: contentColor.withValues(alpha: 0.8),
              fontSize: 12,
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// Custom track shape to remove default padding
class _CustomTrackShape extends RoundedRectSliderTrackShape {
  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackHeight = sliderTheme.trackHeight!;
    final double trackLeft = offset.dx;
    final double trackTop =
        offset.dy + (parentBox.size.height - trackHeight) / 2;
    final double trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }
}
