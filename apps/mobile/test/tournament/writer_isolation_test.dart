import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/tournament/practice_identity.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_controller.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';

import 'tournament_command_test.dart' show ScriptedUatApi;

/// Same-device Player A → B → A must keep distinct writer sessions.
///
/// Backend fences moves to the active writer session/device. Opening a fresh
/// POST /session for a returning player who already claimed today yields
/// WRITER_NOT_AUTHORIZED — that is intended. The client must therefore retain
/// per-authBinding secrets instead of overwriting a single session file.
void main() {
  test('A→B→A keeps both writer session secrets in the vault', () async {
    final directory = Directory.systemTemp.createTempSync('pzd43-writer-vault');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final posts = <String>[];
    final gets = <String>[];
    Future<UatHttpResult> handler(
      String method,
      String path,
      Object? body, {
      required String playerId,
      required String secret,
      required String seriesId,
    }) async {
      if (path.endsWith('/session') && method == 'POST') {
        posts.add(playerId);
        return UatHttpResult(201, {
          'playerId': playerId,
          'sessionSecret': secret,
        });
      }
      if (path.endsWith('/session') && method == 'GET') {
        gets.add(secret);
        return UatHttpResult(200, {
          'playerId': playerId,
          'sessionId': 'session-$playerId',
          'deviceId': 'device-$playerId',
        });
      }
      if (path.endsWith('/claims/daily')) {
        return UatHttpResult(201, {
          'seriesId': seriesId,
          'status': 'ACTIVE',
          'original': true,
          'writerGeneration': 1,
        });
      }
      if (path.contains('/board')) {
        return UatHttpResult(200, {
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
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    }

    const playerA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    const playerB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
    const secretA = 'secret-player-a-writer';
    const secretB = 'secret-player-b-writer';

    Future<TournamentController> boot({
      required String bearer,
      required String label,
      required String playerId,
      required String secret,
      required String seriesId,
    }) async {
      final api = ScriptedUatApi(
        (method, path, body) => handler(
          method,
          path,
          body,
          playerId: playerId,
          secret: secret,
          seriesId: seriesId,
        ),
      );
      final identity = PracticeIdentityStore(directory);
      await identity.load();
      final controller = TournamentController(
        config: UatConfig(
          baseUrl: 'http://127.0.0.1',
          bearer: bearer,
          playerLabel: label,
        ),
        api: api,
        stateDirectory: directory,
        identity: identity,
        haptics: const SilentTournamentHaptics(),
      );
      await controller.start();
      return controller;
    }

    final a1 = await boot(
      bearer: 'Bearer player-a',
      label: 'Player A',
      playerId: playerA,
      secret: secretA,
      seriesId: 'series-a',
    );
    expect(a1.api.sessionSecret, secretA);
    expect(a1.seriesId, 'series-a');
    expect(posts, [playerA]);

    final b1 = await boot(
      bearer: 'Bearer player-b',
      label: 'Player B',
      playerId: playerB,
      secret: secretB,
      seriesId: 'series-b',
    );
    expect(b1.api.sessionSecret, secretB);
    expect(b1.seriesId, 'series-b');
    expect(posts, [playerA, playerB]);

    final vault = jsonDecode(
      File('${directory.path}/pzd-uat-session.json').readAsStringSync(),
    ) as Map;
    final sessions = vault['sessions'] as Map;
    expect(
      (sessions[UatApi.authBinding('Bearer player-a')] as Map)['secret'],
      secretA,
    );
    expect(
      (sessions[UatApi.authBinding('Bearer player-b')] as Map)['secret'],
      secretB,
    );

    // Returning to A must restore the writer session via GET, not POST.
    posts.clear();
    gets.clear();
    final a2 = await boot(
      bearer: 'Bearer player-a',
      label: 'Player A',
      playerId: playerA,
      secret: secretA,
      seriesId: 'series-a',
    );
    expect(a2.api.sessionSecret, secretA);
    expect(posts, isEmpty);
    expect(gets, [secretA]);
    expect(a2.seriesId, 'series-a');
  });

  test('legacy single-binding file migrates without blocking the other player',
      () async {
    final directory = Directory.systemTemp.createTempSync('pzd43-writer-legacy');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    File('${directory.path}/pzd-uat-session.json').writeAsStringSync(
      jsonEncode({
        'secret': 'legacy-a-secret',
        'authBinding': UatApi.authBinding('Bearer player-a'),
        'apiOrigin': 'http://127.0.0.1',
      }),
    );
    var posts = 0;
    final apiB = ScriptedUatApi((method, path, body) async {
      if (path.endsWith('/session') && method == 'POST') {
        posts += 1;
        return const UatHttpResult(201, {
          'playerId': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
          'sessionSecret': 'fresh-b-secret',
        });
      }
      if (path.endsWith('/claims/daily')) {
        return const UatHttpResult(201, {
          'seriesId': 'series-b',
          'status': 'ACTIVE',
          'original': true,
        });
      }
      if (path.contains('/board')) {
        return const UatHttpResult(200, {
          'ordinal': 1,
          'ordinalLabel': 'E1',
          'seriesScore': 0,
          'awaitAdvance': false,
          'resultsPublished': false,
          'state': {'turnsUsed': 0, 'moveLimit': 15, 'boardSize': 5},
        });
      }
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });
    final identity = PracticeIdentityStore(directory);
    await identity.load();
    final controllerB = TournamentController(
      config: const UatConfig(
        baseUrl: 'http://127.0.0.1',
        bearer: 'Bearer player-b',
        playerLabel: 'Player B',
      ),
      api: apiB,
      stateDirectory: directory,
      identity: identity,
      haptics: const SilentTournamentHaptics(),
    );
    await controllerB.start();
    expect(posts, 1);
    expect(controllerB.api.sessionSecret, 'fresh-b-secret');

    final vault = jsonDecode(
      File('${directory.path}/pzd-uat-session.json').readAsStringSync(),
    ) as Map;
    final sessions = vault['sessions'] as Map;
    expect(
      (sessions[UatApi.authBinding('Bearer player-a')] as Map)['secret'],
      'legacy-a-secret',
    );
    expect(
      (sessions[UatApi.authBinding('Bearer player-b')] as Map)['secret'],
      'fresh-b-secret',
    );
  });

  test('stale second session for same player surfaces WRITER_NOT_AUTHORIZED',
      () async {
    final directory = Directory.systemTemp.createTempSync('pzd43-writer-409');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    var commandPosts = 0;
    final api = ScriptedUatApi((method, path, body) async {
      if (path.endsWith('/session') && method == 'POST') {
        return const UatHttpResult(201, {
          'playerId': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
          'sessionSecret': 'new-device-session',
        });
      }
      if (path.endsWith('/claims/daily')) {
        // Existing claim: server keeps the original writer binding.
        return const UatHttpResult(200, {
          'seriesId': 'series-b',
          'status': 'ACTIVE',
          'original': false,
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
      if (path.endsWith('/commands') && method == 'POST') {
        commandPosts += 1;
        return const UatHttpResult(409, {'error': 'WRITER_NOT_AUTHORIZED'});
      }
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });
    final identity = PracticeIdentityStore(directory);
    await identity.load();
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
    await controller.start();
    expect(controller.seriesId, 'series-b');
    // Board/claim succeed for the series owner even when this session is not
    // the active writer — mutation is what the fence blocks.
    final response = await api.post(
      '/v1/tournament/series/series-b/commands',
      {
        'commandType': 'move',
        'idempotencyKey': 'stale-writer',
        'move': {
          'offerIndex': 0,
          'tap': [0, 0],
          'expectedBoardRevision': 0,
          'writerGeneration': 1,
        },
      },
    );
    expect(response.status, 409);
    expect(response.error, 'WRITER_NOT_AUTHORIZED');
    expect(commandPosts, 1);
  });

  test('authBinding hashes never embed bearer material', () {
    final a = UatApi.authBinding('Bearer player-a-token');
    final b = UatApi.authBinding('Bearer player-b-token');
    expect(a, isNot(b));
    expect(a.contains('player-a'), isFalse);
    expect(b.contains('Bearer'), isFalse);
  });
}
