import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

/// Data class representing an imported track item with artist, title, and optional duration.
class ImportedTrackItem {
  final String artist;
  final String title;
  final int? durationMs;

  const ImportedTrackItem({
    required this.artist,
    required this.title,
    this.durationMs,
  });

  String get key =>
      '${artist.toLowerCase().trim()}|${title.toLowerCase().trim()}';

  String formatDuration() {
    if (durationMs == null || durationMs! <= 0) return '';
    final totalSeconds = durationMs! ~/ 1000;
    final m = totalSeconds ~/ 60;
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '($m:$s)';
  }

  String toFormattedLine() {
    final dur = formatDuration();
    if (dur.isNotEmpty) {
      return '$artist - $title $dur';
    }
    return '$artist - $title';
  }
}

/// Reverse-engineered network scraper service that fetches tracks from public
/// VK (via open widget) and Yandex Music (via open JSON API) playlists/albums
/// for Step 1 of the Import Wizard.
class PlaylistUrlScraper {
  static final PlaylistUrlScraper instance = PlaylistUrlScraper();

  static const Map<String, String> defaultBrowserHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept-Language': 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
    'Referer': 'https://vk.com/',
  };

  static const Map<String, String> yandexApiHeaders = {
    'User-Agent': 'YandexMusic/2024.1 (Android; SDK 33)',
    'Accept': 'application/json',
  };

  /// Last detected playlist/album title, if extracted during scraping.
  static String? lastDetectedPlaylistTitle;

  final Dio _dio;

  PlaylistUrlScraper({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                headers: defaultBrowserHeaders,
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 20),
                followRedirects: true,
                validateStatus: (status) => status != null && status < 400,
              ),
            );

  /// Static entry point matching:
  /// PlaylistUrlScraper.fetchTracksFromUrl(_urlController.text.trim())
  static Future<List<ImportedTrackItem>> fetchTracksFromUrl(String rawUrl) {
    return instance._fetchTracks(rawUrl);
  }

  /// Instance method for fetching tracks from a raw URL.
  Future<List<ImportedTrackItem>> fetchTracks(String rawUrl) {
    return _fetchTracks(rawUrl);
  }

  Future<List<ImportedTrackItem>> _fetchTracks(String rawUrl) async {
    lastDetectedPlaylistTitle = null;

    var cleanUrl = rawUrl.trim();
    cleanUrl = cleanUrl.replaceAll(RegExp(r'^[\s<"\x27]+|[\s>"\x27]+$'), '');
    if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
      cleanUrl = 'https://$cleanUrl';
    }

    // 1. Проверка на прямую страницу профиля аудиозаписей VK (/audios)
    if (cleanUrl.contains('vk.com/audios') ||
        (cleanUrl.contains('vk.com/audio') &&
            !cleanUrl.contains('playlist') &&
            !cleanUrl.contains('album') &&
            !cleanUrl.contains('audio_playlist') &&
            !cleanUrl.contains('_'))) {
      throw Exception(
        'VK запрещает прямой сбор всей страницы аудиозаписей без входа. Пожалуйста, откройте конкретный альбом/плейлист или вставьте список через буфер обмена.',
      );
    }

    final isVk = cleanUrl.contains('vk.com') || cleanUrl.contains('vk.ru');
    final isYandex = cleanUrl.contains('music.yandex') ||
        cleanUrl.contains('yandex.ru/music') ||
        cleanUrl.contains('yandex.com/music');

    if (!isVk && !isYandex) {
      throw Exception(
          'Поддерживаются только открытые ссылки VK и Яндекс Музыки');
    }

    if (isYandex) {
      return _parseYandexMusic(cleanUrl);
    } else {
      return _parseVkMusic(cleanUrl);
    }
  }

  // ===========================================================================
  // 1. ПАРСИНГ ЯНДЕКС МУЗЫКИ (ОТКРЫТЫЙ JSON API)
  // ===========================================================================
  Future<List<ImportedTrackItem>> _parseYandexMusic(String url) async {
    // А. Ссылка на Альбом: music.yandex.ru/album/(\d+)
    final albumMatch = RegExp(r'album\/(\d+)').firstMatch(url);
    if (albumMatch != null) {
      final albumId = albumMatch.group(1)!;
      return _fetchYandexAlbum(albumId);
    }

    // Б. Ссылка на Плейлист: /users/([^/]+)/playlists/(\d+)
    final playlistMatch =
        RegExp(r'users\/([^/]+)\/playlists\/(\d+)', caseSensitive: false)
            .firstMatch(url);
    if (playlistMatch != null) {
      final owner = playlistMatch.group(1)!;
      final kind = playlistMatch.group(2)!;
      return _fetchYandexUserPlaylist(owner, kind);
    }

    // Резервная ссылка вида /playlists/(\d+)
    final simplePlMatch = RegExp(r'playlists\/(\d+)').firstMatch(url);
    if (simplePlMatch != null) {
      final kind = simplePlMatch.group(1)!;
      return _fetchYandexUserPlaylist('', kind);
    }

    throw Exception(
      'Не удалось распознать формат ссылки Яндекс Музыки. Поддерживаются ссылки на альбомы (/album/...) и плейлисты (/users/.../playlists/...).',
    );
  }

  Future<List<ImportedTrackItem>> _fetchYandexAlbum(String albumId) async {
    final apiUrl = 'https://api.music.yandex.net/albums/$albumId/with-tracks';
    final Response<dynamic> response;
    try {
      response = await _dio.get<dynamic>(
        apiUrl,
        options: Options(
          headers: yandexApiHeaders,
          responseType: ResponseType.json,
        ),
      );
    } catch (_) {
      throw Exception(
        'Не удалось получить данные альбома Яндекс Музыки. Проверьте правильность ссылки и доступность альбома.',
      );
    }

    dynamic data = response.data;
    if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (_) {}
    }

    if (data is! Map) {
      throw Exception(
        'Не удалось прочитать плейлист Яндекс Музыки. Проверьте правильность ссылки.',
      );
    }

    final result = data['result'];
    if (result is! Map) {
      throw Exception(
        'Альбом Яндекс Музыки не найден или доступ к нему ограничен.',
      );
    }

    final albumTitle = result['title']?.toString().trim();
    if (albumTitle != null && albumTitle.isNotEmpty) {
      final artistName = (result['artists'] is List &&
              (result['artists'] as List).isNotEmpty &&
              (result['artists'] as List).first is Map)
          ? (result['artists'] as List).first['name']?.toString()
          : null;
      lastDetectedPlaylistTitle = (artistName != null && artistName.isNotEmpty)
          ? '$artistName - $albumTitle'
          : albumTitle;
    }

    final volumes = result['volumes'];
    if (volumes is! List || volumes.isEmpty) {
      throw Exception('В альбоме Яндекс Музыки не найдено аудиозаписей.');
    }

    final tracks = <ImportedTrackItem>[];
    for (final vol in volumes) {
      if (vol is! List) continue;
      for (final track in vol) {
        if (track is! Map) continue;
        final title = track['title']?.toString().trim() ?? '';
        String artist = '';
        final artists = track['artists'];
        if (artists is List && artists.isNotEmpty) {
          final first = artists.first;
          if (first is Map && first.containsKey('name')) {
            artist = first['name']?.toString().trim() ?? '';
          } else if (first is String) {
            artist = first.trim();
          }
        }
        final durationMs = (track['durationMs'] as num?)?.toInt();

        if (title.isNotEmpty) {
          tracks.add(
            ImportedTrackItem(
              artist: artist.isNotEmpty ? artist : 'Unknown Artist',
              title: title,
              durationMs: durationMs,
            ),
          );
        }
      }
    }

    if (tracks.isEmpty) {
      throw Exception(
        'Не удалось извлечь треки из альбома Яндекс Музыки.',
      );
    }

    return tracks;
  }

  Future<List<ImportedTrackItem>> _fetchYandexUserPlaylist(
      String owner, String kind) async {
    final queryUrl = owner.isNotEmpty
        ? 'https://music.yandex.ru/handlers/playlist.jsx?owner=$owner&kinds=$kind'
        : 'https://music.yandex.ru/handlers/playlist.jsx?kinds=$kind';

    final Response<dynamic> response;
    try {
      response = await _dio.get<dynamic>(
        queryUrl,
        options: Options(
          headers: defaultBrowserHeaders,
          responseType: ResponseType.json,
        ),
      );
    } catch (_) {
      throw Exception(
        'Не удалось загрузить плейлист Яндекс Музыки. Убедитесь, что плейлист является открытым.',
      );
    }

    dynamic data = response.data;
    if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (_) {}
    }

    if (data is! Map) {
      throw Exception(
        'Не удалось прочитать плейлист Яндекс Музыки. Проверьте правильность ссылки.',
      );
    }

    final playlist = data['playlist'];
    if (playlist is! Map) {
      throw Exception(
        'Плейлист Яндекс Музыки не найден или является приватным.',
      );
    }

    final plTitle = playlist['title']?.toString().trim();
    if (plTitle != null && plTitle.isNotEmpty) {
      lastDetectedPlaylistTitle = plTitle;
    }

    final rawTracks = playlist['tracks'];
    if (rawTracks is! List || rawTracks.isEmpty) {
      throw Exception('Плейлист Яндекс Музыки пуст.');
    }

    final tracks = <ImportedTrackItem>[];
    for (final item in rawTracks) {
      final track = (item is Map &&
              item.containsKey('track') &&
              item['track'] is Map)
          ? item['track'] as Map
          : (item is Map ? item : null);

      if (track == null) continue;
      final title = track['title']?.toString().trim() ?? '';
      String artist = '';
      final artists = track['artists'];
      if (artists is List && artists.isNotEmpty) {
        final first = artists.first;
        if (first is Map && first.containsKey('name')) {
          artist = first['name']?.toString().trim() ?? '';
        } else if (first is String) {
          artist = first.trim();
        }
      }
      final durationMs = (track['durationMs'] as num?)?.toInt();

      if (title.isNotEmpty) {
        tracks.add(
          ImportedTrackItem(
            artist: artist.isNotEmpty ? artist : 'Unknown Artist',
            title: title,
            durationMs: durationMs,
          ),
        );
      }
    }

    if (tracks.isEmpty) {
      throw Exception('Не удалось извлечь треки из плейлиста Яндекс Музыки.');
    }

    return tracks;
  }

  // ===========================================================================
  // 2. ПАРСИНГ VK (ЧЕРЕЗ ОТКРЫТЫЙ ПУБЛИЧНЫЙ ВИДЖЕТ ИЛИ ACCESS_HASH)
  // ===========================================================================
  Future<List<ImportedTrackItem>> _parseVkMusic(String url) async {
    // 1) Нахождение owner_id, playlist_id и access_hash по универсальному регулярному выражению
    final match =
        RegExp(r'(-?\d+)_(\d+)(?:_([a-zA-Z0-9]+))?').firstMatch(url);

    if (match == null) {
      throw Exception(
        'Не удалось извлечь идентификаторы плейлиста VK. Убедитесь, что ссылка имеет вид: https://vk.com/music/playlist/-XXX_YYY...',
      );
    }

    final ownerId = match.group(1)!;
    final playlistId = match.group(2)!;
    final accessHash = match.group(3);

    // 2) Формирование URL открытого виджета VK
    // openapi виджет эндпоинт (oid / pid / hash / app=0) работает без редиректа на страницу авторизации
    var widgetUrl =
        'https://vk.com/widget_playlist.php?oid=$ownerId&pid=$playlistId&app=0';
    if (accessHash != null && accessHash.isNotEmpty) {
      widgetUrl += '&hash=$accessHash';
    }

    var tracks = await _tryFetchVkWidget(widgetUrl);

    // Резервная попытка со стандартным widgetUrl (act=playlist & owner_id & playlist_id)
    if (tracks.isEmpty) {
      var altWidgetUrl =
          'https://vk.com/widget_playlist.php?act=playlist&owner_id=$ownerId&playlist_id=$playlistId';
      if (accessHash != null && accessHash.isNotEmpty) {
        altWidgetUrl += '&access_hash=$accessHash';
      }
      tracks = await _tryFetchVkWidget(altWidgetUrl);
    }

    if (tracks.isEmpty) {
      throw Exception(
        'Не удалось извлечь треки. Убедитесь, что плейлист или страница открыты для всех в настройках приватности VK',
      );
    }

    return tracks;
  }

  static String decodeHtmlBytes(List<int> bytes) {
    try {
      // Сначала пробуем честный UTF-8 (если allowMalformed: false упадет на CP1251)
      return utf8.decode(bytes, allowMalformed: false);
    } catch (_) {
      // Если упало — перед нами windows-1251!
      const cp1251Table =
          'ЂЃ‚ѓ„…†‡€‰Љ‹ЊЌЋЏ'
          'ђ‘’“”•–—\x00™љ›њќћџ'
          '\u00A0ЎўЈ¤Ґ¦§Ё©Є«¬\u00AD®Ї'
          '°±Ііґµ¶·ё№є»јЅѕї'
          'АБВГДЕЖЗИЙКЛМНОП'
          'РСТУФХЦЧШЩЪЫЬЭЮЯ'
          'абвгдежзийклмноп'
          'рстуфхцчшщъыьэюя';
      final buffer = StringBuffer();
      for (final b in bytes) {
        if (b < 0x80) {
          buffer.writeCharCode(b);
        } else {
          buffer.write(cp1251Table[b - 0x80]);
        }
      }
      return buffer.toString();
    }
  }

  Future<List<ImportedTrackItem>> _tryFetchVkWidget(String widgetUrl) async {
    final Response<List<int>> response;
    try {
      response = await _dio.get<List<int>>(
        widgetUrl,
        options: Options(
          headers: defaultBrowserHeaders,
          responseType: ResponseType.bytes, // Читаем как байты!
        ),
      );
    } catch (_) {
      return const [];
    }

    final html = decodeHtmlBytes(response.data ?? []);
    if (html.isEmpty || html.contains('react_rootLoginMobile')) {
      return const [];
    }

    _extractVkWidgetTitle(html);

    final tracks = <ImportedTrackItem>[];

    // 3) Парсинг data-audio атрибутов с JSON-массивом
    // [id, owner_id, "url", "Title", "Artist", duration_in_seconds, ...]
    final dataAudioMatches = RegExp(r'data-audio="([^"]+)"').allMatches(html);

    for (final m in dataAudioMatches) {
      final rawAudio = _unescapeHtml(m.group(1)!);
      try {
        final decoded = jsonDecode(rawAudio);
        if (decoded is List && decoded.length >= 5) {
          final title = _unescapeHtml(decoded[3]?.toString().trim() ?? '');
          final artist = _unescapeHtml(decoded[4]?.toString().trim() ?? '');
          final durSec = (decoded.length > 5
                  ? (decoded[5] as num?)?.toInt()
                  : null) ??
              int.tryParse(decoded.length > 5 ? decoded[5].toString() : '') ??
              0;

          if (title.isNotEmpty) {
            tracks.add(
              ImportedTrackItem(
                artist: artist.isNotEmpty ? artist : 'Unknown Artist',
                title: title,
                durationMs: durSec * 1000,
              ),
            );
          }
        }
      } catch (_) {}
    }

    // Резервный вариант 1: DOM-элементы .audio_item .ai_artist, .audio_item .ai_title, .audio_item .ai_dur
    if (tracks.isEmpty) {
      try {
        final doc = html_parser.parse(html);
        final audioNodes = doc.querySelectorAll('.audio_item');
        for (final node in audioNodes) {
          final artist = node.querySelector('.ai_artist')?.text.trim() ?? '';
          final title = node.querySelector('.ai_title')?.text.trim() ?? '';
          final durEl = node.querySelector('.ai_dur');
          final durSec =
              int.tryParse(durEl?.attributes['data-dur'] ?? '') ?? 0;

          if (title.isNotEmpty) {
            tracks.add(
              ImportedTrackItem(
                artist: artist.isNotEmpty ? artist : 'Unknown Artist',
                title: title,
                durationMs: durSec * 1000,
              ),
            );
          }
        }
      } catch (_) {}
    }

    // Резервный вариант 2: DOM-элементы .audio_row
    if (tracks.isEmpty) {
      try {
        final doc = html_parser.parse(html);
        final rows = doc.querySelectorAll('.audio_row');
        for (final row in rows) {
          final artistEl = row.querySelector(
              '.audio_row__performers a, .audio_row__performer');
          final titleEl = row.querySelector(
              '.audio_row__title_inner, .audio_row__title');
          final artist = artistEl?.text.trim() ?? '';
          final title = titleEl?.text.trim() ?? '';
          final durAttr = row.attributes['data-duration'];
          final durSec = int.tryParse(durAttr ?? '') ?? 0;
          if (title.isNotEmpty) {
            tracks.add(
              ImportedTrackItem(
                artist: artist.isNotEmpty ? artist : 'Unknown Artist',
                title: title,
                durationMs: durSec * 1000,
              ),
            );
          }
        }
      } catch (_) {}
    }

    // Дедупликация с сохранением исходного порядка
    final unique = <String, ImportedTrackItem>{};
    for (final t in tracks) {
      unique.putIfAbsent(t.key, () => t);
    }
    return unique.values.toList();
  }

  void _extractVkWidgetTitle(String html) {
    // 1. Поиск названия в заголовках сниппета виджета
    final titleSnippetMatch = RegExp(
      r'class=["\x27][^"\x27]*audio_pl_snippet_info_maintitle[^"\x27]*["\x27][^>]*>(.*?)<',
      caseSensitive: false,
    ).firstMatch(html);

    if (titleSnippetMatch != null) {
      final t = _unescapeHtml(titleSnippetMatch.group(1)?.trim() ?? '');
      if (t.isNotEmpty) {
        lastDetectedPlaylistTitle = t;
        return;
      }
    }

    final topTitleMatch = RegExp(
      r'class=["\x27](?:top_playlist_title|pl_title|audio_pl_snippet__title)[^"\x27]*["\x27][^>]*>(.*?)<',
      caseSensitive: false,
    ).firstMatch(html);

    if (topTitleMatch != null) {
      final t = _unescapeHtml(topTitleMatch.group(1)?.trim() ?? '');
      if (t.isNotEmpty) {
        lastDetectedPlaylistTitle = t;
        return;
      }
    }

    // 2. <title>...</title>
    final titleMatch = RegExp(
      r'<title[^>]*>(.*?)<\/title>',
      caseSensitive: false,
    ).firstMatch(html);

    if (titleMatch != null) {
      var t = _unescapeHtml(titleMatch.group(1)?.trim() ?? '');
      t = t.replaceAll(RegExp(r'\s*\|\s*ВКонтакте.*$', caseSensitive: false), '');
      t = t.replaceAll(RegExp(r'\s*\|\s*VK.*$', caseSensitive: false), '');
      t = t.replaceAll(RegExp(r'\s*\|\s*Playlist\s*Widget.*$', caseSensitive: false), '');
      if (t.isNotEmpty &&
          !t.toLowerCase().contains('вконтакте') &&
          !t.toLowerCase().contains('playlist widget')) {
        lastDetectedPlaylistTitle = t;
        return;
      }
    }

    lastDetectedPlaylistTitle ??= 'Плейлист VK';
  }

  static String _unescapeHtml(String input) {
    var text = input;
    text = text.replaceAll('&quot;', '"');
    text = text.replaceAll('&amp;', '&');
    text = text.replaceAll('&#39;', "'");
    text = text.replaceAll('&apos;', "'");
    text = text.replaceAll('&lt;', '<');
    text = text.replaceAll('&gt;', '>');
    text = text.replaceAll('&ndash;', '–');
    text = text.replaceAll('&mdash;', '—');
    text = text.replaceAll('&nbsp;', ' ');

    text = text.replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
      final code = int.tryParse(match.group(1) ?? '');
      return code != null ? String.fromCharCode(code) : match.group(0)!;
    });

    text = text.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
      final code = int.tryParse(match.group(1) ?? '', radix: 16);
      return code != null ? String.fromCharCode(code) : match.group(0)!;
    });

    return text;
  }
}
