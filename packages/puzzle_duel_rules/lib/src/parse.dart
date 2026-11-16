part of '../puzzle_duel_rules.dart';

const _stateKeysV1V2 = {
  'rulesVersion',
  'boardSize',
  'moveLimit',
  'blocked',
  'cells',
  'offers',
  'futurePieces',
  'turnsUsed',
  'score',
  'status',
};

const _stateKeysV3 = {
  'rulesVersion',
  'boardSize',
  'moveLimit',
  'blocked',
  'cells',
  'offers',
  'futurePieces',
  'turnsUsed',
  'score',
  'status',
  'terminalReason',
};

const _boardKeys = {'rulesVersion', 'boardSize', 'blocked', 'cells', 'wave'};

const _pieceKeys = {'shape', 'direction'};

const _moveKeys = {'offerIndex', 'tap'};

final class _Issues {
  final List<ValidationCode> codes = [];

  void add(ValidationCode code) {
    if (!codes.contains(code)) codes.add(code);
  }

  bool get isEmpty => codes.isEmpty;

  void throwIfNeeded() {
    if (codes.isNotEmpty) throw ValidationFailure(codes);
  }
}

Map<String, Object?>? _map(Object? value) {
  if (value is! Map) return null;
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) return null;
    result[key] = entry.value;
  }
  return result;
}

void _closed(Map<String, Object?> json, Set<String> allowed, _Issues issues) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) issues.add(ValidationCode.unexpectedProperty);
  }
  for (final key in allowed) {
    if (key == 'wave') continue;
    if (!json.containsKey(key)) issues.add(ValidationCode.missingField);
  }
}

int? _int(Object? value) => value is int ? value : null;

Piece? _piece(Object? value, _Issues issues) {
  if (value == null) {
    issues.add(ValidationCode.malformedPiece);
    return null;
  }
  final json = _map(value);
  if (json == null) {
    issues.add(ValidationCode.malformedPiece);
    return null;
  }
  final local = _Issues();
  _closed(json, _pieceKeys, local);
  final shape = Shape.tryParse(json['shape']);
  final direction = Direction.tryParse(json['direction']);
  if (shape == null) local.add(ValidationCode.malformedShape);
  if (direction == null) local.add(ValidationCode.malformedDirection);
  for (final code in local.codes) {
    issues.add(code);
  }
  if (shape == null || direction == null || local.codes.isNotEmpty) {
    return null;
  }
  return Piece(shape: shape, direction: direction);
}

/// Parses one piece. A null slot is [ValidationCode.malformedPiece].
Piece parsePiece(Object? json) {
  final issues = _Issues();
  final piece = _piece(json, issues);
  issues.throwIfNeeded();
  return piece!;
}

Coordinate? _coordinate(Object? value, _Issues issues, ValidationCode code) {
  if (value is! List || value.length != 2) {
    issues.add(code);
    return null;
  }
  final row = _int(value[0]);
  final column = _int(value[1]);
  if (row == null || column == null || row < 0 || column < 0) {
    issues.add(code);
    return null;
  }
  return Coordinate._(row, column);
}

Coordinate parseCoordinate(Object? json) {
  final issues = _Issues();
  final coordinate = _coordinate(
    json,
    issues,
    ValidationCode.malformedCoordinate,
  );
  issues.throwIfNeeded();
  return coordinate!;
}

final class _Grid {
  _Grid(this.rows, this.rawOccupied);

  final List<List<Piece?>>? rows;
  final List<List<bool>>? rawOccupied;
}

_Grid _cells(Object? value, int? boardSize, _Issues issues) {
  if (boardSize == null || value is! List || value.length != boardSize) {
    issues.add(ValidationCode.malformedBoard);
    return _Grid(null, null);
  }
  final rows = <List<Piece?>>[];
  final occupied = <List<bool>>[];
  var ok = true;
  for (final rawRow in value) {
    if (rawRow is! List || rawRow.length != boardSize) {
      issues.add(ValidationCode.malformedBoard);
      ok = false;
      continue;
    }
    final row = <Piece?>[];
    final flags = <bool>[];
    for (final rawCell in rawRow) {
      flags.add(rawCell != null);
      if (rawCell == null) {
        row.add(null);
        continue;
      }
      final before = issues.codes.length;
      final piece = _piece(rawCell, issues);
      if (piece == null || issues.codes.length != before) {
        ok = false;
        row.add(null);
      } else {
        row.add(piece);
      }
    }
    rows.add(row);
    occupied.add(flags);
  }
  if (!ok || rows.length != boardSize) return _Grid(null, occupied);
  return _Grid(rows, occupied);
}

List<Coordinate> _blocked(
  Object? value,
  int? boardSize,
  List<List<bool>>? occupied,
  _Issues issues,
) {
  if (value is! List) {
    issues.add(ValidationCode.malformedBoard);
    return const [];
  }
  final parsed = <Coordinate>[];
  final seen = <String>{};
  for (final raw in value) {
    final coordinate = _coordinate(
      raw,
      issues,
      ValidationCode.blockedOutOfRange,
    );
    if (coordinate == null) continue;
    final key = '${coordinate.row},${coordinate.column}';
    if (!seen.add(key)) issues.add(ValidationCode.duplicateBlocked);
    if (boardSize == null ||
        coordinate.row >= boardSize ||
        coordinate.column >= boardSize) {
      issues.add(ValidationCode.blockedOutOfRange);
    } else if (occupied != null &&
        coordinate.row < occupied.length &&
        coordinate.column < occupied[coordinate.row].length &&
        occupied[coordinate.row][coordinate.column]) {
      issues.add(ValidationCode.blockedCellOccupied);
    }
    parsed.add(coordinate);
  }
  for (var index = 1; index < parsed.length; index++) {
    final previous = parsed[index - 1];
    final current = parsed[index];
    final ordered =
        current.row > previous.row ||
        (current.row == previous.row && current.column > previous.column);
    if (!ordered) {
      issues.add(ValidationCode.blockedNotRowMajor);
      break;
    }
  }
  return parsed;
}

final class _Offers {
  _Offers(this.slots, this.nulls, this.spent, this.ok);

  final List<OfferSlot> slots;
  final int nulls;
  final int spent;
  final bool ok;
}

_Offers _offers(Object? value, RulesVersion? rules, _Issues issues) {
  if (value is! List || value.length != 3) {
    issues.add(ValidationCode.malformedOffers);
    return _Offers(const [], 0, 0, false);
  }
  final slots = <OfferSlot>[];
  var nulls = 0;
  var spent = 0;
  var ok = true;
  for (final raw in value) {
    if (rules == RulesVersion.core001V3) {
      if (raw == null) {
        issues.add(ValidationCode.nullOffer);
        ok = false;
        slots.add(const OfferSpent());
        continue;
      }
      final json = _map(raw);
      if (json == null) {
        issues.add(ValidationCode.malformedOfferSlot);
        ok = false;
        slots.add(const OfferSpent());
        continue;
      }
      final kind = json['kind'];
      if (kind == 'spent') {
        final local = _Issues();
        _closed(json, {'kind'}, local);
        for (final code in local.codes) {
          issues.add(code);
        }
        if (local.codes.isNotEmpty) ok = false;
        spent += 1;
        slots.add(const OfferSpent());
        continue;
      }
      if (kind == 'piece') {
        final local = _Issues();
        _closed(json, {'kind', 'shape', 'direction'}, local);
        final shape = Shape.tryParse(json['shape']);
        final direction = Direction.tryParse(json['direction']);
        if (shape == null) local.add(ValidationCode.malformedShape);
        if (direction == null) local.add(ValidationCode.malformedDirection);
        for (final code in local.codes) {
          issues.add(code);
        }
        if (shape == null || direction == null || local.codes.isNotEmpty) {
          ok = false;
          slots.add(const OfferSpent());
        } else {
          slots.add(OfferLive(Piece(shape: shape, direction: direction)));
        }
        continue;
      }
      issues.add(ValidationCode.malformedOfferSlot);
      ok = false;
      slots.add(const OfferSpent());
      continue;
    }

    // v1 / v2
    if (raw == null) {
      nulls += 1;
      slots.add(const OfferEmpty());
      if (rules != RulesVersion.core001V2) {
        issues.add(ValidationCode.nullOffer);
        ok = false;
      }
      continue;
    }
    // Reject tagged v3 objects on historical versions.
    if (raw is Map && raw.containsKey('kind')) {
      issues.add(ValidationCode.malformedOffers);
      ok = false;
      slots.add(const OfferEmpty());
      continue;
    }
    final before = issues.codes.length;
    final piece = _piece(raw, issues);
    if (piece == null || issues.codes.length != before) {
      ok = false;
      slots.add(const OfferEmpty());
    } else {
      slots.add(OfferLive(piece));
    }
  }
  return _Offers(slots, nulls, spent, ok);
}

List<Piece>? _future(Object? value, _Issues issues) {
  if (value is! List) {
    issues.add(ValidationCode.malformedOffers);
    return null;
  }
  final pieces = <Piece>[];
  var ok = true;
  for (final raw in value) {
    final before = issues.codes.length;
    final piece = _piece(raw, issues);
    if (piece == null || issues.codes.length != before) {
      ok = false;
    } else {
      pieces.add(piece);
    }
  }
  return ok ? pieces : null;
}

void _terminalOffers({
  required _Offers offers,
  required RulesVersion? rules,
  required GameStatus? status,
  required bool turnsOk,
  required int? turnsUsed,
  required int? moveLimit,
  required List<Piece>? futurePieces,
  required _Issues issues,
}) {
  if (rules != RulesVersion.core001V2 || !offers.ok && offers.nulls == 0) {
    return;
  }
  if (!offers.ok && offers.slots.isEmpty) return;
  final nulls = offers.nulls;
  if (status == GameStatus.inProgress && nulls > 0) {
    issues.add(ValidationCode.nullOfferWhileActive);
  }
  if (nulls > 1) issues.add(ValidationCode.multipleNullOffers);
  if (nulls != 1 || status == GameStatus.inProgress) return;
  final terminal =
      status == GameStatus.ended &&
      turnsOk &&
      turnsUsed != null &&
      moveLimit != null &&
      turnsUsed >= moveLimit &&
      futurePieces != null &&
      futurePieces.isEmpty;
  if (!terminal) issues.add(ValidationCode.nullOfferNotTerminal);
}

BoardGeometry parseBoard(Object? json) {
  final issues = _Issues();
  final object = _map(json);
  if (object == null) {
    throw ValidationFailure([ValidationCode.malformedBoard]);
  }
  _closed(object, _boardKeys, issues);
  final rules = RulesVersion.tryParse(object['rulesVersion']);
  if (object.containsKey('rulesVersion') && rules == null) {
    issues.add(ValidationCode.unknownRulesVersion);
  }
  final boardSize = _int(object['boardSize']);
  if (object.containsKey('boardSize') && (boardSize == null || boardSize < 1)) {
    issues.add(ValidationCode.malformedBoard);
  }
  final grid = _cells(
    object['cells'],
    boardSize != null && boardSize >= 1 ? boardSize : null,
    issues,
  );
  final blocked = _blocked(
    object['blocked'],
    boardSize != null && boardSize >= 1 ? boardSize : null,
    grid.rawOccupied,
    issues,
  );
  int? wave;
  if (object.containsKey('wave')) {
    wave = _int(object['wave']);
    if (wave == null || wave < 1) issues.add(ValidationCode.malformedBoard);
  }
  issues.throwIfNeeded();
  return BoardGeometry._(
    rulesVersion: rules!,
    boardSize: boardSize!,
    blocked: blocked,
    cells: grid.rows!,
    wave: wave,
  );
}

GameState _state(Object? json, {required bool initial}) {
  final issues = _Issues();
  final object = _map(json);
  if (object == null) {
    throw ValidationFailure([ValidationCode.malformedBoard]);
  }
  final rulesHint = RulesVersion.tryParse(object['rulesVersion']);
  final allowedKeys = rulesHint == RulesVersion.core001V3
      ? _stateKeysV3
      : _stateKeysV1V2;
  _closed(object, allowedKeys, issues);
  final rules = rulesHint;
  if (object.containsKey('rulesVersion') && rules == null) {
    issues.add(ValidationCode.unknownRulesVersion);
  }
  final boardSize = _int(object['boardSize']);
  final usableSize = boardSize != null && boardSize >= 1 ? boardSize : null;
  if (object.containsKey('boardSize') && usableSize == null) {
    issues.add(ValidationCode.malformedBoard);
  }
  final moveLimit = _int(object['moveLimit']);
  final turnsUsed = _int(object['turnsUsed']);
  final turnsOk =
      moveLimit != null &&
      turnsUsed != null &&
      moveLimit >= 1 &&
      turnsUsed >= 0 &&
      turnsUsed <= moveLimit;
  if (object.containsKey('moveLimit') &&
      object.containsKey('turnsUsed') &&
      !turnsOk) {
    issues.add(ValidationCode.illegalTurnCount);
  }
  if (rules == RulesVersion.core001V3) {
    if ((moveLimit != null && !isJsonSafeNonNegativeInt(moveLimit)) ||
        (turnsUsed != null && !isJsonSafeNonNegativeInt(turnsUsed))) {
      issues.add(ValidationCode.integerOutOfRange);
    }
  }
  final grid = _cells(object['cells'], usableSize, issues);
  final blocked = _blocked(
    object['blocked'],
    usableSize,
    grid.rawOccupied,
    issues,
  );
  final offers = _offers(object['offers'], rules, issues);
  final futurePieces = _future(object['futurePieces'], issues);
  final score = _int(object['score']);
  if (object.containsKey('score') && (score == null || score < 0)) {
    issues.add(ValidationCode.malformedScore);
  }
  if (rules == RulesVersion.core001V3 &&
      score != null &&
      !isJsonSafeNonNegativeInt(score)) {
    issues.add(ValidationCode.integerOutOfRange);
  }
  final status = GameStatus.tryParse(object['status']);
  if (object.containsKey('status') && status == null) {
    issues.add(ValidationCode.inconsistentStatus);
  }

  TerminalReason? terminalReason;
  if (rules == RulesVersion.core001V3) {
    final rawReason = object['terminalReason'];
    if (rawReason == null) {
      terminalReason = null;
    } else {
      terminalReason = TerminalReason.tryParse(rawReason);
      if (terminalReason == null) {
        issues.add(ValidationCode.inconsistentTerminalReason);
      }
    }
    if (offers.spent > 0 && futurePieces != null && futurePieces.isNotEmpty) {
      issues.add(ValidationCode.spentWithFuturePieces);
    }
  } else if (object.containsKey('terminalReason')) {
    issues.add(ValidationCode.unexpectedProperty);
  }

  _terminalOffers(
    offers: offers,
    rules: rules,
    status: status,
    turnsOk: turnsOk,
    turnsUsed: turnsUsed,
    moveLimit: moveLimit,
    futurePieces: futurePieces,
    issues: issues,
  );

  GameState? candidate;
  if (rules != null &&
      usableSize != null &&
      moveLimit != null &&
      turnsUsed != null &&
      score != null &&
      status != null &&
      grid.rows != null &&
      futurePieces != null &&
      offers.slots.length == 3) {
    candidate = GameState._(
      rulesVersion: rules,
      boardSize: usableSize,
      moveLimit: moveLimit,
      blocked: blocked,
      cells: grid.rows!,
      offers: offers.slots,
      futurePieces: futurePieces,
      turnsUsed: turnsUsed,
      score: score,
      status: status,
      terminalReason: rules == RulesVersion.core001V3 ? terminalReason : null,
    );
  }

  if (candidate != null && turnsOk) {
    final used = candidate.turnsUsed;
    final limit = candidate.moveLimit;
    if (rules == RulesVersion.core001V3) {
      final expected = deriveTerminalExpectation(
        turnsUsed: used,
        moveLimit: limit,
        candidate: candidate,
      );
      if (status != expected.status || terminalReason != expected.reason) {
        issues.add(ValidationCode.inconsistentStatus);
        if (terminalReason != expected.reason) {
          issues.add(ValidationCode.inconsistentTerminalReason);
        }
      }
    } else {
      final ended = used >= limit || _emptyPlayable(grid.rows!, blocked) == 0;
      final actual = ended ? GameStatus.ended : GameStatus.inProgress;
      if (status != actual) issues.add(ValidationCode.inconsistentStatus);
    }
  }

  if (initial && grid.rows != null && _orthogonalRun(grid.rows!)) {
    issues.add(ValidationCode.unresolvedInitialMatch);
  }
  if (initial && rules == RulesVersion.core001V3 && candidate != null) {
    if (candidate.turnsUsed != 0 ||
        candidate.score != 0 ||
        candidate.status != GameStatus.inProgress ||
        candidate.terminalReason != null ||
        candidate.offers.any((slot) => slot is! OfferLive)) {
      issues.add(ValidationCode.inconsistentStatus);
    }
    if (!hasLegalPlacement(candidate)) {
      issues.add(ValidationCode.noLegalInitialPlacement);
    }
  }

  issues.throwIfNeeded();
  return candidate!;
}

int _emptyPlayable(List<List<Piece?>> cells, List<Coordinate> blocked) {
  final obstacles = <String>{
    for (final cell in blocked) '${cell.row},${cell.column}',
  };
  var count = 0;
  for (var row = 0; row < cells.length; row++) {
    for (var column = 0; column < cells[row].length; column++) {
      if (cells[row][column] == null && !obstacles.contains('$row,$column')) {
        count += 1;
      }
    }
  }
  return count;
}

/// Structural state. An existing match is kept.
GameState parseGameState(Object? json) => _state(json, initial: false);

/// Full-move start. Rejects an orthogonal run that is already on the board.
GameState parseInitialGameState(Object? json) => _state(json, initial: true);

Move parseMove(Object? json) {
  final issues = _Issues();
  final object = _map(json);
  if (object == null) {
    throw ValidationFailure([ValidationCode.malformedMove]);
  }
  _closed(object, _moveKeys, issues);
  final index = _int(object['offerIndex']);
  if (object.containsKey('offerIndex') &&
      (index == null || index < 0 || index > 2)) {
    issues.add(ValidationCode.illegalOfferIndex);
  }
  final tap = _coordinate(
    object['tap'],
    issues,
    ValidationCode.malformedCoordinate,
  );
  issues.throwIfNeeded();
  return Move(offerIndex: index!, tap: tap!);
}
