import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/presentation/debug/interaction_perf.dart';
import 'package:puzzle_duel_mobile/tournament/local_kv_store.dart';
import 'package:puzzle_duel_mobile/tournament/practice_identity.dart';
import 'package:puzzle_duel_mobile/tournament/practice_store.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_controller.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_home_snapshot.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';

import 'tournament_command_test.dart' show ScriptedUatApi;

void main() {
  test('normalizeBearer and apiOrigin stay credential-free', () {
    expect(UatApi.normalizeBearer('token-a'), 'Bearer token-a');
    expect(UatApi.normalizeBearer('Bearer token-a'), 'Bearer token-a');
    expect(UatApi.normalizeBearer('bearer token-a'), 'Bearer token-a');
    expect(
      UatApi.apiOrigin('http://192.168.68.52:8787/'),
      'http://192.168.68.52:8787',
    );
    expect(UatApi.apiOrigin('https://example.com'), 'https://example.com');
    final binding = UatApi.authBinding('Bearer secret-token');
    expect(binding.contains('secret'), isFalse);
    expect(binding.contains('Bearer'), isFalse);
  });

  test('legacy unbound session is ignored and POST opens a fresh session', () async {
    final directory = Directory.systemTemp.createTempSync('pzd43-session-legacy');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    File('${directory.path}/pzd-uat-session.json').writeAsStringSync(
      jsonEncode({'secret': 'legacy-secret'}),
    );
    final calls = <String>[];
    final api = ScriptedUatApi((method, path, body) async {
      calls.add('$method $path');
      if (path.endsWith('/session') && method == 'GET') {
        fail('legacy unbound secret must not be validated via GET');
      }
      if (path.endsWith('/session') && method == 'POST') {
        return const UatHttpResult(201, {
          'playerId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'sessionSecret': 'fresh-secret',
        });
      }
      if (path.endsWith('/claims/daily')) {
        return const UatHttpResult(201, {
          'seriesId': 'series-1',
          'status': 'ACTIVE',
          'original': true,
        });
      }
      if (path.endsWith('/board')) {
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
    final controller = TournamentController(
      config: const UatConfig(
        baseUrl: 'http://192.168.68.52:8787',
        bearer: 'Bearer player-a',
        playerLabel: 'Player A',
      ),
      api: api,
      stateDirectory: directory,
      identity: identity,
      haptics: const SilentTournamentHaptics(),
    );
    await controller.beginLocal();
    await controller.refreshTournament();
    expect(calls, contains('POST /v1/tournament/session'));
    expect(calls.where((c) => c.startsWith('GET /v1/tournament/session')), isEmpty);
    expect(api.sessionSecret, 'fresh-secret');
    expect(controller.tournamentReady, isTrue);
    final persisted = jsonDecode(
      File('${directory.path}/pzd-uat-session.json').readAsStringSync(),
    ) as Map;
    final binding = UatApi.authBinding('Bearer player-a');
    final sessions = persisted['sessions'] as Map;
    expect(sessions[binding], isA<Map>());
    expect((sessions[binding] as Map)['secret'], 'fresh-secret');
    expect(
      (sessions[binding] as Map)['apiOrigin'],
      'http://192.168.68.52:8787',
    );
  });

  test('bound session for other bearer is not reused', () async {
    final directory = Directory.systemTemp.createTempSync('pzd43-session-switch');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    File('${directory.path}/pzd-uat-session.json').writeAsStringSync(
      jsonEncode({
        'secret': 'player-a-secret',
        'authBinding': UatApi.authBinding('Bearer player-a'),
        'apiOrigin': 'http://192.168.68.52:8787',
      }),
    );
    final calls = <String>[];
    late final ScriptedUatApi api;
    api = ScriptedUatApi((method, path, body) async {
      calls.add('$method $path');
      if (path.endsWith('/session') && method == 'GET') {
        fail('foreign bearer session must not be validated via GET');
      }
      if (path.endsWith('/session') && method == 'POST') {
        expect(api.sessionSecret, isNull);
        return const UatHttpResult(201, {
          'playerId': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
          'sessionSecret': 'player-b-secret',
        });
      }
      if (path.endsWith('/claims/daily')) {
        return const UatHttpResult(201, {
          'seriesId': 'series-b',
          'status': 'ACTIVE',
          'original': true,
        });
      }
      if (path.endsWith('/board')) {
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
    final controller = TournamentController(
      config: const UatConfig(
        baseUrl: 'http://192.168.68.52:8787',
        bearer: 'Bearer player-b',
        playerLabel: 'Player B',
      ),
      api: api,
      stateDirectory: directory,
      identity: identity,
      haptics: const SilentTournamentHaptics(),
    );
    await controller.start();
    expect(
      calls.where((c) => c.startsWith('GET /v1/tournament/session')),
      isEmpty,
    );
    expect(api.sessionSecret, 'player-b-secret');
  });

  test('connection timeout during bound session GET surfaces TIMEOUT', () async {
    final directory = Directory.systemTemp.createTempSync('pzd43-session-timeout');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    File('${directory.path}/pzd-uat-session.json').writeAsStringSync(
      jsonEncode({
        'secret': 'bound-secret',
        'authBinding': UatApi.authBinding('Bearer player-a'),
        'apiOrigin': 'http://127.0.0.1',
      }),
    );
    var posts = 0;
    final api = ScriptedUatApi((method, path, body) async {
      if (path.endsWith('/session') && method == 'GET') {
        return const UatHttpResult(
          0,
          {'error': 'TIMEOUT', 'timeoutPhase': 'connect'},
          category: UatFailureCategory.connectTimeout,
        );
      }
      if (path.endsWith('/session') && method == 'POST') {
        posts += 1;
        return const UatHttpResult(201, {
          'playerId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'sessionSecret': 'fresh',
        });
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
    await controller.beginLocal();
    await controller.refreshTournament();
    expect(posts, 0);
    expect(controller.tournamentNoticeCode, 'TIMEOUT');
    expect(controller.localReady, isTrue);
  });

  test('claim timeout does not delete practice records', () async {
    final directory = Directory.systemTemp.createTempSync('pzd43-claim-timeout');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final identity = PracticeIdentityStore(directory);
    await identity.load();
    await identity.bindAuthenticatedPlayer(
      'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    );
    final store = PracticeStore(
      directory: directory,
      scope: identity.activeScope,
      store: MemoryKvStore(),
    );
    expect(
      await store.append(
        PracticeRecord(
          sessionId: 'practice-keep',
          difficulty: 'easy',
          rulesVersion: 'core-001.v2',
          generatorVersion: 'gen-001.v1',
          seed: 1,
          score: 9,
          terminalReason: 'move_limit_reached',
          completedAt: '2026-11-19T12:00:00.000Z',
          moveCount: 3,
        ),
      ),
      isTrue,
    );
    final api = ScriptedUatApi((method, path, body) async {
      if (path.endsWith('/session') && method == 'POST') {
        return const UatHttpResult(201, {
          'playerId': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
          'sessionSecret': 'secret',
        });
      }
      if (path.endsWith('/claims/daily')) {
        return const UatHttpResult(
          0,
          {'error': 'TIMEOUT'},
          category: UatFailureCategory.responseTimeout,
        );
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
    expect(controller.tournamentNoticeCode, 'TIMEOUT');
    expect(
      await store.bestScore(
        'easy',
        rulesVersion: 'core-001.v2',
        generatorVersion: 'gen-001.v1',
      ),
      9,
    );
  });

  test('network restore after offline opens session once and claims once', () async {
    final directory = Directory.systemTemp.createTempSync('pzd43-restore-net');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    var online = false;
    var sessionPosts = 0;
    var claims = 0;
    final api = ScriptedUatApi((method, path, body) async {
      if (!online) {
        return const UatHttpResult(
          0,
          {'error': 'TIMEOUT'},
          category: UatFailureCategory.connectTimeout,
        );
      }
      if (path.endsWith('/session') && method == 'POST') {
        sessionPosts += 1;
        return const UatHttpResult(201, {
          'playerId': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
          'sessionSecret': 'secret',
        });
      }
      if (path.endsWith('/claims/daily')) {
        claims += 1;
        return const UatHttpResult(201, {
          'seriesId': 'series-d',
          'status': 'ACTIVE',
          'original': true,
        });
      }
      if (path.endsWith('/board')) {
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
    final controller = TournamentController(
      config: const UatConfig(
        baseUrl: 'http://127.0.0.1',
        bearer: 'Bearer player-d',
        playerLabel: 'Player D',
      ),
      api: api,
      stateDirectory: directory,
      identity: identity,
      haptics: const SilentTournamentHaptics(),
    );
    await controller.beginLocal();
    await controller.refreshTournament();
    expect(controller.tournamentNoticeCode, 'TIMEOUT');
    expect(controller.localReady, isTrue);
    online = true;
    await controller.refreshTournament();
    expect(controller.tournamentReady, isTrue);
    expect(sessionPosts, 1);
    expect(claims, 1);
  });

  test('home snapshot does not leak across player scopes', () async {
    final snapshots = TournamentHomeSnapshotStore(MemoryKvStore());
    final scopeA = PracticeIdentityScope.tryPlayer(
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    )!;
    final scopeB = PracticeIdentityScope.tryPlayer(
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    )!;
    await snapshots.save(
      TournamentHomeSnapshot(
        scopeKey: scopeA.storageKey,
        capturedAtMs: 1,
        originalUtcDate: '2026-11-19',
        seriesId: 'series-a',
        ordinal: 2,
        ordinalLabel: 'E2',
        seriesScore: 40,
        awaitAdvance: false,
        resultsPublished: false,
        claimStatus: 'ACTIVE',
        original: true,
      ),
    );
    expect(await snapshots.load(scopeB), isNull);
    expect((await snapshots.load(scopeA))?.seriesId, 'series-a');
  });

  test('PERF logs never include bearer or session secret', () {
    InteractionPerf.debugEnable(true);
    addTearDown(() {
      InteractionPerf.debugEnable(false);
      InteractionPerf.debugReset();
    });
    final api = UatApi(
      baseUrl: 'http://127.0.0.1:9',
      bearer: 'Bearer super-secret-token',
      sessionSecret: 'session-super-secret',
    );
    expect(api.bearer.startsWith('Bearer '), isTrue);
    final binding = UatApi.authBinding(api.bearer);
    final blob = [
      binding,
      UatApi.apiOrigin(api.baseUrl),
      'PZD_PERF http.start operation=GET endpoint=/v1/tournament/session '
          'status=- category=pending',
      'PZD_PERF http.done operation=POST endpoint=/v1/tournament/session '
          'status=401 category=unauthenticated',
      'PZD_PERF tournament.session.open operation=POST '
          'endpoint=/v1/tournament/session status=401 category=unauthenticated',
    ].join('\n');
    expect(blob.contains('super-secret-token'), isFalse);
    expect(blob.contains('session-super-secret'), isFalse);
    expect(blob.contains('Authorization'), isFalse);
    expect(blob.contains('Bearer '), isFalse);
  });

  test('HTTP 401 is categorized unauthenticated, not ok', () {
    expect(UatApi.categoryForStatus(201), UatFailureCategory.ok);
    expect(UatApi.categoryForStatus(200), UatFailureCategory.ok);
    expect(
      UatApi.categoryForStatus(401),
      UatFailureCategory.unauthenticated,
    );
    expect(UatApi.categoryForStatus(503), UatFailureCategory.server);
    expect(UatApi.categoryForStatus(400), UatFailureCategory.client);
  });

  test('expired bound session GET 401 recovers via POST without UNAUTHENTICATED',
      () async {
    final directory =
        Directory.systemTemp.createTempSync('pzd43-session-expired-secret');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    File('${directory.path}/pzd-uat-session.json').writeAsStringSync(
      jsonEncode({
        'version': 2,
        'sessions': {
          UatApi.authBinding('Bearer player-a'): {
            'secret': 'stale-secret',
            'apiOrigin': 'http://127.0.0.1',
          },
        },
      }),
    );
    final calls = <String>[];
    late final ScriptedUatApi api;
    api = ScriptedUatApi((method, path, body) async {
      calls.add('$method $path');
      if (path.endsWith('/session') && method == 'GET') {
        expect(api.sessionSecret, 'stale-secret');
        return const UatHttpResult(
          401,
          {'error': 'UNAUTHENTICATED'},
          category: UatFailureCategory.unauthenticated,
        );
      }
      if (path.endsWith('/session') && method == 'POST') {
        expect(api.sessionSecret, isNull);
        return const UatHttpResult(201, {
          'playerId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'sessionSecret': 'rotated-secret',
        });
      }
      if (path.endsWith('/claims/daily')) {
        return const UatHttpResult(201, {
          'seriesId': 'series-1',
          'status': 'ACTIVE',
          'original': true,
        });
      }
      if (path.endsWith('/board')) {
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
    await controller.beginLocal();
    await controller.refreshTournament();
    expect(calls, contains('GET /v1/tournament/session'));
    expect(calls, contains('POST /v1/tournament/session'));
    expect(api.sessionSecret, 'rotated-secret');
    expect(controller.tournamentNoticeCode, isNot('UNAUTHENTICATED'));
    expect(controller.tournamentReady, isTrue);
  });

  test('offline and timeout stay distinct from UNAUTHENTICATED', () async {
    expect(UatApi.categoryForStatus(0), UatFailureCategory.offline);
    expect(
      UatApi.categoryForStatus(401),
      UatFailureCategory.unauthenticated,
    );
    expect(
      const UatHttpResult(
        0,
        {'error': 'OFFLINE'},
        category: UatFailureCategory.offline,
      ).isTimeout,
      isFalse,
    );
    expect(
      const UatHttpResult(
        0,
        {'error': 'TIMEOUT', 'timeoutPhase': 'connect'},
        category: UatFailureCategory.connectTimeout,
      ).isTimeout,
      isTrue,
    );
    expect(
      const UatHttpResult(
        401,
        {'error': 'UNAUTHENTICATED'},
        category: UatFailureCategory.unauthenticated,
      ).isTimeout,
      isFalse,
    );
  });

  test('POST /v1/tournament/session 401 is the UNAUTHENTICATED operation',
      () async {
    final directory =
        Directory.systemTemp.createTempSync('pzd43-session-post-401');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final calls = <String>[];
    final api = ScriptedUatApi((method, path, body) async {
      calls.add('$method $path');
      if (path.endsWith('/session') && method == 'POST') {
        return const UatHttpResult(
          401,
          {'error': 'UNAUTHENTICATED'},
          category: UatFailureCategory.unauthenticated,
        );
      }
      fail('unexpected $method $path after bearer rejection');
    });
    final identity = PracticeIdentityStore(directory);
    await identity.load();
    final controller = TournamentController(
      config: const UatConfig(
        baseUrl: 'http://127.0.0.1',
        bearer: 'Bearer expired-or-foreign',
        playerLabel: 'Player A',
      ),
      api: api,
      stateDirectory: directory,
      identity: identity,
      haptics: const SilentTournamentHaptics(),
    );
    await controller.beginLocal();
    await controller.refreshTournament();
    expect(calls, ['POST /v1/tournament/session']);
    expect(controller.tournamentNoticeCode, 'UNAUTHENTICATED');
    expect(controller.localReady, isTrue);
    expect(controller.tournamentReady, isFalse);
  });
}
