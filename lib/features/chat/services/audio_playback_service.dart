import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:diaspora_nearby/features/radio/providers/radio_provider.dart';

final audioPlaybackServiceProvider = Provider<AudioPlaybackService>((ref) {
  return AudioPlaybackService(ref);
});

class AudioPlaybackService {
  final Ref _ref;

  // Track currently playing audio ID (mostly for UI)
  String? _currentId;
  String? get currentId => _currentId;

  // Stream for UI to listen to changes
  final _idController = StreamController<String?>.broadcast();
  Stream<String?> get currentIdStream => _idController.stream;

  AudioPlayer get player => _player;
  final AudioPlayer _player = AudioPlayer();

  AudioPlaybackService(this._ref);

  /// Toggles play/pause for a specific audio ID and URL.
  /// If [id] matches current, it toggles play/pause.
  /// If [id] is different, it stops current, loads new URL, and plays.
  Future<void> togglePlay(String id, String url) async {
    try {
      if (_currentId == id) {
        if (_player.playing) {
          await _player.pause();
        } else {
          // Check/Stop Radio availability before resuming
          // We need to stop radio if it holds the background session
           
          // If finished, seek to start
          if (_player.processingState == ProcessingState.completed) {
            await _player.seek(Duration.zero);
          }
          
           // --- MUTUAL EXCLUSIVITY ---
          try {
             _ref.read(radioProvider.notifier).stop(); 
          } catch (e) { /* ignore */ }
          // --------------------------

          await _player.play();
        }
      } else {
        // New audio
        
        // 1. Stop Radio (Mutual Exclusivity)
        try {
          _ref.read(radioProvider.notifier).stop(); 
        } catch (e) {
          debugPrint('⚠️ Could not auto-stop radio: $e');
        }

        await _player.stop();
        _currentId = id;
        _idController.add(id);

        debugPrint('▶️ Loading audio: $id ($url)');

        Uri audioUri;
        if (url.startsWith('http') || url.startsWith('blob:')) {
          audioUri = Uri.parse(url);
        } else if (url.startsWith('file://')) {
          final fileUri = Uri.parse(url);
          final filePath = fileUri.toFilePath();
          if (!File(filePath).existsSync()) {
            debugPrint('❌ Audio file missing at: $filePath');
            throw Exception('Audio file missing');
          }
          audioUri = fileUri;
        } else {
          // Raw path
          if (!File(url).existsSync()) {
            debugPrint('❌ Audio file missing at: $url');
            throw Exception('Audio file missing');
          }
          audioUri = Uri.file(url);
        }

        // Attach MediaItem tag required by just_audio_background
        final source = AudioSource.uri(
          audioUri,
          tag: MediaItem(
            id: id,
            title: 'Audio Message',
            // artUri: Uri.parse('https://example.com/albumart.jpg'), // Optional
          ),
        );

        await _player.setAudioSource(source);
        _player.play(); // Don't await play to avoid UI blocking if buffering
      }
    } catch (e) {
      debugPrint('❌ Audio Playback Error: $e');
      // Reset state if error occurs during load
      if (_currentId == id) {
        _currentId = null;
        _idController.add(null);
      }
      rethrow;
    }
  }

  /// Stop specific audio if it's playing
  Future<void> stop(String id) async {
    if (_currentId == id) {
      await _player.stop();
      _currentId = null;
      _idController.add(null);
    }
  }

  /// Stop whatever is playing
  Future<void> stopAll() async {
    await _player.stop();
    _currentId = null;
    _idController.add(null);
  }

  void dispose() {
    _idController.close();
    _player.dispose();
  }
}
