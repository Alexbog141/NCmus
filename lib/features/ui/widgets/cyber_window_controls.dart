import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/services/window_overlay_service.dart';
import '../../../core/theme/cyberpunk_theme.dart';

/// Desktop window controls designed with a cyberpunk HUD neon aesthetic.
///
/// Contains buttons for:
/// 1. [ 🫧 ] Transition into the Cyber Orb overlay.
/// 2. [ — ] Minimize to system taskbar.
/// 3. [ 🗖 ] Maximize / Restore toggle.
/// 4. [ ✕ ] Close application (with soft-red hover effect).
///
/// Strictly renders only on desktop platforms (Windows, Linux, macOS).
class CyberWindowControls extends StatefulWidget {
  final double height;

  const CyberWindowControls({
    super.key,
    this.height = 30.0,
  });

  /// True if running on Windows desktop.
  static bool get isDesktop {
    if (kIsWeb) return false;
    return Platform.isWindows;
  }

  static bool get isWindows {
    if (kIsWeb) return false;
    return Platform.isWindows;
  }

  @override
  State<CyberWindowControls> createState() => _CyberWindowControlsState();
}

class _CyberWindowControlsState extends State<CyberWindowControls>
    with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    if (CyberWindowControls.isWindows) {
      windowManager.addListener(this);
      _updateMaximizedState();
    }
  }

  @override
  void dispose() {
    if (CyberWindowControls.isWindows) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  Future<void> _updateMaximizedState() async {
    try {
      final maximized = await windowManager.isMaximized();
      if (mounted) {
        setState(() => _isMaximized = maximized);
      }
    } catch (_) {}
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  @override
  void onWindowRestore() {
    if (mounted) setState(() => _isMaximized = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!CyberWindowControls.isWindows) {
      return const SizedBox.shrink();
    }

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 0.5,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. [ 🫧 ] Cyber Orb overlay
          _CyberWindowButton(
            tooltip: 'Мини-сферка HUD',
            icon: Icons.bubble_chart_rounded,
            accentColor: CyberpunkTheme.neonGreen,
            isOrbButton: true,
            onPressed: () => WindowOverlayService.instance.enableOverlay(),
          ),
          const SizedBox(width: 2),

          // 2. [ — ] Minimize
          _CyberWindowButton(
            tooltip: 'Свернуть',
            icon: Icons.remove_rounded,
            onPressed: () => windowManager.minimize(),
          ),
          const SizedBox(width: 2),

          // 3. [ 🗖 ] Maximize / Restore
          _CyberWindowButton(
            tooltip: _isMaximized ? 'Восстановить' : 'Развернуть',
            icon: _isMaximized
                ? Icons.filter_none_rounded
                : Icons.crop_square_rounded,
            iconSize: _isMaximized ? 13.0 : 14.5,
            onPressed: () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
                if (mounted) setState(() => _isMaximized = false);
              } else {
                await windowManager.maximize();
                if (mounted) setState(() => _isMaximized = true);
              }
            },
          ),
          const SizedBox(width: 2),

          // 4. [ ✕ ] Close
          _CyberWindowButton(
            tooltip: 'Закрыть',
            icon: Icons.close_rounded,
            isClose: true,
            onPressed: () => windowManager.close(),
          ),
        ],
      ),
    );
  }
}

class _CyberWindowButton extends StatefulWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final Color? accentColor;
  final bool isClose;
  final bool isOrbButton;
  final double iconSize;

  const _CyberWindowButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.accentColor,
    this.isClose = false,
    this.isOrbButton = false,
    this.iconSize = 15.0,
  });

  @override
  State<_CyberWindowButton> createState() => _CyberWindowButtonState();
}

class _CyberWindowButtonState extends State<_CyberWindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    Color iconColor;
    List<BoxShadow>? shadows;

    if (widget.isClose) {
      if (_isHovered) {
        backgroundColor = Colors.red.withValues(alpha: 0.8);
        iconColor = Colors.white;
        shadows = [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.5),
            blurRadius: 8,
          ),
        ];
      } else {
        backgroundColor = Colors.transparent;
        iconColor = Colors.white.withValues(alpha: 0.65);
      }
    } else if (widget.isOrbButton) {
      if (_isHovered) {
        backgroundColor = CyberpunkTheme.neonGreen.withValues(alpha: 0.16);
        iconColor = CyberpunkTheme.neonGreen;
        shadows = [
          BoxShadow(
            color: CyberpunkTheme.neonGreen.withValues(alpha: 0.45),
            blurRadius: 10,
          ),
        ];
      } else {
        backgroundColor = Colors.transparent;
        iconColor = CyberpunkTheme.neonGreen.withValues(alpha: 0.85);
      }
    } else {
      if (_isHovered) {
        backgroundColor = Colors.white.withValues(alpha: 0.10);
        iconColor = CyberpunkTheme.neonCyan;
        shadows = [
          BoxShadow(
            color: CyberpunkTheme.neonCyan.withValues(alpha: 0.3),
            blurRadius: 6,
          ),
        ];
      } else {
        backgroundColor = Colors.transparent;
        iconColor = Colors.white.withValues(alpha: 0.65);
      }
    }

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            width: 32,
            height: 24,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(6),
              boxShadow: shadows,
            ),
            child: Center(
              child: Icon(
                widget.icon,
                size: widget.iconSize,
                color: iconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
