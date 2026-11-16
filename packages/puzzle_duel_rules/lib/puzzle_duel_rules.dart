/// Immutable Puzzle Duel state, validation, placement, match, shift, move
/// resolution, and accepted `gen-001.v1` challenge generation.
///
/// [applyMove] resolves a complete CORE-001 turn. [generateChallenge] builds a
/// deterministic initial [GeneratedChallenge] under `core-001.v2`.
library;

part 'src/challenge_generator.dart';
part 'src/deterministic_rng.dart';
part 'src/failure.dart';
part 'src/match_shift.dart';
part 'src/parse.dart';
part 'src/placement.dart';
part 'src/resolution.dart';
part 'src/values.dart';
