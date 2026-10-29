import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../../../core/audio/audio_player_handler.dart';
import '../../../core/database/database_service.dart';
import '../../../core/theme/cyberpunk_theme.dart';
import '../../storage/models/playlist_entity.dart';
import '../../storage/models/track_entity.dart';
import '../widgets/add_to_playlist_modal.dart';
import '../widgets/create_playlist_dialog.dart';
import '../widgets/cyber_visualizer.dart';

/// Screen displaying the tracks and management actions of a single playlist.
class PlaylistDetailScreen extends StatefulWidget {
  final PlaylistEntity playlist;
  final NCPlayerHandler handler;
  final VoidCallback? onClose;

  const PlaylistDetailScreen({
    super.key,
    required this.playlist,
    required this.handler,
    this.onClose,
  });

  /// Shows the playlist detail screen as a floating cyberpunk modal panel over the media library.
  static Future<T?> show<T>(
    BuildContext context, {
    required PlaylistEntity playlist,
    required NCPlayerHandler handler,
  }) {
    return Navigator.of(context).push<T>(
      FloatingPlaylistModalRoute<T>(
        child: Align(
          alignment: Alignment.center,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: PlaylistDetailScreen(
                playlist: playlist,
                handler: handler,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  final DatabaseService _dbService = DatabaseService.instance;
  late PlaylistEntity _playlist;
  List<TrackEntity> _tracks = <TrackEntity>[];
  bool _isLoading = true;
  StreamSubscription<void>? _librarySub;

  @override
  void initState() {
    super.initState();
    _playlist = widget.playlist;
    _librarySub = _dbService.libraryChanges.listen((_) => _loadPlaylistData());
    _loadPlaylistData();
  }

  @override
  void dispose() {
    _librarySub?.cancel();
    super.dispose();
  }

  Future<void> _loadPlaylistData() async {
    try {
      final updatedPl = await _dbService.getPlaylist(_playlist.id);
      final tracks = await _dbService.getPlaylistTracks(_playlist.id);
      if (mounted) {
        setState(() {
          if (updatedPl != null) {
            _playlist = updatedPl;
          }
          _tracks = tracks;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Color _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return CyberpunkTheme.neonCyan;
    try {
      final clean = hex.replaceAll('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return CyberpunkTheme.neonCyan;
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatTotalDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours} ч ${d.inMinutes % 60} мин';
    }
    return '${d.inMinutes} мин ${d.inSeconds % 60} сек';
  }

  Future<void> _playAll({bool shuffle = false}) async {
    if (_tracks.isEmpty) return;
    final items = _tracks.map((t) => t.toMediaItem()).toList();
    if (shuffle) {
      await widget.handler.playShuffledQueue(items);
    } else {
      await widget.handler.setQueueAndPlay(
        items,
        0,
        mode: AudioSourceMode.library,
      );
    }
  }

  Future<void> _playTrackAt(int index) async {
    if (index < 0 || index >= _tracks.length) return;
    final items = _tracks.map((t) => t.toMediaItem()).toList();
    await widget.handler.setQueueAndPlay(
      items,
      index,
      mode: AudioSourceMode.library,
    );
  }

  Future<void> _removeTrack(TrackEntity track) async {
    await _dbService.removeTrackFromPlaylist(_playlist.id, track.id);
    await _loadPlaylistData();
  }

  Future<void> _handleReorder(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _tracks.removeAt(oldIndex);
    _tracks.insert(newIndex, item);
    setState(() {});

    final orderedIds = _tracks.map((t) => t.id).toList();
    await _dbService.reorderPlaylistTracks(_playlist.id, orderedIds);
  }

  Future<void> _editPlaylist() async {
    final updated = await CreatePlaylistDialog.show(
      context,
      initialPlaylist: _playlist,
    );
    if (updated != null && mounted) {
      setState(() => _playlist = updated);
      await _loadPlaylistData();
    }
  }

  Future<void> _deletePlaylist() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF141320),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: Colors.redAccent.withValues(alpha: 0.35),
            width: 0.8,
          ),
        ),
        title: const Text(
          'Удалить плейлист?',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        content: Text(
          'Плейлист «${_playlist.title}» будет удален. Сами треки останутся в медиатеке.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 13,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ОТМЕНА'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('УДАЛИТЬ'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _dbService.deletePlaylist(_playlist.id);
      if (mounted) {
        if (widget.onClose != null) {
          widget.onClose!();
        } else {
          Navigator.of(context).pop();
        }
      }
    }
  }

  Widget _buildMosaicCover(double size, Color accentColor) {
    final covers = _playlist.coverUrls;

    if (covers.length >= 4) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.2),
              blurRadius: 20,
              spreadRadius: 1,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _buildCoverImage(covers[0])),
                    Expanded(child: _buildCoverImage(covers[1])),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _buildCoverImage(covers[2])),
                    Expanded(child: _buildCoverImage(covers[3])),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } else if (covers.isNotEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.2),
              blurRadius: 20,
              spreadRadius: 1,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: _buildCoverImage(covers.first),
        ),
      );
    }

    // Default cyberpunk placeholder
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.35),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.15),
            blurRadius: 24,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: Icon(
          Icons.queue_music_rounded,
          color: accentColor,
          size: size * 0.42,
        ),
      ),
    );
  }

  Widget _buildCoverImage(String url) {
    if (url.startsWith('http')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _coverPlaceholder(),
      );
    }
    final file = File(url);
    if (file.existsSync()) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _coverPlaceholder(),
      );
    }
    return _coverPlaceholder();
  }

  Widget _coverPlaceholder() {
    return Container(
      color: Colors.white.withValues(alpha: 0.04),
      child: const Icon(Icons.music_note_rounded, size: 16, color: Colors.white24),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = _parseColor(_playlist.color);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, animValue, childWidget) {
        return Transform.scale(
          scale: 0.96 + (0.04 * animValue),
          child: Opacity(
            opacity: animValue,
            child: childWidget,
          ),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xF010141E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF00FF9D).withValues(alpha: 0.2),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 30,
                spreadRadius: 2,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: const Color(0xFF00FF9D).withValues(alpha: 0.08),
                blurRadius: 20,
                spreadRadius: 1,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // Top Navigation Bar inside floating card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.playlist_play_rounded,
                      color: accentColor,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'ПЛЕЙЛИСТ',
                      style: TextStyle(
                        color: CyberpunkTheme.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.edit_rounded, size: 20),
                      color: Colors.white.withValues(alpha: 0.7),
                      tooltip: 'Редактировать',
                      onPressed: _editPlaylist,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                      color: Colors.redAccent.withValues(alpha: 0.8),
                      tooltip: 'Удалить плейлист',
                      onPressed: _deletePlaylist,
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.close),
                      color: Colors.white.withValues(alpha: 0.8),
                      tooltip: 'Закрыть',
                      onPressed: () {
                        if (widget.onClose != null) {
                          widget.onClose!();
                        } else {
                          Navigator.pop(context);
                        }
                      },
                    ),
                  ],
                ),
              ),
                    const Divider(color: Colors.white10, height: 1),

            // Header Banner
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildMosaicCover(110, accentColor),
                  const SizedBox(width: 22),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _playlist.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: CyberpunkTheme.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                        if (_playlist.description != null &&
                            _playlist.description!.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            _playlist.description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: CyberpunkTheme.textSecondary
                                  .withValues(alpha: 0.8),
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          '${_tracks.length} треков · ${_formatTotalDuration(_playlist.totalDuration)}',
                          style: TextStyle(
                            color: accentColor.withValues(alpha: 0.9),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 14),
                        // Action buttons row
                        Row(
                          children: [
                            ElevatedButton.icon(
                              onPressed: _tracks.isEmpty
                                  ? null
                                  : () => _playAll(shuffle: false),
                              icon: const Icon(Icons.play_arrow_rounded,
                                  size: 18),
                              label: const Text(
                                'Слушать всё',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  letterSpacing: 0.4,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accentColor,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              onPressed: _tracks.isEmpty
                                  ? null
                                  : () => _playAll(shuffle: true),
                              icon: Icon(
                                Icons.shuffle_rounded,
                                size: 17,
                                color: accentColor,
                              ),
                              label: Text(
                                'Перемешать',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: accentColor.withValues(alpha: 0.4),
                                  width: 0.8,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Divider(color: Colors.white10, height: 1),

            // Track list
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: accentColor,
                        strokeWidth: 2,
                      ),
                    )
                  : _tracks.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.queue_music_rounded,
                                size: 48,
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'В плейлисте пока нет треков',
                                style: TextStyle(
                                  color: CyberpunkTheme.textSecondary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Добавляйте музыку через меню «Добавить в плейлист…»',
                                style: TextStyle(
                                  color: CyberpunkTheme.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        )
                      : StreamBuilder<MediaItem?>(
                          stream: widget.handler.mediaItem,
                          builder: (context, mediaSnap) {
                            final currentItem = mediaSnap.data;

                            return StreamBuilder<PlaybackState>(
                              stream: widget.handler.playbackState,
                              builder: (context, playSnap) {
                                final isPlaying =
                                    playSnap.data?.playing ?? false;

                                return ReorderableListView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                      16, 12, 16, 24),
                                  itemCount: _tracks.length,
                                  // ignore: deprecated_member_use
                                  onReorder: _handleReorder,
                                  itemBuilder: (context, index) {
                                    final track = _tracks[index];
                                    final isCurrent = currentItem != null &&
                                        (currentItem.id == track.id ||
                                            currentItem.extras?['originalId'] ==
                                                track.id ||
                                            (currentItem.title == track.title &&
                                                currentItem.artist ==
                                                    track.artist));

                                    return _buildTrackTile(
                                      key: ValueKey(track.id),
                                      track: track,
                                      index: index,
                                      isCurrent: isCurrent,
                                      isPlaying: isPlaying,
                                      accentColor: accentColor,
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),
            ),
                  ],
                ),
              ),
            ),
          );
        }

  Widget _buildTrackTile({
    required Key key,
    required TrackEntity track,
    required int index,
    required bool isCurrent,
    required bool isPlaying,
    required Color accentColor,
  }) {
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isCurrent
            ? accentColor.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrent
              ? accentColor.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.05),
          width: 0.6,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        dense: true,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Order number / active indicator
            SizedBox(
              width: 24,
              child: isCurrent && isPlaying
                  ? CyberVisualizer(
                      isPlaying: true,
                      barCount: 3,
                      maxHeight: 14,
                      color: accentColor,
                    )
                  : Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: isCurrent
                            ? accentColor
                            : Colors.white.withValues(alpha: 0.35),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
            ),
            const SizedBox(width: 8),
            // Track Cover
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 38,
                height: 38,
                child: track.coverUrl != null && track.coverUrl!.isNotEmpty
                    ? _buildCoverImage(track.coverUrl!)
                    : _coverPlaceholder(),
              ),
            ),
          ],
        ),
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isCurrent ? accentColor : CyberpunkTheme.textPrimary,
            fontSize: 13,
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        subtitle: Text(
          track.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 11,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _formatDuration(track.duration),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
              ),
            ),
            const SizedBox(width: 4),
            // Context menu
            PopupMenuButton<String>(
              tooltip: 'Действия',
              icon: Icon(
                Icons.more_vert_rounded,
                size: 18,
                color: Colors.white.withValues(alpha: 0.4),
              ),
              color: const Color(0xFF161524),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 0.5,
                ),
              ),
              onSelected: (val) {
                if (val == 'play') {
                  _playTrackAt(index);
                } else if (val == 'remove') {
                  _removeTrack(track);
                } else if (val == 'add_to_playlist') {
                  AddToPlaylistModal.show(context, track);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'play',
                  child: Row(
                    children: [
                      Icon(Icons.play_arrow_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Воспроизвести'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'add_to_playlist',
                  child: Row(
                    children: [
                      Icon(Icons.playlist_add_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Добавить в другой плейлист…'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'remove',
                  child: Row(
                    children: [
                      Icon(Icons.remove_circle_outline_rounded,
                          size: 18, color: Colors.redAccent),
                      SizedBox(width: 8),
                      Text('Удалить из плейлиста',
                          style: TextStyle(color: Colors.redAccent)),
                    ],
                  ),
                ),
              ],
            ),
            // Drag handle icon for reorder
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  Icons.drag_handle_rounded,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
              ),
            ),
          ],
        ),
        onTap: () => _playTrackAt(index),
      ),
    );
  }
}

/// Floating modal route displaying the playlist panel with a blurred semi-transparent
/// backdrop while keeping the bottom MiniPlayer visible and fully interactive.
class FloatingPlaylistModalRoute<T> extends PopupRoute<T> {
  final Widget child;

  FloatingPlaylistModalRoute({required this.child});

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Закрыть плейлист';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 260);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 200);

  @override
  Widget buildModalBarrier() {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (barrierDismissible) {
            navigator?.pop();
          }
        },
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            color: Colors.black54,
          ),
        ),
      ),
    );
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return child;
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
        child: child,
      ),
    );
  }
}
