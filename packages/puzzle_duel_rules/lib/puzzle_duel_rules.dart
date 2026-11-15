/// Immutable Puzzle Duel state, validation, and placement phase.
///
/// [applyPlacement] places one piece and records one turn. It does not match,
/// clear, shift, cascade, score, or decide a final game end. A parsed [Move]
/// is not a played move until [applyPlacement] accepts it.
library;

part 'src/failure.dart';
part 'src/parse.dart';
part 'src/placement.dart';
part 'src/values.dart';
