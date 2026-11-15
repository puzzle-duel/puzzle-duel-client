part of '../puzzle_duel_rules.dart';

enum RulesVersion {
  core001V1('core-001.v1'),
  core001V2('core-001.v2');

  const RulesVersion(this.id);

  final String id;

  static RulesVersion? tryParse(Object? value) {
    for (final version in values) {
      if (version.id == value) return version;
    }
    return null;
  }
}

enum Shape {
  circle('circle'),
  diamond('diamond'),
  triangle('triangle');

  const Shape(this.wire);

  final String wire;

  static Shape? tryParse(Object? value) {
    for (final shape in values) {
      if (shape.wire == value) return shape;
    }
    return null;
  }
}

enum Direction {
  up('up'),
  right('right'),
  down('down'),
  left('left');

  const Direction(this.wire);

  final String wire;

  static Direction? tryParse(Object? value) {
    for (final direction in values) {
      if (direction.wire == value) return direction;
    }
    return null;
  }
}

enum GameStatus {
  inProgress('in_progress'),
  ended('ended');

  const GameStatus(this.wire);

  final String wire;

  static GameStatus? tryParse(Object? value) {
    for (final status in values) {
      if (status.wire == value) return status;
    }
    return null;
  }
}

/// Zero-based `[row, column]`. Row 0 is the top row.
final class Coordinate {
  const Coordinate._(this.row, this.column);

  final int row;
  final int column;

  /// Rejects a negative component. This does not decide an out-of-bounds tap.
  factory Coordinate({required int row, required int column}) {
    if (row < 0 || column < 0) {
      throw ValidationFailure([ValidationCode.malformedCoordinate]);
    }
    return Coordinate._(row, column);
  }

  List<int> toJson() => [row, column];

  @override
  bool operator ==(Object other) =>
      other is Coordinate && other.row == row && other.column == column;

  @override
  int get hashCode => Object.hash(row, column);

  @override
  String toString() => '[$row, $column]';
}

final class Piece {
  const Piece({required this.shape, required this.direction});

  final Shape shape;
  final Direction direction;

  Map<String, String> toJson() => {
    'shape': shape.wire,
    'direction': direction.wire,
  };

  @override
  bool operator ==(Object other) =>
      other is Piece && other.shape == shape && other.direction == direction;

  @override
  int get hashCode => Object.hash(shape, direction);

  @override
  String toString() => '${shape.wire}/${direction.wire}';
}

/// A requested offer and tap. Parsing this does not play the move.
final class Move {
  Move({required int offerIndex, required this.tap})
    : offerIndex = _checkedIndex(offerIndex);

  final int offerIndex;
  final Coordinate tap;

  static int _checkedIndex(int offerIndex) {
    if (offerIndex != 0 && offerIndex != 1 && offerIndex != 2) {
      throw ValidationFailure([ValidationCode.illegalOfferIndex]);
    }
    return offerIndex;
  }

  Map<String, Object?> toJson() => {
    'offerIndex': offerIndex,
    'tap': tap.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is Move && other.offerIndex == offerIndex && other.tap == tap;

  @override
  int get hashCode => Object.hash(offerIndex, tap);
}

/// Cells and obstacles without offers, turns, or score.
///
/// Match-phase and shift-phase fixtures use this shape. An existing orthogonal
/// run is retained; this type does not clear it.
final class BoardGeometry {
  BoardGeometry._({
    required this.rulesVersion,
    required this.boardSize,
    required List<Coordinate> blocked,
    required List<List<Piece?>> cells,
    required this.wave,
  }) : blocked = List<Coordinate>.unmodifiable(blocked),
       cells = _freezeCells(cells);

  final RulesVersion rulesVersion;
  final int boardSize;
  final List<Coordinate> blocked;
  final List<List<Piece?>> cells;
  final int? wave;

  bool get hasOrthogonalRun => _orthogonalRun(cells);

  @override
  bool operator ==(Object other) {
    return other is BoardGeometry &&
        other.rulesVersion == rulesVersion &&
        other.boardSize == boardSize &&
        other.wave == wave &&
        _sameCoordinates(other.blocked, blocked) &&
        _sameCells(other.cells, cells);
  }

  @override
  int get hashCode => Object.hash(
    rulesVersion,
    boardSize,
    wave,
    Object.hashAll(blocked),
    _cellsHash(cells),
  );
}

final class GameState {
  GameState._({
    required this.rulesVersion,
    required this.boardSize,
    required this.moveLimit,
    required List<Coordinate> blocked,
    required List<List<Piece?>> cells,
    required List<Piece?> offers,
    required List<Piece> futurePieces,
    required this.turnsUsed,
    required this.score,
    required this.status,
  }) : blocked = List<Coordinate>.unmodifiable(blocked),
       cells = _freezeCells(cells),
       offers = List<Piece?>.unmodifiable(offers),
       futurePieces = List<Piece>.unmodifiable(futurePieces);

  final RulesVersion rulesVersion;
  final int boardSize;
  final int moveLimit;
  final List<Coordinate> blocked;
  final List<List<Piece?>> cells;
  final List<Piece?> offers;
  final List<Piece> futurePieces;
  final int turnsUsed;
  final int score;
  final GameStatus status;

  bool get hasOrthogonalRun => _orthogonalRun(cells);

  Map<String, Object?> toJson() => {
    'rulesVersion': rulesVersion.id,
    'boardSize': boardSize,
    'moveLimit': moveLimit,
    'blocked': [for (final cell in blocked) cell.toJson()],
    'cells': [
      for (final row in cells) [for (final cell in row) cell?.toJson()],
    ],
    'offers': [for (final offer in offers) offer?.toJson()],
    'futurePieces': [for (final piece in futurePieces) piece.toJson()],
    'turnsUsed': turnsUsed,
    'score': score,
    'status': status.wire,
  };

  @override
  bool operator ==(Object other) {
    return other is GameState &&
        other.rulesVersion == rulesVersion &&
        other.boardSize == boardSize &&
        other.moveLimit == moveLimit &&
        other.turnsUsed == turnsUsed &&
        other.score == score &&
        other.status == status &&
        _sameCoordinates(other.blocked, blocked) &&
        _sameCells(other.cells, cells) &&
        _sameOffers(other.offers, offers) &&
        _samePieces(other.futurePieces, futurePieces);
  }

  @override
  int get hashCode => Object.hash(
    rulesVersion,
    boardSize,
    moveLimit,
    Object.hashAll(blocked),
    _cellsHash(cells),
    Object.hashAll(offers),
    Object.hashAll(futurePieces),
    turnsUsed,
    score,
    status,
  );
}

List<List<Piece?>> _freezeCells(List<List<Piece?>> cells) {
  return List<List<Piece?>>.unmodifiable([
    for (final row in cells) List<Piece?>.unmodifiable(row),
  ]);
}

bool _orthogonalRun(List<List<Piece?>> cells) {
  final size = cells.length;
  for (final row in cells) {
    if (row.length != size) return false;
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
      if (end - column >= 3) return true;
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
      if (end - row >= 3) return true;
      row = end;
    }
  }
  return false;
}

bool _sameCoordinates(List<Coordinate> left, List<Coordinate> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _samePieces(List<Piece> left, List<Piece> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _sameOffers(List<Piece?> left, List<Piece?> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _sameCells(List<List<Piece?>> left, List<List<Piece?>> right) {
  if (left.length != right.length) return false;
  for (var row = 0; row < left.length; row++) {
    if (left[row].length != right[row].length) return false;
    for (var column = 0; column < left[row].length; column++) {
      if (left[row][column] != right[row][column]) return false;
    }
  }
  return true;
}

int _cellsHash(List<List<Piece?>> cells) {
  return Object.hashAll([for (final row in cells) Object.hashAll(row)]);
}
