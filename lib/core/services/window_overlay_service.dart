import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Owns the OS-window side of the Cyber Orb HUD.
///
/// The overlay is not a second window: the existing NCmus window is resized,
/// made frameless / transparent / always-on-top and then restored in place.
class WindowOverlayService {
  WindowOverlayService._();

  static final WindowOverlayService instance = WindowOverlayService._();

  static const Size orbWindowSize = Size(128, 128);
  static const Size hudWindowSize = Size(440, 130);
  static const Size defaultWindowSize = Size(1200, 800);

  final ValueNotifier<bool> isOverlayActive = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isExpanded = ValueNotifier<bool>(false);

  /// True while the OS window is being morphed and the full player must stay
  /// mounted but hidden. It is deliberately separate from [isOverlayActive]:
  /// the window becomes 128x128 before the orb overlay is allowed to build.
  final ValueNotifier<bool> isPlayerHidden = ValueNotifier<bool>(false);

  Size _savedWindowSize = defaultWindowSize;
  Offset _savedWindowPosition = Offset.zero;

  /// Restored size of the full player window after closing overlay.
  Size get savedWindowSize => _savedWindowSize;

  /// Restored position of the full player window after closing overlay.
  Offset get savedWindowPosition => _savedWindowPosition;

  @visibleForTesting
  void setSavedGeometry({required Size size, required Offset position}) {
    _savedWindowSize = size;
    _savedWindowPosition = position;
  }

  Timer? _autoCollapseTimer;
  bool _pointerInside = false;

  /// Guards the two window-level transitions so a second click cannot start a
  /// competing geometry animation while the first one is still in flight.
  bool _transitioning = false;

  /// True while the native window is being shrunk after the drawer dismissed.
  bool _collapsing = false;

  /// Hook to capture and show a snapshot of the player before altering the OS
  /// window. Returns true when a snapshot is on screen and the cheap texture
  /// collapse path can be used.
  Future<bool> Function()? onPrepareFullAppCollapse;

  /// Hook to fade out the full application UI before altering OS window geometry.
  Future<void> Function()? onFadeOutFullApp;

  /// Hook to fade out the Cyber Orb before restoring full player geometry.
  Future<void> Function()? onFadeOutOrb;

  _Win32WindowCapture? _win32Capture;
  int? _windowHandle;

  static bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isWindows;
  }

  /// Grabs the current client area as a Flutter image.
  ///
  /// A GDI BitBlt of the already-composited window is dramatically cheaper
  /// than re-rasterising the BackdropFilter-heavy player tree into a texture.
  /// The returned image is only valid as a transient collapse snapshot.
  Future<ui.Image?> captureWindowImage() async {
    if (kIsWeb || !Platform.isWindows) return null;
    try {
      _win32Capture ??= _Win32WindowCapture();
      final hwnd = _windowHandle ?? await windowManager.getId();
      _windowHandle = hwnd;
      return await _win32Capture!.capture(hwnd);
    } catch (error, stack) {
      debugPrint('Could not capture the player window: $error');
      debugPrintStack(stackTrace: stack);
      return null;
    }
  }

  /// Transforms the current player window into the floating orb.
  Future<void> enableOverlay() async {
    if (kIsWeb || !Platform.isWindows) return;
    if (!isSupported || isOverlayActive.value || _transitioning) return;

    _transitioning = true;
    try {
      // Save restored geometry, not the maximized / fullscreen geometry.
      if (await windowManager.isFullScreen()) {
        await windowManager.setFullScreen(false);
      }
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      }

      // 1. _savedWindowSize = await windowManager.getSize();
      _savedWindowSize = await windowManager.getSize();
      _savedWindowPosition = await windowManager.getPosition();

      final targetX =
          _savedWindowPosition.dx + (_savedWindowSize.width - 128) / 2;
      final targetY =
          _savedWindowPosition.dy + (_savedWindowSize.height - 128) / 2;

      // 1. Запуск анимации схлопывания плеера в точку (180 мс)
      if (onFadeOutFullApp != null) {
        unawaited(onFadeOutFullApp!());
      }
      // Ждем 185 мс завершения схлопывания плеера
      await Future<void>.delayed(const Duration(milliseconds: 185));

      isPlayerHidden.value = true;

      // 2. Перевод окна в оверлей: setBounds на координаты центра с размером Size(128, 128) и setAlwaysOnTop(true)
      await windowManager.setHasShadow(false);
      await windowManager.setMinimumSize(orbWindowSize);
      await windowManager.setMaximumSize(orbWindowSize);
      await windowManager.setBounds(
        null,
        position: Offset(targetX, targetY),
        size: const Size(128, 128),
      );
      await windowManager.setAlwaysOnTop(true);

      // 3. Включаем оверлей
      _pointerInside = false;
      isExpanded.value = false;
      isOverlayActive.value = true;
    } finally {
      _transitioning = false;
    }
  }

  /// Morphs the orb into the compact HUD capsule.
  Future<void> expandHud() async {
    if (kIsWeb || !Platform.isWindows) return;
    if (!isOverlayActive.value || _transitioning || _collapsing) return;
    _autoCollapseTimer?.cancel();

    // The native window must already be large enough before the drawer starts
    // revealing; otherwise the OS would clip the first animation frames.
    await windowManager.setHasShadow(false);
    await windowManager.setMinimumSize(hudWindowSize);
    await windowManager.setMaximumSize(hudWindowSize);
    await windowManager.setSize(hudWindowSize);
    await WidgetsBinding.instance.endOfFrame;

    isExpanded.value = true;
    resetIdleTimer();
  }

  /// Morphs the HUD capsule back into the orb.
  Future<void> collapseToOrb() async {
    if (kIsWeb || !Platform.isWindows) return;
    if (!isOverlayActive.value || _transitioning || _collapsing) return;
    _autoCollapseTimer?.cancel();

    if (!isExpanded.value) {
      await handleWidgetCollapseComplete();
      return;
    }

    // The widget reports AnimationStatus.dismissed; only then is the native
    // window allowed to shrink. No timer may pre-empt that frame.
    isExpanded.value = false;
  }

  /// Shrinks the native OS window strictly after the widget animation reaches 0.0.
  Future<void> handleWidgetCollapseComplete() async {
    if (kIsWeb || !Platform.isWindows) return;
    if (_transitioning ||
        _collapsing ||
        isExpanded.value ||
        !isOverlayActive.value) {
      return;
    }

    _collapsing = true;
    try {
      await windowManager.setHasShadow(false);
      await windowManager.setMinimumSize(orbWindowSize);
      await windowManager.setMaximumSize(orbWindowSize);
      await windowManager.setSize(orbWindowSize);
    } finally {
      _collapsing = false;
    }
  }

  void toggleExpand() {
    if (kIsWeb || !Platform.isWindows) return;
    if (!isOverlayActive.value || _transitioning) return;
    if (isExpanded.value) {
      unawaited(collapseToOrb());
    } else {
      unawaited(expandHud());
    }
  }

  /// Restarts the 5 second idle timer. Only an expanded, non-hovered HUD is
  /// allowed to auto-collapse.
  void resetIdleTimer() {
    if (kIsWeb || !Platform.isWindows) return;
    _autoCollapseTimer?.cancel();
    _autoCollapseTimer = Timer(const Duration(seconds: 5), () {
      if (isExpanded.value && !_pointerInside) {
        unawaited(collapseToOrb());
      }
    });
  }

  /// Keeps the HUD open while the cursor is physically over it, even if the
  /// pointer is stationary (no hover events are emitted in that case).
  void setPointerInside(bool inside) {
    if (kIsWeb || !Platform.isWindows) return;
    if (_pointerInside == inside) {
      if (inside) resetIdleTimer();
      return;
    }
    _pointerInside = inside;
    resetIdleTimer();
  }

  /// Restores the original player window and full interface.
  Future<void> restoreApp() async {
    if (kIsWeb || !Platform.isWindows) return;
    if (!isOverlayActive.value || _transitioning) return;

    _transitioning = true;
    try {
      _autoCollapseTimer?.cancel();
      _pointerInside = false;

      // 1. Переключи флаг оверлея
      isOverlayActive.value = false;
      isPlayerHidden.value = false;
      isExpanded.value = false;

      // 2. Сними alwaysOnTop
      await windowManager.setAlwaysOnTop(false);

      // 3. В ОДИН вызов примени геометрию
      await windowManager.setHasShadow(false);
      await windowManager.setMinimumSize(const Size(900, 600));
      await windowManager.setMaximumSize(const Size(4096, 2160));
      await windowManager.setBounds(
        null,
        position: _savedWindowPosition,
        size: _savedWindowSize,
      );

      unawaited(windowManager.focus().catchError((Object _) {}));
    } finally {
      _transitioning = false;
    }
  }

  void dispose() {
    _autoCollapseTimer?.cancel();
    _autoCollapseTimer = null;
  }
}



/// GDI screen capture of the current client area.
///
/// Flutter's `RenderRepaintBoundary.toImage` path has to rasterise the
/// BackdropFilter/glass tree and took roughly 0.7-1 s in debug. A BitBlt of the
/// already-composited window is a single desktop copy and costs a few ms.
class _Win32WindowCapture {
  static const int _srccopy = 0x00CC0020;
  static const int _dibRgbColors = 0;
  static const int _biRgb = 0;

  final DynamicLibrary _user32;
  final DynamicLibrary _gdi32;

  late final int Function(int hwnd, Pointer<_Win32Rect> rect) _getClientRect;
  late final int Function(int hwnd, Pointer<_Win32Point> point) _clientToScreen;
  late final int Function(int hwnd) _getDC;
  late final int Function(int hwnd, int dc) _releaseDC;
  late final int Function(int dc) _createCompatibleDC;
  late final int Function(int dc, int width, int height)
      _createCompatibleBitmap;
  late final int Function(int dc, int object) _selectObject;
  late final int Function(
    int dst,
    int x,
    int y,
    int width,
    int height,
    int src,
    int srcX,
    int srcY,
    int rop,
  ) _bitBlt;
  late final int Function(
    int dc,
    int bitmap,
    int start,
    int lines,
    Pointer<Uint8> bits,
    Pointer<_Win32BitmapInfo> info,
    int usage,
  ) _getDIBits;
  late final int Function(int object) _deleteObject;
  late final int Function(int dc) _deleteDC;

  _Win32WindowCapture()
      : _user32 = DynamicLibrary.open('user32.dll'),
        _gdi32 = DynamicLibrary.open('gdi32.dll') {
    _getClientRect = _user32.lookupFunction<
        Int32 Function(IntPtr, Pointer<_Win32Rect>),
        int Function(int, Pointer<_Win32Rect>)>('GetClientRect');
    _clientToScreen = _user32.lookupFunction<
        Int32 Function(IntPtr, Pointer<_Win32Point>),
        int Function(int, Pointer<_Win32Point>)>('ClientToScreen');
    _getDC = _user32.lookupFunction<IntPtr Function(IntPtr), int Function(int)>(
      'GetDC',
    );
    _releaseDC = _user32.lookupFunction<Int32 Function(IntPtr, IntPtr),
        int Function(int, int)>('ReleaseDC');
    _createCompatibleDC =
        _gdi32.lookupFunction<IntPtr Function(IntPtr), int Function(int)>(
      'CreateCompatibleDC',
    );
    _createCompatibleBitmap = _gdi32.lookupFunction<
        IntPtr Function(IntPtr, Int32, Int32),
        int Function(int, int, int)>('CreateCompatibleBitmap');
    _selectObject = _gdi32.lookupFunction<IntPtr Function(IntPtr, IntPtr),
        int Function(int, int)>('SelectObject');
    _bitBlt = _gdi32.lookupFunction<
        Int32 Function(
          IntPtr,
          Int32,
          Int32,
          Int32,
          Int32,
          IntPtr,
          Int32,
          Int32,
          Uint32,
        ),
        int Function(int, int, int, int, int, int, int, int, int)>('BitBlt');
    _getDIBits = _gdi32.lookupFunction<
        Int32 Function(
          IntPtr,
          IntPtr,
          Uint32,
          Uint32,
          Pointer<Uint8>,
          Pointer<_Win32BitmapInfo>,
          Uint32,
        ),
        int Function(
          int,
          int,
          int,
          int,
          Pointer<Uint8>,
          Pointer<_Win32BitmapInfo>,
          int,
        )>('GetDIBits');
    _deleteObject =
        _gdi32.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
            'DeleteObject');
    _deleteDC = _gdi32
        .lookupFunction<Int32 Function(IntPtr), int Function(int)>('DeleteDC');
  }

  Future<ui.Image?> capture(int hwnd) async {
    final rect = calloc<_Win32Rect>();
    final origin = calloc<_Win32Point>();
    Pointer<_Win32BitmapInfo>? info;
    Pointer<Uint8>? pixels;
    try {
      if (_getClientRect(hwnd, rect) == 0) return null;
      if (_clientToScreen(hwnd, origin) == 0) return null;

      final width = rect.ref.right - rect.ref.left;
      final height = rect.ref.bottom - rect.ref.top;
      if (width <= 0 || height <= 0) return null;

      final screenDc = _getDC(0);
      if (screenDc == 0) return null;

      final memDc = _createCompatibleDC(screenDc);
      if (memDc == 0) {
        _releaseDC(0, screenDc);
        return null;
      }

      final bitmap = _createCompatibleBitmap(screenDc, width, height);
      if (bitmap == 0) {
        _deleteDC(memDc);
        _releaseDC(0, screenDc);
        return null;
      }

      final oldBitmap = _selectObject(memDc, bitmap);
      try {
        if (oldBitmap == 0) return null;
        if (_bitBlt(
              memDc,
              0,
              0,
              width,
              height,
              screenDc,
              origin.ref.x,
              origin.ref.y,
              _srccopy,
            ) ==
            0) {
          return null;
        }

        info = calloc<_Win32BitmapInfo>();
        info.ref.header.size = sizeOf<_Win32BitmapInfoHeader>();
        info.ref.header.width = width;
        // Negative height requests top-down rows, matching decodeImageFromPixels.
        info.ref.header.height = -height;
        info.ref.header.planes = 1;
        info.ref.header.bitCount = 32;
        info.ref.header.compression = _biRgb;

        final byteCount = width * height * 4;
        pixels = calloc<Uint8>(byteCount);
        final lines = _getDIBits(
          memDc,
          bitmap,
          0,
          height,
          pixels,
          info,
          _dibRgbColors,
        );
        if (lines == 0) return null;

        final bytes = pixels.asTypedList(byteCount);
        // GDI leaves the alpha byte undefined (usually zero). Flutter's
        // premultiplied BGRA path would treat that as fully transparent.
        final words = Uint32List.view(bytes.buffer);
        for (var i = 0; i < words.length; i++) {
          words[i] |= 0xFF000000;
        }

        final completer = Completer<ui.Image>();
        ui.decodeImageFromPixels(
          bytes,
          width,
          height,
          ui.PixelFormat.bgra8888,
          completer.complete,
        );
        return await completer.future;
      } finally {
        if (oldBitmap != 0) _selectObject(memDc, oldBitmap);
        _deleteObject(bitmap);
        _deleteDC(memDc);
        _releaseDC(0, screenDc);
      }
    } finally {
      if (pixels != null) calloc.free(pixels);
      if (info != null) calloc.free(info);
      calloc.free(rect);
      calloc.free(origin);
    }
  }
}

final class _Win32Rect extends Struct {
  @Int32()
  external int left;
  @Int32()
  external int top;
  @Int32()
  external int right;
  @Int32()
  external int bottom;
}

final class _Win32Point extends Struct {
  @Int32()
  external int x;
  @Int32()
  external int y;
}

final class _Win32BitmapInfoHeader extends Struct {
  @Uint32()
  external int size;
  @Int32()
  external int width;
  @Int32()
  external int height;
  @Uint16()
  external int planes;
  @Uint16()
  external int bitCount;
  @Uint32()
  external int compression;
  @Uint32()
  external int sizeImage;
  @Int32()
  external int xPelsPerMeter;
  @Int32()
  external int yPelsPerMeter;
  @Uint32()
  external int clrUsed;
  @Uint32()
  external int clrImportant;
}

final class _Win32BitmapInfo extends Struct {
  external _Win32BitmapInfoHeader header;
  @Uint32()
  external int colors;
}



