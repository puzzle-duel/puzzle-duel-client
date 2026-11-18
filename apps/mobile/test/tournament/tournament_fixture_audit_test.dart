import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

void main() {
  const slots = <(String, String)>[
    ('E1', 'V3-02-single-wave.json'),
    ('E2', 'V3-05-cascade-reopen.json'),
    ('E3', 'V3-09-move-limit.json'),
    ('M1', 'V3-03-multi-wave.json'),
    ('M2', 'V3-09-move-limit.json'),
    ('H1', 'V3-02-single-wave.json'),
  ];

  test('E1 matches H1 and E3 matches M2 because the UAT manifest reuses fixtures', () {
    expect(slots[0].$2, slots[5].$2);
    expect(slots[2].$2, slots[4].$2);
  });

  for (final slot in slots) {
    test('${slot.$1} follows the pinned ${slot.$2} contract', () {
      final document = jsonDecode(
        File('test/tournament/fixtures/${slot.$2}').readAsStringSync(),
      ) as Map<String, Object?>;
      final initialJson = document['initialState']! as Map<String, Object?>;
      final initial = parseGameState(initialJson);
      expect(initial.boardSize, initialJson['boardSize']);
      expect(initial.moveLimit, initialJson['moveLimit']);
      expect(initial.score, 0);
      expect(initial.status, GameStatus.inProgress);

      final recorded = (document['moves']! as List).first as Map<String, Object?>;
      final tap = recorded['tap']! as List;
      final offerIndex = recorded['offerIndex']! as int;
      final piece = initial.offers[offerIndex].pieceOrNull;
      final offer = (initialJson['offers']! as List)[offerIndex] as Map;
      expect(piece, isNotNull);
      expect(piece!.shape.wire, offer['shape']);
      expect(piece.direction.wire, offer['direction']);

      final coordinate = Coordinate(row: tap[0] as int, column: tap[1] as int);
      expect(
        canPlaceAt(
          boardSize: initial.boardSize,
          cells: initial.cells,
          blocked: initial.blocked,
          piece: piece,
          tap: coordinate,
        ),
        isTrue,
      );
      final applied = applyMove(initial, Move(offerIndex: offerIndex, tap: coordinate));
      expect(applied, isA<MoveApplied>());
      final done = (applied as MoveApplied).finalState;
      final expected = (document['expected']! as Map)['finalState'] as Map;
      expect(done.score, expected['score']);
      expect(done.turnsUsed, expected['turnsUsed']);
      expect(done.status.name, expected['status'] == 'ended' ? 'ended' : 'inProgress');

      Coordinate? occupied;
      for (var row = 0; row < initial.boardSize && occupied == null; row++) {
        for (var column = 0; column < initial.boardSize; column++) {
          if (initial.cells[row][column] != null) {
            occupied = Coordinate(row: row, column: column);
            break;
          }
        }
      }
      if (occupied != null) {
        final rejected = applyMove(initial, Move(offerIndex: offerIndex, tap: occupied));
        expect(rejected, isA<MoveRejected>());
        expect((rejected as MoveRejected).state.score, initial.score);
        expect(
          canPlaceAt(
            boardSize: initial.boardSize,
            cells: initial.cells,
            blocked: initial.blocked,
            piece: piece,
            tap: occupied,
          ),
          isFalse,
        );
      } else {
        final again = applyMove(
          done,
          Move(offerIndex: 1, tap: Coordinate(row: 0, column: 0)),
        );
        expect(again, isA<MoveRejected>());
        expect((again as MoveRejected).state.score, done.score);
      }
    });
  }
}
