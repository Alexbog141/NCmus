import 'dart:async';
import 'dart:io';
import 'package:audiotags/audiotags.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/database/database_service.dart';
import '../../scraper/models/scraped_track.dart';
import '../models/track_entity.dart';

class StorageManager {
  final DatabaseService _dbService;
  final Directory? _customMusicDirectory;
  final http.Client _client;
  final bool _closeClientOnDispose;

  StorageManager({
    DatabaseService? dbService,
    Directory? customMusicDirectory,
    http.Client? client,
  })  : _dbService = dbService ?? DatabaseService.instance,
        _customMusicDirectory = customMusicDirectory,
        _client = client ?? http.Client(),
        _closeClientOnDispose = client == null;

  String sanitizeFileName(String name) {
    return name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

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

  Future<String> downloadAndTagTrack({
    required ScrapedTrack track,
    Function(double progress)? onProgress,
  }) async {
    final musicDir = await getMusicDirectory();
    final safeArtist = sanitizeFileName(track.artist);
    final safeTitle = sanitizeFileName(track.title);
    final fileName = '$safeArtist - $safeTitle.mp3';
    final filePath = p.join(musicDir.path, fileName);
    final file = File(filePath);

    // 1. Потоковое скачивание MP3 файла с подсчетом прогресса
    final request = http.Request('GET', Uri.parse(track.streamUrl));
    request.headers['User-Agent'] =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

    final streamedResponse = await _client.send(request);
    final contentLength = streamedResponse.contentLength ?? 0;
    var receivedBytes = 0;

    final sink = file.openWrite();
    try {
      await for (final chunk in streamedResponse.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (contentLength > 0 && onProgress != null) {
          onProgress(receivedBytes / contentLength);
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    // 2. Скачивание обложки (если доступна)
    final List<Picture> pictures = [];
    if (track.coverUrl != null && track.coverUrl!.isNotEmpty) {
      try {
        final coverResponse = await _client.get(
          Uri.parse(track.coverUrl!),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          },
        );
        if (coverResponse.statusCode == 200 &&
            coverResponse.bodyBytes.isNotEmpty) {
          final isPng = track.coverUrl!.toLowerCase().endsWith('.png');
          pictures.add(
            Picture(
              pictureType: PictureType.coverFront,
              mimeType: isPng ? MimeType.png : MimeType.jpeg,
              bytes: coverResponse.bodyBytes,
            ),
          );
        }
      } catch (_) {
        // Ошибка скачивания обложки не должна прерывать сохранение трека
      }
    }

    // 3. Прошивка ID3 метаданных через audiotags
    try {
      final tag = Tag(
        title: track.title,
        trackArtist: track.artist,
        album: track.title,
        pictures: pictures,
      );
      await AudioTags.write(filePath, tag);
    } catch (_) {
      // Игнорируем ошибки неподдерживаемых форматов тегов
    }

    // 4. Сохранение записи в SQLite базу данных
    // Скачивание не должно сбрасывать флаг "Избранное", если трек уже лайкнут.
    final existing = await _dbService.getTrack(track.id);
    final entity = TrackEntity.fromScrapedTrack(
      track,
      localPath: filePath,
      isDownloaded: true,
      isFavorite: existing?.isFavorite ?? false,
    );
    await _dbService.insertOrUpdateTrack(entity);

    return filePath;
  }

  void dispose() {
    if (_closeClientOnDispose) {
      _client.close();
    }
  }
}
