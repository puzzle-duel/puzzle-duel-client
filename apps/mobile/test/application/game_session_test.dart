import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/application/game_constants.dart';
import 'package:puzzle_duel_mobile/application/game_session.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

void main() {
  test('starts Easy/Medium/Hard rounds from UAT seed', () {
    final session = GameSession();
    for (final profile in DifficultyProfile.values) {
      expect(
        session.startRound(profile: profile, seed: kUatChallengeSeed),
        isTrue,
      );
      expect(session.view.canonicalState, isNotNull);
      expect(session.view.canonicalState!.boardSize, profile.boardSize);
      expect(session.view.phase, GameScreenPhase.playing);
      expect(session.view.seed, kUatChallengeSeed);
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
    final pre = session.view.canonicalState!;
    MoveApplied? captured;
    session.applyMoveOverride = (state, move) {
      final result = applyMove(state, move);
      if (result is MoveApplied) captured = result;
      return result;
    };

    // Find first empty non-blocked cell.
    Coordinate? tap;
    outer:
    for (var r = 0; r < pre.boardSize; r++) {
      for (var c = 0; c < pre.boardSize; c++) {
        final coord = Coordinate(row: r, column: c);
        if (pre.blocked.contains(coord)) continue;
        if (pre.cells[r][c] != null) continue;
        tap = coord;
        break outer;
      }
    }
    expect(tap, isNotNull);
    session.selectOffer(0);
    expect(session.submitTap(tap!), isTrue);
    expect(session.applyMoveCallCount, 1);
    expect(captured, isNotNull);
    expect(session.view.canonicalState, captured!.finalState);
    expect(session.view.isResolving, isTrue);
    expect(session.view.activeScript!.landing, captured!.landing);
  });

  test('rejection preserves original state', () {
    final session = GameSession();
    session.startRound(
      profile: DifficultyProfile.easy,
      seed: kUatChallengeSeed,
    );
    final pre = session.view.canonicalState!;
    // Tap a blocked cell if any, else occupied.
    Coordinate? illegal;
    if (pre.blocked.isNotEmpty) {
      illegal = pre.blocked.first;
    } else {
      outer:
      for (var r = 0; r < pre.boardSize; r++) {
        for (var c = 0; c < pre.boardSize; c++) {
          if (pre.cells[r][c] != null) {
            illegal = Coordinate(row: r, column: c);
            break outer;
          }
        }
      }
    }
    expect(illegal, isNotNull);
    session.selectOffer(0);
    session.submitTap(illegal!);
    expect(session.view.canonicalState, pre);
    expect(session.view.feedbackKind, MoveFeedbackKind.rejected);
    expect(session.view.phase, GameScreenPhase.playing);
  });

  test('second move during resolution is ignored', () {
    final session = GameSession();
    session.startRound(
      profile: DifficultyProfile.easy,
      seed: kUatChallengeSeed,
    );
    final pre = session.view.canonicalState!;
    Coordinate? tap;
    for (var r = 0; r < pre.boardSize; r++) {
      for (var c = 0; c < pre.boardSize; c++) {
        final coord = Coordinate(row: r, column: c);
        if (!pre.blocked.contains(coord) && pre.cells[r][c] == null) {
          tap = coord;
        }
      }
    }
    session.selectOffer(0);
    session.submitTap(tap!);
    final calls = session.applyMoveCallCount;
    session.selectOffer(1);
    expect(session.submitTap(tap), isFalse);
    expect(session.applyMoveCallCount, calls);
  });

  test('stale completeResolution does not affect newer generation', () {
    final session = GameSession();
    session.startRound(
      profile: DifficultyProfile.easy,
      seed: kUatChallengeSeed,
    );
    final pre = session.view.canonicalState!;
    Coordinate? tap;
    for (var r = 0; r < pre.boardSize; r++) {
      for (var c = 0; c < pre.boardSize; c++) {
        final coord = Coordinate(row: r, column: c);
        if (!pre.blocked.contains(coord) && pre.cells[r][c] == null) {
          tap = coord;
        }
      }
    }
    session.selectOffer(0);
    session.submitTap(tap!);
    final oldGen = session.view.generation;
    session.startRound(
      profile: DifficultyProfile.medium,
      seed: kUatChallengeSeed,
    );
    session.completeResolution(generation: oldGen);
    expect(session.view.phase, GameScreenPhase.playing);
    expect(session.view.profile, DifficultyProfile.medium);
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
    expect(session.view.feedbackCode, 'offer_unavailable');
  });
}
