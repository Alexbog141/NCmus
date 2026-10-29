// ignore_for_file: avoid_print
import 'dart:io' show Platform;

import 'package:audio_service/audio_service.dart';
import 'package:discord_rpc/discord_rpc.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

/// Data structure representing parsed and formatted Discord Presence.
class DiscordPresenceData {
  final String details;
  final String state;
  final String largeImageKey;
  final String largeImageText;
  final String smallImageKey;
  final String smallImageText;
  final int? startTimeStamp;
  final int? endTimeStamp;

  const DiscordPresenceData({
    required this.details,
    required this.state,
    required this.largeImageKey,
    required this.largeImageText,
    required this.smallImageKey,
    required this.smallImageText,
    this.startTimeStamp,
    this.endTimeStamp,
  });

  int? get startTime => startTimeStamp;
  int? get endTime => endTimeStamp;
}

/// Discord Rich Presence (RPC) service for NCmus desktop clients.
class DiscordRpcService {
  static final DiscordRpcService instance = DiscordRpcService();

  static const String defaultClientId = '1564377192845279463';
  static const String defaultApplicationId = defaultClientId;
  static const String prefKey = 'discord_rpc_enabled';

  final String applicationId;
  DiscordRPC? _rpc;
  bool _isConnected = false;
  bool _isInitialized = false;
  bool _isEnabled = true;
  bool _isConnecting = false;
  DiscordPresenceData? _lastPresence;

  DiscordRpcService({this.applicationId = defaultClientId});

  bool get isConnected => _isConnected;
  bool get isInitialized => _isInitialized;
  bool get isEnabled => _isEnabled;
  DiscordPresenceData? get lastPresence => _lastPresence;

  bool get isDesktopPlatform =>
      !kIsWeb && Platform.isWindows;

  /// Loads enabled state from SharedPreferences (defaults to true).
  Future<void> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey(prefKey)) {
        await prefs.setBool(prefKey, true);
        _isEnabled = true;
      } else {
        _isEnabled = prefs.getBool(prefKey) ?? true;
      }
    } catch (_) {
      _isEnabled = true;
    }
  }

  /// Sets whether Discord RPC is enabled and persists to SharedPreferences.
  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefKey, enabled);
    } catch (_) {}

    if (!enabled) {
      clear();
    } else {
      if (!_isConnected) {
        await init();
      }
    }
  }

  /// Registers and initializes the Discord RPC client on supported desktop platforms.
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey(prefKey)) {
        await prefs.setBool(prefKey, true);
        _isEnabled = true;
      } else {
        _isEnabled = prefs.getBool(prefKey) ?? true;
      }
    } catch (_) {
      _isEnabled = true;
    }

    if (kIsWeb || !Platform.isWindows) {
      print('[DiscordRPC] RPC поддерживается только на Windows');
      return;
    }

    if (!_isEnabled) {
      print('[DiscordRPC] RPC отключен в настройках');
      return;
    }

    if (_isConnected && _rpc != null) {
      return;
    }

    if (_isConnecting) {
      return;
    }

    _isConnecting = true;
    try {
      DiscordRPC.initialize();
      _rpc = DiscordRPC(applicationId: defaultClientId);
      _rpc?.start(autoRegister: true);
      _isConnected = true;
      _isInitialized = true;
      print('[DiscordRPC] Соединение установлено. Application ID: $defaultClientId');
    } catch (e) {
      _isConnected = false;
      _isInitialized = false;
      print('[DiscordRPC] Ошибка запуска RPC: $e');
    } finally {
      _isConnecting = false;
    }
  }

  /// Backwards-compatible initialize method.
  void initialize() {
    if (kIsWeb || !Platform.isWindows) {
      print('[DiscordRPC] RPC поддерживается только на Windows');
      return;
    }

    if (!_isEnabled) {
      return;
    }

    if (_isConnected && _rpc != null) {
      return;
    }

    try {
      DiscordRPC.initialize();
      _rpc = DiscordRPC(applicationId: defaultClientId);
      _rpc?.start(autoRegister: true);
      _isConnected = true;
      _isInitialized = true;
      print('[DiscordRPC] Соединение установлено. Application ID: $defaultClientId');
    } catch (e) {
      _isConnected = false;
      _isInitialized = false;
      print('[DiscordRPC] Ошибка запуска RPC: $e');
    }
  }

  /// Builds a [DiscordPresenceData] model without requiring a live Discord socket.
  DiscordPresenceData buildPresenceData({
    required String title,
    required String artist,
    required bool isPlaying,
    Duration? position,
    Duration? duration,
    DateTime? currentTime,
  }) {
    final now = currentTime ?? DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;

    int? startTimestamp;
    int? endTimestamp;

    if (isPlaying) {
      final posMs = position?.inMilliseconds ?? 0;
      startTimestamp = nowMs - posMs;
      if (duration != null && duration > Duration.zero) {
        endTimestamp = startTimestamp + duration.inMilliseconds;
      }
    }

    final safeTitle = title.trim().isNotEmpty ? title.trim() : 'Unknown Track';
    final safeArtist = artist.trim().isNotEmpty ? artist.trim() : 'NCmus';

    return DiscordPresenceData(
      details: safeTitle.length > 128
          ? '${safeTitle.substring(0, 125)}...'
          : safeTitle,
      state: safeArtist.length > 128
          ? '${safeArtist.substring(0, 125)}...'
          : safeArtist,
      largeImageKey: 'ncmus_logo',
      largeImageText: 'NCmus · Cyber Audio',
      smallImageKey: isPlaying ? 'play' : 'pause',
      smallImageText: isPlaying ? 'Воспроизведение' : 'Пауза',
      startTimeStamp: startTimestamp,
      endTimeStamp: endTimestamp,
    );
  }

  /// Updates Discord presence according to active playback metadata and timestamps.
  void updatePresence({
    String? title,
    String? artist,
    MediaItem? item,
    required bool isPlaying,
    Duration? position,
    Duration? duration,
  }) {
    artist ??= item?.artist ?? 'NCmus';
    title ??= item?.title ?? 'Unknown Track';
    final effectiveDuration = duration ?? item?.duration;

    print('[DiscordRPC] Обновление статуса: $artist - $title (isPlaying: $isPlaying)');

    final data = buildPresenceData(
      title: title,
      artist: artist,
      isPlaying: isPlaying,
      position: position,
      duration: effectiveDuration,
    );
    _lastPresence = data;

    if (kIsWeb || !Platform.isWindows) {
      return;
    }

    if (!_isEnabled || !_isConnected || _rpc == null) {
      return;
    }

    try {
      _rpc?.updatePresence(
        DiscordPresence(
          details: data.details,
          state: data.state,
          startTimeStamp: data.startTimeStamp,
          endTimeStamp: data.endTimeStamp,
          largeImageKey: data.largeImageKey,
          largeImageText: data.largeImageText,
          smallImageKey: data.smallImageKey,
          smallImageText: data.smallImageText,
        ),
      );
    } catch (_) {
      // IPC communication errors are handled gracefully.
    }
  }

  /// Backwards-compatible helper for MediaItem.
  void updatePresenceFromItem({
    required MediaItem? item,
    required bool isPlaying,
    required Duration position,
  }) {
    if (item == null) {
      clear();
      return;
    }
    updatePresence(
      title: item.title,
      artist: item.artist ?? 'NCmus',
      isPlaying: isPlaying,
      position: position,
      duration: item.duration,
    );
  }

  /// Clears presence on Discord client.
  void clear() {
    _lastPresence = null;
    if (kIsWeb || !Platform.isWindows) return;
    if (!_isConnected || _rpc == null) return;
    try {
      _rpc?.clearPresence();
    } catch (_) {}
  }

  /// Shuts down the RPC connection.
  void dispose() {
    clear();
    if (kIsWeb || !Platform.isWindows) return;
    try {
      _rpc?.shutDown();
    } catch (_) {}
    _rpc = null;
    _isConnected = false;
    _isInitialized = false;
  }
}
