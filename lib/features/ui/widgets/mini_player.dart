import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../../../core/audio/audio_player_handler.dart';
import '../../../core/audio/position_data.dart';
import '../../../core/database/database_service.dart';
import '../../../core/services/window_overlay_service.dart';
import '../../../core/theme/cyberpunk_theme.dart';
import '../../storage/models/track_entity.dart';
import '../../wave/services/nc_wave_service.dart';
import 'cyber_visualizer.dart';
import 'fullscreen_player.dart';

/// Floating glass mini-player that lives above the app navigation.
///
/// Features a strict 3-column layout on desktop (> 720px):
/// - Column A (left, fixed ~280px): 48x48 cover + Title & Artist + Like button.
/// - Column B (center, expanded): Transport controls (Dislike, Prev, Play/Pause, Next) + Timeline slider.
/// - Column C (right, fixed ~280px): Volume controls + Fullscreen expand button.
///
/// Automatically adapts to mobile screens (<= 720px) with responsive compact controls.
class MiniPlayer extends StatelessWidget {
  final NCPlayerHandler handler;

  const MiniPlayer({
    super.key,
    required this.handler,
  });

  void _openFullscreenPlayer(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (context, animation, secondaryAnimation) =>
            FullscreenPlayerModal(handler: handler),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem,
      builder: (context, snapshot) {
        final item = snapshot.data;

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return SizeTransition(
              sizeFactor: animation,
              alignment: Alignment.topCenter,
              child: FadeTransition(opacity: animation, child: child),
            );
          },
          child: item == null
              ? const SizedBox.shrink(key: ValueKey('ncmus_mini_empty'))
              : Padding(
                  key: const ValueKey('ncmus_mini_active'),
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isDesktop = constraints.maxWidth > 720;
                      return _buildCard(context, item, isDesktop: isDesktop);
                    },
                  ),
                ),
        );
      },
    );
  }

  Widget _buildCard(
    BuildContext context,
    MediaItem item, {
    required bool isDesktop,
  }) {
    final neonPrimary = ThemeController.colors.neonPrimary;
    final neonSecondary = ThemeController.colors.neonSecondary;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -150) {
          // Swipe left -> next track
          handler.skipToNext();
        } else if (velocity > 150) {
          // Swipe right -> previous track
          handler.skipToPrevious();
        }
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            // Ambient Glow: soft blurred aura in tone of active theme
            BoxShadow(
              color: neonPrimary.withValues(alpha: 0.15),
              blurRadius: 30,
              spreadRadius: 2,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: neonSecondary.withValues(alpha: 0.08),
              blurRadius: 40,
              spreadRadius: 1,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: GlassCard(
          borderRadius: 20,
          blur: 18,
          backgroundOpacity: 0.065,
          borderGradient: CyberpunkTheme.glassBorderGradient,
          glowColor: neonPrimary,
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isDesktop) _MiniProgressLine(handler: handler),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                child: isDesktop
                    ? _buildDesktop3Columns(context, item)
                    : _buildMobileRow(context, item),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Desktop 3-Column Layout
  // ---------------------------------------------------------------------------
  Widget _buildDesktop3Columns(BuildContext context, MediaItem item) {
    final coverUrl = item.artUri?.toString();
    final isDownloaded = item.extras?['isDownloaded'] as bool? ?? false;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // A. ЛЕВАЯ КОЛОНКА (SizedBox(width: 280))
        SizedBox(
          width: 280,
          child: Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openFullscreenPlayer(context),
                child: _HeroCover(coverUrl: coverUrl),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openFullscreenPlayer(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          if (isDownloaded) ...[
                            Icon(
                              Icons.offline_pin_rounded,
                              size: 13,
                              color: CyberpunkTheme.neonGreen,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: CyberpunkTheme.textPrimary,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          CyberVisualizer(
                            handler: handler,
                            maxHeight: 14,
                            barCount: 4,
                            color: ThemeController.colors.neonPrimary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.artist ?? 'Unknown Artist',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color:
                              CyberpunkTheme.neonCyan.withValues(alpha: 0.72),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _MiniFavoriteButton(item: item),
            ],
          ),
        ),

        // Б. ЦЕНТРАЛЬНАЯ КОЛОНКА (Expanded(child: ...))
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MiniTransportButtons(handler: handler, mediaItem: item),
                const SizedBox(height: 2),
                _MiniTimelineSlider(handler: handler),
              ],
            ),
          ),
        ),

        // В. ПРАВАЯ КОЛОНКА (SizedBox(width: 280))
        SizedBox(
          width: 280,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _MiniVolumeControl(handler: handler),
              const SizedBox(width: 8),
              if (WindowOverlayService.isSupported) ...[
                _TransportButton(
                  icon: Icons.blur_on_rounded,
                  tooltip: 'Cyber Orb HUD (поверх всех окон)',
                  onPressed: () {
                    unawaited(WindowOverlayService.instance.enableOverlay());
                  },
                ),
                const SizedBox(width: 4),
              ],
              _TransportButton(
                icon: Icons.fullscreen_rounded,
                tooltip: 'Развернуть плеер',
                onPressed: () => _openFullscreenPlayer(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Mobile Adaptive Layout
  // ---------------------------------------------------------------------------
  Widget _buildMobileRow(BuildContext context, MediaItem item) {
    final coverUrl = item.artUri?.toString();
    final isDownloaded = item.extras?['isDownloaded'] as bool? ?? false;

    return Row(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openFullscreenPlayer(context),
          child: _HeroCover(coverUrl: coverUrl),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openFullscreenPlayer(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (isDownloaded) ...[
                      Icon(
                        Icons.offline_pin_rounded,
                        size: 12,
                        color: CyberpunkTheme.neonGreen,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: CyberpunkTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    CyberVisualizer(
                      handler: handler,
                      maxHeight: 12,
                      barCount: 3,
                      color: ThemeController.colors.neonPrimary,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  item.artist ?? 'Unknown Artist',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: CyberpunkTheme.neonCyan.withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        _MiniFavoriteButton(item: item),
        _MiniDislikeButton(
          mediaItem: item,
          handler: handler,
        ),
        StreamBuilder<PlaybackState>(
          stream: handler.playbackState,
          builder: (context, snapshot) {
            final state = snapshot.data;
            final playing = state?.playing ?? false;
            final processing =
                state?.processingState ?? AudioProcessingState.idle;
            final isLoading = processing == AudioProcessingState.loading ||
                processing == AudioProcessingState.buffering;

            return _NeonPlayButton(
              playing: playing,
              isLoading: isLoading,
              size: 40,
              onPressed: () {
                if (playing) {
                  handler.pause();
                } else {
                  handler.play();
                }
              },
            );
          },
        ),
        _TransportButton(
          icon: Icons.skip_next_rounded,
          tooltip: 'Следующий трек',
          onPressed: () => handler.skipToNext(),
        ),
        _MiniShuffleButton(handler: handler),
        if (WindowOverlayService.isSupported)
          _TransportButton(
            icon: Icons.blur_on_rounded,
            tooltip: 'Cyber Orb HUD (поверх всех окон)',
            onPressed: () {
              unawaited(WindowOverlayService.instance.enableOverlay());
            },
          ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Timeline & Seek Slider
// -----------------------------------------------------------------------------
class _MiniTimelineSlider extends StatefulWidget {
  final NCPlayerHandler handler;

  const _MiniTimelineSlider({required this.handler});

  @override
  State<_MiniTimelineSlider> createState() => _MiniTimelineSliderState();
}

class _MiniTimelineSliderState extends State<_MiniTimelineSlider> {
  double? _dragValue;

  String _formatDuration(Duration duration) {
    if (duration <= Duration.zero) return '0:00';
    final minutes = duration.inMinutes.remainder(60).toString();
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      final hours = duration.inHours.toString();
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PositionData>(
      stream: widget.handler.positionDataStream,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final position = data?.position ?? Duration.zero;
        final duration = data?.duration ?? Duration.zero;
        final maxMs = duration.inMilliseconds.toDouble();
        final currentMs = position.inMilliseconds.toDouble().clamp(
              0.0,
              maxMs > 0 ? maxMs : 1.0,
            );
        final sliderValue = (_dragValue ?? currentMs).clamp(
          0.0,
          maxMs > 0 ? maxMs : 1.0,
        );

        return Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            SizedBox(
              width: 34,
              child: Text(
                _formatDuration(position),
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: CyberpunkTheme.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2.5,
                  activeTrackColor: CyberpunkTheme.neonCyan,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.08),
                  thumbColor: Colors.white,
                  overlayColor: CyberpunkTheme.neonCyan.withValues(alpha: 0.16),
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 4),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                ),
                child: Slider(
                  value: maxMs > 0 ? sliderValue : 0.0,
                  min: 0.0,
                  max: maxMs > 0 ? maxMs : 1.0,
                  onChanged: maxMs > 0
                      ? (value) {
                          setState(() {
                            _dragValue = value;
                          });
                        }
                      : null,
                  onChangeEnd: maxMs > 0
                      ? (value) {
                          widget.handler.seek(
                            Duration(milliseconds: value.toInt()),
                          );
                          setState(() {
                            _dragValue = null;
                          });
                        }
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 34,
              child: Text(
                _formatDuration(duration),
                textAlign: TextAlign.left,
                style: TextStyle(
                  color: CyberpunkTheme.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Dislike Button with Visual Feedback
// -----------------------------------------------------------------------------
class _MiniDislikeButton extends StatefulWidget {
  final MediaItem mediaItem;
  final NCPlayerHandler handler;

  const _MiniDislikeButton({
    required this.mediaItem,
    required this.handler,
  });

  @override
  State<_MiniDislikeButton> createState() => _MiniDislikeButtonState();
}

class _MiniDislikeButtonState extends State<_MiniDislikeButton> {
  bool _isDisliked = false;
  StreamSubscription<void>? _librarySub;

  @override
  void initState() {
    super.initState();
    _checkBlacklist();
    _librarySub = DatabaseService.instance.libraryChanges.listen((_) {
      _checkBlacklist();
    });
  }

  @override
  void didUpdateWidget(covariant _MiniDislikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaItem.id != widget.mediaItem.id ||
        oldWidget.mediaItem.title != widget.mediaItem.title ||
        oldWidget.mediaItem.artist != widget.mediaItem.artist) {
      _checkBlacklist();
    }
  }

  @override
  void dispose() {
    _librarySub?.cancel();
    super.dispose();
  }

  Future<void> _checkBlacklist() async {
    final title = widget.mediaItem.title;
    final artist = widget.mediaItem.artist ?? '';
    final isBlacklisted =
        await DatabaseService.instance.isTrackBlacklisted(title, artist);
    if (mounted) {
      setState(() => _isDisliked = isBlacklisted);
    }
  }

  Future<void> _handleDislikeToggle() async {
    final title = widget.mediaItem.title;
    final artist = widget.mediaItem.artist ?? '';

    if (_isDisliked) {
      // Un-dislike: remove ban from SQLite and in-memory caches
      setState(() => _isDisliked = false);
      try {
        await DatabaseService.instance.removeFromBlacklist(title, artist);
        await widget.handler.removeFromBlacklist(widget.mediaItem);
      } catch (_) {}
    } else {
      // Dislike: add to blacklist and immediately skip track
      setState(() => _isDisliked = true);
      await Future.delayed(const Duration(milliseconds: 200));
      try {
        if (NCWaveService.instance != null) {
          await NCWaveService.instance!.dislikeCurrentTrack(widget.mediaItem);
        } else {
          await widget.handler.blacklistCurrentTrack(widget.mediaItem);
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    const neonPink = Color(0xFFFF2A6D);

    return Tooltip(
      message: _isDisliked
          ? 'В чёрном списке (нажмите, чтобы убрать)'
          : 'Не нравится (в чёрный список)',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: _isDisliked
              ? [
                  BoxShadow(
                    color: neonPink.withValues(alpha: 0.55),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: IconButton(
          onPressed: _handleDislikeToggle,
          icon: Icon(
            _isDisliked ? Icons.thumb_down : Icons.thumb_down_outlined,
            size: 20,
            color:
                _isDisliked ? neonPink : Colors.white.withValues(alpha: 0.72),
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 36, height: 38),
          splashRadius: 18,
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Transport Controls Row (Center)
// -----------------------------------------------------------------------------
class _MiniTransportButtons extends StatelessWidget {
  final NCPlayerHandler handler;
  final MediaItem mediaItem;

  const _MiniTransportButtons({
    required this.handler,
    required this.mediaItem,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackState>(
      stream: handler.playbackState,
      builder: (context, snapshot) {
        final state = snapshot.data;
        final playing = state?.playing ?? false;
        final processing = state?.processingState ?? AudioProcessingState.idle;
        final isLoading = processing == AudioProcessingState.loading ||
            processing == AudioProcessingState.buffering;

        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _MiniDislikeButton(
              mediaItem: mediaItem,
              handler: handler,
            ),
            const SizedBox(width: 8),
            _TransportButton(
              icon: Icons.skip_previous_rounded,
              tooltip: 'Предыдущий трек',
              onPressed: () => handler.skipToPrevious(),
            ),
            const SizedBox(width: 10),
            _NeonPlayButton(
              playing: playing,
              isLoading: isLoading,
              size: 44,
              onPressed: () {
                if (playing) {
                  handler.pause();
                } else {
                  handler.play();
                }
              },
            ),
            const SizedBox(width: 10),
            _TransportButton(
              icon: Icons.skip_next_rounded,
              tooltip: 'Следующий трек',
              onPressed: () => handler.skipToNext(),
            ),
            const SizedBox(width: 8),
            _MiniShuffleButton(handler: handler),
          ],
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Shuffle Button
// -----------------------------------------------------------------------------
class _MiniShuffleButton extends StatelessWidget {
  final NCPlayerHandler handler;

  const _MiniShuffleButton({required this.handler});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackState>(
      stream: handler.playbackStateStream,
      builder: (context, snapshot) {
        final shuffleMode =
            snapshot.data?.shuffleMode ?? AudioServiceShuffleMode.none;
        final isActive = shuffleMode == AudioServiceShuffleMode.all ||
            shuffleMode == AudioServiceShuffleMode.group ||
            handler.isShuffleActive;

        return Tooltip(
          message: isActive
              ? 'Случайный порядок включен'
              : 'Включить случайный порядок (Shuffle)',
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: CyberpunkTheme.neonGreen.withValues(alpha: 0.55),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: IconButton(
              onPressed: () => handler.toggleShuffleMode(),
              icon: const Icon(Icons.shuffle_rounded),
              iconSize: 20,
              color: isActive
                  ? CyberpunkTheme.neonGreen
                  : Colors.white.withValues(alpha: 0.4),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 36, height: 38),
              splashRadius: 18,
            ),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Favorite Button
// -----------------------------------------------------------------------------
class _MiniFavoriteButton extends StatefulWidget {
  final MediaItem item;

  const _MiniFavoriteButton({required this.item});

  @override
  State<_MiniFavoriteButton> createState() => _MiniFavoriteButtonState();
}

class _MiniFavoriteButtonState extends State<_MiniFavoriteButton> {
  bool _isFavorite = false;
  StreamSubscription<void>? _sub;

  String get _trackId =>
      widget.item.extras?['originalId']?.toString() ?? widget.item.id;

  @override
  void initState() {
    super.initState();
    _checkFavorite();
    _sub =
        DatabaseService.instance.libraryChanges.listen((_) => _checkFavorite());
  }

  @override
  void didUpdateWidget(covariant _MiniFavoriteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _checkFavorite();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _checkFavorite() async {
    try {
      final track = await DatabaseService.instance.getTrack(_trackId);
      if (mounted) {
        setState(() {
          _isFavorite = track?.isFavorite ?? false;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggle() async {
    final next = !_isFavorite;
    setState(() => _isFavorite = next);
    try {
      final existing = await DatabaseService.instance.getTrack(_trackId);
      if (existing == null) {
        final entity = TrackEntity(
          id: _trackId,
          title: widget.item.title,
          artist: widget.item.artist ?? 'Unknown Artist',
          duration: widget.item.duration ?? Duration.zero,
          streamUrl: widget.item.id,
          coverUrl: widget.item.artUri?.toString(),
          sourceName: widget.item.extras?['sourceName']?.toString() ?? 'Hitmo',
          isFavorite: next,
          createdAt: DateTime.now(),
        );
        await DatabaseService.instance.insertOrUpdateTrack(entity);
      } else {
        await DatabaseService.instance.toggleFavorite(_trackId, next);
      }
    } catch (_) {
      if (mounted) setState(() => _isFavorite = !next);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _isFavorite ? 'Удалить из избранного' : 'Добавить в избранное',
      child: IconButton(
        onPressed: _toggle,
        icon: Icon(
          _isFavorite ? Icons.favorite : Icons.favorite_border,
          size: 20,
          color: _isFavorite
              ? const Color(0xFFFF2A6D)
              : ThemeController.colors.textSecondary.withValues(alpha: 0.5),
        ),
        splashRadius: 18,
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Small Helpers: Cover, Play Button, Progress Line, Volume
// -----------------------------------------------------------------------------
class _MiniProgressLine extends StatelessWidget {
  final NCPlayerHandler handler;

  const _MiniProgressLine({required this.handler});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PositionData>(
      stream: handler.positionDataStream,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final position = data?.position ?? Duration.zero;
        final duration = data?.duration ?? Duration.zero;
        final progress = duration > Duration.zero
            ? (position.inMilliseconds / duration.inMilliseconds)
                .clamp(0.0, 1.0)
                .toDouble()
            : 0.0;

        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: SizedBox(
            height: 2.5,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: Colors.white.withValues(alpha: 0.045),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: progress,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: CyberpunkTheme.cyanVioletGradient,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HeroCover extends StatefulWidget {
  final String? coverUrl;

  const _HeroCover({required this.coverUrl});

  @override
  State<_HeroCover> createState() => _HeroCoverState();
}

class _HeroCoverState extends State<_HeroCover> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = ThemeController.colors;

    return Hero(
      tag: 'player_cover',
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isHovered
                  ? colors.neonPrimary.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.08),
              width: _isHovered ? 1.0 : 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: colors.neonPrimary
                    .withValues(alpha: _isHovered ? 0.35 : 0.16),
                blurRadius: _isHovered ? 18 : 14,
                spreadRadius: 1,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11.5),
            child: widget.coverUrl != null && widget.coverUrl!.isNotEmpty
                ? Image.network(
                    widget.coverUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const _MiniCoverFallback(),
                  )
                : const _MiniCoverFallback(),
          ),
        ),
      ),
    );
  }
}

class _MiniCoverFallback extends StatelessWidget {
  const _MiniCoverFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            ThemeController.colors.bgSurface,
            ThemeController.colors.cardGlass,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.graphic_eq_rounded,
          color: CyberpunkTheme.neonCyan,
          size: 22,
        ),
      ),
    );
  }
}

class _TransportButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _TransportButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 21),
        color: Colors.white.withValues(alpha: 0.72),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 36, height: 38),
        splashRadius: 18,
      ),
    );
  }
}

class _NeonPlayButton extends StatelessWidget {
  final bool playing;
  final bool isLoading;
  final VoidCallback onPressed;
  final double size;

  const _NeonPlayButton({
    required this.playing,
    required this.isLoading,
    required this.onPressed,
    this.size = 46,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: CyberpunkTheme.cyanVioletGradient,
        boxShadow: [
          BoxShadow(
            color: CyberpunkTheme.neonCyan.withValues(alpha: 0.3),
            blurRadius: 18,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: CyberpunkTheme.electricViolet.withValues(alpha: 0.22),
            blurRadius: 22,
            spreadRadius: 1,
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
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.black,
                    size: size * 0.6,
                  ),
          ),
        ),
      ),
    );
  }
}

class _MiniVolumeControl extends StatelessWidget {
  final NCPlayerHandler handler;

  const _MiniVolumeControl({required this.handler});

  IconData _iconFor(double volume) {
    if (volume <= 0.001) return Icons.volume_off_rounded;
    if (volume < 0.5) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: handler.volumeStream,
      initialData: handler.currentVolume,
      builder: (context, snapshot) {
        final volume =
            (snapshot.data ?? handler.currentVolume).clamp(0.0, 1.0).toDouble();
        final muted = volume <= 0.001;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: muted ? 'Включить звук' : 'Выключить звук',
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => handler.toggleMute(),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    _iconFor(volume),
                    size: 19,
                    color: muted
                        ? Colors.white.withValues(alpha: 0.36)
                        : CyberpunkTheme.neonCyan.withValues(alpha: 0.86),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 2),
            SizedBox(
              width: 100,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: CyberpunkTheme.electricViolet,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
                  thumbColor: Colors.white,
                  overlayColor:
                      CyberpunkTheme.electricViolet.withValues(alpha: 0.14),
                  trackHeight: 2.5,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 4.5,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 10,
                  ),
                ),
                child: Slider(
                  value: volume,
                  onChanged: handler.setVolume,
                ),
              ),
            ),
            SizedBox(
              width: 26,
              child: Text(
                '${(volume * 100).round()}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.36),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
