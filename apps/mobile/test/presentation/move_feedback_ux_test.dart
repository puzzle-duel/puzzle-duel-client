import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/app/puzzle_duel_app.dart';
import 'package:puzzle_duel_mobile/application/animation_script.dart';
import 'package:puzzle_duel_mobile/application/game_constants.dart';
import 'package:puzzle_duel_mobile/application/game_session.dart';
import 'package:puzzle_duel_mobile/presentation/audio/game_sfx.dart';
import 'package:puzzle_duel_mobile/presentation/feedback/move_feedback_copy.dart';
import 'package:puzzle_duel_mobile/presentation/game/board/puzzle_board_game.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

void main() {
  group('MoveFeedbackCopy', () {
    test('maps occupied blocked and no-selection', () {
      expect(
        MoveFeedbackCopy.playerMessage(
          kind: MoveFeedbackKind.rejected,
          code: 'occupied_tap',
        ),
        'That slot is taken!',
      );
      expect(
        MoveFeedbackCopy.playerMessage(
          kind: MoveFeedbackKind.rejected,
          code: 'blocked_tap',
        ),
        'That tile is blocked.',
      );
      expect(
        MoveFeedbackCopy.playerMessage(
          kind: MoveFeedbackKind.rejected,
          code: 'select_offer_first',
        ),
        'Pick a piece first.',
      );
      expect(
        MoveFeedbackCopy.playerMessage(
          kind: MoveFeedbackKind.rejected,
          code: 'no_offer_selected',
        ),
        'Pick a piece first.',
      );
      expect(
        MoveFeedbackCopy.playerMessage(
          kind: MoveFeedbackKind.unsafe,
          code: 'offer_unavailable',
        ),
        'That piece isn’t available.',
      );
      expect(
        MoveFeedbackCopy.playerMessage(
          kind: MoveFeedbackKind.unsafe,
          code: 'unresolved_pre_move_match',
        ),
        'That move can’t be played.',
      );
    });

    test('never returns raw technical codes', () {
      for (final code in [
        'occupied_tap',
        'blocked_tap',
        'select_offer_first',
        'no_offer_selected',
        'game_ended',
        'tap_out_of_bounds',
      ]) {
        final text = MoveFeedbackCopy.playerMessage(
          kind: MoveFeedbackKind.rejected,
          code: code,
        )!;
        expect(text.contains(code), isFalse);
        expect(MoveFeedbackCopy.looksTechnical(text), isFalse);
        expect(text.toLowerCase().contains('move rejected'), isFalse);
      }
    });
  });

  group('player-facing feedback toast', () {
    testWidgets('shows mapped copy not wire code for no selection', (
      tester,
    ) async {
      final sfx = RecordingGameSfx();
      final session = GameSession()
        ..startRound(profile: DifficultyProfile.easy, seed: kUatChallengeSeed);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(400, 900)),
          child: PuzzleDuelApp(session: session, sfx: sfx),
        ),
      );
      await tester.pump();

      final empty = _firstEmpty(session.view.canonicalState!);
      await tester.tap(
        find.byKey(ValueKey('board-ink-${empty.row}-${empty.column}')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Pick a piece first.'), findsOneWidget);
      expect(find.textContaining('occupied_tap'), findsNothing);
      expect(find.textContaining('Move rejected:'), findsNothing);
      expect(find.textContaining('select_offer_first'), findsNothing);
      expect(sfx.events, contains(GameSfxEvent.reject));
    });

    testWidgets('replaces toast instead of stacking', (tester) async {
      final sfx = RecordingGameSfx();
      final session = GameSession()
        ..startRound(profile: DifficultyProfile.easy, seed: kUatChallengeSeed);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(400, 900)),
          child: PuzzleDuelApp(session: session, sfx: sfx),
        ),
      );
      await tester.pump();

      final state = session.view.canonicalState!;
      Coordinate? empty;
      Coordinate? occupied;
      for (var r = 0; r < state.boardSize; r++) {
        for (var c = 0; c < state.boardSize; c++) {
          final tap = Coordinate(row: r, column: c);
          if (state.blocked.contains(tap)) continue;
          if (state.cells[r][c] == null) {
            empty ??= tap;
          } else {
            occupied ??= tap;
          }
        }
      }

      await tester.tap(
        find.byKey(ValueKey('board-ink-${empty!.row}-${empty.column}')),
      );
      await tester.pump();
      expect(find.text('Pick a piece first.'), findsOneWidget);

      session.selectOffer(0);
      await tester.pump();
      if (occupied != null) {
        await tester.tap(
          find.byKey(
            ValueKey('board-ink-${occupied.row}-${occupied.column}'),
          ),
        );
        await tester.pump();
        expect(find.text('That slot is taken!'), findsOneWidget);
        expect(find.text('Pick a piece first.'), findsNothing);
        expect(find.text('That slot is taken!'), findsOneWidget);
      }
    });

    testWidgets('does not stack messages during resolving lock', (
      tester,
    ) async {
      final sfx = RecordingGameSfx();
      final session = GameSession()
        ..startRound(profile: DifficultyProfile.easy, seed: kUatChallengeSeed);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(400, 900)),
          child: PuzzleDuelApp(session: session, sfx: sfx),
        ),
      );
      await tester.pump();

      final empty = _firstEmpty(session.view.canonicalState!);
      await tester.tap(
        find.byKey(ValueKey('board-ink-${empty.row}-${empty.column}')),
      );
      await tester.pump();
      expect(find.text('Pick a piece first.'), findsOneWidget);
      final rejectCount = sfx.events
          .where((e) => e == GameSfxEvent.reject)
          .length;

      session.selectOffer(0);
      await tester.pump();
      await tester.tap(
        find.byKey(ValueKey('board-ink-${empty.row}-${empty.column}')),
      );
      await tester.pump();
      expect(session.view.isResolving, isTrue);
      // Toast dismisses when resolution lock engages (no stack).
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Pick a piece first.'), findsNothing);

      session.notifyListeners();
      await tester.pump();
      expect(find.text('Pick a piece first.'), findsNothing);
      expect(find.textContaining('Move rejected:'), findsNothing);
      expect(
        sfx.events.where((e) => e == GameSfxEvent.reject).length,
        rejectCount,
      );
    });
  });

  group('GameSfx', () {
    test('sfxForClearWave maps first vs cascade', () {
      expect(sfxForClearWave(1), GameSfxEvent.clear);
      expect(sfxForClearWave(2), GameSfxEvent.cascade);
      expect(sfxForClearWave(3), GameSfxEvent.cascade);
    });

    test('records place clear cascade chainComplete', () {
      final sfx = RecordingGameSfx();
      sfx.play(GameSfxEvent.place);
      sfx.play(sfxForClearWave(1));
      sfx.play(sfxForClearWave(2));
      sfx.play(GameSfxEvent.chainComplete);
      expect(sfx.events, [
        GameSfxEvent.place,
        GameSfxEvent.clear,
        GameSfxEvent.cascade,
        GameSfxEvent.chainComplete,
      ]);
    });

    test('records events and respects mute', () {
      final sfx = RecordingGameSfx();
      sfx.play(GameSfxEvent.place);
      sfx.muted = true;
      sfx.play(GameSfxEvent.reject);
      expect(sfx.events, [GameSfxEvent.place]);
    });

    test('AssetGameSfx play does not throw when audio fails', () {
      final sfx = AssetGameSfx(
        playerFactory: () => throw Exception('audio unavailable'),
      );
      expect(() => sfx.play(GameSfxEvent.clear), returnsNormally);
      expect(() => sfx.play(GameSfxEvent.reject), returnsNormally);
      sfx.dispose();
    });

    testWidgets('board animation steps emit place clear cascade chain', (
      tester,
    ) async {
      final events = <GameSfxEvent>[];
      final game = PuzzleBoardGame(
        onResolutionComplete: ({required generation, required resolutionId}) {},
        onSfx: events.add,
      );
      final piece = Piece(shape: Shape.circle, direction: Direction.right);
      final landing = Coordinate(row: 0, column: 0);
      game.debugRunSteps([
        AnimationStep.place(landing, piece),
        AnimationStep.clear(1, [landing]),
        AnimationStep.clear(2, [Coordinate(row: 0, column: 1)]),
        const AnimationStep.settle(),
      ]);
      await tester.pump(const Duration(seconds: 2));
      expect(events, [
        GameSfxEvent.place,
        GameSfxEvent.clear,
        GameSfxEvent.cascade,
        GameSfxEvent.chainComplete,
      ]);
      game.disposeGame();
    });
  });
}

Coordinate _firstEmpty(GameState state) {
  for (var r = 0; r < state.boardSize; r++) {
    for (var c = 0; c < state.boardSize; c++) {
      final tap = Coordinate(row: r, column: c);
      if (!state.blocked.contains(tap) && state.cells[r][c] == null) {
        return tap;
      }
    }
  }
  return Coordinate(row: 0, column: 0);
}
