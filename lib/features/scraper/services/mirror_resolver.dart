import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;

class CircuitBreakerEntry {
  int failureCount = 0;
  DateTime? lastFailureTime;
  bool isTripped = false;

  void recordFailure({int threshold = 2}) {
    failureCount++;
    lastFailureTime = DateTime.now();
    if (failureCount >= threshold) {
      isTripped = true;
    }
  }

  void recordSuccess() {
    failureCount = 0;
    lastFailureTime = null;
    isTripped = false;
  }

  bool isAvailable({Duration cooldown = const Duration(minutes: 3)}) {
    if (!isTripped) {
      return true;
    }
    if (lastFailureTime != null &&
        DateTime.now().difference(lastFailureTime!) > cooldown) {
      // Cooldown expired, allow retry (half-open state)
      return true;
    }
    return false;
  }
}

class MirrorResolver {
  static const String defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  static const Duration defaultTimeout = Duration(seconds: 7);

  static const Map<String, List<String>> defaultMirrors = {
    'Hitmo': [
      'https://rus.hitmotop.com',
      'https://hitmo.me',
      'https://hitmos.biz',
      'https://hitmo.org',
    ],
    'Muzofond': [
      'https://muzofond.fm',
      'https://muzofond.org',
    ],
  };

  static const List<String> rknStubIndicators = [
    'единый реестр',
    'доступ к запрашиваемому ресурсу ограничен',
    'доступ ограничен',
    'министерством юстиции',
    'roskomnadzor',
    'block.beeline.ru',
    'warning.rt.ru',
  ];

  final Map<String, List<String>> _mirrors;
  final Map<String, CircuitBreakerEntry> _circuitBreakers = {};
  final Map<String, String> _activeMirrors = {};

  MirrorResolver({Map<String, List<String>>? mirrors})
      : _mirrors = mirrors ?? Map.from(defaultMirrors);

  List<String> getMirrorsFor(String providerName) {
    return _mirrors[providerName] ?? const [];
  }

  String getCurrentBaseUrl(String providerName) {
    if (_activeMirrors.containsKey(providerName)) {
      return _activeMirrors[providerName]!;
    }
    final mirrors = getMirrorsFor(providerName);
    return mirrors.isNotEmpty ? mirrors.first : '';
  }

  void setActiveMirror(String providerName, String mirrorUrl) {
    _activeMirrors[providerName] = mirrorUrl;
  }

  CircuitBreakerEntry _getEntry(String host) {
    return _circuitBreakers.putIfAbsent(host, () => CircuitBreakerEntry());
  }

  bool isHostAvailable(String host) {
    final uri = Uri.tryParse(host);
    final key = uri != null ? uri.host : host;
    return _getEntry(key).isAvailable();
  }

  void recordFailure(String host) {
    final uri = Uri.tryParse(host);
    final key = uri != null ? uri.host : host;
    _getEntry(key).recordFailure();
  }

  void recordSuccess(String host) {
    final uri = Uri.tryParse(host);
    final key = uri != null ? uri.host : host;
    _getEntry(key).recordSuccess();
  }

  bool verifyHtmlSignature(String html, String expectedSignature) {
    if (html.isEmpty || expectedSignature.isEmpty) {
      return false;
    }

    final lower = html.toLowerCase();
    for (final indicator in rknStubIndicators) {
      if (lower.contains(indicator)) {
        return false;
      }
    }

    final cleanSig = expectedSignature.startsWith('.')
        ? expectedSignature.substring(1).toLowerCase()
        : expectedSignature.toLowerCase();

    return lower.contains(expectedSignature.toLowerCase()) ||
        lower.contains(cleanSig);
  }

  Future<bool> validateMirror(
    String baseUrl, {
    String? expectedSignature,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    final shouldClose = client == null;

    try {
      final uri = Uri.parse(baseUrl);
      final response = await httpClient
          .get(
            uri,
            headers: {
              'User-Agent': defaultUserAgent,
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
              'Accept-Language': 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
            },
          )
          .timeout(defaultTimeout);

      if (response.statusCode >= 200 && response.statusCode < 400) {
        if (expectedSignature != null && expectedSignature.isNotEmpty) {
          final isValidSignature =
              verifyHtmlSignature(response.body, expectedSignature);
          if (!isValidSignature) {
            recordFailure(baseUrl);
            return false;
          }
        }
        recordSuccess(baseUrl);
        return true;
      } else {
        recordFailure(baseUrl);
        return false;
      }
    } on TimeoutException {
      recordFailure(baseUrl);
      return false;
    } on SocketException {
      recordFailure(baseUrl);
      return false;
    } catch (_) {
      recordFailure(baseUrl);
      return false;
    } finally {
      if (shouldClose) {
        httpClient.close();
      }
    }
  }

  Future<String> resolveActiveMirror(
    String providerName, {
    String? expectedSignature,
    http.Client? client,
  }) async {
    final current = getCurrentBaseUrl(providerName);
    if (isHostAvailable(current)) {
      return current;
    }

    final mirrors = getMirrorsFor(providerName);
    for (final mirror in mirrors) {
      if (isHostAvailable(mirror)) {
        final isValid = await validateMirror(
          mirror,
          expectedSignature: expectedSignature,
          client: client,
        );
        if (isValid) {
          setActiveMirror(providerName, mirror);
          return mirror;
        }
      }
    }

    return mirrors.isNotEmpty ? mirrors.first : current;
  }
}
