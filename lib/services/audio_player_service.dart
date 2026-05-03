import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:just_audio_background/just_audio_background.dart';

import '../database/database_helper.dart';
import '../models/repeat_mode.dart';
import '../models/track_model.dart';

/// Identifies the UI surface that started playback (`"library"`,
/// `"liked"`, `"history"`, or `"playlist:{id}"`). Used by track tiles to
/// highlight the currently-playing row only in the surface where playback
/// was initiated, so e.g. playing from a playlist doesn't also light up
/// the same track in the main library.
typedef PlaybackContextId = String;

/// Wraps [ja.AudioPlayer] with queue, repeat, shuffle, volume, history hooks
/// and a "playback context" string used for per-surface UI highlighting.
///
/// CRITICAL: When repeat is OFF, intercepts currentIndexStream to prevent auto-advance.
/// This ensures playback stops after the current track completes.
class AudioPlayerService extends ChangeNotifier {
  /// Creates the service; call [init] once before use.
  AudioPlayerService() : _player = ja.AudioPlayer();

  final ja.AudioPlayer _player;
  final DatabaseHelper _db = DatabaseHelper.instance;

  /// Expose the player for external access if needed.
  ja.AudioPlayer get player => _player;

  /// Ordered list currently driving playback.
  List<TrackModel> _queue = [];

  /// Repeat behavior for boundaries and single-track loop.
  RepeatMode repeatMode = RepeatMode.off;

  /// Volume in the range 0.0–1.0 (maps to UI 0–100%).
  double volume = 1;

  /// Whether the player is fully initialized and ready.
  bool isLoading = true;

  /// Whether shuffle mode is currently active.
  bool _shuffleEnabled = false;

  /// Public read-only view of [_shuffleEnabled].
  bool get shuffleEnabled => _shuffleEnabled;

  /// Identifier of the surface that started current playback (see
  /// [PlaybackContextId]). `null` when nothing is playing.
  PlaybackContextId? _playbackContextId;

  /// Public getter for the current playback context.
  PlaybackContextId? get playbackContextId => _playbackContextId;

  /// Track the last known index to detect unwanted auto-advance
  int? _lastKnownIndex;

  /// Flag to prevent recursive pause calls
  bool _isHandlingIndexChange = false;

  /// The active queue (unmodifiable view).
  List<TrackModel> get queue => List.unmodifiable(_queue);

  // ============================================================================
  // REACTIVE STREAMS - SINGLE SOURCE OF TRUTH
  // ============================================================================

  /// Stream of the currently playing track (reactive).
  Stream<TrackModel?> get currentTrackStream {
    return _player.currentIndexStream.map((index) {
      if (index == null || _queue.isEmpty || index < 0 || index >= _queue.length) {
        return null;
      }
      return _queue[index];
    });
  }

  /// Stream of playback position (for progress bar).
  Stream<Duration> get positionStream => _player.positionStream;

  /// Stream of track duration (for progress bar).
  Stream<Duration?> get durationStream => _player.durationStream;

  /// Stream of playing state (for play/pause button).
  Stream<bool> get playingStream => _player.playingStream;

  /// Stream of processing state (for ready checks).
  Stream<ja.ProcessingState> get processingStateStream =>
      _player.playerStateStream.map((state) => state.processingState);

  /// Stream of buffered position (for buffer indicator).
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;

  /// Stream of volume changes (for volume slider).
  Stream<double> get volumeStream => _player.volumeStream;

  /// Stream of loop mode changes (for repeat button).
  Stream<ja.LoopMode> get loopModeStream => _player.loopModeStream;

  // ============================================================================
  // LEGACY GETTERS
  // ============================================================================

  /// Current track or null if the queue is empty.
  TrackModel? get currentTrack {
    if (_queue.isEmpty) return null;
    final actualIndex = _player.currentIndex;
    if (actualIndex == null || actualIndex < 0 || actualIndex >= _queue.length) {
      return null;
    }
    return _queue[actualIndex];
  }

  /// Latest known position for UI.
  Duration get position => _player.position;

  /// Latest known total duration.
  Duration get duration => _player.duration ?? Duration.zero;

  /// Whether the engine is actively playing audio.
  bool get playing => _player.playing;

  /// Whether the player is ready to accept commands.
  bool get isReady {
    final state = _player.processingState;
    return state == ja.ProcessingState.ready ||
           state == ja.ProcessingState.buffering ||
           state == ja.ProcessingState.loading;
  }

  /// Configures session category and wires player streams.
  Future<void> init() async {
    isLoading = true;
    notifyListeners();

    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    await _player.setVolume(volume);
    await _player.setLoopMode(ja.LoopMode.off);

    // Listen to index changes for history recording AND to wake up Provider
    // listeners (context.watch<AudioPlayerService>()) so the mini-player /
    // track tiles rebuild when next/previous switches the active track.
    _player.currentIndexStream.listen((index) {
      // Notify listeners on EVERY index change so widgets that read
      // `currentTrack` synchronously (e.g. the now-playing highlight in
      // track tiles, the mobile mini-player title row) repaint immediately.
      notifyListeners();

      if (index != null && index >= 0 && index < _queue.length) {
        _recordPlayForTrack(_queue[index]);

        // Detect unwanted auto-advance when repeat is OFF
        if (!_isHandlingIndexChange &&
            _lastKnownIndex != null &&
            index != _lastKnownIndex &&
            repeatMode == RepeatMode.off) {
          _isHandlingIndexChange = true;
          debugPrint('AudioPlayerService: Auto-advance detected ($_lastKnownIndex -> $index) with repeat OFF - STOPPING');

          // Pause immediately and go back to the previous track
          _player.pause().then((_) {
            _player.seek(Duration.zero, index: _lastKnownIndex);
            _isHandlingIndexChange = false;
          });
        } else {
          _lastKnownIndex = index;
        }
      }
    });

    // CRITICAL FIX: Listen to player state to handle track completion
    _player.playerStateStream.listen((state) {
      // When track completes and repeat is OFF, stop playback completely
      if (state.processingState == ja.ProcessingState.completed &&
          repeatMode == RepeatMode.off) {
        debugPrint('AudioPlayerService: Track completed with repeat OFF - stopping playback');
        _player.pause();
        _player.seek(Duration.zero);
      }
    });

    isLoading = false;
    notifyListeners();
  }

  /// Replaces the queue and optionally starts at [startIndex].
  ///
  /// [contextId] identifies the UI surface that started this playback (see
  /// [PlaybackContextId]). Track tiles use it to decide whether to render the
  /// "now playing" highlight, so the same track playing from a playlist
  /// doesn't also light up in the main library.
  Future<void> setQueue(
    List<TrackModel> tracks, {
    int startIndex = 0,
    bool playImmediately = true,
    PlaybackContextId? contextId,
  }) async {
    if (tracks.isEmpty) {
      await stop();
      return;
    }

    _queue = List<TrackModel>.from(tracks);
    _playbackContextId = contextId;
    final safeIndex = startIndex.clamp(0, _queue.length - 1);
    _lastKnownIndex = safeIndex;

    final playlist = ja.ConcatenatingAudioSource(
      children: _queue.map((t) {
        // Create MediaItem for mobile platforms
        final mediaItem = MediaItem(
          id: t.id?.toString() ?? t.filePath,
          album: 'Library',
          title: t.title,
          artist: t.artist,
          duration: t.durationMs > 0 ? Duration(milliseconds: t.durationMs) : null,
        );

        // CRITICAL: Only use tag on mobile to avoid sequence validation errors
        return Platform.isAndroid || Platform.isIOS
            ? ja.AudioSource.file(t.filePath, tag: mediaItem)
            : ja.AudioSource.file(t.filePath);
      }).toList(),
    );

    try {
      await _player.setAudioSource(playlist, initialIndex: safeIndex);
      // Re-apply shuffle state to the new source.
      await _player.setShuffleModeEnabled(_shuffleEnabled);
      if (_shuffleEnabled) {
        // Generate a fresh shuffled order, keeping the chosen track current.
        await _player.shuffle();
      }
      if (playImmediately) {
        await _player.play();
      }
    } catch (e) {
      debugPrint('AudioPlayerService: failed to load queue: $e');
      rethrow;
    }
    notifyListeners();
  }

  /// Plays a single track from a list context.
  ///
  /// [contextId] identifies the surface that initiated playback so the now-
  /// playing highlight only appears in that surface (e.g. a track in a
  /// playlist won't also light up in the main library).
  Future<void> playTrackInContext(
    TrackModel clickedTrack,
    List<TrackModel> contextTracks, {
    PlaybackContextId? contextId,
  }) async {
    final clickedIndex = contextTracks.indexWhere(
      (t) => t.id == clickedTrack.id,
    );
    if (clickedIndex == -1) {
      await setQueue(
        [clickedTrack],
        playImmediately: true,
        contextId: contextId,
      );
      return;
    }
    await setQueue(
      contextTracks,
      startIndex: clickedIndex,
      playImmediately: true,
      contextId: contextId,
    );
  }

  /// Toggles play/pause for a specific track.
  ///
  /// When the clicked track is already current AND [contextId] matches the
  /// current playback context, this only toggles play/pause. Otherwise it
  /// starts a new playback session in [contextId].
  Future<void> togglePlayTrack(
    TrackModel clickedTrack,
    List<TrackModel> contextTracks, {
    PlaybackContextId? contextId,
  }) async {
    final current = currentTrack;
    final sameContext = contextId == null ||
        _playbackContextId == null ||
        _playbackContextId == contextId;

    if (current?.id != null &&
        current?.id == clickedTrack.id &&
        sameContext) {
      if (playing) {
        await pause();
      } else {
        await play();
      }
      return;
    }

    await playTrackInContext(
      clickedTrack,
      contextTracks,
      contextId: contextId,
    );
  }

  /// Appends tracks without changing the current item.
  void appendToQueue(List<TrackModel> tracks) {
    _queue.addAll(tracks);
    notifyListeners();
  }

  /// Clears playback state.
  Future<void> stop() async {
    await _player.stop();
    _queue = [];
    _lastKnownIndex = null;
    _playbackContextId = null;
    notifyListeners();
  }

  /// Updates repeat mode with IMMEDIATE effect and UI update.
  Future<void> setRepeatMode(RepeatMode mode) async {
    repeatMode = mode;
    notifyListeners();

    final loopMode = switch (mode) {
      RepeatMode.off => ja.LoopMode.off,
      RepeatMode.all => ja.LoopMode.all,
      RepeatMode.one => ja.LoopMode.one,
    };
    await _player.setLoopMode(loopMode);

    debugPrint('AudioPlayerService: Repeat mode set to $mode');
  }

  /// Cycles repeat mode: off → all → one → off
  Future<void> cycleRepeatMode() async {
    final nextMode = switch (repeatMode) {
      RepeatMode.off => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.off,
    };
    await setRepeatMode(nextMode);
  }

  /// Gets current repeat mode (for UI).
  RepeatMode get currentRepeatMode => repeatMode;

  /// Toggles shuffle mode on/off.
  ///
  /// When enabled: just_audio randomizes the queue order; previous/next
  /// traverse the shuffled sequence (so the back-stack of already-played
  /// tracks is preserved). When disabled: returns to the original queue
  /// order. The current track always keeps playing, regardless of state.
  ///
  /// The state is also remembered when the queue is empty, so toggling
  /// before selecting the first track still "sticks" once a queue gets
  /// loaded (see the apply in [setQueue]).
  Future<void> toggleShuffle() async {
    _shuffleEnabled = !_shuffleEnabled;
    notifyListeners();

    // No source yet? Remember the preference; it's re-applied in setQueue.
    if (_queue.isEmpty) return;

    try {
      await _player.setShuffleModeEnabled(_shuffleEnabled);
      if (_shuffleEnabled) {
        // Generate a fresh shuffled order; just_audio anchors it on the
        // current item so playback doesn't jump.
        await _player.shuffle();
      }
    } catch (e) {
      debugPrint('AudioPlayerService: failed to toggle shuffle: $e');
      // Roll back the boolean if the engine call failed so UI stays in sync.
      _shuffleEnabled = !_shuffleEnabled;
      notifyListeners();
    }
  }

  /// Starts or resumes the current source.
  Future<void> play() async {
    if (currentTrack == null) return;

    if (!isReady) {
      debugPrint('AudioPlayerService: Cannot play - player not ready');
      return;
    }

    await _player.play();
  }

  /// Pauses playback.
  Future<void> pause() async {
    await _player.pause();
  }

  /// Seeks within the current track.
  Future<void> seek(Duration target) async {
    if (!isReady) {
      debugPrint('AudioPlayerService: Cannot seek - player not ready');
      return;
    }

    final maxDuration = _player.duration;
    if (maxDuration == null || maxDuration == Duration.zero) {
      debugPrint('AudioPlayerService: Cannot seek - duration unknown');
      return;
    }

    final safeDuration = target < Duration.zero
        ? Duration.zero
        : (target > maxDuration ? maxDuration : target);

    try {
      await _player.seek(safeDuration);
    } catch (e) {
      debugPrint('AudioPlayerService: Seek failed: $e');
    }
  }

  /// Sets output volume (0.0–1.0) with INSTANT effect.
  Future<void> setVolumeLinear(double v) async {
    volume = v.clamp(0.0, 1.0);
    notifyListeners();
    await _player.setVolume(volume);
  }

  /// Moves to the next track.
  Future<void> skipNext() async {
    if (_queue.isEmpty) return;

    final currentIdx = _player.currentIndex ?? 0;
    final isLastTrack = currentIdx >= _queue.length - 1;

    // When repeat is OFF and we're at the last track, do nothing
    if (repeatMode == RepeatMode.off && isLastTrack) {
      debugPrint('AudioPlayerService: At last track with repeat OFF - not advancing');
      return;
    }

    // Update last known index before seeking
    if (!isLastTrack) {
      _lastKnownIndex = currentIdx + 1;
    } else if (repeatMode == RepeatMode.all) {
      _lastKnownIndex = 0;
    }

    await _player.seekToNext();
    // Wake up Provider listeners immediately so the mini-player title /
    // artist / now-playing highlight repaint without waiting for the index
    // stream's next async tick.
    notifyListeners();
  }

  /// Moves to the previous track.
  Future<void> skipPrevious() async {
    if (_queue.isEmpty) return;

    // Restart current track if more than 2.5s in
    if (_player.position.inMilliseconds > 2500) {
      await _player.seek(Duration.zero);
      return;
    }

    final currentIdx = _player.currentIndex ?? 0;
    final isFirstTrack = currentIdx <= 0;

    // When repeat is OFF and we're at the first track, just restart
    if (repeatMode == RepeatMode.off && isFirstTrack) {
      await _player.seek(Duration.zero);
      return;
    }

    // Update last known index before seeking
    if (!isFirstTrack) {
      _lastKnownIndex = currentIdx - 1;
    } else if (repeatMode == RepeatMode.all) {
      _lastKnownIndex = _queue.length - 1;
    }

    await _player.seekToPrevious();
    // Same rationale as skipNext: notify on user-initiated track change so
    // the UI repaints synchronously instead of one frame late.
    notifyListeners();
  }

  /// Records play history for a specific track.
  Future<void> _recordPlayForTrack(TrackModel track) async {
    if (track.id == null) return;

    try {
      await _db.recordPlay(track.id!);

      final d = _player.duration;
      if (d != null && d > Duration.zero && track.durationMs == 0) {
        await _db.updateTrack(
          track.copyWith(durationMs: d.inMilliseconds),
        );
      }
    } catch (e) {
      debugPrint('AudioPlayerService: failed to record play: $e');
    }
  }

  @override
  void dispose() {
    // Stop playback and clear all streams immediately
    _player.stop();
    _player.dispose();
    super.dispose();
  }
}
