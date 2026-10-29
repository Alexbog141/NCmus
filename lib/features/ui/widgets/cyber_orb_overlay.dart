import 'dart:async';
import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/audio/audio_player_handler.dart';
import '../../../core/audio/position_data.dart';
import '../../../core/services/window_overlay_service.dart';

const Color _neonGreen = Color(0xFF00FF9D);
const Color _neonCyan = Color(0xFF00E5FF);
const Color _hudBackground = Color(0xF2090D16);
const Color _hudInk = Color(0xFF04110D);

/// The continuous morphing Cyber Orb HUD.
///
/// Single living widget structure:
/// - Collapsed: 56x56 glowing orb capsule inside 128x128 transparent window.
/// - Expanding / Collapsing: Continuous morphing from 56.0 to 340.0 px with
///   Curves.easeInOutCubic (250 ms). The AnchorOrb NEVER leaves the widget tree,
///   never disappears, and strictly stays at (36, 36) with size 56x56.
class CyberOrbOverlay extends StatefulWidget {
  final NCPlayerHandler handler;

  const CyberOrbOverlay({
    super.key,
    required this.handler,
  });

  @override
  State<CyberOrbOverlay> createState() => CyberOrbOverlayState();
}

class CyberOrbOverlayState extends State<CyberOrbOverlay>
    with TickerProviderStateMixin {
  static const double _orbDiameter = 56.0;
  static const double _expandedWidth = 340.0;
  static const double _capsuleHeight = 56.0;
  static const double _overlayWidth = 440.0;
  static const double _overlayHeight = 130.0;
  static const double _orbLeft = 36.0;
  static const double _orbTop = 36.0;

  final WindowOverlayService _service = WindowOverlayService.instance;

  /// True while the user drags the seek bar. The HUD-wide pan recognizer must
  /// not move the window in that case, otherwise a seek turns into a drag.
  bool _seeking = false;

  late final AnimationController _morphController;
  late final AnimationController _pulseController;
  late final AnimationController _entranceController;
  late final AnimationController _exitController;
  late final AnimationController _shockwaveController;
  late final Animation<double> _morphCurve;
  late final Animation<double> _entranceFade;
  late final Animation<double> _orbEntranceScale;
  late final Animation<double> _exitFade;
  late final Animation<double> _shockwaveScale;
  late final Animation<double> _waveAlpha;

  @visibleForTesting
  AnimationController get morphController => _morphController;

  @override
  void initState() {
    super.initState();

    _shockwaveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _shockwaveScale = Tween<double>(begin: 1.0, end: 2.2).animate(
      CurvedAnimation(
        parent: _shockwaveController,
        curve: Curves.easeOutCubic,
      ),
    );
    _waveAlpha = Tween<double>(begin: 0.9, end: 0.0).animate(
      CurvedAnimation(
        parent: _shockwaveController,
        curve: Curves.easeOutQuad,
      ),
    );
    _shockwaveController.forward();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _entranceFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Curves.easeInOutCubic,
      ),
    );
    _orbEntranceScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Curves.easeInOutCubic,
      ),
    );
    _entranceController.forward();

    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _exitController,
        curve: Curves.easeInOutCubic,
      ),
    );

    _morphController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _morphCurve = CurvedAnimation(
      parent: _morphController,
      curve: Curves.easeInOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );

    // Shrink the native window only after the capsule has fully retracted.
    _morphController.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) {
        unawaited(_service.handleWidgetCollapseComplete());
      }
    });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _service.onFadeOutOrb = _handleFadeOutOrb;
    _service.isExpanded.addListener(_syncExpansion);
    if (_service.isExpanded.value) {
      _morphController.value = 1.0;
    }
  }

  @override
  void dispose() {
    if (_service.onFadeOutOrb == _handleFadeOutOrb) {
      _service.onFadeOutOrb = null;
    }
    _service.isExpanded.removeListener(_syncExpansion);
    _shockwaveController.dispose();
    _exitController.dispose();
    _entranceController.dispose();
    _morphController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _handleFadeOutOrb() async {
    if (!mounted) return;
    await _exitController.forward(from: 0.0);
  }

  void _syncExpansion() {
    if (_service.isExpanded.value) {
      _morphController.forward();
      return;
    }

    _seeking = false;
    if (_morphController.value == 0.0) {
      unawaited(_service.handleWidgetCollapseComplete());
    } else {
      _morphController.reverse();
    }
  }

  void _handleOrbTap() {
    _service.resetIdleTimer();
    if (_morphController.isAnimating) {
      if (_morphController.status == AnimationStatus.forward) {
        unawaited(_service.collapseToOrb());
      } else {
        unawaited(_service.expandHud());
      }
      return;
    }
    _service.toggleExpand();
  }

  void _startWindowDrag() {
    _service.resetIdleTimer();
    if (_seeking) return;
    if (WindowOverlayService.isSupported) {
      unawaited(windowManager.startDragging());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: DefaultTextStyle(
        style: const TextStyle(
          color: Colors.white,
          decoration: TextDecoration.none,
        ),
        child: MouseRegion(
          cursor: SystemMouseCursors.basic,
          onEnter: (_) => _service.setPointerInside(true),
          onExit: (_) {
            _service.setPointerInside(false);
            _seeking = false;
          },
          onHover: (_) => _service.resetIdleTimer(),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: _overlayWidth,
              height: _overlayHeight,
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  _entranceController,
                  _exitController,
                  _shockwaveController,
                ]),
                builder: (context, _) {
                  final opacity =
                      (_entranceFade.value * _exitFade.value).clamp(0.0, 1.0);

                  return Opacity(
                    opacity: opacity,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // 1. Shockwave Ring (pulse wave centered at the 56x56 orb)
                        Positioned(
                          left: _orbLeft,
                          top: _orbTop,
                          width: _orbDiameter,
                          height: _orbDiameter,
                          child: IgnorePointer(
                            child: AnimatedBuilder(
                              animation: _shockwaveController,
                              builder: (context, _) {
                                if (_shockwaveController.value >= 1.0) {
                                  return const SizedBox.shrink();
                                }
                                return Transform.scale(
                                  scale: _shockwaveScale.value,
                                  alignment: Alignment.center,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: _neonGreen.withValues(
                                          alpha: _waveAlpha.value,
                                        ),
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),

                        // 2. The Living Morphing Capsule & Permanent Anchor Orb
                        Padding(
                          padding: const EdgeInsets.only(
                            left: _orbLeft,
                            top: _orbTop,
                          ),
                          child: AnimatedBuilder(
                            animation: _morphCurve,
                            builder: (context, child) {
                              // Width smoothly interpolates from 56.0 to 340.0:
                              final currentWidth = ui.lerpDouble(
                                _orbDiameter,
                                _expandedWidth,
                                _morphCurve.value,
                              )!;

                              return SizedBox(
                                width: currentWidth,
                                height: _capsuleHeight,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    // 2.1 Capsule background, neon border and glow
                                    Positioned.fill(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: _hudBackground,
                                          borderRadius:
                                              BorderRadius.circular(28.0),
                                          border: Border.all(
                                            color: _neonGreen
                                                .withValues(alpha: 0.5),
                                            width: 1.5,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: _neonGreen
                                                  .withValues(alpha: 0.25),
                                              blurRadius: 16,
                                              spreadRadius: 1,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    // 2.2 Sliding Controls Row (reveals to the right of the orb)
                                    if (_morphCurve.value > 0.05)
                                      Positioned(
                                        left: _orbDiameter,
                                        right: 0,
                                        top: 0,
                                        bottom: 0,
                                        child: ClipRRect(
                                          borderRadius:
                                              const BorderRadius.horizontal(
                                            right: Radius.circular(28.0),
                                          ),
                                          child: ClipRect(
                                            child: OverflowBox(
                                              alignment: Alignment.centerLeft,
                                              minWidth:
                                                  _expandedWidth - _orbDiameter,
                                              maxWidth:
                                                  _expandedWidth - _orbDiameter,
                                              minHeight: _capsuleHeight,
                                              maxHeight: _capsuleHeight,
                                              child: Opacity(
                                                opacity:
                                                    ((_morphCurve.value - 0.05) /
                                                            0.95)
                                                        .clamp(0.0, 1.0),
                                                child: _buildControlsRow(),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),

                                    // 2.3 Permanent Anchor Orb (ALWAYS present, strictly 56x56 at (0,0), never unmounted)
                                    Positioned(
                                      left: 0,
                                      top: 0,
                                      width: _orbDiameter,
                                      height: _orbDiameter,
                                      child: Tooltip(
                                        message: 'Свернуть / развернуть HUD',
                                        waitDuration:
                                            const Duration(milliseconds: 700),
                                        child: MouseRegion(
                                          cursor: SystemMouseCursors.click,
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: _handleOrbTap,
                                            onPanStart: (_) {
                                              _service.resetIdleTimer();
                                              if (WindowOverlayService
                                                  .isSupported) {
                                                unawaited(windowManager
                                                    .startDragging()
                                                    .catchError((_) {}));
                                              }
                                            },
                                            onPanUpdate: (_) {
                                              _service.resetIdleTimer();
                                              if (WindowOverlayService
                                                  .isSupported) {
                                                unawaited(windowManager
                                                    .startDragging()
                                                    .catchError((_) {}));
                                              }
                                            },
                                            child: SizedBox(
                                              key: const Key(
                                                  'cyber_anchor_orb'),
                                              width: _orbDiameter,
                                              height: _orbDiameter,
                                              child: ScaleTransition(
                                                scale: _orbEntranceScale,
                                                alignment: Alignment.center,
                                                child: _buildOrbContent(),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Permanent Anchor Orb Content
  // ---------------------------------------------------------------------------
  Widget _buildOrbContent() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final pulse =
            Curves.easeInOutCubic.transform(_pulseController.value);
        final glow = 0.28 + 0.22 * pulse;

        return Container(
          width: _orbDiameter,
          height: _orbDiameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 0.7 * pulse, -1.0),
              end: Alignment(1.0 - 0.7 * pulse, 1.0),
              colors: [
                Color.lerp(_neonGreen, _neonCyan, pulse)!,
                Color.lerp(_neonCyan, _neonGreen, pulse)!,
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.20),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: _neonGreen.withValues(alpha: glow),
                blurRadius: 10 + 6 * pulse,
                spreadRadius: 1,
              ),
              BoxShadow(
                color: _neonCyan.withValues(alpha: glow * 0.7),
                blurRadius: 14 + 8 * pulse,
                spreadRadius: 1,
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.graphic_eq_rounded,
              color: _hudInk,
              size: 26,
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Controls Row (Revealed smoothly inside the morphing capsule)
  // ---------------------------------------------------------------------------
  Widget _buildControlsRow() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _service.resetIdleTimer,
      onPanStart: (_) => _startWindowDrag(),
      onPanUpdate: (_) => _startWindowDrag(),
      child: Padding(
        padding: const EdgeInsets.only(
          left: 8.0,
          right: 12.0,
          top: 4.0,
          bottom: 4.0,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTrackInfo(),
                  const SizedBox(height: 2),
                  _MicroTimeline(
                    handler: widget.handler,
                    onSeekStart: () => _seeking = true,
                    onSeekEnd: () => _seeking = false,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _buildTransportControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackInfo() {
    return StreamBuilder<MediaItem?>(
      stream: widget.handler.mediaItem,
      builder: (context, snapshot) {
        final item = snapshot.data ?? widget.handler.currentItem;
        final title = item?.title ?? 'NCmus';
        final artist = item?.artist ?? 'Нет активного трека';

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _neonCyan.withValues(alpha: 0.82),
                fontSize: 10,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTransportControls() {
    return StreamBuilder<PlaybackState>(
      stream: widget.handler.playbackStateStream,
      builder: (context, snapshot) {
        final state = snapshot.data;
        final playing = state?.playing ?? false;
        final processing = state?.processingState ?? AudioProcessingState.idle;
        final isLoading = processing == AudioProcessingState.loading ||
            processing == AudioProcessingState.buffering;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _HudIconButton(
              icon: Icons.skip_previous_rounded,
              tooltip: 'Предыдущий трек',
              size: 26,
              iconSize: 16,
              onTap: () {
                unawaited(widget.handler.skipToPrevious());
                _service.resetIdleTimer();
              },
            ),
            const SizedBox(width: 2),
            _HudPlayButton(
              playing: playing,
              isLoading: isLoading,
              size: 30,
              iconSize: 18,
              onTap: () {
                if (playing) {
                  unawaited(widget.handler.pause());
                } else {
                  unawaited(widget.handler.play());
                }
                _service.resetIdleTimer();
              },
            ),
            const SizedBox(width: 2),
            _HudIconButton(
              icon: Icons.skip_next_rounded,
              tooltip: 'Следующий трек',
              size: 26,
              iconSize: 16,
              onTap: () {
                unawaited(widget.handler.skipToNext());
                _service.resetIdleTimer();
              },
            ),
            const SizedBox(width: 2),
            _HudIconButton(
              icon: Icons.open_in_full_rounded,
              tooltip: 'Развернуть плеер',
              size: 26,
              iconSize: 15,
              onTap: () {
                unawaited(_service.restoreApp());
              },
            ),
          ],
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Micro timeline
// -----------------------------------------------------------------------------
class _MicroTimeline extends StatelessWidget {
  final NCPlayerHandler handler;
  final VoidCallback onSeekStart;
  final VoidCallback onSeekEnd;

  const _MicroTimeline({
    required this.handler,
    required this.onSeekStart,
    required this.onSeekEnd,
  });

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

        return LayoutBuilder(
          builder: (context, constraints) {
            void seekTo(double dx) {
              if (duration <= Duration.zero || constraints.maxWidth <= 0) {
                return;
              }
              final fraction =
                  (dx / constraints.maxWidth).clamp(0.0, 1.0).toDouble();
              unawaited(
                handler.seek(
                  Duration(
                    milliseconds: (duration.inMilliseconds * fraction).round(),
                  ),
                ),
              );
              WindowOverlayService.instance.resetIdleTimer();
            }

            return Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) {
                if ((event.buttons & 1) == 0) return;
                onSeekStart();
                seekTo(event.localPosition.dx);
              },
              onPointerMove: (event) {
                if ((event.buttons & 1) == 0) return;
                seekTo(event.localPosition.dx);
              },
              onPointerUp: (_) => onSeekEnd(),
              onPointerCancel: (_) => onSeekEnd(),
              child: SizedBox(
                height: 10,
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(1),
                    child: SizedBox(
                      height: 2,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                          FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: progress,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [_neonGreen, _neonCyan],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _neonCyan.withValues(alpha: 0.55),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
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
// Small HUD controls
// -----------------------------------------------------------------------------
class _HudIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final double size;
  final double iconSize;
  final VoidCallback onTap;

  const _HudIconButton({
    required this.icon,
    required this.tooltip,
    this.size = 26,
    this.iconSize = 16,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 700),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(
                icon,
                size: iconSize,
                color: Colors.white.withValues(alpha: 0.78),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HudPlayButton extends StatelessWidget {
  final bool playing;
  final bool isLoading;
  final double size;
  final double iconSize;
  final VoidCallback onTap;

  const _HudPlayButton({
    required this.playing,
    required this.isLoading,
    this.size = 30,
    this.iconSize = 18,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: playing ? 'Пауза' : 'Воспроизвести',
      waitDuration: const Duration(milliseconds: 700),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [_neonGreen, _neonCyan],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: _neonGreen.withValues(alpha: 0.35),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Center(
                child: isLoading
                    ? SizedBox(
                        width: iconSize * 0.65,
                        height: iconSize * 0.65,
                        child: const CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: _hudInk,
                        ),
                      )
                    : Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: _hudInk,
                        size: iconSize,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
