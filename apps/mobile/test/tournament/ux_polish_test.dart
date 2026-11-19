import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/arcade_backdrop.dart';
import 'package:puzzle_duel_mobile/theme/game_tokens.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_copy.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_page_route.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_uat_app.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

import 'tournament_command_test.dart' show ScriptedUatApi;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('offline status uses friendly copy then auto-dismisses', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-ux-offline');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final api = ScriptedUatApi(
      (_, _, _) async => const UatHttpResult(0, {'error': 'OFFLINE'}),
    );
    await _pumpHome(tester, api, directory);
    await _waitFor(tester, find.byKey(const Key('tournament-status')));
    expect(find.text('No internet connection.'), findsOneWidget);
    expect(find.byKey(const Key('tournament-retry')), findsNothing);
    expect(find.byKey(const Key('daily-offline-icon')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 4500));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('No internet connection.'), findsNothing);
    expect(find.byKey(const Key('daily-offline-icon')), findsOneWidget);
  });

  testWidgets('success status fades away under normal motion', (tester) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-ux-success');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    var online = false;
    final api = ScriptedUatApi((method, path, body) async {
      if (!online) return const UatHttpResult(0, {'error': 'OFFLINE'});
      if (path.endsWith('/session') && method == 'POST') {
        return const UatHttpResult(201, {
          'playerId': '33333333-3333-4333-8333-333333333333',
          'sessionSecret': 'secret',
        });
      }
      if (path.endsWith('/claims/daily')) {
        return const UatHttpResult(201, {
          'seriesId': 'series-ux',
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
    await _waitFor(tester, find.byKey(const Key('daily-offline-icon')));
    online = true;
    final refresh = tester.widget<RefreshIndicator>(
      find.byKey(const Key('home-refresh')),
    );
    await refresh.onRefresh();
    await tester.pump();
    await _waitFor(tester, find.text('Tournament info updated.'));
    expect(find.text('Tournament info updated.'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2800));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Tournament info updated.'), findsNothing);
  });

  testWidgets('reduced motion auto-dismisses offline banner after hold', (
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
    final directory = Directory.systemTemp.createTempSync('pzd43-ux-motion');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final api = ScriptedUatApi(
      (_, _, _) async => const UatHttpResult(0, {'error': 'OFFLINE'}),
    );
    await _pumpHome(tester, api, directory);
    await _waitFor(tester, find.byKey(const Key('tournament-status')));
    await tester.pump(const Duration(milliseconds: 4500));
    await tester.pump();
    expect(find.byKey(const Key('tournament-status')), findsNothing);
    expect(find.byKey(const Key('daily-offline-icon')), findsOneWidget);
  });

  testWidgets('home leaderboard uses pushed route and pops to home', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-ux-lb');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final api = _onlineApi();
    await _pumpHome(tester, api, directory);
    await tester.scrollUntilVisible(find.byKey(const Key('leaderboard')), 200);
    await tester.tap(find.byKey(const Key('leaderboard')));
    await _pumpFrames(tester);
    expect(find.text('Provisional'), findsOneWidget);
    expect(find.byKey(const Key('home-title')), findsNothing);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    expect(navigator.canPop(), isTrue);
    await tester.tap(find.byKey(const Key('nav-back')));
    await _pumpFrames(tester);
    expect(find.byKey(const Key('home-title')), findsOneWidget);
    expect(find.text('Provisional'), findsNothing);
  });

  testWidgets('system back pops pushed leaderboard to home', (tester) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-ux-sysback');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final api = _onlineApi();
    await _pumpHome(tester, api, directory);
    await tester.scrollUntilVisible(find.byKey(const Key('leaderboard')), 200);
    await tester.tap(find.byKey(const Key('leaderboard')));
    await _pumpFrames(tester);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    expect(await navigator.maybePop(), isTrue);
    await _pumpFrames(tester);
    expect(find.byKey(const Key('home-title')), findsOneWidget);
  });

  testWidgets('practice picker shows title beside back arrow', (tester) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-ux-practice');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final api = _onlineApi();
    await _pumpHome(tester, api, directory);
    await tester.scrollUntilVisible(find.byKey(const Key('practice')), 200);
    await tester.tap(find.byKey(const Key('practice')));
    await _pumpFrames(tester);
    expect(find.byKey(const Key('practice-title')), findsOneWidget);
    expect(find.text('Practice'), findsOneWidget);
    final back = tester.getCenter(find.byKey(const Key('nav-back')));
    final title = tester.getCenter(find.byKey(const Key('practice-title')));
    expect((back.dy - title.dy).abs(), lessThan(8));
    expect(title.dx, greaterThan(back.dx));
  });

  testWidgets('active practice leave still asks before popping', (tester) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-ux-leave');
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
    final state = (generated as GeneratedChallenge).state;
    final move = _legal(state);
    await tester.tap(find.byKey(ValueKey('offer-slot-${move.offer}')));
    await tester.pump();
    await tester.tap(
      find.byKey(ValueKey('board-ink-${move.tap.row}-${move.tap.column}')),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('nav-back')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Leave this game?'), findsOneWidget);
    await tester.tap(find.text('Keep playing'));
    await tester.pump();
    expect(find.byKey(const Key('practice-title')), findsOneWidget);
  });

  testWidgets('TR locale and large text scale keep practice header row', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-ux-locale');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final api = _onlineApi();
    await _pumpHome(
      tester,
      api,
      directory,
      locale: const Locale('tr'),
      textScaler: const TextScaler.linear(1.3),
    );
    await tester.scrollUntilVisible(find.byKey(const Key('practice')), 200);
    await tester.tap(find.byKey(const Key('practice')));
    await _pumpFrames(tester);
    expect(find.text('Pratik Yap'), findsOneWidget);
    final back = tester.getCenter(find.byKey(const Key('nav-back')));
    final title = tester.getCenter(find.byKey(const Key('practice-title')));
    expect((back.dy - title.dy).abs(), lessThan(16));
  });

  testWidgets('friendly status copy has no technical jargon', (tester) async {
    const en = TournamentCopy(Locale('en'));
    const tr = TournamentCopy(Locale('tr'));
    for (final copy in [en, tr]) {
      final blobs = [
        copy.tournamentSyncing,
        copy.tournamentRefreshSuccess,
        copy.cachedTournamentBody,
        copy.connectionUnavailable,
        copy.offline,
        copy.timedOut,
        copy.unauthorized,
      ].join(' ').toLowerCase();
      expect(blobs.contains('sunucu'), isFalse);
      expect(blobs.contains('snapshot'), isFalse);
      expect(blobs.contains('cache'), isFalse);
      expect(blobs.contains('backend'), isFalse);
      expect(blobs.contains('önbellek'), isFalse);
    }
    expect(tr.tournamentSyncing, 'Turnuva bilgileri güncelleniyor…');
    expect(tr.tournamentRefreshSuccess, 'Turnuva bilgileri güncellendi.');
    expect(tr.cachedTournamentBody, 'Son turnuva bilgilerin gösteriliyor.');
    expect(tr.connectionUnavailable, 'İnternet bağlantısı yok.');
    expect(tr.timedOut, 'Bağlantı zaman aşımına uğradı.');
    expect(tr.noConnection, 'Bağlantı yok');
  });

  testWidgets('opaque backdrop + page route composition (UX-03)', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          backgroundColor: GameTokens.bgDeep,
          body: ArcadeBackdrop(child: Text('home-surface')),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('home-surface'), findsOneWidget);
    expect(find.byType(ArcadeBackdrop), findsOneWidget);
    expect(_opaqueDeepBoxes(tester), greaterThanOrEqualTo(1));

    late final BuildContext navContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          scaffoldBackgroundColor: GameTokens.bgDeep,
          useMaterial3: true,
        ),
        home: Scaffold(
          backgroundColor: GameTokens.bgDeep,
          body: Builder(
            builder: (context) {
              navContext = context;
              return const ArcadeBackdrop(child: Text('home-surface'));
            },
          ),
        ),
      ),
    );
    await tester.pump();
    final route = tournamentPageRoute<void>(
      builder: (_) => const Scaffold(
        backgroundColor: GameTokens.bgDeep,
        body: ArcadeBackdrop(child: Text('leaf-surface')),
      ),
    );
    expect(route.opaque, isTrue);
    expect(route.barrierColor, isNull);
    unawaited(Navigator.of(navContext).push(route));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('leaf-surface'), findsOneWidget);
    expect(_opaqueDeepBoxes(tester), greaterThanOrEqualTo(2));
    for (final scaffold in tester.widgetList<Scaffold>(
      find.byType(Scaffold, skipOffstage: false),
    )) {
      expect(scaffold.backgroundColor, GameTokens.bgDeep);
    }
  });

  testWidgets('home stays stable after repeated push/pop navigation', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-ux-navstab');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final api = _onlineApi();
    await _pumpHome(tester, api, directory);
    for (var i = 0; i < 3; i++) {
      await tester.scrollUntilVisible(find.byKey(const Key('leaderboard')), 200);
      await tester.tap(find.byKey(const Key('leaderboard')));
      await _pumpFrames(tester);
      await tester.tap(find.byKey(const Key('nav-back')));
      await _pumpFrames(tester);
      expect(find.byKey(const Key('home-title')), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const Key('practice')), 200);
      await tester.tap(find.byKey(const Key('practice')));
      await _pumpFrames(tester);
      await tester.tap(find.byKey(const Key('nav-back')));
      await _pumpFrames(tester);
      expect(find.byKey(const Key('home-title')), findsOneWidget);
    }
  });
}

int _opaqueDeepBoxes(WidgetTester tester) {
  return tester
      .widgetList<ColoredBox>(find.byType(ColoredBox, skipOffstage: false))
      .where((box) => box.color == GameTokens.bgDeep)
      .length;
}

ScriptedUatApi _onlineApi() {
  return ScriptedUatApi((method, path, body) async {
    if (path.endsWith('/session') && method == 'POST') {
      return const UatHttpResult(201, {
        'playerId': '44444444-4444-4444-8444-444444444444',
        'sessionSecret': 'secret',
      });
    }
    if (path.endsWith('/claims/daily')) {
      return const UatHttpResult(201, {
        'seriesId': 'series-online',
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
        'weeks': ['2026-11-17'],
      });
    }
    if (path.contains('/leaderboards/')) {
      return const UatHttpResult(200, {
        'state': 'PROVISIONAL',
        'rows': [
          {'rank': 1, 'score': 10, 'displayName': 'A'},
        ],
        'self': {'rank': 2, 'score': 5},
        'period': '2026-11-19',
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

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 80; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsOneWidget);
}

Future<void> _pumpHome(
  WidgetTester tester,
  ScriptedUatApi api,
  Directory directory, {
  Locale? locale,
  TextScaler? textScaler,
}) async {
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
      locale: locale,
      textScaler: textScaler,
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
  const _Move(this.offer, this.tap);
  final int offer;
  final Coordinate tap;
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
          return _Move(offer, tap);
        }
      }
    }
  }
  throw StateError('no legal practice move');
}
