import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_copy.dart';

void main() {
  test('rankedAuthRequired EN/TR are concise auth CTAs (no free/paid)', () {
    final en = TournamentCopy(const Locale('en'));
    final tr = TournamentCopy(const Locale('tr'));

    expect(en.rankedAuthRequired, 'Sign in to enter the tournament.');
    expect(tr.rankedAuthRequired, 'Turnuvaya katılmak için oturum açmalısın.');

    for (final copy in [en.rankedAuthRequired, tr.rankedAuthRequired]) {
      final lower = copy.toLowerCase();
      expect(lower.contains('free'), isFalse);
      expect(lower.contains('paid'), isFalse);
      expect(lower.contains('ücretsiz'), isFalse);
      expect(lower.contains('ücret'), isFalse);
      expect(lower.contains('practice remains'), isFalse);
      expect(lower.contains('pratik ücretsiz'), isFalse);
    }
  });

  test('guest Home invite copy stays approved and non-monetized', () {
    final en = TournamentCopy(const Locale('en'));
    final tr = TournamentCopy(const Locale('tr'));

    expect(
      en.guestTournamentBody,
      'Sign in with Apple or Google to enter the tournament.',
    );
    expect(
      tr.guestTournamentBody,
      'Turnuvaya katılmak için Apple veya Google hesabınla oturum aç.',
    );
    expect(en.guestTournamentHeadline, 'Join tournament');
    expect(tr.guestTournamentHeadline, 'Turnuvaya katıl');
  });

  test('auth gate copy map resolves RANKED_AUTH_REQUIRED to new strings', () {
    final en = TournamentCopy(const Locale('en'));
    final tr = TournamentCopy(const Locale('tr'));
    expect(
      en.forTournamentRefreshError('RANKED_AUTH_REQUIRED'),
      en.rankedAuthRequired,
    );
    expect(
      tr.forTournamentRefreshError('RANKED_AUTH_REQUIRED'),
      tr.rankedAuthRequired,
    );
  });
}
