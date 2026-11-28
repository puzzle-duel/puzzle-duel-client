import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/presentation/feedback/app_top_banner.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_copy.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_uat_app.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';

import 'tournament_command_test.dart' show ScriptedUatApi;

Map<String, Object?> _okCalendar() {
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
    'completedDayCount': 0,
    'playablePastDayCount': 5,
    'accountScoped': true,
    'days': [
      for (final date in dates)
        {
          'date': date,
          'status': date == '2026-11-29'
              ? 'LOCKED_FUTURE'
              : date == '2026-11-28'
              ? 'AVAILABLE_TODAY'
              : 'AVAILABLE_PAST',
          'isToday': date == '2026-11-28',
          'canStart': date != '2026-11-29',
          'canResume': false,
          'canViewResults': false,
          'completedBoardCount': 0,
          'totalBoardCount': 6,
        },
    ],
  };
}

Future<TournamentController> _pumpHome(
  WidgetTester tester, {
  required ScriptedUatApi api,
  Locale locale = const Locale('tr'),
}) async {
  final dir = Directory.systemTemp.createTempSync('pzd55-cal-err');
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
        playerLabel: 'cal-err',
      ),
      api: api,
      stateDirectory: dir,
      locale: locale,
    ),
  );
  for (var i = 0; i < 100; i++) {
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

  test('weekly overview failure copy is localized TR/EN', () {
    final tr = TournamentCopy(const Locale('tr'));
    final en = TournamentCopy(const Locale('en'));
    expect(
      tr.weeklyOverviewUnavailable,
      'Haftalık turnuva bilgileri yüklenemedi.',
    );
    expect(
      en.weeklyOverviewUnavailable,
      'Weekly tournament information could not be loaded.',
    );
    expect(
      tr.forTournamentRefreshError('WEEKLY_OVERVIEW_UNAVAILABLE'),
      tr.weeklyOverviewUnavailable,
    );
    expect(
      en.forTournamentRefreshError('AUTH_UNAVAILABLE'),
      en.weeklyOverviewUnavailable,
    );
    expect(tr.forTournamentRefreshError('AUTH_UNAVAILABLE'), isNot(tr.genericFailure));
  });

  testWidgets(
    'cold launch calendar HTTP 503 shows TR error and disables ranked CTA',
    (tester) async {
      var calendarCalls = 0;
      final api = ScriptedUatApi((method, path, body) async {
        if (path.endsWith('/session') && method == 'POST') {
          return const UatHttpResult(201, {
            'playerId': '11111111-1111-4111-8111-111111111111',
            'sessionSecret': 'secret',
          });
        }
        if (path.endsWith('/calendar')) {
          calendarCalls += 1;
          return const UatHttpResult(503, {'error': 'AUTH_UNAVAILABLE'});
        }
        return const UatHttpResult(404, {'error': 'NOT_FOUND'});
      });
      final live = await _pumpHome(tester, api: api);
      await tester.pump(const Duration(milliseconds: 200));

      expect(live.weeklyOverview, isNull);
      expect(live.weeklyOverviewFailed, isTrue);
      expect(live.tournamentNoticeCode, 'WEEKLY_OVERVIEW_UNAVAILABLE');
      expect(
        find.text('Haftalık turnuva bilgileri yüklenemedi.'),
        findsWidgets,
      );
      expect(find.text('Bugünün turnuvası açık'), findsNothing);
      expect(find.text('Turnuvaya başla'), findsNothing);
      expect(find.text('Yeniden dene'), findsOneWidget);

      final primary = tester.widget<FilledButton>(
        find.byKey(const Key('primary-action')),
      );
      expect(primary.onPressed, isNotNull);

      // Retry still fails — still no fabricated availability.
      await tester.tap(find.byKey(const Key('primary-action')));
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }
      expect(calendarCalls, greaterThanOrEqualTo(2));
      expect(find.text('Bugünün turnuvası açık'), findsNothing);
      expect(find.text('Turnuvaya başla'), findsNothing);
    },
  );

  testWidgets(
    'EN cold launch calendar 503 uses English overview error',
    (tester) async {
      final api = ScriptedUatApi((method, path, body) async {
        if (path.endsWith('/session') && method == 'POST') {
          return const UatHttpResult(201, {
            'playerId': '11111111-1111-4111-8111-111111111111',
            'sessionSecret': 'secret',
          });
        }
        if (path.endsWith('/calendar')) {
          return const UatHttpResult(503, {'error': 'AUTH_UNAVAILABLE'});
        }
        return const UatHttpResult(404, {'error': 'NOT_FOUND'});
      });
      await _pumpHome(tester, api: api, locale: const Locale('en'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.text('Weekly tournament information could not be loaded.'),
        findsWidgets,
      );
      expect(find.text("Today’s tournament is open"), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
    },
  );

  testWidgets(
    'successful calendar retry recovers Home eligibility',
    (tester) async {
      var calendarCalls = 0;
      final api = ScriptedUatApi((method, path, body) async {
        if (path.endsWith('/session') && method == 'POST') {
          return const UatHttpResult(201, {
            'playerId': '11111111-1111-4111-8111-111111111111',
            'sessionSecret': 'secret',
          });
        }
        if (path.endsWith('/calendar')) {
          calendarCalls += 1;
          if (calendarCalls == 1) {
            return const UatHttpResult(503, {'error': 'AUTH_UNAVAILABLE'});
          }
          return UatHttpResult(200, _okCalendar());
        }
        return const UatHttpResult(404, {'error': 'NOT_FOUND'});
      });
      final live = await _pumpHome(tester, api: api);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Yeniden dene'), findsOneWidget);

      await tester.tap(find.byKey(const Key('primary-action')));
      await tester.pump();
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 25));
        if (live.weeklyOverview != null) break;
      }
      expect(live.weeklyOverviewFailed, isFalse);
      expect(live.weeklyOverview, isNotNull);
      expect(live.tournamentNoticeCode, isNull);
      expect(find.text('Bugünün turnuvası açık'), findsOneWidget);
      expect(find.text('Turnuvaya başla'), findsOneWidget);
      final primary = tester.widget<FilledButton>(
        find.byKey(const Key('primary-action')),
      );
      expect(primary.onPressed, isNotNull);
    },
  );

  test('Log Gönder success userMessage includes reportId exactly once', () {
    const id = 'b3e21fcf-0673-4aff-97e9-696ec79ddedf';
    // Mirrors settings banner: present userMessage alone (no second append).
    final message = 'Sunucu raporu alındı: $id';
    expect(RegExp(RegExp.escape(id)).allMatches(message).length, 1);
    expect(message.contains('($id)'), isFalse);
  });
}
