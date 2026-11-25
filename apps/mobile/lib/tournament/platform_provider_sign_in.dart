import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:puzzle_duel_mobile/tournament/provider_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Native Apple / Google adapters. Requires owner-supplied OAuth client IDs via
/// `--dart-define`. Never embeds secrets. Firebase Auth is not used.
///
/// Google uses `google_sign_in` 7.x so the backend-issued challenge [nonce] is
/// passed into the native ID-token request (InitParameters.nonce). Apple uses
/// `sign_in_with_apple` which forwards the raw nonce; the Apple SDK embeds the
/// SHA-256 digest in the identity token claim (PZD-26 verifier).
final class PlatformProviderSignIn implements ProviderSignInPort {
  PlatformProviderSignIn({
    String? googleServerClientId,
    String? googleIosClientId,
  })  : _googleServerClientId = googleServerClientId ??
            const String.fromEnvironment('PZD_GOOGLE_SERVER_CLIENT_ID'),
        _googleIosClientId = googleIosClientId ??
            const String.fromEnvironment('PZD_GOOGLE_IOS_CLIENT_ID');

  final String _googleServerClientId;
  final String _googleIosClientId;
  var _googleBaseInitialized = false;

  @override
  Future<ProviderAssertion> signIn({
    required AuthProviderKind provider,
    required String nonce,
  }) async {
    if (nonce.isEmpty) {
      throw const ProviderSignInException('INVALID_PROVIDER_CHALLENGE');
    }
    return switch (provider) {
      AuthProviderKind.apple => _apple(nonce),
      AuthProviderKind.google => _google(nonce),
    };
  }

  Future<ProviderAssertion> _apple(String nonce) async {
    // Android Apple Sign-In needs a Services ID / browser callback that the
    // owner must configure separately. Until then, fail closed on Android.
    if (!kIsWeb && Platform.isAndroid) {
      throw const ProviderSignInException(
        'PROVIDER_SIGN_IN_UNAVAILABLE',
        cancelReason: ProviderSignInCancelReason.unavailable,
      );
    }
    try {
      final available = await SignInWithApple.isAvailable();
      if (!available) {
        throw const ProviderSignInException(
          'PROVIDER_SIGN_IN_UNAVAILABLE',
          cancelReason: ProviderSignInCancelReason.unavailable,
        );
      }
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );
      final token = credential.identityToken;
      if (token == null || token.isEmpty) {
        throw const ProviderSignInException('INVALID_PROVIDER_ASSERTION');
      }
      return ProviderAssertion(
        provider: AuthProviderKind.apple,
        idToken: token,
      );
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) {
        throw const ProviderSignInException(
          'PROVIDER_SIGN_IN_CANCELLED',
          cancelReason: ProviderSignInCancelReason.userCancelled,
        );
      }
      throw const ProviderSignInException(
        'PROVIDER_SIGN_IN_UNAVAILABLE',
        cancelReason: ProviderSignInCancelReason.failed,
      );
    }
  }

  Future<ProviderAssertion> _google(String nonce) async {
    if (_googleServerClientId.isEmpty) {
      throw const ProviderSignInException(
        'PROVIDER_CONFIG_MISSING',
        cancelReason: ProviderSignInCancelReason.unavailable,
      );
    }
    try {
      await _prepareGoogleWithNonce(nonce);
      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: const ['openid', 'email'],
      );
      final token = account.authentication.idToken;
      if (token == null || token.isEmpty) {
        throw const ProviderSignInException('INVALID_PROVIDER_ASSERTION');
      }
      return ProviderAssertion(
        provider: AuthProviderKind.google,
        idToken: token,
      );
    } on ProviderSignInException {
      rethrow;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const ProviderSignInException(
          'PROVIDER_SIGN_IN_CANCELLED',
          cancelReason: ProviderSignInCancelReason.userCancelled,
        );
      }
      throw const ProviderSignInException(
        'PROVIDER_SIGN_IN_UNAVAILABLE',
        cancelReason: ProviderSignInCancelReason.failed,
      );
    } catch (_) {
      throw const ProviderSignInException(
        'PROVIDER_SIGN_IN_UNAVAILABLE',
        cancelReason: ProviderSignInCancelReason.failed,
      );
    }
  }

  /// Each challenge has a unique nonce. High-level [GoogleSignIn.initialize]
  /// may only wire streams once; subsequent challenges update the platform
  /// nonce via [GoogleSignInPlatform.init] without fabricating token claims.
  Future<void> _prepareGoogleWithNonce(String nonce) async {
    final clientId = _googleIosClientId.isEmpty ? null : _googleIosClientId;
    if (!_googleBaseInitialized) {
      await GoogleSignIn.instance.initialize(
        clientId: clientId,
        serverClientId: _googleServerClientId,
        nonce: nonce,
      );
      _googleBaseInitialized = true;
      return;
    }
    await GoogleSignInPlatform.instance.init(
      InitParameters(
        clientId: clientId,
        serverClientId: _googleServerClientId,
        nonce: nonce,
      ),
    );
  }
}
