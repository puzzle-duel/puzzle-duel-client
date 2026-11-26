import 'dart:async';

import 'package:puzzle_duel_mobile/diagnostics/diagnostic_runtime.dart';
import 'package:puzzle_duel_mobile/diagnostics/puzzle_duel_logger.dart';
import 'package:puzzle_duel_mobile/tournament/guest_auth.dart';
import 'package:puzzle_duel_mobile/tournament/provider_auth.dart';
import 'package:puzzle_duel_mobile/tournament/provider_sign_in.dart';

/// Result of a provider authentication attempt. Never silently switches accounts.
enum AuthFlowOutcome {
  linked,
  loggedIn,
  cancelled,
  conflict,
  failed,
  /// Backend may have upgraded the guest; identity-preserving recovery required.
  recoveryRequired,
}

final class AuthFlowResult {
  const AuthFlowResult({
    required this.outcome,
    this.access,
    this.errorCode,
    this.conflictPlayerId,
    this.recoveryProvider,
    this.expectedPlayerId,
  });

  final AuthFlowOutcome outcome;
  final GuestAccess? access;
  final String? errorCode;
  final String? conflictPlayerId;
  final AuthProviderKind? recoveryProvider;
  /// Original guest/verified player id that recovery must resolve.
  final String? expectedPlayerId;
}

/// Orchestrates challenge → native provider → backend link/login with
/// generation-guarded credential replacement.
final class AuthCoordinator {
  AuthCoordinator({
    required this.session,
    required this.providers,
    required this.signIn,
    PuzzleDuelLogger? logger,
  }) : _logger = logger ?? DiagnosticRuntime.logger;

  final GuestAuthClient session;
  final ProviderAuthPort providers;
  final ProviderSignInPort signIn;
  final PuzzleDuelLogger _logger;

  var _inFlight = false;

  void _breadcrumb(String operation, {String? errorCode}) {
    unawaited(_logger.log(LogEvent(
      level: errorCode == null ? LogLevel.info : LogLevel.warning,
      code: errorCode == null ? LogCode.screenOpened : LogCode.authRefreshFailed,
      operation: operation,
      errorCode: errorCode,
    )));
  }

  /// Links the current guest identity. Preserves player_id on success.
  Future<AuthFlowResult> linkCurrentGuest(AuthProviderKind provider) async {
    if (_inFlight) {
      return const AuthFlowResult(
        outcome: AuthFlowOutcome.failed,
        errorCode: 'AUTH_IN_FLIGHT',
      );
    }
    _inFlight = true;
    try {
      _breadcrumb('auth_provider_selected_${provider.name}');
      var guest = await session.authenticate();
      if (guest.accountType != AccountType.guest) {
        return AuthFlowResult(
          outcome: AuthFlowOutcome.loggedIn,
          access: guest,
        );
      }
      final priorPlayerId = guest.playerId;
      final priorFamilyId = guest.familyId;
      _breadcrumb('provider_challenge_requested');
      final challenge = await providers.challenge(
        provider: provider,
        purpose: ProviderAuthPurpose.link,
        guestBearer: guest.accessToken,
      );
      _breadcrumb('provider_sign_in_started');
      final assertion = await _nativeSignIn(provider, challenge.nonce);
      if (assertion == null) {
        _breadcrumb('provider_sign_in_cancelled',
            errorCode: 'PROVIDER_SIGN_IN_CANCELLED');
        return const AuthFlowResult(
          outcome: AuthFlowOutcome.cancelled,
          errorCode: 'PROVIDER_SIGN_IN_CANCELLED',
        );
      }
      _breadcrumb('provider_sign_in_completed');

      // Native UI may outlive access TTL. Refresh while keeping player/fid.
      // Challenge nonce is already embedded in the assertion — do not re-challenge.
      if (guest.isNearExpiry) {
        guest = await session.refreshGuestPreservingIdentity(
          playerId: priorPlayerId,
          familyId: priorFamilyId,
        );
      }

      await session.markPendingLink(
        provider: provider.name,
        playerId: priorPlayerId,
      );
      try {
        final bundle = await providers.link(
          provider: provider,
          idToken: assertion.idToken,
          nonce: challenge.nonce,
          guestBearer: guest.accessToken,
        );
        if (bundle.playerId != priorPlayerId) {
          return AuthFlowResult(
            outcome: AuthFlowOutcome.failed,
            errorCode: 'PLAYER_ID_MUTATION',
            expectedPlayerId: priorPlayerId,
          );
        }
        try {
          final access = await session.replaceWithVerifiedBundle(
            accessToken: bundle.accessToken,
            refreshToken: bundle.refreshToken,
            expiresAt: bundle.expiresAt,
          );
          _breadcrumb('auth_credential_replaced');
          return AuthFlowResult(
            outcome: AuthFlowOutcome.linked,
            access: access,
          );
        } on GuestAuthException catch (error) {
          // Backend link likely succeeded; vault write failed. Keep pending
          // marker and require identity-preserving recovery — never guest create.
          _breadcrumb('auth_link_vault_failed', errorCode: error.code);
          return AuthFlowResult(
            outcome: AuthFlowOutcome.recoveryRequired,
            errorCode: error.code,
            recoveryProvider: provider,
            expectedPlayerId: priorPlayerId,
          );
        }
      } on ProviderAuthException catch (error) {
        if (error.code == 'ACCOUNT_CONFLICT') {
          await session.clearPendingLinkProvider();
          _breadcrumb('auth_account_conflict', errorCode: 'ACCOUNT_CONFLICT');
          return const AuthFlowResult(
            outcome: AuthFlowOutcome.conflict,
            errorCode: 'ACCOUNT_CONFLICT',
          );
        }
        if (error.code == 'GUEST_PROOF_REQUIRED' ||
            error.code == 'INVALID_PROVIDER_CHALLENGE') {
          // Stale challenge/bearer after native UI — clear pending, fail closed.
          await session.clearPendingLinkProvider();
        }
        // Network / lost response after possible server success: keep pending.
        if (error.code == 'AUTH_NETWORK_UNAVAILABLE') {
          _breadcrumb('auth_link_uncertain', errorCode: error.code);
          return AuthFlowResult(
            outcome: AuthFlowOutcome.recoveryRequired,
            errorCode: error.code,
            recoveryProvider: provider,
            expectedPlayerId: priorPlayerId,
          );
        }
        _breadcrumb('provider_link_failed', errorCode: error.code);
        return AuthFlowResult(
          outcome: AuthFlowOutcome.failed,
          errorCode: error.code,
          expectedPlayerId: priorPlayerId,
        );
      }
    } on ProviderSignInException catch (error) {
      final cancelled =
          error.cancelReason == ProviderSignInCancelReason.userCancelled;
      return AuthFlowResult(
        outcome:
            cancelled ? AuthFlowOutcome.cancelled : AuthFlowOutcome.failed,
        errorCode: error.code,
      );
    } on GuestAuthException catch (error) {
      final recovery = await _recoveryResultFromCode(error.code);
      if (recovery != null) return recovery;
      return AuthFlowResult(
        outcome: AuthFlowOutcome.failed,
        errorCode: error.code,
      );
    } on ProviderAuthException catch (error) {
      return AuthFlowResult(
        outcome: AuthFlowOutcome.failed,
        errorCode: error.code,
      );
    } finally {
      _inFlight = false;
    }
  }

  /// Explicit sign-in to an existing (or newly created) verified account.
  /// Not used for pending-link recovery — see [recoverPendingLink].
  Future<AuthFlowResult> loginExisting(AuthProviderKind provider) async {
    if (_inFlight) {
      return const AuthFlowResult(
        outcome: AuthFlowOutcome.failed,
        errorCode: 'AUTH_IN_FLIGHT',
      );
    }
    _inFlight = true;
    try {
      _breadcrumb('auth_provider_selected_${provider.name}');
      _breadcrumb('provider_challenge_requested');
      final challenge = await providers.challenge(
        provider: provider,
        purpose: ProviderAuthPurpose.login,
      );
      final binding = challenge.binding;
      if (binding == null || binding.isEmpty) {
        return const AuthFlowResult(
          outcome: AuthFlowOutcome.failed,
          errorCode: 'INVALID_PROVIDER_CHALLENGE',
        );
      }
      _breadcrumb('provider_sign_in_started');
      final assertion = await _nativeSignIn(provider, challenge.nonce);
      if (assertion == null) {
        return const AuthFlowResult(
          outcome: AuthFlowOutcome.cancelled,
          errorCode: 'PROVIDER_SIGN_IN_CANCELLED',
        );
      }
      _breadcrumb('provider_sign_in_completed');
      final bundle = await providers.login(
        provider: provider,
        idToken: assertion.idToken,
        nonce: challenge.nonce,
        binding: binding,
      );
      final access = await session.replaceWithVerifiedBundle(
        accessToken: bundle.accessToken,
        refreshToken: bundle.refreshToken,
        expiresAt: bundle.expiresAt,
      );
      _breadcrumb('auth_credential_replaced');
      return AuthFlowResult(
        outcome: AuthFlowOutcome.loggedIn,
        access: access,
      );
    } on ProviderSignInException catch (error) {
      final cancelled =
          error.cancelReason == ProviderSignInCancelReason.userCancelled;
      return AuthFlowResult(
        outcome:
            cancelled ? AuthFlowOutcome.cancelled : AuthFlowOutcome.failed,
        errorCode: error.code,
      );
    } on GuestAuthException catch (error) {
      return AuthFlowResult(
        outcome: AuthFlowOutcome.failed,
        errorCode: error.code,
      );
    } on ProviderAuthException catch (error) {
      return AuthFlowResult(
        outcome: AuthFlowOutcome.failed,
        errorCode: error.code,
      );
    } finally {
      _inFlight = false;
    }
  }

  /// Identity-preserving recovery for uncertain link completion.
  /// Uses backend `POST /v1/auth/providers/recover` (create-forbidden).
  /// If the original guest session is still valid (link never committed),
  /// returns [RECOVERY_RETRY_LINK] so the UI can re-run guest link instead.
  Future<AuthFlowResult> recoverPendingLink(AuthProviderKind provider) async {
    if (_inFlight) {
      return const AuthFlowResult(
        outcome: AuthFlowOutcome.failed,
        errorCode: 'AUTH_IN_FLIGHT',
      );
    }
    _inFlight = true;
    try {
      final pending = await session.readPendingLinkRecovery();
      if (pending == null) {
        return const AuthFlowResult(
          outcome: AuthFlowOutcome.failed,
          errorCode: 'RECOVERY_MARKER_MISSING',
        );
      }
      if (pending.provider != provider.name) {
        return AuthFlowResult(
          outcome: AuthFlowOutcome.recoveryRequired,
          errorCode: 'RECOVERY_PROVIDER_MISMATCH',
          recoveryProvider: pending.provider == 'apple'
              ? AuthProviderKind.apple
              : AuthProviderKind.google,
          expectedPlayerId: pending.playerId,
        );
      }

      // Probe only with a server-backed refresh. A cached unexpired guest JWT
      // is not proof the backend family is still active after a committed link.
      try {
        final existing = await session.authenticate(
          forceRefresh: true,
          allowGuestCreate: false,
        );
        if (existing.playerId != pending.playerId) {
          _breadcrumb('auth_recovery_probe_identity_mismatch',
              errorCode: 'RECOVERY_IDENTITY_MISMATCH');
          // Keep marker; fall through to create-forbidden recover.
        } else if (existing.isGuest) {
          _breadcrumb('auth_recovery_retry_link');
          return AuthFlowResult(
            outcome: AuthFlowOutcome.failed,
            errorCode: 'RECOVERY_RETRY_LINK',
            recoveryProvider: provider,
            expectedPlayerId: pending.playerId,
          );
        } else if (existing.isVerified) {
          await session.clearPendingLinkProvider();
          return AuthFlowResult(
            outcome: AuthFlowOutcome.loggedIn,
            access: existing,
          );
        }
      } on GuestAuthException catch (error) {
        if (error.code == 'REFRESH_UNAVAILABLE' ||
            error.code == 'AUTH_NETWORK_UNAVAILABLE') {
          // Temporary network failure — keep marker; do not invent guest/recover.
          return AuthFlowResult(
            outcome: AuthFlowOutcome.recoveryRequired,
            errorCode: error.code,
            recoveryProvider: provider,
            expectedPlayerId: pending.playerId,
          );
        }
        // Revoked/rejected family or pending-link recovery → provider recover.
      }

      _breadcrumb('auth_recovery_started_${provider.name}');
      final challenge = await providers.challenge(
        provider: provider,
        purpose: ProviderAuthPurpose.login,
      );
      final binding = challenge.binding;
      if (binding == null || binding.isEmpty) {
        return AuthFlowResult(
          outcome: AuthFlowOutcome.recoveryRequired,
          errorCode: 'INVALID_PROVIDER_CHALLENGE',
          recoveryProvider: provider,
          expectedPlayerId: pending.playerId,
        );
      }
      final assertion = await _nativeSignIn(provider, challenge.nonce);
      if (assertion == null) {
        return AuthFlowResult(
          outcome: AuthFlowOutcome.cancelled,
          errorCode: 'PROVIDER_SIGN_IN_CANCELLED',
          recoveryProvider: provider,
          expectedPlayerId: pending.playerId,
        );
      }
      final bundle = await providers.recover(
        provider: provider,
        idToken: assertion.idToken,
        nonce: challenge.nonce,
        binding: binding,
        expectedPlayerId: pending.playerId,
      );
      if (bundle.playerId != pending.playerId) {
        // Backend should already reject; keep marker as a hard fail-closed belt.
        _breadcrumb('auth_recovery_identity_mismatch',
            errorCode: 'RECOVERY_IDENTITY_MISMATCH');
        return AuthFlowResult(
          outcome: AuthFlowOutcome.recoveryRequired,
          errorCode: 'RECOVERY_IDENTITY_MISMATCH',
          recoveryProvider: provider,
          expectedPlayerId: pending.playerId,
        );
      }
      final access = await session.replaceWithVerifiedBundle(
        accessToken: bundle.accessToken,
        refreshToken: bundle.refreshToken,
        expiresAt: bundle.expiresAt,
      );
      _breadcrumb('auth_recovery_succeeded');
      return AuthFlowResult(
        outcome: AuthFlowOutcome.loggedIn,
        access: access,
      );
    } on ProviderSignInException catch (error) {
      final pending = await session.readPendingLinkRecovery();
      final cancelled =
          error.cancelReason == ProviderSignInCancelReason.userCancelled;
      return AuthFlowResult(
        outcome:
            cancelled ? AuthFlowOutcome.cancelled : AuthFlowOutcome.failed,
        errorCode: error.code,
        recoveryProvider: provider,
        expectedPlayerId: pending?.playerId,
      );
    } on GuestAuthException catch (error) {
      final pending = await session.readPendingLinkRecovery();
      return AuthFlowResult(
        outcome: AuthFlowOutcome.recoveryRequired,
        errorCode: error.code,
        recoveryProvider: provider,
        expectedPlayerId: pending?.playerId,
      );
    } on ProviderAuthException catch (error) {
      final pending = await session.readPendingLinkRecovery();
      return AuthFlowResult(
        outcome: AuthFlowOutcome.recoveryRequired,
        errorCode: error.code,
        recoveryProvider: provider,
        expectedPlayerId: pending?.playerId,
      );
    } finally {
      _inFlight = false;
    }
  }

  /// Create-forbidden provider recovery for a known player_id binding.
  /// Never calls login (which could mint a new verified account).
  Future<AuthFlowResult> recoverKnownPlayer({
    required AuthProviderKind provider,
    required String expectedPlayerId,
  }) async {
    if (_inFlight) {
      return const AuthFlowResult(
        outcome: AuthFlowOutcome.failed,
        errorCode: 'AUTH_IN_FLIGHT',
      );
    }
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(expectedPlayerId)) {
      return const AuthFlowResult(
        outcome: AuthFlowOutcome.failed,
        errorCode: 'RECOVERY_IDENTITY_MISSING',
      );
    }
    _inFlight = true;
    try {
      _breadcrumb('auth_known_player_recovery_started_${provider.name}');
      final challenge = await providers.challenge(
        provider: provider,
        purpose: ProviderAuthPurpose.login,
      );
      final binding = challenge.binding;
      if (binding == null || binding.isEmpty) {
        return AuthFlowResult(
          outcome: AuthFlowOutcome.recoveryRequired,
          errorCode: 'INVALID_PROVIDER_CHALLENGE',
          recoveryProvider: provider,
          expectedPlayerId: expectedPlayerId,
        );
      }
      final assertion = await _nativeSignIn(provider, challenge.nonce);
      if (assertion == null) {
        return AuthFlowResult(
          outcome: AuthFlowOutcome.cancelled,
          errorCode: 'PROVIDER_SIGN_IN_CANCELLED',
          recoveryProvider: provider,
          expectedPlayerId: expectedPlayerId,
        );
      }
      final bundle = await providers.recover(
        provider: provider,
        idToken: assertion.idToken,
        nonce: challenge.nonce,
        binding: binding,
        expectedPlayerId: expectedPlayerId,
      );
      if (bundle.playerId != expectedPlayerId) {
        return AuthFlowResult(
          outcome: AuthFlowOutcome.recoveryRequired,
          errorCode: 'RECOVERY_IDENTITY_MISMATCH',
          recoveryProvider: provider,
          expectedPlayerId: expectedPlayerId,
        );
      }
      final access = await session.replaceWithVerifiedBundle(
        accessToken: bundle.accessToken,
        refreshToken: bundle.refreshToken,
        expiresAt: bundle.expiresAt,
      );
      await session.clearPendingLinkProvider();
      _breadcrumb('auth_known_player_recovery_succeeded');
      return AuthFlowResult(
        outcome: AuthFlowOutcome.loggedIn,
        access: access,
      );
    } on ProviderSignInException catch (error) {
      final cancelled =
          error.cancelReason == ProviderSignInCancelReason.userCancelled;
      return AuthFlowResult(
        outcome:
            cancelled ? AuthFlowOutcome.cancelled : AuthFlowOutcome.failed,
        errorCode: error.code,
        recoveryProvider: provider,
        expectedPlayerId: expectedPlayerId,
      );
    } on GuestAuthException catch (error) {
      return AuthFlowResult(
        outcome: AuthFlowOutcome.recoveryRequired,
        errorCode: error.code,
        recoveryProvider: provider,
        expectedPlayerId: expectedPlayerId,
      );
    } on ProviderAuthException catch (error) {
      return AuthFlowResult(
        outcome: error.code == 'RECOVERY_NOT_LINKED'
            ? AuthFlowOutcome.failed
            : AuthFlowOutcome.recoveryRequired,
        errorCode: error.code,
        recoveryProvider: provider,
        expectedPlayerId: expectedPlayerId,
      );
    } finally {
      _inFlight = false;
    }
  }

  /// After restart: if pending link exists and guest refresh fails, surface
  /// recovery without minting a new guest player.
  Future<AuthFlowResult?> consumePendingLinkRecoveryIfNeeded() async {
    final pending = await session.readPendingLinkRecovery();
    AuthProviderKind? provider;
    String? expectedPlayerId;
    if (pending != null) {
      provider = pending.provider == 'apple'
          ? AuthProviderKind.apple
          : AuthProviderKind.google;
      expectedPlayerId = pending.playerId;
    } else {
      // Legacy provider-only marker: still block guest create via authenticate.
      final encoded = await session.credentials.readPendingLinkProvider();
      final legacy = PendingLinkRecovery.legacyProviderOnly(encoded);
      if (legacy == null) return null;
      provider =
          legacy == 'apple' ? AuthProviderKind.apple : AuthProviderKind.google;
    }
    try {
      final access = await session.authenticate();
      if (access.isVerified) {
        if (expectedPlayerId != null && access.playerId != expectedPlayerId) {
          return AuthFlowResult(
            outcome: AuthFlowOutcome.recoveryRequired,
            errorCode: 'RECOVERY_IDENTITY_MISMATCH',
            recoveryProvider: provider,
            expectedPlayerId: expectedPlayerId,
          );
        }
        await session.clearPendingLinkProvider();
        return AuthFlowResult(
          outcome: AuthFlowOutcome.loggedIn,
          access: access,
        );
      }
      return null;
    } on GuestAuthException catch (error) {
      final recovery = await _recoveryResultFromCode(error.code);
      if (recovery != null) return recovery;
      return AuthFlowResult(
        outcome: AuthFlowOutcome.recoveryRequired,
        errorCode: error.code,
        recoveryProvider: provider,
        expectedPlayerId: expectedPlayerId,
      );
    }
  }

  Future<AuthFlowResult?> _recoveryResultFromCode(String code) async {
    final kind = _recoveryFromCode(code);
    if (kind == null) return null;
    final pending = await session.readPendingLinkRecovery();
    return AuthFlowResult(
      outcome: AuthFlowOutcome.recoveryRequired,
      errorCode: code,
      recoveryProvider: kind,
      expectedPlayerId: pending?.playerId,
    );
  }

  AuthProviderKind? _recoveryFromCode(String code) {
    if (code == 'PROVIDER_LINK_RECOVERY_apple' ||
        code == 'PROVIDER_LINK_RECOVERY_APPLE') {
      return AuthProviderKind.apple;
    }
    if (code == 'PROVIDER_LINK_RECOVERY_google' ||
        code == 'PROVIDER_LINK_RECOVERY_GOOGLE') {
      return AuthProviderKind.google;
    }
    return null;
  }

  Future<ProviderAssertion?> _nativeSignIn(
    AuthProviderKind provider,
    String nonce,
  ) async {
    try {
      return await signIn.signIn(provider: provider, nonce: nonce);
    } on ProviderSignInException catch (error) {
      if (error.cancelReason == ProviderSignInCancelReason.userCancelled) {
        return null;
      }
      rethrow;
    }
  }

  Future<AuthFlowResult> logoutAndStartGuest() async {
    if (_inFlight) {
      return const AuthFlowResult(
        outcome: AuthFlowOutcome.failed,
        errorCode: 'AUTH_IN_FLIGHT',
      );
    }
    _inFlight = true;
    try {
      _breadcrumb('auth_logout');
      final refresh = await session.credentials.readRefreshToken();
      final cached = session.cachedAccess;
      if (refresh != null && refresh.isNotEmpty) {
        try {
          await providers.logout(
            refreshToken: refresh,
            accessBearer: cached?.accessToken,
          );
        } on ProviderAuthException catch (error) {
          if (error.code != 'INVALID_REFRESH') {
            return AuthFlowResult(
              outcome: AuthFlowOutcome.failed,
              errorCode: error.code,
            );
          }
        }
      }
      await session.clearPendingLinkProvider();
      await session.clearSessionLocally();
      final guest = await session.authenticate();
      _breadcrumb('auth_logout_guest_ready');
      return AuthFlowResult(
        outcome: AuthFlowOutcome.loggedIn,
        access: guest,
      );
    } on GuestAuthException catch (error) {
      return AuthFlowResult(
        outcome: AuthFlowOutcome.failed,
        errorCode: error.code,
      );
    } finally {
      _inFlight = false;
    }
  }
}
