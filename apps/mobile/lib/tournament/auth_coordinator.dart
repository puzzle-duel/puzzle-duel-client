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
  /// Backend may have upgraded the guest; explicit provider login is required.
  recoveryRequired,
}

final class AuthFlowResult {
  const AuthFlowResult({
    required this.outcome,
    this.access,
    this.errorCode,
    this.conflictPlayerId,
    this.recoveryProvider,
  });

  final AuthFlowOutcome outcome;
  final GuestAccess? access;
  final String? errorCode;
  final String? conflictPlayerId;
  final AuthProviderKind? recoveryProvider;
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

      await session.markPendingLinkProvider(provider.name);
      try {
        final bundle = await providers.link(
          provider: provider,
          idToken: assertion.idToken,
          nonce: challenge.nonce,
          guestBearer: guest.accessToken,
        );
        if (bundle.playerId != priorPlayerId) {
          return const AuthFlowResult(
            outcome: AuthFlowOutcome.failed,
            errorCode: 'PLAYER_ID_MUTATION',
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
          // marker and require explicit provider recovery — never guest create.
          _breadcrumb('auth_link_vault_failed', errorCode: error.code);
          return AuthFlowResult(
            outcome: AuthFlowOutcome.recoveryRequired,
            errorCode: error.code,
            recoveryProvider: provider,
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
          );
        }
        if (error.code != 'GUEST_PROOF_REQUIRED' &&
            error.code != 'INVALID_PROVIDER_CHALLENGE') {
          // Keep pending for unknown failures that may follow a server commit.
        } else {
          // already cleared
        }
        _breadcrumb('provider_link_failed', errorCode: error.code);
        return AuthFlowResult(
          outcome: AuthFlowOutcome.failed,
          errorCode: error.code,
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
      final recovery = _recoveryFromCode(error.code);
      if (recovery != null) {
        return AuthFlowResult(
          outcome: AuthFlowOutcome.recoveryRequired,
          errorCode: error.code,
          recoveryProvider: recovery,
        );
      }
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
  /// Also used for post-link recovery when guest refresh is revoked.
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

  /// After restart: if pending link exists and guest refresh fails, surface
  /// recovery without minting a new guest player.
  Future<AuthFlowResult?> consumePendingLinkRecoveryIfNeeded() async {
    final pending = await session.readPendingLinkProvider();
    if (pending != 'apple' && pending != 'google') return null;
    final provider =
        pending == 'apple' ? AuthProviderKind.apple : AuthProviderKind.google;
    try {
      final access = await session.authenticate();
      if (access.isVerified) {
        await session.clearPendingLinkProvider();
        return AuthFlowResult(
          outcome: AuthFlowOutcome.loggedIn,
          access: access,
        );
      }
      return null;
    } on GuestAuthException catch (error) {
      final recovery = _recoveryFromCode(error.code) ?? provider;
      return AuthFlowResult(
        outcome: AuthFlowOutcome.recoveryRequired,
        errorCode: error.code,
        recoveryProvider: recovery,
      );
    }
  }

  AuthProviderKind? _recoveryFromCode(String code) {
    if (code == 'PROVIDER_LINK_RECOVERY_apple') return AuthProviderKind.apple;
    if (code == 'PROVIDER_LINK_RECOVERY_google') return AuthProviderKind.google;
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
