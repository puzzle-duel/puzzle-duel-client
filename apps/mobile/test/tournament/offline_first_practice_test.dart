import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/tournament/local_kv_store.dart';
import 'package:puzzle_duel_mobile/tournament/practice_identity.dart';
import 'package:puzzle_duel_mobile/tournament/practice_store.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_home_snapshot.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_uat_app.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';

import 'tournament_command_test.dart' show ScriptedUatApi;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cold launch with unreachable backend opens Home and Practice', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-offline-boot');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    var claimPosts = 0;
    final api = ScriptedUatApi((method, path, body) async {
      if (path.endsWith('/claims/daily')) claimPosts += 1;
      return const UatHttpResult(0, {'error': 'OFFLINE'});
    });
    await _pumpUntilPractice(tester, api, directory);
    expect(find.byKey(const Key('home-title')), findsOneWidget);
    expect(find.byKey(const Key('practice')), findsOneWidget);
    expect(find.byKey(const Key('tournament-status')), findsOneWidget);
    expect(claimPosts, 0);
  });

  testWidgets('tournament timeout never replaces Home with recovery', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-timeout-home');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final api = ScriptedUatApi((method, path, body) async {
      if (path.endsWith('/session') && method == 'POST') {
        return const UatHttpResult(201, {
          'playerId': '11111111-1111-4111-8111-111111111111',
          'sessionSecret': 'secret',
        });
      }
      return const UatHttpResult(0, {'error': 'TIMEOUT'});
    });
    await _pumpUntilPractice(tester, api, directory);
    expect(find.textContaining('timed out'), findsOneWidget);
    expect(find.byKey(const Key('practice')), findsOneWidget);
    expect(find.text('Try again'), findsWidgets);
  });

  testWidgets('offline practice easy completes and persists after restart', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-offline-play');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final api = ScriptedUatApi(
      (method, path, body) async => const UatHttpResult(0, {'error': 'OFFLINE'}),
    );
    await _pumpUntilPractice(tester, api, directory);
    await tester.tap(find.byKey(const Key('practice')));
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.byKey(const Key('practice-easy')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('5×5 board'), findsOneWidget);

    final identity = PracticeIdentityStore(directory, random: Random(1));
    await identity.load();
    final store = PracticeStore(
      directory: directory,
      scope: identity.activeScope,
      identity: identity,
    );
    expect(
      await store.append(
        PracticeRecord(
          sessionId: 'offline-1',
          difficulty: 'easy',
          rulesVersion: 'core-001.v2',
          generatorVersion: 'gen-001.v1',
          seed: 7,
          score: 42,
          terminalReason: 'move_limit_reached',
          completedAt: '2026-11-19T12:00:00.000Z',
          moveCount: 15,
        ),
      ),
      isTrue,
    );
    expect(await store.append(
      PracticeRecord(
        sessionId: 'offline-1',
        difficulty: 'easy',
        rulesVersion: 'core-001.v2',
        generatorVersion: 'gen-001.v1',
        seed: 7,
        score: 42,
        terminalReason: 'move_limit_reached',
        completedAt: '2026-11-19T12:00:00.000Z',
      ),
    ), isFalse);

    final restarted = PracticeStore(
      directory: directory,
      scope: identity.activeScope,
      identity: identity,
    );
    expect(await restarted.load(), hasLength(1));
    expect(
      await restarted.bestScore(
        'easy',
        rulesVersion: 'core-001.v2',
        generatorVersion: 'gen-001.v1',
      ),
      42,
    );
  });

  test('cached tournament snapshot never leaks across player scopes', () async {
    final kv = MemoryKvStore();
    final store = TournamentHomeSnapshotStore(kv);
    final playerA = PracticeIdentityScope.tryPlayer(
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    )!;
    final playerB = PracticeIdentityScope.tryPlayer(
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    )!;
    final guest = PracticeIdentityScope.guest(
      'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    );
    await store.save(
      TournamentHomeSnapshot(
        scopeKey: playerA.storageKey,
        capturedAtMs: 1000,
        originalUtcDate: '2026-11-19',
        seriesId: 'series-a',
        ordinal: 2,
        ordinalLabel: 'E2',
        seriesScore: 50,
        awaitAdvance: false,
        resultsPublished: false,
        claimStatus: 'ACTIVE',
        original: true,
      ),
    );
    expect(await store.load(playerB), isNull);
    expect(await store.load(guest), isNull);
    expect((await store.load(playerA))?.seriesId, 'series-a');
  });

  test('corrupt tournament snapshot falls back safely', () async {
    final kv = MemoryKvStore({
      'tournament-home-guest_cccccccc-cccc-4ccc-8ccc-cccccccccccc.json':
          '{not-json',
    });
    final store = TournamentHomeSnapshotStore(kv);
    final guest = PracticeIdentityScope.guest(
      'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    );
    expect(await store.load(guest), isNull);
  });

  test('memory kv store keeps practice I/O off Directory Sync APIs', () async {
    final kv = MemoryKvStore();
    final scope = PracticeIdentityScope.guest(
      'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    );
    final store = PracticeStore(scope: scope, store: kv);
    expect(await store.nextSeed(), 1);
    expect(await store.nextSeed(), 2);
    expect(await kv.read('practice-seed-${scope.storageKey}.txt'), '3');
  });

  testWidgets('network restore refreshes tournament without blocking practice', (
    tester,
  ) async {
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .accessibilityFeaturesTestValue = FakeAccessibilityFeatures(
      disableAnimations: true,
      reduceMotion: true,
    );
    addTearDown(() {
      TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
          .clearAccessibilityFeaturesTestValue();
    });
    final directory = Directory.systemTemp.createTempSync('pzd43-restore-net');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    var online = false;
    final api = ScriptedUatApi((method, path, body) async {
      if (!online) return const UatHttpResult(0, {'error': 'OFFLINE'});
      if (path.endsWith('/session') && method == 'POST') {
        return const UatHttpResult(201, {
          'playerId': '22222222-2222-4222-8222-222222222222',
          'sessionSecret': 'secret',
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
          'score': 0,
          'awaitAdvance': false,
          'resultsPublished': false,
          'state': {'turnsUsed': 0, 'moveLimit': 15, 'boardSize': 5},
        });
      }
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });
    await _pumpUntilPractice(tester, api, directory);
    expect(find.byKey(const Key('tournament-status')), findsOneWidget);
    expect(
      find.text('No connection. You can keep practicing.'),
      findsOneWidget,
    );
    online = true;
    await tester.tap(find.byKey(const Key('tournament-retry')));
    await tester.pump();
    // primary-action exists offline too (retry CTA) — wait for notice clear.
    for (var i = 0; i < 80; i++) {
      if (find
          .text('No connection. You can keep practicing.')
          .evaluate()
          .isEmpty) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const Key('practice')), findsOneWidget);
    expect(
      find.text('No connection. You can keep practicing.'),
      findsNothing,
    );
    expect(
      find.text('Tournament info updated.'),
      findsOneWidget,
    );
    // Reduced-motion success banner dismisses after the hold without layout shift.
    await tester.pump(const Duration(milliseconds: 2600));
    await tester.pump();
    expect(find.byKey(const Key('tournament-status')), findsNothing);
  });

  test('snapshot JSON stays bounded without raw board payloads', () {
    final snap = TournamentHomeSnapshot(
      scopeKey: 'player_eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
      capturedAtMs: 42,
      originalUtcDate: '2026-11-19',
      seriesId: 's1',
      ordinal: 1,
      ordinalLabel: 'E1',
      seriesScore: 10,
      awaitAdvance: false,
      resultsPublished: false,
      claimStatus: 'ACTIVE',
      original: true,
    );
    final encoded = jsonEncode(snap.toJson());
    expect(encoded.contains('cells'), isFalse);
    expect(encoded.contains('offers'), isFalse);
    expect(TournamentHomeSnapshot.tryParse(jsonDecode(encoded))?.seriesId, 's1');
  });
}

Future<void> _pumpUntilPractice(
  WidgetTester tester,
  ScriptedUatApi api,
  Directory directory,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    TournamentUatApp(
      config: const UatConfig(
        baseUrl: 'http://127.0.0.1',
        bearer: 'Bearer test',
        playerLabel: 'offline',
      ),
      api: api,
      stateDirectory: directory,
      haptics: const SilentTournamentHaptics(),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 40; i++) {
    if (find.byKey(const Key('practice')).evaluate().isNotEmpty) break;
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(find.byKey(const Key('practice')), findsOneWidget);
}
