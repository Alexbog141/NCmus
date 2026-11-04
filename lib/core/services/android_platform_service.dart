import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Result of handing an APK over to the Android package installer.
enum ApkInstallStatus {
  /// The system installer activity was opened.
  started,

  /// The user must allow installing unknown apps for NCmus first.
  permissionRequired,

  /// The downloaded APK is signed with a different certificate than the
  /// installed app (for example, builds made before signing was stabilized).
  signatureMismatch,

  /// The current platform is not Android, so there is nothing to install.
  unsupported,
}

/// Thin bridge to the Android-specific functionality that has no
/// cross-platform plugin equivalent in this project:
///
/// * asking for the Android 13+ notification permission so the media
///   notification can actually be shown;
/// * opening the system package installer for downloaded APK updates.
///
/// Every entry point is a no-op on Windows/Linux/macOS, so the desktop build
/// never touches an Android-only channel.
class AndroidPlatformService {
  AndroidPlatformService._();

  static const MethodChannel _channel =
      MethodChannel('com.example.ncmus/system');

  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  /// Requests POST_NOTIFICATIONS on Android 13+.
  ///
  /// Returns `true` when notifications are allowed (or when the platform does
  /// not require the runtime permission). Failures are treated as "not
  /// granted" so that the player can continue without a notification.
  static Future<bool> requestNotificationPermission() async {
    if (!isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'requestNotificationPermission',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Whether NCmus is currently allowed to start the package installer.
  static Future<bool> canInstallPackages() async {
    if (!isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('canInstallPackages') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the "Install unknown apps" settings page for NCmus.
  static Future<void> openInstallSettings() async {
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod<void>('openInstallSettings');
    } catch (_) {
      // The settings activity is not available on every OEM ROM.
    }
  }

  /// Opens an external URL (for example the GitHub release page).
  static Future<bool> openUrl(String url) async {
    if (!isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'openUrl',
            <String, dynamic>{'url': url},
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Invokes `ACTION_VIEW` for the downloaded APK through a FileProvider.
  static Future<ApkInstallStatus> installApk(String path) async {
    if (!isAndroid) return ApkInstallStatus.unsupported;

    final result = await _channel.invokeMethod<String>(
      'installApk',
      <String, dynamic>{'path': path},
    );

    switch (result) {
      case 'started':
        return ApkInstallStatus.started;
      case 'permission_required':
        return ApkInstallStatus.permissionRequired;
      case 'signature_mismatch':
        return ApkInstallStatus.signatureMismatch;
      default:
        throw PlatformException(
          code: 'install_failed',
          message: 'Android package installer did not start.',
        );
    }
  }
}
