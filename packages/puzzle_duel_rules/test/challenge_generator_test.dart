import 'dart:convert';
import 'dart:io';

import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';
import 'package:test/test.dart';

void main() {
  group('golden fixtures from independent Python reference', () {
    for (final file in _fixtureFiles()) {
      test(file.uri.pathSegments.last, () {
        final expected = (jsonDecode(file.readAsStringSync()) as Map)
            .cast<String, Object?>();
        final profile = DifficultyProfile.tryParse(expected['profile'])!;
        final seed = expected['seed'] as int;
        final result = generateChallenge(
          ChallengeGenerationConfig.profile(profile),
          seed,
        );
        expect(result, isA<GeneratedChallenge>());
        final challenge = result as GeneratedChallenge;
        expect(_normalize(challenge.toJson()), _normalize(expected));
      });
    }
  });

  test('same seed reproduces byte-identical JSON', () {
    final first = generateChallenge(
      ChallengeGenerationConfig.profile(DifficultyProfile.easy),
      42,
    ) as GeneratedChallenge;
    final second = generateChallenge(
      ChallengeGenerationConfig.profile(DifficultyProfile.easy),
      42,
    ) as GeneratedChallenge;
    expect(jsonEncode(first.toJson()), jsonEncode(second.toJson()));
    expect(first, isNot(same(second)));
    expect(first.state, second.state);
  });

  test('medium seed 123456789 survives a rejected board attempt', () {
    // Independent reference recorded attemptsUsed=2 for this vector.
    final challenge = generateChallenge(
      ChallengeGenerationConfig.profile(DifficultyProfile.medium),
      123456789,
    ) as GeneratedChallenge;
    expect(challenge.state.blocked, hasLength(2));
    expect(challenge.state.hasOrthogonalRun, isFalse);
    parseInitialGameState(challenge.state.toJson());
  });

  test('structural invariants across Easy Medium Hard seeds', () {
    for (final profile in DifficultyProfile.values) {
      for (final seed in const [0, 1, 42, 4294967295]) {
        final challenge = generateChallenge(
          ChallengeGenerationConfig.profile(profile),
          seed,
        ) as GeneratedChallenge;
        final state = challenge.state;
        expect(state.boardSize, profile.boardSize);
        expect(state.moveLimit, profile.moveLimit);
        expect(state.blocked, hasLength(profile.obstacleCount));
        expect(state.rulesVersion, RulesVersion.core001V2);
        expect(challenge.generatorVersion, GeneratorVersion.gen001V1);
        expect(state.turnsUsed, 0);
        expect(state.score, 0);
        expect(state.status, GameStatus.inProgress);
        expect(state.offers, hasLength(3));
        expect(state.offers, everyElement(isA<OfferLive>()));
        expect(state.futurePieces, hasLength(profile.moveLimit - 1));
        expect(state.hasOrthogonalRun, isFalse);
        _assertBlockedSortedUnique(state);
        expect(_occupiedCount(state.cells), profile.occupiedCount);
        parseInitialGameState(state.toJson());
        expect(
          () => (state.cells[0] as List).add(null),
          throwsUnsupportedError,
        );
      }
    }
  });

  test('invalid configurations fail closed before RNG work', () {
    expect(
      generateChallenge(
        ChallengeGenerationConfig.profile(DifficultyProfile.easy),
        -1,
      ),
      isA<ChallengeGenerationFailure>().having(
        (failure) => failure.code,
        'code',
        ChallengeGenerationError.invalidConfig,
      ),
    );
    expect(
      generateChallenge(
        ChallengeGenerationConfig.profile(DifficultyProfile.easy),
        4294967296,
      ),
      isA<ChallengeGenerationFailure>(),
    );
    expect(
      generateChallenge(
        const ChallengeGenerationConfig(
          profile: DifficultyProfile.easy,
          rulesVersion: RulesVersion.core001V1,
        ),
        0,
      ),
      isA<ChallengeGenerationFailure>(),
    );
    expect(
      generateChallenge(
        const ChallengeGenerationConfig(
          profile: DifficultyProfile.easy,
          obstacleCount: 99,
        ),
        0,
      ),
      isA<ChallengeGenerationFailure>(),
    );
  });

  test('generation_exhausted returns no partial challenge', () {
    // Independent reference: medium seed 123456789 rejects attempt 1.
    final exhausted = generateChallenge(
      ChallengeGenerationConfig.profile(DifficultyProfile.medium),
      123456789,
      maxAttempts: 1,
    );
    expect(
      exhausted,
      isA<ChallengeGenerationFailure>().having(
        (failure) => failure.code,
        'code',
        ChallengeGenerationError.generationExhausted,
      ),
    );
  });

  test('applyMove works on generated Easy Medium Hard boards', () {
    for (final profile in DifficultyProfile.values) {
      final challenge = generateChallenge(
        ChallengeGenerationConfig.profile(profile),
        0,
      ) as GeneratedChallenge;
      final state = challenge.state;
      Coordinate? tap;
      outer:
      for (var row = 0; row < state.boardSize; row++) {
        for (var column = 0; column < state.boardSize; column++) {
          final blocked = state.blocked.any(
            (cell) => cell.row == row && cell.column == column,
          );
          if (!blocked && state.cells[row][column] == null) {
            tap = Coordinate(row: row, column: column);
            break outer;
          }
        }
      }
      expect(tap, isNotNull);
      final result = applyMove(state, Move(offerIndex: 0, tap: tap!));
      expect(result, isA<MoveApplied>());
      final applied = result as MoveApplied;
      expect(applied.finalState.turnsUsed, 1);
      expect(applied.finalState.score, greaterThanOrEqualTo(state.score));
    }
  });
}

List<File> _fixtureFiles() {
  final dir = Directory(
    '${Directory.current.path}/../../docs/contracts/generator/gen-001.v1/fixtures',
  );
  return dir
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.json'))
      .toList()
    ..sort((left, right) => left.path.compareTo(right.path));
}

Object? _normalize(Object? value) => jsonDecode(jsonEncode(value));

void _assertBlockedSortedUnique(GameState state) {
  final seen = <String>{};
  Coordinate? previous;
  for (final cell in state.blocked) {
    final key = '${cell.row},${cell.column}';
    expect(seen.add(key), isTrue);
    expect(cell.row, inInclusiveRange(0, state.boardSize - 1));
    expect(cell.column, inInclusiveRange(0, state.boardSize - 1));
    expect(state.cells[cell.row][cell.column], isNull);
    if (previous != null) {
      final ordered =
          cell.row > previous.row ||
          (cell.row == previous.row && cell.column > previous.column);
      expect(ordered, isTrue);
    }
    previous = cell;
  }
}

int _occupiedCount(List<List<Piece?>> cells) {
  var count = 0;
  for (final row in cells) {
    for (final cell in row) {
      if (cell != null) count += 1;
    }
  }
  return count;
}
