import 'dart:convert';
import 'dart:io';

import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';
import 'package:test/test.dart';

void main() {
  test('snapshots stay immutable and compare by value', () {
    final first = parseGameState(_valid());
    final second = parseGameState(jsonDecode(jsonEncode(first.toJson())));
    expect(second, first);
    expect(second.hashCode, first.hashCode);
    expect(identical(first, second), isFalse);
    expect(first.cells[0][0], isNull);
    expect(() => first.cells.add(<Piece?>[]), throwsUnsupportedError);
    expect(() => first.cells[0].add(null), throwsUnsupportedError);
    expect(
      () => first.blocked.add(Coordinate(row: 0, column: 0)),
      throwsUnsupportedError,
    );
    expect(() => first.offers.add(null), throwsUnsupportedError);
    expect(() => first.futurePieces.add(_piece()), throwsUnsupportedError);
    final changed = _valid()..['score'] = 10;
    expect(parseGameState(changed), isNot(first));
  });

  test('json round trip keeps a terminal null slot', () {
    final state = parseGameState(_terminalNull());
    final again = parseGameState(jsonDecode(jsonEncode(state.toJson())));
    expect(again, state);
    expect(again.offers[0], isNull);
    expect(again.rulesVersion, RulesVersion.core001V2);
    expect(again.status, GameStatus.ended);
  });

  test('piece and coordinate parsing is closed', () {
    expect(parsePiece(_pieceJson()).shape, Shape.circle);
    expect(parseCoordinate([2, 3]), Coordinate(row: 2, column: 3));
    expectCodes(() => parsePiece({..._pieceJson(), 'color': 'red'}), [
      'unexpected_property',
    ]);
    expectCodes(() => parsePiece({'shape': 'square', 'direction': 'up'}), [
      'malformed_shape',
    ]);
    expectCodes(
      () => parsePiece({'shape': 'circle', 'direction': 'sideways'}),
      ['malformed_direction'],
    );
    expectCodes(() => parseCoordinate([0]), ['malformed_coordinate']);
    expectCodes(() => parseCoordinate([-1, 0]), ['malformed_coordinate']);
    expectCodes(() => parseCoordinate([1.5, 0]), ['malformed_coordinate']);
    expect(
      () => Coordinate(row: -1, column: 0),
      throwsA(isA<ValidationFailure>()),
    );
  });

  test('move model rejects a bad index and does not play the tap', () {
    final move = parseMove({
      'offerIndex': 0,
      'tap': [99, 4],
    });
    expect(move.offerIndex, 0);
    expect(move.tap, Coordinate(row: 99, column: 4));
    expectCodes(
      () => parseMove({
        'offerIndex': 3,
        'tap': [0, 0],
      }),
      ['illegal_offer_index'],
    );
    expectCodes(
      () => parseMove({
        'offerIndex': 1,
        'tap': [0, -1],
      }),
      ['malformed_coordinate'],
    );
    expectCodes(
      () => parseMove({
        'offerIndex': 1,
        'tap': [0, 0],
        'legal': true,
      }),
      ['unexpected_property'],
    );
    expect(
      ValidationCode.values.map((code) => code.wire),
      isNot(contains('blocked_tap')),
    );
    expect(
      ValidationCode.values.map((code) => code.wire),
      isNot(contains('occupied_tap')),
    );
    expect(
      ValidationCode.values.map((code) => code.wire),
      isNot(contains('game_ended')),
    );
  });

  test('defensive copy leaves the input list unchanged', () {
    final raw = _valid();
    final cells = raw['cells']! as List<Object?>;
    final row = cells[0]! as List<Object?>;
    final before = jsonEncode(raw);
    final state = parseGameState(raw);
    row[0] = _pieceJson();
    expect(jsonEncode(raw), isNot(before));
    expect(state.cells[0][0], isNull);
  });

  test('a rejected document does not mutate its input', () {
    final raw = _valid()..['score'] = -5;
    final before = jsonEncode(raw);
    expectCodes(() => parseGameState(raw), ['malformed_score']);
    expect(jsonEncode(raw), before);
  });

  test('structural counters and board shape fail closed', () {
    expectCodes(() => parseGameState(_valid()..['boardSize'] = 2), [
      'malformed_board',
    ]);
    expectCodes(
      () => parseGameState(
        _valid()
          ..['blocked'] = [
            [1, 0],
            [0, 0],
          ]
          ..['boardSize'] = 2
          ..['cells'] = [
            [null, null],
            [null, null],
          ],
      ),
      ['blocked_not_row_major'],
    );
    expectCodes(() => parseGameState(_valid()..['score'] = -1), [
      'malformed_score',
    ]);
    expectCodes(() => parseGameState(_valid()..['turnsUsed'] = 2), [
      'illegal_turn_count',
    ]);
    expectCodes(
      () => parseGameState(_valid()..['rulesVersion'] = 'core-001.v9'),
      ['unknown_rules_version'],
    );
    expectCodes(() => parseGameState(_valid()..['bonus'] = true), [
      'unexpected_property',
    ]);
    expectCodes(() => parseGameState(_valid()..['status'] = 'playing'), [
      'inconsistent_status',
    ]);
    final full = _valid()
      ..['cells'] = [
        [_pieceJson()],
      ]
      ..['status'] = 'in_progress';
    expectCodes(() => parseGameState(full), ['inconsistent_status']);
  });

  test('v1 rejects a null offer and v2 enforces the terminal slot', () {
    expectCodes(
      () => parseGameState(
        _valid()..['offers'] = [null, _pieceJson(), _pieceJson()],
      ),
      ['null_offer'],
    );
    expectCodes(
      () => parseGameState(_valid()..['offers'] = [_pieceJson(), _pieceJson()]),
      ['malformed_offers'],
    );
    final earlyNull = _terminalNull()
      ..['turnsUsed'] = 0
      ..['moveLimit'] = 5
      ..['status'] = 'ended'
      ..['cells'] = [
        [_pieceJson()],
      ];
    expectCodes(() => parseGameState(earlyNull), ['null_offer_not_terminal']);
    final activeNull = _terminalNull()
      ..['turnsUsed'] = 0
      ..['moveLimit'] = 5
      ..['status'] = 'in_progress'
      ..['cells'] = [
        [null],
      ];
    expectCodes(() => parseGameState(activeNull), ['null_offer_while_active']);
    final storedReplacement = _terminalNull()
      ..['futurePieces'] = [_pieceJson()];
    expectCodes(() => parseGameState(storedReplacement), [
      'null_offer_not_terminal',
    ]);
    expect(
      parseGameState(_terminalNull()).offers
          .where((slot) => slot == null)
          .length,
      1,
    );
  });

  test('canonical fixtures and negative probes', () {
    final root = Directory.current.path;
    expect(root.endsWith('puzzle_duel_rules'), isTrue, reason: root);
    for (final path in Directory(
      '$root/../../docs/contracts/gameplay/v1/fixtures',
    ).listSync()) {
      if (path is! File || !path.path.endsWith('.json')) continue;
      final document = jsonDecode(path.readAsStringSync());
      if (document['kind'] == 'fullMove') {
        for (final scenario in document['scenarios'] as List) {
          final given = (scenario['given']['state'] as Map)
              .cast<String, Object?>();
          expect(
            parseInitialGameState(given).hasOrthogonalRun,
            isFalse,
            reason: path.path,
          );
          for (final state in _states(scenario)) {
            expect(
              parseGameState(state).rulesVersion,
              RulesVersion.core001V1,
              reason: path.path,
            );
          }
        }
      } else {
        for (final board in _boards(document)) {
          final parsed = parseBoard(board);
          if (path.path.endsWith('06-cross-union.json')) {
            expect(parsed.hasOrthogonalRun, isTrue);
          }
        }
      }
    }

    final initial = jsonDecode(
      File(
        '$root/../../docs/contracts/gameplay/v1/invalid/unresolved-initial-match.json',
      ).readAsStringSync(),
    );
    final initialState = _states(initial['fixture']).single;
    expect(parseGameState(initialState).hasOrthogonalRun, isTrue);
    expectCodes(() => parseInitialGameState(initialState), [
      'unresolved_initial_match',
    ]);

    for (final path in Directory(
      '$root/../../docs/contracts/gameplay/v1/invalid',
    ).listSync()) {
      if (path is! File) continue;
      final document =
          jsonDecode(path.readAsStringSync()) as Map<String, Object?>;
      final code = document['expectCode'];
      if (code is! String) continue;
      final state = _states(document['fixture']).single;
      if (code == 'unresolved_initial_match') {
        expect(() => parseGameState(state), returnsNormally);
      } else {
        expectCodes(() => parseGameState(state), [code]);
      }
    }

    for (final state in _states(
      _read(
        '$root/../../docs/contracts/gameplay/v2/fixtures/01-terminal-null-slot.json',
      ),
    )) {
      expect(parseGameState(state).rulesVersion, RulesVersion.core001V2);
    }
    final counts = _read(
      '$root/../../docs/contracts/gameplay/v2/invalid/terminal-offer-counts.json',
    );
    for (final rawCase in counts['cases']! as List<Object?>) {
      final item = rawCase! as Map<String, Object?>;
      final codes = (item['expectCodes']! as List<Object?>).cast<String>();
      if (codes.isEmpty) {
        expect(() => parseGameState(item['state']), returnsNormally);
      } else {
        expectCodes(() => parseGameState(item['state']), codes);
      }
    }
    final active = _read(
      '$root/../../docs/contracts/gameplay/v2/invalid/null-offer-while-active.json',
    );
    expectCodes(() => parseGameState(_states(active['fixture']).single), [
      active['expectCode']! as String,
    ]);
    final early = _read(
      '$root/../../docs/contracts/gameplay/v2/invalid/early-board-end-empty-stream.json',
    );
    final earlyState = parseGameState(early['state']);
    expect(earlyState.offers, everyElement(isNotNull));
    expect(earlyState.futurePieces, isEmpty);
    expect(earlyState.status, GameStatus.inProgress);
  });

  test('library sources do not import Flutter or Flame', () {
    final files = Directory('lib').listSync(recursive: true).whereType<File>();
    for (final file in files) {
      final text = file.readAsStringSync();
      expect(text.contains('package:flutter'), isFalse, reason: file.path);
      expect(text.contains('package:flame'), isFalse, reason: file.path);
      expect(text.contains('dart:ui'), isFalse, reason: file.path);
    }
  });
}

Map<String, Object?> _read(String path) {
  return (jsonDecode(File(path).readAsStringSync()) as Map)
      .cast<String, Object?>();
}

Map<String, Object?> _pieceJson() => {'shape': 'circle', 'direction': 'up'};

Piece _piece() => parsePiece(_pieceJson());

Map<String, Object?> _valid() => {
  'rulesVersion': 'core-001.v1',
  'boardSize': 1,
  'moveLimit': 1,
  'blocked': <Object?>[],
  'cells': <Object?>[
    <Object?>[null],
  ],
  'offers': [
    _pieceJson(),
    {'shape': 'diamond', 'direction': 'down'},
    {'shape': 'triangle', 'direction': 'left'},
  ],
  'futurePieces': <Object?>[],
  'turnsUsed': 0,
  'score': 0,
  'status': 'in_progress',
};

Map<String, Object?> _terminalNull() => {
  'rulesVersion': 'core-001.v2',
  'boardSize': 1,
  'moveLimit': 1,
  'blocked': <Object?>[],
  'cells': <Object?>[
    <Object?>[null],
  ],
  'offers': [
    null,
    {'shape': 'diamond', 'direction': 'down'},
    {'shape': 'triangle', 'direction': 'left'},
  ],
  'futurePieces': <Object?>[],
  'turnsUsed': 1,
  'score': 0,
  'status': 'ended',
};

void expectCodes(void Function() body, List<String> required) {
  try {
    body();
    fail('expected ${required.join(', ')}');
  } on ValidationFailure catch (failure) {
    for (final code in required) {
      expect(failure.wires, contains(code), reason: failure.wires.join(','));
    }
  }
}

const _stateKeys = {
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

Iterable<Map<String, Object?>> _states(Object? node) sync* {
  if (node is Map) {
    final map = node.cast<String, Object?>();
    if (_stateKeys.every(map.containsKey)) yield map;
    for (final value in map.values) {
      yield* _states(value);
    }
  } else if (node is List) {
    for (final value in node) {
      yield* _states(value);
    }
  }
}

Iterable<Map<String, Object?>> _boards(Object? node) sync* {
  if (node is Map) {
    final map = node.cast<String, Object?>();
    if (map.containsKey('rulesVersion') &&
        map.containsKey('boardSize') &&
        map.containsKey('blocked') &&
        map.containsKey('cells') &&
        !map.containsKey('offers')) {
      yield map;
    }
    for (final value in map.values) {
      yield* _boards(value);
    }
  } else if (node is List) {
    for (final value in node) {
      yield* _boards(value);
    }
  }
}
