import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/tournament/guest_auth.dart';
import 'package:puzzle_duel_mobile/tournament/guest_secure_store.dart';

void main() {
  test('legacy credentials retain their existing Keychain key names', () {
    final keys = StagingGuestCredentialKeys.forSlot(StagingGuestSlot.legacy);
    expect(keys.refresh, 'pzd.staging.guest.refresh.v1');
    expect(keys.rotation, 'pzd.staging.guest.rotation.v1');
  });

  test('new Player A does not read or overwrite legacy or Player B slots', () {
    final a = StagingGuestCredentialKeys.forSlot(StagingGuestSlot.playerA);
    final b = StagingGuestCredentialKeys.forSlot(StagingGuestSlot.playerB);
    final old = StagingGuestCredentialKeys.forSlot(StagingGuestSlot.legacy);
    expect({
      a.refresh, a.rotation, b.refresh, b.rotation,
      old.refresh, old.rotation,
    }, hasLength(6));
    expect(a.refresh, 'pzd.staging.guest.player-a.refresh.v1');
    expect(a.rotation, 'pzd.staging.guest.player-a.rotation.v1');
    expect(StagingGuestCredentialKeys.forSlot(StagingGuestSlot.playerA).refresh,
        a.refresh); // survives a rebuild/process kill
  });

  test('explicit slots parse while unrecognized inputs fail closed', () {
    expect(StagingGuestSlot.parse('legacy'), StagingGuestSlot.legacy);
    expect(StagingGuestSlot.parse('player-a'), StagingGuestSlot.playerA);
    expect(StagingGuestSlot.parse('player-b'), StagingGuestSlot.playerB);
    expect(() => StagingGuestSlot.parse(''), throwsA(isA<GuestAuthException>()));
    expect(() => StagingGuestSlot.parse('guest-b'), throwsA(isA<GuestAuthException>()));
  });

  test('slot constructor remains non-destructive to legacy identity', () {
    const legacy = SecureGuestCredentialStore();
    const playerA = SecureGuestCredentialStore(slot: StagingGuestSlot.playerA);
    expect(legacy.slot, StagingGuestSlot.legacy);
    expect(playerA.slot, StagingGuestSlot.playerA);
  });
}
