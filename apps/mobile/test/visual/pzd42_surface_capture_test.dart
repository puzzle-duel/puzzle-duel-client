import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/presentation/feedback/app_top_banner.dart';
import 'package:puzzle_duel_mobile/theme/app_theme.dart';
import 'package:puzzle_duel_mobile/tournament/practice_flow.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_copy.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_uat_app.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

import '../tournament/tournament_command_test.dart' show ScriptedUatApi;

/// Rendered UAT surfaces. Skipped on CI because Linux pixels differ.
/// Regenerate: `flutter test test/visual/pzd42_surface_capture_test.dart --update-goldens`
bool get _skipOnCi =>
    Platform.environment['CI'] == 'true' || Platform.environment['GITHUB_ACTIONS'] == 'true';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home tournament available', (tester) async {
    await _captureHome(tester, '01-home-ready', turnsUsed: 0, ordinal: 1, completed: false);
  }, skip: _skipOnCi);

  testWidgets('home tournament in progress', (tester) async {
    await _captureHome(tester, '02-home-progress', turnsUsed: 4, ordinal: 2, completed: false);
  }, skip: _skipOnCi);

  testWidgets('home tournament completed', (tester) async {
    await _captureHome(tester, '03-home-complete', turnsUsed: 10, ordinal: 6, completed: true);
  }, skip: _skipOnCi);

  testWidgets('settings', (tester) async {
    await _captureHome(tester, '04-settings', turnsUsed: 0, ordinal: 1, completed: false, openSettings: true);
  }, skip: _skipOnCi);

  testWidgets('leaderboard weekly with one verified player', (tester) async {
    await _captureBoard(tester, '05-leaderboard-one', _onePlayer, daily: false);
  }, skip: _skipOnCi);

  testWidgets('leaderboard weekly with several verified players', (tester) async {
    await _captureBoard(tester, '06-leaderboard-many', _manyPlayers, daily: false);
  }, skip: _skipOnCi);

  testWidgets('leaderboard empty', (tester) async {
    await _captureBoard(tester, '07-leaderboard-empty', const [], daily: false);
  }, skip: _skipOnCi);

  testWidgets('leaderboard daily', (tester) async {
    await _captureBoard(tester, '08-leaderboard-daily', _onePlayer, daily: true);
  }, skip: _skipOnCi);

  testWidgets('practice result', (tester) async {
    final generated = generateChallenge(ChallengeGenerationConfig.profile(DifficultyProfile.hard), 1);
    var state = (generated as GeneratedChallenge).state;
    var guard = 0;
    while (state.status != GameStatus.ended && guard < 12) {
      guard += 1;
      state = _finish(state);
    }
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('visual-root'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: PuzzleDuelTheme.dark(),
          locale: const Locale('en'),
          supportedLocales: const [Locale('en')],
          localizationsDelegates: const [TournamentCopyDelegate()],
          builder: (context, child) => TournamentLocale(locale: const Locale('en'), child: child ?? const SizedBox.shrink()),
          home: PracticeResultView(
            copy: const TournamentCopy(Locale('en')),
            state: state,
            profile: DifficultyProfile.hard,
            onReplay: () {},
            onNew: () {},
            onDifficulty: () {},
            onHome: () {},
            deviceBest: state.score,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _golden(tester, '09-practice-result');
  }, skip: _skipOnCi);

  testWidgets('tournament final result', (tester) async {
    await _captureHome(tester, '10-tournament-results', turnsUsed: 10, ordinal: 6, completed: true, openResults: true);
  }, skip: _skipOnCi);
}

const _onePlayer = [
  {'rank': 1, 'score': 11000, 'self': true, 'onTimeAwarded': true},
];

const _manyPlayers = [
  {'rank': 1, 'score': 11000, 'self': true, 'onTimeAwarded': true},
  {'rank': 2, 'score': 8400, 'self': false, 'onTimeAwarded': false},
  {'rank': 3, 'score': 6200, 'self': false, 'onTimeAwarded': true},
  {'rank': 4, 'score': 4100, 'self': false, 'onTimeAwarded': false},
];

Future<void> _captureHome(
  WidgetTester tester,
  String name, {
  required int turnsUsed,
  required int ordinal,
  required bool completed,
  bool openSettings = false,
  bool openResults = false,
}) async {
  final api = ScriptedUatApi((method, path, body) async {
    if (method == 'POST' && path.endsWith('/session')) {
      return const UatHttpResult(201, {'sessionSecret': 'secret'});
    }
    if (path.endsWith('/claims/daily')) {
      return UatHttpResult(completed ? 200 : 201, {
        'seriesId': '88888888-8888-4888-8888-888888888888',
        'status': completed ? 'COMPLETED' : 'ACTIVE',
        'original': !completed,
      });
    }
    if (path.endsWith('/board')) {
      return UatHttpResult(200, {
        'ordinal': ordinal,
        'ordinalLabel': ['', 'E1', 'E2', 'E3', 'M1', 'M2', 'H1'][ordinal],
        'seriesScore': completed ? 11000 : 900,
        'score': 900,
        'awaitAdvance': false,
        'resultsPublished': completed,
        'state': {'turnsUsed': turnsUsed, 'moveLimit': 15, 'boardSize': 5},
      });
    }
    if (path.endsWith('/results')) {
      return const UatHttpResult(200, {
        'all': 11000,
        'easy': 4200,
        'medium': 3600,
        'hard': 3200,
        'onTimeAwarded': true,
        'games': [
          {'ordinal': 1, 'label': 'E1', 'score': 1400},
          {'ordinal': 2, 'label': 'E2', 'score': 1500},
          {'ordinal': 3, 'label': 'E3', 'score': 1300},
          {'ordinal': 4, 'label': 'M1', 'score': 1800},
          {'ordinal': 5, 'label': 'M2', 'score': 1800},
          {'ordinal': 6, 'label': 'H1', 'score': 3200},
        ],
      });
    }
    return const UatHttpResult(404, {'error': 'NOT_FOUND'});
  });
  await _pump(tester, api);
  final live = tester
      .widget<AppTopBannerHost>(
        find.byKey(const Key('tournament-status-host')),
      )
      .controller;
  // Calendar boot no longer auto-claims; resume selected day for progress/complete.
  if (turnsUsed > 0 || completed || openResults) {
    await live.resume();
    await tester.pumpAndSettle();
  }
  if (openSettings) {
    await tester.tap(find.byKey(const Key('settings')));
    await tester.pumpAndSettle();
  }
  if (openResults) {
    await live.openResults();
    await tester.pumpAndSettle();
  }
  await _golden(tester, name);
}

Future<void> _captureBoard(WidgetTester tester, String name, List<Map<String, Object>> rows, {required bool daily}) async {
  final api = ScriptedUatApi((method, path, body) async {
    if (method == 'POST' && path.endsWith('/session')) {
      return const UatHttpResult(201, {'sessionSecret': 'secret'});
    }
    if (path.endsWith('/claims/daily')) {
      return const UatHttpResult(201, {
        'seriesId': '88888888-8888-4888-8888-888888888888',
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
    if (path.endsWith('/weeks')) {
      return const UatHttpResult(200, {
        'weeks': ['2026-11-16', '2026-11-09'],
      });
    }
    if (path.contains('/leaderboards/')) {
      final self = rows.cast<Map>().where((row) => row['self'] == true).toList();
      return UatHttpResult(200, {
        'state': 'PROVISIONAL',
        'period': path.contains('daily') ? '2026-11-18' : '2026-11-16',
        'rows': rows,
        if (self.isNotEmpty) 'self': {'rank': self.first['rank'], 'score': self.first['score'], 'onTimeAwarded': true},
      });
    }
    return const UatHttpResult(404, {'error': 'NOT_FOUND'});
  });
  await _pump(tester, api);
  // Weekly hub calendar grows the Home card; scroll actions into view.
  await tester.scrollUntilVisible(
    find.byKey(const Key('leaderboard')),
    80,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('leaderboard')));
  await tester.pumpAndSettle();
  if (daily) {
    await tester.tap(find.byKey(const Key('board-daily')));
    await tester.pumpAndSettle();
  }
  await _golden(tester, name);
}

Future<void> _pump(WidgetTester tester, ScriptedUatApi api) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    RepaintBoundary(
      key: const Key('visual-root'),
      child: TournamentUatApp(
        config: const UatConfig(baseUrl: 'http://127.0.0.1', bearer: 'Bearer test', playerLabel: 'visual'),
        api: api,
        stateDirectory: Directory.systemTemp.createTempSync('pzd42-visual'),
        haptics: const SilentTournamentHaptics(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _golden(WidgetTester tester, String name) {
  return expectLater(
    find.byKey(const Key('visual-root')),
    matchesGoldenFile('../../../../docs/tournament/uat-evidence/pzd42-visual/$name.png'),
  );
}

GameState _finish(GameState state) {
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
        if (applied is MoveApplied) return applied.finalState;
      }
    }
  }
  throw StateError('no legal practice move');
}
