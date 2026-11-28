import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/tournament/practice_identity.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_controller.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

import 'tournament_command_test.dart' show ScriptedUatApi;

void main() {
  for (final verifiedAfterRefresh in [false, true]) {
    test('409 rechecks server writer once; verified=$verifiedAfterRefresh; '
        'never resends the move', () async {
      final dir = Directory.systemTemp.createTempSync('pzd-409-one-shot-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final identity = PracticeIdentityStore(dir);
      await identity.load();
      final fixture = jsonDecode(
        File('test/tournament/fixtures/V3-02-single-wave.json').readAsStringSync(),
      ) as Map<String, Object?>;
      var commands = 0;
      var claims = 0;
      var reads = 0;
      var opened = 0;
      final api = ScriptedUatApi((method, path, body) async {
        if (method == 'POST' && path == '/v1/tournament/session') {
          opened++;
          return const UatHttpResult(201, {
            'playerId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
            'sessionId': '33333333-3333-4333-8333-333333333333',
            'sessionSecret': 'session-secret',
          });
        }
        if (method == 'GET' && path == '/v1/tournament/session') {
          return const UatHttpResult(200, {
            'playerId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
            'sessionId': '33333333-3333-4333-8333-333333333333',
          });
        }
        if (path.endsWith('/devices/register')) {
          return const UatHttpResult(404, {'error': 'NOT_FOUND'});
        }
        if (path.endsWith('/claims/daily')) {
          claims++;
          return UatHttpResult(claims == 1 ? 201 : 200, {
            'seriesId': '22222222-2222-4222-8222-222222222222',
            'status': 'ACTIVE', 'original': claims == 1,
          });
        }
        if (path.endsWith('/board')) {
          reads++;
          return UatHttpResult(200, {
            'seriesId': '22222222-2222-4222-8222-222222222222',
            'ordinal': 1, 'ordinalLabel': 'E1',
            'seriesScore': 0, 'score': 0,
            'boardRevision': 1, 'writerGeneration': 1,
            'writerSessionMatches': reads == 1 || verifiedAfterRefresh,
            'awaitAdvance': false, 'resultsPublished': false,
            'state': fixture['initialState'],
          });
        }
        if (path.endsWith('/recovery-challenge')) {
          return const UatHttpResult(409, {'error': 'WRITER_STILL_ACTIVE'});
        }
        if (method == 'POST' && path.endsWith('/commands')) {
          commands++;
          return const UatHttpResult(409, {'error': 'WRITER_NOT_AUTHORIZED'});
        }
        return const UatHttpResult(404, {'error': 'NOT_FOUND'});
      });
      final controller = TournamentController(
        config: const UatConfig(
          baseUrl: 'http://127.0.0.1',
          bearer: 'Bearer test',
          playerLabel: 'writer-409',
        ),
        api: api,
        stateDirectory: dir,
        identity: identity,
        haptics: const SilentTournamentHaptics(),
      );
      await controller.start();
      await controller.resume();
      controller.session.selectOffer(0);
      expect(controller.session.submitTap(Coordinate(row: 0, column: 2)), isTrue);
      await pumpEventQueue();
      expect(commands, 1); // No blind replay, regardless of outcome.
      expect(opened, 1); // Existing session reused; no takeover.
      // Initial selected-manifest claim only; 409 recheck uses board GET, not
      // a second silent claim (PZD-55 identity fence).
      expect(claims, 1);
      expect(reads, greaterThanOrEqualTo(2)); // Explicit writer revalidation.
      expect(controller.session.applyMoveCallCount, 0);
      expect(controller.rankedWriterLocked, !verifiedAfterRefresh);
    });
  }
}
