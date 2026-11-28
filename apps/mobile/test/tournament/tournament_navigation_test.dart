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
    final now = DateTime.now().toUtc();
    final dayStart = DateTime.utc(now.year, now.month, now.day);
    final monday = dayStart.subtract(Duration(days: (dayStart.weekday + 6) % 7));
    final today = dayStart.toIso8601String().substring(0, 10);
    final api = ScriptedUatApi((method, path, body) async {
      if (method == 'POST' && path.endsWith('/session')) {
        return const UatHttpResult(201, {'sessionSecret': 'secret'});
      }
      if (path.endsWith('/calendar')) {
        return UatHttpResult(200, {
          'weekStartUtc': monday.toIso8601String().substring(0, 10),
          'weekEndUtc': monday
              .add(const Duration(days: 6))
              .toIso8601String()
              .substring(0, 10),
          'serverNowMs': 1,
          'currentTournamentDate': today,
          'completedDayCount': 1,
          'playablePastDayCount': 0,
          'accountScoped': true,
          'days': [
            for (var i = 0; i < 7; i++)
              () {
                final date = monday.add(Duration(days: i));
                final iso = date.toIso8601String().substring(0, 10);
                final isToday = iso == today;
                return {
                  'date': iso,
                  'status': isToday
                      ? 'COMPLETED'
                      : date.isAfter(dayStart)
                      ? 'LOCKED_FUTURE'
                      : 'AVAILABLE_PAST',
                  'isToday': isToday,
                  'canStart': !isToday && !date.isAfter(dayStart),
                  'canResume': false,
                  'canViewResults': isToday,
                  if (isToday)
                    'seriesId': '22222222-2222-4222-8222-222222222222',
                  if (isToday) 'verifiedScore': 900,
                  'completedBoardCount': isToday ? 6 : 0,
                  'totalBoardCount': 6,
                };
              }(),
          ],
        });
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
    await _pumpFrames(tester);

    expect(find.byKey(const Key('home-title')), findsOneWidget);
    expect(find.text('Tournament complete'), findsNothing);
    expect(find.textContaining('900'), findsWidgets);
    expect(api.claimPosts, 0);

    await tester.tap(find.byKey(const Key('primary-action')));
    await _pumpFrames(tester);
    expect(find.byKey(const Key('results-score')), findsOneWidget);
    expect(api.claimPosts, 0);

    await tester.tap(find.byKey(const Key('leaderboard')));
    await _pumpFrames(tester);
    expect(find.byKey(const Key('board-weekly')), findsOneWidget);
    expect(find.text('Provisional'), findsOneWidget);
    final weeklyPeriod = tester.getRect(find.byKey(const Key('period-row')));
    final weeklyRank = tester.getTopLeft(find.byKey(const Key('self-rank')));
    await tester.tap(find.byKey(const Key('board-daily')));
    await _pumpFrames(tester);
    expect(find.text('18 November 2026'), findsOneWidget);
    final dailyPeriod = tester.getRect(find.byKey(const Key('period-row')));
    final dailyRank = tester.getTopLeft(find.byKey(const Key('self-rank')));
    expect(dailyPeriod.height, weeklyPeriod.height);
    expect(dailyPeriod.top, weeklyPeriod.top);
    expect(dailyRank.dy, weeklyRank.dy);

    await tester.tap(find.byKey(const Key('nav-back')));
    await _pumpFrames(tester);
    expect(find.byKey(const Key('results-score')), findsOneWidget);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await _pumpFrames(tester);
    expect(find.byKey(const Key('home-title')), findsOneWidget);
    expect(api.claimPosts, 0);

    await tester.scrollUntilVisible(find.byKey(const Key('leaderboard')), 120);
    await tester.tap(find.byKey(const Key('leaderboard')));
    await _pumpFrames(tester);
    expect(find.text('Provisional'), findsOneWidget);
    await tester.tap(find.byKey(const Key('nav-back')));
    await _pumpFrames(tester);
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
      await _pumpFrames(tester);
      expect(tester.takeException(), isNull);
    }

    await pumpAt(const Size(320, 568), locale: const Locale('en'), scaler: const TextScaler.linear(1.6));
    await tester.scrollUntilVisible(find.byKey(const Key('primary-action')), 80);
    expect(find.text("Start tournament"), findsOneWidget);
    await pumpAt(const Size(390, 844), locale: const Locale('en'));
    await tester.scrollUntilVisible(find.byKey(const Key('primary-action')), 80);
    expect(tester.takeException(), isNull);
    await pumpAt(const Size(430, 932), locale: const Locale('tr'), scaler: const TextScaler.linear(1.3));
    await tester.scrollUntilVisible(find.byKey(const Key('primary-action')), 80);
    expect(find.text('Turnuvaya başla'), findsOneWidget);
  });

  testWidgets('home opens the current weekly board in All', (tester) async {
    final directory = Directory.systemTemp.createTempSync('pzd42-week');
    final paths = <String>[];
    final api = ScriptedUatApi((method, path, body) async {
      paths.add(path);
      if (method == 'POST' && path.endsWith('/session')) {
        return const UatHttpResult(201, {'sessionSecret': 'secret'});
      }
      if (path.endsWith('/claims/daily')) {
        return const UatHttpResult(200, {
          'seriesId': '44444444-4444-4444-8444-444444444444',
          'status': 'COMPLETED',
          'original': false,
        });
      }
      if (path.endsWith('/board')) {
        return const UatHttpResult(200, {
          'ordinal': 6,
          'ordinalLabel': 'H1',
          'seriesScore': 10,
          'awaitAdvance': false,
          'resultsPublished': true,
          'state': {'turnsUsed': 1, 'moveLimit': 1, 'boardSize': 5},
        });
      }
      if (path.endsWith('/results')) {
        return const UatHttpResult(200, {'all': 10, 'easy': 10, 'medium': 0, 'hard': 0});
      }
      if (path.endsWith('/weeks')) {
        return const UatHttpResult(200, {
          'weeks': ['2026-11-16', '2026-11-09'],
        });
      }
      if (path.contains('/leaderboards/')) {
        return const UatHttpResult(200, {
          'state': 'PROVISIONAL',
          'period': '2026-11-18',
          'rows': [],
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
          playerLabel: 'week',
        ),
        api: api,
        stateDirectory: directory,
        haptics: const SilentTournamentHaptics(),
      ),
    );
    await _pumpFrames(tester);

    await tester.scrollUntilVisible(find.byKey(const Key('leaderboard')), 120);
    await tester.tap(find.byKey(const Key('leaderboard')));
    await _pumpFrames(tester);
    expect(paths.last, contains('weekStart=2026-11-16'));
    expect(paths.last, contains('category=ALL'));
    expect(find.textContaining('no verified rank'), findsOneWidget);
    expect(find.text('Player'), findsNothing);
    expect(find.textContaining('No verified scores'), findsOneWidget);

    await tester.tap(find.text('Hard'));
    await _pumpFrames(tester);
    expect(paths.last, contains('category=HARD'));
    await tester.tap(find.byKey(const Key('week-older')));
    await _pumpFrames(tester);
    expect(paths.last, contains('weekStart=2026-11-09'));
    expect(paths.last, contains('category=HARD'));

    await tester.tap(find.byKey(const Key('nav-back')));
    await _pumpFrames(tester);
    await tester.scrollUntilVisible(find.byKey(const Key('leaderboard')), 120);
    await tester.tap(find.byKey(const Key('leaderboard')));
    await _pumpFrames(tester);
    expect(paths.last, contains('weekStart=2026-11-16'));
    expect(paths.last, contains('category=ALL'));
    expect(find.text('16–22 November 2026'), findsOneWidget);
  });
}

Future<void> _pumpFrames(WidgetTester tester, [int frames = 20]) async {
  await tester.pump();
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

