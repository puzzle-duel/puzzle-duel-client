import 'dart:convert';

import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';
import 'package:test/test.dart';

void main() {
  group('v3 offer wire + terminalReason', () {
    test('parses tagged piece and spent slots', () {
      final state = parseGameState(_v3BoardFullEnded());
      expect(state.rulesVersion, RulesVersion.core001V3);
      expect(state.offers[0], isA<OfferSpent>());
      expect(state.offers[1], isA<OfferLive>());
      expect(state.offers[2], isA<OfferLive>());
      expect(state.terminalReason, TerminalReason.noLegalMoves);
      expect(state.status, GameStatus.ended);
      final json = state.toJson();
      final offersJson = json['offers']! as List<Object?>;
      expect(json['terminalReason'], 'no_legal_moves');
      expect(offersJson[0], {'kind': 'spent'});
      expect((offersJson[1]! as Map<String, Object?>)['kind'], 'piece');
      expect(json.containsKey('terminalReason'), isTrue);
    });

    test('v1/v2 serialization never emits tagged offers', () {
      final v1 = parseGameState(_v1Minimal());
      final offers = v1.toJson()['offers']! as List<Object?>;
      expect(offers[0], isA<Map<String, Object?>>());
      expect((offers[0]! as Map<String, Object?>).containsKey('kind'), isFalse);
      expect(offers[0], containsPair('shape', 'circle'));

      final v2 = parseGameState(_v2TerminalNull());
      final v2Offers = v2.toJson()['offers']! as List<Object?>;
      expect(v2Offers[0], isNull);
      expect(v2.toJson().containsKey('terminalReason'), isFalse);
    });

    test('rejects bare null offer on v3', () {
      final json = _v3Playable()
        ..['offers'] = [null, _offerPiece(), _offerPiece()];
      expectCodes(() => parseGameState(json), ['null_offer']);
    });

    test('rejects unknown offer kind', () {
      final json = _v3Playable()
        ..['offers'] = [
          {'kind': 'bonus'},
          _offerPiece(),
          _offerPiece(),
        ];
      expectCodes(() => parseGameState(json), ['malformed_offer_slot']);
    });

    test('rejects spent with remaining future pieces', () {
      final json = _v3BoardFullEnded()..['futurePieces'] = [_pieceJson()];
      expectCodes(() => parseGameState(json), ['spent_with_future_pieces']);
    });
  });

  group('v3 terminal derivation', () {
    test('rejects playable board falsely marked ended', () {
      final json = _v3Playable()
        ..['status'] = 'ended'
        ..['terminalReason'] = 'no_legal_moves';
      expectCodes(() => parseGameState(json), [
        'inconsistent_status',
        'inconsistent_terminal_reason',
      ]);
    });

    test('rejects unplayable board falsely marked active', () {
      final json = _v3BoardFullEnded()
        ..['status'] = 'in_progress'
        ..['terminalReason'] = null;
      expectCodes(() => parseGameState(json), [
        'inconsistent_status',
        'inconsistent_terminal_reason',
      ]);
    });

    test('rejects forged terminal reason on move limit', () {
      final json = _v3MoveLimitReached()..['terminalReason'] = 'no_legal_moves';
      expectCodes(() => parseGameState(json), ['inconsistent_terminal_reason']);
    });

    test('move-limit precedence over no legal placement', () {
      final expected = deriveTerminalExpectation(
        turnsUsed: 1,
        moveLimit: 1,
        candidate: parseGameState(_v3BoardFullEnded()),
      );
      expect(expected.status, GameStatus.ended);
      expect(expected.reason, TerminalReason.moveLimitReached);
    });

    test('hasLegalPlacement is status-agnostic; hasLegalMove is not', () {
      final playable = parseGameState(_v3Playable());
      expect(hasLegalPlacement(playable), isTrue);
      expect(hasLegalMove(playable), isTrue);

      final budgetEnded = parseGameState(_v3MoveLimitReached());
      expect(hasLegalPlacement(budgetEnded), isTrue);
      expect(hasLegalMove(budgetEnded), isFalse);

      final full = parseGameState(_v3BoardFullEnded());
      expect(hasLegalPlacement(full), isFalse);
      expect(hasLegalMove(full), isFalse);
    });

    test('initial challenge requires live offers and playability', () {
      final ok = parseInitialGameState(_v3Playable());
      expect(ok.terminalReason, isNull);
      expect(ok.offers, everyElement(isA<OfferLive>()));

      final spent = _v3Playable()
        ..['offers'] = [
          {'kind': 'spent'},
          _offerPiece(),
          _offerPiece(),
        ];
      expectCodes(() => parseInitialGameState(spent), ['inconsistent_status']);
    });
  });

  group('v3 gameplay', () {
    test('offer replacement from future stream', () {
      final state = parseGameState(_v3Playable());
      final result = applyMove(
        state,
        parseMove({
          'offerIndex': 0,
          'tap': [0, 0],
        }),
      ) as MoveApplied;
      expect(result.finalState.offers[0], isA<OfferLive>());
      expect(
        (result.finalState.offers[0] as OfferLive).piece,
        state.futurePieces.first,
      );
      expect(result.finalState.offers[1], state.offers[1]);
      expect(result.finalState.offers[2], state.offers[2]);
      expect(
        result.finalState.futurePieces.length,
        state.futurePieces.length - 1,
      );
      expect(result.finalState.status, GameStatus.inProgress);
      expect(result.finalState.terminalReason, isNull);
    });

    test('stream exhaustion writes spent and may continue', () {
      final withOne = parseGameState(_v3LastFuture());
      final drained = applyMove(
        withOne,
        parseMove({
          'offerIndex': 1,
          'tap': [0, 1],
        }),
      ) as MoveApplied;
      expect(drained.finalState.futurePieces, isEmpty);
      expect(drained.finalState.offers[1], isA<OfferLive>());
      expect(
        (drained.finalState.offers[1] as OfferLive).piece,
        withOne.futurePieces.first,
      );
      expect(drained.finalState.status, GameStatus.inProgress);

      final emptyStream = parseGameState(_v3EmptyStreamPlayable());
      final spent = applyMove(
        emptyStream,
        parseMove({
          'offerIndex': 1,
          'tap': [0, 1],
        }),
      ) as MoveApplied;
      expect(spent.finalState.futurePieces, isEmpty);
      expect(spent.finalState.offers[1], isA<OfferSpent>());
      expect(spent.finalState.offers[0], isA<OfferLive>());
      expect(spent.finalState.offers[2], isA<OfferLive>());
      expect(spent.finalState.status, GameStatus.inProgress);
    });

    test('selecting spent offer is unsafe and preserves state', () {
      final state = parseGameState(_v3OneSpentPlayable());
      final before = jsonEncode(state.toJson());
      final result = applyMove(
        state,
        parseMove({
          'offerIndex': 0,
          'tap': [0, 0],
        }),
      );
      expect(result, isA<MoveUnsafe>());
      expect((result as MoveUnsafe).reason, MoveSafety.offerUnavailable);
      expect(result.state, state);
      expect(jsonEncode(state.toJson()), before);
    });

    test('board-full natural terminal with spent offers', () {
      final state = parseGameState(_v3AlmostFull());
      final result = applyMove(
        state,
        parseMove({
          'offerIndex': 0,
          'tap': [0, 0],
        }),
      ) as MoveApplied;
      expect(result.finalState.status, GameStatus.ended);
      expect(result.finalState.terminalReason, TerminalReason.noLegalMoves);
      expect(result.finalState.offers[0], isA<OfferSpent>());
    });

    test('v3 early board-full empty stream succeeds (v2 fails closed)', () {
      final state = parseGameState(_v3EarlyBoardFullEmptyStream());
      final result = applyMove(
        state,
        parseMove({
          'offerIndex': 0,
          'tap': [0, 0],
        }),
      );
      expect(result, isA<MoveApplied>());
      final applied = result as MoveApplied;
      expect(applied.finalState.status, GameStatus.ended);
      expect(applied.finalState.terminalReason, TerminalReason.noLegalMoves);
      expect(applied.finalState.offers[0], isA<OfferSpent>());
    });

    test('move limit reached sets terminal reason', () {
      final state = parseGameState(_v3LastMovePlayable());
      final result = applyMove(
        state,
        parseMove({
          'offerIndex': 0,
          'tap': [0, 0],
        }),
      ) as MoveApplied;
      expect(result.finalState.turnsUsed, 1);
      expect(result.finalState.status, GameStatus.ended);
      expect(result.finalState.terminalReason, TerminalReason.moveLimitReached);
    });

    test('cascade scoring uses wave multiplier', () {
      final state = parseGameState(_v3MatchReady());
      final result = applyMove(
        state,
        parseMove({
          'offerIndex': 0,
          'tap': [0, 2],
        }),
      ) as MoveApplied;
      expect(result.scoreDelta, 300);
      expect(result.waves, hasLength(1));
      expect(result.finalState.score, 300);
    });

    test('cascade clear reopens playable space before terminal', () {
      final state = parseGameState(_v3CascadeReopen());
      final result = applyMove(
        state,
        parseMove({
          'offerIndex': 0,
          'tap': [0, 2],
        }),
      ) as MoveApplied;
      expect(result.scoreDelta, 300);
      expect(result.finalState.status, GameStatus.inProgress);
      expect(result.finalState.terminalReason, isNull);
      expect(hasLegalPlacement(result.finalState), isTrue);
    });

    test('all spent offers with empty cells ends no_legal_moves', () {
      final state = parseGameState(_v3AllSpentEmptyBoard());
      expect(state.status, GameStatus.ended);
      expect(state.terminalReason, TerminalReason.noLegalMoves);
      expect(hasLegalPlacement(state), isFalse);
      expect(hasLegalMove(state), isFalse);
    });

    test('post-terminal in-bounds tap returns game_ended', () {
      final state = parseGameState(_v3BoardFullEnded());
      final before = jsonEncode(state.toJson());
      final result = applyMove(
        state,
        parseMove({
          'offerIndex': 1,
          'tap': [0, 0],
        }),
      ) as MoveRejected;
      expect(result.code, GameplayRejection.gameEnded);
      expect(result.state, state);
      expect(jsonEncode(state.toJson()), before);
    });
  });

  group('v3 security negatives', () {
    test('missing terminalReason key', () {
      final json = _v3Playable()..remove('terminalReason');
      expectCodes(() => parseGameState(json), ['missing_field']);
    });

    test('unknown property rejected', () {
      final json = _v3Playable()..['extra'] = true;
      expectCodes(() => parseGameState(json), ['unexpected_property']);
    });

    test('spent slot rejects extra properties', () {
      final json = _v3OneSpentPlayable()
        ..['offers'] = [
          {'kind': 'spent', 'note': 'x'},
          _offerPiece(shape: 'diamond', direction: 'down'),
          _offerPiece(shape: 'triangle', direction: 'left'),
        ];
      expectCodes(() => parseGameState(json), ['unexpected_property']);
    });

    test('self-consistent hash is not ranked authority marker', () {
      final state = parseGameState(_v3Playable());
      final hash = stateHashV3(state);
      expect(hash, hasLength(64));
      // Engine exposes integrity digest only; no verify/auth API exists.
      expect(state.score, 0);
    });

    test(
      'forged higher score with matching hash is still not ranked proof',
      () {
        final forged = parseGameState(_v3Playable()..['score'] = 999);
        final hash = stateHashV3(forged);
        expect(hash, hasLength(64));
        expect(stateHashV3(parseGameState(_v3Playable())), isNot(hash));
        // No engine API authenticates forged.score via hash.
      },
    );

    test('integer out of JSON-safe range rejected on v3', () {
      final json = _v3Playable()..['score'] = 9007199254740992;
      expectCodes(() => parseGameState(json), ['integer_out_of_range']);
    });

    test('score overflow fails closed and preserves original state', () {
      final state = parseGameState(
        _v3MatchReady()..['score'] = kJsonMaxSafeInteger - 100,
      );
      final before = jsonEncode(state.toJson());
      final result = applyMove(
        state,
        parseMove({
          'offerIndex': 0,
          'tap': [0, 2],
        }),
      );
      expect(result, isA<MoveUnsafe>());
      expect((result as MoveUnsafe).reason, MoveSafety.scoreOverflow);
      expect(result.state, state);
      expect(jsonEncode(state.toJson()), before);
    });

    test('checked turnsUsed+1 overflows at JSON-safe bound', () {
      var overflow = false;
      checkedNonNegAdd(
        kJsonMaxSafeInteger,
        1,
        onOverflow: () => overflow = true,
      );
      expect(overflow, isTrue);
    });

    test('checked wave multiply overflows near JSON-safe bound', () {
      var overflow = false;
      checkedNonNegMul(
        kJsonMaxSafeInteger,
        2,
        onOverflow: () => overflow = true,
      );
      expect(overflow, isTrue);
      overflow = false;
      final ok = checkedNonNegMul(3, 100, onOverflow: () => overflow = true);
      expect(overflow, isFalse);
      expect(ok, 300);
    });

    test('rejected illegal tap preserves original state', () {
      final state = parseGameState(_v3Playable());
      final before = state;
      final result = applyMove(
        state,
        parseMove({
          'offerIndex': 0,
          'tap': [0, 0],
        }),
      );
      // First tap is empty — make occupied rejection instead.
      final occupied = parseGameState(
        _v3Playable()
          ..['cells'] = [
            [_pieceJson(), null],
            [null, null],
          ],
      );
      final rejected = applyMove(
        occupied,
        parseMove({
          'offerIndex': 0,
          'tap': [0, 0],
        }),
      ) as MoveRejected;
      expect(rejected.code, GameplayRejection.occupiedTap);
      expect(rejected.state, occupied);
      expect(before.score, 0);
      expect(result, isA<MoveApplied>());
    });
  });

  group('canonical_json_v3 independent vectors', () {
    test('CV-01 empty object', () {
      expect(canonicalJsonV3(<String, Object?>{}), '{}');
      expect(
        sha256HexOfUtf8('{}'),
        '44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a',
      );
    });

    test('CV-02 spent', () {
      const exact = '{"kind":"spent"}';
      expect(canonicalJsonV3({'kind': 'spent'}), exact);
      expect(
        sha256HexOfUtf8(exact),
        '684ab5937663746640cb17fa8b29254454be394376269cdaeca1743a7577fa82',
      );
    });

    test('CV-03 key order independence', () {
      const exact = '{"direction":"up","kind":"piece","shape":"circle"}';
      expect(
        canonicalJsonV3({
          'kind': 'piece',
          'shape': 'circle',
          'direction': 'up',
        }),
        exact,
      );
      expect(
        canonicalJsonV3({
          'shape': 'circle',
          'direction': 'up',
          'kind': 'piece',
        }),
        exact,
      );
      expect(
        sha256HexOfUtf8(exact),
        '1f18d4b9a43e29c7a72d1309f531088c32d792d4e6a31a9a7194637676916186',
      );
    });

    test('CV-04 null', () {
      expect(canonicalJsonV3(null), 'null');
      expect(
        sha256HexOfUtf8('null'),
        '74234e98afe7498fb5daf1f36ac2d78acc339464f950703b8c019892f982b90b',
      );
    });

    test('CV-05 zero', () {
      expect(canonicalJsonV3(0), '0');
      expect(
        sha256HexOfUtf8('0'),
        '5feceb66ffc86f38d952786c6d696c79c2dbc239dd4e91b46729d73a27fb57e9',
      );
    });

    test('CV-06 nine hundred', () {
      expect(canonicalJsonV3(900), '900');
      expect(
        sha256HexOfUtf8('900'),
        'bdc5d8a48c23897906b09a9a3680bd2e9c8b3121edbda36f949800f0959c8d55',
      );
    });

    test('CV-07 ended string', () {
      expect(canonicalJsonV3('ended'), '"ended"');
      expect(
        sha256HexOfUtf8('"ended"'),
        '0f27529487e95082cf0bd9f021be1ede2adc650b34db2ba96235d8805ad49bb3',
      );
    });

    test('CV-08 escaped quote', () {
      const exact = r'"a\"b"';
      expect(canonicalJsonV3('a"b'), exact);
      expect(
        sha256HexOfUtf8(exact),
        '8bbcb681750af483258c5ca72e83c5c397bf66aa01e7c7787c0d212fc1f6fa1d',
      );
    });

    test('CV-09 escaped backslash', () {
      const exact = r'"a\\b"';
      expect(canonicalJsonV3(r'a\b'), exact);
      expect(
        sha256HexOfUtf8(exact),
        'd6b4439bd2d0fecbb8aeb27d4370b0354683ea72adc84cca99b5fe80aa0b62d0',
      );
    });

    test('rejects non-ASCII and floats', () {
      expect(
        () => canonicalJsonV3('ç'),
        throwsA(isA<CanonicalJsonException>()),
      );
      expect(
        () => canonicalJsonV3(1.5),
        throwsA(isA<CanonicalJsonException>()),
      );
    });

    test('different values produce different digests', () {
      expect(
        sha256HexOfUtf8(canonicalJsonV3(0)),
        isNot(sha256HexOfUtf8(canonicalJsonV3(1))),
      );
      expect(
        sha256HexOfUtf8(canonicalJsonV3({'kind': 'spent'})),
        isNot(sha256HexOfUtf8(canonicalJsonV3({'kind': 'piece'}))),
      );
    });

    test('rejects integers outside JSON-safe domain', () {
      expect(
        () => canonicalJsonV3(kJsonMaxSafeInteger + 1),
        throwsA(isA<CanonicalJsonException>()),
      );
      expect(
        () => canonicalJsonV3(-(kJsonMaxSafeInteger + 1)),
        throwsA(isA<CanonicalJsonException>()),
      );
    });

    test('stateHashV3 requires v3', () {
      final v1 = parseGameState(_v1Minimal());
      expect(() => stateHashV3(v1), throwsA(isA<CanonicalJsonException>()));
      final v3 = parseGameState(_v3Playable());
      expect(stateHashV3(v3), hasLength(64));
    });
  });
}

Map<String, Object?> _pieceJson() => {'shape': 'circle', 'direction': 'right'};

Map<String, Object?> _offerPiece({
  String shape = 'circle',
  String direction = 'right',
}) => {'kind': 'piece', 'shape': shape, 'direction': direction};

Map<String, Object?> _v1Minimal() => {
  'rulesVersion': 'core-001.v1',
  'boardSize': 1,
  'moveLimit': 1,
  'blocked': <Object?>[],
  'cells': [
    [null],
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

Map<String, Object?> _v2TerminalNull() => {
  'rulesVersion': 'core-001.v2',
  'boardSize': 1,
  'moveLimit': 1,
  'blocked': <Object?>[],
  'cells': [
    [null],
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

Map<String, Object?> _v3Playable() => {
  'rulesVersion': 'core-001.v3',
  'boardSize': 2,
  'moveLimit': 5,
  'blocked': <Object?>[],
  'cells': [
    [null, null],
    [null, null],
  ],
  'offers': [
    _offerPiece(),
    _offerPiece(shape: 'diamond', direction: 'down'),
    _offerPiece(shape: 'triangle', direction: 'left'),
  ],
  'futurePieces': [
    {'shape': 'circle', 'direction': 'up'},
    {'shape': 'diamond', 'direction': 'left'},
  ],
  'turnsUsed': 0,
  'score': 0,
  'status': 'in_progress',
  'terminalReason': null,
};

Map<String, Object?> _v3LastFuture() {
  final json = _v3Playable();
  json['futurePieces'] = [
    {'shape': 'circle', 'direction': 'up'},
  ];
  return json;
}

Map<String, Object?> _v3EmptyStreamPlayable() {
  final json = _v3Playable();
  json['futurePieces'] = <Object?>[];
  return json;
}

Map<String, Object?> _v3OneSpentPlayable() => {
  'rulesVersion': 'core-001.v3',
  'boardSize': 2,
  'moveLimit': 5,
  'blocked': <Object?>[],
  'cells': [
    [null, null],
    [null, null],
  ],
  'offers': [
    {'kind': 'spent'},
    _offerPiece(shape: 'diamond', direction: 'down'),
    _offerPiece(shape: 'triangle', direction: 'left'),
  ],
  'futurePieces': <Object?>[],
  'turnsUsed': 1,
  'score': 0,
  'status': 'in_progress',
  'terminalReason': null,
};

Map<String, Object?> _v3BoardFullEnded() => {
  'rulesVersion': 'core-001.v3',
  'boardSize': 1,
  'moveLimit': 5,
  'blocked': <Object?>[],
  'cells': [
    [_pieceJson()],
  ],
  'offers': [
    {'kind': 'spent'},
    _offerPiece(shape: 'diamond', direction: 'down'),
    _offerPiece(shape: 'triangle', direction: 'left'),
  ],
  'futurePieces': <Object?>[],
  'turnsUsed': 1,
  'score': 0,
  'status': 'ended',
  'terminalReason': 'no_legal_moves',
};

Map<String, Object?> _v3MoveLimitReached() => {
  'rulesVersion': 'core-001.v3',
  'boardSize': 2,
  'moveLimit': 1,
  'blocked': <Object?>[],
  'cells': [
    [null, null],
    [null, null],
  ],
  'offers': [
    _offerPiece(),
    _offerPiece(shape: 'diamond', direction: 'down'),
    _offerPiece(shape: 'triangle', direction: 'left'),
  ],
  'futurePieces': <Object?>[],
  'turnsUsed': 1,
  'score': 0,
  'status': 'ended',
  'terminalReason': 'move_limit_reached',
};

Map<String, Object?> _v3AlmostFull() => {
  'rulesVersion': 'core-001.v3',
  'boardSize': 1,
  'moveLimit': 5,
  'blocked': <Object?>[],
  'cells': [
    [null],
  ],
  'offers': [
    _offerPiece(),
    _offerPiece(shape: 'diamond', direction: 'down'),
    _offerPiece(shape: 'triangle', direction: 'left'),
  ],
  'futurePieces': <Object?>[],
  'turnsUsed': 0,
  'score': 0,
  'status': 'in_progress',
  'terminalReason': null,
};

Map<String, Object?> _v3EarlyBoardFullEmptyStream() => _v3AlmostFull();

Map<String, Object?> _v3LastMovePlayable() => {
  'rulesVersion': 'core-001.v3',
  'boardSize': 2,
  'moveLimit': 1,
  'blocked': <Object?>[],
  'cells': [
    [null, null],
    [null, null],
  ],
  'offers': [
    _offerPiece(),
    _offerPiece(shape: 'diamond', direction: 'down'),
    _offerPiece(shape: 'triangle', direction: 'left'),
  ],
  'futurePieces': <Object?>[],
  'turnsUsed': 0,
  'score': 0,
  'status': 'in_progress',
  'terminalReason': null,
};

Map<String, Object?> _v3MatchReady() => {
  'rulesVersion': 'core-001.v3',
  'boardSize': 3,
  'moveLimit': 5,
  'blocked': <Object?>[],
  'cells': [
    [
      {'shape': 'circle', 'direction': 'up'},
      {'shape': 'circle', 'direction': 'up'},
      null,
    ],
    [null, null, null],
    [null, null, null],
  ],
  'offers': [
    _offerPiece(shape: 'circle', direction: 'left'),
    _offerPiece(shape: 'diamond', direction: 'down'),
    _offerPiece(shape: 'triangle', direction: 'up'),
  ],
  'futurePieces': [
    {'shape': 'diamond', 'direction': 'right'},
  ],
  'turnsUsed': 0,
  'score': 0,
  'status': 'in_progress',
  'terminalReason': null,
};

Map<String, Object?> _v3CascadeReopen() => {
  'rulesVersion': 'core-001.v3',
  'boardSize': 3,
  'moveLimit': 5,
  'blocked': <Object?>[],
  'cells': [
    [
      {'shape': 'circle', 'direction': 'up'},
      {'shape': 'circle', 'direction': 'up'},
      null,
    ],
    [
      {'shape': 'diamond', 'direction': 'down'},
      {'shape': 'triangle', 'direction': 'left'},
      {'shape': 'diamond', 'direction': 'up'},
    ],
    [
      {'shape': 'triangle', 'direction': 'right'},
      {'shape': 'diamond', 'direction': 'left'},
      {'shape': 'triangle', 'direction': 'down'},
    ],
  ],
  'offers': [
    _offerPiece(shape: 'circle', direction: 'left'),
    _offerPiece(shape: 'diamond', direction: 'down'),
    _offerPiece(shape: 'triangle', direction: 'up'),
  ],
  'futurePieces': [
    {'shape': 'diamond', 'direction': 'right'},
  ],
  'turnsUsed': 0,
  'score': 0,
  'status': 'in_progress',
  'terminalReason': null,
};

Map<String, Object?> _v3AllSpentEmptyBoard() => {
  'rulesVersion': 'core-001.v3',
  'boardSize': 2,
  'moveLimit': 5,
  'blocked': <Object?>[],
  'cells': [
    [null, null],
    [null, null],
  ],
  'offers': [
    {'kind': 'spent'},
    {'kind': 'spent'},
    {'kind': 'spent'},
  ],
  'futurePieces': <Object?>[],
  'turnsUsed': 2,
  'score': 0,
  'status': 'ended',
  'terminalReason': 'no_legal_moves',
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
