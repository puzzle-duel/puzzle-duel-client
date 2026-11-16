import 'dart:convert';
import 'dart:io';

import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';
import 'package:test/test.dart';

void main() {
  group('v1 fullMove golden fixtures', () {
    for (final name in const [
      '01-place-right-free.json',
      '02-place-blocked-neighbor.json',
      '03-place-edge.json',
      '04-illegal-tap.json',
      '05-horizontal-match.json',
      '10-two-wave-cascade.json',
      '11-end-conditions.json',
      '12-replay-determinism.json',
      '13-cascade-reopen-end.json',
    ]) {
      test(name, () => _assertFullMoveFixture(_v1Fixture(name)));
    }
  });

  test('v2 fixture 01 terminal null slot', () {
    _assertFullMoveFixture(_v2Fixture('01-terminal-null-slot.json'));
  });

  test('v2 early board-full empty stream fails closed', () {
    final probe = _v2Invalid('early-board-end-empty-stream.json');
    final state = parseGameState(probe['state']);
    final move = parseMove(probe['move']);
    final before = state;
    final result = applyMove(state, move);
    expect(result, isA<MoveUnsafe>());
    expect((result as MoveUnsafe).reason, MoveSafety.earlyBoardEndEmptyStream);
    expect(identical(result.state, before) || result.state == before, isTrue);
    expect(state, before);
  });

  test('legal move without a match scores zero and does not shift', () {
    final step = _firstStep('01-place-right-free.json');
    final result = applyMove(step.state, step.move) as MoveApplied;
    expect(result.scoreDelta, 0);
    expect(result.waves, isEmpty);
    expect(result.finalState.score, step.state.score);
    expect(result.finalState.cells[2][3]!.shape, Shape.circle);
  });

  test('cross-shaped unique clear counts five at wave 1 score', () {
    final document = _v1Fixture('06-cross-union.json');
    final scenario = (document['scenarios'] as List).first as Map;
    final board = parseBoard(
      (scenario['given'] as Map).cast<String, Object?>(),
    );
    final match = clearMatches(board.cells);
    expect(match.uniqueClearedCount, 5);
    expect(match.uniqueClearedCount * 100 * 1, 500);
  });

  test('wave multiplier resets between player moves', () {
    final document = _v1Fixture('12-replay-determinism.json');
    final scenario = (document['scenarios'] as List).first as Map;
    var state = parseInitialGameState((scenario['given'] as Map)['state']);
    final moves = (scenario['when'] as Map)['moves'] as List;
    final first = applyMove(state, parseMove(moves[0])) as MoveApplied;
    expect(first.waves.single.wave, 1);
    expect(first.scoreDelta, 300);
    state = first.finalState;
    final second = applyMove(state, parseMove(moves[1])) as MoveApplied;
    expect(second.waves.single.wave, 1);
    expect(second.scoreDelta, 300);
    expect(second.finalState.score, 600);
  });

  test('no movement when zero cells clear', () {
    final step = _firstStep('01-place-right-free.json');
    final result = applyMove(step.state, step.move) as MoveApplied;
    expect(result.waves, isEmpty);
  });

  test('rejected move keeps score and turns unchanged', () {
    final document = _v1Fixture('04-illegal-tap.json');
    final scenario = (document['scenarios'] as List).first as Map;
    final state = parseGameState((scenario['given'] as Map)['state']);
    final move = parseMove(((scenario['when'] as Map)['moves'] as List).first);
    final result = applyMove(state, move) as MoveRejected;
    expect(result.state, state);
    expect(result.state.score, state.score);
    expect(result.state.turnsUsed, state.turnsUsed);
  });

  test('ended-game in-bounds tap returns game_ended', () {
    final document = _v1Fixture('11-end-conditions.json');
    final scenario = (document['scenarios'] as List).firstWhere(
      (item) => (item as Map)['name'] == 'move_limit',
    ) as Map;
    var state = parseGameState((scenario['given'] as Map)['state']);
    final moves = (scenario['when'] as Map)['moves'] as List;
    state = (applyMove(state, parseMove(moves[0])) as MoveApplied).finalState;
    expect(state.status, GameStatus.ended);
    final rejected = applyMove(state, parseMove(moves[1])) as MoveRejected;
    expect(rejected.code, GameplayRejection.gameEnded);
    expect(rejected.state, state);
  });

  test('v1 empty stream fails closed without inventing a piece', () {
    final blank = _blank()..['futurePieces'] = <Object?>[];
    final state = parseGameState(blank);
    final result = applyMove(
      state,
      parseMove({
        'offerIndex': 0,
        'tap': [1, 1],
      }),
    );
    expect(result, isA<MoveUnsafe>());
    expect((result as MoveUnsafe).reason, MoveSafety.emptyStreamNotTerminal);
    expect(result.state, state);
  });

  test('unresolved pre-move match fails closed without scoring', () {
    final raw = _blank()
      ..['cells'] = [
        for (var row = 0; row < 5; row++)
          [
            for (var column = 0; column < 5; column++)
              row == 2 && column < 3
                  ? {'shape': 'circle', 'direction': 'left'}
                  : null,
          ],
      ]
      ..['score'] = 40
      ..['turnsUsed'] = 2;
    final state = parseGameState(raw);
    expect(state.hasOrthogonalRun, isTrue);
    expect(state.status, GameStatus.inProgress);
    expect(
      () => parseInitialGameState(raw),
      throwsA(
        isA<ValidationFailure>().having(
          (failure) => failure.codes,
          'codes',
          contains(ValidationCode.unresolvedInitialMatch),
        ),
      ),
    );

    final snapshot = parseGameState(state.toJson());
    final result = applyMove(
      state,
      parseMove({
        'offerIndex': 1,
        'tap': [0, 0],
      }),
    );
    expect(result, isA<MoveUnsafe>());
    expect((result as MoveUnsafe).reason, MoveSafety.unresolvedPreMoveMatch);
    expect(result.state, state);
    expect(state, snapshot);
    expect(state.score, 40);
    expect(state.turnsUsed, 2);
    expect(state.offers, snapshot.offers);
    expect(state.futurePieces, snapshot.futurePieces);
    expect(state.rulesVersion, RulesVersion.core001V1);
    expect(state.status, GameStatus.inProgress);
  });

  test('pre-move match does not override gameplay rejections', () {
    final raw = _blank()
      ..['cells'] = [
        for (var row = 0; row < 5; row++)
          [
            for (var column = 0; column < 5; column++)
              row == 2 && column < 3
                  ? {'shape': 'circle', 'direction': 'left'}
                  : null,
          ],
      ]
      ..['status'] = 'ended'
      ..['turnsUsed'] = 5
      ..['moveLimit'] = 5;
    final state = parseGameState(raw);
    expect(state.hasOrthogonalRun, isTrue);
    final result = applyMove(
      state,
      parseMove({
        'offerIndex': 0,
        'tap': [4, 4],
      }),
    );
    expect(result, isA<MoveRejected>());
    expect((result as MoveRejected).code, GameplayRejection.gameEnded);
    expect(result.state, state);
  });

  test('deep immutability of applied results', () {
    final step = _firstStep('05-horizontal-match.json');
    final result = applyMove(step.state, step.move) as MoveApplied;
    expect(
      () => (result.waves as List).add(
        WaveResult(wave: 99, cleared: const [], scoreDelta: 0, moved: const []),
      ),
      throwsUnsupportedError,
    );
    expect(
      () => (result.finalState.cells[0] as List).add(null),
      throwsUnsupportedError,
    );
    expect(
      () => (result.waves.first.cleared as List).add(
        Coordinate(row: 0, column: 0),
      ),
      throwsUnsupportedError,
    );
  });

  test('repeated replay produces deeply equal outputs', () {
    final document = _v1Fixture('12-replay-determinism.json');
    final scenario = (document['scenarios'] as List).first as Map;
    final given = (scenario['given'] as Map)['state'];
    final moves = (scenario['when'] as Map)['moves'] as List;

    List<MoveResult> run() {
      var state = parseInitialGameState(given);
      final produced = <MoveResult>[];
      for (final raw in moves) {
        final result = applyMove(state, parseMove(raw));
        produced.add(result);
        if (result is MoveApplied) state = result.finalState;
      }
      return produced;
    }

    final first = run();
    final second = run();
    expect(first, second);
    expect((first.last as MoveApplied).finalState.score, 600);
  });

  test('input state is unchanged after a successful move', () {
    final step = _firstStep('10-two-wave-cascade.json');
    final snapshot = parseGameState(step.state.toJson());
    final result = applyMove(step.state, step.move) as MoveApplied;
    expect(step.state, snapshot);
    expect(result.scoreDelta, 900);
    expect(result.waves, hasLength(2));
    expect(result.waves[0].scoreDelta, 300);
    expect(result.waves[1].scoreDelta, 600);
  });

  test('fixture 10 diamond sourceIndex 23 and wave order', () {
    final step = _firstStep('10-two-wave-cascade.json');
    final result = applyMove(step.state, step.move) as MoveApplied;
    expect(result.waves[0].moved, [
      MovedPiece(
        sourceIndex: 23,
        from: Coordinate(row: 4, column: 3),
        to: Coordinate(row: 4, column: 2),
        shape: Shape.diamond,
        direction: Direction.left,
      ),
    ]);
    expect(result.waves[1].moved, isEmpty);
    expect(result.waves[0].cleared.map((cell) => cell.toJson()).toList(), [
      [0, 0],
      [0, 1],
      [0, 2],
    ]);
    expect(result.waves[1].cleared.map((cell) => cell.toJson()).toList(), [
      [4, 0],
      [4, 1],
      [4, 2],
    ]);
  });
}

void _assertFullMoveFixture(Map<String, Object?> document) {
  expect(document['kind'], 'fullMove');
  for (final raw in document['scenarios'] as List) {
    final scenario = raw as Map;
    final label = '${document['id']}/${scenario['name']}';
    var state = parseInitialGameState((scenario['given'] as Map)['state']);
    final moves = (scenario['when'] as Map)['moves'] as List;
    final steps = (scenario['expected'] as Map)['steps'] as List;
    expect(moves.length, steps.length, reason: label);
    final produced = <Map<String, Object?>>[];
    for (var index = 0; index < moves.length; index++) {
      final before = state;
      final result = applyMove(state, parseMove(moves[index]));
      final expected = (steps[index] as Map).cast<String, Object?>();
      if (expected['legal'] == true) {
        expect(result, isA<MoveApplied>(), reason: '$label step $index');
        final applied = result as MoveApplied;
        expect(
          _normalize(applied.toJson()),
          _normalize(expected),
          reason: '$label step $index',
        );
        state = applied.finalState;
      } else {
        expect(result, isA<MoveRejected>(), reason: '$label step $index');
        final rejected = result as MoveRejected;
        expect(
          _normalize(rejected.toJson()),
          _normalize(expected),
          reason: '$label step $index',
        );
        expect(rejected.state, before);
        state = before;
      }
      produced.add(
        result is MoveApplied
            ? result.toJson()
            : (result as MoveRejected).toJson(),
      );
    }
    final repeat = (scenario['expected'] as Map)['repeat'];
    if (repeat != null) {
      var again = parseInitialGameState((scenario['given'] as Map)['state']);
      final second = <Map<String, Object?>>[];
      for (final rawMove in moves) {
        final result = applyMove(again, parseMove(rawMove));
        if (result is MoveApplied) {
          second.add(result.toJson());
          again = result.finalState;
        } else {
          second.add((result as MoveRejected).toJson());
        }
      }
      expect(_normalize(second), _normalize(produced), reason: '$label repeat');
    }
  }
}

({GameState state, Move move}) _firstStep(String name) {
  final document = _v1Fixture(name);
  final scenario = (document['scenarios'] as List).first as Map;
  return (
    state: parseInitialGameState((scenario['given'] as Map)['state']),
    move: parseMove(((scenario['when'] as Map)['moves'] as List).first),
  );
}

Map<String, Object?> _v1Fixture(String name) {
  final path =
      '${Directory.current.path}/../../docs/contracts/gameplay/v1/fixtures/$name';
  return (jsonDecode(File(path).readAsStringSync()) as Map)
      .cast<String, Object?>();
}

Map<String, Object?> _v2Fixture(String name) {
  final path =
      '${Directory.current.path}/../../docs/contracts/gameplay/v2/fixtures/$name';
  return (jsonDecode(File(path).readAsStringSync()) as Map)
      .cast<String, Object?>();
}

Map<String, Object?> _v2Invalid(String name) {
  final path =
      '${Directory.current.path}/../../docs/contracts/gameplay/v2/invalid/$name';
  return (jsonDecode(File(path).readAsStringSync()) as Map)
      .cast<String, Object?>();
}

Object? _normalize(Object? value) => jsonDecode(jsonEncode(value));

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
