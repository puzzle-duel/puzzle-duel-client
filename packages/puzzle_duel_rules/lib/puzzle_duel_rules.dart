/// Immutable Puzzle Duel state, validation, placement, match, and shift.
///
/// [applyPlacement] places one piece. [clearMatches] and [applyShift] are
/// independent phases. [resolveAfterPlacement] clears once and shifts once
/// after a real clear. Cascades, scoring, offer commit, and game end are not
/// implemented here.
library;

part 'src/failure.dart';
part 'src/match_shift.dart';
part 'src/parse.dart';
part 'src/placement.dart';
part 'src/values.dart';
