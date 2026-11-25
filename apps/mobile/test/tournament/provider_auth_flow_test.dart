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
    if (fid != null) 'fid': fid,
  };
  final payload = base64Url
      .encode(utf8.encode(jsonEncode(claims)))
      .replaceAll('=', '');
  return '$header.$payload.sig';
}

final class _MemoryStore implements GuestCredentialStore {
  String? token;
  String? rotationId;
  @override
  Future<String?> readRefreshToken() async => token;
  @override
  Future<void> writeRefreshToken(String value) async => token = value;
  @override
  Future<void> clearRefreshToken() async => token = null;
  @override
  Future<String?> readPendingRotationId() async => rotationId;
  @override
  Future<void> writePendingRotationId(String id) async => rotationId = id;
  @override
  Future<void> clearPendingRotationId() async => rotationId = null;
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
  var challengeCalls = 0;

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
  Future<void> logout({
    required String refreshToken,
    String? accessBearer,
  }) async {}
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
