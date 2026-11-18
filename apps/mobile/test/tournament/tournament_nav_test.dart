import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_nav.dart';

void main() {
  test('leaderboard back returns to the screen that opened it', () {
    const home = TournamentRoute();
    expect(home.open(TournamentPlace.daily).back().place, TournamentPlace.home);

    const results = TournamentRoute(place: TournamentPlace.results);
    final dailyFromResults = results.open(TournamentPlace.daily);
    expect(dailyFromResults.back().place, TournamentPlace.results);
    expect(dailyFromResults.open(TournamentPlace.daily).leaderboardReturn, TournamentPlace.results);

    final weekly = results.open(TournamentPlace.weekly);
    expect(weekly.back().place, TournamentPlace.results);
    expect(results.back().place, TournamentPlace.home);
    expect(const TournamentRoute(place: TournamentPlace.overview).back().place, TournamentPlace.home);
  });

  test('a completed claim is a home state, not a results route', () {
    final day = dayFromPayload(
      claim: {
        'seriesId': 'series-1',
        'status': 'COMPLETED',
        'original': false,
      },
      board: {
        'ordinal': 6,
        'ordinalLabel': 'H1',
        'seriesScore': 900,
        'resultsPublished': true,
        'state': {'turnsUsed': 1},
      },
    );
    expect(day.phase, DayPhase.completed);
    expect(day.completedGames, 6);
    expect(const TournamentRoute().place, isNot(TournamentPlace.results));
  });

  test('ordinal progress matches the server fence', () {
    final fresh = dayFromPayload(
      claim: {'seriesId': 's', 'status': 'ACTIVE', 'original': true},
      board: {
        'ordinal': 1,
        'awaitAdvance': false,
        'state': {'turnsUsed': 0},
      },
    );
    expect(fresh.phase, DayPhase.ready);
    expect(fresh.completedGames, 0);

    final between = dayFromPayload(
      claim: {'seriesId': 's', 'status': 'ACTIVE', 'original': false},
      board: {'ordinal': 3, 'ordinalLabel': 'E3', 'awaitAdvance': true},
    );
    expect(between.phase, DayPhase.betweenGames);
    expect(between.completedGames, 3);
    expect(nextOrdinalLabel(3), 'M1');
  });
}
