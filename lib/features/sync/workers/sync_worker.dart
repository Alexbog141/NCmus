import 'dart:async';

import '../../../core/database/database_service.dart';
import '../models/sync_snapshot.dart';
import '../services/cloud_sync_service.dart';

/// Worker responsible for background and on-demand synchronization
/// following the Local-First architectural pattern.
class SyncWorker {
  static final SyncWorker instance = SyncWorker._internal();

  final DatabaseService dbService;
  final CloudSyncService cloudService;

  String? currentUsername;
  String? currentPassword;
  Timer? _periodicTimer;
  bool _isSyncing = false;

  bool get isSyncing => _isSyncing;

  SyncWorker._internal()
      : dbService = DatabaseService.instance,
        cloudService = CloudSyncService();

  SyncWorker({
    DatabaseService? dbService,
    CloudSyncService? cloudService,
  })  : dbService = dbService ?? DatabaseService.instance,
        cloudService = cloudService ?? CloudSyncService();

  /// Starts recurring background sync.
  void startPeriodicSync({
    required String username,
    required String password,
    Duration interval = const Duration(seconds: 90),
  }) {
    currentUsername = username;
    currentPassword = password;
    stopPeriodicSync();

    // Trigger an immediate sync run
    unawaited(syncNow());

    _periodicTimer = Timer.periodic(interval, (_) {
      syncNow();
    });
  }

  /// Stops recurring background sync.
  void stopPeriodicSync() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  /// Executes a single synchronization cycle.
  ///
  /// Returns `true` if changes were pushed or pulled and applied,
  /// `false` if nothing needed syncing, credentials were missing, or on error.
  Future<bool> syncNow() async {
    if (_isSyncing) return false;

    final user = currentUsername;
    final pass = currentPassword;
    if (user == null || user.isEmpty || pass == null || pass.isEmpty) {
      return false;
    }

    _isSyncing = true;
    try {
      final outboxEntries = await dbService.getOutboxEntries();

      // Step A: If local changes are pending in outbox, push current state to cloud
      if (outboxEntries.isNotEmpty) {
        final tracks = await dbService.getAllTracks();
        final localVersion = await dbService.getLocalDbVersion();
        final blacklist = await dbService.getBlacklistRaw();
        final playlists = await dbService.getPlaylistsForSync();
        final snapshot = SyncSnapshot.fromDatabase(
          version: localVersion,
          tracks: tracks,
          playlists: playlists,
          blacklist: blacklist,
        );

        final newVersion = await cloudService.pushSnapshot(
          username: user,
          password: pass,
          snapshot: snapshot,
        );

        if (newVersion != null) {
          await dbService.clearOutbox();
          await dbService.setLocalDbVersion(newVersion);
          return true;
        }
        return false;
      }

      // Step B: Outbox is empty, check if remote server has a newer snapshot
      final remoteVersion = await cloudService.checkRemoteVersion(username: user);
      final localVersion = await dbService.getLocalDbVersion();

      if (remoteVersion > localVersion) {
        final remoteSnapshot = await cloudService.pullSnapshot(
          username: user,
          password: pass,
        );

        if (remoteSnapshot != null) {
          await dbService.mergeRemoteSnapshot(remoteSnapshot);
          return true;
        }
      }

      return false;
    } catch (_) {
      return false;
    } finally {
      _isSyncing = false;
    }
  }

  void dispose() {
    stopPeriodicSync();
  }
}
