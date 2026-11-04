import 'dart:io';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'android_platform_service.dart';

/// A newer GitHub release that can be installed over the current APK.
class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.tagName,
    required this.body,
    required this.apkUrl,
    required this.apkName,
    required this.releaseUrl,
    this.apkSize = 0,
    this.publishedAt,
  });

  /// Normalized version without the leading `v` (for example `1.0.4`).
  final String version;
  final String tagName;
  final String body;
  final String apkUrl;
  final String apkName;
  final String releaseUrl;
  final int apkSize;
  final DateTime? publishedAt;

  bool get hasApk => apkUrl.isNotEmpty;
}

/// Raised when an update cannot be checked, downloaded or installed.
class UpdateException implements Exception {
  const UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// GitHub Releases based update service used by the sideloaded Android build.
///
/// The service itself is platform agnostic for checking/downloading, while
/// installation is delegated to [AndroidPlatformService] and therefore never
/// runs on Windows.
class UpdateService {
  UpdateService._();

  static const String repository = 'Alexbog141/NCmus';
  static const String _latestReleaseUrl =
      'https://api.github.com/repos/$repository/releases/latest';
  static const String _userAgent = 'NCmus-Android-Updater';

  static const Duration _requestTimeout = Duration(seconds: 20);

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: _requestTimeout,
      receiveTimeout: _requestTimeout,
      sendTimeout: _requestTimeout,
      headers: const <String, String>{
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': _userAgent,
      },
    ),
  );

  /// Returns the installed application version, for example `1.0.4`.
  static Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// Checks the latest GitHub release.
  ///
  /// Returns `null` when the installed build is already up to date.
  /// Throws [UpdateException] with a human-readable message on network or
  /// release-format errors.
  static Future<AppUpdate?> checkForUpdate() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final current = '${packageInfo.version}+${packageInfo.buildNumber}';

    final Response<dynamic> response;
    try {
      response = await _dio.get<dynamic>(
        _latestReleaseUrl,
        options: Options(
          responseType: ResponseType.json,
          receiveTimeout: _requestTimeout,
        ),
      );
    } on DioException catch (error) {
      throw UpdateException(_describeDioError(error));
    }

    final rawData = response.data;
    if (rawData is! Map) {
      throw const UpdateException(
        'GitHub вернул ответ в неизвестном формате.',
      );
    }
    final data = Map<String, dynamic>.from(rawData);

    final tagName = (data['tag_name'] as String?)?.trim() ?? '';
    if (tagName.isEmpty) {
      throw const UpdateException(
        'В последнем релизе GitHub отсутствует tag_name.',
      );
    }

    final remoteVersion = normalizeVersion(tagName);
    if (!isNewerVersion(current, remoteVersion)) {
      return null;
    }

    final asset = _selectApkAsset(data['assets']);
    if (asset == null) {
      throw const UpdateException(
        'В последнем релизе не найден APK-файл NCmus.',
      );
    }

    final assetName = (asset['name'] as String?)?.trim() ?? 'NCmus-Android.apk';
    final downloadUrl =
        (asset['browser_download_url'] as String?)?.trim() ?? '';
    if (downloadUrl.isEmpty) {
      throw const UpdateException(
        'У APK-файла отсутствует ссылка browser_download_url.',
      );
    }

    return AppUpdate(
      version: remoteVersion,
      tagName: tagName,
      body: (data['body'] as String?)?.trim() ?? '',
      apkUrl: downloadUrl,
      apkName: assetName,
      releaseUrl: (data['html_url'] as String?)?.trim() ?? '',
      apkSize: (asset['size'] as num?)?.toInt() ?? 0,
      publishedAt: DateTime.tryParse(
        (data['published_at'] as String?) ?? '',
      ),
    );
  }

  /// Downloads [update] into the app cache and returns the resulting file.
  static Future<File> downloadUpdate(
    AppUpdate update, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (!update.hasApk) {
      throw const UpdateException('В релизе нет ссылки на APK.');
    }

    final directory = await getTemporaryDirectory();
    final sanitizedVersion = normalizeVersion(update.version).replaceAll(
      RegExp(r'[^0-9A-Za-z._-]'),
      '_',
    );
    final file = File(
      '${directory.path}${Platform.pathSeparator}NCmus-$sanitizedVersion.apk',
    );

    try {
      if (await file.exists()) {
        await file.delete();
      }

      await _dio.download(
        update.apkUrl,
        file.path,
        cancelToken: cancelToken,
        onReceiveProgress: onProgress,
        options: Options(
          followRedirects: true,
          receiveTimeout: const Duration(minutes: 10),
          headers: const <String, String>{'User-Agent': _userAgent},
        ),
      );

      final length = await file.length();
      if (length < 1024) {
        throw const UpdateException(
          'Скачанный APK-файл пуст или повреждён.',
        );
      }

      // An APK is a ZIP archive, so it must start with the "PK" signature.
      final handle = await file.open(mode: FileMode.read);
      try {
        final magic = await handle.read(2);
        if (magic.length < 2 || magic[0] != 0x50 || magic[1] != 0x4B) {
          throw const UpdateException(
            'Сервер вернул файл, который не является APK.',
          );
        }
      } finally {
        await handle.close();
      }

      return file;
    } on DioException catch (error) {
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      if (CancelToken.isCancel(error)) {
        throw const UpdateException('Загрузка обновления отменена.');
      }
      throw UpdateException(_describeDioError(error));
    } on UpdateException {
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      rethrow;
    } catch (error) {
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      throw UpdateException('Не удалось сохранить обновление: $error');
    }
  }

  /// Hands a downloaded APK to the Android package installer.
  static Future<ApkInstallStatus> installUpdate(File file) async {
    if (!AndroidPlatformService.isAndroid) {
      return ApkInstallStatus.unsupported;
    }
    if (!await file.exists()) {
      throw const UpdateException('Скачанный APK-файл не найден.');
    }
    return AndroidPlatformService.installApk(file.path);
  }

  /// Normalizes a tag such as `v1.0.4` into `1.0.4`.
  static String normalizeVersion(String value) {
    return value
        .trim()
        .replaceFirst(RegExp(r'^[vV]'), '')
        .replaceAll(RegExp(r'\s+'), '');
  }

  /// Semver comparison with optional build metadata (`1.0.4+5`).
  ///
  /// The build number is only compared when the remote tag explicitly contains
  /// one; otherwise a release tag is considered the same build as the installed
  /// package with the same semantic version.
  static bool isNewerVersion(String current, String remote) {
    final currentVersion = _ParsedVersion.parse(current);
    final remoteVersion = _ParsedVersion.parse(remote);

    if (remoteVersion == null) return false;
    if (currentVersion == null) return true;

    final length = currentVersion.numbers.length > remoteVersion.numbers.length
        ? currentVersion.numbers.length
        : remoteVersion.numbers.length;

    for (var index = 0; index < length; index++) {
      final currentPart = index < currentVersion.numbers.length
          ? currentVersion.numbers[index]
          : 0;
      final remotePart = index < remoteVersion.numbers.length
          ? remoteVersion.numbers[index]
          : 0;

      if (remotePart > currentPart) return true;
      if (remotePart < currentPart) return false;
    }

    if (remoteVersion.build != null) {
      return remoteVersion.build! > (currentVersion.build ?? 0);
    }

    return false;
  }

  static Map<String, dynamic>? _selectApkAsset(dynamic rawAssets) {
    if (rawAssets is! List) return null;

    Map<String, dynamic>? firstApk;
    for (final rawAsset in rawAssets) {
      if (rawAsset is! Map) continue;
      final asset = Map<String, dynamic>.from(rawAsset);
      final name = (asset['name'] as String?)?.toLowerCase() ?? '';
      if (!name.endsWith('.apk')) continue;

      if (name.contains('ncmus-android') || name.contains('android')) {
        return asset;
      }
      firstApk ??= asset;
    }
    return firstApk;
  }

  static String _describeDioError(DioException error) {
    final statusCode = error.response?.statusCode;
    if (statusCode == 404) {
      return 'На GitHub пока нет опубликованных релизов.';
    }
    if (statusCode == 403) {
      return 'GitHub временно ограничил проверку обновлений. Попробуйте позже.';
    }
    if (statusCode != null) {
      return 'GitHub вернул ошибку HTTP $statusCode.';
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Истекло время ожидания ответа GitHub.';
      case DioExceptionType.connectionError:
        return 'Нет подключения к интернету.';
      case DioExceptionType.cancel:
        return 'Загрузка обновления отменена.';
      default:
        return 'Не удалось проверить обновления: ${error.message ?? 'неизвестная ошибка'}.';
    }
  }
}

class _ParsedVersion {
  const _ParsedVersion(this.numbers, this.build);

  final List<int> numbers;
  final int? build;

  static _ParsedVersion? parse(String value) {
    final cleaned = UpdateService.normalizeVersion(value);
    if (cleaned.isEmpty) return null;

    final plusIndex = cleaned.indexOf('+');
    final withoutBuild =
        plusIndex >= 0 ? cleaned.substring(0, plusIndex) : cleaned;
    final build =
        plusIndex >= 0 ? int.tryParse(cleaned.substring(plusIndex + 1)) : null;

    // Drop pre-release suffixes such as `-beta.1`; only numeric core parts
    // participate in the comparison.
    final core = withoutBuild.split('-').first;
    final parts = core.split('.');
    final numbers = <int>[];

    for (final part in parts) {
      final parsed = int.tryParse(part);
      if (parsed == null) return null;
      numbers.add(parsed);
    }

    if (numbers.isEmpty) return null;
    return _ParsedVersion(numbers, build);
  }
}
