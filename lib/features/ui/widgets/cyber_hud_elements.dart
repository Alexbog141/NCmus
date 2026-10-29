import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/audio/audio_player_handler.dart';
import '../../../core/theme/cyberpunk_theme.dart';
import '../../scraper/models/scraped_track.dart';

// =============================================================================
// А. CyberRadarScanner (Анимированный радар на CustomPainter)
// =============================================================================

/// Premium Cyberpunk Radar Scanner with rotating sweep beam, concentric neon
/// grid rings, wandering radar target blips, and central telemetry readout.
class CyberRadarScanner extends StatefulWidget {
  final double size;
  final Color? color;
  final int matchedCount;
  final int disputedCount;
  final int notFoundCount;
  final bool isScanning;
  final String statusText;

  const CyberRadarScanner({
    super.key,
    this.size = 200,
    this.color,
    this.matchedCount = 0,
    this.disputedCount = 0,
    this.notFoundCount = 0,
    this.isScanning = true,
    this.statusText = 'SCANNING AUDIO SIGNATURES...',
  });

  @override
  State<CyberRadarScanner> createState() => _CyberRadarScannerState();
}

class _CyberRadarScannerState extends State<CyberRadarScanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweepController;
  final Random _rng = Random(42);
  late final List<_RadarBlip> _blips;

  @override
  void initState() {
    super.initState();
    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    // Generate futuristic coordinates around the radar
    _blips = List.generate(8, (i) {
      final angle = _rng.nextDouble() * 2 * pi;
      final radiusFactor = 0.25 + _rng.nextDouble() * 0.65;
      return _RadarBlip(
        angle: angle,
        radiusFactor: radiusFactor,
        colorType: i % 3, // 0 = green (100%), 1 = amber (disputed), 2 = red (not found)
      );
    });
  }

  @override
  void dispose() {
    _sweepController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = widget.color ?? ThemeController.colors.neonPrimary;
    final secondary = ThemeController.colors.neonSecondary;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer glow halo
                Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: primary.withValues(alpha: widget.isScanning ? 0.25 : 0.1),
                        blurRadius: 32,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                ),

                // Radar Painter Canvas
                AnimatedBuilder(
                  animation: _sweepController,
                  builder: (context, _) {
                    return CustomPaint(
                      size: Size(widget.size, widget.size),
                      painter: _RadarCanvasPainter(
                        sweepAngle: _sweepController.value * 2 * pi,
                        primaryColor: primary,
                        secondaryColor: secondary,
                        blips: _blips,
                        isScanning: widget.isScanning,
                      ),
                    );
                  },
                ),

                // Central Tech Reticle Chip
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.8),
                    border: Border.all(
                      color: primary.withValues(alpha: 0.8),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: primary.withValues(alpha: 0.4),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      Icons.radar_rounded,
                      color: primary,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Running telemetry banner
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: primary.withValues(alpha: 0.3),
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.isScanning ? CyberpunkTheme.neonGreen : primary,
                      boxShadow: [
                        BoxShadow(
                          color: (widget.isScanning ? CyberpunkTheme.neonGreen : primary)
                              .withValues(alpha: 0.8),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      widget.statusText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RadarBlip {
  final double angle;
  final double radiusFactor;
  final int colorType;

  const _RadarBlip({
    required this.angle,
    required this.radiusFactor,
    required this.colorType,
  });
}

class _RadarCanvasPainter extends CustomPainter {
  final double sweepAngle;
  final Color primaryColor;
  final Color secondaryColor;
  final List<_RadarBlip> blips;
  final bool isScanning;

  _RadarCanvasPainter({
    required this.sweepAngle,
    required this.primaryColor,
    required this.secondaryColor,
    required this.blips,
    required this.isScanning,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 1. Grid Rings
    final ringPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (final factor in [0.28, 0.52, 0.76, 1.0]) {
      canvas.drawCircle(center, radius * factor, ringPaint);
    }

    // Outer bold ring
    final outerRing = Paint()
      ..color = primaryColor.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawCircle(center, radius, outerRing);

    // 2. Compass Tick Marks along outer border
    final tickPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.4)
      ..strokeWidth = 1.0;

    for (int deg = 0; deg < 360; deg += 15) {
      final rad = deg * pi / 180;
      final isMajor = deg % 45 == 0;
      final tickLen = isMajor ? 6.0 : 3.0;
      final p1 = Offset(
        center.dx + (radius - tickLen) * cos(rad),
        center.dy + (radius - tickLen) * sin(rad),
      );
      final p2 = Offset(
        center.dx + radius * cos(rad),
        center.dy + radius * sin(rad),
      );
      canvas.drawLine(p1, p2, tickPaint);
    }

    // 3. Crosshairs Axis Lines
    final crossPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.15)
      ..strokeWidth = 0.8;
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      crossPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      crossPaint,
    );

    if (isScanning) {
      // 4. Sweeping Tail Sector (Conic gradient behind the sweep line)
      final sweepPath = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(
          Rect.fromCircle(center: center, radius: radius),
          sweepAngle - (pi / 3),
          pi / 3,
          false,
        )
        ..close();

      final sweepShader = SweepGradient(
        center: FractionalOffset.center,
        startAngle: sweepAngle - (pi / 3),
        endAngle: sweepAngle,
        colors: [
          Colors.transparent,
          primaryColor.withValues(alpha: 0.28),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

      final tailPaint = Paint()
        ..shader = sweepShader
        ..style = PaintingStyle.fill;
      canvas.drawPath(sweepPath, tailPaint);

      // 5. Main Sweep Line with glow
      final sweepLineEnd = Offset(
        center.dx + radius * cos(sweepAngle),
        center.dy + radius * sin(sweepAngle),
      );

      final sweepLinePaint = Paint()
        ..color = primaryColor.withValues(alpha: 0.95)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      canvas.drawLine(center, sweepLineEnd, sweepLinePaint);
    }

    // 6. Target Blips
    for (final blip in blips) {
      final pos = Offset(
        center.dx + (radius * blip.radiusFactor) * cos(blip.angle),
        center.dy + (radius * blip.radiusFactor) * sin(blip.angle),
      );

      // Angular distance from sweep line for trail glow
      double angleDiff = (sweepAngle - blip.angle) % (2 * pi);
      if (angleDiff < 0) angleDiff += 2 * pi;

      // Brightness fades as sweep line moves away
      final double brightness = isScanning ? (1.0 - (angleDiff / (2 * pi))).clamp(0.2, 1.0) : 0.6;

      Color blipColor;
      if (blip.colorType == 0) {
        blipColor = CyberpunkTheme.neonGreen;
      } else if (blip.colorType == 1) {
        blipColor = CyberpunkTheme.neonAmber;
      } else {
        blipColor = CyberpunkTheme.neonPink;
      }

      final dotPaint = Paint()
        ..color = blipColor.withValues(alpha: brightness)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, 3.5, dotPaint);

      // Blip pulse ring
      final ringBlip = Paint()
        ..color = blipColor.withValues(alpha: brightness * 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawCircle(pos, 7.0, ringBlip);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarCanvasPainter oldDelegate) => true;
}

// =============================================================================
// Б. CyberStepPipeline (Премиальный неоновый степпер шагов)
// =============================================================================

class CyberStepItem {
  final String stepNumber;
  final String title;

  const CyberStepItem({
    required this.stepNumber,
    required this.title,
  });
}

/// 4-step pipeline: [ 01 ВХОД ] —— [ 02 РАДАР ] —— [ 03 ПРОВЕРКА ] —— [ 04 ФИНАЛ ]
class CyberStepPipeline extends StatefulWidget {
  final int currentStep; // 0, 1, 2, 3
  final List<CyberStepItem> steps;
  final ValueChanged<int>? onStepTapped;

  const CyberStepPipeline({
    super.key,
    required this.currentStep,
    this.steps = const [
      CyberStepItem(stepNumber: '01', title: 'ВХОД'),
      CyberStepItem(stepNumber: '02', title: 'РАДАР'),
      CyberStepItem(stepNumber: '03', title: 'ПРОВЕРКА'),
      CyberStepItem(stepNumber: '04', title: 'ФИНАЛ'),
    ],
    this.onStepTapped,
  });

  @override
  State<CyberStepPipeline> createState() => _CyberStepPipelineState();
}

class _CyberStepPipelineState extends State<CyberStepPipeline>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = ThemeController.colors.neonPrimary;
    final secondary = ThemeController.colors.neonSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 0.5,
        ),
      ),
      child: Row(
        children: List.generate(widget.steps.length * 2 - 1, (index) {
          if (index.isOdd) {
            // Connector line between step (index ~/ 2) and (index ~/ 2 + 1)
            final prevStep = index ~/ 2;
            final isPassed = prevStep < widget.currentStep;
            final isActiveSegment = prevStep == widget.currentStep - 1;

            return Expanded(
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, _) {
                  return Container(
                    height: 2.5,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      gradient: isPassed
                          ? LinearGradient(
                              colors: [
                                primary,
                                secondary,
                              ],
                            )
                          : (isActiveSegment
                              ? LinearGradient(
                                  colors: [
                                    primary,
                                    primary.withValues(alpha: 0.2),
                                  ],
                                )
                              : null),
                      color: (!isPassed && !isActiveSegment)
                          ? Colors.white.withValues(alpha: 0.08)
                          : null,
                      boxShadow: isPassed
                          ? [
                              BoxShadow(
                                color: primary.withValues(alpha: 0.4),
                                blurRadius: 6,
                              ),
                            ]
                          : null,
                    ),
                  );
                },
              ),
            );
          }

          final stepIdx = index ~/ 2;
          final step = widget.steps[stepIdx];
          final isCurrent = stepIdx == widget.currentStep;
          final isCompleted = stepIdx < widget.currentStep;

          return _buildStepBadge(
            step: step,
            stepIndex: stepIdx,
            isCurrent: isCurrent,
            isCompleted: isCompleted,
            primary: primary,
            secondary: secondary,
          );
        }),
      ),
    );
  }

  Widget _buildStepBadge({
    required CyberStepItem step,
    required int stepIndex,
    required bool isCurrent,
    required bool isCompleted,
    required Color primary,
    required Color secondary,
  }) {
    Color badgeColor;
    Color textColor;
    Border? border;
    List<BoxShadow>? shadows;

    if (isCurrent) {
      badgeColor = primary;
      textColor = Colors.black;
      shadows = [
        BoxShadow(
          color: primary.withValues(alpha: 0.65),
          blurRadius: 16,
          spreadRadius: 2,
        ),
      ];
    } else if (isCompleted) {
      badgeColor = primary.withValues(alpha: 0.2);
      textColor = primary;
      border = Border.all(color: primary.withValues(alpha: 0.6), width: 1);
    } else {
      badgeColor = Colors.white.withValues(alpha: 0.04);
      textColor = Colors.white.withValues(alpha: 0.35);
      border = Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5);
    }

    return InkWell(
      onTap: widget.onStepTapped != null ? () => widget.onStepTapped!(stepIndex) : null,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isCurrent ? null : badgeColor,
          gradient: isCurrent
              ? LinearGradient(
                  colors: [primary, secondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          borderRadius: BorderRadius.circular(12),
          border: border,
          boxShadow: shadows,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isCompleted) ...[
              Icon(
                Icons.check_rounded,
                size: 14,
                color: primary,
              ),
              const SizedBox(width: 4),
            ] else ...[
              Text(
                step.stepNumber,
                style: TextStyle(
                  color: isCurrent ? Colors.black : textColor,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              step.title,
              style: TextStyle(
                color: isCurrent ? Colors.black : textColor,
                fontSize: 11,
                fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// В. MiniAudioWavePreview (Миниатюрная звуковая волна с предпросмотром 5 сек)
// =============================================================================

/// Compact preview button with animated 6-bar neon audio visualizer.
/// Automatically limits preview playback to 5 seconds.
class MiniAudioWavePreview extends StatefulWidget {
  final ScrapedTrack? track;
  final NCPlayerHandler? handler;
  final VoidCallback? onPlaySnippet;

  const MiniAudioWavePreview({
    super.key,
    this.track,
    this.handler,
    this.onPlaySnippet,
  });

  @override
  State<MiniAudioWavePreview> createState() => _MiniAudioWavePreviewState();
}

class _MiniAudioWavePreviewState extends State<MiniAudioWavePreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveController;
  bool _isPlaying = false;
  Timer? _autoStopTimer;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
  }

  @override
  void dispose() {
    _autoStopTimer?.cancel();
    _waveController.dispose();
    super.dispose();
  }

  void _togglePreview() {
    if (_isPlaying) {
      _stopPreview();
    } else {
      _startPreview();
    }
  }

  void _startPreview() {
    setState(() => _isPlaying = true);
    _waveController.repeat(reverse: true);

    widget.onPlaySnippet?.call();

    // If a handler is provided and track has a streamUrl, initiate preview
    if (widget.handler != null && widget.track != null) {
      try {
        widget.handler!.playMediaItem(widget.track!.toMediaItem());
      } catch (_) {}
    }

    _autoStopTimer?.cancel();
    _autoStopTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        _stopPreview();
      }
    });
  }

  void _stopPreview() {
    _autoStopTimer?.cancel();
    if (mounted) {
      setState(() => _isPlaying = false);
      _waveController.stop();
      _waveController.reset();
    }

    if (widget.handler != null) {
      try {
        widget.handler!.pause();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = ThemeController.colors.neonPrimary;

    return InkWell(
      onTap: _togglePreview,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: _isPlaying
              ? primary.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _isPlaying ? primary : Colors.white.withValues(alpha: 0.1),
            width: _isPlaying ? 1.0 : 0.5,
          ),
          boxShadow: _isPlaying
              ? [
                  BoxShadow(
                    color: primary.withValues(alpha: 0.35),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
              size: 16,
              color: _isPlaying ? primary : Colors.white.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 6),
            // 6-bar mini wave visualizer
            SizedBox(
              height: 14,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(6, (i) {
                  return AnimatedBuilder(
                    animation: _waveController,
                    builder: (context, _) {
                      final h = _isPlaying
                          ? (4.0 + (sin((_waveController.value * 2 * pi) + (i * 0.8)).abs() * 10))
                          : 3.5;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 1.0),
                        width: 2.2,
                        height: h,
                        decoration: BoxDecoration(
                          color: _isPlaying ? primary : Colors.white.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      );
                    },
                  );
                }),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              _isPlaying ? '0:05' : 'ПРЕВЬЮ',
              style: TextStyle(
                color: _isPlaying ? primary : CyberpunkTheme.textMuted,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Г. CyberShimmerProgressBar (Неоновый прогресс-бар со световым бликом)
// =============================================================================

class CyberShimmerProgressBar extends StatefulWidget {
  final double progress; // 0.0 to 1.0
  final double height;
  final Color? color;
  final Color? secondaryColor;

  const CyberShimmerProgressBar({
    super.key,
    required this.progress,
    this.height = 7,
    this.color,
    this.secondaryColor,
  });

  @override
  State<CyberShimmerProgressBar> createState() => _CyberShimmerProgressBarState();
}

class _CyberShimmerProgressBarState extends State<CyberShimmerProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = widget.color ?? ThemeController.colors.neonPrimary;
    final secondary = widget.secondaryColor ?? ThemeController.colors.neonSecondary;
    final clampedProgress = widget.progress.clamp(0.0, 1.0);

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(widget.height),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 0.5,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final filledWidth = constraints.maxWidth * clampedProgress;

          return Stack(
            children: [
              // Filled bar
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: filledWidth,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(widget.height),
                  gradient: LinearGradient(
                    colors: [primary, secondary],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: primary.withValues(alpha: 0.45),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),

              // Moving Shimmer light reflection
              if (clampedProgress > 0)
                AnimatedBuilder(
                  animation: _shimmerController,
                  builder: (context, _) {
                    final shimmerOffset =
                        (constraints.maxWidth * _shimmerController.value) % filledWidth;

                    return Positioned(
                      left: shimmerOffset - 30,
                      top: 0,
                      bottom: 0,
                      width: 50,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(widget.height),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                Colors.white.withValues(alpha: 0.6),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}
