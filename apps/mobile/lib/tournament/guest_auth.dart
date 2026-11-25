import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:puzzle_duel_mobile/diagnostics/diagnostic_runtime.dart';
import 'package:puzzle_duel_mobile/diagnostics/puzzle_duel_logger.dart';

/// Staging session auth transport. No Firebase Authentication dependency.
///
/// The server owns player identity. Never use the playerId as an auth proof.
abstract interface class GuestCredentialStore {
  Future<String?> readRefreshToken();
  Future<void> writeRefreshToken(String token);
  Future<void> clearRefreshToken();
  Future<String?> readPendingRotationId();
  Future<void> writePendingRotationId(String id);
  Future<void> clearPendingRotationId();
  /// Durable provider name (`apple`|`google`) while a link may have succeeded
  /// without a confirmed vault write. Never stores tokens or nonces.
  Future<String?> readPendingLinkProvider();
  Future<void> writePendingLinkProvider(String provider);
  Future<void> clearPendingLinkProvider();
}

enum AccountType { guest, verified }

final class GuestAccess {
  const GuestAccess({
    required this.accessToken,
    required this.expiresAt,
    required this.accountType,
    required this.playerId,
    this.familyId,
  });
  final String accessToken;
  final DateTime expiresAt;
  final AccountType accountType;
  final String playerId;
  /// Exact refresh family id from staging JWT `fid` when present.
  final String? familyId;

  bool get isVerified => accountType == AccountType.verified;
  bool get isGuest => accountType == AccountType.guest;

  /// Local vault namespace only. Server-side JWT verification remains mandatory.
  /// Prefix stays `staging-guest:` so practice isolation keys remain stable
  /// across guest→verified linking of the same player_id.
  String get sessionVaultBinding => 'staging-guest:$playerId';

  bool get isNearExpiry =>
      !expiresAt.isAfter(DateTime.now().toUtc().add(const Duration(minutes: 2)));

  /// Parses a staging access JWT. Accepts guest or verified account_type.
  static GuestAccess parse({
    required String accessToken,
    required DateTime expiresAt,
  }) {
    try {
      final parts = accessToken.split('.');
      if (parts.length != 3) throw const FormatException('jwt');
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (claims is! Map ||
          claims['iss'] != 'https://staging.puzzle-duel.app' ||
          claims['aud'] != 'puzzle-duel-api') {
        throw const FormatException('claims');
      }
      final typeRaw = claims['account_type'];
      final AccountType accountType;
      if (typeRaw == 'guest') {
        accountType = AccountType.guest;
      } else if (typeRaw == 'verified') {
        accountType = AccountType.verified;
      } else {
        throw const FormatException('account_type');
      }
      final subject = claims['sub'];
      if (subject is! String ||
          subject.length != 36 ||
          !RegExp(r'^[0-9a-fA-F-]+$').hasMatch(subject)) {
        throw const FormatException('subject');
      }
      final fid = claims['fid'];
      final String? familyId;
      if (fid == null) {
        familyId = null;
      } else if (fid is String &&
          fid.isNotEmpty &&
          fid.length <= 128 &&
          RegExp(r'^[0-9a-zA-Z_-]+$').hasMatch(fid)) {
        familyId = fid;
      } else {
        throw const FormatException('fid');
      }
      return GuestAccess(
        accessToken: accessToken,
        expiresAt: expiresAt,
        accountType: accountType,
        playerId: subject,
        familyId: familyId,
      );
    } catch (_) {
      throw const GuestAuthException('INVALID_AUTH_RESPONSE');
    }
  }
}

/// Write and independently read back before reporting durable token rotation.
Future<void> persistVerifiedGuestCredential(
  GuestCredentialStore store,
  String token,
) async {
  await store.writeRefreshToken(token);
  final confirmed = await store.readRefreshToken();
  if (confirmed != token) {
    throw const GuestAuthException('SECURE_STORE_VERIFY_FAILED');
  }
}

/// Durable intent must exist before the network request. Its identity survives
/// app termination, HTTP timeouts and the UTC daily tournament cutover.
Future<String> acquireVerifiedGuestRotationId(
  GuestCredentialStore store,
  String Function() newId,
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
  })  : _factory = httpClientFactory ?? HttpClient.new,
        _logger = logger ?? DiagnosticRuntime.logger,
        _rotationRetryEnabled = rotationRetryEnabled ??
            const bool.fromEnvironment(
              'PZD_GUEST_RETRY_ENABLED',
              defaultValue: false,
            ) {
    final uri = Uri.parse(origin);
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw ArgumentError.value(origin, 'origin', 'HTTPS origin required');
    }
  }

  final String origin;
  final GuestCredentialStore credentials;
  final HttpClient Function() _factory;
  final PuzzleDuelLogger _logger;
  final bool _rotationRetryEnabled;

  void _breadcrumb(
    LogCode code,
    String operation, {
    String? requestId,
    int? httpStatus,
    String? errorCode,
  }) {
    unawaited(_logger.log(LogEvent(
      level: errorCode == null ? LogLevel.info : LogLevel.warning,
      code: code,
      operation: operation,
      requestId: requestId,
      httpVerb: HttpVerb.post,
      httpStatus: httpStatus,
      errorCode: errorCode,
    )));
  }

  static String _newRequestId() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<GuestAccess>? _pending;
  int _pendingGeneration = 0;
  GuestAccess? _current;
  int _credentialGeneration = 0;

  /// Serializes durable vault mutations so stale refresh cannot interleave with
  /// link/logout commits. Nested vault work inside a held mutation must call
  /// the `*Unlocked` helpers — never re-enter `_serializedMutation` via a
  /// boolean flag (external callers during an await would race).
  Future<void> _mutationChain = Future<void>.value();

  GuestAccess? get cachedAccess => _current;
  int get credentialGeneration => _credentialGeneration;

  @visibleForTesting
  void debugSeedAccess(GuestAccess access) {
    _current = access;
  }

  Future<T> _serializedMutation<T>(Future<T> Function() action) {
    final gate = Completer<T>();
    _mutationChain = _mutationChain.then((_) async {
      try {
        gate.complete(await action());
      } catch (error, stack) {
        gate.completeError(error, stack);
      }
    });
    return gate.future;
  }

  /// Coalesces concurrent authentication. Stale `_pending` futures from a prior
  /// generation (after logout/link) are never reused.
  Future<GuestAccess> authenticate({bool forceRefresh = false}) {
    final cached = _current;
    if (!forceRefresh &&
        cached != null &&
        cached.expiresAt
            .isAfter(DateTime.now().toUtc().add(const Duration(minutes: 1)))) {
      return Future.value(cached);
    }
    final pending = _pending;
    if (pending != null && _pendingGeneration == _credentialGeneration) {
      return pending;
    }
    final generation = _credentialGeneration;
    final next = _authenticate(generation: generation);
    _pending = next;
    _pendingGeneration = generation;
    return next.whenComplete(() {
      if (identical(_pending, next)) {
        _pending = null;
      }
    });
  }

  /// Refreshes the guest access token while requiring the same player and
  /// family (fid). Used after native provider UI may outlive access TTL.
  Future<GuestAccess> refreshGuestPreservingIdentity({
    required String playerId,
    required String? familyId,
  }) {
    return _serializedMutation(() async {
      final generation = _credentialGeneration;
      final access = await _authenticate(
        generation: generation,
        forceNetworkRefresh: true,
        vaultLocked: true,
      );
      if (access.playerId != playerId || access.familyId != familyId) {
        throw const GuestAuthException('GUEST_IDENTITY_CHANGED');
      }
      if (!access.isGuest) {
        throw const GuestAuthException('INVALID_AUTH_RESPONSE');
      }
      return access;
    });
  }

  Future<GuestAccess> replaceWithVerifiedBundle({
    required String accessToken,
    required String refreshToken,
    required DateTime expiresAt,
  }) {
    return _serializedMutation(() async {
      final generation = ++_credentialGeneration;
      _pending = null;
      _breadcrumb(LogCode.authRefreshSucceeded, 'auth_credential_replace_started');
      final access = GuestAccess.parse(
        accessToken: accessToken,
        expiresAt: expiresAt,
      );
      if (!access.isVerified) {
        throw const GuestAuthException('INVALID_AUTH_RESPONSE');
      }
      try {
        await persistVerifiedGuestCredential(credentials, refreshToken);
      } catch (_) {
        _breadcrumb(LogCode.authRefreshFailed, 'auth_credential_replace_failed',
            errorCode: 'SECURE_STORE_UNAVAILABLE');
        throw const GuestAuthException('SECURE_STORE_UNAVAILABLE');
      }
      if (generation != _credentialGeneration) {
        _breadcrumb(LogCode.authRefreshFailed, 'auth_credential_replace_stale',
            errorCode: 'STALE_CREDENTIAL_RESPONSE');
        throw const GuestAuthException('STALE_CREDENTIAL_RESPONSE');
      }
      await credentials.clearPendingRotationId();
      await credentials.clearPendingLinkProvider();
      _breadcrumb(LogCode.authRefreshSucceeded, 'auth_credential_replaced');
      return _current = access;
    });
  }

  Future<void> markPendingLinkProvider(String provider) {
    if (provider != 'apple' && provider != 'google') {
      throw const GuestAuthException('INVALID_AUTH_RESPONSE');
    }
    return _serializedMutation(() async {
      await credentials.writePendingLinkProvider(provider);
      final confirmed = await credentials.readPendingLinkProvider();
      if (confirmed != provider) {
        throw const GuestAuthException('SECURE_STORE_VERIFY_FAILED');
      }
      _breadcrumb(LogCode.authRefreshSucceeded, 'auth_pending_link_saved');
    });
  }

  Future<String?> readPendingLinkProvider() =>
      credentials.readPendingLinkProvider();

  Future<void> clearPendingLinkProvider() => _serializedMutation(() async {
        await credentials.clearPendingLinkProvider();
      });

  Future<void> clearSessionLocally() {
    return _serializedMutation(() async {
      _credentialGeneration++;
      _pending = null;
      _current = null;
      await credentials.clearRefreshToken();
      await credentials.clearPendingRotationId();
      // Keep pending link marker so restart can recover via provider login.
      _breadcrumb(LogCode.authExpired, 'auth_logout_local_cleared');
    });
  }

  Future<GuestAccess> _authenticate({
    required int generation,
    bool forceNetworkRefresh = false,
    bool vaultLocked = false,
  }) async {
    if (generation != _credentialGeneration) {
      throw const GuestAuthException('STALE_CREDENTIAL_RESPONSE');
    }
    final previous = await credentials.readRefreshToken();
    _breadcrumb(
      LogCode.authExpired,
      previous == null || previous.isEmpty
          ? 'guest_refresh_absent'
          : 'guest_refresh_present',
    );
    if (previous != null && previous.isNotEmpty) {
      String? rotationId;
      if (_rotationRetryEnabled) {
        Future<String> acquire() async {
          if (generation != _credentialGeneration) {
            throw const GuestAuthException('STALE_CREDENTIAL_RESPONSE');
          }
          return acquireVerifiedGuestRotationId(credentials, _newRequestId);
        }

        rotationId = vaultLocked
            ? await acquire()
            : await _serializedMutation(acquire);
        _breadcrumb(LogCode.authRefreshSucceeded, 'guest_rotation_intent_saved');
      }
      final result = await _post('/v1/auth/refresh', {
        'refreshToken': previous,
        'rotationId': ?rotationId,
      });
      if (result.status == 200) {
        _breadcrumb(
            LogCode.authRefreshSucceeded, 'guest_refresh_http_succeeded');
        return _commitCredentials(
          result.body,
          generation: generation,
          clearRotation: _rotationRetryEnabled,
          vaultLocked: vaultLocked,
        );
      }
      if (result.status != 401 && result.status != 403) {
        _breadcrumb(LogCode.authRefreshFailed, 'guest_refresh_unavailable',
            httpStatus: result.status, errorCode: 'REFRESH_UNAVAILABLE');
        throw const GuestAuthException('REFRESH_UNAVAILABLE');
      }
      final pendingLink = await credentials.readPendingLinkProvider();
      if (pendingLink == 'apple' || pendingLink == 'google') {
        _breadcrumb(LogCode.authRefreshFailed, 'auth_pending_link_recovery',
            httpStatus: result.status, errorCode: 'PROVIDER_LINK_RECOVERY');
        throw GuestAuthException('PROVIDER_LINK_RECOVERY_$pendingLink');
      }
      _breadcrumb(LogCode.authRefreshFailed, 'guest_refresh_rejected',
          httpStatus: result.status, errorCode: 'GUEST_RECOVERY_REQUIRED');
      throw const GuestAuthException('GUEST_RECOVERY_REQUIRED');
    }
    if (forceNetworkRefresh) {
      throw const GuestAuthException('GUEST_RECOVERY_REQUIRED');
    }
    final pendingLink = await credentials.readPendingLinkProvider();
    if (pendingLink == 'apple' || pendingLink == 'google') {
      // Never silently mint a new guest while a link may have upgraded identity.
      throw GuestAuthException('PROVIDER_LINK_RECOVERY_$pendingLink');
    }
    final result = await _post('/v1/auth/guest', const {});
    if (result.status != 201 && result.status != 200) {
      throw const GuestAuthException('GUEST_CREATION_UNAVAILABLE');
    }
    return _commitCredentials(
      result.body,
      generation: generation,
      vaultLocked: vaultLocked,
    );
  }

  Future<GuestAccess> _commitCredentials(
    Map<String, dynamic> data, {
    required int generation,
    bool clearRotation = false,
    bool vaultLocked = false,
  }) {
    Future<GuestAccess> body() async {
      if (generation != _credentialGeneration) {
        _breadcrumb(LogCode.authRefreshFailed, 'guest_refresh_stale_discarded',
            errorCode: 'STALE_CREDENTIAL_RESPONSE');
        throw const GuestAuthException('STALE_CREDENTIAL_RESPONSE');
      }
      final accessToken = data['accessToken'];
      final refresh = data['refreshToken'];
      final expiry = data['expiresAt'];
      if (accessToken is! String ||
          accessToken.isEmpty ||
          refresh is! String ||
          refresh.isEmpty ||
          expiry is! String) {
        throw const GuestAuthException('INVALID_AUTH_RESPONSE');
      }
      final expiresAt = DateTime.tryParse(expiry)?.toUtc();
      if (expiresAt == null || !expiresAt.isAfter(DateTime.now().toUtc())) {
        throw const GuestAuthException('INVALID_AUTH_RESPONSE');
      }
      final access = GuestAccess.parse(
        accessToken: accessToken,
        expiresAt: expiresAt,
      );
      _breadcrumb(
          LogCode.authRefreshSucceeded, 'guest_refresh_vault_write_started');
      try {
        await persistVerifiedGuestCredential(credentials, refresh);
      } catch (_) {
        _breadcrumb(LogCode.authRefreshFailed, 'guest_refresh_vault_write_failed',
            errorCode: 'SECURE_STORE_UNAVAILABLE');
        throw const GuestAuthException('SECURE_STORE_UNAVAILABLE');
      }
      if (generation != _credentialGeneration) {
        // Newer commit owns the vault; discard this response without inventing
        // a compensating write (serialized queue prevents mid-write races).
        _breadcrumb(LogCode.authRefreshFailed, 'guest_refresh_stale_after_write',
            errorCode: 'STALE_CREDENTIAL_RESPONSE');
        throw const GuestAuthException('STALE_CREDENTIAL_RESPONSE');
      }
      if (clearRotation) {
        await credentials.clearPendingRotationId();
        _breadcrumb(
            LogCode.authRefreshSucceeded, 'guest_rotation_intent_cleared');
      }
      _breadcrumb(
          LogCode.authRefreshSucceeded, 'guest_refresh_vault_write_completed');
      return _current = access;
    }

    if (vaultLocked) return body();
    return _serializedMutation(body);
  }

  Future<_GuestResponse> _post(String path, Map<String, Object?> body) async {
    final client = _factory();
    final requestId = _newRequestId();
    final operation =
        path == '/v1/auth/refresh' ? 'guest_auth_refresh' : 'guest_auth_create';
    _breadcrumb(LogCode.httpStarted, operation, requestId: requestId);
    client.connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .postUrl(Uri.parse(origin).resolve(path))
          .timeout(const Duration(seconds: 8));
      request.headers.contentType = ContentType.json;
      request.headers.set('x-request-id', requestId);
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      final payload = utf8.encode(jsonEncode(body));
      request.contentLength = payload.length;
      request.add(payload);
      final response =
          await request.close().timeout(const Duration(seconds: 12));
      final bytes = await response
          .fold<List<int>>(<int>[], (a, b) => a..addAll(b))
          .timeout(const Duration(seconds: 12));
      if (bytes.length > 16384) {
        throw const GuestAuthException('INVALID_AUTH_RESPONSE');
      }
      final parsed = jsonDecode(utf8.decode(bytes));
      if (parsed is! Map<String, dynamic>) {
        throw const GuestAuthException('INVALID_AUTH_RESPONSE');
      }
      _breadcrumb(LogCode.httpCompleted, operation,
          requestId: requestId,
          httpStatus: response.statusCode,
          errorCode: response.statusCode >= 400 ? 'AUTH_HTTP_REJECTED' : null);
      return _GuestResponse(response.statusCode, parsed);
    } on GuestAuthException {
      _breadcrumb(LogCode.httpFailed, operation,
          requestId: requestId, errorCode: 'AUTH_INVALID_RESPONSE');
      rethrow;
    } catch (_) {
      _breadcrumb(LogCode.httpFailed, operation,
          requestId: requestId, errorCode: 'AUTH_NETWORK_UNAVAILABLE');
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
