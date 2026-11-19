import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/tournament/local_kv_store.dart';
import 'package:puzzle_duel_mobile/tournament/practice_identity.dart';
import 'package:puzzle_duel_mobile/tournament/practice_store.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_controller.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_home_snapshot.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';

import 'tournament_command_test.dart' show ScriptedUatApi;

/// PZD-45 MVP regression — client identity / stale-response isolation only.
///
/// Does not invent recovery/takeover. Expired ranked writers remain fail-closed
/// at the server fence (see backend HTTP E2E); the vault keeps per-binding
/// secrets but cannot resurrect an expired writer session.
void main() {
  test(
    'stale loadDay epoch cannot contaminate the active player UI state',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'pzd45-stale-epoch',
      );
      addTearDown(() {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });

      final staleBoard = Completer<UatHttpResult>();
      var claimPosts = 0;
      final api = ScriptedUatApi((method, path, body) async {
        if (path.endsWith('/session') && method == 'POST') {
          return const UatHttpResult(201, {
            'playerId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
            'sessionSecret': 'secret-a',
          });
        }
        if (path.endsWith('/claims/daily')) {
          claimPosts += 1;
          if (claimPosts == 1) {
            return const UatHttpResult(201, {
              'seriesId': 'series-active',
              'status': 'ACTIVE',
              'original': true,
              'writerGeneration': 1,
            });
          }
          return const UatHttpResult(200, {
            'seriesId': 'series-stale',
            'status': 'ACTIVE',
            'original': false,
            'writerGeneration': 1,
          });
        }
        if (path.contains('/board')) {
          if (claimPosts == 1) {
            return const UatHttpResult(200, {
              'ordinal': 1,
              'ordinalLabel': 'E1',
              'seriesScore': 12,
              'boardRevision': 0,
              'writerGeneration': 1,
              'awaitAdvance': false,
              'resultsPublished': false,
              'state': {'turnsUsed': 0, 'moveLimit': 15, 'boardSize': 5},
            });
          }
          return staleBoard.future;
        }
        return const UatHttpResult(404, {'error': 'NOT_FOUND'});
      });

      final identity = PracticeIdentityStore(directory);
      await identity.load();
      final controller = TournamentController(
        config: const UatConfig(
          baseUrl: 'http://127.0.0.1',
          bearer: 'Bearer player-a',
          playerLabel: 'Player A',
        ),
        api: api,
        stateDirectory: directory,
        identity: identity,
        haptics: const SilentTournamentHaptics(),
      );

      await controller.start();
      expect(controller.seriesId, 'series-active');
      expect(controller.day?.seriesScore, 12);
      final activeEpoch = claimPosts;

      // Simulate an in-flight response from a superseded refresh epoch.
      final stale = controller.loadDay(presentHome: true, epoch: 0);
      staleBoard.complete(
        const UatHttpResult(200, {
          'ordinal': 3,
          'ordinalLabel': 'M1',
          'seriesScore': 9999,
          'boardRevision': 9,
          'writerGeneration': 7,
          'awaitAdvance': false,
          'resultsPublished': false,
          'state': {'turnsUsed': 4, 'moveLimit': 15, 'boardSize': 6},
        }),
      );
      await stale;

      expect(controller.seriesId, 'series-active');
      expect(controller.day?.seriesScore, 12);
      expect(controller.day?.ordinalLabel, 'E1');
      expect(claimPosts, greaterThan(activeEpoch));
    },
  );

  test(
    'ranked home snapshot cache stays isolated by internal playerId',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'pzd45-snapshot-iso',
      );
      addTearDown(() {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });

      const alice = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
      const bob = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
      final kv = DirectoryKvStore(directory);
      final snapshots = TournamentHomeSnapshotStore(kv);

      await snapshots.save(
        TournamentHomeSnapshot(
          scopeKey: 'player_$alice',
          capturedAtMs: 1_700_000_000_000,
          originalUtcDate: '2026-11-19',
          seriesId: 'series-alice',
          ordinal: 2,
          ordinalLabel: 'E2',
          seriesScore: 42,
          awaitAdvance: false,
          resultsPublished: false,
          claimStatus: 'ACTIVE',
          original: true,
          verifiedAll: 900,
          onTimeAwarded: true,
        ),
      );

      final identity = PracticeIdentityStore(directory);
      await identity.load();
      expect(await identity.bindAuthenticatedPlayer(bob), isTrue);

      final api = ScriptedUatApi((method, path, body) async {
        if (path.endsWith('/session') && method == 'POST') {
          return const UatHttpResult(201, {
            'playerId': bob,
            'sessionSecret': 'secret-bob',
          });
        }
        // Offline ranked refresh: must not leak Alice's cached series.
        return const UatHttpResult(0, {'error': 'OFFLINE'});
      });

      final controller = TournamentController(
        config: const UatConfig(
          baseUrl: 'http://127.0.0.1',
          bearer: 'Bearer player-b',
          playerLabel: 'Player B',
        ),
        api: api,
        stateDirectory: directory,
        identity: identity,
        haptics: const SilentTournamentHaptics(),
      );

      await controller.beginLocal();
      expect(controller.seriesId, isNull);
      expect(controller.day, isNull);
      expect(controller.homeSnapshot, isNull);
      expect(controller.results, isEmpty);

      // Alice's disk cache remains intact for her scope.
      final aliceSnap = await snapshots.load(
        PracticeIdentityScope.tryPlayer(alice)!,
      );
      expect(aliceSnap?.seriesId, 'series-alice');
      expect(aliceSnap?.seriesScore, 42);
      expect(aliceSnap?.onTimeAwarded, isTrue);
    },
  );

  test(
    'practice scores never become ranked series/results state',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'pzd45-practice-ranked',
      );
      addTearDown(() {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });

      const playerId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
      final identity = PracticeIdentityStore(directory);
      await identity.load();
      await identity.bindAuthenticatedPlayer(playerId);
      await PracticeStore(
        directory: directory,
        scope: identity.activeScope,
        identity: identity,
      ).append(
        PracticeRecord(
          sessionId: 'practice-1',
          difficulty: 'hard',
          rulesVersion: 'core-001.v3',
          generatorVersion: 'gen-001.v1',
          seed: 7,
          score: 7777,
          terminalReason: 'ended',
          completedAt: '2026-11-19T12:00:00.000Z',
        ),
      );

      var commandPosts = 0;
      final api = ScriptedUatApi((method, path, body) async {
        if (path.endsWith('/session') && method == 'POST') {
          return const UatHttpResult(201, {
            'playerId': playerId,
            'sessionSecret': 'secret',
          });
        }
        if (path.endsWith('/claims/daily')) {
          return const UatHttpResult(201, {
            'seriesId': 'series-ranked',
            'status': 'ACTIVE',
            'original': true,
            'writerGeneration': 1,
          });
        }
        if (path.contains('/board')) {
          return const UatHttpResult(200, {
            'ordinal': 1,
            'ordinalLabel': 'E1',
            'seriesScore': 0,
            'boardRevision': 0,
            'writerGeneration': 1,
            'awaitAdvance': false,
            'resultsPublished': false,
            'state': {'turnsUsed': 0, 'moveLimit': 15, 'boardSize': 5},
          });
        }
        if (path.endsWith('/commands')) {
          commandPosts += 1;
        }
        return const UatHttpResult(404, {'error': 'NOT_FOUND'});
      });

      final controller = TournamentController(
        config: const UatConfig(
          baseUrl: 'http://127.0.0.1',
          bearer: 'Bearer player-c',
          playerLabel: 'Player C',
        ),
        api: api,
        stateDirectory: directory,
        identity: identity,
        haptics: const SilentTournamentHaptics(),
      );

      await controller.start();
      expect(controller.seriesId, 'series-ranked');
      expect(controller.day?.seriesScore, 0);
      expect(controller.results, isEmpty);
      expect(commandPosts, 0);
      expect(
        await controller.practiceStore().bestScore(
          'hard',
          rulesVersion: 'core-001.v3',
          generatorVersion: 'gen-001.v1',
        ),
        7777,
      );
    },
  );
}
