import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import 'package:diaspora_nearby/models/radio_station.dart';
import 'package:diaspora_nearby/features/auth/repository/auth_repository.dart';
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

// Global singleton player
final _globalAudioPlayer = AudioPlayer();

// Notifier (Riverpod 2.0)
class RadioNotifier extends Notifier<RadioState> {
  late AudioPlayer _player;
  Timer? _successTimer;
  
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<PlaybackEvent>? _eventSubscription;
  
  @override
  RadioState build() {
    _player = _globalAudioPlayer;
    
    // Manage listener lifecycle
    _initPlayer();
    
    // Ensure cleanup on dispose
    ref.onDispose(() {
      _successTimer?.cancel();
      _playerStateSubscription?.cancel();
      _eventSubscription?.cancel();
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

       if (processingState == ProcessingState.loading || processingState == ProcessingState.buffering) {
         state = state.copyWith(isLoading: true, isPlaying: isPlaying);
       } else {
         state = state.copyWith(isLoading: false, isPlaying: isPlaying);
       }
       
       if (processingState == ProcessingState.completed) {
          stop();
       }
    });

    _eventSubscription = _player.playbackEventStream.listen((event) {},
        onError: (Object e, StackTrace stackTrace) {
      _handlePlaybackError('Stream error');
    });
  }

  void _handlePlaybackError(String errorMsg) {
      final currentStation = state.currentStation;
      _successTimer?.cancel();

      if (currentStation != null) {
        ref.read(radioRepositoryProvider).reportFailure(currentStation.stationuuid);
      }

      state = state.copyWith(error: errorMsg, isLoading: false, isPlaying: false);
  }

  Future<void> playStation(RadioStation station) async {
    final repo = ref.read(radioRepositoryProvider);

    try {
      // Optimistic update
      state = state.copyWith(
        currentStation: station, 
        isLoading: true, 
        error: null
      );
      
      _successTimer?.cancel();

      await _player.stop();
      
      // Use AudioSource with MediaItem for notification metadata
      final source = AudioSource.uri(
        Uri.parse(station.url),
      );
      
      await _player.setAudioSource(source);
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
      
    } catch (e) {
      _handlePlaybackError("Failed to play station");
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

final radioProvider = NotifierProvider<RadioNotifier, RadioState>(RadioNotifier.new);

// --- New Providers for Tabs & Search ---

class SelectedCountryNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setCountry(String? country) => state = country;
}

final selectedCountryProvider = NotifierProvider<SelectedCountryNotifier, String?>(SelectedCountryNotifier.new);

final recentStationsProvider = FutureProvider<List<RadioStation>>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return [];
  final repo = ref.watch(radioRepositoryProvider);
  return repo.getHistory(user.uid);
});

final favoriteStationsProvider = FutureProvider<List<RadioStation>>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return [];
  final repo = ref.watch(radioRepositoryProvider);
  return repo.getFavorites(user.uid);
});
