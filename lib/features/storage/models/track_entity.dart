import 'dart:io';
import 'package:audio_service/audio_service.dart';

import '../../scraper/models/scraped_track.dart';

class TrackEntity {
  final String id;
  final String title;
  final String artist;
  final Duration duration;
  final String streamUrl;
  final String? localPath;
  final String? coverUrl;
  final String sourceName;
  final bool isDownloaded;
  final bool isFavorite;
  final DateTime createdAt;

  const TrackEntity({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
    required this.streamUrl,
    this.localPath,
    this.coverUrl,
    required this.sourceName,
    this.isDownloaded = false,
    this.isFavorite = false,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'duration_ms': duration.inMilliseconds,
      'stream_url': streamUrl,
      'local_path': localPath,
      'cover_url': coverUrl,
      'source_name': sourceName,
      'is_downloaded': isDownloaded ? 1 : 0,
      'is_favorite': isFavorite ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory TrackEntity.fromMap(Map<String, dynamic> map) {
    return TrackEntity(
      id: map['id'] as String,
      title: map['title'] as String,
      artist: map['artist'] as String,
      duration: Duration(milliseconds: map['duration_ms'] as int? ?? 0),
      streamUrl: map['stream_url'] as String,
      localPath: map['local_path'] as String?,
      coverUrl: map['cover_url'] as String?,
      sourceName: map['source_name'] as String,
      isDownloaded: (map['is_downloaded'] as int? ?? 0) == 1,
      isFavorite: (map['is_favorite'] as int? ?? 0) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['created_at'] as int? ?? 0,
      ),
    );
  }

  factory TrackEntity.fromScrapedTrack(
    ScrapedTrack scraped, {
    String? localPath,
    bool isDownloaded = false,
    bool isFavorite = false,
  }) {
    return TrackEntity(
      id: scraped.id,
      title: scraped.title,
      artist: scraped.artist,
      duration: scraped.duration,
      streamUrl: scraped.streamUrl,
      localPath: localPath,
      coverUrl: scraped.coverUrl,
      sourceName: scraped.sourceName,
      isDownloaded: isDownloaded,
      isFavorite: isFavorite,
      createdAt: DateTime.now(),
    );
  }

  MediaItem toMediaItem() {
    final hasLocal = localPath != null &&
        localPath!.isNotEmpty &&
        File(localPath!).existsSync();
    final effectiveId = hasLocal ? localPath! : streamUrl;

    return MediaItem(
      id: effectiveId,
      title: title,
      artist: artist,
      duration: duration,
      artUri: coverUrl != null && coverUrl!.isNotEmpty
          ? Uri.tryParse(coverUrl!)
          : null,
      extras: <String, dynamic>{
        'originalId': id,
        'streamUrl': streamUrl,
        'localPath': localPath,
        'sourceName': sourceName,
        'source': sourceName,
        'isWave': sourceName == 'wave',
        'isDownloaded': isDownloaded,
        'isFavorite': isFavorite,
      },
    );
  }

  TrackEntity copyWith({
    String? id,
    String? title,
    String? artist,
    Duration? duration,
    String? streamUrl,
    String? localPath,
    String? coverUrl,
    String? sourceName,
    bool? isDownloaded,
    bool? isFavorite,
    DateTime? createdAt,
  }) {
    return TrackEntity(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      duration: duration ?? this.duration,
      streamUrl: streamUrl ?? this.streamUrl,
      localPath: localPath ?? this.localPath,
      coverUrl: coverUrl ?? this.coverUrl,
      sourceName: sourceName ?? this.sourceName,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      isFavorite: isFavorite ?? this.isFavorite,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrackEntity &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'TrackEntity(id: $id, artist: $artist, title: $title, isDownloaded: $isDownloaded, localPath: $localPath)';
}
