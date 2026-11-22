import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/tournament/guest_auth.dart';

final class FakeGuestStore implements GuestCredentialStore {
  String? token;
  String? rotationId;
  bool failReadback = false;
  bool failWrite = false;
  @override
  Future<String?> readRefreshToken() async => failReadback ? 'old-token' : token;
  @override
  Future<void> writeRefreshToken(String value) async {
    if (failWrite) throw StateError('storage denied');
    token = value;
  }
  @override
  Future<void> clearRefreshToken() async { token = null; }
  @override
  Future<String?> readPendingRotationId() async => rotationId;
  @override
  Future<void> writePendingRotationId(String id) async { rotationId = id; }
  @override
  Future<void> clearPendingRotationId() async { rotationId = null; }
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
}
