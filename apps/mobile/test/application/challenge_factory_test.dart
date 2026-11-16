import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/application/challenge_factory.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

void main() {
  const factory = ChallengeFactory();

  test('explicit seed produces repeatable challenge state', () {
    final a = factory.generate(profile: DifficultyProfile.easy, seed: 42);
    final b = factory.generate(profile: DifficultyProfile.easy, seed: 42);

    expect(a, isA<GeneratedChallenge>());
    expect(b, isA<GeneratedChallenge>());
    final ga = a as GeneratedChallenge;
    final gb = b as GeneratedChallenge;
    expect(ga.toJson(), equals(gb.toJson()));
  });

  test('Easy/Medium/Hard map to Accepted generator profiles', () {
    for (final profile in DifficultyProfile.values) {
      final result = factory.generate(profile: profile, seed: 42);
      expect(result, isA<GeneratedChallenge>());
      final challenge = result as GeneratedChallenge;
      expect(challenge.profile, profile);
      expect(challenge.state.boardSize, profile.boardSize);
      expect(challenge.state.moveLimit, profile.moveLimit);
      expect(challenge.state.blocked.length, profile.obstacleCount);
    }
  });

  test('generated result carries correct generator and rules versions', () {
    final result = factory.generate(
      profile: DifficultyProfile.medium,
      seed: 1,
    );
    final challenge = result as GeneratedChallenge;
    expect(challenge.generatorVersion, GeneratorVersion.gen001V1);
    expect(challenge.rulesVersion, RulesVersion.core001V2);
    expect(challenge.generatorVersion.id, 'gen-001.v1');
    expect(challenge.rulesVersion.id, 'core-001.v2');
  });

  test('typed generation failures propagate for invalid seed', () {
    final result = factory.generate(
      profile: DifficultyProfile.easy,
      seed: -1,
    );
    expect(result, isA<ChallengeGenerationFailure>());
    final failure = result as ChallengeGenerationFailure;
    expect(failure.code, ChallengeGenerationError.invalidConfig);
    expect(failure.code.wire, 'invalid_config');
  });

  test('no network dependency is required to generate a local challenge', () {
    // Pure local path: factory never opens sockets or HTTP clients.
    final result = factory.generate(
      profile: DifficultyProfile.hard,
      seed: 123456789,
    );
    expect(result, isA<GeneratedChallenge>());
  });
}
