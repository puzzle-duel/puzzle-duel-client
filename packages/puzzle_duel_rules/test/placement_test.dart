import 'dart:convert';
import 'dart:io';

import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';
import 'package:test/test.dart';

void main() {
  test('fixture 01 lands on the free right neighbor', () {
    final step = _firstLegal('01-place-right-free.json');
    final result = applyPlacement(step.state, step.move);
    final applied = result as PlacementApplied;
    expect(applied.landing, Coordinate(row: 2, column: 3));
    expect(applied.turnsUsed, 1);
    expect(applied.score, 0);
    expect(applied.placedPiece.direction, Direction.right);
    expect(applied.cells[2][3], applied.placedPiece);
    expect(applied.cells[2][2], isNull);
    expect(applied.before.status, GameStatus.inProgress);
    expect(applied.offerConsumption, isA<OfferWillReplace>());
    final offer = applied.offerConsumption as OfferWillReplace;
    expect(offer.replacement.shape, Shape.circle);
    expect(offer.replacement.direction, Direction.left);
    expect(offer.remainingFuture.single.direction, Direction.up);
  });

  test('fixture 02 falls back when the forward cell is blocked', () {
    final step = _firstLegal('02-place-blocked-neighbor.json');
    final applied = applyPlacement(step.state, step.move) as PlacementApplied;
    expect(applied.landing, Coordinate(row: 2, column: 2));
    expect(applied.turnsUsed, 1);
    expect(applied.cells[2][2], applied.placedPiece);
  });

  test('fixture 03 stays on the tap at the top edge', () {
    final step = _firstLegal('03-place-edge.json');
    final applied = applyPlacement(step.state, step.move) as PlacementApplied;
    expect(applied.landing, Coordinate(row: 0, column: 2));
    expect(applied.placedPiece.direction, Direction.up);
  });

  test('fixture 04 rejects blocked and occupied taps without changes', () {
    final document = _fixture('04-illegal-tap.json');
    for (final scenario in document['scenarios'] as List) {
      final state = parseGameState(
        ((scenario as Map)['given'] as Map)['state'],
      );
      final move = parseMove(
        (((scenario['when'] as Map)['moves'] as List).first) as Object?,
      );
      final before = jsonEncode(state.toJson());
      final result = applyPlacement(state, move) as PlacementRejected;
      final expected =
          ((((scenario['expected'] as Map)['steps'] as List).first)
                  as Map)['error']
              as Map;
      expect(result.code.wire, expected['code']);
      expect(jsonEncode(result.state.toJson()), before);
      expect(identical(result.state, state), isTrue);
    }
  });

  test('fixture 05 places correctly and defers match resolution', () {
    final step = _firstLegal('05-horizontal-match.json');
    final applied = applyPlacement(step.state, step.move) as PlacementApplied;
    expect(applied.landing.toJson(), step.expectedLanding);
    expect(applied.turnsUsed, step.expectedTurns);
    expect(applied.score, step.state.score);
    expect(
      applied.cells[applied.landing.row][applied.landing.column],
      isNotNull,
    );
    // Match/clear is not applied: fixture final cells after clear differ.
    expect(applied.cells, isNot(equals(_cellsFrom(step.expectedFinalCells))));
  });

  test('fixture 11 already-ended taps reject as game_ended', () {
    final document = _fixture('11-end-conditions.json');
    final scenario = (document['scenarios'] as List).first as Map;
    final steps = ((scenario['expected'] as Map)['steps'] as List);
    final illegal = steps[1] as Map;
    expect(illegal['legal'], isFalse);
    final ended = parseGameState(illegal['state']);
    expect(ended.status, GameStatus.ended);
    final move = parseMove({
      'offerIndex': 0,
      'tap': [0, 0],
    });
    final before = jsonEncode(ended.toJson());
    final result = applyPlacement(ended, move) as PlacementRejected;
    expect(result.code, GameplayRejection.gameEnded);
    expect(jsonEncode(result.state.toJson()), before);
  });

  test('fixture 13 placement does not finalize game end', () {
    final step = _firstLegal('13-cascade-reopen-end.json');
    final applied = applyPlacement(step.state, step.move) as PlacementApplied;
    expect(applied.landing.toJson(), step.expectedLanding);
    expect(applied.turnsUsed, 1);
    // After placement the last empty cell is occupied, but status is not ended.
    expect(applied.before.status, GameStatus.inProgress);
    expect(applied.score, step.state.score);
    // Clearing would reopen cells; this phase keeps the piece on the board.
    expect(
      applied.cells[applied.landing.row][applied.landing.column],
      isNotNull,
    );
  });

  test('all four directions and boundaries', () {
    expect(_landing(direction: Direction.right, tap: [2, 2]), [2, 3]);
    expect(_landing(direction: Direction.left, tap: [2, 2]), [2, 1]);
    expect(_landing(direction: Direction.up, tap: [2, 2]), [1, 2]);
    expect(_landing(direction: Direction.down, tap: [2, 2]), [3, 2]);
    expect(_landing(direction: Direction.up, tap: [0, 2]), [0, 2]);
    expect(_landing(direction: Direction.down, tap: [4, 2]), [4, 2]);
    expect(_landing(direction: Direction.left, tap: [2, 0]), [2, 0]);
    expect(_landing(direction: Direction.right, tap: [2, 4]), [2, 4]);
  });

  test('blocked or occupied neighbor falls back to the tap', () {
    final blocked = _blank()
      ..['blocked'] = [
        [2, 3],
      ];
    final state = parseGameState(blocked);
    final move = parseMove({
      'offerIndex': 0,
      'tap': [2, 2],
    });
    final applied = applyPlacement(state, move) as PlacementApplied;
    expect(applied.landing, Coordinate(row: 2, column: 2));

    final occupied = _blank();
    occupied['cells'] = <Object?>[
      for (var row = 0; row < 5; row++)
        <Object?>[
          for (var column = 0; column < 5; column++)
            if (row == 2 && column == 3)
              {'shape': 'diamond', 'direction': 'down'}
            else
              null,
        ],
    ];
    final occupiedState = parseGameState(occupied);
    final appliedOccupied =
        applyPlacement(occupiedState, move) as PlacementApplied;
    expect(appliedOccupied.landing, Coordinate(row: 2, column: 2));
  });

  test('never moves farther than one cell', () {
    final state = parseGameState(_blank());
    final move = parseMove({
      'offerIndex': 0,
      'tap': [2, 0],
    });
    final applied = applyPlacement(state, move) as PlacementApplied;
    expect(applied.landing, Coordinate(row: 2, column: 1));
    expect(applied.cells[2][2], isNull);
    expect(applied.cells[2][3], isNull);
    expect(applied.cells[2][4], isNull);
  });

  test(
    'ended in-bounds empty, blocked, and occupied taps return game_ended',
    () {
      final ended = parseGameState(
        _blank()
          ..['turnsUsed'] = 5
          ..['moveLimit'] = 5
          ..['status'] = 'ended'
          ..['cells'] = [
            for (var row = 0; row < 5; row++)
              [
                for (var column = 0; column < 5; column++)
                  if (row == 0 && column == 0)
                    {'shape': 'circle', 'direction': 'up'}
                  else
                    null,
              ],
          ]
          ..['blocked'] = [
            [0, 1],
          ],
      );
      for (final tap in [
        [1, 1],
        [0, 1],
        [0, 0],
      ]) {
        final before = jsonEncode(ended.toJson());
        final result = applyPlacement(
          ended,
          parseMove({'offerIndex': 0, 'tap': tap}),
        ) as PlacementRejected;
        expect(result.code, GameplayRejection.gameEnded);
        expect(jsonEncode(result.state.toJson()), before);
        expect(result.state.cells, ended.cells);
        expect(result.state.offers, ended.offers);
        expect(result.state.futurePieces, ended.futurePieces);
        expect(result.state.turnsUsed, ended.turnsUsed);
        expect(result.state.score, ended.score);
      }
    },
  );

  test('out of bounds is a safety stop while in progress and when ended', () {
    final active = parseGameState(_blank());
    final activeBefore = jsonEncode(active.toJson());
    final activeResult = applyPlacement(
      active,
      parseMove({
        'offerIndex': 0,
        'tap': [9, 9],
      }),
    ) as PlacementUnsafe;
    expect(activeResult.reason, PlacementSafety.tapOutOfBounds);
    expect(jsonEncode(activeResult.state.toJson()), activeBefore);
    expect(activeResult.state.offers, active.offers);
    expect(activeResult.state.futurePieces, active.futurePieces);
    expect(activeResult.state.turnsUsed, active.turnsUsed);
    expect(activeResult.state.score, active.score);

    final ended = parseGameState(
      _blank()
        ..['turnsUsed'] = 5
        ..['moveLimit'] = 5
        ..['status'] = 'ended',
    );
    final endedBefore = jsonEncode(ended.toJson());
    final endedResult = applyPlacement(
      ended,
      parseMove({
        'offerIndex': 0,
        'tap': [9, 9],
      }),
    ) as PlacementUnsafe;
    expect(endedResult.reason, PlacementSafety.tapOutOfBounds);
    expect(endedResult, isNot(isA<PlacementRejected>()));
    expect(jsonEncode(endedResult.state.toJson()), endedBefore);
    expect(endedResult.state.cells, ended.cells);
    expect(endedResult.state.offers, ended.offers);
    expect(endedResult.state.futurePieces, ended.futurePieces);
    expect(endedResult.state.turnsUsed, ended.turnsUsed);
    expect(endedResult.state.score, ended.score);
  });

  test('empty future stream defers offer replacement', () {
    final state = parseGameState(_blank()..['futurePieces'] = <Object?>[]);
    final applied = applyPlacement(
      state,
      parseMove({
        'offerIndex': 1,
        'tap': [2, 2],
      }),
    ) as PlacementApplied;
    expect(applied.offerConsumption, isA<OfferReplacementDeferred>());
    expect(
      (applied.offerConsumption as OfferReplacementDeferred).offerIndex,
      1,
    );
    expect(applied.before.offers, state.offers);
  });

  test('replacement names only the consumed slot', () {
    final state = parseGameState(_blank());
    final applied = applyPlacement(
      state,
      parseMove({
        'offerIndex': 2,
        'tap': [1, 1],
      }),
    ) as PlacementApplied;
    final offer = applied.offerConsumption as OfferWillReplace;
    expect(offer.offerIndex, 2);
    expect(offer.replacement, state.futurePieces.first);
    expect(offer.remainingFuture, state.futurePieces.skip(1));
    expect(state.offers[0], isNotNull);
    expect(state.offers[1], isNotNull);
  });

  test('placement is deterministic and does not mutate the input', () {
    final state = parseGameState(_blank());
    final move = parseMove({
      'offerIndex': 0,
      'tap': [2, 2],
    });
    final before = jsonEncode(state.toJson());
    final first = applyPlacement(state, move) as PlacementApplied;
    final second = applyPlacement(state, move) as PlacementApplied;
    expect(first.landing, second.landing);
    expect(first.turnsUsed, second.turnsUsed);
    expect(first.cells, second.cells);
    expect(jsonEncode(state.toJson()), before);
    expect(() => first.cells[0].add(null), throwsUnsupportedError);
  });

  test('selected piece keeps its direction on the board', () {
    final state = parseGameState(_blank());
    final applied = applyPlacement(
      state,
      parseMove({
        'offerIndex': 0,
        'tap': [2, 2],
      }),
    ) as PlacementApplied;
    expect(applied.placedPiece.direction, Direction.right);
    expect(applied.cells[2][3]!.direction, Direction.right);
  });
}

Map<String, Object?> _fixture(String name) {
  final path =
      '${Directory.current.path}/../../docs/contracts/gameplay/v1/fixtures/$name';
  return (jsonDecode(File(path).readAsStringSync()) as Map)
      .cast<String, Object?>();
}

({
  GameState state,
  Move move,
  List<int> expectedLanding,
  int expectedTurns,
  Object? expectedFinalCells,
})
_firstLegal(String name) {
  final document = _fixture(name);
  final scenario = (document['scenarios'] as List).first as Map;
  final state = parseGameState((scenario['given'] as Map)['state']);
  final move = parseMove(((scenario['when'] as Map)['moves'] as List).first);
  final step = ((scenario['expected'] as Map)['steps'] as List).first as Map;
  return (
    state: state,
    move: move,
    expectedLanding: (step['landing'] as List).cast<int>(),
    expectedTurns: step['turnsUsed'] as int,
    expectedFinalCells: (step['finalState'] as Map)['cells'],
  );
}

List<List<Piece?>> _cellsFrom(Object? raw) {
  final rows = raw as List;
  return [
    for (final row in rows)
      [for (final cell in row as List) cell == null ? null : parsePiece(cell)],
  ];
}

List<int> _landing({required Direction direction, required List<int> tap}) {
  final state = parseGameState(
    _blank()
      ..['offers'] = [
        {'shape': 'circle', 'direction': direction.wire},
        {'shape': 'diamond', 'direction': 'down'},
        {'shape': 'triangle', 'direction': 'left'},
      ],
  );
  final applied = applyPlacement(
    state,
    parseMove({'offerIndex': 0, 'tap': tap}),
  ) as PlacementApplied;
  return applied.landing.toJson();
}

Map<String, Object?> _blank() => {
  'rulesVersion': 'core-001.v1',
  'boardSize': 5,
  'moveLimit': 5,
  'blocked': <Object?>[],
  'cells': [
    for (var row = 0; row < 5; row++)
      [for (var column = 0; column < 5; column++) null],
  ],
  'offers': [
    {'shape': 'circle', 'direction': 'right'},
    {'shape': 'diamond', 'direction': 'down'},
    {'shape': 'triangle', 'direction': 'left'},
  ],
  'futurePieces': [
    {'shape': 'circle', 'direction': 'left'},
    {'shape': 'diamond', 'direction': 'up'},
  ],
  'turnsUsed': 0,
  'score': 0,
  'status': 'in_progress',
};
