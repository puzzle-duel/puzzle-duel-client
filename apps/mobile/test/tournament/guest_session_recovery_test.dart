import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/diagnostics/crash_reporter.dart';
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
  String accountType = 'verified',
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

  test('recoverable startup codes cover hard and transient paths', () {
    expect(GuestSessionRecovery.isRecoverableStartup('GUEST_RECOVERY_REQUIRED'),
        isTrue);
    expect(GuestSessionRecovery.isRecoverableStartup('REFRESH_REPLAY'), isTrue);
    expect(GuestSessionRecovery.isRecoverableStartup('AUTH_NETWORK_UNAVAILABLE'),
        isTrue);
    expect(GuestSessionRecovery.isRecoverableStartup('REFRESH_UNAVAILABLE'),
        isTrue);
    expect(
        GuestSessionRecovery.isRecoverableStartup('PROVIDER_LINK_RECOVERY_GOOGLE'),
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

  test('legacy vault without identity binding still captures requestId', () async {
    final store = FakeGuestStore()..token = 'b' * 64;
    final auth = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    auth.debugTransport = (path, body) async =>
        (status: 401, body: {'error': 'INVALID_REFRESH'});
    await expectLater(
      auth.authenticate(),
      throwsA(isA<GuestAuthException>()),
    );
    final recovery = await auth.captureSessionRecovery('GUEST_RECOVERY_REQUIRED');
    expect(recovery.binding, isNull);
    expect(recovery.expectedPlayerId, isNull);
    expect(recovery.lastRequestId, isNotNull);
    expect(store.token, 'b' * 64);
  });

  test('successful recovery clears gate and allows authenticated refresh',
      () async {
    final directory =
        Directory.systemTemp.createTempSync('pzd27-recovery-success');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final store = FakeGuestStore()
      ..token = 'c' * 64
      ..identityBinding =
          'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa|bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb|guest';
    final auth = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    var refreshCalls = 0;
    auth.debugTransport = (path, body) async {
      refreshCalls++;
      expect(path, '/v1/auth/refresh');
      return (
        status: 200,
        body: {
          'accessToken': _jwt(
            playerId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            familyId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
          ),
          'refreshToken': 'd' * 64,
          'expiresAt':
              DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String(),
        },
      );
    };
    final identity = PracticeIdentityStore(directory, random: Random(2));
    await identity.load();
    final api = ScriptedUatApi((method, path, body) async {
      if (path.endsWith('/claims/daily')) {
        return const UatHttpResult(403, {'error': 'RANKED_AUTH_REQUIRED'});
      }
      return const UatHttpResult(200, {});
    });
    final controller = TournamentController(
      config: const UatConfig(
        baseUrl: 'https://staging.puzzle-duel.app',
        bearer: '',
        playerLabel: 'Session recovery',
      ),
      api: api,
      stateDirectory: directory,
      identity: identity,
      sessionAuth: auth,
      initialSessionRecovery: await auth.captureSessionRecovery(
        'GUEST_RECOVERY_REQUIRED',
      ),
    );
    expect(controller.sessionRecoveryRequired, isTrue);
    final access = await auth.authenticate(allowGuestCreate: false);
    controller.clearSessionRecoveryGate(
      bearer: access.accessToken,
      access: access,
    );
    expect(controller.sessionRecoveryRequired, isFalse);
    expect(controller.activeSessionRecovery, isNull);
    expect(controller.rankedAuthRequired, isFalse);
    expect(controller.rankedWriterLocked, isTrue);
    expect(controller.api.bearer, contains(access.accessToken.substring(0, 20)));
    final refreshed = await auth.authenticate(forceRefresh: true);
    expect(refreshed.accessToken, isNotEmpty);
    expect(refreshCalls, greaterThanOrEqualTo(2));
    await controller.requestRankedEntry();
    expect(controller.sessionRecoveryRequired, isFalse);
    controller.dispose();
  });

  test('offline startup keeps Practice; network restore retries without mint',
      () async {
    final directory =
        Directory.systemTemp.createTempSync('pzd27-recovery-offline');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final store = FakeGuestStore()
      ..token = 'e' * 64
      ..identityBinding =
          'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa||guest';
    final auth = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    var online = false;
    var guestCreates = 0;
    auth.debugTransport = (path, body) async {
      if (path == '/v1/auth/guest') {
        guestCreates++;
        fail('guest mint must not run during transient recovery retry');
      }
      if (!online) {
        return (status: 503, body: {'error': 'AUTH_UNAVAILABLE'});
      }
      return (
        status: 200,
        body: {
          'accessToken': _jwt(
            playerId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            familyId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
            accountType: 'guest',
          ),
          'refreshToken': 'f' * 64,
          'expiresAt':
              DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String(),
        },
      );
    };
    await expectLater(
      auth.authenticate(),
      throwsA(isA<GuestAuthException>().having(
        (e) => e.code,
        'code',
        'REFRESH_UNAVAILABLE',
      )),
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
        (method, path, body) async =>
            const UatHttpResult(0, {'error': 'OFFLINE'}),
      ),
      stateDirectory: directory,
      identity: identity,
      sessionAuth: auth,
      initialSessionRecovery:
          await auth.captureSessionRecovery('REFRESH_UNAVAILABLE'),
    );
    await controller.beginLocal();
    expect(controller.localReady, isTrue);
    expect(controller.sessionRecoveryRequired, isTrue);
    expect(store.token, 'e' * 64);
    online = true;
    await controller.refreshTournament(
      origin: TournamentRefreshOrigin.pullToRefresh,
    );
    expect(controller.sessionRecoveryRequired, isFalse);
    expect(store.token, 'f' * 64);
    expect(guestCreates, 0);
    // Guest account type + writer lock preserved after transient clear.
    // (Session restore may still degrade with OFFLINE from the scripted API.)
    expect(controller.rankedAuthRequired, isTrue);
    expect(controller.rankedWriterLocked, isTrue);
    controller.dispose();
  });

  test('runtime revoked family uses captureSessionRecovery binding', () async {
    final directory =
        Directory.systemTemp.createTempSync('pzd27-recovery-runtime');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final store = FakeGuestStore()
      ..token = 'g' * 64
      ..identityBinding =
          'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa||guest'
      ..pendingLink =
          'google|aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    final auth = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    auth.debugTransport = (path, body) async =>
        (status: 401, body: {'error': 'INVALID_REFRESH'});
    final identity = PracticeIdentityStore(directory, random: Random(4));
    await identity.load();
    final controller = TournamentController(
      config: const UatConfig(
        baseUrl: 'https://staging.puzzle-duel.app',
        bearer: 'Bearer prior',
        playerLabel: 'Guest',
      ),
      api: ScriptedUatApi(
        (method, path, body) async =>
            const UatHttpResult(200, {}),
      ),
      stateDirectory: directory,
      identity: identity,
      sessionAuth: auth,
    );
    var recoveryOpened = false;
    controller.onRequestRankedAuth = () => recoveryOpened = true;
    await controller.requestRankedEntry();
    expect(recoveryOpened, isTrue);
    expect(controller.sessionRecoveryRequired, isTrue);
    expect(controller.activeSessionRecovery?.expectedPlayerId,
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
    expect(controller.activeSessionRecovery?.pendingLink?.provider, 'google');
    expect(controller.activeSessionRecovery?.lastRequestId, isNotNull);
    controller.dispose();
  });

  test('diagnostic reporting separates Crashlytics record from server delivery',
      () async {
    final crash = _RecordingCrashReporter();
    final result = await sendStagingManualDiagnostics(
      operation: 'unit_diagnostic',
      requestId: '0123456789abcdef0123456789abcdef',
      errorCode: 'GUEST_RECOVERY_REQUIRED',
      crashReporter: crash,
    );
    expect(result.breadcrumbLogged, isTrue);
    expect(result.crashlyticsRecorded, isTrue);
    expect(result.serverDelivered, isFalse);
    expect(result.userMessage.contains('Crashlytics'), isTrue);
    expect(result.userMessage.contains('sunucu raporu yok'), isTrue);
    expect(result.userMessage.contains('gönderildi. Rapor'), isFalse);

    final failed = await sendStagingManualDiagnostics(
      operation: 'unit_diagnostic_fail',
      crashReporter: _FailingCrashReporter(),
    );
    expect(failed.crashlyticsRecorded, isFalse);
    expect(failed.userMessage.contains('gönderilemedi') ||
            failed.userMessage.contains('breadcrumb'),
        isTrue);
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
      initialSessionRecovery: const GuestSessionRecovery(
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

  Future<void> pumpRecoveryHome(
    WidgetTester tester, {
    required Directory directory,
    required GuestSessionRecovery recovery,
    GuestAuthClient? sessionAuth,
  }) async {
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
      sessionAuth: sessionAuth,
      sessionRecovery: recovery,
    ));
    await tester.pump();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.text('Restore session').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('guest-recovery-title')), findsOneWidget);
  }

  testWidgets('new-guest confirm cancel issues zero guest create requests',
      (tester) async {
    final directory =
        Directory.systemTemp.createTempSync('pzd27-new-guest-cancel');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final store = FakeGuestStore()
      ..token = 'a' * 64
      ..identityBinding =
          'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa||guest';
    var guestCreates = 0;
    final auth = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    auth.debugTransport = (path, body) async {
      if (path == '/v1/auth/guest') guestCreates++;
      fail('cancel must not hit auth transport');
    };
    await pumpRecoveryHome(
      tester,
      directory: directory,
      sessionAuth: auth,
      recovery: const GuestSessionRecovery(
        code: 'GUEST_RECOVERY_REQUIRED',
        lastRequestId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        binding: GuestIdentityBinding(
          playerId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
          accountType: AccountType.guest,
        ),
      ),
    );
    expect(find.byKey(const Key('guest-recovery-new-guest')), findsOneWidget);
    await tester.tap(find.byKey(const Key('guest-recovery-new-guest')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guest-recovery-new-guest-confirm-body')),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('guest-recovery-new-guest-cancel')));
    await tester.pumpAndSettle();
    expect(guestCreates, 0);
    expect(store.token, 'a' * 64);
    expect(find.byKey(const Key('guest-recovery-new-guest-confirm-body')),
        findsNothing);
    expect(find.byKey(const Key('guest-recovery-new-guest')), findsOneWidget);
  });

  testWidgets('new-guest confirm confirm issues exactly one guest create',
      (tester) async {
    final directory =
        Directory.systemTemp.createTempSync('pzd27-new-guest-confirm');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final store = FakeGuestStore()
      ..token = 'b' * 64
      ..identityBinding =
          'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa||guest';
    var guestCreates = 0;
    final auth = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    auth.debugTransport = (path, body) async {
      if (path == '/v1/auth/guest') {
        guestCreates++;
        return (
          status: 201,
          body: {
            'accessToken': _jwt(
              playerId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
              familyId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
              accountType: 'guest',
            ),
            'refreshToken': 'c' * 64,
            'expiresAt': DateTime.now()
                .toUtc()
                .add(const Duration(hours: 1))
                .toIso8601String(),
          },
        );
      }
      fail('unexpected $path');
    };
    await pumpRecoveryHome(
      tester,
      directory: directory,
      sessionAuth: auth,
      recovery: const GuestSessionRecovery(
        code: 'GUEST_RECOVERY_REQUIRED',
        lastRequestId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        binding: GuestIdentityBinding(
          playerId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
          accountType: AccountType.guest,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('guest-recovery-new-guest')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('guest-recovery-new-guest-confirm')));
    await tester.pumpAndSettle();
    expect(guestCreates, 1);
    expect(store.token, 'c' * 64);
    expect(find.byKey(const Key('guest-recovery-title')), findsNothing);
  });

  testWidgets('new-guest confirm failure keeps prior credentials and sheet',
      (tester) async {
    final directory =
        Directory.systemTemp.createTempSync('pzd27-new-guest-fail');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final store = FakeGuestStore()
      ..token = 'd' * 64
      ..identityBinding =
          'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa||guest';
    final auth = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    auth.debugTransport = (path, body) async {
      if (path == '/v1/auth/guest') {
        return (status: 503, body: {'error': 'AUTH_UNAVAILABLE'});
      }
      fail('unexpected $path');
    };
    await pumpRecoveryHome(
      tester,
      directory: directory,
      sessionAuth: auth,
      recovery: const GuestSessionRecovery(
        code: 'GUEST_RECOVERY_REQUIRED',
        lastRequestId: 'cccccccccccccccccccccccccccccccc',
        binding: GuestIdentityBinding(
          playerId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
          accountType: AccountType.guest,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('guest-recovery-new-guest')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('guest-recovery-new-guest-confirm')));
    await tester.pumpAndSettle();
    expect(store.token, 'd' * 64);
    expect(find.byKey(const Key('guest-recovery-title')), findsOneWidget);
    expect(find.byKey(const Key('guest-recovery-error')), findsOneWidget);
    expect(find.text('GUEST_CREATION_UNAVAILABLE'), findsOneWidget);
  });

  testWidgets('verified recovery hides new-guest action', (tester) async {
    final directory =
        Directory.systemTemp.createTempSync('pzd27-verified-no-new');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final store = FakeGuestStore()
      ..token = 'e' * 64
      ..identityBinding =
          'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa||verified';
    final auth = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    auth.debugTransport = (path, body) async {
      fail('verified recovery must not mint guest');
    };
    await pumpRecoveryHome(
      tester,
      directory: directory,
      sessionAuth: auth,
      recovery: const GuestSessionRecovery(
        code: 'GUEST_RECOVERY_REQUIRED',
        lastRequestId: 'dddddddddddddddddddddddddddddddd',
        binding: GuestIdentityBinding(
          playerId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
          accountType: AccountType.verified,
        ),
      ),
    );
    expect(find.byKey(const Key('guest-recovery-new-guest')), findsNothing);
    expect(find.byKey(const Key('guest-recovery-title')), findsOneWidget);
  });

  testWidgets('pending-link recovery hides new-guest action', (tester) async {
    final directory =
        Directory.systemTemp.createTempSync('pzd27-pending-no-new');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final store = FakeGuestStore()
      ..token = 'f' * 64
      ..pendingLink =
          'google|aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    final auth = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    auth.debugTransport = (path, body) async {
      fail('pending recovery must not mint guest');
    };
    await pumpRecoveryHome(
      tester,
      directory: directory,
      sessionAuth: auth,
      recovery: const GuestSessionRecovery(
        code: 'PROVIDER_LINK_RECOVERY_GOOGLE',
        lastRequestId: 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
        pendingLink: PendingLinkRecovery(
          provider: 'google',
          playerId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        ),
      ),
    );
    expect(find.byKey(const Key('guest-recovery-new-guest')), findsNothing);
    expect(find.byKey(const Key('guest-recovery-title')), findsOneWidget);
  });

  test('cleared mutable recovery ignores immutable startup seed', () async {
    final directory =
        Directory.systemTemp.createTempSync('pzd27-guest-recovery-clear');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final store = FakeGuestStore()..token = 'h' * 64;
    final auth = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    auth.debugTransport = (path, body) async => (
          status: 200,
          body: {
            'accessToken': _jwt(
              playerId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
              familyId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
            ),
            'refreshToken': 'i' * 64,
            'expiresAt': DateTime.now()
                .toUtc()
                .add(const Duration(hours: 1))
                .toIso8601String(),
          },
        );
    final seed = const GuestSessionRecovery(
      code: 'GUEST_RECOVERY_REQUIRED',
      lastRequestId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      binding: GuestIdentityBinding(
        playerId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        accountType: AccountType.guest,
      ),
    );
    final identity = PracticeIdentityStore(directory, random: Random(5));
    await identity.load();
    final controller = TournamentController(
      config: const UatConfig(
        baseUrl: 'https://staging.puzzle-duel.app',
        bearer: '',
        playerLabel: 'Session recovery',
      ),
      api: ScriptedUatApi(
        (method, path, body) async =>
            const UatHttpResult(403, {'error': 'RANKED_AUTH_REQUIRED'}),
      ),
      stateDirectory: directory,
      identity: identity,
      sessionAuth: auth,
      initialSessionRecovery: seed,
    );
    expect(controller.activeSessionRecovery?.code, 'GUEST_RECOVERY_REQUIRED');
    final access = await auth.authenticate(allowGuestCreate: false);
    controller.clearSessionRecoveryGate(
      bearer: access.accessToken,
      access: access,
    );
    expect(controller.sessionRecoveryRequired, isFalse);
    expect(controller.activeSessionRecovery, isNull);
    expect(controller.rankedAuthRequired, isFalse);
    // Writer stays locked until server-authoritative loadDay/resume.
    expect(controller.rankedWriterLocked, isTrue);
    // Ranked entry after clear must not re-enter recovery from seed alone.
    var openedRecovery = false;
    controller.onRequestRankedAuth = () => openedRecovery = true;
    await controller.requestRankedEntry();
    expect(controller.sessionRecoveryRequired, isFalse);
    expect(openedRecovery, isFalse);
    controller.dispose();
  });

  test('loadDay revoked-family routes through enterSessionRecovery', () async {
    final directory =
        Directory.systemTemp.createTempSync('pzd27-loadday-revoked');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final store = FakeGuestStore()
      ..token = 'j' * 64
      ..identityBinding =
          'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa||guest'
      ..pendingLink =
          'apple|aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    final auth = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    auth.debugTransport = (path, body) async =>
        (status: 401, body: {'error': 'INVALID_REFRESH'});
    var claimPosts = 0;
    final api = ScriptedUatApi((method, path, body) async {
      if (path.endsWith('/claims/daily')) {
        claimPosts += 1;
        fail('ranked claim must not run during revoked-family recovery');
      }
      return const UatHttpResult(200, {});
    });
    final identity = PracticeIdentityStore(directory, random: Random(6));
    await identity.load();
    final controller = TournamentController(
      config: const UatConfig(
        baseUrl: 'https://staging.puzzle-duel.app',
        bearer: 'Bearer prior',
        playerLabel: 'Guest',
      ),
      api: api,
      stateDirectory: directory,
      identity: identity,
      sessionAuth: auth,
    );
    await controller.beginLocal();
    await controller.loadDay(presentHome: true);
    expect(controller.sessionRecoveryRequired, isTrue);
    expect(controller.activeSessionRecovery?.code,
        'PROVIDER_LINK_RECOVERY_APPLE');
    expect(controller.activeSessionRecovery?.expectedPlayerId,
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
    expect(controller.activeSessionRecovery?.pendingLink?.provider, 'apple');
    expect(controller.activeSessionRecovery?.lastRequestId, isNotNull);
    expect(controller.rankedWriterLocked, isTrue);
    expect(controller.tournamentNoticeCode, 'PROVIDER_LINK_RECOVERY_APPLE');
    expect(claimPosts, 0);
    expect(store.token, 'j' * 64);
    controller.dispose();
  });

  test('loadDay transient recovery keeps guest ranked gate', () async {
    final directory =
        Directory.systemTemp.createTempSync('pzd27-loadday-transient-guest');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final store = FakeGuestStore()
      ..token = 'k' * 64
      ..identityBinding =
          'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa||guest';
    final auth = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    auth.debugTransport = (path, body) async => (
          status: 200,
          body: {
            'accessToken': _jwt(
              playerId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
              familyId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
              accountType: 'guest',
            ),
            'refreshToken': 'l' * 64,
            'expiresAt': DateTime.now()
                .toUtc()
                .add(const Duration(hours: 1))
                .toIso8601String(),
          },
        );
    var claimPosts = 0;
    final api = ScriptedUatApi((method, path, body) async {
      if (path.endsWith('/claims/daily')) {
        claimPosts += 1;
        fail('guest must not claim after transient recovery');
      }
      return const UatHttpResult(200, {});
    });
    final identity = PracticeIdentityStore(directory, random: Random(7));
    await identity.load();
    final controller = TournamentController(
      config: const UatConfig(
        baseUrl: 'https://staging.puzzle-duel.app',
        bearer: '',
        playerLabel: 'Guest',
      ),
      api: api,
      stateDirectory: directory,
      identity: identity,
      sessionAuth: auth,
      initialSessionRecovery: await auth.captureSessionRecovery(
        'AUTH_NETWORK_UNAVAILABLE',
      ),
    );
    expect(controller.rankedWriterLocked, isTrue);
    await controller.beginLocal();
    await controller.loadDay(presentHome: true);
    expect(controller.sessionRecoveryRequired, isFalse);
    expect(controller.rankedAuthRequired, isTrue);
    expect(controller.rankedWriterLocked, isTrue);
    expect(controller.tournamentNoticeCode, 'RANKED_AUTH_REQUIRED');
    expect(claimPosts, 0);
    controller.dispose();
  });

  test('loadDay transient recovery verified keeps writer lock until server',
      () async {
    final directory =
        Directory.systemTemp.createTempSync('pzd27-loadday-transient-verified');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final store = FakeGuestStore()
      ..token = 'm' * 64
      ..identityBinding =
          'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa||verified';
    final auth = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    final verifiedToken = _jwt(
      playerId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      familyId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      accountType: 'verified',
    );
    auth.debugTransport = (path, body) async => (
          status: 200,
          body: {
            'accessToken': verifiedToken,
            'refreshToken': 'n' * 64,
            'expiresAt': DateTime.now()
                .toUtc()
                .add(const Duration(hours: 1))
                .toIso8601String(),
          },
        );
    var claimPosts = 0;
    final api = ScriptedUatApi((method, path, body) async {
      if (path.endsWith('/claims/daily')) {
        claimPosts += 1;
        // Deny writer so server-authoritative lock remains true.
        return const UatHttpResult(403, {'error': 'WRITER_NOT_AUTHORIZED'});
      }
      return const UatHttpResult(200, {});
    });
    final identity = PracticeIdentityStore(directory, random: Random(8));
    await identity.load();
    final controller = TournamentController(
      config: const UatConfig(
        baseUrl: 'https://staging.puzzle-duel.app',
        bearer: '',
        playerLabel: 'Verified',
      ),
      api: api,
      stateDirectory: directory,
      identity: identity,
      sessionAuth: auth,
      initialSessionRecovery: await auth.captureSessionRecovery(
        'REFRESH_UNAVAILABLE',
      ),
    );
    expect(controller.rankedWriterLocked, isTrue);
    await controller.beginLocal();
    await controller.loadDay(presentHome: true);
    expect(controller.sessionRecoveryRequired, isFalse);
    expect(controller.rankedAuthRequired, isFalse);
    // clearSessionRecoveryGate must not have unlocked the writer; loadDay
    // then keeps/sets lock from server-authoritative claim outcome.
    expect(controller.rankedWriterLocked, isTrue);
    expect(claimPosts, 1);
    controller.dispose();
  });

  test('explicit new guest flags: pure guest yes; pending/verified/transient no',
      () {
    const pure = GuestSessionRecovery(
      code: 'GUEST_RECOVERY_REQUIRED',
      binding: GuestIdentityBinding(
        playerId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        accountType: AccountType.guest,
      ),
    );
    expect(pure.allowsExplicitNewGuest, isTrue);
    expect(pure.canAttemptProviderRecover, isFalse);

    const pending = GuestSessionRecovery(
      code: 'PROVIDER_LINK_RECOVERY_GOOGLE',
      pendingLink: PendingLinkRecovery(
        provider: 'google',
        playerId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      ),
    );
    expect(pending.allowsExplicitNewGuest, isFalse);
    expect(pending.canAttemptProviderRecover, isTrue);

    const verified = GuestSessionRecovery(
      code: 'GUEST_RECOVERY_REQUIRED',
      binding: GuestIdentityBinding(
        playerId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        accountType: AccountType.verified,
      ),
    );
    expect(verified.allowsExplicitNewGuest, isFalse);
    expect(verified.canAttemptProviderRecover, isTrue);

    const transient = GuestSessionRecovery(code: 'REFRESH_UNAVAILABLE');
    expect(transient.allowsExplicitNewGuest, isFalse);
  });

  test('explicit new guest replaces vault atomically and gates ranked', () async {
    final directory =
        Directory.systemTemp.createTempSync('pzd27-explicit-new-guest');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final oldToken = 'o' * 64;
    final store = FakeGuestStore()
      ..token = oldToken
      ..identityBinding =
          'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa||guest';
    final auth = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    var guestCreates = 0;
    auth.debugTransport = (path, body) async {
      if (path == '/v1/auth/guest') {
        guestCreates++;
        return (
          status: 201,
          body: {
            'accessToken': _jwt(
              playerId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
              familyId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
              accountType: 'guest',
            ),
            'refreshToken': 'p' * 64,
            'expiresAt': DateTime.now()
                .toUtc()
                .add(const Duration(hours: 1))
                .toIso8601String(),
          },
        );
      }
      fail('unexpected path $path');
    };
    final access = await auth.replaceWithExplicitNewGuest();
    expect(guestCreates, 1);
    expect(access.playerId, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
    expect(store.token, 'p' * 64);
    expect(store.identityBinding, contains('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'));
    expect(store.token, isNot(oldToken));

    final identity = PracticeIdentityStore(directory, random: Random(9));
    await identity.load();
    final controller = TournamentController(
      config: const UatConfig(
        baseUrl: 'https://staging.puzzle-duel.app',
        bearer: '',
        playerLabel: 'Guest',
      ),
      api: ScriptedUatApi(
        (method, path, body) async {
          if (path.endsWith('/claims/daily')) {
            fail('guest must not claim without verification');
          }
          return const UatHttpResult(200, {});
        },
      ),
      stateDirectory: directory,
      identity: identity,
      sessionAuth: auth,
      initialSessionRecovery: const GuestSessionRecovery(
        code: 'GUEST_RECOVERY_REQUIRED',
      ),
    );
    controller.clearSessionRecoveryGate(
      bearer: access.accessToken,
      access: access,
    );
    expect(controller.sessionRecoveryRequired, isFalse);
    expect(controller.rankedAuthRequired, isTrue);
    await controller.beginLocal();
    expect(controller.localReady, isTrue);
    controller.dispose();
  });

  test('explicit new guest binding-write failure restores prior token',
      () async {
    final store = FakeGuestStore()
      ..token = 'q' * 64
      ..identityBinding =
          'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa||guest'
      ..rotationId = '0123456789abcdef0123456789abcdef'
      ..failBindingWrite = true;
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
              playerId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
              familyId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
              accountType: 'guest',
            ),
            'refreshToken': 'n' * 64,
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
    expect(store.token, 'q' * 64);
    expect(store.identityBinding,
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa||guest');
    expect(store.rotationId, '0123456789abcdef0123456789abcdef');
    expect(store.vaultJournal, isNull);
  });

  test('explicit new guest rotation-clear failure restores prior vault',
      () async {
    final store = FakeGuestStore()
      ..token = 'm' * 64
      ..identityBinding =
          'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa||guest'
      ..rotationId = 'fedcba9876543210fedcba9876543210'
      ..failClearRotation = true;
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
              playerId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
              familyId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
              accountType: 'guest',
            ),
            'refreshToken': 'l' * 64,
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
    expect(store.token, 'm' * 64);
    expect(store.identityBinding,
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa||guest');
    expect(store.rotationId, 'fedcba9876543210fedcba9876543210');
    expect(store.vaultJournal, isNull);
  });

  test('explicit new guest restore failure surfaces SECURE_STORE_RECOVERY_FAILED',
      () async {
    final store = FakeGuestStore()
      ..token = 'k' * 64
      ..identityBinding =
          'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa||guest'
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
              playerId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
              familyId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
              accountType: 'guest',
            ),
            'refreshToken': 'j' * 64,
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
    // Partial commit left new token; restore could not rewind; journal kept.
    expect(store.token, 'j' * 64);
    expect(store.vaultJournal, isNotNull);
    expect(auth.vaultCorrupt, isTrue);
    expect(auth.cachedAccess, isNull);
  });

  test('verified binding blocks explicit new guest mint', () async {
    final store = FakeGuestStore()
      ..token = 'z' * 64
      ..identityBinding =
          'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa||verified';
    final auth = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    var guestCreates = 0;
    auth.debugTransport = (path, body) async {
      if (path == '/v1/auth/guest') guestCreates++;
      fail('must not mint while verified binding present');
    };
    await expectLater(
      auth.replaceWithExplicitNewGuest(),
      throwsA(isA<GuestAuthException>().having(
        (e) => e.code,
        'code',
        'RECOVERY_NOT_LINKED',
      )),
    );
    expect(guestCreates, 0);
    expect(store.token, 'z' * 64);
  });

  test('replaceWithVerifiedBundle persists verified identity binding', () async {
    final store = FakeGuestStore()
      ..token = 'g' * 64
      ..identityBinding =
          'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa||guest';
    final auth = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    final verified = await auth.replaceWithVerifiedBundle(
      accessToken: _jwt(
        playerId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        familyId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        accountType: 'verified',
      ),
      refreshToken: 'f' * 64,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    expect(verified.isVerified, isTrue);
    expect(store.token, 'f' * 64);
    final binding = GuestIdentityBinding.tryParse(store.identityBinding);
    expect(binding?.accountType, AccountType.verified);
    expect(binding?.playerId, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
    expect(binding?.familyId, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

    // Restart semantics: captureSessionRecovery must not treat as pure guest.
    final recovery =
        await auth.captureSessionRecovery('GUEST_RECOVERY_REQUIRED');
    expect(recovery.binding?.accountType, AccountType.verified);
    expect(recovery.allowsExplicitNewGuest, isFalse);
  });

  test('concurrent refresh yields to explicit new-guest replacement', () async {
    final store = FakeGuestStore()
      ..token = 'e' * 64
      ..identityBinding =
          'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa||guest';
    final auth = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    var refreshCalls = 0;
    var guestCreates = 0;
    final refreshStarted = Completer<void>();
    final refreshGate = Completer<void>();
    auth.debugTransport = (path, body) async {
      if (path == '/v1/auth/refresh') {
        refreshCalls++;
        if (!refreshStarted.isCompleted) refreshStarted.complete();
        await refreshGate.future;
        return (
          status: 200,
          body: {
            'accessToken': _jwt(
              playerId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
              familyId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
              accountType: 'guest',
            ),
            'refreshToken': 'd' * 64,
            'expiresAt': DateTime.now()
                .toUtc()
                .add(const Duration(hours: 1))
                .toIso8601String(),
          },
        );
      }
      if (path == '/v1/auth/guest') {
        guestCreates++;
        return (
          status: 201,
          body: {
            'accessToken': _jwt(
              playerId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
              familyId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
              accountType: 'guest',
            ),
            'refreshToken': 'c' * 64,
            'expiresAt': DateTime.now()
                .toUtc()
                .add(const Duration(hours: 1))
                .toIso8601String(),
          },
        );
      }
      fail('unexpected $path');
    };
    final refreshFuture = auth.authenticate(forceRefresh: true);
    await refreshStarted.future;
    final replaceFuture = auth.replaceWithExplicitNewGuest();
    refreshGate.complete();
    final replaced = await replaceFuture;
    expect(guestCreates, 1);
    expect(replaced.playerId, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
    expect(store.token, 'c' * 64);
    // Stale refresh must not overwrite the explicit replacement vault.
    await expectLater(
      refreshFuture,
      throwsA(isA<GuestAuthException>().having(
        (e) => e.code,
        'code',
        'STALE_CREDENTIAL_RESPONSE',
      )),
    );
    expect(store.token, 'c' * 64);
    expect(refreshCalls, 1);
  });

  test('explicit new guest create failure preserves old credentials', () async {
    final store = FakeGuestStore()
      ..token = 'r' * 64
      ..identityBinding =
          'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa||guest';
    final auth = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    auth.debugTransport = (path, body) async {
      if (path == '/v1/auth/guest') {
        return (status: 503, body: {'error': 'AUTH_UNAVAILABLE'});
      }
      fail('unexpected $path');
    };
    await expectLater(
      auth.replaceWithExplicitNewGuest(),
      throwsA(isA<GuestAuthException>().having(
        (e) => e.code,
        'code',
        'GUEST_CREATION_UNAVAILABLE',
      )),
    );
    expect(store.token, 'r' * 64);
    expect(store.identityBinding,
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa||guest');
  });

  test('explicit new guest vault failure restores prior credentials', () async {
    final store = FakeGuestStore()
      ..token = 's' * 64
      ..identityBinding =
          'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa||guest'
      ..failWrite = true;
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
              playerId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
              familyId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
              accountType: 'guest',
            ),
            'refreshToken': 't' * 64,
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
    // failWrite prevents overwrite; prior token remains.
    expect(store.token, 's' * 64);
    expect(store.identityBinding,
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa||guest');
    expect(store.vaultJournal, isNull);
  });

  test('pending link blocks explicit new guest mint', () async {
    final store = FakeGuestStore()
      ..token = 'u' * 64
      ..pendingLink =
          'google|aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    final auth = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    var guestCreates = 0;
    auth.debugTransport = (path, body) async {
      if (path == '/v1/auth/guest') guestCreates++;
      fail('must not mint while pending link');
    };
    await expectLater(
      auth.replaceWithExplicitNewGuest(),
      throwsA(isA<GuestAuthException>().having(
        (e) => e.code,
        'code',
        'PROVIDER_LINK_RECOVERY_GOOGLE',
      )),
    );
    expect(guestCreates, 0);
    expect(store.token, 'u' * 64);
  });

  test('concurrent authenticate single-flights without dual refresh', () async {
    final store = FakeGuestStore()..token = 'v' * 64;
    final auth = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
      rotationRetryEnabled: false,
    );
    var refreshCalls = 0;
    final gate = Completer<void>();
    auth.debugTransport = (path, body) async {
      if (path == '/v1/auth/refresh') {
        refreshCalls++;
        await gate.future;
        return (
          status: 200,
          body: {
            'accessToken': _jwt(
              playerId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
              familyId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
            ),
            'refreshToken': 'w' * 64,
            'expiresAt': DateTime.now()
                .toUtc()
                .add(const Duration(hours: 1))
                .toIso8601String(),
          },
        );
      }
      fail('unexpected $path');
    };
    final a = auth.authenticate(forceRefresh: true);
    final b = auth.authenticate(forceRefresh: true);
    gate.complete();
    final results = await Future.wait([a, b]);
    expect(refreshCalls, 1);
    expect(results[0].accessToken, results[1].accessToken);
    expect(store.token, 'w' * 64);
  });
}

final class _RecordingCrashReporter implements CrashReporter {
  var nonFatals = 0;
  @override
  Future<void> recordFatal(Object error, StackTrace stack) async {}
  @override
  Future<void> recordNonFatal(Object error, StackTrace stack) async {
    nonFatals++;
  }
}

final class _FailingCrashReporter implements CrashReporter {
  @override
  Future<void> recordFatal(Object error, StackTrace stack) async {}
  @override
  Future<void> recordNonFatal(Object error, StackTrace stack) async {
    throw StateError('crashlytics denied');
  }
}
