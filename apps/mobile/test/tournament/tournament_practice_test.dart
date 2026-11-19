import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_uat_app.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

import 'tournament_command_test.dart' show ScriptedUatApi;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .accessibilityFeaturesTestValue = FakeAccessibilityFeatures(
      disableAnimations: true,
      reduceMotion: true,
    );
  });

  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
        .clearAccessibilityFeaturesTestValue();
  });

  testWidgets(
    'practice offers every difficulty and does not touch the daily claim',
    (tester) async {
      final api = _api(completed: false);
      final directory = Directory.systemTemp.createTempSync(
        'pzd42-practice-budget',
      );
      await _pumpHome(tester, api, directory);

      await tester.tap(find.byKey(const Key('practice')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('practice-easy')), findsOneWidget);
      expect(find.byKey(const Key('practice-medium')), findsOneWidget);
      expect(find.byKey(const Key('practice-hard')), findsOneWidget);

      await tester.tap(find.byKey(const Key('practice-easy')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('5×5 board, 15 moves'), findsOneWidget);

      await tester.tap(find.byKey(const Key('practice-change')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('practice-medium')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('6×6 board, 12 moves'), findsOneWidget);

      await tester.tap(find.byKey(const Key('practice-change')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('practice-hard')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('7×7 board, 10 moves'), findsOneWidget);

      await tester.tap(find.byKey(const Key('nav-back')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('practice-easy')), findsOneWidget);
      await tester.tap(find.byKey(const Key('nav-back')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text("Play today's tournament"), findsOneWidget);
      expect(api.claimPosts, 1);
      expect(api.commandBodies, isEmpty);
    },
  );

  testWidgets(
    'a finished practice puzzle is local, replayable, and absent from the ranked board',
    (tester) async {
      final api = _api(completed: true);
      final directory = Directory.systemTemp.createTempSync(
        'pzd42-practice-play',
      );
      await _pumpHome(tester, api, directory);
      expect(find.byKey(const Key('practice')), findsOneWidget);

      await tester.tap(find.byKey(const Key('practice')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('practice-hard')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final generated = generateChallenge(
        ChallengeGenerationConfig.profile(DifficultyProfile.hard),
        1,
      );
      expect(generated, isA<GeneratedChallenge>());
      var state = (generated as GeneratedChallenge).state;
      var guard = 0;
      while (find
          .byKey(const Key('practice-result-score'))
          .evaluate()
          .isEmpty) {
        guard += 1;
        expect(
          guard,
          lessThan(12),
          reason: 'practice did not finish from the canonical generator',
        );
        final move = _legal(state);
        await tester.tap(find.byKey(ValueKey('offer-slot-${move.offer}')));
        await tester.pump();
        await tester.tap(
          find.byKey(ValueKey('board-ink-${move.tap.row}-${move.tap.column}')),
        );
        await tester.pump();
        await tester.pump();
        state = move.next;
      }

      expect(
        find.text('Saved on this device only. This is not a verified rank.'),
        findsOneWidget,
      );
      expect(find.text('On-Time'), findsNothing);
      await tester.pump();
      final recordFiles = directory
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('practice-records-player_'))
          .toList();
      expect(recordFiles, hasLength(1));
      final records = jsonDecode(recordFiles.single.readAsStringSync()) as List;
      final record = records.single as Map;
      expect(record['verifiedRank'], isFalse);
      expect(record['difficulty'], 'hard');
      expect(record['generatorVersion'], 'gen-001.v1');
      expect(record['rulesVersion'], 'core-001.v2');
      expect(record['seed'], 1);
      expect(record['score'], state.score);

      await tester.tap(find.byKey(const Key('practice-replay')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('7×7 board, 10 moves'), findsOneWidget);
      expect(
        directory
            .listSync()
            .whereType<File>()
            .firstWhere((f) => f.path.contains('practice-seed-player_'))
            .readAsStringSync()
            .trim(),
        '2',
      );

      await tester.tap(find.byKey(const Key('nav-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('practice-new')), findsOneWidget);
      await tester.tap(find.byKey(const Key('practice-new')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('7×7 board, 10 moves'), findsOneWidget);
      expect(
        directory
            .listSync()
            .whereType<File>()
            .firstWhere((f) => f.path.contains('practice-seed-player_'))
            .readAsStringSync()
            .trim(),
        '3',
      );

      await tester.tap(find.byKey(const Key('nav-back')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const Key('nav-back')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byKey(const Key('primary-action'), skipOffstage: false),
        findsOneWidget,
      );

      await tester.scrollUntilVisible(
        find.byKey(const Key('leaderboard')),
        200,
        scrollable: find.byType(Scrollable).hitTestable(),
      );
      await tester.tap(find.byKey(const Key('leaderboard')));
      await tester.pumpAndSettle();
      expect(find.textContaining('no verified rank'), findsOneWidget);
      expect(find.text('Player'), findsNothing);
      expect(api.claimPosts, 1);
      expect(api.commandBodies, isEmpty);
    },
  );

  testWidgets(
    'leaving an unfinished practice asks first and backgrounding keeps the board',
    (tester) async {
      final api = _api(completed: false);
      final directory = Directory.systemTemp.createTempSync(
        'pzd42-practice-leave',
      );
      await _pumpHome(tester, api, directory);
      await tester.tap(find.byKey(const Key('practice')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('practice-easy')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final generated = generateChallenge(
        ChallengeGenerationConfig.profile(DifficultyProfile.easy),
        1,
      );
      final state = (generated as GeneratedChallenge).state;
      final move = _legal(state);
      await tester.tap(find.byKey(ValueKey('offer-slot-${move.offer}')));
      await tester.pump();
      await tester.tap(
        find.byKey(ValueKey('board-ink-${move.tap.row}-${move.tap.column}')),
      );
      await tester.pump();
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.byKey(const Key('practice-budget')), findsOneWidget);

      await tester.tap(find.byKey(const Key('nav-back')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Leave this game?'), findsOneWidget);
      await tester.tap(find.text('Keep playing'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('practice-budget')), findsOneWidget);

      await tester.tap(find.byKey(const Key('nav-back')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Go to Home'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text("Play today's tournament"), findsOneWidget);
      expect(api.claimPosts, 1);
      expect(api.commandBodies, isEmpty);
    },
  );
}

final class _Move {
  const _Move(this.offer, this.tap, this.next);

  final int offer;
  final Coordinate tap;
  final GameState next;
}

_Move _legal(GameState state) {
  for (var offer = 0; offer < state.offers.length; offer++) {
    final piece = state.offers[offer].pieceOrNull;
    if (piece == null) continue;
    for (var row = 0; row < state.boardSize; row++) {
      for (var column = 0; column < state.boardSize; column++) {
        final tap = Coordinate(row: row, column: column);
        if (!canPlaceAt(
          boardSize: state.boardSize,
          cells: state.cells,
          blocked: state.blocked,
          piece: piece,
          tap: tap,
        )) {
          continue;
        }
        final applied = applyMove(state, Move(offerIndex: offer, tap: tap));
        if (applied is MoveApplied)
          return _Move(offer, tap, applied.finalState);
      }
    }
  }
  throw StateError('canonical practice state has no legal move');
}

ScriptedUatApi _api({required bool completed}) {
  return ScriptedUatApi((method, path, body) async {
    if (method == 'POST' && path.endsWith('/session')) {
      return const UatHttpResult(201, {
        'playerId': '66666666-6666-4666-8666-666666666666',
        'sessionSecret': 'secret',
      });
    }
    if (path.endsWith('/claims/daily')) {
      return UatHttpResult(completed ? 200 : 201, {
        'seriesId': '66666666-6666-4666-8666-666666666666',
        'status': completed ? 'COMPLETED' : 'ACTIVE',
        'original': !completed,
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
    if (path.endsWith('/results')) {
      return const UatHttpResult(200, {
        'all': 20,
        'easy': 20,
        'medium': 0,
        'hard': 0,
        'onTimeAwarded': true,
      });
    }
    if (path.endsWith('/weeks')) {
      return const UatHttpResult(200, {
        'weeks': ['2026-11-16', '2026-11-09'],
      });
    }
    if (path.contains('/leaderboards/')) {
      return const UatHttpResult(200, {'state': 'PROVISIONAL', 'rows': []});
    }
    return const UatHttpResult(404, {'error': 'NOT_FOUND'});
  });
}

Future<void> _pumpHome(
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
        playerLabel: 'practice',
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
  if (find.byKey(const Key('practice')).evaluate().isEmpty) {
    final boot = find.byKey(const Key('app-boot'));
    final message = boot.evaluate().isEmpty
        ? tester.allWidgets
              .map((w) => w.runtimeType.toString())
              .take(20)
              .join(',')
        : (boot.evaluate().single.widget as Text).data;
    fail('home did not boot: $message');
  }
  await tester.scrollUntilVisible(find.byKey(const Key('practice')), 200);
}
