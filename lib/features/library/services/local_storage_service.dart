import 'dart:async';
import 'dart:io';

import 'package:audiotags/audiotags.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/database/database_service.dart';
import '../../storage/models/track_entity.dart';

/// Service responsible for scanning the local downloads directory (Music/NCmus),
/// reading ID3 metadata tags with [AudioTags], and syncing discovered files with SQLite.
class LocalStorageService {
  static final LocalStorageService instance = LocalStorageService._internal();

  final DatabaseService _dbService;
  final Directory? _customDirectory;
  bool _isScanning = false;

  LocalStorageService({
    DatabaseService? dbService,
    Directory? customDirectory,
  })  : _dbService = dbService ?? DatabaseService.instance,
        _customDirectory = customDirectory;

  LocalStorageService._internal()
      : _dbService = DatabaseService.instance,
        _customDirectory = null;

  factory LocalStorageService.getInstance() => instance;

  bool get isScanning => _isScanning;

  /// Returns the music directory for NCmus based on platform:
  /// - Windows: C:\Users\<User>\Music\NCmus
  /// - Android: /storage/emulated/0/Music/NCmus (with fallback to external/documents)
  Future<Directory> getMusicDirectory() async {
    if (_customDirectory != null) {
      if (!await _customDirectory!.exists()) {
        await _customDirectory!.create(recursive: true);
      }
      return _customDirectory!;
    }

    Directory musicDir;

    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'] ?? '';
      if (userProfile.isNotEmpty) {
        musicDir = Directory(p.join(userProfile, 'Music', 'NCmus'));
      } else {
        final docs = await getApplicationDocumentsDirectory();
        musicDir = Directory(p.join(docs.path, 'NCmus'));
      }
    } else if (Platform.isAndroid) {
      const standardAndroidPath = '/storage/emulated/0/Music/NCmus';
      final directDir = Directory(standardAndroidPath);
      try {
        if (!await directDir.exists()) {
          await directDir.create(recursive: true);
        }
        return directDir;
      } catch (_) {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          musicDir = Directory(p.join(extDir.path, 'NCmus'));
        } else {
          final docDir = await getApplicationDocumentsDirectory();
          musicDir = Directory(p.join(docDir.path, 'NCmus'));
        }
      }
    } else {
      final docDir = await getApplicationDocumentsDirectory();
      musicDir = Directory(p.join(docDir.path, 'NCmus'));
    }

    if (!await musicDir.exists()) {
      await musicDir.create(recursive: true);
    }
    return musicDir;
  }

  /// Scans the download folder (Music/NCmus) for MP3 files, parses their ID3 metadata,
  /// synchronizes them with the SQLite database, and returns the number of newly added tracks.
  Future<int> scanAndSyncLocalFolder() async {
    if (_isScanning) return 0;
    _isScanning = true;

    var addedCount = 0;

    try {
      // Purge ghost tracks automatically on local sync
      await _dbService.purgeZeroDurationGhostTracks();

      final directory = await getMusicDirectory();
      if (!await directory.exists()) {
        return 0;
      }

      final entities = directory.listSync(recursive: false);
      final mp3Files = entities
          .whereType<File>()
          .where((f) => p.extension(f.path).toLowerCase() == '.mp3')
          .toList();

      if (mp3Files.isEmpty) {
        return 0;
      }

      final existingTracks = await _dbService.getAllDownloadedTracks();
      final existingPaths = <String>{};
      for (final t in existingTracks) {
        if (t.localPath != null && t.localPath!.isNotEmpty) {
          existingPaths.add(p.normalize(t.localPath!));
        }
      }

      // Also check all tracks in database in case some were not marked is_downloaded
      final allDbTracks = await _dbService.getAllTracks();
      final allPathToTrack = <String, TrackEntity>{};
      for (final t in allDbTracks) {
        if (t.localPath != null && t.localPath!.isNotEmpty) {
          allPathToTrack[p.normalize(t.localPath!)] = t;
        }
      }

      for (final file in mp3Files) {
        final normalizedPath = p.normalize(file.path);

        // If track already exists in DB with local_path
        if (allPathToTrack.containsKey(normalizedPath)) {
          final existing = allPathToTrack[normalizedPath]!;
          if (!existing.isDownloaded) {
            await _dbService.markAsDownloaded(existing.id, file.path);
            addedCount++;
          }
          continue;
        }

        if (existingPaths.contains(normalizedPath)) {
          continue;
        }

        // Parse ID3 tags via audiotags
        String title = p.basenameWithoutExtension(file.path);
        String artist = 'Unknown Artist';
        int durationMs = 0;

        // Smart parse: "Artist - Title.mp3"
        if (title.contains(' - ')) {
          final parts = title.split(' - ');
          if (parts.length >= 2) {
            artist = parts[0].trim();
            title = parts.sublist(1).join(' - ').trim();
          }
        }

        try {
          final tag = await AudioTags.read(file.path);
          if (tag != null) {
            if (tag.title != null && tag.title!.trim().isNotEmpty) {
              title = tag.title!.trim();
            }
            if (tag.trackArtist != null && tag.trackArtist!.trim().isNotEmpty) {
              artist = tag.trackArtist!.trim();
            }
            if (tag.duration != null && tag.duration! > 0) {
              durationMs = tag.duration! * 1000;
            }
          }
        } catch (_) {
          // audiotags reading is best effort
        }

        // Generate stable deterministic ID based on normalized file path
        final trackId = 'local_${normalizedPath.hashCode.abs()}';

        final newEntity = TrackEntity(
          id: trackId,
          title: title.isNotEmpty ? title : p.basenameWithoutExtension(file.path),
          artist: artist.isNotEmpty ? artist : 'Unknown Artist',
          duration: Duration(milliseconds: durationMs),
          streamUrl: file.path,
          localPath: file.path,
          coverUrl: null,
          sourceName: 'Local Storage',
          isDownloaded: true,
          isFavorite: false,
          createdAt: file.lastModifiedSync(),
        );

        await _dbService.insertOrUpdateTrack(newEntity);
        existingPaths.add(normalizedPath);
        addedCount++;
      }

      if (addedCount > 0) {
        _dbService.notifyLibraryChanged();
      }

      return addedCount;
    } catch (_) {
      return addedCount;
    } finally {
      _isScanning = false;
    }
  }
}
