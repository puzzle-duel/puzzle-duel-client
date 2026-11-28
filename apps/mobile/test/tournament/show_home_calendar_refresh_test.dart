import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/tournament/practice_identity.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_controller.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_nav.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';
import 'package:puzzle_duel_mobile/tournament/weekly_tournament_overview.dart';

import 'tournament_command_test.dart' show ScriptedUatApi;

Map<String, Object?> _calendar({
  required String focusDate,
  required String focusStatus,
  int? verifiedScore,
  String? completionTiming,
  bool canStart = false,
  bool canViewResults = false,
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
    'completedDayCount': focusStatus == 'COMPLETED' ? 1 : 0,
    'playablePastDayCount': focusDate == '2026-11-25' ? 0 : 4,
    'accountScoped': true,
    'days': [
      for (final date in dates)
        {
          'date': date,
          'status': date == focusDate
              ? focusStatus
              : date == '2026-11-29'
              ? 'LOCKED_FUTURE'
              : date == '2026-11-28'
              ? 'AVAILABLE_TODAY'
              : 'AVAILABLE_PAST',
          'isToday': date == '2026-11-28',
          'canStart': date == focusDate
              ? canStart
              : date != '2026-11-29' && date != focusDate,
          'canResume': false,
          'canViewResults': date == focusDate ? canViewResults : false,
          'completedBoardCount':
              date == focusDate && focusStatus == 'COMPLETED' ? 6 : 0,
          'totalBoardCount': 6,
          if (date == focusDate && verifiedScore != null) ...{
            'seriesId': 'series-$date',
            'verifiedScore': verifiedScore,
            'completionTiming': completionTiming,
          },
        },
    ],
  };
}

Future<TournamentController> _controller(
  ScriptedUatApi api,
) async {
  final dir = Directory.systemTemp.createTempSync('pzd55-show-home');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  final identity = PracticeIdentityStore(dir);
  await identity.load();
  return TournamentController(
    config: const UatConfig(
      baseUrl: 'http://127.0.0.1',
      bearer: 'Bearer test',
      playerLabel: 'show-home',
    ),
    api: api,
    stateDirectory: dir,
    identity: identity,
    haptics: const SilentTournamentHaptics(),
  );
}

void main() {
  test(
    'showHome refreshes calendar after today completion while ready',
    () async {
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
            return UatHttpResult(
              200,
              _calendar(
                focusDate: '2026-11-28',
                focusStatus: 'AVAILABLE_TODAY',
                canStart: true,
              ),
            );
          }
          return UatHttpResult(
            200,
            _calendar(
              focusDate: '2026-11-28',
              focusStatus: 'COMPLETED',
              verifiedScore: 10600,
              completionTiming: 'ON_TIME',
              canViewResults: true,
            ),
          );
        }
        return const UatHttpResult(404, {'error': 'NOT_FOUND'});
      });
      final controller = await _controller(api);
      await controller.start();
      expect(calendarCalls, 1);
      controller.selectedTournamentDate = '2026-11-28';
      controller.tournamentSync = TournamentSyncState.ready;
      controller.route = const TournamentRoute(place: TournamentPlace.results);
      final claimsBefore = api.claimPosts;

      await controller.showHome();

      expect(controller.route.place, TournamentPlace.home);
      expect(calendarCalls, 2);
      expect(controller.selectedTournamentDate, '2026-11-28');
      expect(controller.selectedWeeklyDay?.status, WeeklyDayStatus.completed);
      expect(controller.selectedWeeklyDay?.verifiedScore, 10600);
      expect(controller.selectedWeeklyDay?.completionTiming, CompletionTiming.onTime);
      expect(controller.selectedWeeklyDay?.canViewResults, isTrue);
      expect(controller.weeklyOverview?.completedDayCount, 1);
      expect(api.claimPosts, claimsBefore);
    },
  );

  test(
    'showHome refreshes calendar after past manifest completion while ready',
    () async {
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
            return UatHttpResult(
              200,
              _calendar(
                focusDate: '2026-11-25',
                focusStatus: 'AVAILABLE_PAST',
                canStart: true,
              ),
            );
          }
          return UatHttpResult(
            200,
            _calendar(
              focusDate: '2026-11-25',
              focusStatus: 'COMPLETED',
              verifiedScore: 8000,
              completionTiming: 'LATE',
              canViewResults: true,
            ),
          );
        }
        return const UatHttpResult(404, {'error': 'NOT_FOUND'});
      });
      final controller = await _controller(api);
      await controller.start();
      controller.selectedTournamentDate = '2026-11-25';
      controller.tournamentSync = TournamentSyncState.ready;
      controller.route = const TournamentRoute(place: TournamentPlace.playing);
      final claimsBefore = api.claimPosts;

      await controller.showHome();

      expect(calendarCalls, 2);
      expect(controller.selectedTournamentDate, '2026-11-25');
      expect(controller.selectedWeeklyDay?.status, WeeklyDayStatus.completed);
      expect(controller.selectedWeeklyDay?.verifiedScore, 8000);
      expect(controller.selectedWeeklyDay?.completionTiming, CompletionTiming.late);
      expect(controller.selectedWeeklyDay?.canViewResults, isTrue);
      expect(api.claimPosts, claimsBefore);
    },
  );

  test('concurrent showHome joins one calendar refresh', () async {
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
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return UatHttpResult(
          200,
          _calendar(
            focusDate: '2026-11-28',
            focusStatus: 'AVAILABLE_TODAY',
            canStart: true,
          ),
        );
      }
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });
    final controller = await _controller(api);
    await controller.start();
    final afterStart = calendarCalls;
    controller.tournamentSync = TournamentSyncState.ready;
    await Future.wait([controller.showHome(), controller.showHome()]);
    expect(calendarCalls, afterStart + 1);
  });
}
