import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/audio/audio_player_handler.dart';
import '../../../core/database/database_service.dart';
import '../../../core/theme/cyberpunk_theme.dart';
import '../../library/services/local_storage_service.dart';
import '../../wave/services/nc_wave_service.dart';
import '../../wave/services/wave_service.dart';
import '../widgets/cyber_window_controls.dart';
import '../widgets/mini_player.dart';
import 'home_wave_screen.dart';
import 'library_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'sync_screen.dart';

/// Responsive NCmus shell: glass sidebar on wide screens, floating bottom
/// navigation on mobile. The mini-player sits above navigation in both modes.
class HomeShell extends StatefulWidget {
  final NCPlayerHandler handler;

  const HomeShell({
    super.key,
    required this.handler,
  });

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;
  late final List<Widget> _screens;
  StreamSubscription<String>? _waveStatusSub;

  static const List<_NavDestination> _destinations = <_NavDestination>[
    _NavDestination(
      icon: Icons.graphic_eq_rounded,
      activeIcon: Icons.graphic_eq_rounded,
      label: 'Главная',
      shortLabel: 'Главная',
    ),
    _NavDestination(
      icon: Icons.search_rounded,
      activeIcon: Icons.manage_search_rounded,
      label: 'Поиск треков',
      shortLabel: 'Поиск',
    ),
    _NavDestination(
      icon: Icons.library_music_outlined,
      activeIcon: Icons.library_music_rounded,
      label: 'Медиатека',
      shortLabel: 'Медиатека',
    ),
    _NavDestination(
      icon: Icons.sync_rounded,
      activeIcon: Icons.sync_rounded,
      label: 'Синхронизация',
      shortLabel: 'Синхронизация',
    ),
    _NavDestination(
      icon: Icons.tune_rounded,
      activeIcon: Icons.tune_rounded,
      label: 'Настройки',
      shortLabel: 'Настройки',
    ),
  ];

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalHardwareKey);
    _screens = <Widget>[
      HomeWaveScreen(handler: widget.handler),
      SearchScreen(handler: widget.handler),
      LibraryScreen(handler: widget.handler),
      const SyncScreen(),
      SettingsScreen(handler: widget.handler),
    ];

    // Background scan of Music/NCmus folder on app startup
    unawaited(LocalStorageService.instance.scanAndSyncLocalFolder());

    _waveStatusSub = WaveService.instance.statusMessages.listen((message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.wifi_off_rounded,
                  color: CyberpunkTheme.neonPink, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF141322),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: CyberpunkTheme.neonPink.withValues(alpha: 0.6),
              width: 0.8,
            ),
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _waveStatusSub?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleGlobalHardwareKey);
    super.dispose();
  }

  void _selectTab(int index) {
    if (_currentIndex == index) return;
    setState(() => _currentIndex = index);
  }

  bool _handleGlobalHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    // СТРОГАЯ ПРОВЕРКА: если курсор находится в ЛЮБОМ текстовом поле:
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null && focus.context != null) {
      final isEditable = focus.context!.widget is EditableText ||
          focus.context!.findAncestorWidgetOfExactType<EditableText>() != null;
      if (isEditable) return false; // Пропускаем событие текстовому полю!
    }

    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    // Space: Play/Pause
    if (event.logicalKey == LogicalKeyboardKey.space) {
      _togglePlayPause();
      return true;
    }

    // Ctrl + Right: Следующий трек | Right: +5 сек
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (isCtrl) {
        widget.handler.skipToNext();
      } else {
        _seekRelative(const Duration(seconds: 5));
      }
      return true;
    }

    // Ctrl + Left: Предыдущий трек | Left: -5 сек
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (isCtrl) {
        widget.handler.skipToPrevious();
      } else {
        _seekRelative(const Duration(seconds: -5));
      }
      return true;
    }

    // L: Лайк
    if (event.logicalKey == LogicalKeyboardKey.keyL) {
      _toggleFavorite();
      return true;
    }

    // D: Дизлайк
    if (event.logicalKey == LogicalKeyboardKey.keyD) {
      _dislikeCurrentTrack();
      return true;
    }

    return false;
  }

  void _togglePlayPause() {
    final playing = widget.handler.playbackState.value.playing;
    if (playing) {
      widget.handler.pause();
    } else {
      widget.handler.play();
    }
  }

  void _seekRelative(Duration delta) {
    final current = widget.handler.currentPosition;
    final total = widget.handler.currentDuration;
    final target = current + delta;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (total > Duration.zero && target > total ? total : target);
    widget.handler.seek(clamped);
  }

  Future<void> _toggleFavorite() async {
    final item = widget.handler.currentItem;
    if (item == null) return;
    final trackId = item.extras?['originalId']?.toString() ?? item.id;
    final db = DatabaseService.instance;
    final entity = await db.getTrack(trackId);
    final isFav = entity?.isFavorite ?? (item.extras?['isFavorite'] == true);
    await db.toggleFavorite(trackId, !isFav);
  }

  Future<void> _dislikeCurrentTrack() async {
    final item = widget.handler.currentItem;
    if (item == null) return;
    final isBanned = await DatabaseService.instance
        .isTrackBlacklisted(item.title, item.artist ?? '');
    if (isBanned) {
      await DatabaseService.instance
          .removeFromBlacklist(item.title, item.artist ?? '');
      await widget.handler.removeFromBlacklist(item);
    } else {
      if (NCWaveService.instance != null) {
        await NCWaveService.instance!.dislikeCurrentTrack(item);
      } else {
        await widget.handler.blacklistCurrentTrack(item);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CyberpunkTheme.backgroundColor,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _AppBackdrop(),
          LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth > 720;
              return isDesktop ? _buildDesktopLayout() : _buildMobileLayout();
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Desktop
  // ---------------------------------------------------------------------------
  Widget _buildDesktopLayout() {
    return Row(
      children: [
        SizedBox(
          width: 252,
          child: _buildSidebar(),
        ),
        Expanded(
          child: SafeArea(
            left: false,
            bottom: false,
            child: Column(
              children: [
                _buildHeaderBar(isDesktop: true),
                Expanded(
                  child: ClipRect(
                    child: IndexedStack(
                      index: _currentIndex,
                      children: _screens,
                    ),
                  ),
                ),
                MiniPlayer(handler: widget.handler),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSidebar() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: CyberpunkTheme.surfaceColor.withValues(alpha: 0.62),
            border: Border(
              right: BorderSide(
                color: Colors.white.withValues(alpha: 0.06),
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            right: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: CyberpunkTheme.neonCyan
                                            .withValues(alpha: 0.28),
                                        blurRadius: 16,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.asset(
                                      'assets/icon/app_icon.png',
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'NCMUS',
                                      style: TextStyle(
                                        color: CyberpunkTheme.textPrimary,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 2.6,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      ThemeController.currentPreset.value.name
                                          .toUpperCase(),
                                      style: TextStyle(
                                        color: CyberpunkTheme.neonCyan,
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.6,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Divider(
                            color: Colors.white.withValues(alpha: 0.055),
                            height: 1,
                            thickness: 0.5,
                          ),
                          const SizedBox(height: 18),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              'НАВИГАЦИЯ',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.24),
                                fontSize: 8.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          for (var i = 0; i < _destinations.length; i++)
                            _buildSidebarItem(
                              index: i,
                              destination: _destinations[i],
                            ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarItem({
    required int index,
    required _NavDestination destination,
  }) {
    final isSelected = _currentIndex == index;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _selectTab(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 11,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: isSelected
                  ? LinearGradient(
                      colors: [
                        CyberpunkTheme.neonCyan.withValues(alpha: 0.11),
                        CyberpunkTheme.electricViolet.withValues(alpha: 0.07),
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    )
                  : null,
              border: Border.all(
                color: isSelected
                    ? CyberpunkTheme.neonCyan.withValues(alpha: 0.2)
                    : Colors.transparent,
                width: 0.5,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: CyberpunkTheme.neonCyan.withValues(alpha: 0.06),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    color: isSelected
                        ? CyberpunkTheme.neonCyan.withValues(alpha: 0.1)
                        : Colors.white.withValues(alpha: 0.025),
                    border: Border.all(
                      color: isSelected
                          ? CyberpunkTheme.neonCyan.withValues(alpha: 0.22)
                          : Colors.white.withValues(alpha: 0.045),
                      width: 0.5,
                    ),
                  ),
                  child: Icon(
                    isSelected ? destination.activeIcon : destination.icon,
                    size: 18,
                    color: isSelected
                        ? CyberpunkTheme.neonCyan
                        : Colors.white.withValues(alpha: 0.38),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    destination.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected
                          ? CyberpunkTheme.textPrimary
                          : Colors.white.withValues(alpha: 0.5),
                      fontSize: 12.5,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                if (isSelected)
                  Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: CyberpunkTheme.neonCyan,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Mobile
  // ---------------------------------------------------------------------------
  Widget _buildMobileLayout() {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          _buildHeaderBar(isDesktop: false),
          Expanded(
            child: ClipRect(
              child: IndexedStack(
                index: _currentIndex,
                children: _screens,
              ),
            ),
          ),
          MiniPlayer(handler: widget.handler),
          _buildBottomNavigation(),
        ],
      ),
    );
  }

  Widget _buildHeaderBar({required bool isDesktop}) {
    final currentDest = _destinations[_currentIndex];

    return _withDesktopDrag(
      Padding(
        padding: EdgeInsets.fromLTRB(
          isDesktop ? 22 : 16,
          isDesktop ? 12 : 8,
          isDesktop ? 22 : 16,
          isDesktop ? 6 : 4,
        ),
        child: Row(
          children: [
            if (!isDesktop) ...[
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: CyberpunkTheme.neonCyan.withValues(alpha: 0.25),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/icon/app_icon.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'NCMUS',
                    style: TextStyle(
                      color: CyberpunkTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.2,
                    ),
                  ),
                  Text(
                    currentDest.shortLabel.toUpperCase(),
                    style: TextStyle(
                      color: CyberpunkTheme.neonCyan,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                    ),
                  ),
                ],
              ),
            ] else ...[
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: CyberpunkTheme.neonCyan.withValues(alpha: 0.2),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/icon/app_icon.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                currentDest.label.toUpperCase(),
                style: TextStyle(
                  color: CyberpunkTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                ),
              ),
            ],
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 0.5,
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
                      color: CyberpunkTheme.neonGreen,
                      boxShadow: [
                        BoxShadow(
                          color:
                              CyberpunkTheme.neonGreen.withValues(alpha: 0.55),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'LOCAL-FIRST',
                    style: TextStyle(
                      color: CyberpunkTheme.textSecondary,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
            ),
            if (isDesktop && !kIsWeb && Platform.isWindows) ...[
              const SizedBox(width: 12),
              // The header is a DragToMoveArea. Claim horizontal pans here so
              // a tiny mouse movement while pressing a window button cannot
              // start dragging the whole window instead of clicking it.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) {},
                onPanUpdate: (_) {},
                onPanEnd: (_) {},
                child: const CyberWindowControls(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _withDesktopDrag(Widget child) {
    if (kIsWeb || !Platform.isWindows) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTap: () async {
        try {
          if (await windowManager.isMaximized()) {
            await windowManager.unmaximize();
          } else {
            await windowManager.maximize();
          }
        } catch (_) {}
      },
      child: DragToMoveArea(child: child),
    );
  }

  Widget _buildBottomNavigation() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: CyberpunkTheme.backgroundColor.withValues(alpha: 0.8),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.07),
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 5, 8, 4),
              child: Row(
                children: [
                  for (var i = 0; i < _destinations.length; i++)
                    Expanded(
                      child: _buildBottomNavItem(
                        index: i,
                        destination: _destinations[i],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavItem({
    required int index,
    required _NavDestination destination,
  }) {
    final isSelected = _currentIndex == index;

    return InkWell(
      onTap: () => _selectTab(index),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                color: isSelected
                    ? CyberpunkTheme.neonCyan.withValues(alpha: 0.08)
                    : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? CyberpunkTheme.neonCyan.withValues(alpha: 0.16)
                      : Colors.transparent,
                  width: 0.5,
                ),
              ),
              child: Icon(
                isSelected ? destination.activeIcon : destination.icon,
                color: isSelected
                    ? CyberpunkTheme.neonCyan
                    : Colors.white.withValues(alpha: 0.35),
                size: 21,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              destination.shortLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isSelected
                    ? CyberpunkTheme.neonCyan
                    : Colors.white.withValues(alpha: 0.35),
                fontSize: 9.5,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavDestination {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String shortLabel;

  const _NavDestination({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.shortLabel,
  });
}

class _AppBackdrop extends StatelessWidget {
  const _AppBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: CyberpunkTheme.backgroundGradient,
            ),
          ),
          Positioned(
            top: -220,
            right: -160,
            child: _BackdropGlow(
              size: 540,
              color: CyberpunkTheme.neonCyan,
              opacity: 0.055,
            ),
          ),
          Positioned(
            bottom: -260,
            left: -180,
            child: _BackdropGlow(
              size: 600,
              color: CyberpunkTheme.electricViolet,
              opacity: 0.07,
            ),
          ),
          Positioned(
            top: 180,
            left: -260,
            child: _BackdropGlow(
              size: 480,
              color: CyberpunkTheme.neonCyan,
              opacity: 0.025,
            ),
          ),
        ],
      ),
    );
  }
}

class _BackdropGlow extends StatelessWidget {
  final double size;
  final Color color;
  final double opacity;

  const _BackdropGlow({
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
