/// Domain entity representing a user playlist with its metadata, track count,
/// total playtime, and cover art mosaic paths.
class PlaylistEntity {
  final String id;
  final String title;
  final String? description;
  final String? color;
  final DateTime createdAt;
  final int trackCount;
  final Duration totalDuration;
  final List<String> coverUrls;

  const PlaylistEntity({
    required this.id,
    required this.title,
    this.description,
    this.color,
    required this.createdAt,
    this.trackCount = 0,
    this.totalDuration = Duration.zero,
    this.coverUrls = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'color': color,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory PlaylistEntity.fromMap(
    Map<String, dynamic> map, {
    int trackCount = 0,
    Duration totalDuration = Duration.zero,
    List<String> coverUrls = const [],
  }) {
    return PlaylistEntity(
      id: map['id'] as String,
      title: map['title'] as String,
      description: map['description'] as String?,
      color: map['color'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['created_at'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      ),
      trackCount: trackCount,
      totalDuration: totalDuration,
      coverUrls: coverUrls,
    );
  }

  PlaylistEntity copyWith({
    String? id,
    String? title,
    String? description,
    String? color,
    DateTime? createdAt,
    int? trackCount,
    Duration? totalDuration,
    List<String>? coverUrls,
  }) {
    return PlaylistEntity(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
      trackCount: trackCount ?? this.trackCount,
      totalDuration: totalDuration ?? this.totalDuration,
      coverUrls: coverUrls ?? this.coverUrls,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaylistEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title;

  @override
  int get hashCode => id.hashCode ^ title.hashCode;
}
