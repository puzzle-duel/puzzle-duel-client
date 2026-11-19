import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/application/game_session.dart';
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

  testWidgets('Home cards stay put when status banner appears and clears', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-ux05-shift');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    var online = false;
    final api = ScriptedUatApi((method, path, body) async {
      if (!online) {
        return const UatHttpResult(
          0,
          {'error': 'TIMEOUT'},
          category: UatFailureCategory.connectTimeout,
        );
      }
      if (path.endsWith('/session') && method == 'POST') {
        return const UatHttpResult(201, {
          'playerId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
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
          'awaitAdvance': false,
          'resultsPublished': false,
          'state': {'turnsUsed': 0, 'moveLimit': 15, 'boardSize': 5},
        });
      }
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });
    await _pumpHome(tester, api, directory);
    final titleBefore = tester.getTopLeft(find.byKey(const Key('home-title')));
    final dailyBefore = tester.getTopLeft(
      find.byKey(const Key('home-daily-card')),
    );
    expect(find.byKey(const Key('tournament-status')), findsOneWidget);

    online = true;
    final refresh = tester.widget<RefreshIndicator>(
      find.byKey(const Key('home-refresh')),
    );
    await refresh.onRefresh();
    await tester.pump();
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('Tournament info updated.').evaluate().isNotEmpty) break;
    }
    expect(tester.getTopLeft(find.byKey(const Key('home-title'))), titleBefore);
    expect(
      tester.getTopLeft(find.byKey(const Key('home-daily-card'))),
      dailyBefore,
    );

    await tester.pump(const Duration(milliseconds: 2800));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getTopLeft(find.byKey(const Key('home-title'))), titleBefore);
    expect(
      tester.getTopLeft(find.byKey(const Key('home-daily-card'))),
      dailyBefore,
    );
  });

  testWidgets('terminal Practice move stays on board until phase ended', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-ux06-resolve');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final api = _onlineApi();
    await _pumpHome(tester, api, directory);
    await tester.scrollUntilVisible(find.byKey(const Key('practice')), 200);
    await tester.tap(find.byKey(const Key('practice')));
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const Key('practice-easy')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final generated = generateChallenge(
      ChallengeGenerationConfig.profile(DifficultyProfile.easy),
      1,
    );
    var state = (generated as GeneratedChallenge).state;
    var guard = 0;
    while (find.byKey(const Key('practice-result-score')).evaluate().isEmpty) {
      guard += 1;
      expect(guard, lessThan(16));
      final move = _legal(state);
      await tester.tap(find.byKey(ValueKey('offer-slot-${move.offer}')));
      await tester.pump();
      await tester.tap(
        find.byKey(ValueKey('board-ink-${move.tap.row}-${move.tap.column}')),
      );
      await tester.pump();
      // While resolving/settling, results must not replace the board yet.
      if (find.byKey(const Key('practice-result-score')).evaluate().isEmpty) {
        expect(find.byKey(const Key('play-board')), findsOneWidget);
      }
      await tester.pump(const Duration(milliseconds: 50));
      state = move.next;
    }
    expect(find.byKey(const Key('practice-result-score')), findsOneWidget);
  });

  testWidgets('Change Difficulty from results opens picker', (tester) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-ux07-diff');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final api = _onlineApi();
    await _pumpHome(tester, api, directory);
    await tester.scrollUntilVisible(find.byKey(const Key('practice')), 200);
    await tester.tap(find.byKey(const Key('practice')));
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const Key('practice-easy')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final generated = generateChallenge(
      ChallengeGenerationConfig.profile(DifficultyProfile.easy),
      1,
    );
    var state = (generated as GeneratedChallenge).state;
    var guard = 0;
    while (find.byKey(const Key('practice-result-score')).evaluate().isEmpty) {
      guard += 1;
      expect(guard, lessThan(16));
      final move = _legal(state);
      await tester.tap(find.byKey(ValueKey('offer-slot-${move.offer}')));
      await tester.pump();
      await tester.tap(
        find.byKey(ValueKey('board-ink-${move.tap.row}-${move.tap.column}')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      state = move.next;
    }

    await tester.tap(find.byKey(const Key('practice-change-difficulty')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('practice-easy')), findsOneWidget);
    expect(find.byKey(const Key('practice-medium')), findsOneWidget);
    expect(find.byKey(const Key('practice-hard')), findsOneWidget);
    expect(find.byKey(const Key('practice-title')), findsOneWidget);
    expect(find.byKey(const Key('practice-result-score')), findsNothing);

    await tester.tap(find.byKey(const Key('practice-medium')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('6×6 board, 12 moves'), findsOneWidget);
  });

  test('GameSession completeResolution gates ended phase', () {
    final session = GameSession();
    expect(session.startRound(profile: DifficultyProfile.easy, seed: 1), isTrue);
    var state = session.view.canonicalState!;
    var safety = 0;
    while (state.status != GameStatus.ended && safety < 30) {
      safety += 1;
      final move = _legal(state);
      session.selectOffer(move.offer);
      expect(session.submitTap(move.tap), isTrue);
      expect(session.view.phase, GameScreenPhase.resolving);
      final script = session.view.activeScript!;
      if (move.next.status == GameStatus.ended) {
        expect(session.view.canonicalState!.status, GameStatus.ended);
        expect(session.view.phase, isNot(GameScreenPhase.ended));
      }
      session.completeResolution(
        generation: script.generation,
        resolutionId: script.resolutionId,
      );
      state = move.next;
    }
    expect(session.view.phase, GameScreenPhase.ended);
  });
}

ScriptedUatApi _onlineApi() {
  return ScriptedUatApi((method, path, body) async {
    if (path.endsWith('/session') && method == 'POST') {
      return const UatHttpResult(201, {
        'playerId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
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
        'awaitAdvance': false,
        'resultsPublished': false,
        'state': {'turnsUsed': 0, 'moveLimit': 15, 'boardSize': 5},
      });
    }
    return const UatHttpResult(404, {'error': 'NOT_FOUND'});
  });
}

Future<void> _pumpFrames(WidgetTester tester, [int frames = 20]) async {
  await tester.pump();
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
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
        playerLabel: 'ux',
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
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
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
        if (applied is MoveApplied) {
          return _Move(offer, tap, applied.finalState);
        }
      }
    }
  }
  throw StateError('no legal practice move');
}
