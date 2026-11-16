part of '../puzzle_duel_rules.dart';

/// Approved gameplay rejection codes for an in-bounds placement attempt.
///
/// These are not [ValidationCode] values. Out-of-bounds and malformed tap
/// precedence is not decided here.
enum GameplayRejection {
  blockedTap('blocked_tap'),
  occupiedTap('occupied_tap'),
  gameEnded('game_ended');

  const GameplayRejection(this.wire);

  final String wire;
}

/// Safety stop that is not a transport gameplay rejection.
///
/// Used when the tap is outside the board, or the selected offer slot has no
/// piece. The contract has not approved a precedence for those cases.
enum PlacementSafety {
  tapOutOfBounds('tap_out_of_bounds'),
  offerUnavailable('offer_unavailable'),
  integerOverflow('integer_overflow');

  const PlacementSafety(this.wire);

  final String wire;
}

/// How the consumed offer slot will be filled after later resolution.
///
/// The reference checkers replace the slot after match, clear, shift, cascade,
/// and scoring. This package records the same intent without finishing those
/// phases. A terminal null is never written here.
sealed class OfferConsumption {
  const OfferConsumption();
}

/// The stream has a replacement. After resolution, slot [offerIndex] becomes
/// [replacement] and [remainingFuture] is the unused tail.
final class OfferWillReplace extends OfferConsumption {
  OfferWillReplace({
    required this.offerIndex,
    required this.replacement,
    required List<Piece> remainingFuture,
  }) : remainingFuture = List<Piece>.unmodifiable(remainingFuture);

  final int offerIndex;
  final Piece replacement;
  final List<Piece> remainingFuture;
}

/// The stream is empty. V1 must abort rather than invent a piece. V2 may write
/// one terminal null only after resolution when the move reaches `moveLimit`.
/// An early board-full end with an empty stream stays unspecified.
final class OfferReplacementDeferred extends OfferConsumption {
  const OfferReplacementDeferred({required this.offerIndex});

  final int offerIndex;
}

/// Result of [applyPlacement]. This is not a fully resolved CORE-001 move.
sealed class PlacementResult {
  const PlacementResult();
}

/// Placement rejected. [state] is the unchanged input snapshot.
final class PlacementRejected extends PlacementResult {
  const PlacementRejected({required this.code, required this.state});

  final GameplayRejection code;
  final GameState state;
}

/// Internal safety rejection. Distinct from [GameplayRejection].
final class PlacementUnsafe extends PlacementResult {
  const PlacementUnsafe({required this.reason, required this.state});

  final PlacementSafety reason;
  final GameState state;
}

/// Placement phase only. Match, clear, shift, cascade, score, and end are not
/// applied. [cells] contain the piece at [landing]. [score] is unchanged.
/// [status] is the pre-move status and is not re-evaluated for board fill.
final class PlacementApplied extends PlacementResult {
  PlacementApplied({
    required this.before,
    required this.placedPiece,
    required this.landing,
    required this.offerIndex,
    required List<List<Piece?>> cells,
    required this.turnsUsed,
    required this.score,
    required this.offerConsumption,
  }) : cells = List<List<Piece?>>.unmodifiable([
         for (final row in cells) List<Piece?>.unmodifiable(row),
       ]);

  final GameState before;
  final Piece placedPiece;
  final Coordinate landing;
  final int offerIndex;
  final List<List<Piece?>> cells;
  final int turnsUsed;
  final int score;
  final OfferConsumption offerConsumption;

  /// Absolute turns after this placement, identical to [turnsUsed].
  int get absoluteTurnsUsed => turnsUsed;
}

(int, int) _delta(Direction direction) {
  switch (direction) {
    case Direction.up:
      return (-1, 0);
    case Direction.down:
      return (1, 0);
    case Direction.left:
      return (0, -1);
    case Direction.right:
      return (0, 1);
  }
}

bool _inBounds(int boardSize, int row, int column) {
  return row >= 0 && column >= 0 && row < boardSize && column < boardSize;
}

Set<String> _blockedKeys(List<Coordinate> blocked) {
  return {for (final cell in blocked) '${cell.row},${cell.column}'};
}

Coordinate landingCoordinate({
  required GameState state,
  required Piece piece,
  required Coordinate tap,
}) {
  final obstacles = _blockedKeys(state.blocked);
  final delta = _delta(piece.direction);
  final forwardRow = tap.row + delta.$1;
  final forwardColumn = tap.column + delta.$2;
  if (_inBounds(state.boardSize, forwardRow, forwardColumn) &&
      !obstacles.contains('$forwardRow,$forwardColumn') &&
      state.cells[forwardRow][forwardColumn] == null) {
    return Coordinate._(forwardRow, forwardColumn);
  }
  return Coordinate._(tap.row, tap.column);
}

List<List<Piece?>> _withPiece(
  List<List<Piece?>> cells,
  Coordinate landing,
  Piece piece,
) {
  return [
    for (var row = 0; row < cells.length; row++)
      [
        for (var column = 0; column < cells[row].length; column++)
          row == landing.row && column == landing.column
              ? piece
              : cells[row][column],
      ],
  ];
}

/// Applies directional placement and one-turn consumption.
///
/// Does not match, clear, shift, cascade, score, or decide terminal offers.
/// Does not set `ended` because a later clear may reopen the board.
///
/// An out-of-bounds tap is stopped as [PlacementSafety.tapOutOfBounds] before
/// any gameplay rejection, including when the game has already ended. That is
/// an internal safety stop for an unspecified contract case, not a new
/// transport-level error precedence.
PlacementResult applyPlacement(GameState state, Move move) {
  final tap = move.tap;
  if (!_inBounds(state.boardSize, tap.row, tap.column)) {
    return PlacementUnsafe(
      reason: PlacementSafety.tapOutOfBounds,
      state: state,
    );
  }

  if (state.status != GameStatus.inProgress) {
    return PlacementRejected(code: GameplayRejection.gameEnded, state: state);
  }

  final obstacles = _blockedKeys(state.blocked);
  final key = '${tap.row},${tap.column}';
  if (obstacles.contains(key)) {
    return PlacementRejected(code: GameplayRejection.blockedTap, state: state);
  }
  if (state.cells[tap.row][tap.column] != null) {
    return PlacementRejected(code: GameplayRejection.occupiedTap, state: state);
  }

  final slot = state.offers[move.offerIndex];
  final selected = slot.pieceOrNull;
  if (!slot.isSelectable || selected == null) {
    return PlacementUnsafe(
      reason: PlacementSafety.offerUnavailable,
      state: state,
    );
  }

  final land = landingCoordinate(state: state, piece: selected, tap: tap);
  final placed = _withPiece(state.cells, land, selected);
  final OfferConsumption consumption;
  if (state.futurePieces.isEmpty) {
    consumption = OfferReplacementDeferred(offerIndex: move.offerIndex);
  } else {
    consumption = OfferWillReplace(
      offerIndex: move.offerIndex,
      replacement: state.futurePieces.first,
      remainingFuture: List<Piece>.unmodifiable(state.futurePieces.skip(1)),
    );
  }

  late final int nextTurns;
  if (state.rulesVersion == RulesVersion.core001V3) {
    var overflow = false;
    nextTurns = checkedNonNegAdd(
      state.turnsUsed,
      1,
      onOverflow: () => overflow = true,
    );
    if (overflow) {
      return PlacementUnsafe(
        reason: PlacementSafety.integerOverflow,
        state: state,
      );
    }
  } else {
    nextTurns = state.turnsUsed + 1;
  }

  return PlacementApplied(
    before: state,
    placedPiece: selected,
    landing: land,
    offerIndex: move.offerIndex,
    cells: placed,
    turnsUsed: nextTurns,
    score: state.score,
    offerConsumption: consumption,
  );
}

/// Status-agnostic placement geometry probe (ADR-E01 §5.1).
///
/// Does not trust [GameState.status]. Reuses PZD-18 empty/unblocked tap rules.
bool canPlaceAt({
  required int boardSize,
  required List<List<Piece?>> cells,
  required List<Coordinate> blocked,
  required Piece piece,
  required Coordinate tap,
}) {
  if (!_inBounds(boardSize, tap.row, tap.column)) return false;
  final obstacles = _blockedKeys(blocked);
  final key = '${tap.row},${tap.column}';
  if (obstacles.contains(key)) return false;
  if (cells[tap.row][tap.column] != null) return false;
  // Direction affects landing only; acceptance matches applyPlacement.
  return true;
}

bool hasLegalPlacement(GameState state) {
  for (var offerIndex = 0; offerIndex < state.offers.length; offerIndex++) {
    final slot = state.offers[offerIndex];
    final piece = slot.pieceOrNull;
    if (!slot.isSelectable || piece == null) continue;
    for (var row = 0; row < state.boardSize; row++) {
      for (var column = 0; column < state.boardSize; column++) {
        final tap = Coordinate._(row, column);
        if (canPlaceAt(
          boardSize: state.boardSize,
          cells: state.cells,
          blocked: state.blocked,
          piece: piece,
          tap: tap,
        )) {
          return true;
        }
      }
    }
  }
  return false;
}

bool hasLegalMove(GameState state) {
  return state.status == GameStatus.inProgress &&
      state.turnsUsed < state.moveLimit &&
      hasLegalPlacement(state);
}

({GameStatus status, TerminalReason? reason}) deriveTerminalExpectation({
  required int turnsUsed,
  required int moveLimit,
  required GameState candidate,
}) {
  if (turnsUsed >= moveLimit) {
    return (status: GameStatus.ended, reason: TerminalReason.moveLimitReached);
  }
  if (!hasLegalPlacement(candidate)) {
    return (status: GameStatus.ended, reason: TerminalReason.noLegalMoves);
  }
  return (status: GameStatus.inProgress, reason: null);
}
