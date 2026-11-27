import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/tournament/practice_identity.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_controller.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';

import 'tournament_command_test.dart' show ScriptedUatApi;

void main() {
  test('delayed renewal after invalidate cannot restore old secret or clear '
      'newer in-flight renewal', () async {
    final dir = Directory.systemTemp.createTempSync('pzd-renewal-invalidate-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final identity = PracticeIdentityStore(dir);
    await identity.load();

    const playerA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    const sessionA = '11111111-1111-4111-8111-111111111111';
    const playerB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
    const sessionB = '22222222-2222-4222-8222-222222222222';
    final firstExpiry = DateTime.now().millisecondsSinceEpoch + 45_000;

    final renewGate = Completer<void>();
    var renewals = 0;
    var sessionOpens = 0;
    late final ScriptedUatApi api;
    api = ScriptedUatApi((method, path, body) async {
      if (path == '/v1/tournament/session' && method == 'POST') {
        sessionOpens++;
        if (sessionOpens == 1) {
          return UatHttpResult(201, {
            'playerId': playerA,
            'sessionId': sessionA,
            'sessionSecret': 'secret-a',
            'expiresAtMs': firstExpiry,
          });
        }
        return UatHttpResult(201, {
          'playerId': playerB,
          'sessionId': sessionB,
          'sessionSecret': 'secret-b',
          'expiresAtMs': DateTime.now().millisecondsSinceEpoch + 45_000,
        });
      }
      if (path == '/v1/tournament/session' && method == 'PATCH') {
        renewals++;
        // First renewal is delayed across invalidate + account switch.
        if (renewals == 1) {
          await renewGate.future;
          // Stale response for account A — must be discarded.
          return UatHttpResult(200, {
            'playerId': playerA,
            'sessionId': sessionA,
            'expiresAtMs': DateTime.now().millisecondsSinceEpoch + 45_000,
          });
        }
        return UatHttpResult(200, {
          'playerId': playerB,
          'sessionId': sessionB,
          'expiresAtMs': DateTime.now().millisecondsSinceEpoch + 45_000,
        });
      }
      if (path.endsWith('/devices/register')) {
        return const UatHttpResult(200, {});
      }
      if (path.endsWith('/claims/daily')) {
        return const UatHttpResult(201, {
          'seriesId': '33333333-3333-4333-8333-333333333333',
          'status': 'ACTIVE',
          'original': true,
        });
      }
      if (path.endsWith('/board')) {
        return const UatHttpResult(200, {
          'ordinal': 1,
          'awaitAdvance': true,
          'boardRevision': 1,
          'writerGeneration': 1,
        });
      }
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });

    final controller = TournamentController(
      config: const UatConfig(
        baseUrl: 'http://127.0.0.1',
        bearer: 'Bearer account-a',
        playerLabel: 'A',
      ),
      api: api,
      stateDirectory: dir,
      identity: identity,
      haptics: const SilentTournamentHaptics(),
    );
    addTearDown(controller.dispose);

    await controller.start();
    expect(api.sessionSecret, 'secret-a');

    // Start proactive renewal, then invalidate before it completes.
    controller.setAppForeground(false);
    controller.setAppForeground(true);
    for (var i = 0; i < 50 && renewals == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(renewals, 1);

    await controller.invalidateTournamentGameplaySession(reason: 'logout');
    expect(api.sessionSecret, isNull);

    // New account gameplay session while stale renewal is still pending.
    api.bearer = UatApi.normalizeBearer('Bearer account-b');
    await controller.refreshTournament(
      origin: TournamentRefreshOrigin.pullToRefresh,
    );
    expect(api.sessionSecret, 'secret-b');

    // Start a second renewal for account B.
    controller.setAppForeground(false);
    controller.setAppForeground(true);
    for (var i = 0; i < 50 && renewals < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(renewals, greaterThanOrEqualTo(2));

    // Release stale account-A renewal; must not restore secret-a or wipe B.
    renewGate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(api.sessionSecret, 'secret-b');
    expect(api.sessionSecret, isNot('secret-a'));
  });

  test('logout invalidate discards delayed renewal before guest session binds',
      () async {
    final dir = Directory.systemTemp.createTempSync('pzd-renewal-logout-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final identity = PracticeIdentityStore(dir);
    await identity.load();

    const playerId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
    const sessionId = '44444444-4444-4444-8444-444444444444';
    final renewGate = Completer<void>();
    var renewals = 0;
    late final ScriptedUatApi api;
    api = ScriptedUatApi((method, path, body) async {
      if (path == '/v1/tournament/session' && method == 'POST') {
        return UatHttpResult(201, {
          'playerId': playerId,
          'sessionId': sessionId,
          'sessionSecret': 'secret-verified',
          'expiresAtMs': DateTime.now().millisecondsSinceEpoch + 45_000,
        });
      }
      if (path == '/v1/tournament/session' && method == 'PATCH') {
        renewals++;
        await renewGate.future;
        return UatHttpResult(200, {
          'playerId': playerId,
          'sessionId': sessionId,
          'expiresAtMs': DateTime.now().millisecondsSinceEpoch + 45_000,
        });
      }
      if (path.endsWith('/devices/register')) {
        return const UatHttpResult(200, {});
      }
      if (path.endsWith('/claims/daily')) {
        return const UatHttpResult(201, {
          'seriesId': '55555555-5555-4555-8555-555555555555',
          'status': 'ACTIVE',
          'original': true,
        });
      }
      if (path.endsWith('/board')) {
        return const UatHttpResult(200, {
          'ordinal': 1,
          'awaitAdvance': true,
          'boardRevision': 1,
          'writerGeneration': 1,
        });
      }
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });

    final controller = TournamentController(
      config: const UatConfig(
        baseUrl: 'http://127.0.0.1',
        bearer: 'Bearer verified',
        playerLabel: 'Verified',
      ),
      api: api,
      stateDirectory: dir,
      identity: identity,
      haptics: const SilentTournamentHaptics(),
    );
    addTearDown(controller.dispose);
    await controller.start();
    controller.setAppForeground(false);
    controller.setAppForeground(true);
    for (var i = 0; i < 50 && renewals == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(renewals, 1);

    controller.applyGuestSessionAfterLogout(rankedAuthRequired: true);
    expect(api.sessionSecret, isNull);

    renewGate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(api.sessionSecret, isNull);
  });
}
