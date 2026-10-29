import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';
import 'package:diaspora_nearby/features/radio/providers/radio_provider.dart';

final audioPlaybackServiceProvider = Provider<AudioPlaybackService>((ref) {
  return AudioPlaybackService(ref);
});

class AudioPlaybackService {
  final Ref _ref;

  static final Map<String, String> _localAudioCache = {};
  static final Set<String> _inFlightPrefetches = {};

  String? _currentId;
  String? get currentId => _currentId;

  final _idController = StreamController<String?>.broadcast();
  Stream<String?> get currentIdStream => _idController.stream;

  AudioPlayer get player => _player;
  final AudioPlayer _player = AudioPlayer();

  AudioPlaybackService(this._ref) {
    _ref.onDispose(() {
      _idController.close();
      _player.dispose();
    });
  }

  /// Pre-caches a remote audio URL to local disk so tapping Play starts in 0ms.
  Future<void> prefetchAudio(String url) async {
    if (kIsWeb || !url.startsWith('http')) return;
    if (_localAudioCache.containsKey(url) || _inFlightPrefetches.contains(url)) {
      return;
    }
    _inFlightPrefetches.add(url);
    try {
      final tempDir = await getTemporaryDirectory();
      final safeKey = url.hashCode.toUnsigned(32).toRadixString(16);
      final file = File('${tempDir.path}/dn_audio_$safeKey.m4a');
      if (file.existsSync() && file.lengthSync() > 0) {
        _localAudioCache[url] = file.path;
        return;
      }
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        await file.writeAsBytes(response.bodyBytes, flush: true);
        _localAudioCache[url] = file.path;
      }
    } catch (_) {
    } finally {
      _inFlightPrefetches.remove(url);
    }
  }

  /// Toggles play/pause for a specific audio ID and URL.
  Future<void> togglePlay(String id, String url) async {
    try {
      if (_currentId == id) {
        if (_player.playing) {
          await _player.pause();
        } else {
          if (_player.processingState == ProcessingState.completed) {
            await _player.seek(Duration.zero);
          }

          try {
            _ref.read(radioProvider.notifier).stop();
          } catch (_) {}

          unawaited(_player.play());
        }
      } else {
        try {
          _ref.read(radioProvider.notifier).stop();
        } catch (e) {
          debugPrint('⚠️ Could not auto-stop radio: $e');
        }

        _currentId = id;
        _idController.add(id);

        unawaited(_player.stop());

        Uri audioUri;
        final cachedLocalPath = !kIsWeb ? _localAudioCache[url] : null;
        if (cachedLocalPath != null && File(cachedLocalPath).existsSync()) {
          audioUri = Uri.file(cachedLocalPath);
        } else if (url.startsWith('http') || url.startsWith('blob:')) {
          audioUri = Uri.parse(url);
          unawaited(prefetchAudio(url));
        } else if (url.startsWith('file://')) {
          final fileUri = Uri.parse(url);
          final filePath = fileUri.toFilePath();
          if (!File(filePath).existsSync()) {
            throw Exception('Audio file missing');
          }
          audioUri = fileUri;
        } else {
          if (!File(url).existsSync()) {
            throw Exception('Audio file missing');
          }
          audioUri = Uri.file(url);
        }

        final source = AudioSource.uri(
          audioUri,
          tag: MediaItem(
            id: id,
            title: 'Audio Message',
          ),
        );

        await _player.setAudioSource(source);
        unawaited(_player.play());
      }
    } catch (e) {
      debugPrint('❌ Audio Playback Error: $e');
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
}
