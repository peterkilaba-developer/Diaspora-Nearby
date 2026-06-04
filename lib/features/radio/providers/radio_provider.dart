import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'package:diaspora_nearby/features/radio/models/radio_station.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
import 'package:diaspora_nearby/features/chat/services/audio_playback_service.dart';
import '../repository/radio_repository.dart';

// State class
class RadioState {
  final RadioStation? currentStation;
  final bool isPlaying;
  final bool isLoading;
  final String? error;

  RadioState({
    this.currentStation,
    this.isPlaying = false,
    this.isLoading = false,
    this.error,
  });

  RadioState copyWith({
    RadioStation? currentStation,
    bool? isPlaying,
    bool? isLoading,
    String? error,
  }) {
    return RadioState(
      currentStation: currentStation ?? this.currentStation,
      isPlaying: isPlaying ?? this.isPlaying,
      isLoading: isLoading ?? this.isLoading,
      error: error, // Allow nulling error
    );
  }
}

// Notifier (Riverpod 2.0)
class RadioNotifier extends Notifier<RadioState> {
  late AudioPlayer _player;
  Timer? _successTimer;

  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<PlaybackEvent>? _eventSubscription;

  @override
  RadioState build() {
    // Initialize AudioPlayer here. Since build() is called when the provider
    // is first used (which is after main() runs), this ensures
    // JustAudioBackground.init() has been called.
    _player = AudioPlayer();

    // Manage listener lifecycle
    _initPlayer();

    // Ensure cleanup on dispose
    ref.onDispose(() {
      _successTimer?.cancel();
      _playerStateSubscription?.cancel();
      _eventSubscription?.cancel();
      _player.dispose(); // IMPORTANT: Dispose player on provider destruction
    });

    return RadioState();
  }

  void _initPlayer() {
    // Cancel any existing subscriptions to avoid duplicates on rebuild
    _playerStateSubscription?.cancel();
    _eventSubscription?.cancel();

    _playerStateSubscription = _player.playerStateStream.listen((playerState) {
      final isPlaying = playerState.playing;
      final processingState = playerState.processingState;

      if (processingState == ProcessingState.loading ||
          processingState == ProcessingState.buffering) {
        state = state.copyWith(isLoading: true, isPlaying: isPlaying);
      } else {
        state = state.copyWith(isLoading: false, isPlaying: isPlaying);
      }

      if (processingState == ProcessingState.completed) {
        stop();
      }
    });

    _eventSubscription = _player.playbackEventStream.listen(
      (event) {},
      onError: (Object e, StackTrace stackTrace) {
        debugPrint('ðŸ”´ Radio Playback Stream Error: $e');
        debugPrint('Stack: $stackTrace');
        _handlePlaybackError('Stream error: $e');
      },
    );
  }

  void _handlePlaybackError(String errorMsg) {
    final currentStation = state.currentStation;
    _successTimer?.cancel();

    if (currentStation != null) {
      ref
          .read(radioRepositoryProvider)
          .reportFailure(currentStation.stationuuid);
    }

    state = state.copyWith(error: errorMsg, isLoading: false, isPlaying: false);
  }

  Future<void> playStation(RadioStation station) async {
    final repo = ref.read(radioRepositoryProvider);

    // --- MUTUAL EXCLUSIVITY: STOP CHAT AUDIO ---
    try {
      ref.read(audioPlaybackServiceProvider).stopAll();
    } catch (e) {
      debugPrint('⚠️ Could not stop chat audio: $e');
    }
    // ------------------------------------------

    try {
      // Optimistic update
      state = state.copyWith(
        currentStation: station,
        isLoading: true,
        error: null,
      );

      _successTimer?.cancel();

      await _player.stop();

      // Use streamUrl which prefers url_resolved (pre-resolved direct stream)
      // over url (which may be a playlist or redirect chain).
      final streamUrl = station.streamUrl;
      debugPrint('🎵 Radio: Playing stream URL: $streamUrl');
      debugPrint('🎵 Radio: Original URL: ${station.url}');
      debugPrint('🎵 Radio: Resolved URL: ${station.urlResolved}');

      // Set Android-specific audio attributes for streaming optimization
      await _player.setAndroidAudioAttributes(
        const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
      );

      final source = AudioSource.uri(
        Uri.parse(streamUrl),
        tag: MediaItem(
          id: station.stationuuid,
          album: "Diaspora Nearby Radio",
          title: station.name,
          artUri: station.favicon.isNotEmpty
              ? Uri.tryParse(station.favicon)
              : null,
        ),
      );

      // Explicitly preload to start buffering immediately
      await _player.setAudioSource(source, preload: true);
      await _player.play();

      // Start Success Timer (15 seconds)
      _successTimer = Timer(const Duration(seconds: 15), () {
        final user = ref.read(authStateProvider).value;

        // Report Success
        repo.reportSuccess(station.stationuuid);

        // Add to history (only if it played successfully for 15s)
        if (user != null) {
          repo.addToHistory(user.uid, station);
          ref.invalidate(recentStationsProvider);
        }
      });
    } catch (e, stackTrace) {
      debugPrint('ðŸ”´ Radio Play Error: $e');
      debugPrint('Stack: $stackTrace');
      _handlePlaybackError("Failed to play: $e");
    }
  }

  Future<void> stop() async {
    _successTimer?.cancel();
    await _player.stop();
    // Reset state completely to hide the player (currentStation = null)
    state = RadioState();
  }

  Future<void> pause() async {
    _successTimer?.cancel();
    await _player.pause();
    state = state.copyWith(isPlaying: false);
  }

  Future<void> resume() async {
    if (state.currentStation != null) {
      await _player.play();
      state = state.copyWith(isPlaying: true);
    }
  }
}

final radioProvider = NotifierProvider<RadioNotifier, RadioState>(
  RadioNotifier.new,
);

// --- New Providers for Tabs & Search ---

class SelectedCountryNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setCountry(String? country) => state = country;
}

final selectedCountryProvider =
    NotifierProvider<SelectedCountryNotifier, String?>(
      SelectedCountryNotifier.new,
    );

final recentStationsProvider = FutureProvider<List<RadioStation>>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return [];
  final repo = ref.watch(radioRepositoryProvider);
  return repo.getHistory(user.uid);
});

final favoriteStationsProvider = FutureProvider<List<RadioStation>>((
  ref,
) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return [];
  final repo = ref.watch(radioRepositoryProvider);
  return repo.getFavorites(user.uid);
});
