part of '../puzzle_duel_rules.dart';

/// A piece that changed cells during one simultaneous shift.
final class MovedPiece {
  const MovedPiece({
    required this.sourceIndex,
    required this.from,
    required this.to,
    required this.shape,
    required this.direction,
  });

  /// Row-major index of [from] on the pre-shift board: `row * boardSize + column`.
  final int sourceIndex;
  final Coordinate from;
  final Coordinate to;
  final Shape shape;
  final Direction direction;

  Map<String, Object?> toJson() => {
    'sourceIndex': sourceIndex,
    'from': from.toJson(),
    'to': to.toJson(),
    'shape': shape.wire,
    'direction': direction.wire,
  };

  @override
  bool operator ==(Object other) {
    return other is MovedPiece &&
        other.sourceIndex == sourceIndex &&
        other.from == from &&
        other.to == to &&
        other.shape == shape &&
        other.direction == direction;
  }

  @override
  int get hashCode => Object.hash(sourceIndex, from, to, shape, direction);
}

/// Result of one match scan and simultaneous clear. Does not shift survivors.
final class MatchClearResult {
  MatchClearResult({
    required List<List<Piece?>> before,
    required List<Coordinate> cleared,
    required List<List<Piece?>> cells,
  }) : before = _freezeCells(before),
       cleared = List<Coordinate>.unmodifiable(cleared),
       cells = _freezeCells(cells);

  final List<List<Piece?>> before;
  final List<Coordinate> cleared;
  final List<List<Piece?>> cells;

  int get uniqueClearedCount => cleared.length;

  bool get foundMatch => cleared.isNotEmpty;
}

/// Result of one simultaneous one-cell shift on a pre-shift board snapshot.
final class ShiftResult {
  ShiftResult({
    required List<List<Piece?>> before,
    required List<List<Piece?>> cells,
    required List<MovedPiece> moved,
  }) : before = _freezeCells(before),
       cells = _freezeCells(cells),
       moved = List<MovedPiece>.unmodifiable(moved);

  final List<List<Piece?>> before;
  final List<List<Piece?>> cells;
  final List<MovedPiece> moved;
}

/// One wave after placement: match/clear, then one shift only when a clear ran.
///
/// Does not rematch, score, replace offers, or decide game end.
final class SingleWaveResult {
  const SingleWaveResult({
    required this.placement,
    required this.match,
    required this.shift,
  });

  final PlacementApplied placement;
  final MatchClearResult match;

  /// Null when [match] found no clear. Zero matches must not move survivors.
  final ShiftResult? shift;
}

/// Unique matching cells in ascending row-major order.
///
/// Shape identity only. Direction is ignored. Diagonals are not scanned.
List<Coordinate> findMatches(List<List<Piece?>> cells) {
  final size = cells.length;
  for (final row in cells) {
    if (row.length != size) {
      throw StateError('match scan requires a square board');
    }
  }
  final found = <String>{};
  final ordered = <Coordinate>[];

  void add(int row, int column) {
    final key = '$row,$column';
    if (found.add(key)) {
      ordered.add(Coordinate._(row, column));
    }
  }

  for (var row = 0; row < size; row++) {
    var column = 0;
    while (column < size) {
      final piece = cells[row][column];
      if (piece == null) {
        column += 1;
        continue;
      }
      var end = column + 1;
      while (end < size) {
        final next = cells[row][end];
        if (next == null || next.shape != piece.shape) break;
        end += 1;
      }
      if (end - column >= 3) {
        for (var index = column; index < end; index++) {
          add(row, index);
        }
      }
      column = end;
    }
  }

  for (var column = 0; column < size; column++) {
    var row = 0;
    while (row < size) {
      final piece = cells[row][column];
      if (piece == null) {
        row += 1;
        continue;
      }
      var end = row + 1;
      while (end < size) {
        final next = cells[end][column];
        if (next == null || next.shape != piece.shape) break;
        end += 1;
      }
      if (end - row >= 3) {
        for (var index = row; index < end; index++) {
          add(index, column);
        }
      }
      row = end;
    }
  }

  ordered.sort((left, right) {
    final byRow = left.row.compareTo(right.row);
    return byRow != 0 ? byRow : left.column.compareTo(right.column);
  });
  return List<Coordinate>.unmodifiable(ordered);
}

/// Clears every unique match cell at once. Does not shift survivors.
MatchClearResult clearMatches(List<List<Piece?>> cells) {
  final before = [
    for (final row in cells) [for (final cell in row) cell],
  ];
  final cleared = findMatches(before);
  if (cleared.isEmpty) {
    return MatchClearResult(before: before, cleared: cleared, cells: before);
  }
  final after = [
    for (final row in before) [for (final cell in row) cell],
  ];
  for (final cell in cleared) {
    if (cell.row < 0 ||
        cell.column < 0 ||
        cell.row >= after.length ||
        cell.column >= after[cell.row].length) {
      throw StateError('match clear coordinate is outside the board');
    }
    if (after[cell.row][cell.column] == null) {
      throw StateError('match clear tried to clear an empty cell twice');
    }
    after[cell.row][cell.column] = null;
  }
  return MatchClearResult(before: before, cleared: cleared, cells: after);
}

/// One simultaneous one-cell shift using a single pre-shift occupancy snapshot.
ShiftResult applyShift(
  List<List<Piece?>> cells, {
  required List<Coordinate> blocked,
}) {
  final size = cells.length;
  for (final row in cells) {
    if (row.length != size) {
      throw StateError('shift requires a square board');
    }
  }
  final before = [
    for (final row in cells) [for (final cell in row) cell],
  ];
  final obstacles = _blockedKeys(blocked);
  final occupied = <String>{};
  final pieces = <({int row, int column, Piece piece, int sourceIndex})>[];
  for (var row = 0; row < size; row++) {
    for (var column = 0; column < size; column++) {
      final piece = before[row][column];
      if (piece == null) continue;
      occupied.add('$row,$column');
      pieces.add((
        row: row,
        column: column,
        piece: piece,
        sourceIndex: row * size + column,
      ));
    }
  }

  final proposals =
      <
        ({
          int row,
          int column,
          Piece piece,
          int sourceIndex,
          int targetRow,
          int targetColumn,
          bool ok,
        })
      >[];
  for (final item in pieces) {
    final delta = _delta(item.piece.direction);
    final targetRow = item.row + delta.$1;
    final targetColumn = item.column + delta.$2;
    final ok =
        _inBounds(size, targetRow, targetColumn) &&
        !obstacles.contains('$targetRow,$targetColumn') &&
        !occupied.contains('$targetRow,$targetColumn');
    proposals.add((
      row: item.row,
      column: item.column,
      piece: item.piece,
      sourceIndex: item.sourceIndex,
      targetRow: targetRow,
      targetColumn: targetColumn,
      ok: ok,
    ));
  }

  final claims = <String, int>{};
  for (final proposal in proposals) {
    if (!proposal.ok) continue;
    final key = '${proposal.targetRow},${proposal.targetColumn}';
    claims[key] = (claims[key] ?? 0) + 1;
  }

  final accepted = [
    for (final proposal in proposals)
      (
        row: proposal.row,
        column: proposal.column,
        piece: proposal.piece,
        sourceIndex: proposal.sourceIndex,
        targetRow: proposal.targetRow,
        targetColumn: proposal.targetColumn,
        ok:
            proposal.ok &&
            (claims['${proposal.targetRow},${proposal.targetColumn}'] ?? 0) ==
                1,
      ),
  ];

  final after = [
    for (final row in before) [for (final cell in row) cell],
  ];
  for (final proposal in accepted) {
    if (proposal.ok) {
      after[proposal.row][proposal.column] = null;
    }
  }
  final moved = <MovedPiece>[];
  for (final proposal in accepted) {
    if (!proposal.ok) continue;
    if (after[proposal.targetRow][proposal.targetColumn] != null) {
      throw StateError('shift destination overwrite');
    }
    after[proposal.targetRow][proposal.targetColumn] = proposal.piece;
    moved.add(
      MovedPiece(
        sourceIndex: proposal.sourceIndex,
        from: Coordinate._(proposal.row, proposal.column),
        to: Coordinate._(proposal.targetRow, proposal.targetColumn),
        shape: proposal.piece.shape,
        direction: proposal.piece.direction,
      ),
    );
  }
  moved.sort((left, right) => left.sourceIndex.compareTo(right.sourceIndex));
  return ShiftResult(before: before, cells: after, moved: moved);
}

/// After a successful placement: clear matches once, then shift only if cleared.
SingleWaveResult resolveAfterPlacement(PlacementApplied placement) {
  final match = clearMatches(placement.cells);
  if (!match.foundMatch) {
    return SingleWaveResult(placement: placement, match: match, shift: null);
  }
  final shift = applyShift(match.cells, blocked: placement.before.blocked);
  return SingleWaveResult(placement: placement, match: match, shift: shift);
}
