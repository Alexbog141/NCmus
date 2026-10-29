import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../../../core/audio/audio_player_handler.dart';
import '../../../core/theme/cyberpunk_theme.dart';

/// Animated neon equalizer visualizer with 4–5 bouncing vertical bars.
///
/// Automatically reacts to playback state:
/// - When playing: smooth randomized bar oscillations with neon glow.
/// - When paused/stopped: smoothly drops bars to [minHeight] (4px) and freezes.
class CyberVisualizer extends StatefulWidget {
  final NCPlayerHandler? handler;
  final bool? isPlaying;
  final int barCount;
  final double maxHeight;
  final double minHeight;
  final double barWidth;
  final Color? color;

  const CyberVisualizer({
    super.key,
    this.handler,
    this.isPlaying,
    this.barCount = 4,
    this.maxHeight = 22,
    this.minHeight = 4,
    this.barWidth = 3,
    this.color,
  });

  @override
  State<CyberVisualizer> createState() => _CyberVisualizerState();
}

class _CyberVisualizerState extends State<CyberVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final Random _random = Random();
  late List<double> _baseHeights;
  late List<double> _targetHeights;

  @override
  void initState() {
    super.initState();
    _baseHeights = List.filled(widget.barCount, widget.minHeight);
    _targetHeights = List.generate(
      widget.barCount,
      (_) => _nextRandomHeight(),
    );

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )
      ..addListener(_onTick)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed ||
            status == AnimationStatus.dismissed) {
          _randomizeTargets();
        }
      });
  }

  double _nextRandomHeight() {
    return widget.minHeight +
        _random.nextDouble() * (widget.maxHeight - widget.minHeight);
  }

  void _randomizeTargets() {
    _baseHeights = List.from(_targetHeights);
    _targetHeights = List.generate(
      widget.barCount,
      (_) => _nextRandomHeight(),
    );
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  void _updateAnimationState(bool playing) {
    if (playing) {
      if (!_controller.isAnimating) {
        _randomizeTargets();
        _controller.repeat(reverse: true);
      }
    } else {
      if (_controller.isAnimating) {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveColor = widget.color ?? ThemeController.colors.neonPrimary;

    Widget renderBars(bool playing) {
      _updateAnimationState(playing);
      final t = _controller.value;

      return SizedBox(
        height: widget.maxHeight + 2,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(widget.barCount, (index) {
            final double h;
            if (playing) {
              final b = index < _baseHeights.length
                  ? _baseHeights[index]
                  : widget.minHeight;
              final target = index < _targetHeights.length
                  ? _targetHeights[index]
                  : widget.maxHeight;
              h = (b + (target - b) * t).clamp(widget.minHeight, widget.maxHeight);
            } else {
              h = widget.minHeight;
            }

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: widget.barWidth,
              height: h,
              decoration: BoxDecoration(
                color: effectiveColor,
                borderRadius: BorderRadius.circular(2),
                boxShadow: playing
                    ? [
                        BoxShadow(
                          color: effectiveColor.withValues(alpha: 0.65),
                          blurRadius: 6,
                          spreadRadius: 0.5,
                        ),
                      ]
                    : null,
              ),
            );
          }),
        ),
      );
    }

    if (widget.isPlaying != null) {
      return renderBars(widget.isPlaying!);
    }

    if (widget.handler != null) {
      return StreamBuilder<PlaybackState>(
        stream: widget.handler!.playbackState,
        builder: (context, snapshot) {
          final playing = snapshot.data?.playing ?? false;
          return renderBars(playing);
        },
      );
    }

    return renderBars(false);
  }
}
