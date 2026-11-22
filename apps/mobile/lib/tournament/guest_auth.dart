import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:puzzle_duel_mobile/diagnostics/diagnostic_runtime.dart';
import 'package:puzzle_duel_mobile/diagnostics/puzzle_duel_logger.dart';

/// Staging guest-auth transport. No Firebase Authentication dependency.
///
/// The server owns player identity. Never use the playerId as an auth proof.
abstract interface class GuestCredentialStore {
  Future<String?> readRefreshToken();
  Future<void> writeRefreshToken(String token);
  Future<void> clearRefreshToken();
  Future<String?> readPendingRotationId();
  Future<void> writePendingRotationId(String id);
  Future<void> clearPendingRotationId();
}

final class GuestAccess {
  const GuestAccess({required this.accessToken, required this.expiresAt});
  final String accessToken;
  final DateTime expiresAt;

  /// Local vault namespace only. Server-side JWT verification remains mandatory.
  String get sessionVaultBinding {
    try {
      final parts = accessToken.split('.');
      if (parts.length != 3) throw const FormatException('jwt');
      final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      if (claims is! Map ||
          claims['iss'] != 'https://staging.puzzle-duel.app' ||
          claims['aud'] != 'puzzle-duel-api' ||
          claims['account_type'] != 'guest') {
        throw const FormatException('claims');
      }
      final subject = claims['sub'];
      if (subject is! String || subject.length != 36 ||
          !RegExp(r'^[0-9a-fA-F-]+$').hasMatch(subject)) {
        throw const FormatException('subject');
      }
      return 'staging-guest:$subject';
    } catch (_) {
      throw const GuestAuthException('INVALID_AUTH_RESPONSE');
    }
  }
}

/// Write and independently read back before reporting durable token rotation.
Future<void> persistVerifiedGuestCredential(GuestCredentialStore store, String token) async {
  await store.writeRefreshToken(token);
  final confirmed = await store.readRefreshToken();
  if (confirmed != token) throw const GuestAuthException('SECURE_STORE_VERIFY_FAILED');
}

/// Durable intent must exist before the network request. Its identity survives
/// app termination, HTTP timeouts and the UTC daily tournament cutover.
Future<String> acquireVerifiedGuestRotationId(
  GuestCredentialStore store, String Function() newId,
) async {
  var id = await store.readPendingRotationId();
  if (id == null || id.isEmpty) {
    id = newId();
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) {
      throw const GuestAuthException('SECURE_STORE_VERIFY_FAILED');
    }
    await store.writePendingRotationId(id);
    if (await store.readPendingRotationId() != id) {
      throw const GuestAuthException('SECURE_STORE_VERIFY_FAILED');
    }
  }
  if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) {
    throw const GuestAuthException('SECURE_STORE_VERIFY_FAILED');
  }
  return id;
}

/// Backend contract: POST /v1/auth/guest -> {accessToken,refreshToken,expiresAt}
/// POST /v1/auth/refresh {refreshToken} -> same shape.
/// Server must atomically rotate refresh tokens and reject replay.
final class GuestAuthClient {
  GuestAuthClient({
    required this.origin,
    required this.credentials,
    HttpClient Function()? httpClientFactory,
    PuzzleDuelLogger? logger,
    bool? rotationRetryEnabled,
  }) : _factory = httpClientFactory ?? HttpClient.new,
       _logger = logger ?? DiagnosticRuntime.logger,
       _rotationRetryEnabled = rotationRetryEnabled ??
           const bool.fromEnvironment('PZD_GUEST_RETRY_ENABLED', defaultValue: false) {
    final uri = Uri.parse(origin);
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty ||
        uri.hasQuery || uri.hasFragment || (uri.path.isNotEmpty && uri.path != '/')) {
      throw ArgumentError.value(origin, 'origin', 'HTTPS origin required');
    }
  }

  final String origin;
  final GuestCredentialStore credentials;
  final HttpClient Function() _factory;
  final PuzzleDuelLogger _logger;
  final bool _rotationRetryEnabled;

  // Fixed protocol vocabulary only. No token, identity, raw URL or body data.
  void _breadcrumb(LogCode code, String operation, {
    String? requestId, int? httpStatus, String? errorCode,
  }) {
    unawaited(_logger.log(LogEvent(
      level: errorCode == null ? LogLevel.info : LogLevel.warning,
      code: code, operation: operation, requestId: requestId,
      httpVerb: HttpVerb.post, httpStatus: httpStatus, errorCode: errorCode,
    )));
  }

  static String _newRequestId() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<GuestAccess>? _pending;
  GuestAccess? _current;

  /// Coalesces concurrent app startup/foreground authentication attempts.
  Future<GuestAccess> authenticate({bool forceRefresh = false}) {
    final cached = _current;
    if (!forceRefresh && cached != null &&
        cached.expiresAt.isAfter(DateTime.now().toUtc().add(const Duration(minutes: 1)))) {
      return Future.value(cached);
    }
    final pending = _pending;
    if (pending != null) return pending;
    final next = _authenticate();
    _pending = next;
    return next.whenComplete(() => _pending = null);
  }

  Future<GuestAccess> _authenticate() async {
    final previous = await credentials.readRefreshToken();
    _breadcrumb(LogCode.authExpired, previous == null || previous.isEmpty
        ? 'guest_refresh_absent' : 'guest_refresh_present');
    if (previous != null && previous.isNotEmpty) {
      // Never silently create a new player on transient refresh failures.
      String? rotationId;
      if (_rotationRetryEnabled) {
        rotationId = await acquireVerifiedGuestRotationId(
            credentials, _newRequestId);
        _breadcrumb(LogCode.authRefreshSucceeded, 'guest_rotation_intent_saved');
      }
      final result = await _post('/v1/auth/refresh', {
        'refreshToken': previous,
        'rotationId': ?rotationId,
      });
      if (result.status == 200) {
        _breadcrumb(LogCode.authRefreshSucceeded, 'guest_refresh_http_succeeded');
        final access = await _save(result.body);
        if (_rotationRetryEnabled) {
          await credentials.clearPendingRotationId();
          _breadcrumb(LogCode.authRefreshSucceeded, 'guest_rotation_intent_cleared');
        }
        return access;
      }
      if (result.status != 401 && result.status != 403) {
        _breadcrumb(LogCode.authRefreshFailed, 'guest_refresh_unavailable',
            httpStatus: result.status, errorCode: 'REFRESH_UNAVAILABLE');
        throw const GuestAuthException('REFRESH_UNAVAILABLE');
      }
      // Invalid/revoked credentials must not be silently replaced: the user
      // may have ranked progress tied to this guest identity.
      _breadcrumb(LogCode.authRefreshFailed, 'guest_refresh_rejected',
          httpStatus: result.status, errorCode: 'GUEST_RECOVERY_REQUIRED');
      throw const GuestAuthException('GUEST_RECOVERY_REQUIRED');
    }
    final result = await _post('/v1/auth/guest', const {});
    if (result.status != 201 && result.status != 200) {
      throw const GuestAuthException('GUEST_CREATION_UNAVAILABLE');
    }
    return _save(result.body);
  }

  Future<GuestAccess> _save(Map<String, dynamic> data) async {
    final access = data['accessToken'];
    final refresh = data['refreshToken'];
    final expiry = data['expiresAt'];
    if (access is! String || access.isEmpty || refresh is! String ||
        refresh.isEmpty || expiry is! String) {
      throw const GuestAuthException('INVALID_AUTH_RESPONSE');
    }
    final expiresAt = DateTime.tryParse(expiry)?.toUtc();
    if (expiresAt == null || !expiresAt.isAfter(DateTime.now().toUtc())) {
      throw const GuestAuthException('INVALID_AUTH_RESPONSE');
    }
    _breadcrumb(LogCode.authRefreshSucceeded, 'guest_refresh_vault_write_started');
    try {
      await persistVerifiedGuestCredential(credentials, refresh);
    } catch (_) {
      _breadcrumb(LogCode.authRefreshFailed, 'guest_refresh_vault_write_failed',
          errorCode: 'SECURE_STORE_UNAVAILABLE');
      throw const GuestAuthException('SECURE_STORE_UNAVAILABLE');
    }
    _breadcrumb(LogCode.authRefreshSucceeded, 'guest_refresh_vault_write_completed');
    return _current = GuestAccess(accessToken: access, expiresAt: expiresAt);
  }

  Future<_GuestResponse> _post(String path, Map<String, Object?> body) async {
    final client = _factory();
    final requestId = _newRequestId();
    final operation = path == '/v1/auth/refresh' ? 'guest_auth_refresh' : 'guest_auth_create';
    _breadcrumb(LogCode.httpStarted, operation, requestId: requestId);
    client.connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.postUrl(Uri.parse(origin).resolve(path))
          .timeout(const Duration(seconds: 8));
      request.headers.contentType = ContentType.json;
      request.headers.set('x-request-id', requestId);
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      final payload = utf8.encode(jsonEncode(body));
      request.contentLength = payload.length;
      request.add(payload);
      final response = await request.close().timeout(const Duration(seconds: 12));
      final bytes = await response.fold<List<int>>(<int>[], (a, b) => a..addAll(b))
          .timeout(const Duration(seconds: 12));
      if (bytes.length > 16384) throw const GuestAuthException('INVALID_AUTH_RESPONSE');
      final parsed = jsonDecode(utf8.decode(bytes));
      if (parsed is! Map<String, dynamic>) {
        throw const GuestAuthException('INVALID_AUTH_RESPONSE');
      }
      _breadcrumb(LogCode.httpCompleted, operation, requestId: requestId,
          httpStatus: response.statusCode,
          errorCode: response.statusCode >= 400 ? 'AUTH_HTTP_REJECTED' : null);
      return _GuestResponse(response.statusCode, parsed);
    } on GuestAuthException {
      _breadcrumb(LogCode.httpFailed, operation, requestId: requestId,
          errorCode: 'AUTH_INVALID_RESPONSE');
      rethrow;
    } catch (_) {
      // Never include request/response content or credentials in diagnostics.
      _breadcrumb(LogCode.httpFailed, operation, requestId: requestId,
          errorCode: 'AUTH_NETWORK_UNAVAILABLE');
      throw const GuestAuthException('AUTH_NETWORK_UNAVAILABLE');
    } finally {
      client.close(force: true);
    }
  }
}

final class _GuestResponse {
  const _GuestResponse(this.status, this.body);
  final int status;
  final Map<String, dynamic> body;
}

final class GuestAuthException implements Exception {
  const GuestAuthException(this.code);
  final String code;
  @override
  String toString() => code;
}