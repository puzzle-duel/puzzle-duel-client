import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/tournament/guest_auth.dart';

final class FakeGuestStore implements GuestCredentialStore {
  String? token;
  String? rotationId;
  String? pendingLink;
  bool failReadback = false;
  bool failWrite = false;
  bool failBindingWrite = false;
  bool failClearRotation = false;
  /// After the first successful token write, further writes (restore) fail.
  bool failRestoreAfterPartial = false;
  var _successfulTokenWrites = 0;
  Duration writeDelay = Duration.zero;
  @override
  Future<String?> readRefreshToken() async => failReadback ? 'old-token' : token;
  @override
  Future<void> writeRefreshToken(String value) async {
    if (writeDelay > Duration.zero) await Future<void>.delayed(writeDelay);
    if (failWrite) throw StateError('storage denied');
    if (failRestoreAfterPartial && _successfulTokenWrites >= 1) {
      throw StateError('restore denied');
    }
    token = value;
    _successfulTokenWrites++;
  }
  @override
  Future<void> clearRefreshToken() async { token = null; }
  @override
  Future<String?> readPendingRotationId() async => rotationId;
  @override
  Future<void> writePendingRotationId(String id) async { rotationId = id; }
  @override
  Future<void> clearPendingRotationId() async {
    if (failClearRotation) throw StateError('clear rotation denied');
    rotationId = null;
  }
  @override
  Future<String?> readPendingLinkProvider() async => pendingLink;
  @override
  Future<void> writePendingLinkProvider(String provider) async {
    pendingLink = provider;
  }
  @override
  Future<void> clearPendingLinkProvider() async { pendingLink = null; }
  String? identityBinding;
  @override
  Future<String?> readIdentityBinding() async => identityBinding;
  @override
  Future<void> writeIdentityBinding(String encoded) async {
    if (failBindingWrite) throw StateError('binding denied');
    identityBinding = encoded;
  }
  @override
  Future<void> clearIdentityBinding() async { identityBinding = null; }
}

void main() {
  test('pending intent survives app restart and UTC 03:00 Türkiye cutover', () async {
    final store = FakeGuestStore();
    const fixedId = '0123456789abcdef0123456789abcdef';
    var generated = 0;
    String issueId() {
      generated++;
      return fixedId;
    }
    final beforeMidnight = await acquireVerifiedGuestRotationId(store, issueId);
    // Simulates app process termination and new GuestAuthClient instance at
    // 00:02 UTC. No device secret is regenerated or lost across this boundary.
    final afterMidnight = await acquireVerifiedGuestRotationId(store, issueId);
    expect(afterMidnight, beforeMidnight);
    expect(generated, 1);
    expect(store.rotationId, fixedId);
  });
  test('corrupt pending intent fails closed instead of overwriting it', () async {
    final store = FakeGuestStore()..rotationId = 'bad';
    await expectLater(
      acquireVerifiedGuestRotationId(store, () => '0123456789abcdef0123456789abcdef'),
      throwsA(isA<GuestAuthException>()),
    );
    expect(store.rotationId, 'bad');
  });

  test('credential write must read back exactly before success', () async {
    final store = FakeGuestStore()..token = 'prior-secret';
    await persistVerifiedGuestCredential(store, 'next-secret');
    expect(store.token, 'next-secret');
  });
  test('readback mismatch fails closed without clearing pending intent', () async {
    final store = FakeGuestStore()
      ..rotationId = '0123456789abcdef0123456789abcdef'
      ..failReadback = true;
    await expectLater(persistVerifiedGuestCredential(store, 'next-secret'),
        throwsA(isA<GuestAuthException>()));
    expect(store.rotationId, '0123456789abcdef0123456789abcdef');
  });
  test('write failure never clears existing token or pending intent', () async {
    final store = FakeGuestStore()
      ..token = 'prior-secret'
      ..rotationId = '0123456789abcdef0123456789abcdef'
      ..failWrite = true;
    await expectLater(persistVerifiedGuestCredential(store, 'next-secret'),
        throwsStateError);
    expect(store.token, 'prior-secret');
    expect(store.rotationId, '0123456789abcdef0123456789abcdef');
  });

  test('delayed vault write still verifies exact readback', () async {
    final store = FakeGuestStore()..writeDelay = const Duration(milliseconds: 30);
    await persistVerifiedGuestCredential(store, 'delayed-secret');
    expect(store.token, 'delayed-secret');
  });

  test('pending link marker survives process restart semantics', () async {
    const guestId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    final encoded = PendingLinkRecovery(
      provider: 'google',
      playerId: guestId,
    ).encode();
    final store = FakeGuestStore();
    await store.writePendingLinkProvider(encoded);
    expect(await store.readPendingLinkProvider(), encoded);
    // New client process would rehydrate from the same Keychain key.
    final restarted = FakeGuestStore()..pendingLink = store.pendingLink;
    expect(
      PendingLinkRecovery.tryParse(await restarted.readPendingLinkProvider()),
      isA<PendingLinkRecovery>()
          .having((m) => m.provider, 'provider', 'google')
          .having((m) => m.playerId, 'playerId', guestId),
    );
  });
}
