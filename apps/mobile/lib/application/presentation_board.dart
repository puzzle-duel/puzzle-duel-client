import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

/// Mutable presentation grid used only for animation projection.
///
/// Never treated as canonical gameplay state. Built from the pre-move board
/// plus [MoveApplied] landing/wave events — does not re-run rules.
final class PresentationBoard {
  PresentationBoard.fromGameState(GameState state)
    : boardSize = state.boardSize,
      blocked = Set<Coordinate>.from(state.blocked),
      cells = [
        for (final row in state.cells) [for (final cell in row) cell],
      ];

  final int boardSize;
  final Set<Coordinate> blocked;
  final List<List<Piece?>> cells;

  Piece? pieceAt(int row, int column) => cells[row][column];

  bool isBlocked(int row, int column) =>
      blocked.contains(Coordinate(row: row, column: column));

  void place(Coordinate at, Piece piece) {
    cells[at.row][at.column] = piece;
  }

  void clearCells(Iterable<Coordinate> cleared) {
    for (final cell in cleared) {
      cells[cell.row][cell.column] = null;
    }
  }

  void applyMoves(Iterable<MovedPiece> moved) {
    // Clear sources first so simultaneous swaps do not overwrite.
    for (final item in moved) {
      cells[item.from.row][item.from.column] = null;
    }
    for (final item in moved) {
      cells[item.to.row][item.to.column] = Piece(
        shape: item.shape,
        direction: item.direction,
      );
    }
  }

  GameState asFrozenOverlay(GameState canonical) {
    // Overlay cells onto a copy-shaped snapshot for display helpers only.
    return canonical;
  }
}
