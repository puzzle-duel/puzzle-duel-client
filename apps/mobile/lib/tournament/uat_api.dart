import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:puzzle_duel_mobile/presentation/debug/interaction_perf.dart';

/// Authenticated Tournament UAT client. It never sends a score or a seal.
class UatApi {
  UatApi({
    required this.baseUrl,
    required String bearer,
    this.sessionSecret,
    HttpClient Function()? httpClientFactory,
  }) : bearer = normalizeBearer(bearer),
       _httpClientFactory = httpClientFactory ?? HttpClient.new;

  /// Origin only (scheme/host/port). Never includes credentials.
  final String baseUrl;
  String bearer;
  String? sessionSecret;
  final HttpClient Function() _httpClientFactory;

  /// Ensures `Authorization` is `Bearer <token>` without double-prefixing.
  static String normalizeBearer(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return trimmed;
    if (trimmed.length >= 7 &&
        trimmed.substring(0, 7).toLowerCase() == 'bearer ') {
      return 'Bearer ${trimmed.substring(7).trim()}';
    }
    return 'Bearer $trimmed';
  }

  /// Non-secret fingerprint so persisted sessions bind to the current auth
  /// material without storing the bearer.
  static String authBinding(String bearer) {
    final normalized = normalizeBearer(bearer);
    var hash = 2166136261;
    for (final unit in utf8.encode(normalized)) {
      hash ^= unit;
      hash = (hash * 16777619) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// Scheme://host:port with no path, query, or credentials.
  static String apiOrigin(String baseUrl) {
    final trimmed = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return trimmed;
    final port = uri.hasPort
        ? uri.port
        : (uri.scheme == 'https'
              ? 443
              : uri.scheme == 'http'
              ? 80
              : uri.port);
    final showPort =
        !(uri.scheme == 'http' && port == 80) &&
        !(uri.scheme == 'https' && port == 443);
    return showPort
        ? '${uri.scheme}://${uri.host}:$port'
        : '${uri.scheme}://${uri.host}';
  }

  Future<UatHttpResult> get(String path) => _send('GET', path);

  Future<UatHttpResult> post(String path, [Object? body]) =>
      _send('POST', path, body);

  Future<UatHttpResult> _send(
    String method,
    String path, [
    Object? body,
  ]) async {
    final client = _httpClientFactory();
    client.connectionTimeout = _connectTimeout;
    final started = Stopwatch()..start();
    var phase = 'connect';
    final hadSession = sessionSecret != null && sessionSecret!.isNotEmpty;
    final origin = apiOrigin(baseUrl);
    _perfLog(
      'http.start $method $path origin=$origin hadSession=$hadSession',
    );
    try {
      final uri = Uri.parse('$baseUrl$path');
      final request = await client.openUrl(method, uri).timeout(
        _connectTimeout,
        onTimeout: () => throw const _UatTimeout('connect'),
      );
      phase = 'headers';
      request.headers.set(HttpHeaders.authorizationHeader, bearer);
      final secret = sessionSecret;
      if (secret != null && secret.isNotEmpty) {
        request.headers.set('x-pzd-session-secret', secret);
      }
      if (body == null) {
        // Unknown length becomes Transfer-Encoding: chunked, which readBody rejects.
        request.contentLength = 0;
      } else {
        final bytes = utf8.encode(jsonEncode(body));
        request.headers.contentType = ContentType.json;
        request.contentLength = bytes.length;
        request.add(bytes);
      }
      phase = 'response';
      final response = await request.close().timeout(
        _responseTimeout,
        onTimeout: () => throw const _UatTimeout('response'),
      );
      phase = 'body';
      final text = await utf8.decodeStream(response).timeout(
        _responseTimeout,
        onTimeout: () => throw const _UatTimeout('response'),
      );
      Object? json;
      if (text.isNotEmpty) {
        try {
          json = jsonDecode(text);
        } on FormatException {
          _perfLog(
            'http.done $method $path status=${response.statusCode} '
            'ms=${started.elapsedMilliseconds} category=MALFORMED_BODY '
            'phase=$phase hadSession=$hadSession',
          );
          return UatHttpResult(
            response.statusCode,
            {'error': 'MALFORMED_BODY'},
            category: UatFailureCategory.malformed,
          );
        }
      }
      _perfLog(
        'http.done $method $path status=${response.statusCode} '
        'ms=${started.elapsedMilliseconds} category=ok '
        'phase=$phase hadSession=$hadSession',
      );
      return UatHttpResult(response.statusCode, json);
    } on _UatTimeout catch (error) {
      final category = error.phase == 'connect'
          ? UatFailureCategory.connectTimeout
          : UatFailureCategory.responseTimeout;
      _perfLog(
        'http.fail $method $path status=0 ms=${started.elapsedMilliseconds} '
        'category=${category.name} phase=${error.phase} hadSession=$hadSession',
      );
      return UatHttpResult(
        0,
        {'error': 'TIMEOUT', 'timeoutPhase': error.phase},
        category: category,
      );
    } on SocketException {
      _perfLog(
        'http.fail $method $path status=0 ms=${started.elapsedMilliseconds} '
        'category=offline phase=$phase hadSession=$hadSession',
      );
      return const UatHttpResult(
        0,
        {'error': 'OFFLINE'},
        category: UatFailureCategory.offline,
      );
    } on HttpException {
      _perfLog(
        'http.fail $method $path status=0 ms=${started.elapsedMilliseconds} '
        'category=offline phase=$phase hadSession=$hadSession',
      );
      return const UatHttpResult(
        0,
        {'error': 'OFFLINE'},
        category: UatFailureCategory.offline,
      );
    } on TimeoutException {
      _perfLog(
        'http.fail $method $path status=0 ms=${started.elapsedMilliseconds} '
        'category=responseTimeout phase=$phase hadSession=$hadSession',
      );
      return const UatHttpResult(
        0,
        {'error': 'TIMEOUT', 'timeoutPhase': 'response'},
        category: UatFailureCategory.responseTimeout,
      );
    } on Exception catch (error) {
      _perfLog(
        'http.fail $method $path status=0 ms=${started.elapsedMilliseconds} '
        'category=other phase=$phase type=${error.runtimeType} '
        'hadSession=$hadSession',
      );
      return const UatHttpResult(
        0,
        {'error': 'OFFLINE'},
        category: UatFailureCategory.other,
      );
    } finally {
      client.close(force: true);
    }
  }

  static const _connectTimeout = Duration(seconds: 8);
  static const _responseTimeout = Duration(seconds: 12);

  static void _perfLog(String message) {
    if (!InteractionPerf.enabled) return;
    debugPrint('PZD_PERF $message');
  }
}

enum UatFailureCategory {
  ok,
  offline,
  connectTimeout,
  responseTimeout,
  malformed,
  other,
}

final class UatHttpResult {
  const UatHttpResult(
    this.status,
    this.json, {
    this.category = UatFailureCategory.ok,
  });

  final int status;
  final Object? json;
  final UatFailureCategory category;

  Map<String, Object?> get map {
    final value = json;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return const {};
  }

  String get error => map['error']?.toString() ?? 'REQUEST_FAILED';

  bool get isTimeout =>
      category == UatFailureCategory.connectTimeout ||
      category == UatFailureCategory.responseTimeout ||
      error == 'TIMEOUT';
}

final class _UatTimeout implements Exception {
  const _UatTimeout(this.phase);
  final String phase;
}
