import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_copy.dart';
import 'package:puzzle_duel_mobile/tournament/weekly_tournament_calendar.dart';
import 'package:puzzle_duel_mobile/tournament/weekly_tournament_overview.dart';

WeeklyTournamentOverview _overview({required bool accountScoped}) {
  return WeeklyTournamentOverview.tryParse({
    'weekStartUtc': '2026-11-23',
    'weekEndUtc': '2026-11-29',
    'serverNowMs': 1,
    'currentTournamentDate': '2026-11-28',
    'completedDayCount': accountScoped ? 4 : 0,
    'playablePastDayCount': accountScoped ? 2 : 0,
    'accountScoped': accountScoped,
    'days': [
      for (final entry in [
        ('2026-11-23', 'AVAILABLE_PAST', false),
        ('2026-11-24', 'AVAILABLE_PAST', false),
        ('2026-11-25', 'COMPLETED', false),
        ('2026-11-26', 'COMPLETED', false),
        ('2026-11-27', 'COMPLETED', false),
        ('2026-11-28', 'COMPLETED', true),
        ('2026-11-29', 'LOCKED_FUTURE', false),
      ])
        {
          'date': entry.$1,
          'status': accountScoped
              ? entry.$2
              : (entry.$3
                    ? 'AVAILABLE_TODAY'
                    : entry.$2 == 'LOCKED_FUTURE'
                    ? 'LOCKED_FUTURE'
                    : 'AVAILABLE_PAST'),
          'isToday': entry.$3,
          'canStart': accountScoped && entry.$2 == 'AVAILABLE_PAST',
          'canResume': false,
          'canViewResults': accountScoped && entry.$2 == 'COMPLETED',
          'completedBoardCount': entry.$2 == 'COMPLETED' ? 6 : 0,
          'totalBoardCount': 6,
          if (accountScoped && entry.$2 == 'COMPLETED') 'verifiedScore': 10600,
        },
    ],
  })!;
}

void main() {
  testWidgets('RC visual goldens: guest + verified calendar', (tester) async {
    Future<void> pumpCalendar({
      required bool accountScoped,
      required String selected,
      required String golden,
    }) async {
      await tester.binding.setSurfaceSize(const Size(390, 280));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: TournamentLocale(
            locale: const Locale('tr'),
            child: Scaffold(
              backgroundColor: const Color(0xFF070B16),
              body: Center(
                child: SizedBox(
                  width: 360,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: WeeklyTournamentCalendar(
                      overview: _overview(accountScoped: accountScoped),
                      selectedDate: selected,
                      accountScoped: accountScoped,
                      onSelect: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await expectLater(
        find.byType(WeeklyTournamentCalendar),
        matchesGoldenFile('goldens/$golden.png'),
      );
    }

    await pumpCalendar(
      accountScoped: false,
      selected: '2026-11-28',
      golden: 'pzd55-guest-calendar',
    );
    await pumpCalendar(
      accountScoped: true,
      selected: '2026-11-28',
      golden: 'pzd55-verified-calendar',
    );
    await pumpCalendar(
      accountScoped: true,
      selected: '2026-11-23',
      golden: 'pzd55-verified-past-selected',
    );
  });
}
