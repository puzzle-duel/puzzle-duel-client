import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/tournament/guest_auth.dart';
import 'package:puzzle_duel_mobile/tournament/guest_session_recovery.dart';
import 'package:puzzle_duel_mobile/tournament/practice_identity.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_controller.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_uat_app.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';

import 'guest_refresh_durability_test.dart' show FakeGuestStore;
import 'tournament_command_test.dart' show ScriptedUatApi;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('GuestIdentityBinding round-trips without secrets', () {
    final binding = GuestIdentityBinding(
      playerId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      familyId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      accountType: AccountType.guest,
    );
    final parsed = GuestIdentityBinding.tryParse(binding.encode());
    expect(parsed?.playerId, binding.playerId);
    expect(parsed?.familyId, binding.familyId);
    expect(parsed?.accountType, AccountType.guest);
    expect(GuestIdentityBinding.tryParse('not-a-binding'), isNull);
  });

  test('recoverable startup codes cover revoked family path', () {
    expect(GuestSessionRecovery.isRecoverableStartup('GUEST_RECOVERY_REQUIRED'),
        isTrue);
    expect(GuestSessionRecovery.isRecoverableStartup('REFRESH_REPLAY'), isTrue);
    expect(
        GuestSessionRecovery.isRecoverableStartup('PROVIDER_LINK_RECOVERY_google'),
        isTrue);
    expect(GuestSessionRecovery.isRecoverableStartup('STAGING_BASE_URL_MISSING'),
        isFalse);
  });

  test('revoked family refresh throws GUEST_RECOVERY_REQUIRED and keeps vault',
      () async {
    final store = FakeGuestStore()
      ..token = 'a' * 64
      ..identityBinding =
          'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa||guest';
    final auth = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    auth.debugTransport = (path, body) async {
      expect(path, '/v1/auth/refresh');
      expect(body['refreshToken'], 'a' * 64);
      return (status: 401, body: {'error': 'INVALID_REFRESH'});
    };
    await expectLater(
      auth.authenticate(allowGuestCreate: true),
      throwsA(isA<GuestAuthException>().having(
        (e) => e.code,
        'code',
        'GUEST_RECOVERY_REQUIRED',
      )),
    );
    expect(store.token, 'a' * 64);
    expect(store.identityBinding, isNotNull);
    final recovery = await auth.captureSessionRecovery('GUEST_RECOVERY_REQUIRED');
    expect(recovery.expectedPlayerId, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
    expect(auth.lastAuthRequestId, isNotNull);
    expect(auth.lastAuthRequestId!.length, 32);
  });

  test('recovery boot keeps Practice and blocks ranked claim', () async {
    final directory =
        Directory.systemTemp.createTempSync('pzd27-guest-recovery-boot');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    var claimPosts = 0;
    final api = ScriptedUatApi((method, path, body) async {
      if (path.endsWith('/claims/daily')) {
        claimPosts += 1;
        fail('ranked claim must not run during session recovery');
      }
      return const UatHttpResult(401, {'error': 'UNAUTHENTICATED'});
    });
    final identity = PracticeIdentityStore(directory, random: Random(1));
    await identity.load();
    final controller = TournamentController(
      config: const UatConfig(
        baseUrl: 'https://staging.puzzle-duel.app',
        bearer: '',
        playerLabel: 'Session recovery',
      ),
      api: api,
      stateDirectory: directory,
      identity: identity,
      sessionRecovery: const GuestSessionRecovery(
        code: 'GUEST_RECOVERY_REQUIRED',
        lastRequestId: '0123456789abcdef0123456789abcdef',
        binding: GuestIdentityBinding(
          playerId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
          accountType: AccountType.guest,
        ),
      ),
    );
    await controller.beginLocal();
    await controller.refreshTournament(
      origin: TournamentRefreshOrigin.startup,
    );
    expect(controller.localReady, isTrue);
    expect(controller.sessionRecoveryRequired, isTrue);
    expect(controller.rankedWriterLocked, isTrue);
    expect(controller.tournamentNoticeCode, 'GUEST_RECOVERY_REQUIRED');
    expect(claimPosts, 0);
    expect(identity.activeScope.kind, PracticeIdentityKind.guest);
    controller.dispose();
  });

  testWidgets('recovery shell keeps Practice and opens recovery sheet from Home',
      (tester) async {
    final directory =
        Directory.systemTemp.createTempSync('pzd27-guest-recovery-ui');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final api = ScriptedUatApi(
      (method, path, body) async =>
          const UatHttpResult(401, {'error': 'UNAUTHENTICATED'}),
    );
    await tester.pumpWidget(TournamentUatApp(
      config: const UatConfig(
        baseUrl: 'https://staging.puzzle-duel.app',
        bearer: '',
        playerLabel: 'Session recovery',
      ),
      api: api,
      stateDirectory: directory,
      sessionRecovery: const GuestSessionRecovery(
        code: 'GUEST_RECOVERY_REQUIRED',
        lastRequestId: 'fedcba9876543210fedcba9876543210',
      ),
    ));
    await tester.pump();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const Key('practice')), findsOneWidget);
    expect(find.textContaining('HTTPS configuration'), findsNothing);
    expect(find.textContaining('Restore session'), findsWidgets);
    await tester.tap(find.text('Restore session').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('guest-recovery-title')), findsOneWidget);
    expect(find.byKey(const Key('guest-recovery-send-diagnostics')),
        findsOneWidget);
    expect(find.byKey(const Key('guest-recovery-request-id')), findsOneWidget);
  });
}
