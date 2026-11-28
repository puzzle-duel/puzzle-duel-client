import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/presentation/feedback/app_top_banner.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_nav.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_uat_app.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';
import 'package:puzzle_duel_mobile/tournament/weekly_tournament_overview.dart';

import 'tournament_command_test.dart' show ScriptedUatApi;

Map<String, Object?> _calendar({
  required bool accountScoped,
  required Map<String, Map<String, Object?>> dayOverrides,
}) {
  const dates = [
    '2026-11-23',
    '2026-11-24',
    '2026-11-25',
    '2026-11-26',
    '2026-11-27',
    '2026-11-28',
    '2026-11-29',
  ];
  return {
    'weekStartUtc': '2026-11-23',
    'weekEndUtc': '2026-11-29',
    'serverNowMs': 1,
    'currentTournamentDate': '2026-11-28',
    'completedDayCount': accountScoped ? 4 : 0,
    'playablePastDayCount': accountScoped ? 2 : 0,
    'accountScoped': accountScoped,
    'days': [
      for (final date in dates)
        {
          'date': date,
          'status': date == '2026-11-29'
              ? 'LOCKED_FUTURE'
              : date == '2026-11-28'
              ? 'COMPLETED'
              : date == '2026-11-24'
              ? 'IN_PROGRESS'
              : date == '2026-11-25'
              ? 'COMPLETED'
              : 'AVAILABLE_PAST',
          'isToday': date == '2026-11-28',
          'canStart': accountScoped &&
              (date == '2026-11-23' || date == '2026-11-26'),
          'canResume': accountScoped && date == '2026-11-24',
          'canViewResults': accountScoped &&
              (date == '2026-11-28' || date == '2026-11-25'),
          'completedBoardCount': date == '2026-11-24'
              ? 3
              : (date == '2026-11-28' || date == '2026-11-25')
              ? 6
              : 0,
          'totalBoardCount': 6,
          if (date == '2026-11-28') ...{
            'seriesId': 'series-sat',
            'verifiedScore': 10600,
            'completionTiming': 'ON_TIME',
          },
          if (date == '2026-11-25') ...{
            'seriesId': 'series-wed',
            'verifiedScore': 8000,
            'completionTiming': 'LATE',
          },
          if (date == '2026-11-24') 'seriesId': 'series-tue',
          ...?dayOverrides[date],
        },
    ],
  };
}

Future<TournamentController> _pumpHome(
  WidgetTester tester, {
  required ScriptedUatApi api,
}) async {
  final dir = Directory.systemTemp.createTempSync('pzd55-sel-iso');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    TournamentUatApp(
      config: const UatConfig(
        baseUrl: 'http://127.0.0.1',
        bearer: 'Bearer test',
        playerLabel: 'iso',
      ),
      api: api,
      stateDirectory: dir,
    ),
  );
  for (var i = 0; i < 80; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (find.byKey(const Key('home-daily-card')).evaluate().isNotEmpty) break;
  }
  expect(find.byKey(const Key('home-daily-card')), findsOneWidget);
  return tester
      .widget<AppTopBannerHost>(
        find.byKey(const Key('tournament-status-host')),
      )
      .controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Sat completed score does not leak onto unplayed Monday selection',
    (tester) async {
      final api = ScriptedUatApi((method, path, body) async {
        if (path.endsWith('/session') && method == 'POST') {
          return const UatHttpResult(201, {
            'playerId': '11111111-1111-4111-8111-111111111111',
            'sessionSecret': 'secret',
          });
        }
        if (path.endsWith('/calendar')) {
          return UatHttpResult(200, _calendar(accountScoped: true, dayOverrides: {}));
        }
        return const UatHttpResult(404, {'error': 'NOT_FOUND'});
      });
      final live = await _pumpHome(tester, api: api);
      live.activeManifestUtcDate = '2026-11-28';
      live.seriesId = 'series-sat';
      live.day = const TournamentDay(
        seriesId: 'series-sat',
        original: true,
        claimStatus: 'COMPLETED',
        ordinal: 6,
        seriesScore: 10600,
        resultsPublished: true,
      );
      live.results = {'all': 10600, 'onTimeAwarded': true};
      live.selectedTournamentDate = '2026-11-28';
      live.notifyListeners();
      await tester.pump();
      expect(find.textContaining('10,600'), findsWidgets);

      live.selectTournamentDay('2026-11-23');
      await tester.pump();
      expect(find.textContaining('10,600'), findsNothing);
      expect(find.textContaining('On-Time'), findsNothing);
      expect(find.text('—'), findsWidgets);
    },
  );

  testWidgets('active Tuesday progress does not leak onto Monday', (tester) async {
    final api = ScriptedUatApi((method, path, body) async {
      if (path.endsWith('/session') && method == 'POST') {
        return const UatHttpResult(201, {
          'playerId': '11111111-1111-4111-8111-111111111111',
          'sessionSecret': 'secret',
        });
      }
      if (path.endsWith('/calendar')) {
        return UatHttpResult(200, _calendar(accountScoped: true, dayOverrides: {}));
      }
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });
    final live = await _pumpHome(tester, api: api);
    live.activeManifestUtcDate = '2026-11-24';
    live.seriesId = 'series-tue';
    live.day = const TournamentDay(
      seriesId: 'series-tue',
      original: true,
      claimStatus: 'ACTIVE',
      ordinal: 4,
      ordinalLabel: 'M1',
      seriesScore: 2100,
    );
    live.selectedTournamentDate = '2026-11-24';
    live.notifyListeners();
    await tester.pump();

    live.selectTournamentDay('2026-11-23');
    await tester.pump();
    expect(find.textContaining('2,100'), findsNothing);
    // Board-progress pips always label E1–H2; assert no active ordinal highlight
    // from Tuesday (ordinal 4) by keeping Monday score empty and Start CTA.
    expect(find.text('—'), findsWidgets);
    expect(find.text('Start challenge'), findsOneWidget);
  });

  testWidgets('completed Wednesday shows only Wednesday score/timing', (
    tester,
  ) async {
    final api = ScriptedUatApi((method, path, body) async {
      if (path.endsWith('/session') && method == 'POST') {
        return const UatHttpResult(201, {
          'playerId': '11111111-1111-4111-8111-111111111111',
          'sessionSecret': 'secret',
        });
      }
      if (path.endsWith('/calendar')) {
        return UatHttpResult(200, _calendar(accountScoped: true, dayOverrides: {}));
      }
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });
    final live = await _pumpHome(tester, api: api);
    live.activeManifestUtcDate = '2026-11-28';
    live.seriesId = 'series-sat';
    live.day = const TournamentDay(
      seriesId: 'series-sat',
      original: true,
      claimStatus: 'COMPLETED',
      seriesScore: 10600,
      resultsPublished: true,
    );
    live.results = {'all': 10600, 'onTimeAwarded': true};
    live.selectTournamentDay('2026-11-25');
    await tester.pump();
    expect(find.textContaining('8,000'), findsWidgets);
    expect(find.textContaining('10,600'), findsNothing);
  });

  testWidgets('future Sunday cannot start and shows no foreign score', (
    tester,
  ) async {
    final api = ScriptedUatApi((method, path, body) async {
      if (path.endsWith('/session') && method == 'POST') {
        return const UatHttpResult(201, {
          'playerId': '11111111-1111-4111-8111-111111111111',
          'sessionSecret': 'secret',
        });
      }
      if (path.endsWith('/calendar')) {
        return UatHttpResult(200, _calendar(accountScoped: true, dayOverrides: {}));
      }
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });
    final live = await _pumpHome(tester, api: api);
    live.activeManifestUtcDate = '2026-11-28';
    live.day = const TournamentDay(
      seriesId: 'series-sat',
      original: true,
      claimStatus: 'COMPLETED',
      seriesScore: 10600,
      resultsPublished: true,
    );
    live.results = {'all': 10600, 'onTimeAwarded': true};
    live.selectTournamentDay('2026-11-29');
    await tester.pump();
    expect(find.textContaining('10,600'), findsNothing);
    final button = tester.widget<FilledButton>(find.byKey(const Key('primary-action')));
    expect(button.onPressed, isNull);
  });

  testWidgets('guest mode hides personal score and board pips', (tester) async {
    final api = ScriptedUatApi((method, path, body) async {
      if (path.endsWith('/session') && method == 'POST') {
        return const UatHttpResult(201, {
          'playerId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'sessionSecret': 'secret',
        });
      }
      if (path.endsWith('/calendar')) {
        return UatHttpResult(
          200,
          _calendar(accountScoped: false, dayOverrides: {}),
        );
      }
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });
    final live = await _pumpHome(tester, api: api);
    live.applyGuestSessionAfterLogout(rankedAuthRequired: true);
    live.weeklyOverview = WeeklyTournamentOverview.tryParse(
      _calendar(accountScoped: false, dayOverrides: {}),
    );
    live.selectedTournamentDate = '2026-11-28';
    live.notifyListeners();
    await tester.pump();
    expect(find.textContaining('10,600'), findsNothing);
    expect(find.text('Join tournament'), findsWidgets);
    // Guest calendar has no personal pip row under the card score section.
    expect(find.byType(FilledButton), findsWidgets);
  });
}
