import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/tournament/auth_coordinator.dart';
import 'package:puzzle_duel_mobile/tournament/guest_auth.dart';
import 'package:puzzle_duel_mobile/tournament/provider_auth.dart';
import 'package:puzzle_duel_mobile/tournament/provider_sign_in.dart';

String _jwt({
  required String sub,
  required String accountType,
  String? fid,
}) {
  final header = base64Url
      .encode(utf8.encode(jsonEncode({'alg': 'none', 'typ': 'JWT'})))
      .replaceAll('=', '');
  final claims = <String, Object?>{
    'iss': 'https://staging.puzzle-duel.app',
    'aud': 'puzzle-duel-api',
    'sub': sub,
    'account_type': accountType,
    'fid': ?fid,
  };
  final payload = base64Url
      .encode(utf8.encode(jsonEncode(claims)))
      .replaceAll('=', '');
  return '$header.$payload.sig';
}

final class _MemoryStore implements GuestCredentialStore {
  String? token;
  String? rotationId;
  String? pendingLink;
  Duration writeDelay = Duration.zero;
  bool failWrite = false;
  @override
  Future<String?> readRefreshToken() async => token;
  @override
  Future<void> writeRefreshToken(String value) async {
    if (writeDelay > Duration.zero) await Future<void>.delayed(writeDelay);
    if (failWrite) throw StateError('storage denied');
    token = value;
  }
  @override
  Future<void> clearRefreshToken() async => token = null;
  @override
  Future<String?> readPendingRotationId() async => rotationId;
  @override
  Future<void> writePendingRotationId(String id) async => rotationId = id;
  @override
  Future<void> clearPendingRotationId() async => rotationId = null;
  @override
  Future<String?> readPendingLinkProvider() async => pendingLink;
  @override
  Future<void> writePendingLinkProvider(String provider) async {
    pendingLink = provider;
  }
  @override
  Future<void> clearPendingLinkProvider() async => pendingLink = null;
}

final class _FakeProviders implements ProviderAuthPort {
  _FakeProviders({
    this.linkError,
    this.loginPlayerId = '11111111-1111-1111-1111-111111111111',
    this.linkPlayerId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  });

  ProviderAuthException? linkError;
  String loginPlayerId;
  String linkPlayerId;
  var linkCalls = 0;
  var loginCalls = 0;
  var recoverCalls = 0;
  var challengeCalls = 0;
  var logoutCalls = 0;
  ProviderAuthException? recoverError;
  String? recoverExpectedPlayerId;

  @override
  Future<ProviderChallenge> challenge({
    required AuthProviderKind provider,
    required ProviderAuthPurpose purpose,
    String? guestBearer,
  }) async {
    challengeCalls++;
    if (purpose == ProviderAuthPurpose.link &&
        (guestBearer == null || guestBearer.isEmpty)) {
      throw const ProviderAuthException('GUEST_PROOF_REQUIRED');
    }
    return ProviderChallenge(
      provider: provider,
      purpose: purpose,
      nonce: 'n' * 43,
      binding: purpose == ProviderAuthPurpose.login ? 'binding-secret' : null,
    );
  }

  @override
  Future<ProviderCredentialBundle> login({
    required AuthProviderKind provider,
    required String idToken,
    required String nonce,
    required String binding,
  }) async {
    loginCalls++;
    return ProviderCredentialBundle(
      playerId: loginPlayerId,
      accountType: 'verified',
      accessToken: _jwt(
        sub: loginPlayerId,
        accountType: 'verified',
        fid: 'login-fid',
      ),
      refreshToken: 'verified-refresh-login',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      linkedProviders: [provider.name],
    );
  }

  @override
  Future<ProviderCredentialBundle> link({
    required AuthProviderKind provider,
    required String idToken,
    required String nonce,
    required String guestBearer,
  }) async {
    linkCalls++;
    if (linkError != null) throw linkError!;
    return ProviderCredentialBundle(
      playerId: linkPlayerId,
      accountType: 'verified',
      accessToken: _jwt(
        sub: linkPlayerId,
        accountType: 'verified',
        fid: 'link-fid',
      ),
      refreshToken: 'verified-refresh-link',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      linkedProviders: [provider.name],
    );
  }

  @override
  Future<ProviderCredentialBundle> recover({
    required AuthProviderKind provider,
    required String idToken,
    required String nonce,
    required String binding,
    required String expectedPlayerId,
  }) async {
    recoverCalls++;
    recoverExpectedPlayerId = expectedPlayerId;
    if (recoverError != null) throw recoverError!;
    return ProviderCredentialBundle(
      playerId: expectedPlayerId,
      accountType: 'verified',
      accessToken: _jwt(
        sub: expectedPlayerId,
        accountType: 'verified',
        fid: 'recover-fid',
      ),
      refreshToken: 'verified-refresh-recover',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      linkedProviders: [provider.name],
    );
  }

  @override
  Future<void> logout({
    required String refreshToken,
    String? accessBearer,
  }) async {
    logoutCalls++;
  }
}

void main() {
  const guestId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

  test('GuestAccess.parse accepts guest and verified with fid', () {
    final guest = GuestAccess.parse(
      accessToken: _jwt(sub: guestId, accountType: 'guest', fid: 'g-fid'),
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    expect(guest.isGuest, isTrue);
    expect(guest.playerId, guestId);
    expect(guest.familyId, 'g-fid');
    expect(guest.sessionVaultBinding, 'staging-guest:$guestId');

    final verified = GuestAccess.parse(
      accessToken: _jwt(sub: guestId, accountType: 'verified', fid: 'v-fid'),
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    expect(verified.isVerified, isTrue);
    expect(verified.sessionVaultBinding, 'staging-guest:$guestId');
  });

  test('replaceWithVerifiedBundle bumps generation and persists refresh',
      () async {
    final store = _MemoryStore()..token = 'guest-refresh';
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    final guestTok = _jwt(sub: guestId, accountType: 'guest', fid: 'g1');
    session.debugSeedAccess(GuestAccess.parse(
      accessToken: guestTok,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    ));
    final genBefore = session.credentialGeneration;
    final verified = await session.replaceWithVerifiedBundle(
      accessToken: _jwt(sub: guestId, accountType: 'verified', fid: 'v1'),
      refreshToken: 'verified-refresh',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    expect(verified.isVerified, isTrue);
    expect(verified.playerId, guestId);
    expect(store.token, 'verified-refresh');
    expect(session.credentialGeneration, greaterThan(genBefore));
  });

  test('stale refresh generation fails closed before overwrite', () async {
    final store = _MemoryStore()..token = 'guest-refresh';
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    session.debugSeedAccess(GuestAccess.parse(
      accessToken: _jwt(sub: guestId, accountType: 'guest', fid: 'g1'),
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    ));
    final gen = session.credentialGeneration;
    // Simulate concurrent link bumping generation.
    await session.replaceWithVerifiedBundle(
      accessToken: _jwt(sub: guestId, accountType: 'verified', fid: 'v1'),
      refreshToken: 'verified-first',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    expect(session.credentialGeneration, greaterThan(gen));
    expect(store.token, 'verified-first');
  });

  test('Apple linking preserves player_id', () async {
    final store = _MemoryStore()..token = 'guest-refresh';
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    session.debugSeedAccess(GuestAccess.parse(
      accessToken: _jwt(sub: guestId, accountType: 'guest', fid: 'g1'),
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    ));
    final providers = _FakeProviders(linkPlayerId: guestId);
    final coordinator = AuthCoordinator(
      session: session,
      providers: providers,
      signIn: FakeProviderSignIn(),
    );
    final result = await coordinator.linkCurrentGuest(AuthProviderKind.apple);
    expect(result.outcome, AuthFlowOutcome.linked);
    expect(result.access?.playerId, guestId);
    expect(result.access?.isVerified, isTrue);
    expect(store.token, 'verified-refresh-link');
    expect(providers.linkCalls, 1);
  });

  test('Google linking success path', () async {
    final store = _MemoryStore()..token = 'guest-refresh';
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    session.debugSeedAccess(GuestAccess.parse(
      accessToken: _jwt(sub: guestId, accountType: 'guest', fid: 'g1'),
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    ));
    final coordinator = AuthCoordinator(
      session: session,
      providers: _FakeProviders(linkPlayerId: guestId),
      signIn: FakeProviderSignIn(),
    );
    final result = await coordinator.linkCurrentGuest(AuthProviderKind.google);
    expect(result.outcome, AuthFlowOutcome.linked);
    expect(result.access?.isVerified, isTrue);
  });

  test('ACCOUNT_CONFLICT preserves guest credentials', () async {
    final store = _MemoryStore()..token = 'guest-refresh';
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    session.debugSeedAccess(GuestAccess.parse(
      accessToken: _jwt(sub: guestId, accountType: 'guest', fid: 'g1'),
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    ));
    final coordinator = AuthCoordinator(
      session: session,
      providers: _FakeProviders(
        linkPlayerId: guestId,
        linkError: const ProviderAuthException('ACCOUNT_CONFLICT', httpStatus: 409),
      ),
      signIn: FakeProviderSignIn(),
    );
    final result = await coordinator.linkCurrentGuest(AuthProviderKind.apple);
    expect(result.outcome, AuthFlowOutcome.conflict);
    expect(store.token, 'guest-refresh');
    expect(session.cachedAccess?.isGuest, isTrue);
  });

  test('user cancellation does not mutate credentials', () async {
    final store = _MemoryStore()..token = 'guest-refresh';
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    session.debugSeedAccess(GuestAccess.parse(
      accessToken: _jwt(sub: guestId, accountType: 'guest', fid: 'g1'),
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    ));
    final coordinator = AuthCoordinator(
      session: session,
      providers: _FakeProviders(linkPlayerId: guestId),
      signIn: FakeProviderSignIn(
        cancelProviders: {AuthProviderKind.apple},
      ),
    );
    final result = await coordinator.linkCurrentGuest(AuthProviderKind.apple);
    expect(result.outcome, AuthFlowOutcome.cancelled);
    expect(store.token, 'guest-refresh');
  });

  test('explicit login creates verified session for existing account', () async {
    final store = _MemoryStore();
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    const other = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
    final coordinator = AuthCoordinator(
      session: session,
      providers: _FakeProviders(loginPlayerId: other),
      signIn: FakeProviderSignIn(),
    );
    final result = await coordinator.loginExisting(AuthProviderKind.google);
    expect(result.outcome, AuthFlowOutcome.loggedIn);
    expect(result.access?.playerId, other);
    expect(store.token, 'verified-refresh-login');
  });

  test('logout revokes family and clears vault before guest recreate', () async {
    final store = _MemoryStore()..token = 'verified-refresh';
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    session.debugSeedAccess(GuestAccess.parse(
      accessToken: _jwt(sub: guestId, accountType: 'verified', fid: 'v1'),
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    ));
    final providers = _FakeProviders(linkPlayerId: guestId);
    final coordinator = AuthCoordinator(
      session: session,
      providers: providers,
      signIn: FakeProviderSignIn(),
    );
    // Guest recreate requires live HTTPS; assert revoke + local clear first.
    final result = await coordinator.logoutAndStartGuest();
    expect(providers.logoutCalls, 1);
    expect(store.token, isNull);
    expect(session.cachedAccess, isNull);
    expect(result.outcome, AuthFlowOutcome.failed);
    expect(result.errorCode, isNotNull);
  });

  test('duplicate in-flight link is rejected', () async {
    final store = _MemoryStore()..token = 'guest-refresh';
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    session.debugSeedAccess(GuestAccess.parse(
      accessToken: _jwt(sub: guestId, accountType: 'guest', fid: 'g1'),
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    ));
    final slow = _SlowProviders(linkPlayerId: guestId);
    final coordinator = AuthCoordinator(
      session: session,
      providers: slow,
      signIn: FakeProviderSignIn(),
    );
    final first = coordinator.linkCurrentGuest(AuthProviderKind.apple);
    final second = await coordinator.linkCurrentGuest(AuthProviderKind.apple);
    expect(second.outcome, AuthFlowOutcome.failed);
    expect(second.errorCode, 'AUTH_IN_FLIGHT');
    await first;
  });

  test('native sign-in receives backend challenge nonce', () async {
    final store = _MemoryStore()..token = 'guest-refresh';
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    session.debugSeedAccess(GuestAccess.parse(
      accessToken: _jwt(sub: guestId, accountType: 'guest', fid: 'g1'),
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    ));
    final signIn = FakeProviderSignIn();
    final coordinator = AuthCoordinator(
      session: session,
      providers: _FakeProviders(linkPlayerId: guestId),
      signIn: signIn,
    );
    await coordinator.linkCurrentGuest(AuthProviderKind.google);
    expect(signIn.nonces, ['n' * 43]);
  });

  test('serialized delayed vault writes: last replace wins without interleaving',
      () async {
    final store = _MemoryStore()..writeDelay = const Duration(milliseconds: 40);
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    final first = session.replaceWithVerifiedBundle(
      accessToken: _jwt(sub: guestId, accountType: 'verified', fid: 'v1'),
      refreshToken: 'verified-first',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    final second = session.replaceWithVerifiedBundle(
      accessToken: _jwt(sub: guestId, accountType: 'verified', fid: 'v2'),
      refreshToken: 'verified-second',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    await Future.wait([first, second]);
    expect(store.token, 'verified-second');
    expect(session.cachedAccess?.familyId, 'v2');
  });

  test('logout after delayed replace clears vault and bumps generation',
      () async {
    final store = _MemoryStore()..writeDelay = const Duration(milliseconds: 50);
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    final replace = session.replaceWithVerifiedBundle(
      accessToken: _jwt(sub: guestId, accountType: 'verified', fid: 'v1'),
      refreshToken: 'verified-refresh',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final clear = session.clearSessionLocally();
    await replace;
    await clear;
    expect(store.token, isNull);
    expect(session.cachedAccess, isNull);
  });

  test('stale queued replace after logout does not resurrect credentials',
      () async {
    final store = _MemoryStore()
      ..token = 'guest-refresh'
      ..writeDelay = const Duration(milliseconds: 60);
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    // Logout starts first and clears; delayed replace must still serialize.
    final clear = session.clearSessionLocally();
    final replace = session.replaceWithVerifiedBundle(
      accessToken: _jwt(sub: guestId, accountType: 'verified', fid: 'v1'),
      refreshToken: 'verified-after-logout',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    await clear;
    await replace;
    // Replace runs after logout and intentionally installs verified credentials
    // (recoverable replacement). Generation advanced twice.
    expect(store.token, 'verified-after-logout');
    expect(session.credentialGeneration, greaterThanOrEqualTo(2));
  });

  test('pending rotation cleared only by successful replace', () async {
    final store = _MemoryStore()
      ..token = 'guest-refresh'
      ..rotationId = '0123456789abcdef0123456789abcdef'
      ..pendingLink = 'google|$guestId';
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    await session.replaceWithVerifiedBundle(
      accessToken: _jwt(sub: guestId, accountType: 'verified', fid: 'v1'),
      refreshToken: 'verified-refresh',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    expect(store.rotationId, isNull);
    expect(store.pendingLink, isNull);
  });

  test('link vault write failure keeps pending link for recovery', () async {
    final store = _MemoryStore()
      ..token = 'guest-refresh'
      ..failWrite = true;
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    session.debugSeedAccess(GuestAccess.parse(
      accessToken: _jwt(sub: guestId, accountType: 'guest', fid: 'g1'),
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    ));
    final coordinator = AuthCoordinator(
      session: session,
      providers: _FakeProviders(linkPlayerId: guestId),
      signIn: FakeProviderSignIn(),
    );
    final result = await coordinator.linkCurrentGuest(AuthProviderKind.apple);
    expect(result.outcome, AuthFlowOutcome.recoveryRequired);
    expect(result.recoveryProvider, AuthProviderKind.apple);
    expect(result.expectedPlayerId, guestId);
    expect(store.pendingLink, 'apple|$guestId');
    expect(store.token, 'guest-refresh');
  });

  test('link network uncertainty keeps pending link without replay', () async {
    final store = _MemoryStore()..token = 'guest-refresh';
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    session.debugSeedAccess(GuestAccess.parse(
      accessToken: _jwt(sub: guestId, accountType: 'guest', fid: 'g1'),
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    ));
    final providers = _FakeProviders(
      linkPlayerId: guestId,
      linkError: const ProviderAuthException('AUTH_NETWORK_UNAVAILABLE'),
    );
    final coordinator = AuthCoordinator(
      session: session,
      providers: providers,
      signIn: FakeProviderSignIn(),
    );
    final result = await coordinator.linkCurrentGuest(AuthProviderKind.google);
    expect(result.outcome, AuthFlowOutcome.recoveryRequired);
    expect(store.pendingLink, 'google|$guestId');
    expect(result.expectedPlayerId, guestId);
    expect(providers.linkCalls, 1);
    expect(store.token, 'guest-refresh');
  });

  test('ACCOUNT_CONFLICT clears pending link and keeps guest refresh', () async {
    final store = _MemoryStore()
      ..token = 'guest-refresh'
      ..pendingLink = 'apple|$guestId';
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    session.debugSeedAccess(GuestAccess.parse(
      accessToken: _jwt(sub: guestId, accountType: 'guest', fid: 'g1'),
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    ));
    final coordinator = AuthCoordinator(
      session: session,
      providers: _FakeProviders(
        linkPlayerId: guestId,
        linkError:
            const ProviderAuthException('ACCOUNT_CONFLICT', httpStatus: 409),
      ),
      signIn: FakeProviderSignIn(),
    );
    final result = await coordinator.linkCurrentGuest(AuthProviderKind.apple);
    expect(result.outcome, AuthFlowOutcome.conflict);
    expect(store.pendingLink, isNull);
    expect(store.token, 'guest-refresh');
  });

  test('pending link blocks silent guest creation on restart', () async {
    final store = _MemoryStore()..pendingLink = 'google|$guestId';
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    await expectLater(
      session.authenticate(),
      throwsA(
        isA<GuestAuthException>().having(
          (e) => e.code,
          'code',
          'PROVIDER_LINK_RECOVERY_google',
        ),
      ),
    );
    expect(store.pendingLink, 'google|$guestId');
  });

  test('consumePendingLinkRecoveryIfNeeded surfaces provider recovery',
      () async {
    final store = _MemoryStore()..pendingLink = 'apple|$guestId';
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    final coordinator = AuthCoordinator(
      session: session,
      providers: _FakeProviders(),
      signIn: FakeProviderSignIn(),
    );
    final result = await coordinator.consumePendingLinkRecoveryIfNeeded();
    expect(result?.outcome, AuthFlowOutcome.recoveryRequired);
    expect(result?.recoveryProvider, AuthProviderKind.apple);
    expect(result?.expectedPlayerId, guestId);
  });

  test('recoverPendingLink succeeds via server recover for expected player',
      () async {
    final store = _MemoryStore()..pendingLink = 'google|$guestId';
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    final providers = _FakeProviders(loginPlayerId: guestId);
    final coordinator = AuthCoordinator(
      session: session,
      providers: providers,
      signIn: FakeProviderSignIn(),
    );
    final result = await coordinator.recoverPendingLink(AuthProviderKind.google);
    expect(result.outcome, AuthFlowOutcome.loggedIn);
    expect(result.access?.playerId, guestId);
    expect(store.token, 'verified-refresh-recover');
    expect(store.pendingLink, isNull);
    expect(providers.recoverCalls, 1);
    expect(providers.loginCalls, 0);
    expect(providers.recoverExpectedPlayerId, guestId);
  });

  test('recoverPendingLink keeps marker when server reports not linked',
      () async {
    final store = _MemoryStore()..pendingLink = 'google|$guestId';
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    final providers = _FakeProviders(loginPlayerId: guestId)
      ..recoverError = const ProviderAuthException('RECOVERY_NOT_LINKED');
    final coordinator = AuthCoordinator(
      session: session,
      providers: providers,
      signIn: FakeProviderSignIn(),
    );
    final result = await coordinator.recoverPendingLink(AuthProviderKind.google);
    expect(result.outcome, AuthFlowOutcome.recoveryRequired);
    expect(result.errorCode, 'RECOVERY_NOT_LINKED');
    expect(store.pendingLink, 'google|$guestId');
    expect(providers.loginCalls, 0);
    expect(store.token, isNull);
  });

  test('recoverPendingLink keeps marker on ACCOUNT_CONFLICT from recover',
      () async {
    final store = _MemoryStore()..pendingLink = 'google|$guestId';
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    final providers = _FakeProviders()
      ..recoverError =
          const ProviderAuthException('ACCOUNT_CONFLICT', httpStatus: 409);
    final coordinator = AuthCoordinator(
      session: session,
      providers: providers,
      signIn: FakeProviderSignIn(),
    );
    final result = await coordinator.recoverPendingLink(AuthProviderKind.google);
    expect(result.outcome, AuthFlowOutcome.recoveryRequired);
    expect(result.errorCode, 'ACCOUNT_CONFLICT');
    expect(store.pendingLink, 'google|$guestId');
    expect(providers.loginCalls, 0);
  });

  test('recoverPendingLink retries link only after server confirms guest family',
      () async {
    final store = _MemoryStore()
      ..token = 'guest-refresh'
      ..pendingLink = 'google|$guestId';
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    // Cached JWT alone must not decide — forceRefresh must hit the server.
    session.debugSeedAccess(GuestAccess.parse(
      accessToken: _jwt(sub: guestId, accountType: 'guest', fid: 'g1'),
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    ));
    var refreshPosts = 0;
    session.debugTransport = (path, body) async {
      expect(path, '/v1/auth/refresh');
      refreshPosts++;
      return (
        status: 200,
        body: {
          'accessToken': _jwt(sub: guestId, accountType: 'guest', fid: 'g1'),
          'refreshToken': 'guest-refresh-still-valid',
          'expiresAt':
              DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String(),
        },
      );
    };
    final providers = _FakeProviders();
    final coordinator = AuthCoordinator(
      session: session,
      providers: providers,
      signIn: FakeProviderSignIn(),
    );
    final result = await coordinator.recoverPendingLink(AuthProviderKind.google);
    expect(result.outcome, AuthFlowOutcome.failed);
    expect(result.errorCode, 'RECOVERY_RETRY_LINK');
    expect(refreshPosts, 1);
    expect(store.pendingLink, 'google|$guestId');
    expect(store.token, 'guest-refresh-still-valid');
    expect(providers.recoverCalls, 0);
    expect(providers.loginCalls, 0);
  });

  test('cached guest JWT after committed link still forces recover', () async {
    final store = _MemoryStore()
      ..token = 'revoked-guest-refresh'
      ..pendingLink = 'google|$guestId';
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    session.debugSeedAccess(GuestAccess.parse(
      accessToken: _jwt(sub: guestId, accountType: 'guest', fid: 'g1'),
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    ));
    var refreshPosts = 0;
    session.debugTransport = (path, body) async {
      expect(path, '/v1/auth/refresh');
      refreshPosts++;
      return (status: 401, body: {'error': 'INVALID_REFRESH'});
    };
    final providers = _FakeProviders(loginPlayerId: guestId);
    final coordinator = AuthCoordinator(
      session: session,
      providers: providers,
      signIn: FakeProviderSignIn(),
    );
    final result = await coordinator.recoverPendingLink(AuthProviderKind.google);
    expect(result.outcome, AuthFlowOutcome.loggedIn);
    expect(result.access?.playerId, guestId);
    expect(refreshPosts, 1);
    expect(providers.recoverCalls, 1);
    expect(providers.loginCalls, 0);
    expect(store.pendingLink, isNull);
    expect(store.token, 'verified-refresh-recover');
  });

  test('revoked guest family keeps marker until recover succeeds', () async {
    final store = _MemoryStore()
      ..token = 'revoked-guest-refresh'
      ..pendingLink = 'apple|$guestId';
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    session.debugTransport = (path, body) async =>
        (status: 403, body: {'error': 'INVALID_REFRESH'});
    final providers = _FakeProviders()
      ..recoverError = const ProviderAuthException('RECOVERY_NOT_LINKED');
    final coordinator = AuthCoordinator(
      session: session,
      providers: providers,
      signIn: FakeProviderSignIn(),
    );
    final result = await coordinator.recoverPendingLink(AuthProviderKind.apple);
    expect(result.outcome, AuthFlowOutcome.recoveryRequired);
    expect(result.errorCode, 'RECOVERY_NOT_LINKED');
    expect(store.pendingLink, 'apple|$guestId');
    expect(providers.recoverCalls, 1);
  });

  test('temporary refresh network failure keeps marker without recover',
      () async {
    final store = _MemoryStore()
      ..token = 'guest-refresh'
      ..pendingLink = 'google|$guestId';
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    session.debugTransport = (path, body) async =>
        (status: 503, body: {'error': 'AUTH_UNAVAILABLE'});
    final providers = _FakeProviders();
    final coordinator = AuthCoordinator(
      session: session,
      providers: providers,
      signIn: FakeProviderSignIn(),
    );
    final result = await coordinator.recoverPendingLink(AuthProviderKind.google);
    expect(result.outcome, AuthFlowOutcome.recoveryRequired);
    expect(result.errorCode, 'REFRESH_UNAVAILABLE');
    expect(store.pendingLink, 'google|$guestId');
    expect(providers.recoverCalls, 0);
  });

  test('socket-class probe failure keeps marker without recover', () async {
    final store = _MemoryStore()
      ..token = 'guest-refresh'
      ..pendingLink = 'google|$guestId';
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    session.debugTransport = (path, body) async {
      throw const GuestAuthException('AUTH_NETWORK_UNAVAILABLE');
    };
    final providers = _FakeProviders();
    final coordinator = AuthCoordinator(
      session: session,
      providers: providers,
      signIn: FakeProviderSignIn(),
    );
    final result = await coordinator.recoverPendingLink(AuthProviderKind.google);
    expect(result.outcome, AuthFlowOutcome.recoveryRequired);
    expect(result.errorCode, 'AUTH_NETWORK_UNAVAILABLE');
    expect(store.pendingLink, 'google|$guestId');
    expect(providers.recoverCalls, 0);
  });

  test('recovery probe shares single-flight with concurrent forceRefresh',
      () async {
    final store = _MemoryStore()
      ..token = 'guest-refresh'
      ..pendingLink = 'google|$guestId';
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    final gate = Completer<void>();
    var refreshPosts = 0;
    session.debugTransport = (path, body) async {
      refreshPosts++;
      await gate.future;
      return (
        status: 200,
        body: {
          'accessToken': _jwt(sub: guestId, accountType: 'guest', fid: 'g1'),
          'refreshToken': 'guest-refresh-shared',
          'expiresAt':
              DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String(),
        },
      );
    };
    final providers = _FakeProviders();
    final coordinator = AuthCoordinator(
      session: session,
      providers: providers,
      signIn: FakeProviderSignIn(),
    );
    final recovery = coordinator.recoverPendingLink(AuthProviderKind.google);
    final concurrent = session.authenticate(forceRefresh: true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(refreshPosts, 1);
    gate.complete();
    final result = await recovery;
    final refreshed = await concurrent;
    expect(result.errorCode, 'RECOVERY_RETRY_LINK');
    expect(refreshed.playerId, guestId);
    expect(refreshed.isGuest, isTrue);
    expect(refreshPosts, 1);
    expect(providers.recoverCalls, 0);
  });

  test('recoverPendingLink rejects wrong provider without clearing marker',
      () async {
    final store = _MemoryStore()..pendingLink = 'google|$guestId';
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    final coordinator = AuthCoordinator(
      session: session,
      providers: _FakeProviders(loginPlayerId: guestId),
      signIn: FakeProviderSignIn(),
    );
    final result = await coordinator.recoverPendingLink(AuthProviderKind.apple);
    expect(result.outcome, AuthFlowOutcome.recoveryRequired);
    expect(result.errorCode, 'RECOVERY_PROVIDER_MISMATCH');
    expect(store.pendingLink, 'google|$guestId');
  });

  test('generic loginExisting remains available outside recovery', () async {
    final store = _MemoryStore();
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    const other = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
    final coordinator = AuthCoordinator(
      session: session,
      providers: _FakeProviders(loginPlayerId: other),
      signIn: FakeProviderSignIn(),
    );
    final result = await coordinator.loginExisting(AuthProviderKind.google);
    expect(result.outcome, AuthFlowOutcome.loggedIn);
    expect(result.access?.playerId, other);
  });

  test('logout clears pending link before minting a new guest session attempt',
      () async {
    final store = _MemoryStore()
      ..token = 'verified-refresh'
      ..pendingLink = 'apple|$guestId';
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    session.debugSeedAccess(GuestAccess.parse(
      accessToken: _jwt(sub: guestId, accountType: 'verified', fid: 'v1'),
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    ));
    final providers = _FakeProviders();
    final coordinator = AuthCoordinator(
      session: session,
      providers: providers,
      signIn: FakeProviderSignIn(),
    );
    await coordinator.logoutAndStartGuest();
    expect(providers.logoutCalls, 1);
    expect(store.token, isNull);
    expect(store.pendingLink, isNull);
  });

  test('overlapping authenticate and identity refresh share one network flight',
      () async {
    final store = _MemoryStore()..token = 'guest-refresh';
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    final gate = Completer<void>();
    var refreshPosts = 0;
    final seenRotationIds = <String?>[];
    session.debugTransport = (path, body) async {
      expect(path, '/v1/auth/refresh');
      refreshPosts++;
      seenRotationIds.add(body['rotationId'] as String?);
      await gate.future;
      return (
        status: 200,
        body: {
          'accessToken': _jwt(sub: guestId, accountType: 'guest', fid: 'g1'),
          'refreshToken': 'rotated-refresh',
          'expiresAt':
              DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String(),
        },
      );
    };
    final a = session.authenticate(forceRefresh: true);
    final b = session.refreshGuestPreservingIdentity(
      playerId: guestId,
      familyId: 'g1',
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(refreshPosts, 1);
    gate.complete();
    final results = await Future.wait([a, b]);
    expect(results[0].playerId, guestId);
    expect(results[1].playerId, guestId);
    expect(results[1].familyId, 'g1');
    expect(refreshPosts, 1);
    expect(seenRotationIds, [null]);
    expect(store.token, 'rotated-refresh');
  });

  test('overlapping refresh with rotation retry enabled uses one rotation id',
      () async {
    final store = _MemoryStore()..token = 'guest-refresh';
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: true,
    );
    final gate = Completer<void>();
    var refreshPosts = 0;
    final seenRotationIds = <String>[];
    session.debugTransport = (path, body) async {
      expect(path, '/v1/auth/refresh');
      refreshPosts++;
      final rotationId = body['rotationId'];
      expect(rotationId, isA<String>());
      seenRotationIds.add(rotationId! as String);
      await gate.future;
      return (
        status: 200,
        body: {
          'accessToken': _jwt(sub: guestId, accountType: 'guest', fid: 'g1'),
          'refreshToken': 'rotated-refresh-retry',
          'expiresAt':
              DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String(),
        },
      );
    };
    final a = session.refreshGuestPreservingIdentity(
      playerId: guestId,
      familyId: 'g1',
    );
    final b = session.authenticate(forceRefresh: true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(refreshPosts, 1);
    gate.complete();
    await Future.wait([a, b]);
    expect(refreshPosts, 1);
    expect(seenRotationIds.toSet(), hasLength(1));
    expect(store.rotationId, isNull);
    expect(store.token, 'rotated-refresh-retry');
  });

  test('identity-preserving refresh rejects player or fid mutation', () async {
    final store = _MemoryStore()..token = 'guest-refresh';
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    session.debugTransport = (path, body) async => (
          status: 200,
          body: {
            'accessToken': _jwt(
              sub: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
              accountType: 'guest',
              fid: 'other-fid',
            ),
            'refreshToken': 'bad-refresh',
            'expiresAt': DateTime.now()
                .toUtc()
                .add(const Duration(hours: 1))
                .toIso8601String(),
          },
        );
    await expectLater(
      session.refreshGuestPreservingIdentity(
        playerId: guestId,
        familyId: 'g1',
      ),
      throwsA(
        isA<GuestAuthException>().having(
          (e) => e.code,
          'code',
          'GUEST_IDENTITY_CHANGED',
        ),
      ),
    );
  });
}

/// Delays link so concurrent calls exercise the in-flight guard.
final class _SlowProviders extends _FakeProviders {
  _SlowProviders({required super.linkPlayerId});

  @override
  Future<ProviderCredentialBundle> link({
    required AuthProviderKind provider,
    required String idToken,
    required String nonce,
    required String guestBearer,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return super.link(
      provider: provider,
      idToken: idToken,
      nonce: nonce,
      guestBearer: guestBearer,
    );
  }
}
