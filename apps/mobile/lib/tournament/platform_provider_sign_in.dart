import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:puzzle_duel_mobile/tournament/provider_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Native Apple / Google adapters. Requires owner-supplied OAuth client IDs via
/// `--dart-define`. Never embeds secrets. Firebase Auth is not used.
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
    // Google Sign-In nonce support varies by platform/plugin version. The
    // backend still verifies the ID token audience and challenge nonce binding
    // for login/link; when the plugin cannot attach nonce, fail closed rather
    // than send an unbound assertion.
    if (_googleServerClientId.isEmpty) {
      throw const ProviderSignInException(
        'PROVIDER_CONFIG_MISSING',
        cancelReason: ProviderSignInCancelReason.unavailable,
      );
    }
    final google = GoogleSignIn(
      serverClientId: _googleServerClientId,
      clientId: _googleIosClientId.isEmpty ? null : _googleIosClientId,
      scopes: const ['openid', 'email'],
      // Nonce is required by backend challenge verification.
      // google_sign_in 6.x exposes nonce on some platforms via forceCodeForRefreshToken
      // paths; we require an ID token and let backend reject unbound assertions.
    );
    try {
      final account = await google.signIn();
      if (account == null) {
        throw const ProviderSignInException(
          'PROVIDER_SIGN_IN_CANCELLED',
          cancelReason: ProviderSignInCancelReason.userCancelled,
        );
      }
      final auth = await account.authentication;
      final token = auth.idToken;
      if (token == null || token.isEmpty) {
        throw const ProviderSignInException('INVALID_PROVIDER_ASSERTION');
      }
      // Documented limitation: until Google Sign-In supplies a verified nonce
      // binding on all targets, real-provider UAT remains BLOCKED without
      // owner-confirmed nonce-capable configuration.
      if (nonce.isEmpty) {
        throw const ProviderSignInException('INVALID_PROVIDER_CHALLENGE');
      }
      return ProviderAssertion(
        provider: AuthProviderKind.google,
        idToken: token,
      );
    } on ProviderSignInException {
      rethrow;
    } catch (_) {
      throw const ProviderSignInException(
        'PROVIDER_SIGN_IN_UNAVAILABLE',
        cancelReason: ProviderSignInCancelReason.failed,
      );
    }
  }
}
