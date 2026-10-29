import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../../../core/audio/audio_player_handler.dart';
import '../../../core/audio/position_data.dart';
import '../../../core/database/database_service.dart';
import '../../../core/theme/cyberpunk_theme.dart';
import '../../lyrics/services/lyrics_service.dart';
import '../../storage/models/track_entity.dart';

/// Immersive fullscreen player with ambient artwork, synchronized karaoke
/// lyrics with auto-scroll and line highlighting, queue transport, and volume.
class FullscreenPlayerModal extends StatefulWidget {
  final NCPlayerHandler handler;

  const FullscreenPlayerModal({
    super.key,
    required this.handler,
  });

  @override
  State<FullscreenPlayerModal> createState() => _FullscreenPlayerModalState();
}

class _FullscreenPlayerModalState extends State<FullscreenPlayerModal> {
  final LyricsService _lyricsService = LyricsService();

  double? _dragValue;
  bool _isFavorite = false;
  bool _favoriteBusy = false;
  String? _lastTrackId;

  // Lyrics state
  bool _showLyrics = false;
  LyricsModel? _lyrics;
  bool _loadingLyrics = false;
  String? _lyricsTrackId;

  @override
  void dispose() {
    _lyricsService.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  String _formatDuration(Duration duration) {
    if (duration <= Duration.zero) return '00:00';
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      final hours = duration.inHours.toString().padLeft(2, '0');
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  String _trackIdFor(MediaItem item) =>
      item.extras?['originalId']?.toString() ?? item.id;

  Future<void> _checkFavorite(String trackId) async {
    if (_lastTrackId == trackId) return;
    _lastTrackId = trackId;

    try {
      final track = await DatabaseService.instance.getTrack(trackId);
      if (!mounted || _lastTrackId != trackId) return;
      setState(() {
        _isFavorite = track?.isFavorite ?? false;
      });
    } catch (_) {
      if (!mounted || _lastTrackId != trackId) return;
      setState(() {
        _isFavorite = false;
      });
    }
  }

  Future<void> _loadLyricsFor(MediaItem item, {bool force = false}) async {
    final trackId = _trackIdFor(item);
    if (!force && _lyricsTrackId == trackId && _lyrics != null) return;
    _lyricsTrackId = trackId;

    setState(() {
      _loadingLyrics = true;
      _lyrics = null;
    });

    try {
      final lyrics = await _lyricsService.fetchLyrics(
        title: item.title,
        artist: item.artist ?? '',
        duration: item.duration,
      );
      if (!mounted || _lyricsTrackId != trackId) return;
      setState(() {
        _lyrics = lyrics;
        _loadingLyrics = false;
      });
    } catch (_) {
      if (!mounted || _lyricsTrackId != trackId) return;
      setState(() {
        _lyrics = null;
        _loadingLyrics = false;
      });
    }
  }

  TrackEntity _entityFromMediaItem(
    MediaItem item, {
    required bool isFavorite,
  }) {
    final extras = item.extras ?? const <String, dynamic>{};
    return TrackEntity(
      id: _trackIdFor(item),
      title: item.title,
      artist: item.artist ?? 'Unknown Artist',
      duration: item.duration ?? Duration.zero,
      streamUrl: extras['streamUrl']?.toString() ?? item.id,
      localPath: extras['localPath']?.toString(),
      coverUrl: item.artUri?.toString(),
      sourceName: extras['sourceName']?.toString() ?? 'Web',
      isDownloaded: extras['isDownloaded'] == true,
      isFavorite: isFavorite,
      createdAt: DateTime.now(),
    );
  }

  Future<void> _toggleFavorite(MediaItem item) async {
    if (_favoriteBusy) return;

    final trackId = _trackIdFor(item);
    final nextValue = !_isFavorite;

    setState(() {
      _isFavorite = nextValue;
      _favoriteBusy = true;
    });

    try {
      final database = DatabaseService.instance;
      final existing = await database.getTrack(trackId);

      if (existing == null) {
        await database.insertOrUpdateTrack(
          _entityFromMediaItem(item, isFavorite: nextValue),
        );
      } else {
        await database.toggleFavorite(trackId, nextValue);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isFavorite = !nextValue;
      });
    } finally {
      if (mounted) {
        setState(() {
          _favoriteBusy = false;
        });
      }
    }
  }

  Future<void> _seekBy(Duration offset) async {
    final duration = widget.handler.currentDuration;
    var target = widget.handler.currentPosition + offset;

    if (target < Duration.zero) {
      target = Duration.zero;
    }
    if (duration > Duration.zero && target > duration) {
      target = duration;
    }

    await widget.handler.seek(target);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CyberpunkTheme.backgroundColor,
      body: StreamBuilder<MediaItem?>(
        stream: widget.handler.mediaItem,
        builder: (context, snapshot) {
          final item = snapshot.data;

          if (item == null) {
            return _buildEmptyState(context);
          }

          final trackId = _trackIdFor(item);
          if (_lastTrackId != trackId) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _checkFavorite(trackId);
            });
          }

          if (_showLyrics && _lyricsTrackId != trackId && !_loadingLyrics) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _loadLyricsFor(item);
            });
          }

          final coverUrl = item.artUri?.toString();

          return Stack(
            fit: StackFit.expand,
            children: [
              _AmbientBackground(coverUrl: coverUrl),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final maxHeight = constraints.maxHeight;
                    final maxWidth = constraints.maxWidth;
                    final isCompact = maxHeight < 680;
                    final isVeryCompact = maxHeight < 540;

                    final double coverSize;
                    if (isVeryCompact) {
                      coverSize = (maxHeight * 0.22).clamp(120.0, 160.0);
                    } else if (isCompact) {
                      coverSize = (maxHeight * 0.28).clamp(180.0, 220.0);
                    } else {
                      coverSize = math.min(
                        320.0,
                        math.min(
                          maxWidth * 0.60,
                          maxHeight * 0.40,
                        ),
                      );
                    }

                    return Column(
                      children: [
                        _buildTopBar(context, item, isCompact: isCompact),
                        Expanded(
                          child: Center(
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              padding: EdgeInsets.symmetric(
                                horizontal: isCompact ? 16 : 24,
                                vertical: isCompact ? 4 : 8,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 320),
                                    switchInCurve: Curves.easeOutCubic,
                                    switchOutCurve: Curves.easeInCubic,
                                    child: _showLyrics
                                        ? _LyricsContainer(
                                            key: ValueKey('lyrics_$trackId'),
                                            lyrics: _lyrics,
                                            isLoading: _loadingLyrics,
                                            handler: widget.handler,
                                            height: isCompact
                                                ? math.max(
                                                    160.0, coverSize * 1.1)
                                                : coverSize * 1.08,
                                            width: math.min(
                                              520.0,
                                              maxWidth - 32,
                                            ),
                                            onSeek: (pos) =>
                                                widget.handler.seek(pos),
                                            onRetry: () => _loadLyricsFor(item,
                                                force: true),
                                            onClose: () => setState(() {
                                              _showLyrics = false;
                                            }),
                                          )
                                        : _buildCover(
                                            coverUrl,
                                            coverSize,
                                            key: ValueKey('cover_$trackId'),
                                          ),
                                  ),
                                  SizedBox(height: isCompact ? 10 : 18),
                                  _buildTitleRow(item, trackId,
                                      isCompact: isCompact),
                                  SizedBox(height: isCompact ? 4 : 7),
                                  _buildArtistRow(item, isCompact: isCompact),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Always pinned and visible controls at the bottom
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            isCompact ? 16 : 24,
                            2,
                            isCompact ? 16 : 24,
                            isCompact ? 8 : 16,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildPositionSection(isCompact: isCompact),
                              SizedBox(height: isCompact ? 6 : 12),
                              _buildTransportControls(isCompact: isCompact),
                              SizedBox(height: isCompact ? 6 : 12),
                              _buildVolumeSection(isCompact: isCompact),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: CyberpunkTheme.backgroundGradient,
      ),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.graphic_eq_rounded,
                size: 54,
                color: CyberpunkTheme.neonCyan,
              ),
              const SizedBox(height: 16),
              Text(
                'Ничего не играет',
                style: TextStyle(
                  color: CyberpunkTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Выберите трек в поиске или медиатеке',
                style: TextStyle(
                  color: CyberpunkTheme.textMuted,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    MediaItem item, {
    bool isCompact = false,
  }) {
    final queueLength = widget.handler.queueItems.length;
    final currentPosition = widget.handler.currentIndex + 1;
    final queueLabel = queueLength > 0
        ? '${currentPosition.toString().padLeft(2, '0')} / '
            '${queueLength.toString().padLeft(2, '0')}'
        : '01 / 01';
    final sourceName = item.extras?['sourceName']?.toString();

    return Padding(
      padding:
          EdgeInsets.fromLTRB(16, isCompact ? 4 : 8, 16, isCompact ? 2 : 4),
      child: Row(
        children: [
          _GlassCircleButton(
            icon: Icons.keyboard_arrow_down_rounded,
            tooltip: 'Свернуть плеер',
            onTap: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  'NOW PLAYING',
                  style: TextStyle(
                    color: CyberpunkTheme.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  sourceName == null || sourceName.isEmpty
                      ? 'NC MUS'
                      : sourceName.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: CyberpunkTheme.neonCyan.withValues(alpha: 0.76),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
          ),
          _GlassCircleButton(
            icon: _showLyrics ? Icons.album_rounded : Icons.lyrics_rounded,
            tooltip: _showLyrics ? 'Показать обложку' : 'Караоке-текст',
            activeColor: _showLyrics ? CyberpunkTheme.neonCyan : null,
            onTap: () {
              setState(() {
                _showLyrics = !_showLyrics;
              });
              if (_showLyrics) {
                _loadLyricsFor(item);
              }
            },
          ),
          const SizedBox(width: 8),
          GlassCard(
            borderRadius: 14,
            blur: 12,
            backgroundOpacity: 0.035,
            borderGradient: CyberpunkTheme.glassBorderGradientSoft,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Text(
              queueLabel,
              style: TextStyle(
                color: CyberpunkTheme.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCover(String? coverUrl, double size, {Key? key}) {
    return Hero(
      key: key,
      tag: 'player_cover',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: CyberpunkTheme.neonCyan.withValues(alpha: 0.2),
              blurRadius: 42,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: CyberpunkTheme.electricViolet.withValues(alpha: 0.22),
              blurRadius: 58,
              spreadRadius: 4,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: coverUrl != null && coverUrl.isNotEmpty
              ? Image.network(
                  coverUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _buildCoverPlaceholder(),
                )
              : _buildCoverPlaceholder(),
        ),
      ),
    );
  }

  Widget _buildCoverPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            ThemeController.colors.bgSurface,
            ThemeController.colors.cardGlass
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.graphic_eq_rounded,
          color: CyberpunkTheme.neonCyan,
          size: 74,
        ),
      ),
    );
  }

  Widget _buildTitleRow(
    MediaItem item,
    String trackId, {
    bool isCompact = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            item.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: CyberpunkTheme.textPrimary,
              fontSize: isCompact ? 18 : 24,
              height: 1.16,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _FavoriteButton(
          isFavorite: _isFavorite,
          isBusy: _favoriteBusy,
          onTap: () => _toggleFavorite(item),
        ),
      ],
    );
  }

  Widget _buildArtistRow(
    MediaItem item, {
    bool isCompact = false,
  }) {
    final sourceName = item.extras?['sourceName']?.toString();
    final isDownloaded = item.extras?['isDownloaded'] as bool? ?? false;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isDownloaded) ...[
          Icon(
            Icons.offline_pin_rounded,
            size: 14,
            color: CyberpunkTheme.neonGreen,
          ),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            item.artist ?? 'Unknown Artist',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: CyberpunkTheme.neonCyan.withValues(alpha: 0.82),
              fontSize: isCompact ? 12.5 : 14,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
        ),
        if (sourceName != null && sourceName.isNotEmpty) ...[
          const SizedBox(width: 10),
          Container(
            width: 3,
            height: 3,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.28),
            ),
          ),
          const SizedBox(width: 10),
          _SourceBadge(sourceName: sourceName),
        ],
      ],
    );
  }

  Widget _buildPositionSection({bool isCompact = false}) {
    return StreamBuilder<PositionData>(
      stream: widget.handler.positionDataStream,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final position = data?.position ?? Duration.zero;
        final duration = data?.duration ?? Duration.zero;
        final maxMs = duration.inMilliseconds.toDouble();
        final safeMax = maxMs > 0 ? maxMs : 1.0;
        final currentMs = _dragValue ??
            position.inMilliseconds.toDouble().clamp(0.0, safeMax);

        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: CyberpunkTheme.neonCyan,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
                thumbColor: Colors.white,
                overlayColor: CyberpunkTheme.neonCyan.withValues(alpha: 0.14),
                trackHeight: isCompact ? 2.5 : 3,
                thumbShape: RoundSliderThumbShape(
                  enabledThumbRadius: isCompact ? 5 : 6,
                ),
                overlayShape: RoundSliderOverlayShape(
                  overlayRadius: isCompact ? 12 : 16,
                ),
              ),
              child: Slider(
                min: 0,
                max: safeMax,
                value: currentMs.clamp(0.0, safeMax),
                onChanged: (value) {
                  setState(() {
                    _dragValue = value;
                  });
                },
                onChangeEnd: (value) {
                  widget.handler.seek(Duration(milliseconds: value.toInt()));
                  setState(() {
                    _dragValue = null;
                  });
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(
                      _dragValue != null
                          ? Duration(milliseconds: _dragValue!.toInt())
                          : position,
                    ),
                    style: TextStyle(
                      color: CyberpunkTheme.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [ui.FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    _formatDuration(duration),
                    style: TextStyle(
                      color: CyberpunkTheme.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [ui.FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTransportControls({bool isCompact = false}) {
    return StreamBuilder<PlaybackState>(
      stream: widget.handler.playbackState,
      builder: (context, snapshot) {
        final state = snapshot.data;
        final playing = state?.playing ?? false;
        final processing = state?.processingState ?? AudioProcessingState.idle;
        final isLoading = processing == AudioProcessingState.loading ||
            processing == AudioProcessingState.buffering;

        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: GlassCard(
            borderRadius: isCompact ? 22 : 28,
            blur: 18,
            backgroundOpacity: 0.035,
            borderGradient: CyberpunkTheme.glassBorderGradientSoft,
            padding: EdgeInsets.symmetric(
              horizontal: 10,
              vertical: isCompact ? 6 : 9,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _RoundControlButton(
                  icon: Icons.thumb_down_outlined,
                  tooltip: 'Не нравится (в чёрный список)',
                  isCompact: isCompact,
                  onPressed: () => widget.handler.blacklistCurrentTrack(),
                ),
                _RoundControlButton(
                  icon: Icons.skip_previous_rounded,
                  tooltip: 'Предыдущий трек',
                  isCompact: isCompact,
                  onPressed: () => widget.handler.skipToPrevious(),
                ),
                _RoundControlButton(
                  icon: Icons.replay_10_rounded,
                  tooltip: 'Назад на 10 секунд',
                  isCompact: isCompact,
                  onPressed: () => _seekBy(const Duration(seconds: -10)),
                ),
                _MainPlayButton(
                  playing: playing,
                  isLoading: isLoading,
                  isCompact: isCompact,
                  onPressed: () {
                    if (playing) {
                      widget.handler.pause();
                    } else {
                      widget.handler.play();
                    }
                  },
                ),
                _RoundControlButton(
                  icon: Icons.forward_10_rounded,
                  tooltip: 'Вперёд на 10 секунд',
                  isCompact: isCompact,
                  onPressed: () => _seekBy(const Duration(seconds: 10)),
                ),
                _RoundControlButton(
                  icon: Icons.skip_next_rounded,
                  tooltip: 'Следующий трек',
                  isCompact: isCompact,
                  onPressed: () => widget.handler.skipToNext(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVolumeSection({bool isCompact = false}) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: GlassCard(
        borderRadius: isCompact ? 18 : 22,
        blur: 14,
        backgroundOpacity: 0.03,
        borderGradient: CyberpunkTheme.glassBorderGradientSoft,
        padding:
            EdgeInsets.fromLTRB(8, isCompact ? 0 : 2, 12, isCompact ? 0 : 2),
        child: StreamBuilder<double>(
          stream: widget.handler.volumeStream,
          initialData: widget.handler.currentVolume,
          builder: (context, snapshot) {
            final volume = (snapshot.data ?? widget.handler.currentVolume)
                .clamp(0.0, 1.0)
                .toDouble();
            final muted = volume <= 0.001;
            final icon = muted
                ? Icons.volume_off_rounded
                : volume < 0.5
                    ? Icons.volume_down_rounded
                    : Icons.volume_up_rounded;

            return Row(
              children: [
                Tooltip(
                  message: muted ? 'Включить звук' : 'Выключить звук',
                  child: IconButton(
                    onPressed: () => widget.handler.toggleMute(),
                    icon: Icon(icon, size: isCompact ? 19 : 21),
                    color: muted
                        ? Colors.white.withValues(alpha: 0.34)
                        : CyberpunkTheme.electricViolet,
                    splashRadius: 18,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: CyberpunkTheme.electricViolet,
                      inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
                      thumbColor: Colors.white,
                      overlayColor:
                          CyberpunkTheme.electricViolet.withValues(alpha: 0.14),
                      trackHeight: isCompact ? 2.5 : 3,
                      thumbShape: RoundSliderThumbShape(
                        enabledThumbRadius: isCompact ? 4.5 : 5,
                      ),
                      overlayShape: RoundSliderOverlayShape(
                        overlayRadius: isCompact ? 11 : 14,
                      ),
                    ),
                    child: Slider(
                      value: volume,
                      onChanged: widget.handler.setVolume,
                    ),
                  ),
                ),
                SizedBox(
                  width: 34,
                  child: Text(
                    '${(volume * 100).round()}%',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: CyberpunkTheme.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [ui.FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Lyrics container & auto-scrolling view
// -----------------------------------------------------------------------------
class _LyricsContainer extends StatelessWidget {
  final LyricsModel? lyrics;
  final bool isLoading;
  final NCPlayerHandler handler;
  final double height;
  final double width;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  const _LyricsContainer({
    super.key,
    required this.lyrics,
    required this.isLoading,
    required this.handler,
    required this.height,
    required this.width,
    required this.onSeek,
    required this.onRetry,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      width: width,
      height: height,
      borderRadius: 26,
      blur: 20,
      backgroundOpacity: 0.065,
      borderGradient: CyberpunkTheme.glassBorderGradient,
      glowColor: CyberpunkTheme.neonCyan,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: _buildInnerContent(),
    );
  }

  Widget _buildInnerContent() {
    if (isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: CyberpunkTheme.neonCyan,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'ЗАГРУЗКА КАРАОКЕ ТЕКСТА...',
              style: TextStyle(
                color: CyberpunkTheme.textSecondary,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'LRCLIB Cloud Lyrics',
              style: TextStyle(
                color: CyberpunkTheme.textMuted.withValues(alpha: 0.7),
                fontSize: 10,
              ),
            ),
          ],
        ),
      );
    }

    if (lyrics == null || lyrics!.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lyrics_outlined,
              size: 42,
              color: Colors.white.withValues(alpha: 0.28),
            ),
            const SizedBox(height: 12),
            Text(
              'ТЕКСТ НЕ НАЙДЕН',
              style: TextStyle(
                color: CyberpunkTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Слова для этого трека пока отсутствуют в базе LRCLIB',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CyberpunkTheme.textMuted,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  color: CyberpunkTheme.neonCyan,
                  tooltip: 'Повторить поиск текста',
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                  color: Colors.white.withValues(alpha: 0.4),
                  tooltip: 'Закрыть',
                ),
              ],
            ),
          ],
        ),
      );
    }

    return _SyncedLyricsList(
      lyrics: lyrics!,
      handler: handler,
      onSeek: onSeek,
    );
  }
}

class _SyncedLyricsList extends StatefulWidget {
  final LyricsModel lyrics;
  final NCPlayerHandler handler;
  final ValueChanged<Duration> onSeek;

  const _SyncedLyricsList({
    required this.lyrics,
    required this.handler,
    required this.onSeek,
  });

  @override
  State<_SyncedLyricsList> createState() => _SyncedLyricsListState();
}

class _SyncedLyricsListState extends State<_SyncedLyricsList> {
  final ScrollController _scrollController = ScrollController();
  int _lastActiveIndex = -1;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToIndex(int index, int totalCount) {
    if (index == _lastActiveIndex || !_scrollController.hasClients) return;
    _lastActiveIndex = index;

    const itemHeightEstimate = 48.0;
    final target = (index * itemHeightEstimate) - 80.0;
    final safeTarget = target.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    _scrollController.animateTo(
      safeTarget,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  int _findActiveIndex(List<LyricLine> lines, Duration currentPos) {
    if (lines.isEmpty) return -1;
    for (int i = lines.length - 1; i >= 0; i--) {
      if (lines[i].timestamp <= currentPos) {
        return i;
      }
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lyrics.lines;
    final isSynced = widget.lyrics.isSynced;

    return StreamBuilder<PositionData>(
      stream: widget.handler.positionDataStream,
      builder: (context, snapshot) {
        final position = snapshot.data?.position ?? Duration.zero;
        final activeIndex = isSynced ? _findActiveIndex(lines, position) : -1;

        if (isSynced && activeIndex >= 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToIndex(activeIndex, lines.length);
          });
        }

        return ListView.builder(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
          itemCount: lines.length,
          itemBuilder: (context, index) {
            final line = lines[index];
            final isActive = isSynced && index == activeIndex;
            final isPast = isSynced && index < activeIndex;

            return InkWell(
              onTap: () => widget.onSeek(line.timestamp),
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: isActive
                      ? CyberpunkTheme.neonCyan.withValues(alpha: 0.1)
                      : Colors.transparent,
                  border: Border.all(
                    color: isActive
                        ? CyberpunkTheme.neonCyan.withValues(alpha: 0.3)
                        : Colors.transparent,
                    width: 0.5,
                  ),
                ),
                child: Text(
                  line.text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isActive
                        ? CyberpunkTheme.neonCyan
                        : isPast
                            ? Colors.white.withValues(alpha: 0.55)
                            : Colors.white.withValues(alpha: 0.28),
                    fontSize: isActive ? 17 : 14.5,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    shadows: isActive
                        ? [
                            BoxShadow(
                              color: CyberpunkTheme.neonCyan
                                  .withValues(alpha: 0.45),
                              blurRadius: 16,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Private visual components
// -----------------------------------------------------------------------------
class _AmbientBackground extends StatelessWidget {
  final String? coverUrl;

  const _AmbientBackground({required this.coverUrl});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (coverUrl != null && coverUrl!.isNotEmpty)
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 54, sigmaY: 54),
                child: Transform.scale(
                  scale: 1.2,
                  child: Image.network(
                    coverUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => ColoredBox(
                      color: CyberpunkTheme.backgroundColor,
                    ),
                  ),
                ),
              ),
            )
          else
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: CyberpunkTheme.backgroundGradient,
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  ThemeController.colors.bgPrimary.withValues(alpha: 0.90),
                  ThemeController.colors.bgSurface.withValues(alpha: 0.72),
                  ThemeController.colors.bgPrimary.withValues(alpha: 0.98),
                ],
                stops: const [0.0, 0.48, 1.0],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Positioned(
            top: -150,
            right: -100,
            child: _GlowOrb(
              size: 420,
              color: CyberpunkTheme.neonCyan,
              opacity: 0.1,
            ),
          ),
          Positioned(
            bottom: -180,
            left: -130,
            child: _GlowOrb(
              size: 460,
              color: CyberpunkTheme.electricViolet,
              opacity: 0.13,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final double size;
  final Color color;
  final double opacity;

  const _GlowOrb({
    required this.size,
    required this.color,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: opacity),
            color.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  final String sourceName;

  const _SourceBadge({required this.sourceName});

  @override
  Widget build(BuildContext context) {
    final isHitmo = sourceName.toLowerCase().contains('hitmo');
    final color =
        isHitmo ? CyberpunkTheme.electricViolet : CyberpunkTheme.neonCyan;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: color.withValues(alpha: 0.25),
          width: 0.5,
        ),
      ),
      child: Text(
        sourceName.toUpperCase(),
        style: TextStyle(
          color: color.withValues(alpha: 0.9),
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _FavoriteButton extends StatelessWidget {
  final bool isFavorite;
  final bool isBusy;
  final VoidCallback onTap;

  const _FavoriteButton({
    required this.isFavorite,
    required this.isBusy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isFavorite ? 'Убрать из избранного' : 'В избранное',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: isBusy ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isFavorite
                ? CyberpunkTheme.electricViolet.withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: 0.04),
            border: Border.all(
              color: isFavorite
                  ? CyberpunkTheme.electricViolet.withValues(alpha: 0.45)
                  : Colors.white.withValues(alpha: 0.08),
              width: 0.5,
            ),
            boxShadow: isFavorite
                ? [
                    BoxShadow(
                      color:
                          CyberpunkTheme.electricViolet.withValues(alpha: 0.24),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: isBusy
              ? Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: CyberpunkTheme.electricViolet,
                    ),
                  ),
                )
              : Icon(
                  isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: 21,
                  color: isFavorite
                      ? CyberpunkTheme.electricViolet
                      : Colors.white.withValues(alpha: 0.48),
                ),
        ),
      ),
    );
  }
}

class _GlassCircleButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? activeColor;
  final VoidCallback onTap;

  const _GlassCircleButton({
    required this.icon,
    required this.tooltip,
    this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GlassCard(
        borderRadius: 22,
        blur: 12,
        backgroundOpacity: 0.04,
        borderGradient: activeColor != null
            ? LinearGradient(
                colors: [
                  activeColor!.withValues(alpha: 0.6),
                  CyberpunkTheme.electricViolet.withValues(alpha: 0.4),
                ],
              )
            : CyberpunkTheme.glassBorderGradientSoft,
        glowColor: activeColor,
        padding: EdgeInsets.zero,
        child: SizedBox(
          width: 44,
          height: 44,
          child: IconButton(
            onPressed: onTap,
            icon: Icon(icon, size: 24),
            color: activeColor ?? Colors.white.withValues(alpha: 0.76),
            splashRadius: 20,
          ),
        ),
      ),
    );
  }
}

class _RoundControlButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isCompact;
  final VoidCallback onPressed;

  const _RoundControlButton({
    required this.icon,
    required this.tooltip,
    this.isCompact = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final size = isCompact ? 36.0 : 42.0;
    final iconSize = isCompact ? 19.0 : 22.0;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.04),
        shape: CircleBorder(
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.075),
            width: 0.5,
          ),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              size: iconSize,
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
        ),
      ),
    );
  }
}

class _MainPlayButton extends StatelessWidget {
  final bool playing;
  final bool isLoading;
  final bool isCompact;
  final VoidCallback onPressed;

  const _MainPlayButton({
    required this.playing,
    required this.isLoading,
    this.isCompact = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final size = isCompact ? 54.0 : 64.0;
    final iconSize = isCompact ? 32.0 : 38.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: CyberpunkTheme.cyanVioletGradient,
        boxShadow: [
          BoxShadow(
            color: CyberpunkTheme.neonCyan.withValues(alpha: 0.26),
            blurRadius: 24,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: CyberpunkTheme.electricViolet.withValues(alpha: 0.22),
            blurRadius: 30,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Center(
            child: isLoading
                ? SizedBox(
                    width: isCompact ? 21 : 25,
                    height: isCompact ? 21 : 25,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.black,
                    ),
                  )
                : Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.black,
                    size: iconSize,
                  ),
          ),
        ),
      ),
    );
  }
}
