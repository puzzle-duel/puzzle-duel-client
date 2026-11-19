import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/theme/game_tokens.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_uat_app.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';

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

  testWidgets('blue info banner is near-opaque over Home content', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-ux08-blue');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final gate = Completer<void>();
    var allowRefresh = false;
    final api = ScriptedUatApi((method, path, body) async {
      if (!allowRefresh) return const UatHttpResult(0, {'error': 'OFFLINE'});
      if (path.endsWith('/session') && method == 'POST') {
        await gate.future;
      }
      return _ok(method, path);
    });
    await _pumpHome(tester, api, directory);
    await tester.pump(const Duration(milliseconds: 4500));
    await tester.pump();
    allowRefresh = true;
    final refresh = tester.widget<RefreshIndicator>(
      find.byKey(const Key('home-refresh')),
    );
    final pending = refresh.onRefresh();
    await tester.pump();
    // UX-11: no blue loading toast during pull.
    expect(find.byKey(const Key('tournament-status-info')), findsNothing);
    final titleBefore = tester.getTopLeft(find.byKey(const Key('home-title')));
    gate.complete();
    await pending;
    await tester.pump();
    expect(find.text('Tournament info updated.'), findsOneWidget);
    expect(find.byKey(const Key('tournament-status-info')), findsOneWidget);
    final fill = _bannerFill(tester);
    expect(fill.a, greaterThanOrEqualTo(0.90));
    expect(fill.a, lessThanOrEqualTo(0.94));
    expect(_bannerAccent(tester), GameTokens.notifyInfo);
    expect(tester.getTopLeft(find.byKey(const Key('home-title'))), titleBefore);
  });

  testWidgets('red error banner is near-opaque and auto-dismisses', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-ux08-red');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final api = ScriptedUatApi(
      (_, _, _) async => const UatHttpResult(0, {'error': 'OFFLINE'}),
    );
    await _pumpHome(tester, api, directory);
    await _waitFor(tester, find.text('No internet connection.'));
    expect(find.byKey(const Key('tournament-status-error')), findsOneWidget);
    final fill = _bannerFill(tester);
    expect(fill.a, greaterThanOrEqualTo(0.90));
    expect(_bannerAccent(tester), GameTokens.notifyError);
    expect(find.byKey(const Key('daily-offline-icon')), findsOneWidget);
    expect(find.byKey(const Key('tournament-retry')), findsNothing);

    final daily = tester.getTopLeft(find.byKey(const Key('home-daily-card')));
    await tester.pump(const Duration(milliseconds: 4500));
    await tester.pump();
    expect(find.byKey(const Key('tournament-status')), findsNothing);
    expect(find.byKey(const Key('daily-offline-icon')), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const Key('home-daily-card'))), daily);

    final refresh = tester.widget<RefreshIndicator>(
      find.byKey(const Key('home-refresh')),
    );
    await refresh.onRefresh();
    await tester.pump();
    expect(find.byKey(const Key('practice')), findsOneWidget);
  });

  testWidgets('Home→Leaderboard first frame selects Weekly only', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-ux09-first');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    var dailyGets = 0;
    var weeklyGets = 0;
    var weeksGets = 0;
    final gate = Completer<void>();
    final api = ScriptedUatApi((method, path, body) async {
      if (path.contains('/leaderboards/daily')) {
        dailyGets += 1;
        return _dailyBoard();
      }
      if (path.endsWith('/weeks')) {
        weeksGets += 1;
        await gate.future;
        return const UatHttpResult(200, {
          'weeks': ['2026-11-17'],
        });
      }
      if (path.contains('/leaderboards/weekly')) {
        weeklyGets += 1;
        await gate.future;
        return _weeklyBoard();
      }
      return _ok(method, path);
    });
    await _pumpHome(tester, api, directory);
    await tester.scrollUntilVisible(find.byKey(const Key('leaderboard')), 200);
    await tester.tap(find.byKey(const Key('leaderboard')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(const Key('board-weekly')), findsOneWidget);
    expect(_segmentSelected(tester, 'board-weekly'), isTrue);
    expect(_segmentSelected(tester, 'board-daily'), isFalse);
    expect(dailyGets, 0);

    expect(weeksGets, 1);
    expect(weeklyGets, 0);
    gate.complete();
    for (var i = 0; i < 80; i++) {
      if (weeklyGets >= 1) break;
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(weeklyGets, 1);
    expect(dailyGets, 0);
    expect(weeksGets, 1);
    expect(_segmentSelected(tester, 'board-weekly'), isTrue);
  });

  testWidgets('manual Weekly↔Daily switch and Home cycles stay stable', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-ux09-cycle');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    var dailyGets = 0;
    final api = ScriptedUatApi((method, path, body) async {
      if (path.contains('/leaderboards/daily')) {
        dailyGets += 1;
        return _dailyBoard();
      }
      if (path.endsWith('/weeks')) {
        return const UatHttpResult(200, {
          'weeks': ['2026-11-17', '2026-11-10'],
        });
      }
      if (path.contains('/leaderboards/weekly')) {
        return _weeklyBoard();
      }
      return _ok(method, path);
    });
    await _pumpHome(tester, api, directory);

    for (var cycle = 0; cycle < 2; cycle++) {
      await tester.scrollUntilVisible(find.byKey(const Key('leaderboard')), 200);
      await tester.tap(find.byKey(const Key('leaderboard')));
      await _pumpFrames(tester);
      expect(_segmentSelected(tester, 'board-weekly'), isTrue);

      await tester.tap(find.byKey(const Key('board-daily')));
      await _pumpFrames(tester);
      expect(_segmentSelected(tester, 'board-daily'), isTrue);
      expect(dailyGets, greaterThan(0));

      await tester.tap(find.byKey(const Key('board-weekly')));
      await _pumpFrames(tester);
      expect(_segmentSelected(tester, 'board-weekly'), isTrue);

      await tester.tap(find.byKey(const Key('nav-back')));
      await _pumpFrames(tester);
      expect(find.byKey(const Key('home-title')), findsOneWidget);
    }
  });

  testWidgets('Results→Leaderboard still opens Weekly and returns to Results', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-ux09-results');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final api = ScriptedUatApi((method, path, body) async {
      if (path.endsWith('/claims/daily')) {
        return const UatHttpResult(200, {
          'seriesId': '22222222-2222-4222-8222-222222222222',
          'status': 'COMPLETED',
          'original': false,
        });
      }
      if (path.endsWith('/board')) {
        return const UatHttpResult(200, {
          'ordinal': 6,
          'ordinalLabel': 'H1',
          'seriesScore': 900,
          'score': 400,
          'awaitAdvance': false,
          'resultsPublished': true,
          'state': {'turnsUsed': 1, 'moveLimit': 1, 'boardSize': 3},
        });
      }
      if (path.endsWith('/results')) {
        return const UatHttpResult(200, {
          'easy': 300,
          'medium': 200,
          'hard': 400,
          'all': 900,
          'onTimeAwarded': true,
          'games': [
            {'ordinal': 1, 'label': 'E1', 'score': 100},
            {'ordinal': 6, 'label': 'H1', 'score': 400},
          ],
        });
      }
      if (path.endsWith('/weeks')) {
        return const UatHttpResult(200, {
          'weeks': ['2026-11-17'],
        });
      }
      if (path.contains('/leaderboards/weekly')) {
        return _weeklyBoard();
      }
      if (path.contains('/leaderboards/daily')) {
        return _dailyBoard();
      }
      return _ok(method, path);
    });
    await _pumpHome(tester, api, directory);
    await tester.tap(find.byKey(const Key('primary-action')));
    await _pumpFrames(tester);
    expect(find.byKey(const Key('results-score')), findsOneWidget);

    await tester.tap(find.byKey(const Key('leaderboard')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(_segmentSelected(tester, 'board-weekly'), isTrue);
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const Key('nav-back')));
    await _pumpFrames(tester);
    expect(find.byKey(const Key('results-score')), findsOneWidget);
  });
}

bool _segmentSelected(WidgetTester tester, String key) {
  final material = tester.widget<Material>(
    find.descendant(
      of: find.byKey(Key(key)),
      matching: find.byType(Material),
    ).first,
  );
  return material.color == GameTokens.accent;
}

Color _bannerFill(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find.byKey(const Key('tournament-status')),
  );
  final decoration = box.decoration as BoxDecoration;
  return decoration.color!;
}

Color _bannerAccent(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find.byKey(const Key('tournament-status')),
  );
  final decoration = box.decoration as BoxDecoration;
  return decoration.border!.top.color.withValues(alpha: 1);
}

UatHttpResult _ok(String method, String path) {
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
}

UatHttpResult _weeklyBoard() {
  return const UatHttpResult(200, {
    'state': 'PROVISIONAL',
    'rows': [
      {'rank': 1, 'score': 10, 'displayName': 'A', 'self': true},
    ],
    'self': {'rank': 1, 'score': 10},
    'period': '2026-11-17',
  });
}

UatHttpResult _dailyBoard() {
  return const UatHttpResult(200, {
    'period': '2026-11-19',
    'rows': [
      {'rank': 1, 'score': 5, 'displayName': 'A', 'self': true},
    ],
    'self': {'rank': 1, 'score': 5},
  });
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 80; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsOneWidget);
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
        playerLabel: 'ux0809',
      ),
      api: api,
      stateDirectory: directory,
      haptics: const SilentTournamentHaptics(),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 60; i++) {
    if (find.byKey(const Key('practice')).evaluate().isNotEmpty) break;
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(find.byKey(const Key('practice')), findsOneWidget);
}
