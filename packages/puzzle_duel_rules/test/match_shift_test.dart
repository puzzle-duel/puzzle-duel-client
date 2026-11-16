import 'dart:convert';
import 'dart:io';

import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';
import 'package:test/test.dart';

void main() {
  test('fixture 05 places, clears three circles, and shifts the survivor', () {
    final step = _fullMove('05-horizontal-match.json');
    final placement = applyPlacement(step.state, step.move) as PlacementApplied;
    expect(placement.landing, Coordinate(row: 2, column: 2));
    final wave = resolveAfterPlacement(placement);
    expect(wave.match.cleared.map((cell) => cell.toJson()).toList(), [
      [2, 0],
      [2, 1],
      [2, 2],
    ]);
    expect(wave.match.uniqueClearedCount, 3);
    expect(wave.shift, isNotNull);
    expect(wave.shift!.moved, [
      MovedPiece(
        sourceIndex: 0,
        from: Coordinate(row: 0, column: 0),
        to: Coordinate(row: 0, column: 1),
        shape: Shape.triangle,
        direction: Direction.right,
      ),
    ]);
    expect(wave.shift!.cells[0][0], isNull);
    expect(wave.shift!.cells[0][1]!.shape, Shape.triangle);
    expect(wave.placement.score, step.state.score);
    expect(wave.placement.offerConsumption, isA<OfferWillReplace>());
  });

  test('fixture 06 clears five unique cells and does not shift', () {
    final board = _phaseBoard('06-cross-union.json');
    final match = clearMatches(board.cells);
    expect(match.cleared.map((cell) => cell.toJson()).toList(), [
      [1, 2],
      [2, 1],
      [2, 2],
      [2, 3],
      [3, 2],
    ]);
    expect(match.uniqueClearedCount, 5);
    expect(match.cells, everyElement(everyElement(isNull)));
    final shift = applyShift(match.cells, blocked: board.blocked);
    expect(shift.moved, isEmpty);
  });

  test('fixture 07 contested destination keeps both pieces', () {
    final board = _phaseBoard('07-contested-shift.json');
    final shift = applyShift(board.cells, blocked: board.blocked);
    expect(shift.moved, isEmpty);
    expect(shift.cells, board.cells);
  });

  test('fixture 08 preoccupied destination blocks the follower', () {
    final board = _phaseBoard('08-preoccupied-shift.json');
    final shift = applyShift(board.cells, blocked: board.blocked);
    expect(shift.moved, [
      MovedPiece(
        sourceIndex: 12,
        from: Coordinate(row: 2, column: 2),
        to: Coordinate(row: 2, column: 3),
        shape: Shape.diamond,
        direction: Direction.right,
      ),
    ]);
    expect(shift.cells[2][1]!.shape, Shape.circle);
    expect(shift.cells[2][2], isNull);
    expect(shift.cells[2][3]!.shape, Shape.diamond);
  });

  test('fixture 09 out-of-bounds and blocked destinations stay put', () {
    final document = _fixture('09-blocked-shift.json');
    for (final raw in document['scenarios'] as List) {
      final scenario = raw as Map;
      final board = parseBoard(
        (scenario['given'] as Map).cast<String, Object?>(),
      );
      final shift = applyShift(board.cells, blocked: board.blocked);
      expect(shift.moved, isEmpty, reason: scenario['name'].toString());
      expect(shift.cells, board.cells);
    }
  });

  test('horizontal runs of three, four, and five clear once', () {
    expect(_horizontalRun(3).uniqueClearedCount, 3);
    expect(_horizontalRun(4).uniqueClearedCount, 4);
    expect(_horizontalRun(5).uniqueClearedCount, 5);
  });

  test('vertical matches and independent pairs clear together', () {
    final cells = _empty(5);
    cells[0][1] = _piece(Shape.circle, Direction.up);
    cells[1][1] = _piece(Shape.circle, Direction.down);
    cells[2][1] = _piece(Shape.circle, Direction.left);
    cells[4][0] = _piece(Shape.diamond, Direction.right);
    cells[4][1] = _piece(Shape.diamond, Direction.right);
    cells[4][2] = _piece(Shape.diamond, Direction.right);
    final match = clearMatches(cells);
    expect(match.cleared.map((cell) => cell.toJson()).toList(), [
      [0, 1],
      [1, 1],
      [2, 1],
      [4, 0],
      [4, 1],
      [4, 2],
    ]);
  });

  test('same shape with different directions still matches', () {
    final cells = _empty(5);
    cells[2][0] = _piece(Shape.triangle, Direction.up);
    cells[2][1] = _piece(Shape.triangle, Direction.right);
    cells[2][2] = _piece(Shape.triangle, Direction.down);
    final match = clearMatches(cells);
    expect(match.uniqueClearedCount, 3);
  });

  test('different shapes and diagonals do not match', () {
    final mixed = _empty(5);
    mixed[2][0] = _piece(Shape.circle, Direction.up);
    mixed[2][1] = _piece(Shape.diamond, Direction.up);
    mixed[2][2] = _piece(Shape.circle, Direction.up);
    expect(clearMatches(mixed).foundMatch, isFalse);

    final diagonal = _empty(5);
    diagonal[0][0] = _piece(Shape.circle, Direction.up);
    diagonal[1][1] = _piece(Shape.circle, Direction.up);
    diagonal[2][2] = _piece(Shape.circle, Direction.up);
    expect(clearMatches(diagonal).foundMatch, isFalse);
  });

  test('no match skips shift in the placement wave helper', () {
    final state = parseGameState(_blankBoard());
    final placement = applyPlacement(
      state,
      parseMove({
        'offerIndex': 0,
        'tap': [1, 1],
      }),
    ) as PlacementApplied;
    final wave = resolveAfterPlacement(placement);
    expect(wave.match.foundMatch, isFalse);
    expect(wave.shift, isNull);
    expect(wave.placement.cells[1][2], placement.placedPiece);
  });

  test('swap and follow-into-vacated-cell are rejected', () {
    final swap = _empty(5);
    swap[2][1] = _piece(Shape.circle, Direction.right);
    swap[2][2] = _piece(Shape.diamond, Direction.left);
    final swapShift = applyShift(swap, blocked: const []);
    expect(swapShift.moved, isEmpty);
    expect(swapShift.cells[2][1]!.shape, Shape.circle);
    expect(swapShift.cells[2][2]!.shape, Shape.diamond);

    final follow = _empty(5);
    follow[2][0] = _piece(Shape.circle, Direction.right);
    follow[2][1] = _piece(Shape.diamond, Direction.right);
    final followShift = applyShift(follow, blocked: const []);
    expect(followShift.moved.single.sourceIndex, 2 * 5 + 1);
    expect(followShift.cells[2][0]!.shape, Shape.circle);
    expect(followShift.cells[2][1], isNull);
    expect(followShift.cells[2][2]!.shape, Shape.diamond);
  });

  test('moved records are sorted and omit stationary pieces', () {
    final cells = _empty(5);
    cells[0][0] = _piece(Shape.circle, Direction.right);
    cells[3][1] = _piece(Shape.diamond, Direction.up);
    final shift = applyShift(cells, blocked: const []);
    expect(shift.moved.map((item) => item.sourceIndex).toList(), [0, 16]);
    expect(shift.moved.every((item) => item.from != item.to), isTrue);
  });

  test('inputs and results stay immutable and deterministic', () {
    final board = _phaseBoard('08-preoccupied-shift.json');
    final before = jsonEncode([
      for (final row in board.cells) [for (final cell in row) cell?.toJson()],
    ]);
    final first = applyShift(board.cells, blocked: board.blocked);
    final second = applyShift(board.cells, blocked: board.blocked);
    expect(
      jsonEncode(first.moved.map((item) => item.toJson()).toList()),
      jsonEncode(second.moved.map((item) => item.toJson()).toList()),
    );
    expect(
      jsonEncode([
        for (final row in board.cells) [for (final cell in row) cell?.toJson()],
      ]),
      before,
    );
    expect(() => first.cells[0].add(null), throwsUnsupportedError);
    expect(() => first.moved.add(first.moved.first), throwsUnsupportedError);

    final match = clearMatches(board.cells);
    expect(
      () => match.cleared.add(Coordinate(row: 0, column: 0)),
      throwsUnsupportedError,
    );
  });

  test('PZD-18 placement regression still lands and rejects', () {
    final free = _fullMove('01-place-right-free.json');
    final applied = applyPlacement(free.state, free.move) as PlacementApplied;
    expect(applied.landing, Coordinate(row: 2, column: 3));
    final illegal = _fixture('04-illegal-tap.json');
    final scenario = (illegal['scenarios'] as List).first as Map;
    final state = parseGameState((scenario['given'] as Map)['state']);
    final move = parseMove(((scenario['when'] as Map)['moves'] as List).first);
    final rejected = applyPlacement(state, move) as PlacementRejected;
    expect(rejected.code, GameplayRejection.blockedTap);
    expect(identical(rejected.state, state), isTrue);
  });

  test('shift rejects a piece on a blocked cell without mutating input', () {
    final cells = _empty(5);
    cells[2][3] = _piece(Shape.circle, Direction.right);
    final blocked = [Coordinate(row: 2, column: 3)];
    final before = jsonEncode([
      for (final row in cells) [for (final cell in row) cell?.toJson()],
    ]);
    try {
      applyShift(cells, blocked: blocked);
      fail('expected ValidationFailure');
    } on ValidationFailure catch (failure) {
      expect(failure.wires, contains('blocked_cell_occupied'));
    }
    expect(
      jsonEncode([
        for (final row in cells) [for (final cell in row) cell?.toJson()],
      ]),
      before,
    );
  });

  test('shift rejects duplicate, out-of-range, and unsorted blocked lists', () {
    final cells = _empty(5);
    expect(
      () => applyShift(
        cells,
        blocked: [Coordinate(row: 1, column: 1), Coordinate(row: 1, column: 1)],
      ),
      throwsA(
        isA<ValidationFailure>().having(
          (failure) => failure.wires,
          'wires',
          contains('duplicate_blocked'),
        ),
      ),
    );
    expect(
      () => applyShift(cells, blocked: [Coordinate(row: 9, column: 0)]),
      throwsA(
        isA<ValidationFailure>().having(
          (failure) => failure.wires,
          'wires',
          contains('blocked_out_of_range'),
        ),
      ),
    );
    expect(
      () => applyShift(
        cells,
        blocked: [Coordinate(row: 1, column: 2), Coordinate(row: 1, column: 0)],
      ),
      throwsA(
        isA<ValidationFailure>().having(
          (failure) => failure.wires,
          'wires',
          contains('blocked_not_row_major'),
        ),
      ),
    );
  });

  test('match and clear reject empty or non-square boards', () {
    expect(
      () => findMatches(const <List<Piece?>>[]),
      throwsA(
        isA<ValidationFailure>().having(
          (failure) => failure.wires,
          'wires',
          contains('malformed_board'),
        ),
      ),
    );
    expect(
      () => clearMatches([
        [null, null],
        [null],
      ]),
      throwsA(
        isA<ValidationFailure>().having(
          (failure) => failure.wires,
          'wires',
          contains('malformed_board'),
        ),
      ),
    );
    final jagged = [
      [null, null],
      [null],
    ];
    final before = jagged.map((row) => List<Piece?>.from(row)).toList();
    try {
      clearMatches(jagged);
      fail('expected ValidationFailure');
    } on ValidationFailure catch (failure) {
      expect(failure.wires, contains('malformed_board'));
    }
    expect(jagged[0].length, before[0].length);
    expect(jagged[1].length, before[1].length);
  });
}

Map<String, Object?> _fixture(String name) {
  final path =
      '${Directory.current.path}/../../docs/contracts/gameplay/v1/fixtures/$name';
  return (jsonDecode(File(path).readAsStringSync()) as Map)
      .cast<String, Object?>();
}

({GameState state, Move move}) _fullMove(String name) {
  final document = _fixture(name);
  final scenario = (document['scenarios'] as List).first as Map;
  return (
    state: parseGameState((scenario['given'] as Map)['state']),
    move: parseMove(((scenario['when'] as Map)['moves'] as List).first),
  );
}

BoardGeometry _phaseBoard(String name) {
  final document = _fixture(name);
  final scenario = (document['scenarios'] as List).first as Map;
  return parseBoard((scenario['given'] as Map).cast<String, Object?>());
}

Piece _piece(Shape shape, Direction direction) =>
    Piece(shape: shape, direction: direction);

List<List<Piece?>> _empty(int size) => [
  for (var row = 0; row < size; row++)
    [for (var column = 0; column < size; column++) null],
];

MatchClearResult _horizontalRun(int length) {
  final cells = _empty(5);
  for (var column = 0; column < length; column++) {
    cells[2][column] = _piece(Shape.circle, Direction.up);
  }
  return clearMatches(cells);
}

Map<String, Object?> _blankBoard() => {
  'rulesVersion': 'core-001.v1',
  'boardSize': 5,
  'moveLimit': 5,
  'blocked': <Object?>[],
  'cells': <Object?>[
    for (var row = 0; row < 5; row++)
      <Object?>[for (var column = 0; column < 5; column++) null],
  ],
  'offers': [
    {'shape': 'circle', 'direction': 'right'},
    {'shape': 'diamond', 'direction': 'down'},
    {'shape': 'triangle', 'direction': 'left'},
  ],
  'futurePieces': [
    {'shape': 'circle', 'direction': 'left'},
  ],
  'turnsUsed': 0,
  'score': 0,
  'status': 'in_progress',
};
