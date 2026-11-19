import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_copy.dart';

void main() {
  const english = TournamentCopy(Locale('en'));
  const turkish = TournamentCopy(Locale('tr'));

  test('week ranges use the server date and a six-day UTC span', () {
    expect(english.weekRange('2026-11-16'), '16–22 November 2026');
    expect(turkish.weekRange('2026-11-16'), '16–22 Kasım 2026');
    expect(english.weekRange('2026-11-30'), '30 November–6 December 2026');
    expect(english.dayLabel('2026-11-18'), '18 November 2026');
    expect(turkish.dayLabel('2026-11-18'), '18 Kasım 2026');
    expect(english.weekRange('not-a-date'), 'not-a-date');
  });

  test('scores use the player locale grouping and do not round', () {
    expect(english.groupedScore(11000), '11,000');
    expect(turkish.groupedScore(11000), '11.000');
    expect(english.groupedScore(1900), '1,900');
    expect(english.groupedScore(0), '0');
  });
}
