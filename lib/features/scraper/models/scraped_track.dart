import 'package:audio_service/audio_service.dart';

class ScrapedTrack {
  final String id;
  final String title;
  final String artist;
  final Duration duration;
  final String streamUrl;
  final String? coverUrl;
  final String sourceName;

  const ScrapedTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
    required this.streamUrl,
    this.coverUrl,
    required this.sourceName,
  });

  String get deduplicationKey =>
      '${artist.trim().toLowerCase()} - ${title.trim().toLowerCase()}';

  MediaItem toMediaItem() {
    return MediaItem(
      id: streamUrl,
      title: title,
      artist: artist,
      duration: duration,
      artUri: coverUrl != null && coverUrl!.isNotEmpty
          ? Uri.tryParse(coverUrl!)
          : null,
      extras: <String, dynamic>{
        'originalId': id,
        'sourceName': sourceName,
        'streamUrl': streamUrl,
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScrapedTrack &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          sourceName == other.sourceName;

  @override
  int get hashCode => id.hashCode ^ sourceName.hashCode;

  @override
  String toString() =>
      'ScrapedTrack(id: $id, artist: $artist, title: $title, duration: $duration, sourceName: $sourceName, streamUrl: $streamUrl)';
}
