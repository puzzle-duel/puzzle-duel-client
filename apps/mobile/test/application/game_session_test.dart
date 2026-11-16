import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/application/game_constants.dart';
import 'package:puzzle_duel_mobile/application/game_session.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

Coordinate? firstEmpty(GameState state) {
  for (var r = 0; r < state.boardSize; r++) {
    for (var c = 0; c < state.boardSize; c++) {
      final coord = Coordinate(row: r, column: c);
      if (!state.blocked.contains(coord) && state.cells[r][c] == null) {
        return coord;
      }
    }
  }
  return null;
}

({int offer, Coordinate tap, MoveApplied applied})? firstLegalApplied(
  GameState state,
) {
  for (var offer = 0; offer < 3; offer++) {
    if (!state.offers[offer].isSelectable) continue;
    for (var r = 0; r < state.boardSize; r++) {
      for (var c = 0; c < state.boardSize; c++) {
        final tap = Coordinate(row: r, column: c);
        if (state.blocked.contains(tap) || state.cells[r][c] != null) continue;
        final result = applyMove(state, Move(offerIndex: offer, tap: tap));
        if (result is MoveApplied) {
          return (offer: offer, tap: tap, applied: result);
        }
      }
    }
  }
  return null;
}

void main() {
  test('starts Easy/Medium/Hard rounds from UAT seed', () {
    final session = GameSession();
    for (final profile in DifficultyProfile.values) {
      expect(
        session.startRound(profile: profile, seed: kUatChallengeSeed),
        isTrue,
      );
      expect(session.view.canonicalState!.boardSize, profile.boardSize);
      expect(session.view.phase, GameScreenPhase.playing);
    }
  });

  test('initial state equals generated challenge', () {
    final session = GameSession();
    session.startRound(
      profile: DifficultyProfile.easy,
      seed: kUatChallengeSeed,
    );
    final a = session.view.canonicalState!;
    final again = GameSession()
      ..startRound(profile: DifficultyProfile.easy, seed: kUatChallengeSeed);
    expect(again.view.canonicalState, a);
  });

  test('legal tap invokes applyMove once and respects landing', () {
    final session = GameSession();
    session.startRound(
      profile: DifficultyProfile.easy,
      seed: kUatChallengeSeed,
    );
    final legal = firstLegalApplied(session.view.canonicalState!)!;
    MoveApplied? captured;
    session.applyMoveOverride = (state, move) {
      final result = applyMove(state, move);
      if (result is MoveApplied) captured = result;
      return result;
    };
    session.selectOffer(legal.offer);
    expect(session.submitTap(legal.tap), isTrue);
    expect(session.applyMoveCallCount, 1);
    expect(session.view.canonicalState, captured!.finalState);
    expect(session.view.isResolving, isTrue);
    expect(session.view.activeScript!.landing, captured!.landing);
    expect(session.view.activeResolutionId, greaterThan(0));
    expect(
      session.view.activeScript!.resolutionId,
      session.view.activeResolutionId,
    );
  });

  test('rejection preserves original state', () {
    final session = GameSession();
    session.startRound(
      profile: DifficultyProfile.easy,
      seed: kUatChallengeSeed,
    );
    final pre = session.view.canonicalState!;
    final illegal = pre.blocked.isNotEmpty
        ? pre.blocked.first
        : firstEmpty(pre)!;
    // Prefer blocked; if tapping empty would apply, force blocked when present.
    session.selectOffer(0);
    if (pre.blocked.isNotEmpty) {
      session.submitTap(pre.blocked.first);
      expect(session.view.canonicalState, pre);
      expect(session.view.feedbackKind, MoveFeedbackKind.rejected);
    } else {
      // Occupied tap
      Coordinate? occupied;
      for (var r = 0; r < pre.boardSize; r++) {
        for (var c = 0; c < pre.boardSize; c++) {
          if (pre.cells[r][c] != null) {
            occupied = Coordinate(row: r, column: c);
          }
        }
      }
      session.submitTap(occupied ?? illegal);
      expect(session.view.canonicalState, pre);
    }
  });

  test('second move during resolution is ignored', () {
    final session = GameSession();
    session.startRound(
      profile: DifficultyProfile.easy,
      seed: kUatChallengeSeed,
    );
    final legal = firstLegalApplied(session.view.canonicalState!)!;
    session.selectOffer(legal.offer);
    session.submitTap(legal.tap);
    final calls = session.applyMoveCallCount;
    session.selectOffer(1);
    expect(session.submitTap(legal.tap), isFalse);
    expect(session.applyMoveCallCount, calls);
  });

  test('stale resolution callback cannot complete a newer move', () {
    final session = GameSession();
    session.startRound(
      profile: DifficultyProfile.easy,
      seed: kUatChallengeSeed,
    );

    final a = firstLegalApplied(session.view.canonicalState!)!;
    session.selectOffer(a.offer);
    session.submitTap(a.tap);
    final gen = session.view.generation;
    final resolutionA = session.view.activeResolutionId;
    final canonicalAfterA = session.view.canonicalState!;

    session.completeResolution(generation: gen, resolutionId: resolutionA);
    expect(session.view.acceptsInput, isTrue);

    final b = firstLegalApplied(session.view.canonicalState!)!;
    session.selectOffer(b.offer);
    session.submitTap(b.tap);
    final resolutionB = session.view.activeResolutionId;
    expect(resolutionB, isNot(equals(resolutionA)));
    expect(session.view.isResolving, isTrue);
    final canonicalDuringB = session.view.canonicalState!;

    // Delayed completion from move A must not unlock/finish B.
    session.completeResolution(generation: gen, resolutionId: resolutionA);
    expect(session.view.isResolving, isTrue);
    expect(session.view.activeResolutionId, resolutionB);
    expect(session.view.canonicalState, canonicalDuringB);
    expect(session.view.acceptsInput, isFalse);

    session.completeResolution(generation: gen, resolutionId: resolutionB);
    expect(session.view.isResolving, isFalse);
    expect(session.view.canonicalState, canonicalDuringB);
    expect(
      session.view.acceptsInput || session.view.phase == GameScreenPhase.ended,
      isTrue,
    );
    // Canonical never rolled back to pre-B or pre-A incorrectly.
    expect(session.view.canonicalState, isNot(equals(canonicalAfterA)));
  });

  test('stale callback after restart is ignored', () {
    final session = GameSession();
    session.startRound(
      profile: DifficultyProfile.easy,
      seed: kUatChallengeSeed,
    );
    final a = firstLegalApplied(session.view.canonicalState!)!;
    session.selectOffer(a.offer);
    session.submitTap(a.tap);
    final oldGen = session.view.generation;
    final oldRes = session.view.activeResolutionId;

    session.startRound(
      profile: DifficultyProfile.medium,
      seed: kUatChallengeSeed,
    );
    expect(session.view.phase, GameScreenPhase.playing);
    expect(session.view.activeResolutionId, 0);

    session.completeResolution(generation: oldGen, resolutionId: oldRes);
    expect(session.view.phase, GameScreenPhase.playing);
    expect(session.view.profile, DifficultyProfile.medium);
    expect(session.view.canonicalState!.boardSize, 6);
  });

  test('duplicate completeResolution is harmless', () {
    final session = GameSession();
    session.startRound(
      profile: DifficultyProfile.easy,
      seed: kUatChallengeSeed,
    );
    final legal = firstLegalApplied(session.view.canonicalState!)!;
    session.selectOffer(legal.offer);
    session.submitTap(legal.tap);
    final gen = session.view.generation;
    final res = session.view.activeResolutionId;
    session.completeResolution(generation: gen, resolutionId: res);
    final phase = session.view.phase;
    final state = session.view.canonicalState;
    session.completeResolution(generation: gen, resolutionId: res);
    expect(session.view.phase, phase);
    expect(session.view.canonicalState, state);
  });

  test('unsafe result fails closed without changing state', () {
    final session = GameSession();
    session.startRound(
      profile: DifficultyProfile.easy,
      seed: kUatChallengeSeed,
    );
    final pre = session.view.canonicalState!;
    session.applyMoveOverride = (state, move) {
      return MoveUnsafe(reason: MoveSafety.offerUnavailable, state: state);
    };
    session.selectOffer(0);
    session.submitTap(Coordinate(row: 0, column: 0));
    expect(session.view.canonicalState, pre);
    expect(session.view.feedbackKind, MoveFeedbackKind.unsafe);
  });

  test('null offer slots are not selectable', () {
    final session = GameSession();
    session.startRound(
      profile: DifficultyProfile.easy,
      seed: kUatChallengeSeed,
    );
    // Inject a null middle offer into a playing session via override path:
    // generate until we can simulate by selecting only available slots.
    session.selectOffer(0);
    expect(session.view.selectedOfferIndex, 0);
    // Selecting an index with a null piece must no-op; forge via temporary state
    // is engine-owned, so verify unavailable index bounds and empty-slot UI contract
    // by rejecting index that has null when present after a v2 terminal move.
    final state = session.view.canonicalState!;
    for (var i = 0; i < 3; i++) {
      if (!state.offers[i].isSelectable) {
        session.selectOffer(i);
        expect(session.view.selectedOfferIndex, isNot(i));
      }
    }
  });

  test('one-wave and multi-wave scripts preserve canonical wave order', () {
    // Search seeds for at least one MoveApplied with waves.
    MoveApplied? withWaves;
    GameState? pre;
    Piece? placed;
    for (var seed = 0; seed < 200 && withWaves == null; seed++) {
      final generated = generateChallenge(
        ChallengeGenerationConfig.profile(DifficultyProfile.easy),
        seed,
      );
      if (generated is! GeneratedChallenge) continue;
      final legal = firstLegalApplied(generated.state);
      if (legal == null) continue;
      if (legal.applied.waves.isEmpty) continue;
      withWaves = legal.applied;
      pre = generated.state;
      placed = generated.state.offers[legal.offer].pieceOrNull;
    }
    expect(withWaves, isNotNull);
    expect(placed, isNotNull);

    var expectedWave = 1;
    for (final wave in withWaves!.waves) {
      expect(wave.wave, expectedWave);
      expectedWave += 1;
    }

    // Projection still ends at finalState.
    final board = PresentationBoardProjection(pre!, placed!, withWaves);
    expect(board.matches(withWaves.finalState), isTrue);
  });
}

/// Tiny helper to avoid importing presentation in naming clash — inline.
final class PresentationBoardProjection {
  PresentationBoardProjection(GameState pre, Piece placed, MoveApplied applied)
    : cells = [
        for (final row in pre.cells) [for (final cell in row) cell],
      ] {
    cells[applied.landing.row][applied.landing.column] = placed;
    for (final wave in applied.waves) {
      for (final c in wave.cleared) {
        cells[c.row][c.column] = null;
      }
      for (final m in wave.moved) {
        cells[m.from.row][m.from.column] = null;
      }
      for (final m in wave.moved) {
        cells[m.to.row][m.to.column] = Piece(
          shape: m.shape,
          direction: m.direction,
        );
      }
    }
  }

  final List<List<Piece?>> cells;

  bool matches(GameState finalState) {
    for (var r = 0; r < finalState.boardSize; r++) {
      for (var c = 0; c < finalState.boardSize; c++) {
        if (cells[r][c] != finalState.cells[r][c]) return false;
      }
    }
    return true;
  }
}
