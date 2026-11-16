import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/application/animation_script.dart';
import 'package:puzzle_duel_mobile/application/game_constants.dart';
import 'package:puzzle_duel_mobile/application/presentation_board.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

void main() {
  test(
    'projection from MoveApplied settles to final cells without re-rules',
    () {
      final generated = generateChallenge(
        ChallengeGenerationConfig.profile(DifficultyProfile.easy),
        kUatChallengeSeed,
      ) as GeneratedChallenge;

      // Exhaustively try offers/taps until a MoveApplied with waves or without.
      MoveApplied? applied;
      Piece? placed;
      outer:
      for (var offer = 0; offer < 3; offer++) {
        if (generated.state.offers[offer] == null) continue;
        for (var r = 0; r < generated.state.boardSize; r++) {
          for (var c = 0; c < generated.state.boardSize; c++) {
            final tap = Coordinate(row: r, column: c);
            if (generated.state.blocked.contains(tap)) continue;
            if (generated.state.cells[r][c] != null) continue;
            final result = applyMove(
              generated.state,
              Move(offerIndex: offer, tap: tap),
            );
            if (result is MoveApplied) {
              applied = result;
              placed = generated.state.offers[offer];
              break outer;
            }
          }
        }
      }
      expect(applied, isNotNull);
      expect(placed, isNotNull);

      final script = AnimationScript(
        generation: 1,
        resolutionId: 7,
        preState: generated.state,
        applied: applied!,
        placedPiece: placed!,
      );
      final board = PresentationBoard.fromGameState(script.preState);
      board.place(script.landing, script.placedPiece);
      for (final wave in script.waves) {
        board.clearCells(wave.cleared);
        board.applyMoves(wave.moved);
      }

      // Final occupied layout should match engine finalState cells.
      for (var r = 0; r < applied.finalState.boardSize; r++) {
        for (var c = 0; c < applied.finalState.boardSize; c++) {
          expect(board.pieceAt(r, c), applied.finalState.cells[r][c]);
        }
      }

      final steps = buildAnimationSteps(script);
      expect(steps.first.kind, AnimationStepKind.place);
      expect(steps.last.kind, AnimationStepKind.settle);
    },
  );
}
