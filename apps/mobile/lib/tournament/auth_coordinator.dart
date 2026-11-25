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
}

final class AuthFlowResult {
  const AuthFlowResult({
    required this.outcome,
    this.access,
    this.errorCode,
    this.conflictPlayerId,
  });

  final AuthFlowOutcome outcome;
  final GuestAccess? access;
  final String? errorCode;
  /// Present only as a non-secret signal that an existing account owns the
  /// provider identity. Never an email or provider subject.
  final String? conflictPlayerId;
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
      final guest = await session.authenticate();
      if (guest.accountType != AccountType.guest) {
        return AuthFlowResult(
          outcome: AuthFlowOutcome.loggedIn,
          access: guest,
        );
      }
      final priorPlayerId = guest.playerId;
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
      try {
        final bundle = await providers.link(
          provider: provider,
          idToken: assertion.idToken,
          nonce: challenge.nonce,
          guestBearer: guest.accessToken,
        );
        if (bundle.playerId != priorPlayerId) {
          // Backend contract requires immutable player_id on link. Fail closed.
          return const AuthFlowResult(
            outcome: AuthFlowOutcome.failed,
            errorCode: 'PLAYER_ID_MUTATION',
          );
        }
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
      } on ProviderAuthException catch (error) {
        if (error.code == 'ACCOUNT_CONFLICT') {
          _breadcrumb('auth_account_conflict', errorCode: 'ACCOUNT_CONFLICT');
          return const AuthFlowResult(
            outcome: AuthFlowOutcome.conflict,
            errorCode: 'ACCOUNT_CONFLICT',
          );
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
  /// Does not merge with the current guest. Caller must confirm after conflict.
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

  /// Revokes the current refresh family on the backend, clears the vault, then
  /// issues a fresh guest session so Practice remains available without login.
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
          // Unknown/already-revoked refresh still clears local state.
          if (error.code != 'INVALID_REFRESH') {
            return AuthFlowResult(
              outcome: AuthFlowOutcome.failed,
              errorCode: error.code,
            );
          }
        }
      }
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
