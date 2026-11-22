import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:puzzle_duel_mobile/diagnostics/diagnostic_runtime.dart';
import 'package:puzzle_duel_mobile/diagnostics/puzzle_duel_logger.dart';


/// Authenticated Tournament UAT client. It never sends a score or a seal.
class UatApi {
  UatApi({
    required this.baseUrl,
    required String bearer,
    this.sessionSecret,
    this.accessTokenProvider,
    HttpClient Function()? httpClientFactory,
  }) : bearer = normalizeBearer(bearer),
       _httpClientFactory = httpClientFactory ?? HttpClient.new;

  /// Origin only (scheme/host/port). Never includes credentials.
  final String baseUrl;
  String bearer;
  String? sessionSecret;
  /// Optional staging token provider; UAT fixed-bearer mode remains unchanged.
  final Future<String> Function()? accessTokenProvider;
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

  /// Explicit staging-only diagnostic report submission. Never automatic.
  /// The server validates the fixed event schema and returns a reportId.
  Future<UatHttpResult> sendDiagnosticReport() async {
    if (!DiagnosticRuntime.policy.manualReportEnabled) {
      return const UatHttpResult(
        403, {'error': 'DIAGNOSTICS_DISABLED'},
        category: UatFailureCategory.client,
      );
    }
    final events = (await DiagnosticRuntime.snapshot())
        .where((event) => event.code != LogCode.httpStarted && event.code != LogCode.screenOpened)
        .toList();
    return post('/v1/diagnostics/reports', {
      'events': events.length <= 64
          ? events.map((event) => event.toJson()).toList()
          : events.skip(events.length - 64)
              .map((event) => event.toJson()).toList(),
    });
  }

  Future<UatHttpResult> get(String path) => _send('GET', path, null);

  /// Traced variant without changing the existing mockable GET contract.
  Future<UatHttpResult> getTraced(String path, {required String traceId}) =>
      _send('GET', path, null, traceId: traceId);

  Future<UatHttpResult> patch(String path) => _send('PATCH', path, null);

  Future<UatHttpResult> post(String path, [Object? body]) =>
      _send('POST', path, body);

  /// Same HTTP operation, with a safe per-move correlation ID.
  Future<UatHttpResult> postTraced(
    String path,
    Object? body, {
    required String traceId,
  }) => _send('POST', path, body, traceId: traceId);

  Future<UatHttpResult> _send(
    String method,
    String path,
    Object? body, {
    String? traceId,
  }) async {
    final started = Stopwatch()..start();
    final requestId = _newDiagnosticId();
    unawaited(DiagnosticRuntime.logger.log(LogEvent(
      level: LogLevel.info, code: LogCode.httpStarted,
      operation: 'tournament_http', requestId: requestId,
      traceId: traceId,
    )));
    final client = _httpClientFactory();
    client.connectionTimeout = _connectTimeout;
    var diagnosticStatus = 0;
    try {
      final uri = Uri.parse('$baseUrl$path');
      final request = await client.openUrl(method, uri).timeout(
        _connectTimeout,
        onTimeout: () => throw const _UatTimeout('connect'),
      );
      final token = accessTokenProvider == null
          ? bearer
          : normalizeBearer(await accessTokenProvider!());
      request.headers.set(HttpHeaders.authorizationHeader, token);
      request.headers.set('x-request-id', requestId);
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
      final response = await request.close().timeout(
        _responseTimeout,
        onTimeout: () => throw const _UatTimeout('response'),
      );
      diagnosticStatus = response.statusCode;
      final text = await utf8.decodeStream(response).timeout(
        _responseTimeout,
        onTimeout: () => throw const _UatTimeout('response'),
      );
      Object? json;
      if (text.isNotEmpty) {
        try {
          json = jsonDecode(text);
        } on FormatException {

          return UatHttpResult(
            response.statusCode,
            {'error': 'MALFORMED_BODY'},
            category: UatFailureCategory.malformed,
          );
        }
      }
      final category = categoryForStatus(response.statusCode);
      _structuredAuthStatus(response.statusCode, json, requestId);

      return UatHttpResult(response.statusCode, json, category: category);
    } on _UatTimeout catch (error) {
      final category = error.phase == 'connect'
          ? UatFailureCategory.connectTimeout
          : UatFailureCategory.responseTimeout;

      return UatHttpResult(
        0,
        {'error': 'TIMEOUT', 'timeoutPhase': error.phase},
        category: category,
      );
    } on SocketException {

      return const UatHttpResult(
        0,
        {'error': 'OFFLINE'},
        category: UatFailureCategory.offline,
      );
    } on HttpException {

      return const UatHttpResult(
        0,
        {'error': 'OFFLINE'},
        category: UatFailureCategory.offline,
      );
    } on TimeoutException {

      return const UatHttpResult(
        0,
        {'error': 'TIMEOUT', 'timeoutPhase': 'response'},
        category: UatFailureCategory.responseTimeout,
      );
    } on Exception {

      return const UatHttpResult(
        0,
        {'error': 'OFFLINE'},
        category: UatFailureCategory.other,
      );
    } finally {
      started.stop();
      _structuredHttp(method: method, status: diagnosticStatus,
          requestId: requestId, traceId: traceId,
          durationMs: started.elapsedMilliseconds);
      client.close(force: true);
    }
  }

  static void _structuredAuthStatus(int status, Object? response, String requestId) {
    LogCode? code;
    String? reason;
    if (status == 401) {
      code = LogCode.authExpired;
    } else if (status == 409 && response is Map) {
      final safeCode = diagnosticErrorCode(response['error']?.toString());
      if (safeCode == 'STALE_WRITER' ||
          safeCode == 'WRITER_NOT_AUTHORIZED' ||
          safeCode == 'WRITER_STILL_ACTIVE') {
        code = LogCode.writerBindingRejected;
        reason = safeCode;
      }
    }
    if (code == null) return;
    unawaited(DiagnosticRuntime.logger.log(LogEvent(
      level: LogLevel.warning,
      code: code,
      operation: 'tournament_session',
      requestId: requestId,
      errorCode: reason,
      httpStatus: status,
    )));
  }

  static String _newDiagnosticId() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static void _structuredHttp({
    required String method,
    required int status,
    required String requestId,
    String? traceId,
    required int durationMs,
  }) {
    // Crashlytics keeps both successful and failed requests as breadcrumbs.
    final verb = switch (method) {
      'GET' => HttpVerb.get,
      'POST' => HttpVerb.post,
      'PATCH' => HttpVerb.patch,
      'PUT' => HttpVerb.put,
      _ => HttpVerb.delete,
    };
    unawaited(DiagnosticRuntime.logger.log(LogEvent(
      level: status >= 200 && status < 400 ? LogLevel.info : LogLevel.warning,
      code: status >= 200 && status < 400 ? LogCode.httpCompleted : LogCode.httpFailed,
      operation: 'tournament_http',
      requestId: requestId,
      traceId: traceId,
      httpVerb: verb,
      httpStatus: status == 0 ? null : status,
      durationMs: durationMs,
    )));
  }

  static const _connectTimeout = Duration(seconds: 8);
  static const _responseTimeout = Duration(seconds: 12);

  /// Maps HTTP status to a safe diagnostic category (never auth material).
  static UatFailureCategory categoryForStatus(int status) {
    if (status >= 200 && status < 300) return UatFailureCategory.ok;
    if (status == 401) return UatFailureCategory.unauthenticated;
    if (status == 0) return UatFailureCategory.offline;
    if (status >= 500) return UatFailureCategory.server;
    if (status >= 400) return UatFailureCategory.client;
    return UatFailureCategory.other;
  }

  /// Only known protocol error codes may enter diagnostics. Never log an
  /// arbitrary response string (which could accidentally contain secrets).
  static String? diagnosticErrorCode(String? code) {
    if (code == null) return null;
    return const {
      'SERIES_NOT_OWNED',
      'RECOVERY_NOT_ELIGIBLE',
      'RECOVERY_PROOF_INVALID',
      'WRITER_STILL_ACTIVE',
      'STALE_WRITER',
      'SERIES_TERMINAL',
      'IDLE_EXPIRED',
      'HARD_CUTOFF_EXPIRED',
      'SERIES_STATE_INCONSISTENT',
      'WRITER_NOT_AUTHORIZED',
      'UNAUTHENTICATED',
      'STATE_CONFLICT',
      'CLAIM_WINDOW_CLOSED',
      'TIMEOUT',
      'OFFLINE',
      'MALFORMED_REQUEST',
      'REQUEST_FAILED',
    }.contains(code) ? code : null;
  }

}

enum UatFailureCategory {
  ok,
  offline,
  connectTimeout,
  responseTimeout,
  malformed,
  unauthenticated,
  client,
  server,
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
