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
