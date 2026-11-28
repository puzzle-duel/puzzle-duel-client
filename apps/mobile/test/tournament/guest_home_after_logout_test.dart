import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/presentation/feedback/app_top_banner.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_nav.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_uat_app.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';
import 'package:puzzle_duel_mobile/tournament/weekly_tournament_overview.dart';

import 'tournament_command_test.dart' show ScriptedUatApi;

/// A01 / A19 — Guest Home must not paint previous verified tournament personal data.
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
    'A01/A19 guest Home after logout shows invite CTA without prior score/progress',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('pzd54-guest-home');
      addTearDown(() {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });
      final api = ScriptedUatApi((method, path, body) async {
        if (path.endsWith('/session') && method == 'POST') {
          return const UatHttpResult(201, {
            'playerId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
            'sessionSecret': 'secret',
          });
        }
        if (path.endsWith('/calendar') && method == 'GET') {
          return UatHttpResult(200, _guestCalendarFixture());
        }
        if (path.endsWith('/claims/daily')) {
          return const UatHttpResult(201, {
            'seriesId': 'series-1',
            'status': 'COMPLETED',
            'original': true,
          });
        }
        if (path.endsWith('/board')) {
          return const UatHttpResult(200, {
            'ordinal': 6,
            'ordinalLabel': 'H1',
            'seriesScore': 10200,
            'awaitAdvance': false,
            'resultsPublished': true,
            'state': {'turnsUsed': 10, 'moveLimit': 15, 'boardSize': 5},
          });
        }
        if (path.contains('/results')) {
          return const UatHttpResult(200, {
            'all': 10200,
            'onTimeAwarded': true,
            'easy': 3000,
            'medium': 4000,
            'hard': 3200,
          });
        }
        return const UatHttpResult(404, {'error': 'NOT_FOUND'});
      });

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        TournamentUatApp(
          config: UatConfig(
            baseUrl: 'http://127.0.0.1',
            bearer: _jwt(
              sub: '11111111-1111-1111-1111-111111111111',
              accountType: 'verified',
            ),
            playerLabel: 'Verified',
          ),
          api: api,
          stateDirectory: directory,
          haptics: const SilentTournamentHaptics(),
          locale: const Locale('en'),
        ),
      );
      await tester.pump();
      for (var i = 0; i < 80; i++) {
        if (find.byKey(const Key('practice')).evaluate().isNotEmpty) break;
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byKey(const Key('practice')), findsOneWidget);

      final live = tester
          .widget<AppTopBannerHost>(
            find.byKey(const Key('tournament-status-host')),
          )
          .controller;

      // Verified personal presentation requires account-scoped overview +
      // matching active/selected manifest identity (PZD-55 isolation).
      live.weeklyOverview = WeeklyTournamentOverview.tryParse({
        'weekStartUtc': '2026-11-23',
        'weekEndUtc': '2026-11-29',
        'serverNowMs': 1,
        'currentTournamentDate': '2026-11-28',
        'completedDayCount': 1,
        'playablePastDayCount': 0,
        'accountScoped': true,
        'days': [
          for (final date in [
            '2026-11-23',
            '2026-11-24',
            '2026-11-25',
            '2026-11-26',
            '2026-11-27',
            '2026-11-28',
            '2026-11-29',
          ])
            {
              'date': date,
              'status': date == '2026-11-29'
                  ? 'LOCKED_FUTURE'
                  : date == '2026-11-28'
                  ? 'COMPLETED'
                  : 'AVAILABLE_PAST',
              'isToday': date == '2026-11-28',
              'canStart': false,
              'canResume': false,
              'canViewResults': date == '2026-11-28',
              'completedBoardCount': date == '2026-11-28' ? 6 : 0,
              'totalBoardCount': 6,
              if (date == '2026-11-28') ...{
                'seriesId': 'series-a',
                'verifiedScore': 10200,
                'completionTiming': 'ON_TIME',
              },
            },
        ],
      });
      live.selectedTournamentDate = '2026-11-28';
      live.activeManifestUtcDate = '2026-11-28';
      live.seriesId = 'series-a';
      live.day = const TournamentDay(
        seriesId: 'series-a',
        original: true,
        claimStatus: 'COMPLETED',
        ordinal: 6,
        ordinalLabel: 'H1',
        seriesScore: 10200,
        resultsPublished: true,
      );
      live.results = {'all': 10200, 'onTimeAwarded': true};
      live.rankedAuthRequired = false;
      live.tournamentNoticeCode = null;
      live.notifyListeners();
      await tester.pump();

      expect(find.textContaining('10,200'), findsWidgets);

      live.applyGuestSessionAfterLogout(rankedAuthRequired: true);
      await tester.pump();
      expect(find.textContaining('10,200'), findsNothing);
      expect(live.day, isNull);
      expect(live.results, isEmpty);

      // Mimic post-logout public calendar refresh (logout handler calls refreshTournament).
      live.weeklyOverview = WeeklyTournamentOverview.tryParse({
        'weekStartUtc': '2026-11-23',
        'weekEndUtc': '2026-11-29',
        'serverNowMs': 1,
        'currentTournamentDate': '2026-11-28',
        'completedDayCount': 0,
        'playablePastDayCount': 0,
        'accountScoped': false,
        'days': [
          for (final date in [
            '2026-11-23',
            '2026-11-24',
            '2026-11-25',
            '2026-11-26',
            '2026-11-27',
            '2026-11-28',
            '2026-11-29',
          ])
            {
              'date': date,
              'status': date == '2026-11-29'
                  ? 'LOCKED_FUTURE'
                  : date == '2026-11-28'
                  ? 'AVAILABLE_TODAY'
                  : 'AVAILABLE_PAST',
              'isToday': date == '2026-11-28',
              'canStart': false,
              'canResume': false,
              'canViewResults': false,
              'completedBoardCount': 0,
              'totalBoardCount': 6,
            },
        ],
      });
      live.selectedTournamentDate = '2026-11-28';
      live.notifyListeners();
      await tester.pump();

      expect(find.textContaining('10,200'), findsNothing);
      expect(find.textContaining('On-Time'), findsNothing);
      expect(find.textContaining("Today's tournament completed"), findsNothing);
      expect(find.text('Join tournament'), findsWidgets);
      expect(
        find.text('Sign in with Apple or Google to enter the tournament.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('primary-action')), findsOneWidget);
      expect(find.byKey(const Key('weekly-tournament-calendar')), findsOneWidget);
      expect(find.text('Oyna'), findsNothing);
      expect(live.day, isNull);
      expect(live.results, isEmpty);
      expect(live.tournamentNoticeCode, isNull);
    },
  );
}

String _jwt({required String sub, required String accountType}) {
  final header = base64Url
      .encode(utf8.encode(jsonEncode({'alg': 'none'})))
      .replaceAll('=', '');
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'iss': 'https://staging.puzzle-duel.app',
            'aud': 'puzzle-duel-api',
            'sub': sub,
            'account_type': accountType,
            'fid': 'fid',
          }),
        ),
      )
      .replaceAll('=', '');
  return '$header.$payload.sig';
}

Map<String, Object?> _guestCalendarFixture() {
  final today = DateTime.now().toUtc();
  final dayStart = DateTime.utc(today.year, today.month, today.day);
  final mondayOffset = (dayStart.weekday + 6) % 7;
  final monday = dayStart.subtract(Duration(days: mondayOffset));
  final days = <Map<String, Object?>>[];
  for (var i = 0; i < 7; i++) {
    final date = monday.add(Duration(days: i));
    final iso = date.toIso8601String().substring(0, 10);
    final isToday = date == dayStart;
    final isFuture = date.isAfter(dayStart);
    days.add({
      'date': iso,
      'status': isFuture
          ? 'LOCKED_FUTURE'
          : isToday
          ? 'AVAILABLE_TODAY'
          : 'AVAILABLE_PAST',
      'isToday': isToday,
      'canStart': false,
      'canResume': false,
      'canViewResults': false,
      'completedBoardCount': 0,
      'totalBoardCount': 6,
    });
  }
  return {
    'weekStartUtc': monday.toIso8601String().substring(0, 10),
    'weekEndUtc': monday.add(const Duration(days: 6)).toIso8601String().substring(0, 10),
    'serverNowMs': DateTime.now().toUtc().millisecondsSinceEpoch,
    'currentTournamentDate': dayStart.toIso8601String().substring(0, 10),
    'completedDayCount': 0,
    'playablePastDayCount': 0,
    'accountScoped': false,
    'days': days,
  };
}
