import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:puzzle_duel_mobile/diagnostics/diagnostic_runtime.dart';
import 'package:puzzle_duel_mobile/diagnostics/puzzle_duel_logger.dart';
import 'package:puzzle_duel_mobile/tournament/guest_session_recovery.dart';

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
  /// Durable pending-link recovery marker. Encoded as `provider|playerId`
  /// (see [PendingLinkRecovery]). Never stores tokens or nonces.
  Future<String?> readPendingLinkProvider();
  Future<void> writePendingLinkProvider(String encoded);
  Future<void> clearPendingLinkProvider();
  /// Non-secret last-known player/family binding for recovery UX only.
  Future<String?> readIdentityBinding();
  Future<void> writeIdentityBinding(String encoded);
  Future<void> clearIdentityBinding();
  /// Write-ahead vault journal (secure storage only). Never log contents.
  Future<String?> readVaultJournal();
  Future<void> writeVaultJournal(String encoded);
  Future<void> clearVaultJournal();
}

/// Pending-link field action encoded in [GuestVaultJournal].
enum GuestVaultPendingLinkAction { keep, clear, set }

/// Durable write-ahead intent for multi-key vault commits.
///
/// Crash between live-key writes leaves this journal intact; startup
/// [GuestAuthClient.reconcilePersistedVault] completes the intent before any
/// refresh/create consumes credentials. Contents stay in secure storage only.
final class GuestVaultJournal {
  const GuestVaultJournal({
    required this.nextRefresh,
    required this.nextBinding,
    this.clearRotation = true,
    this.nextRotation,
    this.pendingLinkAction = GuestVaultPendingLinkAction.keep,
    this.nextPendingLink,
  });

  final String nextRefresh;
  final String nextBinding;
  final bool clearRotation;
  final String? nextRotation;
  final GuestVaultPendingLinkAction pendingLinkAction;
  final String? nextPendingLink;

  String encode() {
    final payload = <String, Object?>{
      'v': 1,
      'nr': nextRefresh,
      'nb': nextBinding,
      'cr': clearRotation,
      'nrn': nextRotation,
      'pla': switch (pendingLinkAction) {
        GuestVaultPendingLinkAction.keep => 'keep',
        GuestVaultPendingLinkAction.clear => 'clear',
        GuestVaultPendingLinkAction.set => 'set',
      },
      'npl': nextPendingLink,
    };
    return 'v1:${base64Url.encode(utf8.encode(jsonEncode(payload)))}';
  }

  static GuestVaultJournal? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (!raw.startsWith('v1:')) return null;
    try {
      final decoded = utf8.decode(base64Url.decode(raw.substring(3)));
      final map = jsonDecode(decoded);
      if (map is! Map) return null;
      final nextRefresh = map['nr'];
      final nextBinding = map['nb'];
      if (nextRefresh is! String ||
          nextRefresh.isEmpty ||
          nextBinding is! String ||
          nextBinding.isEmpty) {
        return null;
      }
      final pla = map['pla'];
      final GuestVaultPendingLinkAction action;
      if (pla == 'clear') {
        action = GuestVaultPendingLinkAction.clear;
      } else if (pla == 'set') {
        action = GuestVaultPendingLinkAction.set;
      } else if (pla == 'keep' || pla == null) {
        action = GuestVaultPendingLinkAction.keep;
      } else {
        return null;
      }
      final nextPending = map['npl'];
      if (action == GuestVaultPendingLinkAction.set &&
          (nextPending is! String || nextPending.isEmpty)) {
        return null;
      }
      final nextRotation = map['nrn'];
      if (nextRotation != null && nextRotation is! String) return null;
      return GuestVaultJournal(
        nextRefresh: nextRefresh,
        nextBinding: nextBinding,
        clearRotation: map['cr'] == true,
        nextRotation: nextRotation as String?,
        pendingLinkAction: action,
        nextPendingLink:
            nextPending is String && nextPending.isNotEmpty ? nextPending : null,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Durable recovery intent kinds stored in the pending-link secure slot.
enum PendingAuthRecoveryKind {
  /// Classic guest→verified link; [playerId] is the expected preserved guest id.
  link,

  /// Unified continue mutating request in flight; resolve via provider_linked.
  /// [playerId] is optional source guest context only — never the switch target.
  unifiedContinue,

  /// Server asked for account-switch consent; user has not approved yet.
  /// Recovery must retain the guest — never recoverLinked to [playerId] target.
  unifiedAwaitingSwitch,

  /// User explicitly approved switch; mutating confirm may be in flight.
  /// [playerId] is the server-issued target player (opaque hint, not proof).
  unifiedConfirm,
}

/// Identity-preserving recovery intent after uncertain auth mutation.
///
/// Wire formats (secure storage only; never log):
/// - `apple|<uuid>` / `google|<uuid>` — legacy/exact link expected player
/// - `continue|apple` / `continue|google` — unified continue (provider_linked)
/// - `continue|apple|<sourceGuestUuid>` — unified continue with source context
/// - `awaiting|apple|<targetPlayerUuid>` — confirmation required, not yet approved
/// - `confirm|apple|<targetPlayerUuid>` — user-approved confirm mutate intent
final class PendingLinkRecovery {
  const PendingLinkRecovery({
    required this.provider,
    required this.playerId,
    this.kind = PendingAuthRecoveryKind.link,
  });

  final String provider;
  /// Link: expected guest id. Unified continue: optional source guest.
  /// Awaiting/confirm: server-advertised target player id.
  final String playerId;
  final PendingAuthRecoveryKind kind;

  bool get resolvesViaProviderLinked =>
      kind == PendingAuthRecoveryKind.unifiedContinue;

  bool get isAwaitingSwitchConsent =>
      kind == PendingAuthRecoveryKind.unifiedAwaitingSwitch;

  String encode() => switch (kind) {
        PendingAuthRecoveryKind.link => '$provider|$playerId',
        PendingAuthRecoveryKind.unifiedContinue => playerId.isEmpty
            ? 'continue|$provider'
            : 'continue|$provider|$playerId',
        PendingAuthRecoveryKind.unifiedAwaitingSwitch =>
          'awaiting|$provider|$playerId',
        PendingAuthRecoveryKind.unifiedConfirm => 'confirm|$provider|$playerId',
      };

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static PendingLinkRecovery? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split('|');
    if (parts.length == 2 &&
        parts[0] != 'continue' &&
        parts[0] != 'confirm' &&
        parts[0] != 'awaiting') {
      final provider = parts[0];
      final playerId = parts[1];
      if (provider != 'apple' && provider != 'google') return null;
      if (!_uuid.hasMatch(playerId)) return null;
      return PendingLinkRecovery(provider: provider, playerId: playerId);
    }
    if (parts.length >= 2 && parts[0] == 'continue') {
      final provider = parts[1];
      if (provider != 'apple' && provider != 'google') return null;
      if (parts.length == 2) {
        return PendingLinkRecovery(
          provider: provider,
          playerId: '',
          kind: PendingAuthRecoveryKind.unifiedContinue,
        );
      }
      if (parts.length == 3 && _uuid.hasMatch(parts[2])) {
        return PendingLinkRecovery(
          provider: provider,
          playerId: parts[2],
          kind: PendingAuthRecoveryKind.unifiedContinue,
        );
      }
      return null;
    }
    if (parts.length == 3 && parts[0] == 'awaiting') {
      final provider = parts[1];
      final playerId = parts[2];
      if (provider != 'apple' && provider != 'google') return null;
      if (!_uuid.hasMatch(playerId)) return null;
      return PendingLinkRecovery(
        provider: provider,
        playerId: playerId,
        kind: PendingAuthRecoveryKind.unifiedAwaitingSwitch,
      );
    }
    if (parts.length == 3 && parts[0] == 'confirm') {
      final provider = parts[1];
      final playerId = parts[2];
      if (provider != 'apple' && provider != 'google') return null;
      if (!_uuid.hasMatch(playerId)) return null;
      return PendingLinkRecovery(
        provider: provider,
        playerId: playerId,
        kind: PendingAuthRecoveryKind.unifiedConfirm,
      );
    }
    return null;
  }

  /// Legacy provider-only markers still block silent guest creation.
  static String? legacyProviderOnly(String? raw) {
    if (raw == 'apple' || raw == 'google') return raw;
    return null;
  }
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

  /// Mirrors compile-time `PZD_GUEST_RETRY_ENABLED` (default false). Must stay
  /// false unless Oracle `PZD_STAGING_GUEST_RETRY_ENABLED=true` is confirmed.
  bool get rotationRetryEnabled => _rotationRetryEnabled;

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
  String? _lastAuthRequestId;
  var _vaultReconciled = false;
  var _vaultCorrupt = false;

  /// Serializes durable vault mutations so stale refresh cannot interleave with
  /// link/logout commits. Nested vault work inside a held mutation must call
  /// the `*Unlocked` helpers — never re-enter `_serializedMutation` via a
  /// boolean flag (external callers during an await would race).
  Future<void> _mutationChain = Future<void>.value();

  /// Null while vault is unsafe or reconcile is outstanding — never bypass.
  GuestAccess? get cachedAccess =>
      (_vaultCorrupt || !_vaultReconciled) ? null : _current;
  int get credentialGeneration => _credentialGeneration;
  /// Last guest-auth HTTP `x-request-id` (32 hex). Never a token or player proof.
  String? get lastAuthRequestId => _lastAuthRequestId;
  /// True after a failed journal reconcile; ranked/auth stay fail-closed.
  bool get vaultCorrupt => _vaultCorrupt;

  @visibleForTesting
  void debugSeedAccess(GuestAccess access) {
    _current = access;
    _vaultReconciled = true;
    _vaultCorrupt = false;
  }

  void _invalidateVaultSession({required bool unsafe}) {
    _vaultReconciled = false;
    _current = null;
    _pending = null;
    if (unsafe) {
      _vaultCorrupt = true;
    }
  }

  /// Test-only auth HTTP transport. Production always uses HTTPS [HttpClient].
  @visibleForTesting
  Future<({int status, Map<String, dynamic> body})> Function(
    String path,
    Map<String, Object?> body,
  )? debugTransport;

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
  ///
  /// [forceRefresh] skips the local JWT cache and requires a server-backed
  /// refresh (or guest create when [allowGuestCreate] is true). Cached JWT
  /// expiry alone is never proof that a backend family is still active.
  ///
  /// [allowGuestCreate] must be false for recovery probes so an uncertain
  /// pending-link state cannot mint a replacement guest player.
  Future<GuestAccess> authenticate({
    bool forceRefresh = false,
    bool allowGuestCreate = true,
  }) async {
    await reconcilePersistedVault();
    if (_vaultCorrupt) {
      throw const GuestAuthException('SECURE_STORE_RECOVERY_FAILED');
    }
    final cached = _current;
    if (!forceRefresh &&
        cached != null &&
        cached.expiresAt
            .isAfter(DateTime.now().toUtc().add(const Duration(minutes: 1)))) {
      return cached;
    }
    final pending = _pending;
    if (pending != null && _pendingGeneration == _credentialGeneration) {
      return pending;
    }
    final generation = _credentialGeneration;
    final next = _authenticate(
      generation: generation,
      forceNetworkRefresh: forceRefresh,
      allowGuestCreate: allowGuestCreate,
    );
    _pending = next;
    _pendingGeneration = generation;
    return next.whenComplete(() {
      if (identical(_pending, next)) {
        _pending = null;
      }
    });
  }

  /// Completes or clears a crash-torn vault journal before auth consumes keys.
  /// Idempotent per client instance. Fail-closed on corrupt journal/apply.
  Future<void> reconcilePersistedVault() {
    if (_vaultReconciled && !_vaultCorrupt) {
      return Future<void>.value();
    }
    return _serializedMutation(() async {
      if (_vaultReconciled && !_vaultCorrupt) return;
      try {
        final pending = await credentials.readVaultJournal();
        await _applyVaultJournalUnlocked();
        _vaultReconciled = true;
        _vaultCorrupt = false;
        if (pending != null && pending.isNotEmpty) {
          _breadcrumb(LogCode.sessionRestored, 'guest_vault_reconciled');
        }
      } on GuestAuthException catch (error) {
        _invalidateVaultSession(unsafe: true);
        _breadcrumb(LogCode.sessionRestoreFailed, 'guest_vault_reconcile_failed',
            errorCode: error.code);
        throw const GuestAuthException('SECURE_STORE_RECOVERY_FAILED');
      } catch (_) {
        _invalidateVaultSession(unsafe: true);
        _breadcrumb(LogCode.sessionRestoreFailed, 'guest_vault_reconcile_failed',
            errorCode: 'SECURE_STORE_RECOVERY_FAILED');
        throw const GuestAuthException('SECURE_STORE_RECOVERY_FAILED');
      }
    });
  }

  /// Refreshes the guest access token while requiring the same player and
  /// family (fid). Used after native provider UI may outlive access TTL.
  ///
  /// Network ownership is unified through [authenticate] single-flight so an
  /// ordinary refresh already in flight cannot be duplicated under the vault
  /// mutation lock (replay / family revocation / rotation races).
  Future<GuestAccess> refreshGuestPreservingIdentity({
    required String playerId,
    required String? familyId,
  }) async {
    final access = await authenticate(forceRefresh: true);
    if (access.playerId != playerId || access.familyId != familyId) {
      throw const GuestAuthException('GUEST_IDENTITY_CHANGED');
    }
    if (!access.isGuest) {
      throw const GuestAuthException('INVALID_AUTH_RESPONSE');
    }
    return access;
  }

  Future<GuestAccess> replaceWithVerifiedBundle({
    required String accessToken,
    required String refreshToken,
    required DateTime expiresAt,
  }) async {
    await reconcilePersistedVault();
    if (_vaultCorrupt) {
      throw const GuestAuthException('SECURE_STORE_RECOVERY_FAILED');
    }
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
      final oldToken = await credentials.readRefreshToken();
      final oldBindingRaw = await credentials.readIdentityBinding();
      final oldRotation = await credentials.readPendingRotationId();
      final oldPendingLink = await credentials.readPendingLinkProvider();
      final binding = GuestIdentityBinding(
        playerId: access.playerId,
        familyId: access.familyId,
        accountType: AccountType.verified,
      ).encode();
      try {
        await _commitVaultJournalled(
          GuestVaultJournal(
            nextRefresh: refreshToken,
            nextBinding: binding,
            clearRotation: true,
            pendingLinkAction: GuestVaultPendingLinkAction.clear,
          ),
        );
      } catch (error) {
        _breadcrumb(LogCode.authRefreshFailed, 'auth_credential_replace_failed',
            errorCode: error is GuestAuthException
                ? error.code
                : 'SECURE_STORE_RECOVERY_FAILED');
        await _rollbackVaultOrMarkUnsafe(
          token: oldToken,
          binding: oldBindingRaw,
          rotation: oldRotation,
          pendingLink: oldPendingLink,
        );
      }
      if (generation != _credentialGeneration) {
        _breadcrumb(LogCode.authRefreshFailed, 'auth_credential_replace_stale',
            errorCode: 'STALE_CREDENTIAL_RESPONSE');
        throw const GuestAuthException('STALE_CREDENTIAL_RESPONSE');
      }
      _breadcrumb(LogCode.authRefreshSucceeded, 'auth_credential_replaced');
      return _current = access;
    });
  }

  /// Owner-approved UX: mint a **new** guest after explicit confirmation.
  ///
  /// Never silent: pending provider link and verified bindings refuse.
  /// Create-on-server first; vault commit is ordered token→binding→rotation
  /// clear with readback. Any step failure restores the prior snapshot (or
  /// surfaces [SECURE_STORE_RECOVERY_FAILED] if restore itself fails).
  Future<GuestAccess> replaceWithExplicitNewGuest() async {
    await reconcilePersistedVault();
    if (_vaultCorrupt) {
      throw const GuestAuthException('SECURE_STORE_RECOVERY_FAILED');
    }
    return _serializedMutation(() async {
      final pendingCode = await _pendingLinkRecoveryCode();
      if (pendingCode != null) {
        _breadcrumb(LogCode.authRefreshFailed, 'guest_explicit_new_blocked',
            errorCode: 'PROVIDER_LINK_RECOVERY');
        throw GuestAuthException(pendingCode);
      }
      final priorBinding = GuestIdentityBinding.tryParse(
        await credentials.readIdentityBinding(),
      );
      if (priorBinding?.accountType == AccountType.verified) {
        _breadcrumb(LogCode.authRefreshFailed, 'guest_explicit_new_blocked',
            errorCode: 'RECOVERY_NOT_LINKED');
        throw const GuestAuthException('RECOVERY_NOT_LINKED');
      }

      final oldToken = await credentials.readRefreshToken();
      final oldBindingRaw = await credentials.readIdentityBinding();
      final oldRotation = await credentials.readPendingRotationId();
      final oldPendingLink = await credentials.readPendingLinkProvider();

      final generation = ++_credentialGeneration;
      _pending = null;
      _breadcrumb(LogCode.authRefreshSucceeded, 'guest_explicit_new_started');

      final result = await _post('/v1/auth/guest', const {});
      if (result.status != 201 && result.status != 200) {
        _breadcrumb(LogCode.authRefreshFailed, 'guest_explicit_new_create_failed',
            httpStatus: result.status, errorCode: 'GUEST_CREATION_UNAVAILABLE');
        throw const GuestAuthException('GUEST_CREATION_UNAVAILABLE');
      }
      if (generation != _credentialGeneration) {
        _breadcrumb(LogCode.authRefreshFailed, 'guest_explicit_new_stale',
            errorCode: 'STALE_CREDENTIAL_RESPONSE');
        throw const GuestAuthException('STALE_CREDENTIAL_RESPONSE');
      }

      final accessToken = result.body['accessToken'];
      final refresh = result.body['refreshToken'];
      final expiry = result.body['expiresAt'];
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
      if (!access.isGuest) {
        throw const GuestAuthException('INVALID_AUTH_RESPONSE');
      }

      final binding = GuestIdentityBinding(
        playerId: access.playerId,
        familyId: access.familyId,
        accountType: access.accountType,
      ).encode();
      try {
        await _commitVaultJournalled(
          GuestVaultJournal(
            nextRefresh: refresh,
            nextBinding: binding,
            clearRotation: true,
            pendingLinkAction: GuestVaultPendingLinkAction.keep,
          ),
        );
      } catch (error) {
        _breadcrumb(LogCode.authRefreshFailed, 'guest_explicit_new_vault_failed',
            errorCode: error is GuestAuthException
                ? error.code
                : 'SECURE_STORE_RECOVERY_FAILED');
        await _rollbackVaultOrMarkUnsafe(
          token: oldToken,
          binding: oldBindingRaw,
          rotation: oldRotation,
          pendingLink: oldPendingLink,
        );
      }
      if (generation != _credentialGeneration) {
        _breadcrumb(LogCode.authRefreshFailed, 'guest_explicit_new_stale',
            errorCode: 'STALE_CREDENTIAL_RESPONSE');
        throw const GuestAuthException('STALE_CREDENTIAL_RESPONSE');
      }
      _breadcrumb(LogCode.authRefreshSucceeded, 'guest_explicit_new_replaced');
      return _current = access;
    });
  }

  /// Write-ahead journal → apply live keys → clear journal.
  /// Callers hold `_serializedMutation`. Crash mid-apply leaves journal for
  /// [reconcilePersistedVault]; try/catch alone is not the durability claim.
  Future<void> _commitVaultJournalled(GuestVaultJournal journal) async {
    final encoded = journal.encode();
    await credentials.writeVaultJournal(encoded);
    if (await credentials.readVaultJournal() != encoded) {
      throw const GuestAuthException('SECURE_STORE_VERIFY_FAILED');
    }
    await _applyVaultJournalUnlocked();
  }

  /// Applies a durable journal to live keys, then clears it. Idempotent when
  /// live keys already match. Callers hold `_serializedMutation`.
  Future<void> _applyVaultJournalUnlocked() async {
    final raw = await credentials.readVaultJournal();
    if (raw == null || raw.isEmpty) return;
    final journal = GuestVaultJournal.tryParse(raw);
    if (journal == null) {
      throw const GuestAuthException('SECURE_STORE_RECOVERY_FAILED');
    }
    await persistVerifiedGuestCredential(credentials, journal.nextRefresh);
    await credentials.writeIdentityBinding(journal.nextBinding);
    if (await credentials.readIdentityBinding() != journal.nextBinding) {
      throw const GuestAuthException('SECURE_STORE_VERIFY_FAILED');
    }
    if (journal.clearRotation) {
      await credentials.clearPendingRotationId();
      if (await credentials.readPendingRotationId() != null) {
        throw const GuestAuthException('SECURE_STORE_VERIFY_FAILED');
      }
    } else if (journal.nextRotation != null && journal.nextRotation!.isNotEmpty) {
      await credentials.writePendingRotationId(journal.nextRotation!);
      if (await credentials.readPendingRotationId() != journal.nextRotation) {
        throw const GuestAuthException('SECURE_STORE_VERIFY_FAILED');
      }
    }
    switch (journal.pendingLinkAction) {
      case GuestVaultPendingLinkAction.keep:
        break;
      case GuestVaultPendingLinkAction.clear:
        await credentials.clearPendingLinkProvider();
        if (await credentials.readPendingLinkProvider() != null) {
          throw const GuestAuthException('SECURE_STORE_VERIFY_FAILED');
        }
        break;
      case GuestVaultPendingLinkAction.set:
        final next = journal.nextPendingLink;
        if (next == null || next.isEmpty) {
          throw const GuestAuthException('SECURE_STORE_RECOVERY_FAILED');
        }
        await credentials.writePendingLinkProvider(next);
        if (await credentials.readPendingLinkProvider() != next) {
          throw const GuestAuthException('SECURE_STORE_VERIFY_FAILED');
        }
        break;
    }
    await credentials.clearVaultJournal();
    if (await credentials.readVaultJournal() != null) {
      throw const GuestAuthException('SECURE_STORE_VERIFY_FAILED');
    }
  }

  /// Restores a prior vault snapshot after a failed replacement. Skips writes
  /// that already match the snapshot (partial-commit / first-step failure).
  ///
  /// Clears the durable journal **only** after the restored live keys verify.
  /// Never clears the journal in a failure path — restart reconcile needs it.
  Future<void> _restoreVaultSnapshot({
    required String? token,
    required String? binding,
    required String? rotation,
    required String? pendingLink,
  }) async {
    try {
      if (token != null && token.isNotEmpty) {
        if (await credentials.readRefreshToken() != token) {
          await persistVerifiedGuestCredential(credentials, token);
        }
      }
      final currentBinding = await credentials.readIdentityBinding();
      if (binding != null && binding.isNotEmpty) {
        if (currentBinding != binding) {
          await credentials.writeIdentityBinding(binding);
          if (await credentials.readIdentityBinding() != binding) {
            throw const GuestAuthException('SECURE_STORE_RECOVERY_FAILED');
          }
        }
      } else if (currentBinding != null) {
        await credentials.clearIdentityBinding();
        if (await credentials.readIdentityBinding() != null) {
          throw const GuestAuthException('SECURE_STORE_RECOVERY_FAILED');
        }
      }
      final currentRotation = await credentials.readPendingRotationId();
      if (rotation != null && rotation.isNotEmpty) {
        if (currentRotation != rotation) {
          await credentials.writePendingRotationId(rotation);
          if (await credentials.readPendingRotationId() != rotation) {
            throw const GuestAuthException('SECURE_STORE_RECOVERY_FAILED');
          }
        }
      } else if (currentRotation != null) {
        await credentials.clearPendingRotationId();
        if (await credentials.readPendingRotationId() != null) {
          throw const GuestAuthException('SECURE_STORE_RECOVERY_FAILED');
        }
      }
      final currentPending = await credentials.readPendingLinkProvider();
      if (pendingLink != null && pendingLink.isNotEmpty) {
        if (currentPending != pendingLink) {
          await credentials.writePendingLinkProvider(pendingLink);
          if (await credentials.readPendingLinkProvider() != pendingLink) {
            throw const GuestAuthException('SECURE_STORE_RECOVERY_FAILED');
          }
        }
      } else if (currentPending != null) {
        await credentials.clearPendingLinkProvider();
        if (await credentials.readPendingLinkProvider() != null) {
          throw const GuestAuthException('SECURE_STORE_RECOVERY_FAILED');
        }
      }
      await credentials.clearVaultJournal();
      if (await credentials.readVaultJournal() != null) {
        throw const GuestAuthException('SECURE_STORE_RECOVERY_FAILED');
      }
    } on GuestAuthException {
      rethrow;
    } catch (_) {
      throw const GuestAuthException('SECURE_STORE_RECOVERY_FAILED');
    }
  }

  /// In-process rollback after a failed journalled commit. On rollback failure
  /// keeps the journal, marks the vault unsafe, and fails closed.
  Future<void> _rollbackVaultOrMarkUnsafe({
    required String? token,
    required String? binding,
    required String? rotation,
    required String? pendingLink,
  }) async {
    try {
      await _restoreVaultSnapshot(
        token: token,
        binding: binding,
        rotation: rotation,
        pendingLink: pendingLink,
      );
      _invalidateVaultSession(unsafe: false);
    } catch (_) {
      _invalidateVaultSession(unsafe: true);
      throw const GuestAuthException('SECURE_STORE_RECOVERY_FAILED');
    }
    throw const GuestAuthException('SECURE_STORE_RECOVERY_FAILED');
  }

  Future<void> markPendingLink({
    required String provider,
    required String playerId,
  }) {
    return _persistPendingRecovery(
      PendingLinkRecovery(provider: provider, playerId: playerId),
    );
  }

  /// Durable marker before the first mutating unified continue request.
  Future<void> markPendingUnifiedContinue({
    required String provider,
    String? sourcePlayerId,
  }) {
    return _persistPendingRecovery(
      PendingLinkRecovery(
        provider: provider,
        playerId: sourcePlayerId ?? '',
        kind: PendingAuthRecoveryKind.unifiedContinue,
      ),
    );
  }

  /// Durable marker while the UI awaits explicit account-switch consent.
  /// Must not be treated as an approved confirm intent.
  Future<void> markPendingUnifiedAwaitingSwitch({
    required String provider,
    required String targetPlayerId,
  }) {
    return _persistPendingRecovery(
      PendingLinkRecovery(
        provider: provider,
        playerId: targetPlayerId,
        kind: PendingAuthRecoveryKind.unifiedAwaitingSwitch,
      ),
    );
  }

  /// Durable marker after the user approves switch and before confirm HTTP.
  Future<void> markPendingUnifiedConfirm({
    required String provider,
    required String targetPlayerId,
  }) {
    return _persistPendingRecovery(
      PendingLinkRecovery(
        provider: provider,
        playerId: targetPlayerId,
        kind: PendingAuthRecoveryKind.unifiedConfirm,
      ),
    );
  }

  Future<void> _persistPendingRecovery(PendingLinkRecovery marker) {
    final encoded = marker.encode();
    if (PendingLinkRecovery.tryParse(encoded) == null) {
      throw const GuestAuthException('INVALID_AUTH_RESPONSE');
    }
    return _serializedMutation(() async {
      await credentials.writePendingLinkProvider(encoded);
      final confirmed = await credentials.readPendingLinkProvider();
      if (confirmed != encoded) {
        throw const GuestAuthException('SECURE_STORE_VERIFY_FAILED');
      }
      _breadcrumb(LogCode.authRefreshSucceeded, 'auth_pending_link_saved');
    });
  }

  Future<PendingLinkRecovery?> readPendingLinkRecovery() async {
    return PendingLinkRecovery.tryParse(
      await credentials.readPendingLinkProvider(),
    );
  }

  Future<void> clearPendingLinkProvider() => _serializedMutation(() async {
        await credentials.clearPendingLinkProvider();
      });

  Future<String?> _pendingLinkRecoveryCode() async {
    final raw = await credentials.readPendingLinkProvider();
    final parsed = PendingLinkRecovery.tryParse(raw);
    if (parsed != null) {
      // Uppercase provider so LogEvent errorCode allowlist accepts the code.
      return 'PROVIDER_LINK_RECOVERY_${parsed.provider.toUpperCase()}';
    }
    final legacy = PendingLinkRecovery.legacyProviderOnly(raw);
    if (legacy != null) {
      return 'PROVIDER_LINK_RECOVERY_${legacy.toUpperCase()}';
    }
    return null;
  }

  Future<void> clearSessionLocally() {
    return _serializedMutation(() async {
      _credentialGeneration++;
      _pending = null;
      _current = null;
      _vaultCorrupt = false;
      _vaultReconciled = true;
      await credentials.clearVaultJournal();
      await credentials.clearRefreshToken();
      await credentials.clearPendingRotationId();
      // Keep pending link marker so restart can recover via provider login.
      _breadcrumb(LogCode.authExpired, 'auth_logout_local_cleared');
    });
  }

  Future<GuestAccess> _authenticate({
    required int generation,
    bool forceNetworkRefresh = false,
    bool allowGuestCreate = true,
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
        rotationId = await _serializedMutation(() async {
          if (generation != _credentialGeneration) {
            throw const GuestAuthException('STALE_CREDENTIAL_RESPONSE');
          }
          return acquireVerifiedGuestRotationId(credentials, _newRequestId);
        });
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
        );
      }
      if (result.status != 401 && result.status != 403) {
        _breadcrumb(LogCode.authRefreshFailed, 'guest_refresh_unavailable',
            httpStatus: result.status, errorCode: 'REFRESH_UNAVAILABLE');
        throw const GuestAuthException('REFRESH_UNAVAILABLE');
      }
      final recovery = await _pendingLinkRecoveryCode();
      if (recovery != null) {
        _breadcrumb(LogCode.authRefreshFailed, 'auth_pending_link_recovery',
            httpStatus: result.status, errorCode: 'PROVIDER_LINK_RECOVERY');
        throw GuestAuthException(recovery);
      }
      _breadcrumb(LogCode.authRefreshFailed, 'guest_refresh_rejected',
          httpStatus: result.status, errorCode: 'GUEST_RECOVERY_REQUIRED');
      throw const GuestAuthException('GUEST_RECOVERY_REQUIRED');
    }
    final recovery = await _pendingLinkRecoveryCode();
    if (recovery != null) {
      // Never silently mint a new guest while a link may have upgraded identity.
      throw GuestAuthException(recovery);
    }
    if (forceNetworkRefresh || !allowGuestCreate) {
      throw const GuestAuthException('GUEST_RECOVERY_REQUIRED');
    }
    final result = await _post('/v1/auth/guest', const {});
    if (result.status != 201 && result.status != 200) {
      throw const GuestAuthException('GUEST_CREATION_UNAVAILABLE');
    }
    return _commitCredentials(result.body, generation: generation);
  }

  Future<GuestAccess> _commitCredentials(
    Map<String, dynamic> data, {
    required int generation,
    bool clearRotation = false,
  }) {
    return _serializedMutation(() async {
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
      final binding = GuestIdentityBinding(
        playerId: access.playerId,
        familyId: access.familyId,
        accountType: access.accountType,
      ).encode();
      try {
        await _commitVaultJournalled(
          GuestVaultJournal(
            nextRefresh: refresh,
            nextBinding: binding,
            clearRotation: clearRotation,
            pendingLinkAction: GuestVaultPendingLinkAction.keep,
          ),
        );
      } catch (_) {
        // Journal may remain for reconcile; never serve cached access meanwhile.
        _invalidateVaultSession(unsafe: true);
        _breadcrumb(LogCode.authRefreshFailed, 'guest_refresh_vault_write_failed',
            errorCode: 'SECURE_STORE_RECOVERY_FAILED');
        throw const GuestAuthException('SECURE_STORE_RECOVERY_FAILED');
      }
      if (generation != _credentialGeneration) {
        // Newer commit owns the vault; discard this response without inventing
        // a compensating write (serialized queue prevents mid-write races).
        _breadcrumb(LogCode.authRefreshFailed, 'guest_refresh_stale_after_write',
            errorCode: 'STALE_CREDENTIAL_RESPONSE');
        throw const GuestAuthException('STALE_CREDENTIAL_RESPONSE');
      }
      if (clearRotation) {
        _breadcrumb(
            LogCode.authRefreshSucceeded, 'guest_rotation_intent_cleared');
      }
      _breadcrumb(
          LogCode.authRefreshSucceeded, 'guest_refresh_vault_write_completed');
      return _current = access;
    });
  }

  /// Snapshot for startup recovery UI. Does not clear vault credentials.
  Future<GuestSessionRecovery> captureSessionRecovery(String code) async {
    final binding = GuestIdentityBinding.tryParse(
      await credentials.readIdentityBinding(),
    );
    final pendingRaw = await credentials.readPendingLinkProvider();
    final pending = PendingLinkRecovery.tryParse(pendingRaw);
    return GuestSessionRecovery(
      code: code,
      lastRequestId: _lastAuthRequestId,
      binding: binding,
      pendingLink: pending,
    );
  }

  Future<_GuestResponse> _post(String path, Map<String, Object?> body) async {
    final requestId = _newRequestId();
    _lastAuthRequestId = requestId;
    final override = debugTransport;
    if (override != null) {
      final operation =
          path == '/v1/auth/refresh' ? 'guest_auth_refresh' : 'guest_auth_create';
      _breadcrumb(LogCode.httpStarted, operation, requestId: requestId);
      final result = await override(path, body);
      _breadcrumb(LogCode.httpCompleted, operation,
          requestId: requestId,
          httpStatus: result.status,
          errorCode: result.status >= 400 ? 'AUTH_HTTP_REJECTED' : null);
      return _GuestResponse(result.status, result.body);
    }
    final client = _factory();
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
