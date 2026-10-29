import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

import '../database/database_service.dart';
import '../services/discord_rpc_service.dart';
import 'local_file_audio_source.dart';
import 'position_data.dart';
import '../../features/wave/services/wave_service.dart';

/// Source mode of the current audio queue to isolate Wave streaming from library tracks.
enum AudioSourceMode { library, wave, custom }

/// NCmus playback engine.
///
/// Owns a real queue, local/remote source resolution, volume persistence and
/// automatic advancement when a track reaches [ProcessingState.completed].
class NCPlayerHandler extends BaseAudioHandler with SeekHandler {
  static const String _volumeKey = 'app_volume';
  static const double _defaultVolume = 0.8;

  final AudioPlayer _player = AudioPlayer();
  final DiscordRpcService _discordRpc = DiscordRpcService.instance;

  final List<MediaItem> _queue = <MediaItem>[];
  List<MediaItem> _originalQueue = <MediaItem>[];
  bool _isShuffleActive = false;
  bool get isShuffleActive => _isShuffleActive;

  /// Current audio source mode distinguishing library vs infinite wave.
  AudioSourceMode currentSourceMode = AudioSourceMode.library;

  int _currentIndex = -1;

  /// Optional attached wave service instance for blacklist coordination.
  dynamic waveService;

  final Set<String> _blacklist = <String>{};

  bool _handlingCompletion = false;
  bool _volumeTouchedByUser = false;

  double _lastAudibleVolume = _defaultVolume;
  double _volumeBeforeDuck = _defaultVolume;
  Timer? _volumePersistTimer;
  Timer? _historyTimer;
  String? _loggedHistoryTrackKey;

  NCPlayerHandler() {
    _initAudioSession();
    _initStreams();
    _initDiscordRpc();
    unawaited(_restoreSavedVolume());
    unawaited(_restoreSavedBlacklist());
  }

  Future<void> _restoreSavedBlacklist() async {
    try {
      final raw = await DatabaseService.instance.getSyncMeta('wave_blacklist');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _blacklist.addAll(decoded.map((e) => e.toString()));
        }
      }
    } catch (_) {}
  }

  void _initDiscordRpc() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      unawaited(DiscordRpcService.instance.init());
    }
  }

  // ---------------------------------------------------------------------------
  // Public state
  // ---------------------------------------------------------------------------
  List<MediaItem> get queueItems => List<MediaItem>.unmodifiable(_queue);

  int get currentIndex => _currentIndex;

  MediaItem? get currentItem => mediaItem.value;

  bool get hasNext => _currentIndex >= 0 && _currentIndex < _queue.length - 1;

  bool get hasPrevious => _currentIndex > 0;

  Duration get currentPosition => _player.position;

  Duration get currentDuration => _player.duration ?? Duration.zero;

  /// The UI listens to this for the mute icon and volume sliders.
  Stream<double> get volumeStream => _player.volumeStream;

  double get currentVolume => _player.volume;

  bool get isMuted => _player.volume <= 0.001;

  /// Direct stream of PlaybackState for UI components (e.g. CyberFluidOrb).
  Stream<PlaybackState> get playbackStateStream => playbackState;

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------
  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());

      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _volumeBeforeDuck = _player.volume;
              if (_player.volume > 0.001) {
                unawaited(_player.setVolume(_player.volume / 2));
              }
              break;
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              unawaited(pause());
              break;
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              unawaited(_player.setVolume(_volumeBeforeDuck));
              break;
            case AudioInterruptionType.pause:
              unawaited(play());
              break;
            case AudioInterruptionType.unknown:
              break;
          }
        }
      });

      session.becomingNoisyEventStream.listen((_) {
        unawaited(pause());
      });
    } catch (_) {
      // AudioSession is not available on every desktop configuration.
    }
  }

  void _initStreams() {
    _player.playbackEventStream.listen(
      _broadcastPlaybackState,
      onError: (Object error, StackTrace stackTrace) {
        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.error,
            errorMessage: error.toString(),
          ),
        );
      },
    );

    _player.playerStateStream.listen(_handlePlayerState);

    _player.durationStream.listen((duration) {
      final current = mediaItem.value;
      if (current != null &&
          duration != null &&
          duration > Duration.zero &&
          current.duration != duration) {
        final resolved = current.copyWith(duration: duration);
        mediaItem.add(resolved);
        if (_currentIndex >= 0 && _currentIndex < _queue.length) {
          _queue[_currentIndex] = resolved;
          queue.add(List<MediaItem>.unmodifiable(_queue));
        }
      }
    });

    _player.volumeStream.listen((volume) {
      if (volume > 0.001) {
        _lastAudibleVolume = volume;
      }
    });

    mediaItem.listen((item) {
      if (item != null) {
        _discordRpc.updatePresence(
          title: item.title,
          artist: item.artist ?? 'NCmus',
          isPlaying: _player.playing,
          position: _player.position,
          duration: item.duration ?? _player.duration,
        );
      } else {
        _discordRpc.clear();
      }
    });
  }

  Future<void> _restoreSavedVolume() async {
    double value = _defaultVolume;
    try {
      final raw = await DatabaseService.instance.getSyncMeta(_volumeKey);
      final parsed = double.tryParse(raw ?? '');
      if (parsed != null) {
        value = parsed.clamp(0.0, 1.0).toDouble();
      }
    } catch (_) {
      // A missing database must never prevent playback.
    }

    if (_volumeTouchedByUser) return;
    if (value > 0.001) {
      _lastAudibleVolume = value;
    }
    await _player.setVolume(value);
  }

  // ---------------------------------------------------------------------------
  // Queue
  // ---------------------------------------------------------------------------

  /// Replaces the queue and starts playing [initialIndex].
  ///
  /// Guarantees that previous playback is stopped, the queue is replaced,
  /// and playback is forcefully started even if the player was previously paused.
  Future<void> setQueueAndPlay(
    List<MediaItem> items,
    int initialIndex, {
    AudioSourceMode? mode,
  }) async {
    if (mode != null) {
      currentSourceMode = mode;
    }
    // 1. Force stop previous playback before mutating queue
    await _player.stop();

    if (!_isShuffleActive) {
      _originalQueue = List<MediaItem>.from(items);
    }

    if (items.isEmpty) {
      _queue.clear();
      _currentIndex = -1;
      queue.add(const <MediaItem>[]);
      mediaItem.add(null);
      _broadcastPlaybackState();
      return;
    }

    final safeIndex = initialIndex.clamp(0, items.length - 1).toInt();

    // 2. Replace queue
    _queue
      ..clear()
      ..addAll(items);
    _currentIndex = safeIndex;
    queue.add(List<MediaItem>.unmodifiable(_queue));

    // 3. Load item and forcefully start playback
    await _loadQueueItem(safeIndex);
    try {
      await _player.play().timeout(
            const Duration(milliseconds: 150),
            onTimeout: () {},
          );
    } catch (_) {
      unawaited(_player.play());
    }
  }

  /// Запуск воспроизведения с честной перетасовкой всей очереди (Фишер-Йетс)
  Future<void> playShuffledQueue(List<MediaItem> items, {int startIndex = 0}) async {
    if (items.isEmpty) return;
    currentSourceMode = AudioSourceMode.library;
    _originalQueue = List.from(items);
    _isShuffleActive = true;

    final shuffledList = List<MediaItem>.from(items)..shuffle();
    if (startIndex > 0 && startIndex < items.length) {
      final selected = items[startIndex];
      shuffledList.remove(selected);
      shuffledList.insert(0, selected);
    }

    queue.add(shuffledList);
    await setQueueAndPlay(shuffledList, 0);
    playbackState.add(playbackState.value.copyWith(
      shuffleMode: AudioServiceShuffleMode.all,
    ));
  }

  /// Переключение Shuffle-режима на лету (для кнопок в плеерах)
  Future<void> toggleShuffleMode() async {
    _isShuffleActive = !_isShuffleActive;
    final currentItem = mediaItem.value;

    if (_isShuffleActive) {
      if (_originalQueue.isEmpty) {
        _originalQueue = List<MediaItem>.from(queue.value);
      }
      final currentQueue = List<MediaItem>.from(queue.value)..shuffle();
      if (currentItem != null) {
        currentQueue.remove(currentItem);
        currentQueue.insert(0, currentItem);
      }
      await setQueueAndPlay(currentQueue, 0);
      playbackState.add(playbackState.value.copyWith(
        shuffleMode: AudioServiceShuffleMode.all,
      ));
    } else {
      if (_originalQueue.isNotEmpty && currentItem != null) {
        final originalIndex = _originalQueue.indexWhere((e) => e.id == currentItem.id);
        final targetIndex = originalIndex >= 0 ? originalIndex : 0;
        await setQueueAndPlay(_originalQueue, targetIndex);
      }
      playbackState.add(playbackState.value.copyWith(
        shuffleMode: AudioServiceShuffleMode.none,
      ));
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final shouldBeActive = shuffleMode == AudioServiceShuffleMode.all ||
        shuffleMode == AudioServiceShuffleMode.group;
    if (shouldBeActive != _isShuffleActive) {
      await toggleShuffleMode();
    }
  }

  /// Clears the queue, resets playback, and notifies listeners.
  Future<void> clearQueue() async {
    await _player.stop();
    _queue.clear();
    _originalQueue.clear();
    _isShuffleActive = false;
    _currentIndex = -1;
    queue.add(const <MediaItem>[]);
    mediaItem.add(null);
    _historyTimer?.cancel();
    _historyTimer = null;
    _loggedHistoryTrackKey = null;
    _broadcastPlaybackState();
  }

  /// Dislikes [item], saving to SQLite blacklist and skipping playback.
  Future<void> dislikeCurrentTrack([MediaItem? item]) =>
      blacklistCurrentTrack(item);

  /// Blacklists [item] (or the current active track if null), saving its hash to
  /// memory and SQLite, stopping current playback and immediately skipping to next.
  Future<void> blacklistCurrentTrack([MediaItem? item]) async {
    final target = item ?? mediaItem.value;
    if (target == null) return;

    if (waveService != null) {
      try {
        await (waveService as dynamic).dislikeCurrentTrack(target);
        return;
      } catch (_) {}
    }

    final artist = target.artist?.trim() ?? '';
    final title = target.title.trim();
    await DatabaseService.instance.addToBlacklist(title, artist);

    final hash = '${artist.toLowerCase()} - ${title.toLowerCase()}';
    _blacklist.add(hash);
    if (target.extras?['originalId'] != null) {
      _blacklist.add(target.extras!['originalId'].toString());
    }
    _blacklist.add(target.id);

    try {
      await DatabaseService.instance.setSyncMeta(
        'wave_blacklist',
        jsonEncode(_blacklist.toList()),
      );
    } catch (_) {}

    await skipToNext();
  }

  /// Removes [item] (or the current active track) from the blacklist.
  Future<void> removeFromBlacklist([MediaItem? item]) async {
    final target = item ?? mediaItem.value;
    if (target == null) return;

    final artist = target.artist?.trim() ?? '';
    final title = target.title.trim();
    await DatabaseService.instance.removeFromBlacklist(title, artist);

    final hash = '${artist.toLowerCase()} - ${title.toLowerCase()}';
    _blacklist.remove(hash);
    if (target.extras?['originalId'] != null) {
      _blacklist.remove(target.extras!['originalId'].toString());
    }
    _blacklist.remove(target.id);

    try {
      await DatabaseService.instance.setSyncMeta(
        'wave_blacklist',
        jsonEncode(_blacklist.toList()),
      );
    } catch (_) {}
  }

  /// Appends [items] to the existing queue without interrupting playback.
  Future<void> appendToQueue(List<MediaItem> items) async {
    if (items.isEmpty) return;
    _queue.addAll(items);
    queue.add(List<MediaItem>.unmodifiable(_queue));
    _broadcastPlaybackState();
  }

  @override
  Future<void> skipToNext() async {
    if (currentSourceMode == AudioSourceMode.wave) {
      await WaveService.instance.playNextWaveTrack();
      return;
    }
    if (_queue.isEmpty) return;
    if (_currentIndex >= _queue.length - 1) return;
    await _loadQueueItem(_currentIndex + 1);
  }

  @override
  Future<void> skipToPrevious() async {
    if (_queue.isEmpty) return;

    // The familiar media-player behaviour: a short press restarts the track,
    // a press near the beginning jumps to the previous queue item.
    if (_player.position > const Duration(seconds: 3) || _currentIndex <= 0) {
      await seek(Duration.zero);
      return;
    }

    await _loadQueueItem(_currentIndex - 1);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _queue.length) return;
    await _loadQueueItem(index);
  }

  /// Kept for compatibility with callers that play one track directly.
  /// If the item already belongs to the queue, its queue position is reused.
  @override
  Future<void> playMediaItem(MediaItem item) async {
    currentSourceMode = AudioSourceMode.library;
    try {
      (waveService as dynamic)?.stopWave();
    } catch (_) {}

    final index = _queue.indexWhere((candidate) => _sameTrack(candidate, item));

    if (index >= 0) {
      _currentIndex = index;
      final isAlreadyLoaded =
          mediaItem.value != null && _sameTrack(mediaItem.value!, item);

      if (isAlreadyLoaded) {
        _broadcastPlaybackState();
        await play();
      } else {
        await _loadQueueItem(index);
      }
      return;
    }

    await setQueueAndPlay(<MediaItem>[item], 0);
  }

  Future<void> _loadQueueItem(int index) async {
    if (index < 0 || index >= _queue.length) return;

    _historyTimer?.cancel();
    _historyTimer = null;
    _loggedHistoryTrackKey = null;

    final requested = _queue[index];
    _currentIndex = index;

    // Update the UI immediately so track changes feel instant while the
    // decoder is still opening the file/stream.
    mediaItem.add(requested);
    _broadcastPlaybackState();

    final hasLocalFile = _hasUsableLocalFile(requested);
    final remoteUri = _remoteUri(requested);

    try {
      await _player.stop();

      Duration? duration;
      try {
        duration = await _player.setAudioSource(
          _createAudioSource(requested, preferLocal: true),
        );
      } catch (error) {
        // A corrupt/missing local file should transparently fall back to the
        // remote mirror instead of killing the queue.
        if (!hasLocalFile || remoteUri == null) rethrow;

        await _player.stop();
        duration = await _player.setAudioSource(
          _createAudioSource(requested, preferLocal: false),
        );
      }

      final resolved = duration != null && duration > Duration.zero
          ? requested.copyWith(duration: duration)
          : requested;

      _queue[index] = resolved;
      mediaItem.add(resolved);
      queue.add(List<MediaItem>.unmodifiable(_queue));
      _broadcastPlaybackState();

      // Deliberately not awaited: just_audio's play() future completes when
      // playback finishes, which would hold callers open for the whole track.
      unawaited(play());
    } catch (error) {
      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.error,
          errorMessage: error.toString(),
        ),
      );
      rethrow;
    }
  }

  void _handlePlayerState(PlayerState state) {
    _broadcastPlaybackState();
    _updateHistoryTracking(state);

    if (state.processingState != ProcessingState.completed ||
        _handlingCompletion) {
      return;
    }

    _handlingCompletion = true;
    unawaited(_handleTrackCompletion());
  }

  void _updateHistoryTracking(PlayerState state) {
    final item = mediaItem.value;
    if (item == null) {
      _historyTimer?.cancel();
      _historyTimer = null;
      return;
    }

    final trackKey = '${item.id}_$_currentIndex';

    if (!state.playing ||
        (state.processingState != ProcessingState.ready &&
            state.processingState != ProcessingState.buffering)) {
      _historyTimer?.cancel();
      _historyTimer = null;
      return;
    }

    if (_loggedHistoryTrackKey == trackKey) {
      return;
    }

    _historyTimer ??= Timer(const Duration(seconds: 25), () async {
      final current = mediaItem.value;
      if (current != null &&
          _player.playing &&
          _loggedHistoryTrackKey != trackKey) {
        _loggedHistoryTrackKey = trackKey;
        try {
          await DatabaseService.instance.logPlayHistory(current);
        } catch (_) {}
      }
    });
  }

  Future<void> _handleTrackCompletion() async {
    try {
      if (currentSourceMode == AudioSourceMode.wave) {
        await WaveService.instance.playNextWaveTrack();
      } else if (hasNext) {
        await skipToNext();
      } else {
        // End of queue: stop at the beginning of the last track rather than
        // spinning on the completed state.
        await _player.pause();
        await _player.seek(Duration.zero);
        _broadcastPlaybackState();
      }
    } catch (_) {
      // The error is already published to playbackState.
    } finally {
      _handlingCompletion = false;
    }
  }

  /// Safely pauses and sets player processing state to idle when Wave has no tracks available.
  Future<void> handleWaveExhausted() async {
    try {
      await _player.pause();
    } catch (_) {}
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
  }

  AudioSource _createAudioSource(
    MediaItem item, {
    required bool preferLocal,
  }) {
    final localPath = item.extras?['localPath'] as String?;

    if (preferLocal && localPath != null && localPath.isNotEmpty) {
      final file = File(localPath);
      if (file.existsSync() && file.lengthSync() > 0) {
        if (Platform.isWindows) {
          return LocalFileAudioSource(file, tag: item);
        }
        return AudioSource.file(file.path, tag: item);
      }
    }

    final uri = _remoteUri(item);
    if (uri == null) {
      throw StateError('Track "${item.title}" has no playable source.');
    }

    return AudioSource.uri(uri, tag: item);
  }

  bool _hasUsableLocalFile(MediaItem item) {
    final localPath = item.extras?['localPath'] as String?;
    if (localPath == null || localPath.isEmpty) return false;

    final file = File(localPath);
    return file.existsSync() && file.lengthSync() > 0;
  }

  Uri? _remoteUri(MediaItem item) {
    final streamUrl = item.extras?['streamUrl'] as String?;
    final candidate =
        (streamUrl != null && streamUrl.isNotEmpty) ? streamUrl : item.id;
    final uri = Uri.tryParse(candidate);
    if (uri == null || !uri.hasScheme) return null;
    return uri;
  }

  bool _sameTrack(MediaItem a, MediaItem b) {
    final aOriginal = a.extras?['originalId']?.toString();
    final bOriginal = b.extras?['originalId']?.toString();
    if (aOriginal != null && bOriginal != null) {
      return aOriginal == bOriginal;
    }
    return a.id == b.id;
  }

  // ---------------------------------------------------------------------------
  // Volume
  // ---------------------------------------------------------------------------

  Future<void> setVolume(double volume) async {
    _volumeTouchedByUser = true;
    final normalized = volume.clamp(0.0, 1.0).toDouble();

    if (normalized > 0.001) {
      _lastAudibleVolume = normalized;
    }

    await _player.setVolume(normalized);
    _scheduleVolumePersist(normalized);
  }

  Future<void> toggleMute() async {
    _volumeTouchedByUser = true;

    if (_player.volume > 0.001) {
      _lastAudibleVolume = _player.volume;
      await _player.setVolume(0);
      _scheduleVolumePersist(0);
    } else {
      final restore =
          _lastAudibleVolume > 0.001 ? _lastAudibleVolume : _defaultVolume;
      await _player.setVolume(restore);
      _scheduleVolumePersist(restore);
    }
  }

  void _scheduleVolumePersist(double volume) {
    _volumePersistTimer?.cancel();
    _volumePersistTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(_persistVolume(volume));
    });
  }

  Future<void> _persistVolume(double volume) async {
    try {
      await DatabaseService.instance.setSyncMeta(
        _volumeKey,
        volume.toStringAsFixed(3),
      );
    } catch (_) {
      // Persisting volume is best-effort.
    }
  }

  // ---------------------------------------------------------------------------
  // BaseAudioHandler
  // ---------------------------------------------------------------------------
  @override
  Future<void> play() async {
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
    }
    return _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  void _broadcastPlaybackState([PlaybackEvent? event]) {
    final playing = _player.playing;
    final processingState = const <ProcessingState, AudioProcessingState>{
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[_player.processingState] ??
        AudioProcessingState.idle;

    playbackState.add(
      playbackState.value.copyWith(
        controls: <MediaControl>[
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        systemActions: const <MediaAction>{
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
        },
        androidCompactActionIndices: const <int>[0, 1, 3],
        processingState: processingState,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _currentIndex >= 0 ? _currentIndex : null,
        shuffleMode: _isShuffleActive
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
      ),
    );

    final current = mediaItem.value;
    if (current != null) {
      _discordRpc.updatePresence(
        title: current.title,
        artist: current.artist ?? 'NCmus',
        isPlaying: playing,
        position: _player.position,
        duration: current.duration ?? _player.duration,
      );
    } else {
      _discordRpc.clear();
    }
  }

  Stream<PositionData> get positionDataStream =>
      Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
        _player.positionStream,
        _player.bufferedPositionStream,
        _player.durationStream,
        (position, bufferedPosition, duration) => PositionData(
          position,
          bufferedPosition,
          duration ?? Duration.zero,
        ),
      );

  Future<void> dispose() async {
    _historyTimer?.cancel();
    _volumePersistTimer?.cancel();
    _discordRpc.dispose();
    await _player.dispose();
    await super.stop();
  }

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    if (name == 'dispose') {
      await dispose();
      return true;
    }
    return super.customAction(name, extras);
  }
}
