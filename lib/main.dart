import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:window_manager/window_manager.dart';

import 'core/audio/audio_player_handler.dart';
import 'core/database/database_service.dart';
import 'core/services/discord_rpc_service.dart';
import 'core/services/window_overlay_service.dart';
import 'core/theme/cyberpunk_theme.dart';
import 'features/ui/screens/home_shell.dart';
import 'features/ui/widgets/cyber_orb_overlay.dart';
import 'features/wave/services/wave_service.dart';

late final NCPlayerHandler _audioHandler;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  DatabaseService.initFfiIfNeeded();
  await ThemeController.init();

  final bool isDesktop = !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  if (isDesktop && Platform.isWindows) {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      size: Size(1200, 800),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );

    unawaited(
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.setAsFrameless();
        await windowManager.setHasShadow(false);
        await windowManager.show();
        await windowManager.focus();
      }),
    );

    DiscordRpcService.instance.initialize();
  }

  _audioHandler = await AudioService.init<NCPlayerHandler>(
    builder: () => NCPlayerHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.ncmus.channel.audio',
      androidNotificationChannelName: 'NCmus Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'mipmap/ic_launcher',
    ),
  );

  WaveService.instance.attachHandler(_audioHandler);

  runApp(NCmusApp(handler: _audioHandler));
}

class NCmusApp extends StatelessWidget {
  final NCPlayerHandler handler;

  const NCmusApp({
    super.key,
    required this.handler,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'NCmus',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.dark,
          theme: ThemeController.instance.currentThemeData,
          home: _WindowRoot(handler: handler),
        );
      },
    );
  }
}

/// Keeps the full player alive while the same OS window is morphed into the
/// Cyber Orb HUD. The window itself is never recreated.
class _WindowRoot extends StatefulWidget {
  final NCPlayerHandler handler;

  const _WindowRoot({required this.handler});

  @override
  State<_WindowRoot> createState() => _WindowRootState();
}

class _WindowRootState extends State<_WindowRoot>
    with TickerProviderStateMixin {
  // 1. Holographic collapse into the singularity: 180 ms.
  late final AnimationController _collapseController;
  late final Animation<double> _collapseScale;
  late final Animation<double> _collapseFade;

  // 2. Soft player reveal after the native window is restored: 220 ms.
  late final AnimationController _revealController;
  late final Animation<double> _revealScale;
  late final Animation<double> _revealFade;

  // Cheap GDI snapshot of the player, animated instead of the glass tree.
  final ValueNotifier<ui.Image?> _snapshotImage =
      ValueNotifier<ui.Image?>(null);
  final ValueNotifier<bool> _snapshotVisible = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();

    _collapseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _collapseScale = Tween<double>(begin: 1.0, end: 0.05).animate(
      CurvedAnimation(
        parent: _collapseController,
        curve: Curves.easeInOutCubic,
      ),
    );
    _collapseFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _collapseController,
        curve: Curves.easeInOutCubic,
      ),
    );

    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1.0,
    );
    _revealScale = Tween<double>(begin: 0.97, end: 1.0).animate(
      CurvedAnimation(
        parent: _revealController,
        curve: Curves.easeInOutCubic,
      ),
    );
    _revealFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _revealController,
        curve: Curves.easeInOutCubic,
      ),
    );

    WindowOverlayService.instance.onPrepareFullAppCollapse =
        _handlePrepareFullAppCollapse;
    WindowOverlayService.instance.onFadeOutFullApp = _handleFadeOutFullApp;
    WindowOverlayService.instance.isOverlayActive
        .addListener(_handleOverlayActiveChange);
  }

  @override
  void dispose() {
    WindowOverlayService.instance.onPrepareFullAppCollapse = null;
    WindowOverlayService.instance.onFadeOutFullApp = null;
    WindowOverlayService.instance.isOverlayActive
        .removeListener(_handleOverlayActiveChange);
    _snapshotImage.value?.dispose();
    _snapshotImage.dispose();
    _snapshotVisible.dispose();
    _collapseController.dispose();
    _revealController.dispose();
    super.dispose();
  }

  /// Captures the already-composited player and paints it above the live tree.
  /// Returns true when the cheap snapshot collapse can be used.
  Future<bool> _handlePrepareFullAppCollapse() async {
    if (!mounted || kIsWeb || !Platform.isWindows) return false;
    _revealController.value = 1.0;

    final image = await WindowOverlayService.instance.captureWindowImage();
    if (!mounted) {
      image?.dispose();
      return false;
    }
    if (image == null) return false;

    final previous = _snapshotImage.value;
    _collapseController.value = 0.0;
    _snapshotImage.value = image;
    _snapshotVisible.value = true;
    // The previous snapshot is no longer in the tree (it was hidden when the
    // overlay activated), so it is safe to release here. Do not dispose the
    // current image when the overlay activates: the raster thread may still
    // hold its texture for a frame, and freeing it there can crash ANGLE.
    previous?.dispose();
    return true;
  }

  Future<void> _handleFadeOutFullApp() async {
    if (!mounted) return;
    // If the user re-enters while the player reveal is still running, cancel
    // that transform first so only the collapse is visible.
    _revealController.value = 1.0;
    // The snapshot is a single texture; the live glass tree is offstage, so
    // this is a cheap fade/scale rather than a full player re-raster.
    await _collapseController.forward(from: 0.0);
    // Deliberately leave the controller at 1.0. Resetting it here would make
    // the snapshot or player flash back for one or more frames.
  }

  void _handleOverlayActiveChange() {
    final service = WindowOverlayService.instance;
    if (service.isOverlayActive.value) {
      // Hide the collapse snapshot. Keep the ui.Image alive until the next
      // entry: disposing it immediately can free a texture that the raster
      // thread is still using, which crashes the Windows embedder.
      _snapshotVisible.value = false;
      return;
    }
    if (mounted) {
      _collapseController.value = 0.0;
      _revealController.forward(from: 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !Platform.isWindows) {
      return HomeShell(handler: widget.handler);
    }

    return ListenableBuilder(
      listenable: Listenable.merge([
        WindowOverlayService.instance.isOverlayActive,
        WindowOverlayService.instance.isPlayerHidden,
        _snapshotVisible,
      ]),
      builder: (context, player) {
        final service = WindowOverlayService.instance;
        final isOverlay = service.isOverlayActive.value;
        final playerHidden = isOverlay || service.isPlayerHidden.value;
        final showSnapshot =
            _snapshotVisible.value && _snapshotImage.value != null;
        final playerSize = playerHidden ? service.savedWindowSize : null;

        return ColoredBox(
          color: Colors.transparent,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Keep the player mounted but offstage while the OS window morphs.
              // `player` is the stable child, so toggling this does not rebuild
              // the heavy HomeShell tree. Pinning the hidden player to its saved
              // size also stops the 128x128 window resize from re-laying out the
              // HomeShell during the collapse.
              Offstage(
                offstage: playerHidden || showSnapshot,
                child: TickerMode(
                  enabled: !playerHidden,
                  child: playerSize != null
                      ? SizedBox(
                          width: playerSize.width,
                          height: playerSize.height,
                          child: player,
                        )
                      : player!,
                ),
              ),
              // Cheap texture collapse painted above the live player.
              if (showSnapshot) _buildSnapshotLayer(),
              // The overlay lives in the same OS window, on top of the player.
              if (isOverlay) _buildOverlay(),
            ],
          ),
        );
      },
      child: _buildPlayer(),
    );
  }

  Widget _buildPlayer() {
    return AnimatedBuilder(
      animation: Listenable.merge([_collapseController, _revealController]),
      builder: (context, child) {
        Widget current = child!;

        // Player reveal: a soft fade with a very small scale-up.
        if (_revealController.value < 1.0) {
          current = FadeTransition(
            opacity: _revealFade,
            child: ScaleTransition(
              scale: _revealScale,
              alignment: Alignment.center,
              child: current,
            ),
          );
        }

        // Entry: collapse to 0.05 and fade to zero.
        if (_collapseController.value > 0.0) {
          current = FadeTransition(
            opacity: _collapseFade,
            child: ScaleTransition(
              scale: _collapseScale,
              alignment: Alignment.center,
              child: current,
            ),
          );
        }

        return current;
      },
      // Keep the player mounted while the OS window is 128x128, but lay it
      // out against its last full-window size. Offstage still performs layout,
      // so without this the genre grid throws overflow exceptions on every
      // HUD frame and stalls the morph animation in debug builds.
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final service = WindowOverlayService.instance;
            final hidden =
                service.isOverlayActive.value || service.isPlayerHidden.value;
            final size = (hidden || constraints.maxWidth < 600)
                ? service.savedWindowSize
                : Size(constraints.maxWidth, constraints.maxHeight);
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(size: size),
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: size.width,
                maxWidth: size.width,
                minHeight: size.height,
                maxHeight: size.height,
                child: HomeShell(handler: widget.handler),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSnapshotLayer() {
    final image = _snapshotImage.value;
    if (image == null) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        child: ScaleTransition(
          scale: _collapseScale,
          alignment: Alignment.center,
          // RawImage applies the opacity in its own paint. Wrapping the
          // full-screen texture in Opacity forced a saveLayer every frame and
          // stretched the 180 ms collapse to ~570 ms in debug.
          child: RawImage(
            image: image,
            fit: BoxFit.fill,
            filterQuality: FilterQuality.low,
            opacity: _collapseFade,
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay() {
    return ColoredBox(
      color: Colors.transparent,
      child: CyberOrbOverlay(handler: widget.handler),
    );
  }
}
