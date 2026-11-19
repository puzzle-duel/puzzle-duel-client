import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/application/game_session.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

void main() {
  const slots = <(String, DifficultyProfile, int, int, int, int)>[
    ('E1.json', DifficultyProfile.easy, 0, 5, 15, 1),
    ('E2.json', DifficultyProfile.easy, 1, 5, 15, 1),
    ('E3.json', DifficultyProfile.easy, 2, 5, 15, 1),
    ('M1.json', DifficultyProfile.medium, 0, 6, 12, 2),
    ('M2.json', DifficultyProfile.medium, 1, 6, 12, 2),
    ('H1.json', DifficultyProfile.hard, 5, 7, 10, 4),
  ];

  final layouts = <String>{};

  for (final slot in slots) {
    test('${slot.$1} is a distinct gen-001.v1 board the v3 engine can finish', () {
      final document = jsonDecode(
        File('test/tournament/fixtures/v4/${slot.$1}').readAsStringSync(),
      ) as Map<String, Object?>;
      final pinned = document['initialState']! as Map<String, Object?>;
      final generated = generateChallenge(
        ChallengeGenerationConfig.profile(slot.$2),
        slot.$3,
      );
      expect(generated, isA<GeneratedChallenge>());
      final source = (generated as GeneratedChallenge).state;
      expect(source.rulesVersion, RulesVersion.core001V2);
      expect(source.boardSize, slot.$4);
      expect(source.moveLimit, slot.$5);
      expect(source.blocked, hasLength(slot.$6));
      _expectSameLayout(source, pinned);

      final initial = parseInitialGameState(pinned);
      expect(initial.rulesVersion, RulesVersion.core001V3);
      expect(initial.boardSize, slot.$4);
      expect(initial.moveLimit, slot.$5);
      final layout = jsonEncode(initial.toJson()['cells']);
      expect(layouts.contains(layout), isFalse);
      layouts.add(layout);

      final deltas = <int>{};
      Coordinate? legal;
      for (var offer = 0; offer < 3; offer++) {
        for (var row = 0; row < initial.boardSize; row++) {
          for (var column = 0; column < initial.boardSize; column++) {
            final tap = Coordinate(row: row, column: column);
            final result = applyMove(initial, Move(offerIndex: offer, tap: tap));
            if (result is MoveApplied) {
              deltas.add(result.scoreDelta);
              legal ??= tap;
            }
          }
        }
      }
      expect(legal, isNotNull);
      expect(deltas.length, greaterThan(1));

      final v2 = applyMove(source, Move(offerIndex: 0, tap: legal!));
      final v3 = applyMove(initial, Move(offerIndex: 0, tap: legal));
      expect(v2, isA<MoveApplied>());
      expect(v3, isA<MoveApplied>());
      final v2Done = (v2 as MoveApplied).finalState;
      final v3Done = (v3 as MoveApplied).finalState;
      expect(v3Done.score, v2Done.score);
      expect(v3Done.turnsUsed, v2Done.turnsUsed);
      _expectSameCells(v2Done, v3Done);

      Coordinate? occupied;
      for (var row = 0; row < initial.boardSize && occupied == null; row++) {
        for (var column = 0; column < initial.boardSize; column++) {
          if (initial.cells[row][column] != null) {
            occupied = Coordinate(row: row, column: column);
            break;
          }
        }
      }
      expect(occupied, isNotNull);
      final rejected = applyMove(initial, Move(offerIndex: 0, tap: occupied!));
      expect(rejected, isA<MoveRejected>());
      expect((rejected as MoveRejected).state.score, 0);

      var cursor = initial;
      var steps = 0;
      while (cursor.status == GameStatus.inProgress && steps < slot.$5) {
        MoveApplied? played;
        for (var offer = 0; offer < 3 && played == null; offer++) {
          for (var row = 0; row < cursor.boardSize && played == null; row++) {
            for (var column = 0; column < cursor.boardSize; column++) {
              final result = applyMove(
                cursor,
                Move(offerIndex: offer, tap: Coordinate(row: row, column: column)),
              );
              if (result is MoveApplied) {
                played = result;
                break;
              }
            }
          }
        }
        expect(played, isNotNull);
        cursor = played!.finalState;
        steps += 1;
      }
      expect(cursor.status, GameStatus.ended);
      expect(cursor.terminalReason, TerminalReason.moveLimitReached);
      expect(cursor.turnsUsed, slot.$5);
    });
  }

  for (final name in ['E1.json', 'M1.json', 'H1.json']) {
    test('$name touch uses the selected cell and renders the server board', () {
      final pinned = (jsonDecode(
        File('test/tournament/fixtures/v4/$name').readAsStringSync(),
      ) as Map<String, Object?>)['initialState']! as Map<String, Object?>;
      final initial = parseInitialGameState(pinned);
      final session = GameSession();
      int? sentOffer;
      Coordinate? sentTap;
      session.onAuthoritativeTap = (offer, tap) async {
        sentOffer = offer;
        sentTap = tap;
      };
      session.showAuthoritative(initial);
      session.selectOffer(0);
      expect(session.view.selectedOfferIndex, 0);

      Coordinate? legal;
      final piece = initial.offers[0].pieceOrNull!;
      for (var row = 0; row < initial.boardSize && legal == null; row++) {
        for (var column = 0; column < initial.boardSize; column++) {
          final tap = Coordinate(row: row, column: column);
          if (canPlaceAt(
            boardSize: initial.boardSize,
            cells: initial.cells,
            blocked: initial.blocked,
            piece: piece,
            tap: tap,
          )) {
            legal = tap;
            break;
          }
        }
      }
      expect(session.submitTap(legal!), isTrue);
      expect(sentOffer, 0);
      expect(sentTap, legal);
      expect(session.applyMoveCallCount, 0);
      expect(session.view.score, 0);

      final applied = applyMove(initial, Move(offerIndex: 0, tap: legal));
      expect(applied, isA<MoveApplied>());
      final server = (applied as MoveApplied).finalState;
      session.showAuthoritative(server);
      expect(session.view.canonicalState!.toJson(), server.toJson());
      expect(session.view.score, server.score);
      expect(session.view.selectedOfferIndex, isNull);
      expect(session.applyMoveCallCount, 0);
    });
  }
}

void _expectSameLayout(GameState source, Map<String, Object?> pinned) {
  expect(pinned['boardSize'], source.boardSize);
  expect(pinned['moveLimit'], source.moveLimit);
  final cells = pinned['cells']! as List;
  for (var row = 0; row < source.boardSize; row++) {
    final line = cells[row] as List;
    for (var column = 0; column < source.boardSize; column++) {
      final piece = source.cells[row][column];
      final json = line[column];
      if (piece == null) {
        expect(json, isNull);
      } else {
        final map = json as Map;
        expect(map['shape'], piece.shape.wire);
        expect(map['direction'], piece.direction.wire);
      }
    }
  }
  final offers = pinned['offers']! as List;
  for (var index = 0; index < 3; index++) {
    final map = offers[index] as Map;
    final piece = source.offers[index].pieceOrNull!;
    expect(map['kind'], 'piece');
    expect(map['shape'], piece.shape.wire);
    expect(map['direction'], piece.direction.wire);
  }
  final future = pinned['futurePieces']! as List;
  expect(future, hasLength(source.futurePieces.length));
  for (var index = 0; index < future.length; index++) {
    final map = future[index] as Map;
    expect(map['shape'], source.futurePieces[index].shape.wire);
    expect(map['direction'], source.futurePieces[index].direction.wire);
  }
  final blocked = pinned['blocked']! as List;
  expect(blocked, hasLength(source.blocked.length));
  for (var index = 0; index < blocked.length; index++) {
    final pair = blocked[index] as List;
    expect(pair[0], source.blocked[index].row);
    expect(pair[1], source.blocked[index].column);
  }
}

void _expectSameCells(GameState left, GameState right) {
  expect(right.boardSize, left.boardSize);
  for (var row = 0; row < left.boardSize; row++) {
    for (var column = 0; column < left.boardSize; column++) {
      final a = left.cells[row][column];
      final b = right.cells[row][column];
      if (a == null || b == null) {
        expect(b, a);
      } else {
        expect(b.shape, a.shape);
        expect(b.direction, a.direction);
      }
    }
  }
}
