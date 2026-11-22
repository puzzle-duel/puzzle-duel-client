import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_copy.dart';

void main() {
  test('home refresh failure never claims a move was rejected', () {
    for (final locale in [const Locale('tr'), const Locale('en')]) {
      final copy = TournamentCopy(locale);
      for (final code in ['NOT_FOUND', 'MALFORMED_REQUEST', 'RATE_LIMITED', 'BOOTSTRAP_FAILED', 'RECOVERY_NOT_ELIGIBLE', 'UNKNOWN_ERROR']) {
        final home = copy.forTournamentRefreshError(code);
        expect(home, isNot(equals(copy.rejectedMove)));
        expect(home, isNot(contains(locale.languageCode == 'tr'
            ? 'hamle kabul edilmedi' : 'move was not accepted')));
      }
      expect(copy.forError('NOT_FOUND'), copy.rejectedMove);
    }
  });

  test('Home keeps proper session and connectivity messages', () {
    final copy = TournamentCopy(const Locale('tr'));
    expect(copy.forTournamentRefreshError('UNAUTHENTICATED'), copy.unauthorized);
    expect(copy.forTournamentRefreshError('WRITER_NOT_AUTHORIZED'), copy.writerBlocked);
    expect(copy.forTournamentRefreshError('TIMEOUT'), copy.timedOut);
    expect(copy.forTournamentRefreshError('OFFLINE'), copy.offline);
  });
}
