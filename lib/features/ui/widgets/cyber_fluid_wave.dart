import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../../../core/audio/audio_player_handler.dart';
import '../../../core/theme/cyberpunk_theme.dart';

/// Живой жидкостный сгусток "CyberFluidOrb" в стиле Яндекс Музыки (Моя Волна).
///
/// Органическая деформирующаяся сфера (Liquid Mesh / Metaball), которая:
/// - Во время воспроизведения: динамично деформируется, переливается градиентом
///   (Neon Green <-> Electric Violet <-> Cyan) и мягко пульсирует в такт.
/// - На паузе: плавно замедляется до медитативного левитирующего свечения.
class CyberFluidOrb extends StatefulWidget {
  final NCPlayerHandler? handler;
  final Stream<PlaybackState>? playbackStateStream;
  final bool? isPlaying;
  final double size;
  final Color? neonGreen;
  final Color? electricViolet;
  final Color? cyan;

  const CyberFluidOrb({
    super.key,
    this.handler,
    this.playbackStateStream,
    this.isPlaying,
    this.size = 150.0,
    this.neonGreen,
    this.electricViolet,
    this.cyan,
  });

  @override
  State<CyberFluidOrb> createState() => _CyberFluidOrbState();
}

class _CyberFluidOrbState extends State<CyberFluidOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  StreamSubscription<PlaybackState>? _playbackSub;

  bool _isPlaying = false;
  double _currentEnergy = 0.0; // 0.0 = paused/meditative, 1.0 = active playback
  double _time = 0.0;
  double _colorAngle = 0.0;
  int _lastTickMs = 0;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..addListener(_onTick);

    _controller.repeat();

    _setupStreamSubscription();
  }

  void _setupStreamSubscription() {
    if (widget.isPlaying != null) {
      _isPlaying = widget.isPlaying!;
      _currentEnergy = _isPlaying ? 1.0 : 0.0;
      return;
    }

    final stream = widget.playbackStateStream ??
        widget.handler?.playbackStateStream ??
        widget.handler?.playbackState;

    if (stream != null) {
      _playbackSub = stream.listen((state) {
        if (!mounted) return;
        final playing = state.playing;
        if (_isPlaying != playing) {
          setState(() {
            _isPlaying = playing;
          });
        }
      });

      // Инициализируем текущее состояние если доступно
      if (widget.handler != null) {
        _isPlaying = widget.handler!.playbackState.value.playing;
        _currentEnergy = _isPlaying ? 1.0 : 0.0;
      }
    }
  }

  @override
  void didUpdateWidget(covariant CyberFluidOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying && widget.isPlaying != null) {
      _isPlaying = widget.isPlaying!;
    }
    if (widget.handler != oldWidget.handler ||
        widget.playbackStateStream != oldWidget.playbackStateStream) {
      _playbackSub?.cancel();
      _setupStreamSubscription();
    }
  }

  void _onTick() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastTickMs == 0) _lastTickMs = now;
    final dt = ((now - _lastTickMs) / 1000.0).clamp(0.001, 0.05);
    _lastTickMs = now;

    // Плавная интерполяция энергии (0.0 -> 1.0 при старте, 1.0 -> 0.0 на паузе)
    final targetEnergy = _isPlaying ? 1.0 : 0.0;
    _currentEnergy += (targetEnergy - _currentEnergy) * 0.05;

    // Скорость анимации: медитативная на паузе, энергичная при игре
    final speed = ui.lerpDouble(0.45, 1.85, _currentEnergy)!;
    _time += dt * speed;

    // Вращение градиента
    final colorSpeed = ui.lerpDouble(0.35, 1.4, _currentEnergy)!;
    _colorAngle += dt * colorSpeed;

    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _playbackSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final green = widget.neonGreen ?? CyberpunkTheme.neonGreen;
    final violet = widget.electricViolet ?? CyberpunkTheme.electricViolet;
    final cyan = widget.cyan ?? CyberpunkTheme.neonCyan;

    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _CyberFluidOrbPainter(
            time: _time,
            colorAngle: _colorAngle,
            energy: _currentEnergy,
            colorGreen: green,
            colorViolet: violet,
            colorCyan: cyan,
          ),
        ),
      ),
    );
  }
}

class _CyberFluidOrbPainter extends CustomPainter {
  final double time;
  final double colorAngle;
  final double energy;
  final Color colorGreen;
  final Color colorViolet;
  final Color colorCyan;

  _CyberFluidOrbPainter({
    required this.time,
    required this.colorAngle,
    required this.energy,
    required this.colorGreen,
    required this.colorViolet,
    required this.colorCyan,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width * 0.33;

    // Ритмическая пульсация в такт при воспроизведении + мягкое дыхание на паузе
    final tempoPulse = math.sin(time * 3.8);
    final pulseScale = 1.0 +
        (0.065 * energy * (tempoPulse * tempoPulse)) +
        (0.02 * (1.0 - energy) * math.sin(time * 1.2));

    final effectiveRadius = baseRadius * pulseScale;

    // Генерация сглаженного контура сгустка (Liquid Metaball Path)
    final fluidPath = _createFluidPath(center, effectiveRadius, time, energy);

    // Вращающийся неоновый градиент (Neon Green <-> Electric Violet <-> Cyan)
    final gradientColors = [
      colorCyan,
      colorGreen,
      colorViolet,
      colorCyan,
    ];

    final sweepGradient = SweepGradient(
      center: Alignment.center,
      startAngle: 0.0,
      endAngle: math.pi * 2,
      transform: GradientRotation(colorAngle),
      colors: gradientColors,
      stops: const [0.0, 0.35, 0.72, 1.0],
    );

    final bounds = Rect.fromCircle(center: center, radius: effectiveRadius * 1.5);
    final gradientShader = sweepGradient.createShader(bounds);

    // 1. ВНЕШНЕЕ СВЕЧЕНИЕ (NEON GLOW BLOOM)
    final glowBlurRadius = ui.lerpDouble(18.0, 30.0, energy)!;
    final glowOpacity = ui.lerpDouble(0.35, 0.65, energy)!;

    final glowPaint = Paint()
      ..shader = gradientShader
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowBlurRadius)
      ..color = Colors.white.withValues(alpha: glowOpacity);

    canvas.drawPath(fluidPath, glowPaint);

    // 2. ВТОРИЧНОЕ ИНТЕНСИВНОЕ СВЕЧЕНИЕ СЕРДЦЕВИНЫ
    final coreGlowPaint = Paint()
      ..shader = gradientShader
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12.0)
      ..color = Colors.white.withValues(alpha: 0.5);

    canvas.drawPath(fluidPath, coreGlowPaint);

    // 3. ОСНОВНОЕ ЖИДКОСТНОЕ ТЕЛО СГУСТКА
    final bodyPaint = Paint()
      ..shader = gradientShader
      ..style = PaintingStyle.fill;

    canvas.drawPath(fluidPath, bodyPaint);

    // 4. ВНУТРЕННИЕ ПЛАВАЮЩИЕ МЕТАБОЛЫ (LIQUID MESH HIGHLIGHTS)
    canvas.save();
    canvas.clipPath(fluidPath);

    // Метабол 1 (Cyan/White highlight, циркулирующий внутри)
    final orb1Angle = time * 1.3;
    final orb1Dist = effectiveRadius * 0.38;
    final orb1Center = Offset(
      center.dx + math.cos(orb1Angle) * orb1Dist,
      center.dy + math.sin(orb1Angle * 0.9) * orb1Dist,
    );

    final innerOrb1Paint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.85),
          colorCyan.withValues(alpha: 0.6),
          colorCyan.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(
        Rect.fromCircle(center: orb1Center, radius: effectiveRadius * 0.55),
      );

    canvas.drawCircle(orb1Center, effectiveRadius * 0.55, innerOrb1Paint);

    // Метабол 2 (Electric Violet/Pink контрастный вихрь)
    final orb2Angle = -time * 1.1 + math.pi;
    final orb2Dist = effectiveRadius * 0.34;
    final orb2Center = Offset(
      center.dx + math.cos(orb2Angle) * orb2Dist,
      center.dy + math.sin(orb2Angle * 1.2) * orb2Dist,
    );

    final innerOrb2Paint = Paint()
      ..shader = RadialGradient(
        colors: [
          colorViolet.withValues(alpha: 0.75),
          colorViolet.withValues(alpha: 0.35),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(
        Rect.fromCircle(center: orb2Center, radius: effectiveRadius * 0.5),
      );

    canvas.drawCircle(orb2Center, effectiveRadius * 0.5, innerOrb2Paint);

    // Метабол 3 (Neon Green энергетическое ядро)
    final orb3Angle = time * 2.1;
    final orb3Dist = effectiveRadius * 0.22;
    final orb3Center = Offset(
      center.dx + math.sin(orb3Angle) * orb3Dist,
      center.dy + math.cos(orb3Angle) * orb3Dist,
    );

    final innerOrb3Paint = Paint()
      ..shader = RadialGradient(
        colors: [
          colorGreen.withValues(alpha: ui.lerpDouble(0.4, 0.8, energy)!),
          colorGreen.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 1.0],
      ).createShader(
        Rect.fromCircle(center: orb3Center, radius: effectiveRadius * 0.45),
      );

    canvas.drawCircle(orb3Center, effectiveRadius * 0.45, innerOrb3Paint);

    // Блик на верхней грани (Caustic Specular Gloss)
    final glossPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.5),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(
        Rect.fromCircle(center: center, radius: effectiveRadius),
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0);

    canvas.drawCircle(
      Offset(center.dx - effectiveRadius * 0.2, center.dy - effectiveRadius * 0.28),
      effectiveRadius * 0.35,
      glossPaint,
    );

    canvas.restore();

    // 5. ТОНКИЙ НЕОНОВЫЙ КОНТУР СГУСТКА
    final strokePaint = Paint()
      ..shader = sweepGradient.createShader(bounds)
      ..style = PaintingStyle.stroke
      ..strokeWidth = ui.lerpDouble(1.2, 2.0, energy)!
      ..color = Colors.white.withValues(alpha: 0.7);

    canvas.drawPath(fluidPath, strokePaint);
  }

  Path _createFluidPath(
    Offset center,
    double radius,
    double t,
    double energyValue,
  ) {
    const pointCount = 36;
    final points = <Offset>[];

    // Амплитуда волновых гармоник (сильнее при воспроизведении)
    final a1 = ui.lerpDouble(0.04, 0.12, energyValue)!;
    final a2 = ui.lerpDouble(0.03, 0.08, energyValue)!;
    final a3 = ui.lerpDouble(0.015, 0.05, energyValue)!;

    for (int i = 0; i < pointCount; i++) {
      final theta = (i * 2 * math.pi) / pointCount;

      // Суперпозиция гармонических колебаний для органической формы капли
      final harmonic1 = a1 * math.sin(2 * theta + t * 2.2);
      final harmonic2 = a2 * math.cos(3 * theta - t * 1.7 + 0.8);
      final harmonic3 = a3 * math.sin(5 * theta + t * 2.8 + 1.6);

      final r = radius * (1.0 + harmonic1 + harmonic2 + harmonic3);

      final x = center.dx + r * math.cos(theta);
      final y = center.dy + r * math.sin(theta);
      points.add(Offset(x, y));
    }

    final path = Path();
    if (points.isEmpty) return path;

    // Гладкий кубический Bézier сплайн через средние точки
    final firstMid = Offset(
      (points[0].dx + points[1].dx) / 2,
      (points[0].dy + points[1].dy) / 2,
    );
    path.moveTo(firstMid.dx, firstMid.dy);

    for (int i = 1; i < points.length; i++) {
      final current = points[i];
      final next = points[(i + 1) % points.length];
      final mid = Offset(
        (current.dx + next.dx) / 2,
        (current.dy + next.dy) / 2,
      );
      path.quadraticBezierTo(current.dx, current.dy, mid.dx, mid.dy);
    }

    // Замыкаем сплайн обратно на первую точку
    path.quadraticBezierTo(
      points[0].dx,
      points[0].dy,
      firstMid.dx,
      firstMid.dy,
    );
    path.close();

    return path;
  }

  @override
  bool shouldRepaint(covariant _CyberFluidOrbPainter oldDelegate) {
    return oldDelegate.time != time ||
        oldDelegate.energy != energy ||
        oldDelegate.colorAngle != colorAngle;
  }
}
