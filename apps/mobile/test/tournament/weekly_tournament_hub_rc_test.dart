import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/theme/game_tokens.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_copy.dart';
import 'package:puzzle_duel_mobile/tournament/weekly_tournament_calendar.dart';
import 'package:puzzle_duel_mobile/tournament/weekly_tournament_overview.dart';

WeeklyTournamentOverview _week({required bool accountScoped}) {
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
        ('2026-11-28', 'AVAILABLE_TODAY', true),
        ('2026-11-29', 'LOCKED_FUTURE', false),
      ])
        {
          'date': entry.$1,
          'status': entry.$2,
          'isToday': entry.$3,
          'canStart': accountScoped &&
              (entry.$2 == 'AVAILABLE_PAST' || entry.$2 == 'AVAILABLE_TODAY'),
          'canResume': false,
          'canViewResults': accountScoped && entry.$2 == 'COMPLETED',
          'completedBoardCount': entry.$2 == 'COMPLETED' ? 6 : 0,
          'totalBoardCount': 6,
          if (entry.$2 == 'COMPLETED') 'verifiedScore': 1000,
        },
    ],
  })!;
}

Widget _wrap(Widget child) {
  return MaterialApp(
    home: TournamentLocale(
      locale: const Locale('tr'),
      child: Scaffold(
        body: MediaQuery(
          data: const MediaQueryData(size: Size(320, 700)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: child,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('RC-03 guest past days stay neutral; today cyan; future locked', (
    tester,
  ) async {
    final overview = _week(accountScoped: false);
    await tester.pumpWidget(
      _wrap(
        WeeklyTournamentCalendar(
          overview: overview,
          selectedDate: '2026-11-28',
          accountScoped: false,
          onSelect: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Pzt 23'), findsOneWidget);
    expect(find.textContaining('Cmt 28'), findsOneWidget);
    expect(find.textContaining('Paz 29'), findsOneWidget);
    // Guest must not show amber catch-up "Oyna" on past days.
    expect(find.text('Oyna'), findsNothing);
    expect(find.text('Tamamlandı'), findsNothing);
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_filled_rounded), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked_rounded), findsWidgets);

    final pastInk = tester.widget<Ink>(
      find
          .descendant(
            of: find.byKey(const Key('week-day-2026-11-23')),
            matching: find.byType(Ink),
          )
          .first,
    );
    final pastBorder = (pastInk.decoration! as BoxDecoration).border!;
    expect(
      (pastBorder as Border).top.color,
      isNot(GameTokens.scoreGlow),
    );
  });

  testWidgets('RC-03 verified past available is amber and shows day numbers', (
    tester,
  ) async {
    final overview = _week(accountScoped: true);
    await tester.pumpWidget(
      _wrap(
        WeeklyTournamentCalendar(
          overview: overview,
          // Keep selection on today so past-day border shows status color.
          selectedDate: '2026-11-28',
          accountScoped: true,
          onSelect: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Pzt 23'), findsOneWidget);
    expect(find.text('Oyna'), findsWidgets);
    expect(find.text('Tamamlandı'), findsWidgets);

    final pastInk = tester.widget<Ink>(
      find
          .descendant(
            of: find.byKey(const Key('week-day-2026-11-23')),
            matching: find.byType(Ink),
          )
          .first,
    );
    final pastBorder = ((pastInk.decoration! as BoxDecoration).border! as Border)
        .top
        .color;
    expect(pastBorder, GameTokens.scoreGlow);
  });

  testWidgets('RC-03 320px calendar has no overflow', (tester) async {
    final overview = _week(accountScoped: true);
    await tester.pumpWidget(
      _wrap(
        WeeklyTournamentCalendar(
          overview: overview,
          selectedDate: '2026-11-28',
          accountScoped: true,
          onSelect: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
