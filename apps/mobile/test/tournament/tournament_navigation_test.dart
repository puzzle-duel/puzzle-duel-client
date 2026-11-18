import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_uat_app.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';

import 'tournament_command_test.dart' show ScriptedUatApi;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('completed day stays on home and leaderboard back returns to results', (tester) async {
    final directory = Directory.systemTemp.createTempSync('pzd42-nav');
    final api = ScriptedUatApi((method, path, body) async {
      if (method == 'POST' && path.endsWith('/session')) {
        return const UatHttpResult(201, {'sessionSecret': 'secret'});
      }
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
      if (path.contains('/leaderboards/daily')) {
        return const UatHttpResult(200, {
          'period': '2026-11-18',
          'rows': [
            {'rank': 1, 'score': 900, 'displayPosition': 1, 'self': true, 'onTimeAwarded': true},
          ],
          'self': {'rank': 1, 'score': 900, 'onTimeAwarded': true},
        });
      }
      if (path.endsWith('/weeks')) {
        return const UatHttpResult(200, {
          'weeks': ['2026-11-17', '2026-11-10'],
        });
      }
      if (path.contains('/leaderboards/weekly')) {
        return const UatHttpResult(200, {
          'state': 'PROVISIONAL',
          'rows': [
            {'rank': 1, 'score': 900, 'self': true, 'onTimeAwarded': true},
          ],
          'self': {'rank': 1, 'score': 900, 'onTimeAwarded': true},
        });
      }
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });

    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      TournamentUatApp(
        config: const UatConfig(
          baseUrl: 'http://127.0.0.1',
          bearer: 'Bearer test',
          playerLabel: 'nav',
        ),
        api: api,
        stateDirectory: directory,
        haptics: const SilentTournamentHaptics(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home-title')), findsOneWidget);
    expect(find.text('Tournament complete'), findsNothing);
    expect(find.text('900'), findsWidgets);
    expect(api.claimPosts, 1);

    await tester.tap(find.byKey(const Key('primary-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('results-score')), findsOneWidget);
    expect(api.claimPosts, 1);

    await tester.tap(find.byKey(const Key('daily-leaderboard')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Daily leaderboard'), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('results-score')), findsOneWidget);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-title')), findsOneWidget);
    expect(api.claimPosts, 1);

    await tester.scrollUntilVisible(find.byKey(const Key('weekly-leaderboard')), 120);
    await tester.tap(find.byKey(const Key('weekly-leaderboard')));
    await tester.pumpAndSettle();
    expect(find.text('Provisional'), findsOneWidget);
    await tester.tap(find.byKey(const Key('nav-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-title')), findsOneWidget);
    expect(find.text('Tournament complete'), findsNothing);
  });

  testWidgets('home layout holds on a narrow phone and in Turkish', (tester) async {
    final directory = Directory.systemTemp.createTempSync('pzd42-layout');
    final api = ScriptedUatApi((method, path, body) async {
      if (method == 'POST' && path.endsWith('/session')) {
        return const UatHttpResult(201, {'sessionSecret': 'secret'});
      }
      if (path.endsWith('/claims/daily')) {
        return const UatHttpResult(201, {
          'seriesId': '33333333-3333-4333-8333-333333333333',
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
          'state': {'turnsUsed': 0, 'moveLimit': 5, 'boardSize': 3},
        });
      }
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> pumpAt(Size size, {Locale? locale, TextScaler? scaler}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        TournamentUatApp(
          config: const UatConfig(
            baseUrl: 'http://127.0.0.1',
            bearer: 'Bearer test',
            playerLabel: 'layout',
          ),
          api: api,
          stateDirectory: directory,
          haptics: const SilentTournamentHaptics(),
          locale: locale,
          textScaler: scaler,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    await pumpAt(const Size(320, 568), locale: const Locale('en'), scaler: const TextScaler.linear(1.6));
    await tester.scrollUntilVisible(find.byKey(const Key('primary-action')), 80);
    expect(find.text("Play today's challenge"), findsOneWidget);
    await pumpAt(const Size(390, 844), locale: const Locale('en'));
    await tester.scrollUntilVisible(find.byKey(const Key('primary-action')), 80);
    expect(tester.takeException(), isNull);
    await pumpAt(const Size(430, 932), locale: const Locale('tr'), scaler: const TextScaler.linear(1.3));
    await tester.scrollUntilVisible(find.byKey(const Key('primary-action')), 80);
    expect(find.text('Bugünün mücadelesini oyna'), findsOneWidget);
  });
}
