/// Native provider assertion acquisition. Backend verifies tokens; never
/// treat a provider ID token as a Puzzle Duel session credential.
enum AuthProviderKind { apple, google }

enum ProviderSignInCancelReason { userCancelled, unavailable, failed }

final class ProviderAssertion {
  const ProviderAssertion({
    required this.provider,
    required this.idToken,
  });

  final AuthProviderKind provider;
  final String idToken;
}

final class ProviderSignInException implements Exception {
  const ProviderSignInException(this.code, {this.cancelReason});
  final String code;
  final ProviderSignInCancelReason? cancelReason;
  @override
  String toString() => code;
}

/// Platform adapters implement this. Tests use [FakeProviderSignIn].
abstract interface class ProviderSignInPort {
  Future<ProviderAssertion> signIn({
    required AuthProviderKind provider,
    required String nonce,
  });
}

/// Deterministic test double. Never used for production authentication.
final class FakeProviderSignIn implements ProviderSignInPort {
  FakeProviderSignIn({
    this.tokens = const {
      AuthProviderKind.apple: 'fake-apple-id-token',
      AuthProviderKind.google: 'fake-google-id-token',
    },
    this.failWith,
    this.cancelProviders = const {},
  });

  final Map<AuthProviderKind, String> tokens;
  final ProviderSignInException? failWith;
  final Set<AuthProviderKind> cancelProviders;
  final List<AuthProviderKind> calls = [];
  final List<String> nonces = [];

  @override
  Future<ProviderAssertion> signIn({
    required AuthProviderKind provider,
    required String nonce,
  }) async {
    calls.add(provider);
    nonces.add(nonce);
    if (nonce.isEmpty) {
      throw const ProviderSignInException('INVALID_PROVIDER_CHALLENGE');
    }
    if (cancelProviders.contains(provider)) {
      throw const ProviderSignInException(
        'PROVIDER_SIGN_IN_CANCELLED',
        cancelReason: ProviderSignInCancelReason.userCancelled,
      );
    }
    if (failWith != null) throw failWith!;
    final token = tokens[provider];
    if (token == null || token.isEmpty) {
      throw const ProviderSignInException(
        'PROVIDER_SIGN_IN_UNAVAILABLE',
        cancelReason: ProviderSignInCancelReason.unavailable,
      );
    }
    return ProviderAssertion(provider: provider, idToken: token);
  }
}
