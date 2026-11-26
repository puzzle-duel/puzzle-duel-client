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
        'PROVIDER_LINK_RECOVERY_apple');
    expect(controller.activeSessionRecovery?.expectedPlayerId,
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
    expect(controller.activeSessionRecovery?.pendingLink?.provider, 'apple');
    expect(controller.activeSessionRecovery?.lastRequestId, isNotNull);
    expect(controller.rankedWriterLocked, isTrue);
    expect(controller.tournamentNoticeCode, 'PROVIDER_LINK_RECOVERY_apple');
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
