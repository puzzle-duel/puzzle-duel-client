import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/application/challenge_session.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

void main() {
  test('session starts ready without network or auth', () {
    final session = ChallengeSession();
    expect(session.snapshot.ready, isTrue);
    expect(session.snapshot.hasChallenge, isFalse);
    expect(session.supportedProfiles, DifficultyProfile.values);
  });

  test('application state does not mutate the engine snapshot', () {
    final session = ChallengeSession();
    session.runGeneratorSmokeTest(profile: DifficultyProfile.easy, seed: 42);
    final first = session.snapshot.lastChallenge!;
    final scoreBefore = first.state.score;
    final blockedBefore = first.state.blocked.length;

    session.runGeneratorSmokeTest(profile: DifficultyProfile.medium, seed: 1);

    expect(first.state.score, scoreBefore);
    expect(first.state.blocked.length, blockedBefore);
    expect(identical(session.snapshot.lastChallenge, first), isFalse);
  });

  test('typed failures surface on the session snapshot', () {
    final session = ChallengeSession();
    session.runGeneratorSmokeTest(profile: DifficultyProfile.easy, seed: -1);
    expect(session.snapshot.hasFailure, isTrue);
    expect(
      session.snapshot.lastFailure,
      ChallengeGenerationError.invalidConfig,
    );
    expect(session.snapshot.lastErrorMessage, 'invalid_config');
    expect(session.snapshot.hasChallenge, isFalse);
  });
}
