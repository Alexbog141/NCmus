import '../../storage/models/track_entity.dart';

/// Data transfer object representing a synchronization snapshot of user data.
class SyncSnapshot {
  final int version;
  final List<Map<String, dynamic>> tracks;
  final List<Map<String, dynamic>> playlists;
  final String theme;
  final List<String> blacklist;

  const SyncSnapshot({
    this.version = 0,
    this.tracks = const [],
    this.playlists = const [],
    this.theme = 'cyberpunk_neon',
    this.blacklist = const [],
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'tracks': tracks,
        'playlists': playlists,
        'theme': theme,
        'blacklist': blacklist,
      };

  factory SyncSnapshot.fromJson(Map<String, dynamic> json) {
    // If the response wraps data inside 'sync_data', unwrap it.
    final rawData = json['sync_data'] is Map<String, dynamic>
        ? json['sync_data'] as Map<String, dynamic>
        : json;

    final versionValue = json['version'] ?? rawData['version'];
    final version = (versionValue is num) ? versionValue.toInt() : 0;

    final rawTracks = rawData['tracks'] as List<dynamic>? ?? const [];
    final tracks = rawTracks
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    final rawPlaylists = rawData['playlists'] as List<dynamic>? ?? const [];
    final playlists = rawPlaylists
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    final theme = (rawData['theme'] as String?) ?? 'cyberpunk_neon';

    final rawBlacklist = json['blacklist'] ?? rawData['blacklist'];
    final blacklist = (rawBlacklist as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const [];

    return SyncSnapshot(
      version: version,
      tracks: tracks,
      playlists: playlists,
      theme: theme,
      blacklist: blacklist,
    );
  }

  factory SyncSnapshot.fromDatabase({
    required int version,
    required List<TrackEntity> tracks,
    List<Map<String, dynamic>> playlists = const [],
    String theme = 'cyberpunk_neon',
    List<String> blacklist = const [],
  }) {
    return SyncSnapshot(
      version: version,
      tracks: tracks
          .map((t) => {
                'id': t.id,
                'title': t.title,
                'artist': t.artist,
                'duration_ms': t.duration.inMilliseconds,
                'stream_url': t.streamUrl,
                'cover_url': t.coverUrl,
                'source_name': t.sourceName,
                'is_favorite': t.isFavorite ? 1 : 0,
                'created_at': t.createdAt.millisecondsSinceEpoch,
              })
          .toList(),
      playlists: playlists,
      theme: theme,
      blacklist: blacklist,
    );
  }

  @override
  String toString() =>
      'SyncSnapshot(version: $version, tracks: ${tracks.length}, playlists: ${playlists.length}, theme: $theme, blacklist: ${blacklist.length})';
}
