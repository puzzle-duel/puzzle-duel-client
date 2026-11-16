/// Immutable Puzzle Duel state, validation, placement, match, shift, and move
/// resolution.
///
/// [applyMove] resolves a complete CORE-001 turn: placement, cascades, integer
/// scoring, offer commit, and terminal status. Phase helpers remain available
/// for independent fixture coverage.
library;

part 'src/failure.dart';
part 'src/match_shift.dart';
part 'src/parse.dart';
part 'src/placement.dart';
part 'src/resolution.dart';
part 'src/values.dart';
