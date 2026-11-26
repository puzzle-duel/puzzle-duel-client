import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:puzzle_duel_mobile/diagnostics/diagnostic_runtime.dart';
import 'package:puzzle_duel_mobile/diagnostics/puzzle_duel_logger.dart';
import 'package:puzzle_duel_mobile/tournament/provider_sign_in.dart';

/// Backend PZD-26 provider HTTP surface. Never invents tokens or bypasses
/// challenge/nonce verification.
final class ProviderChallenge {
  const ProviderChallenge({
    required this.provider,
    required this.purpose,
    required this.nonce,
    this.binding,
  });

  final AuthProviderKind provider;
  final ProviderAuthPurpose purpose;
  final String nonce;
  /// Present for login challenges; link challenges bind server-side via fid.
  final String? binding;
}

enum ProviderAuthPurpose { login, link, continueWith }

final class ProviderCredentialBundle {
  const ProviderCredentialBundle({
    required this.playerId,
    required this.accountType,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.linkedProviders,
    this.resolution,
  });

  final String playerId;
  final String accountType;
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final List<String> linkedProviders;
  /// Backend continue resolution: link_guest, existing_account, etc.
  final String? resolution;
}

final class ProviderAuthException implements Exception {
  const ProviderAuthException(
    this.code, {
    this.httpStatus,
    this.continuationToken,
    this.expiresAt,
    this.targetPlayerId,
  });
  final String code;
  final int? httpStatus;
  final String? continuationToken;
  final DateTime? expiresAt;
  final String? targetPlayerId;
  @override
  String toString() => code;
}

abstract interface class ProviderAuthPort {
  Future<ProviderChallenge> challenge({
    required AuthProviderKind provider,
    required ProviderAuthPurpose purpose,
    String? guestBearer,
  });

  Future<ProviderCredentialBundle> login({
    required AuthProviderKind provider,
    required String idToken,
    required String nonce,
    required String binding,
  });

  Future<ProviderCredentialBundle> link({
    required AuthProviderKind provider,
    required String idToken,
    required String nonce,
    required String guestBearer,
  });

  /// Server-side identity-preserving recovery. Never uses generic login create.
  Future<ProviderCredentialBundle> recover({
    required AuthProviderKind provider,
    required String idToken,
    required String nonce,
    required String binding,
    required String expectedPlayerId,
  });

  /// Create-forbidden recovery resolving the linked player from provider evidence.
  /// Used for unified continue lost-response; never filters by source guest id.
  Future<ProviderCredentialBundle> recoverLinked({
    required AuthProviderKind provider,
    required String idToken,
    required String nonce,
    required String binding,
  });

  Future<ProviderCredentialBundle> continueWithProvider({
    required AuthProviderKind provider,
    required String idToken,
    required String nonce,
    required String binding,
    bool localProgressProtected = false,
    String? guestBearer,
  });

  Future<ProviderCredentialBundle> confirmContinue({
    required String continuationToken,
  });

  Future<void> logout({
    required String refreshToken,
    String? accessBearer,
  });
}

final class ProviderAuthClient implements ProviderAuthPort {
  ProviderAuthClient({
    required this.origin,
    HttpClient Function()? httpClientFactory,
    PuzzleDuelLogger? logger,
  })  : _factory = httpClientFactory ?? HttpClient.new,
        _logger = logger ?? DiagnosticRuntime.logger {
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
  final HttpClient Function() _factory;
  final PuzzleDuelLogger _logger;

  static String _purposeWire(ProviderAuthPurpose purpose) {
    return purpose == ProviderAuthPurpose.continueWith ? 'continue' : purpose.name;
  }

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

  @override
  Future<ProviderChallenge> challenge({
    required AuthProviderKind provider,
    required ProviderAuthPurpose purpose,
    String? guestBearer,
  }) async {
    if (purpose == ProviderAuthPurpose.link &&
        (guestBearer == null || guestBearer.isEmpty)) {
      throw const ProviderAuthException('GUEST_PROOF_REQUIRED');
    }
    final body = <String, Object?>{
      'provider': provider.name,
      'purpose': _purposeWire(purpose),
    };
    final guestProof = purpose == ProviderAuthPurpose.link ||
        purpose == ProviderAuthPurpose.continueWith;
    final result = await _post(
      '/v1/auth/providers/challenge',
      body,
      operation: 'provider_challenge_requested',
      bearer: guestProof && guestBearer != null && guestBearer.isNotEmpty
          ? guestBearer
          : null,
    );
    if (result.status != 201) {
      throw ProviderAuthException(
        _safeError(result.body) ?? 'AUTH_UNAVAILABLE',
        httpStatus: result.status,
      );
    }
    final nonce = result.body['nonce'];
    if (nonce is! String || nonce.isEmpty) {
      throw const ProviderAuthException('INVALID_PROVIDER_CHALLENGE');
    }
    final binding = result.body['binding'];
    if (purpose == ProviderAuthPurpose.login ||
        purpose == ProviderAuthPurpose.continueWith) {
      if (binding is! String || binding.isEmpty) {
        throw const ProviderAuthException('INVALID_PROVIDER_CHALLENGE');
      }
    }
    _breadcrumb(LogCode.httpCompleted, 'provider_challenge_completed',
        requestId: result.requestId, httpStatus: result.status);
    return ProviderChallenge(
      provider: provider,
      purpose: purpose,
      nonce: nonce,
      binding: binding is String ? binding : null,
    );
  }

  @override
  Future<ProviderCredentialBundle> login({
    required AuthProviderKind provider,
    required String idToken,
    required String nonce,
    required String binding,
  }) async {
    final result = await _post(
      '/v1/auth/providers/login',
      {
        'provider': provider.name,
        'idToken': idToken,
        'nonce': nonce,
        'binding': binding,
      },
      operation: 'provider_login_requested',
    );
    if (result.status != 201) {
      throw ProviderAuthException(
        _safeError(result.body) ?? 'AUTH_UNAVAILABLE',
        httpStatus: result.status,
      );
    }
    _breadcrumb(LogCode.httpCompleted, 'provider_login_completed',
        requestId: result.requestId, httpStatus: result.status);
    return _parseBundle(result.body);
  }

  @override
  Future<ProviderCredentialBundle> link({
    required AuthProviderKind provider,
    required String idToken,
    required String nonce,
    required String guestBearer,
  }) async {
    final result = await _post(
      '/v1/auth/providers/link',
      {
        'provider': provider.name,
        'idToken': idToken,
        'nonce': nonce,
      },
      operation: 'provider_link_requested',
      bearer: guestBearer,
    );
    if (result.status != 201) {
      throw ProviderAuthException(
        _safeError(result.body) ?? 'AUTH_UNAVAILABLE',
        httpStatus: result.status,
      );
    }
    _breadcrumb(LogCode.httpCompleted, 'provider_link_completed',
        requestId: result.requestId, httpStatus: result.status);
    return _parseBundle(result.body);
  }

  @override
  Future<ProviderCredentialBundle> recover({
    required AuthProviderKind provider,
    required String idToken,
    required String nonce,
    required String binding,
    required String expectedPlayerId,
  }) async {
    if (expectedPlayerId.length != 36) {
      throw const ProviderAuthException('INVALID_REQUEST');
    }
    final result = await _post(
      '/v1/auth/providers/recover',
      {
        'provider': provider.name,
        'idToken': idToken,
        'nonce': nonce,
        'binding': binding,
        'expectedPlayerId': expectedPlayerId,
      },
      operation: 'provider_recover_requested',
    );
    if (result.status != 201) {
      throw ProviderAuthException(
        _safeError(result.body) ?? 'AUTH_UNAVAILABLE',
        httpStatus: result.status,
      );
    }
    _breadcrumb(LogCode.httpCompleted, 'provider_recover_completed',
        requestId: result.requestId, httpStatus: result.status);
    return _parseBundle(result.body);
  }

  @override
  Future<ProviderCredentialBundle> recoverLinked({
    required AuthProviderKind provider,
    required String idToken,
    required String nonce,
    required String binding,
  }) async {
    final result = await _post(
      '/v1/auth/providers/recover',
      {
        'provider': provider.name,
        'idToken': idToken,
        'nonce': nonce,
        'binding': binding,
        'recoveryKind': 'provider_linked',
      },
      operation: 'provider_recover_linked_requested',
    );
    if (result.status != 201) {
      throw ProviderAuthException(
        _safeError(result.body) ?? 'AUTH_UNAVAILABLE',
        httpStatus: result.status,
      );
    }
    _breadcrumb(LogCode.httpCompleted, 'provider_recover_linked_completed',
        requestId: result.requestId, httpStatus: result.status);
    return _parseBundle(result.body);
  }

  @override
  Future<ProviderCredentialBundle> continueWithProvider({
    required AuthProviderKind provider,
    required String idToken,
    required String nonce,
    required String binding,
    bool localProgressProtected = false,
    String? guestBearer,
  }) async {
    final body = <String, Object?>{
      'provider': provider.name,
      'idToken': idToken,
      'nonce': nonce,
      'binding': binding,
    };
    if (localProgressProtected) {
      body['localProgressProtected'] = true;
    }
    final result = await _post(
      '/v1/auth/providers/continue',
      body,
      operation: 'provider_continue_requested',
      bearer: guestBearer,
    );
    if (result.status == 409) {
      final code = result.body['error']?.toString();
      if (code == 'ACCOUNT_SWITCH_CONFIRMATION_REQUIRED') {
        final token = result.body['continuationToken'];
        final expires = result.body['expiresAt'];
        DateTime? expiresAt;
        if (expires is String) {
          expiresAt = DateTime.tryParse(expires)?.toUtc();
        }
        final target = result.body['targetPlayerId'];
        throw ProviderAuthException(
          'ACCOUNT_SWITCH_CONFIRMATION_REQUIRED',
          httpStatus: 409,
          continuationToken: token is String ? token : null,
          expiresAt: expiresAt,
          targetPlayerId: target is String ? target : null,
        );
      }
    }
    if (result.status != 201) {
      throw ProviderAuthException(
        _safeError(result.body) ?? 'AUTH_UNAVAILABLE',
        httpStatus: result.status,
      );
    }
    _breadcrumb(LogCode.httpCompleted, 'provider_continue_completed',
        requestId: result.requestId, httpStatus: result.status);
    return _parseBundle(result.body);
  }

  @override
  Future<ProviderCredentialBundle> confirmContinue({
    required String continuationToken,
  }) async {
    if (continuationToken.isEmpty) {
      throw const ProviderAuthException('INVALID_REQUEST');
    }
    final result = await _post(
      '/v1/auth/providers/continue/confirm',
      {'continuationToken': continuationToken},
      operation: 'provider_continue_confirm_requested',
    );
    if (result.status != 201) {
      throw ProviderAuthException(
        _safeError(result.body) ?? 'AUTH_UNAVAILABLE',
        httpStatus: result.status,
      );
    }
    _breadcrumb(LogCode.httpCompleted, 'provider_continue_confirm_completed',
        requestId: result.requestId, httpStatus: result.status);
    return _parseBundle(result.body);
  }

  @override
  Future<void> logout({
    required String refreshToken,
    String? accessBearer,
  }) async {
    final result = await _post(
      '/v1/auth/logout',
      {'refreshToken': refreshToken},
      operation: 'auth_logout',
      bearer: accessBearer,
    );
    if (result.status != 200 && result.status != 204) {
      throw ProviderAuthException(
        _safeError(result.body) ?? 'AUTH_UNAVAILABLE',
        httpStatus: result.status,
      );
    }
  }

  ProviderCredentialBundle _parseBundle(Map<String, dynamic> data) {
    final playerId = data['playerId'];
    final accountType = data['accountType'];
    final access = data['accessToken'];
    final refresh = data['refreshToken'];
    final expiry = data['expiresAt'];
    final linked = data['linkedProviders'];
    if (playerId is! String ||
        playerId.length != 36 ||
        accountType != 'verified' ||
        access is! String ||
        access.isEmpty ||
        refresh is! String ||
        refresh.isEmpty ||
        expiry is! String) {
      throw const ProviderAuthException('INVALID_AUTH_RESPONSE');
    }
    final expiresAt = DateTime.tryParse(expiry)?.toUtc();
    if (expiresAt == null || !expiresAt.isAfter(DateTime.now().toUtc())) {
      throw const ProviderAuthException('INVALID_AUTH_RESPONSE');
    }
    final providers = <String>[];
    if (linked is List) {
      for (final item in linked) {
        if (item == 'apple' || item == 'google') providers.add(item);
      }
    }
    final resolution = data['resolution'];
    return ProviderCredentialBundle(
      playerId: playerId,
      accountType: accountType,
      accessToken: access,
      refreshToken: refresh,
      expiresAt: expiresAt,
      linkedProviders: providers,
      resolution: resolution is String ? resolution : null,
    );
  }

  static String? _safeError(Map<String, dynamic> body) {
    final code = body['error']?.toString();
    const allowed = {
      'INVALID_PROVIDER_ASSERTION',
      'INVALID_PROVIDER_CHALLENGE',
      'ACCOUNT_CONFLICT',
      'ACCOUNT_SWITCH_CONFIRMATION_REQUIRED',
      'INVALID_CONTINUATION',
      'GUEST_PROOF_REQUIRED',
      'RANKED_AUTH_REQUIRED',
      'AUTH_UNAVAILABLE',
      // Backend emits PROVIDER_CONFIG_MISSING only as a diagnostic reason;
      // the JSON body remains AUTH_UNAVAILABLE (503).
      'PROVIDER_CONFIG_MISSING',
      'INVALID_REFRESH',
      'INVALID_REQUEST',
      'RATE_LIMITED',
      'HTTPS_REQUIRED',
      'RECOVERY_NOT_LINKED',
      'AUTH_NETWORK_UNAVAILABLE',
    };
    if (code != null && allowed.contains(code)) return code;
    return null;
  }

  Future<_ProviderHttpResult> _post(
    String path,
    Map<String, Object?> body, {
    required String operation,
    String? bearer,
  }) async {
    final client = _factory();
    final requestId = _newRequestId();
    _breadcrumb(LogCode.httpStarted, operation, requestId: requestId);
    client.connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .postUrl(Uri.parse(origin).resolve(path))
          .timeout(const Duration(seconds: 8));
      request.headers.contentType = ContentType.json;
      request.headers.set('x-request-id', requestId);
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      if (bearer != null && bearer.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
      }
      final payload = utf8.encode(jsonEncode(body));
      if (payload.length > 8192) {
        throw const ProviderAuthException('INVALID_REQUEST');
      }
      request.contentLength = payload.length;
      request.add(payload);
      final response =
          await request.close().timeout(const Duration(seconds: 12));
      final bytes = await response
          .fold<List<int>>(<int>[], (a, b) => a..addAll(b))
          .timeout(const Duration(seconds: 12));
      if (bytes.length > 16384) {
        throw const ProviderAuthException('INVALID_AUTH_RESPONSE');
      }
      final parsed = bytes.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(utf8.decode(bytes));
      if (parsed is! Map<String, dynamic>) {
        throw const ProviderAuthException('INVALID_AUTH_RESPONSE');
      }
      final error = response.statusCode >= 400 ? _safeError(parsed) : null;
      _breadcrumb(
        response.statusCode >= 400 ? LogCode.httpFailed : LogCode.httpCompleted,
        operation,
        requestId: requestId,
        httpStatus: response.statusCode,
        errorCode: error,
      );
      return _ProviderHttpResult(response.statusCode, parsed, requestId);
    } on ProviderAuthException {
      _breadcrumb(LogCode.httpFailed, operation,
          requestId: requestId, errorCode: 'AUTH_INVALID_RESPONSE');
      rethrow;
    } catch (_) {
      _breadcrumb(LogCode.httpFailed, operation,
          requestId: requestId, errorCode: 'AUTH_NETWORK_UNAVAILABLE');
      throw const ProviderAuthException('AUTH_NETWORK_UNAVAILABLE');
    } finally {
      client.close(force: true);
    }
  }
}

final class _ProviderHttpResult {
  const _ProviderHttpResult(this.status, this.body, this.requestId);
  final int status;
  final Map<String, dynamic> body;
  final String requestId;
}
