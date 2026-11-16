import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

/// Thin adapter over the pure Dart [generateChallenge] API.
///
/// Does not invent scores, cascades, or pieces. Typed generation failures are
/// returned unchanged.
final class ChallengeFactory {
  const ChallengeFactory();

  /// Builds a deterministic challenge for [profile] and [seed].
  ChallengeGenerationResult generate({
    required DifficultyProfile profile,
    required int seed,
  }) {
    return generateChallenge(ChallengeGenerationConfig.profile(profile), seed);
  }
}
