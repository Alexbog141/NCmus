import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/database/database_service.dart';
import '../../../core/theme/cyberpunk_theme.dart';
import '../../storage/models/playlist_entity.dart';
import '../../storage/models/track_entity.dart';
import 'create_playlist_dialog.dart';

/// Modal dialog with checkboxes allowing users to add/remove a track from playlists,
/// as well as quickly create a new playlist on the fly.
class AddToPlaylistModal extends StatefulWidget {
  final TrackEntity track;

  const AddToPlaylistModal({
    super.key,
    required this.track,
  });

  static Future<void> show(BuildContext context, TrackEntity track) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AddToPlaylistModal(track: track),
    );
  }

  @override
  State<AddToPlaylistModal> createState() => _AddToPlaylistModalState();
}

class _AddToPlaylistModalState extends State<AddToPlaylistModal> {
  final DatabaseService _dbService = DatabaseService.instance;
  List<PlaylistEntity> _playlists = <PlaylistEntity>[];
  Set<String> _selectedPlaylistIds = <String>{};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final playlists = await _dbService.getPlaylists();
      final trackPlaylists =
          await _dbService.getPlaylistsForTrack(widget.track.id);

      if (mounted) {
        setState(() {
          _playlists = playlists;
          _selectedPlaylistIds = trackPlaylists;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _togglePlaylist(PlaylistEntity playlist) async {
    final isSelected = _selectedPlaylistIds.contains(playlist.id);

    setState(() {
      if (isSelected) {
        _selectedPlaylistIds.remove(playlist.id);
      } else {
        _selectedPlaylistIds.add(playlist.id);
      }
    });

    try {
      if (isSelected) {
        await _dbService.removeTrackFromPlaylist(playlist.id, widget.track.id);
      } else {
        await _dbService.addTrackToPlaylist(playlist.id, widget.track);
      }
    } catch (e) {
      // Revert on error
      if (mounted) {
        setState(() {
          if (isSelected) {
            _selectedPlaylistIds.add(playlist.id);
          } else {
            _selectedPlaylistIds.remove(playlist.id);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка обновления плейлиста: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _createNewPlaylist() async {
    final newPlaylist = await CreatePlaylistDialog.show(context);
    if (newPlaylist != null) {
      // Automatically add this track to the new playlist
      await _dbService.addTrackToPlaylist(newPlaylist.id, widget.track);
      await _loadData();
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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            width: 460,
            constraints: const BoxConstraints(maxHeight: 560),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0F0E17).withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: CyberpunkTheme.neonCyan.withValues(alpha: 0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: CyberpunkTheme.neonCyan.withValues(alpha: 0.12),
                  blurRadius: 36,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: CyberpunkTheme.neonCyan.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              CyberpunkTheme.neonCyan.withValues(alpha: 0.35),
                          width: 0.8,
                        ),
                      ),
                      child: Icon(
                        Icons.playlist_add_rounded,
                        color: CyberpunkTheme.neonCyan,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ДОБАВИТЬ В ПЛЕЙЛИСТ',
                            style: TextStyle(
                              color: CyberpunkTheme.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${widget.track.artist} — ${widget.track.title}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: CyberpunkTheme.neonCyan
                                  .withValues(alpha: 0.8),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      color: Colors.white.withValues(alpha: 0.5),
                      splashRadius: 18,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Button to create a new playlist immediately
                InkWell(
                  onTap: _createNewPlaylist,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: CyberpunkTheme.neonCyan.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: CyberpunkTheme.neonCyan.withValues(alpha: 0.25),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.add_circle_outline_rounded,
                          color: CyberpunkTheme.neonCyan,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '+ Новый плейлист',
                          style: TextStyle(
                            color: CyberpunkTheme.neonCyan,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // List of existing playlists
                Expanded(
                  child: _isLoading
                      ? Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: CyberpunkTheme.neonCyan,
                          ),
                        )
                      : _playlists.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.queue_music_rounded,
                                    size: 40,
                                    color: Colors.white.withValues(alpha: 0.2),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Нет созданных плейлистов',
                                    style: TextStyle(
                                      color: CyberpunkTheme.textMuted,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: _playlists.length,
                              itemBuilder: (context, index) {
                                final pl = _playlists[index];
                                final isSelected =
                                    _selectedPlaylistIds.contains(pl.id);
                                final color = _parseColor(pl.color);

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => _togglePlaylist(pl),
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? color.withValues(alpha: 0.08)
                                              : Colors.white
                                                  .withValues(alpha: 0.025),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                            color: isSelected
                                                ? color.withValues(alpha: 0.35)
                                                : Colors.white
                                                    .withValues(alpha: 0.05),
                                            width: 0.6,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            // Checkbox styled
                                            Container(
                                              width: 22,
                                              height: 22,
                                              decoration: BoxDecoration(
                                                color: isSelected
                                                    ? color
                                                    : Colors.transparent,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: isSelected
                                                      ? color
                                                      : Colors.white.withValues(
                                                          alpha: 0.3),
                                                  width: 1.5,
                                                ),
                                              ),
                                              child: isSelected
                                                  ? const Icon(
                                                      Icons.check_rounded,
                                                      size: 16,
                                                      color: Colors.black,
                                                    )
                                                  : null,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    pl.title,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: isSelected
                                                          ? Colors.white
                                                          : Colors.white
                                                              .withValues(
                                                                  alpha: 0.8),
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                  Text(
                                                    '${pl.trackCount} треков',
                                                    style: TextStyle(
                                                      color: CyberpunkTheme
                                                          .textMuted,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                ),
                const SizedBox(height: 16),

                // Done Button
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: CyberpunkTheme.neonCyan,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 11,
                      ),
                    ),
                    child: const Text(
                      'ГОТОВО',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
