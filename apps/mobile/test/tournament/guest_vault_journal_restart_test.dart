import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/tournament/guest_auth.dart';
import 'package:puzzle_duel_mobile/tournament/guest_session_recovery.dart';
import 'package:puzzle_duel_mobile/tournament/practice_identity.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_uat_app.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';

import 'guest_refresh_durability_test.dart' show FakeGuestStore;
import 'tournament_command_test.dart' show ScriptedUatApi;

String _jwt({
  required String playerId,
  required String familyId,
  String accountType = 'guest',
}) {
  final header = base64Url.encode(utf8.encode('{"alg":"none"}'));
  final payload = base64Url.encode(utf8.encode(jsonEncode({
    'iss': 'https://staging.puzzle-duel.app',
    'aud': 'puzzle-duel-api',
    'sub': playerId,
    'fid': familyId,
    'account_type': accountType,
  })));
  return '$header.$payload.sig';
}

GuestVaultJournal _journal({
  required String nextRefresh,
  required String nextBinding,
  bool clearRotation = true,
  GuestVaultPendingLinkAction pendingLinkAction =
      GuestVaultPendingLinkAction.keep,
  String? nextPendingLink,
}) {
  return GuestVaultJournal(
    nextRefresh: nextRefresh,
    nextBinding: nextBinding,
    clearRotation: clearRotation,
    pendingLinkAction: pendingLinkAction,
    nextPendingLink: nextPendingLink,
  );
}

/// Builds a torn vault as if the OS killed the process mid-commit — no catch
/// / rollback path runs. A new [GuestAuthClient] must reconcile from journal.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const oldToken = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const newToken = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const oldGuestBinding =
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa|bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb|guest';
  const newGuestBinding =
      'cccccccc-cccc-cccc-cccc-cccccccccccc|dddddddd-dddd-dddd-dddd-dddddddddddd|guest';
  const newVerifiedBinding =
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa|bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb|verified';

  test('journal round-trip omits empty pending and survives parse', () {
    final encoded = _journal(
      nextRefresh: newToken,
      nextBinding: newVerifiedBinding,
      pendingLinkAction: GuestVaultPendingLinkAction.clear,
    ).encode();
    final parsed = GuestVaultJournal.tryParse(encoded);
    expect(parsed?.nextRefresh, newToken);
    expect(parsed?.nextBinding, newVerifiedBinding);
    expect(parsed?.pendingLinkAction, GuestVaultPendingLinkAction.clear);
    expect(GuestVaultJournal.tryParse(null), isNull);
    expect(GuestVaultJournal.tryParse('garbage'), isNull);
  });

  test('legacy vault without journal authenticates refresh path', () async {
    final store = FakeGuestStore()
      ..token = oldToken
      ..identityBinding = oldGuestBinding;
    final auth = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    auth.debugTransport = (path, body) async {
      expect(path, '/v1/auth/refresh');
      return (
        status: 200,
        body: {
          'accessToken': _jwt(
            playerId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            familyId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
          ),
          'refreshToken': newToken,
          'expiresAt': DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .toIso8601String(),
        },
      );
    };
    final access = await auth.authenticate(forceRefresh: true);
    expect(access.playerId, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
    expect(store.token, newToken);
    expect(store.vaultJournal, isNull);
    expect(
      GuestIdentityBinding.tryParse(store.identityBinding)?.accountType,
      AccountType.guest,
    );
  });

  test('kill before credential commit: prior vault unchanged after restart',
      () async {
    final store = FakeGuestStore()
      ..token = oldToken
      ..identityBinding = oldGuestBinding
      ..rotationId = '0123456789abcdef0123456789abcdef';
    // Journal never written — process died before commit started.
    expect(store.vaultJournal, isNull);

    final restarted = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    await restarted.reconcilePersistedVault();
    expect(store.token, oldToken);
    expect(store.identityBinding, oldGuestBinding);
    expect(store.rotationId, '0123456789abcdef0123456789abcdef');
    expect(restarted.vaultCorrupt, isFalse);
  });

  test('kill after refresh token write: restart completes journal intent',
      () async {
    final journal = _journal(
      nextRefresh: newToken,
      nextBinding: newGuestBinding,
      pendingLinkAction: GuestVaultPendingLinkAction.keep,
    );
    final store = FakeGuestStore()
      ..token = newToken // live key advanced
      ..identityBinding = oldGuestBinding // binding still old
      ..rotationId = '0123456789abcdef0123456789abcdef'
      ..vaultJournal = journal.encode();

    final restarted = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    await restarted.reconcilePersistedVault();
    expect(store.token, newToken);
    expect(store.identityBinding, newGuestBinding);
    expect(store.rotationId, isNull);
    expect(store.vaultJournal, isNull);
    expect(
      GuestIdentityBinding.tryParse(store.identityBinding)?.playerId,
      'cccccccc-cccc-cccc-cccc-cccccccccccc',
    );
  });

  test('kill after identity binding write: restart clears rotation via journal',
      () async {
    final journal = _journal(
      nextRefresh: newToken,
      nextBinding: newVerifiedBinding,
      pendingLinkAction: GuestVaultPendingLinkAction.clear,
    );
    final store = FakeGuestStore()
      ..token = newToken
      ..identityBinding = newVerifiedBinding
      ..rotationId = 'fedcba9876543210fedcba9876543210'
      ..pendingLink = 'google|aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      ..vaultJournal = journal.encode();

    final restarted = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    await restarted.reconcilePersistedVault();
    expect(store.token, newToken);
    expect(store.identityBinding, newVerifiedBinding);
    expect(store.rotationId, isNull);
    expect(store.pendingLink, isNull);
    expect(store.vaultJournal, isNull);
    expect(
      GuestIdentityBinding.tryParse(store.identityBinding)?.accountType,
      AccountType.verified,
    );
  });

  test('kill during pending rotation cleanup: restart finishes clear', () async {
    final journal = _journal(
      nextRefresh: newToken,
      nextBinding: newGuestBinding,
    );
    final store = FakeGuestStore()
      ..token = newToken
      ..identityBinding = newGuestBinding
      ..rotationId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' // clear not finished
      ..vaultJournal = journal.encode();

    final restarted = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    await restarted.reconcilePersistedVault();
    expect(store.rotationId, isNull);
    expect(store.vaultJournal, isNull);
  });

  test('kill during pending provider link cleanup: restart clears link',
      () async {
    final journal = _journal(
      nextRefresh: newToken,
      nextBinding: newVerifiedBinding,
      pendingLinkAction: GuestVaultPendingLinkAction.clear,
    );
    final store = FakeGuestStore()
      ..token = newToken
      ..identityBinding = newVerifiedBinding
      ..rotationId = null
      ..pendingLink = 'apple|aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      ..vaultJournal = journal.encode();

    final restarted = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    await restarted.reconcilePersistedVault();
    expect(store.pendingLink, isNull);
    expect(store.vaultJournal, isNull);
    final recovery =
        await restarted.captureSessionRecovery('GUEST_RECOVERY_REQUIRED');
    expect(recovery.binding?.accountType, AccountType.verified);
    expect(recovery.allowsExplicitNewGuest, isFalse);
  });

  test('kill after commit before journal cleanup: restart clears journal only',
      () async {
    final journal = _journal(
      nextRefresh: newToken,
      nextBinding: newGuestBinding,
    );
    final store = FakeGuestStore()
      ..token = newToken
      ..identityBinding = newGuestBinding
      ..rotationId = null
      ..vaultJournal = journal.encode(); // live complete, journal uncleared

    final restarted = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    await restarted.reconcilePersistedVault();
    expect(store.token, newToken);
    expect(store.identityBinding, newGuestBinding);
    expect(store.vaultJournal, isNull);
  });

  test('corrupt journal fails closed without minting guest', () async {
    final store = FakeGuestStore()
      ..token = oldToken
      ..identityBinding = oldGuestBinding
      ..vaultJournal = 'v1:not-valid-base64!!!';
    final auth = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    var guestCreates = 0;
    auth.debugTransport = (path, body) async {
      if (path == '/v1/auth/guest') guestCreates++;
      fail('must not hit network while vault corrupt');
    };
    await expectLater(
      auth.authenticate(),
      throwsA(isA<GuestAuthException>().having(
        (e) => e.code,
        'code',
        'SECURE_STORE_RECOVERY_FAILED',
      )),
    );
    expect(guestCreates, 0);
    expect(auth.vaultCorrupt, isTrue);
    expect(store.token, oldToken);
  });

  test('reconcile failure keeps Practice open and ranked gated', () async {
    final directory =
        Directory.systemTemp.createTempSync('pzd27-vault-reconcile-fail');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final store = FakeGuestStore()
      ..token = oldToken
      ..identityBinding = oldGuestBinding
      ..vaultJournal = 'v1:%%%%';
    final auth = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    await expectLater(
      auth.reconcilePersistedVault(),
      throwsA(isA<GuestAuthException>()),
    );
    final identity = PracticeIdentityStore(directory, random: Random(3));
    await identity.load();
    final controller = TournamentController(
      config: const UatConfig(
        baseUrl: 'https://staging.puzzle-duel.app',
        bearer: '',
        playerLabel: 'Session recovery',
      ),
      api: ScriptedUatApi(
        (method, path, body) async => const UatHttpResult(200, {}),
      ),
      stateDirectory: directory,
      identity: identity,
      sessionAuth: auth,
      initialSessionRecovery: const GuestSessionRecovery(
        code: 'SECURE_STORE_RECOVERY_FAILED',
        binding: GuestIdentityBinding(
          playerId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
          accountType: AccountType.guest,
        ),
      ),
    );
    expect(controller.sessionRecoveryRequired, isTrue);
    expect(controller.rankedWriterLocked, isTrue);
    await controller.beginLocal();
    expect(controller.localReady, isTrue);
    controller.dispose();
  });

  test('verified journal intent cannot downgrade to pure guest after restart',
      () async {
    final journal = _journal(
      nextRefresh: newToken,
      nextBinding: newVerifiedBinding,
      pendingLinkAction: GuestVaultPendingLinkAction.clear,
    );
    final store = FakeGuestStore()
      ..token = newToken
      ..identityBinding = oldGuestBinding // torn: still guest label
      ..vaultJournal = journal.encode();

    final restarted = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    await restarted.reconcilePersistedVault();
    expect(
      GuestIdentityBinding.tryParse(store.identityBinding)?.accountType,
      AccountType.verified,
    );
    final recovery =
        await restarted.captureSessionRecovery('GUEST_RECOVERY_REQUIRED');
    expect(recovery.allowsExplicitNewGuest, isFalse);
  });

  test('partial commit + rollback failure keeps journal for restart reconcile',
      () async {
    final store = FakeGuestStore()
      ..token = oldToken
      ..identityBinding = oldGuestBinding
      ..failBindingWrite = true
      ..failRestoreAfterPartial = true;
    final auth = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    auth.debugTransport = (path, body) async {
      if (path == '/v1/auth/guest') {
        return (
          status: 201,
          body: {
            'accessToken': _jwt(
              playerId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
              familyId: 'dddddddd-dddd-dddd-dddd-dddddddddddd',
            ),
            'refreshToken': newToken,
            'expiresAt': DateTime.now()
                .toUtc()
                .add(const Duration(hours: 1))
                .toIso8601String(),
          },
        );
      }
      fail('unexpected $path');
    };
    await expectLater(
      auth.replaceWithExplicitNewGuest(),
      throwsA(isA<GuestAuthException>().having(
        (e) => e.code,
        'code',
        'SECURE_STORE_RECOVERY_FAILED',
      )),
    );
    expect(auth.vaultCorrupt, isTrue);
    expect(auth.cachedAccess, isNull);
    expect(store.vaultJournal, isNotNull);
    expect(store.token, newToken);
    expect(store.identityBinding, oldGuestBinding);

    // Restart: storage healthy again; no catch/rollback — reconcile completes.
    store
      ..failBindingWrite = false
      ..failRestoreAfterPartial = false;
    final restarted = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    await restarted.reconcilePersistedVault();
    expect(store.token, newToken);
    expect(store.identityBinding, newGuestBinding);
    expect(store.vaultJournal, isNull);
    expect(restarted.vaultCorrupt, isFalse);
    expect(
      GuestIdentityBinding.tryParse(store.identityBinding)?.playerId,
      'cccccccc-cccc-cccc-cccc-cccccccccccc',
    );
  });

  test('partial commit + same-process authenticate cannot bypass reconcile',
      () async {
    final store = FakeGuestStore()
      ..token = oldToken
      ..identityBinding = oldGuestBinding
      ..failBindingWrite = true
      ..failRestoreAfterPartial = true;
    final auth = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    auth.debugSeedAccess(GuestAccess.parse(
      accessToken: _jwt(
        playerId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        familyId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      ),
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    ));
    expect(auth.cachedAccess, isNotNull);

    auth.debugTransport = (path, body) async {
      if (path == '/v1/auth/guest') {
        return (
          status: 201,
          body: {
            'accessToken': _jwt(
              playerId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
              familyId: 'dddddddd-dddd-dddd-dddd-dddddddddddd',
            ),
            'refreshToken': newToken,
            'expiresAt': DateTime.now()
                .toUtc()
                .add(const Duration(hours: 1))
                .toIso8601String(),
          },
        );
      }
      fail('must not network while vault unsafe before reconcile');
    };
    await expectLater(
      auth.replaceWithExplicitNewGuest(),
      throwsA(isA<GuestAuthException>().having(
        (e) => e.code,
        'code',
        'SECURE_STORE_RECOVERY_FAILED',
      )),
    );
    expect(auth.cachedAccess, isNull);
    expect(auth.vaultCorrupt, isTrue);

    store
      ..failBindingWrite = false
      ..failRestoreAfterPartial = false;
    var guestCreates = 0;
    auth.debugTransport = (path, body) async {
      if (path == '/v1/auth/guest') {
        guestCreates++;
        fail('must not silent-mint after vault failure');
      }
      if (path == '/v1/auth/refresh') {
        return (
          status: 200,
          body: {
            'accessToken': _jwt(
              playerId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
              familyId: 'dddddddd-dddd-dddd-dddd-dddddddddddd',
            ),
            'refreshToken': newToken,
            'expiresAt': DateTime.now()
                .toUtc()
                .add(const Duration(hours: 1))
                .toIso8601String(),
          },
        );
      }
      fail('unexpected $path');
    };
    // Same process: authenticate must reconcile journal first (no ranked bypass).
    final access = await auth.authenticate(allowGuestCreate: false);
    expect(guestCreates, 0);
    expect(auth.vaultCorrupt, isFalse);
    expect(store.vaultJournal, isNull);
    expect(store.identityBinding, newGuestBinding);
    expect(access.playerId, 'cccccccc-cccc-cccc-cccc-cccccccccccc');
  });

  test('pending-link cleanup failure restores prior pending marker', () async {
    const pending = 'google|aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    final store = FakeGuestStore()
      ..token = oldToken
      ..identityBinding = oldGuestBinding
      ..pendingLink = pending
      ..failClearPendingLink = true;
    final auth = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    await expectLater(
      auth.replaceWithVerifiedBundle(
        accessToken: _jwt(
          playerId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
          familyId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
          accountType: 'verified',
        ),
        refreshToken: newToken,
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
      throwsA(isA<GuestAuthException>().having(
        (e) => e.code,
        'code',
        'SECURE_STORE_RECOVERY_FAILED',
      )),
    );
    expect(store.token, oldToken);
    expect(store.identityBinding, oldGuestBinding);
    expect(store.pendingLink, pending);
    expect(store.vaultJournal, isNull);
    expect(auth.cachedAccess, isNull);
  });

  testWidgets('recovery shell Practice remains after vault recovery code',
      (tester) async {
    final directory =
        Directory.systemTemp.createTempSync('pzd27-vault-practice-ui');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    await tester.pumpWidget(TournamentUatApp(
      config: const UatConfig(
        baseUrl: 'https://staging.puzzle-duel.app',
        bearer: '',
        playerLabel: 'Session recovery',
      ),
      api: ScriptedUatApi(
        (method, path, body) async =>
            const UatHttpResult(401, {'error': 'UNAUTHENTICATED'}),
      ),
      stateDirectory: directory,
      sessionRecovery: const GuestSessionRecovery(
        code: 'SECURE_STORE_RECOVERY_FAILED',
        lastRequestId: 'ffffffffffffffffffffffffffffffff',
      ),
    ));
    await tester.pump();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const Key('practice')), findsOneWidget);
    expect(find.textContaining('HTTPS configuration'), findsNothing);
  });
}
