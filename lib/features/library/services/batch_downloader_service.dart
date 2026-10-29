import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audiotags/audiotags.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/database/database_service.dart';
import '../../scraper/engine/scraper_engine.dart';
import '../../storage/models/track_entity.dart';

/// Multithreaded batch MP3 downloader service with concurrent workers pool,
/// audio stream resolution, ID3 tag embedding and real-time database syncing.
class BatchDownloaderService {
  static final BatchDownloaderService instance = BatchDownloaderService();

  final DatabaseService _dbService;
  final Dio _dio;
  final ScraperEngine _scraperEngine;
  final Directory? _customMusicDirectory;

  bool _isDownloading = false;
  bool _isCancelled = false;
  final List<CancelToken> _activeTokens = [];

  BatchDownloaderService({
    DatabaseService? dbService,
    Dio? dio,
    ScraperEngine? scraperEngine,
    Directory? customMusicDirectory,
  })  : _dbService = dbService ?? DatabaseService.instance,
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 40),
                followRedirects: true,
                validateStatus: (status) => status != null && status < 400,
              ),
            ),
        _scraperEngine = scraperEngine ?? ScraperEngine.instance,
        _customMusicDirectory = customMusicDirectory;

  bool get isDownloading => _isDownloading;
  bool get isCancelled => _isCancelled;

  /// Sanitizes track title and artist into a valid safe filename.
  /// Removes forbidden filesystem characters: \ / : * ? " < > |
  static String sanitizeFileName(String input) {
    var sanitized = input.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
    sanitized = sanitized.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (sanitized.isEmpty || sanitized == '.mp3') {
      return 'track.mp3';
    }
    if (!sanitized.toLowerCase().endsWith('.mp3')) {
      sanitized = '$sanitized.mp3';
    }
    return sanitized;
  }

  /// Resolves the storage directory for downloaded MP3 tracks:
  /// - Windows: <UserHome>/Music/NCmus/
  /// - Android: System app external directory / Music (with fallback to app docs)
  Future<Directory> getMusicDirectory() async {
    if (_customMusicDirectory != null) {
      if (!await _customMusicDirectory!.exists()) {
        await _customMusicDirectory!.create(recursive: true);
      }
      return _customMusicDirectory!;
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
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          musicDir = Directory(p.join(extDir.path, 'Music'));
        } else {
          const standardPath = '/storage/emulated/0/Music/NCmus';
          musicDir = Directory(standardPath);
        }
      } catch (_) {
        final docDir = await getApplicationDocumentsDirectory();
        musicDir = Directory(p.join(docDir.path, 'Music'));
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

  /// Downloads a list of tracks with a pool of up to 3 parallel download workers.
  Future<void> downloadTracks({
    required List<TrackEntity> tracks,
    required void Function(int completed, int total, String currentTitle)
        onProgress,
    required void Function(String error) onError,
  }) async {
    // 1. Filter tracks: only download tracks that are not yet downloaded or missing local file
    final pendingTracks = tracks.where((t) {
      if (!t.isDownloaded) return true;
      if (t.localPath == null || t.localPath!.isEmpty) return true;
      final file = File(t.localPath!);
      return !file.existsSync() || file.lengthSync() == 0;
    }).toList();

    final total = pendingTracks.length;
    if (total == 0) {
      onProgress(0, 0, '');
      return;
    }

    _isCancelled = false;
    _isDownloading = true;
    _activeTokens.clear();

    int completed = 0;
    final queue = List<TrackEntity>.from(pendingTracks);
    final targetDir = await getMusicDirectory();

    onProgress(0, total, '');

    Future<void> runWorker() async {
      while (queue.isNotEmpty && !_isCancelled) {
        final track = queue.removeAt(0);
        final currentTitle = '${track.artist} - ${track.title}';
        onProgress(completed, total, currentTitle);

        final cancelToken = CancelToken();
        _activeTokens.add(cancelToken);

        try {
          await downloadSingleTrack(track, targetDir, cancelToken);
        } catch (e) {
          if (!_isCancelled) {
            onError('Ошибка скачивания "$currentTitle": $e');
          }
        } finally {
          _activeTokens.remove(cancelToken);
          if (!_isCancelled) {
            completed++;
            onProgress(completed, total, currentTitle);
          }
        }
      }
    }

    // 3 concurrent worker pool
    final poolSize = min(3, pendingTracks.length);
    final workers = List.generate(poolSize, (_) => runWorker());

    try {
      await Future.wait(workers);
    } finally {
      _isDownloading = false;
      _activeTokens.clear();
    }
  }

  /// Downloads a single track, embeds tags, and syncs database records.
  Future<TrackEntity> downloadSingleTrack(
    TrackEntity track,
    Directory targetDir, [
    CancelToken? cancelToken,
  ]) async {
    var streamUrl = track.streamUrl.trim();

    // 1. If stream_url is missing, resolve stream via ScraperEngine
    if (streamUrl.isEmpty) {
      final query = '${track.artist} ${track.title}'.trim();
      final results = await _scraperEngine.searchAll(query);
      if (results.isNotEmpty && results.first.streamUrl.isNotEmpty) {
        streamUrl = results.first.streamUrl;
      } else {
        throw Exception('Не удалось разрешить аудиопоток для "${track.title}"');
      }
    }

    // 2. Target filename with sanitization
    final fileName = sanitizeFileName('${track.artist} - ${track.title}.mp3');
    final filePath = p.join(targetDir.path, fileName);
    final tempPath = '$filePath.tmp';

    // 3. Download stream to temp file
    await _dio.download(
      streamUrl,
      tempPath,
      cancelToken: cancelToken,
      options: Options(
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        },
      ),
    );

    final tempFile = File(tempPath);
    if (!await tempFile.exists() || await tempFile.length() == 0) {
      throw Exception('Скачанный файл пуст или поврежден');
    }

    final targetFile = File(filePath);
    if (await targetFile.exists()) {
      try {
        await targetFile.delete();
      } catch (_) {}
    }
    await tempFile.rename(filePath);

    // 4. Embed ID3 tags via audiotags (with safe fallback)
    try {
      final tag = Tag(
        title: track.title,
        trackArtist: track.artist,
        pictures: const [],
      );
      await AudioTags.write(filePath, tag);
    } catch (_) {
      // Fallback: continuing without tags if native platform fails
    }

    // 5. Update SQLite database and notify UI
    final updatedTrack = track.copyWith(
      streamUrl: streamUrl,
      localPath: filePath,
      isDownloaded: true,
    );

    await _dbService.insertOrUpdateTrack(updatedTrack);
    await _dbService.markAsDownloaded(track.id, filePath);
    _dbService.notifyLibraryChanged();

    return updatedTrack;
  }

  /// Gracefully cancels the active download queue.
  void cancel() {
    _isCancelled = true;
    for (final token in _activeTokens) {
      if (!token.isCancelled) {
        token.cancel('Загрузка отменена пользователем');
      }
    }
    _activeTokens.clear();
    _isDownloading = false;
  }
}
