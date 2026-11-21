import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Staging guest-auth transport. No Firebase Authentication dependency.
///
/// The server owns player identity. Never use the playerId as an auth proof.
abstract interface class GuestCredentialStore {
  Future<String?> readRefreshToken();
  Future<void> writeRefreshToken(String token);
  Future<void> clearRefreshToken();
}

final class GuestAccess {
  const GuestAccess({required this.accessToken, required this.expiresAt});
  final String accessToken;
  final DateTime expiresAt;

  /// Local vault namespace only; the server must verify the JWT signature.
  /// Never use this unverified claim as authorization or a player ID.
  String get sessionVaultBinding {
    try {
      final parts = accessToken.split('.');
      if (parts.length != 3) throw const FormatException('jwt');
      final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      if (claims is! Map || claims['iss'] != 'https://staging.puzzle-duel.app' ||
          claims['aud'] != 'puzzle-duel-api' || claims['account_type'] != 'guest') {
        throw const FormatException('claims');
      }
      final subject = claims['sub'];
      if (subject is! String ||
          !RegExp(r'^[0-9a-fA-F-]{36}

/// Backend contract: POST /v1/auth/guest -> {accessToken,refreshToken,expiresAt}
/// POST /v1/auth/refresh {refreshToken} -> same shape.
/// Server must atomically rotate refresh tokens and reject replay.
final class GuestAuthClient {
  GuestAuthClient({
    required this.origin,
    required this.credentials,
    HttpClient Function()? httpClientFactory,
  }) : _factory = httpClientFactory ?? HttpClient.new {
    final uri = Uri.parse(origin);
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty ||
        uri.hasQuery || uri.hasFragment || (uri.path.isNotEmpty && uri.path != '/')) {
      throw ArgumentError.value(origin, 'origin', 'HTTPS origin required');
    }
  }

  final String origin;
  final GuestCredentialStore credentials;
  final HttpClient Function() _factory;
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
    if (previous != null && previous.isNotEmpty) {
      // Never silently create a new player on transient refresh failures.
      final result = await _post('/v1/auth/refresh', {'refreshToken': previous});
      if (result.status == 200) return _save(result.body);
      if (result.status != 401 && result.status != 403) {
        throw const GuestAuthException('REFRESH_UNAVAILABLE');
      }
      // Invalid/revoked credentials must not be silently replaced: the user
      // may have ranked progress tied to this guest identity.
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
    await credentials.writeRefreshToken(refresh);
    return _current = GuestAccess(accessToken: access, expiresAt: expiresAt);
  }

  Future<_GuestResponse> _post(String path, Map<String, Object?> body) async {
    final client = _factory();
    client.connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.postUrl(Uri.parse(origin).resolve(path))
          .timeout(const Duration(seconds: 8));
      request.headers.contentType = ContentType.json;
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
      return _GuestResponse(response.statusCode, parsed);
    } on GuestAuthException {
      rethrow;
    } catch (_) {
      // Never include request/response content or credentials in diagnostics.
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
).hasMatch(subject)) {
        throw const FormatException('subject');
      }
      return 'staging-guest:$subject';
    } catch (_) {
      throw const GuestAuthException('INVALID_AUTH_RESPONSE');
    }
  }
}

/// Backend contract: POST /v1/auth/guest -> {accessToken,refreshToken,expiresAt}
/// POST /v1/auth/refresh {refreshToken} -> same shape.
/// Server must atomically rotate refresh tokens and reject replay.
final class GuestAuthClient {
  GuestAuthClient({
    required this.origin,
    required this.credentials,
    HttpClient Function()? httpClientFactory,
  }) : _factory = httpClientFactory ?? HttpClient.new {
    final uri = Uri.parse(origin);
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty ||
        uri.hasQuery || uri.hasFragment || (uri.path.isNotEmpty && uri.path != '/')) {
      throw ArgumentError.value(origin, 'origin', 'HTTPS origin required');
    }
  }

  final String origin;
  final GuestCredentialStore credentials;
  final HttpClient Function() _factory;
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
    if (previous != null && previous.isNotEmpty) {
      // Never silently create a new player on transient refresh failures.
      final result = await _post('/v1/auth/refresh', {'refreshToken': previous});
      if (result.status == 200) return _save(result.body);
      if (result.status != 401 && result.status != 403) {
        throw const GuestAuthException('REFRESH_UNAVAILABLE');
      }
      // Invalid/revoked credentials must not be silently replaced: the user
      // may have ranked progress tied to this guest identity.
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
    await credentials.writeRefreshToken(refresh);
    return _current = GuestAccess(accessToken: access, expiresAt: expiresAt);
  }

  Future<_GuestResponse> _post(String path, Map<String, Object?> body) async {
    final client = _factory();
    client.connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.postUrl(Uri.parse(origin).resolve(path))
          .timeout(const Duration(seconds: 8));
      request.headers.contentType = ContentType.json;
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
      return _GuestResponse(response.statusCode, parsed);
    } on GuestAuthException {
      rethrow;
    } catch (_) {
      // Never include request/response content or credentials in diagnostics.
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
