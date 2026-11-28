import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/tournament/weekly_tournament_overview.dart';

void main() {
  test('parses owner catch-up week fixture without claiming rights for guests', () {
    final overview = WeeklyTournamentOverview.tryParse({
      'weekStartUtc': '2026-11-23',
      'weekEndUtc': '2026-11-29',
      'serverNowMs': DateTime.utc(2026, 11, 28, 15).millisecondsSinceEpoch,
      'currentTournamentDate': '2026-11-28',
      'completedDayCount': 3,
      'playablePastDayCount': 2,
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
    expect(overview, isNotNull);
    expect(overview!.days, hasLength(7));
    expect(overview.accountScoped, isFalse);
    expect(overview.dayFor('2026-11-23')!.canStart, isFalse);
    expect(overview.dayFor('2026-11-29')!.status, WeeklyDayStatus.lockedFuture);
  });

  test('parses verified completed and past-playable day states', () {
    final overview = WeeklyTournamentOverview.tryParse({
      'weekStartUtc': '2026-11-23',
      'weekEndUtc': '2026-11-29',
      'serverNowMs': 1,
      'currentTournamentDate': '2026-11-28',
      'completedDayCount': 3,
      'playablePastDayCount': 2,
      'accountScoped': true,
      'days': [
        {
          'date': '2026-11-23',
          'status': 'AVAILABLE_PAST',
          'isToday': false,
          'canStart': true,
          'canResume': false,
          'canViewResults': false,
          'completedBoardCount': 0,
          'totalBoardCount': 6,
        },
        {
          'date': '2026-11-24',
          'status': 'AVAILABLE_PAST',
          'isToday': false,
          'canStart': true,
          'canResume': false,
          'canViewResults': false,
          'completedBoardCount': 0,
          'totalBoardCount': 6,
        },
        {
          'date': '2026-11-25',
          'status': 'COMPLETED',
          'isToday': false,
          'canStart': false,
          'canResume': false,
          'canViewResults': true,
          'seriesId': 's1',
          'verifiedScore': 10600,
          'completionTiming': 'ON_TIME',
          'completedBoardCount': 6,
          'totalBoardCount': 6,
        },
        {
          'date': '2026-11-26',
          'status': 'COMPLETED',
          'isToday': false,
          'canStart': false,
          'canResume': false,
          'canViewResults': true,
          'seriesId': 's2',
          'verifiedScore': 9000,
          'completionTiming': 'ON_TIME',
          'completedBoardCount': 6,
          'totalBoardCount': 6,
        },
        {
          'date': '2026-11-27',
          'status': 'COMPLETED',
          'isToday': false,
          'canStart': false,
          'canResume': false,
          'canViewResults': true,
          'seriesId': 's3',
          'verifiedScore': 8000,
          'completionTiming': 'ON_TIME',
          'completedBoardCount': 6,
          'totalBoardCount': 6,
        },
        {
          'date': '2026-11-28',
          'status': 'AVAILABLE_TODAY',
          'isToday': true,
          'canStart': true,
          'canResume': false,
          'canViewResults': false,
          'completedBoardCount': 0,
          'totalBoardCount': 6,
        },
        {
          'date': '2026-11-29',
          'status': 'LOCKED_FUTURE',
          'isToday': false,
          'canStart': false,
          'canResume': false,
          'canViewResults': false,
          'completedBoardCount': 0,
          'totalBoardCount': 6,
        },
      ],
    });
    expect(overview, isNotNull);
    expect(overview!.dayFor('2026-11-23')!.canStart, isTrue);
    expect(overview.dayFor('2026-11-25')!.verifiedScore, 10600);
    expect(
      overview.dayFor('2026-11-25')!.completionTiming,
      CompletionTiming.onTime,
    );
  });
}
