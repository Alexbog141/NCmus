import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/sync_snapshot.dart';

/// Service for communicating with Google Apps Script Web App sync endpoint.
class CloudSyncService {
  static const String apiEndpoint =
      'https://script.google.com/macros/s/AKfycbysjW_1aZnwMsy64cn2xzRbR6G5oOfg8krpPO-ziw6U3Ah3FyJTxZmyw5-JUX9TKUoQVw/exec';

  final http.Client _client;
  final bool _closeClientOnDispose;
  final Duration timeout;

  CloudSyncService({
    http.Client? client,
    this.timeout = const Duration(seconds: 12),
  })  : _client = client ?? http.Client(),
        _closeClientOnDispose = client == null;

  /// Checks the current version of the user database on the remote server.
  ///
  /// Returns the remote version integer, or -1 if the user does not exist or network fails.
  Future<int> checkRemoteVersion({required String username}) async {
    try {
      final uri = Uri.parse(apiEndpoint).replace(queryParameters: {
        'action': 'check_version',
        'username': username,
      });

      final response = await _client.get(uri).timeout(timeout);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded.containsKey('version')) {
          final version = decoded['version'];
          if (version is num) {
            return version.toInt();
          }
        }
      }
      return -1;
    } catch (_) {
      return -1;
    }
  }

  /// Pulls the latest database snapshot from the remote server.
  ///
  /// Returns [SyncSnapshot] if successful, or `null` on network error or invalid credentials.
  Future<SyncSnapshot?> pullSnapshot({
    required String username,
    required String password,
  }) async {
    try {
      final uri = Uri.parse(apiEndpoint).replace(queryParameters: {
        'action': 'pull',
        'username': username,
        'password': password,
      });

      final response = await _client.get(uri).timeout(timeout);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          if (decoded.containsKey('error')) {
            return null;
          }
          return SyncSnapshot.fromJson(decoded);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Pushes the local database snapshot to the remote server.
  ///
  /// Google Apps Script returns an HTTP 302 redirect for Web App POST actions;
  /// this method follows redirects to retrieve the final JSON response.
  /// Returns the updated remote version integer, or `null` on failure.
  Future<int?> pushSnapshot({
    required String username,
    required String password,
    required SyncSnapshot snapshot,
  }) async {
    try {
      final body = jsonEncode({
        'action': 'push',
        'username': username,
        'password': password,
        'sync_data': snapshot.toJson(),
      });

      var response = await _client.post(
        Uri.parse(apiEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(timeout);

      // Follow 301/302/303/307/308 redirects required by Google Apps Script Web App
      int redirectCount = 0;
      while ((response.statusCode == 301 ||
              response.statusCode == 302 ||
              response.statusCode == 303 ||
              response.statusCode == 307 ||
              response.statusCode == 308) &&
          response.headers['location'] != null &&
          redirectCount < 5) {
        final location = response.headers['location']!;
        redirectCount++;
        response = await _client.get(Uri.parse(location)).timeout(timeout);
      }

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          if (decoded.containsKey('error')) {
            return null;
          }
          final version = decoded['version'];
          if (version is num) {
            return version.toInt();
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    if (_closeClientOnDispose) {
      _client.close();
    }
  }
}
