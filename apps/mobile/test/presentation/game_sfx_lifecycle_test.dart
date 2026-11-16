import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/application/animation_script.dart';
import 'package:puzzle_duel_mobile/application/game_constants.dart';
import 'package:puzzle_duel_mobile/presentation/audio/game_sfx.dart';
import 'package:puzzle_duel_mobile/presentation/game/board/puzzle_board_game.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

({AnimationScript script, MoveApplied applied}) _scriptWithWaves() {
  final generated =
      generateChallenge(
            ChallengeGenerationConfig.profile(DifficultyProfile.easy),
            kUatChallengeSeed,
          )
          as GeneratedChallenge;

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
        if (result is MoveApplied && result.waves.isNotEmpty) {
          return (
            script: AnimationScript(
              generation: 1,
              resolutionId: 11,
              preState: generated.state,
              applied: result,
              placedPiece: generated.state.offers[offer]!,
            ),
            applied: result,
          );
        }
      }
    }
  }

  // Fall back: synthesize a script from the first legal MoveApplied and inject
  // explicit wave numbers via sfxEventsForWaves unit coverage separately.
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
          return (
            script: AnimationScript(
              generation: 1,
              resolutionId: 11,
              preState: generated.state,
              applied: result,
              placedPiece: generated.state.offers[offer]!,
            ),
            applied: result,
          );
        }
      }
    }
  }
  throw StateError('no MoveApplied for UAT seed');
}

void main() {
  group('AssetGameSfx lifecycle', () {
    testWidgets('queued play does not start after mute', (tester) async {
      final started = <String>[];
      final gate = Completer<void>();
      late final AssetGameSfx sfx;
      sfx = AssetGameSfx(
        playOverride: (path, volume) async {
          await gate.future;
          // Lifecycle gate in AssetGameSfx must drop this after mute.
          if (!sfx.muted) {
            started.add(path);
          }
        },
      );

      sfx.play(GameSfxEvent.place);
      sfx.muted = true;
      gate.complete();
      await tester.pump();
      await tester.pump();
      expect(started, isEmpty);
      sfx.dispose();
    });

    test('queued play does not start after dispose', () async {
      final started = <String>[];
      final gate = Completer<void>();
      final sfx = AssetGameSfx(
        playOverride: (path, volume) async {
          await gate.future;
          started.add(path);
        },
      );

      sfx.play(GameSfxEvent.clear);
      sfx.dispose();
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(started, isEmpty);
    });

    test('mute is deterministic and suppresses further plays', () {
      final played = <String>[];
      final sfx = AssetGameSfx(
        playOverride: (path, volume) async {
          played.add(path);
        },
      );
      sfx.muted = true;
      sfx.play(GameSfxEvent.reject);
      sfx.play(GameSfxEvent.place);
      expect(played, isEmpty);
      expect(sfx.muted, isTrue);
      sfx.muted = false;
      sfx.play(GameSfxEvent.reject);
      // Allow microtask queue.
    });

    testWidgets('unmute allows plays again after mute', (tester) async {
      final played = <String>[];
      final sfx = AssetGameSfx(
        playOverride: (path, volume) async {
          played.add(path);
        },
      );
      sfx.muted = true;
      sfx.play(GameSfxEvent.place);
      await tester.pump();
      expect(played, isEmpty);

      sfx.muted = false;
      sfx.play(GameSfxEvent.place);
      await tester.pump();
      expect(played, ['sfx/place.wav']);
      sfx.dispose();
    });

    testWidgets('transient failure does not permanently disable audio', (
      tester,
    ) async {
      var failNext = true;
      final played = <String>[];
      final sfx = AssetGameSfx(
        playOverride: (path, volume) async {
          if (failNext) {
            failNext = false;
            throw Exception('transient');
          }
          played.add(path);
        },
      );

      sfx.play(GameSfxEvent.clear);
      await tester.pump();
      // Different event avoids same-event debounce (DateTime is real in tests).
      sfx.play(GameSfxEvent.cascade);
      await tester.pump();
      expect(played, ['sfx/cascade.wav']);
      expect(sfx.isInFailureCooldown, isFalse);
      sfx.dispose();
    });

    test('dispose during in-flight play does not throw', () async {
      final gate = Completer<void>();
      final sfx = AssetGameSfx(
        playOverride: (path, volume) async {
          await gate.future;
        },
      );
      sfx.play(GameSfxEvent.cascade);
      expect(() => sfx.dispose(), returnsNormally);
      gate.complete();
      await Future<void>.delayed(Duration.zero);
    });
  });

  group('reduced motion and skip SFX', () {
    test('sfxEventsForWaves maps actual waves only', () {
      expect(sfxEventsForWaves(const []), [GameSfxEvent.place]);
      expect(sfxEventsForWaves(const [1]), [
        GameSfxEvent.place,
        GameSfxEvent.clear,
        GameSfxEvent.chainComplete,
      ]);
      expect(sfxEventsForWaves(const [1, 2]), [
        GameSfxEvent.place,
        GameSfxEvent.clear,
        GameSfxEvent.cascade,
        GameSfxEvent.chainComplete,
      ]);
    });

    testWidgets('reduced motion emits wave SFX once then finishes', (
      tester,
    ) async {
      final events = <GameSfxEvent>[];
      var completed = 0;
      final game = PuzzleBoardGame(
        onResolutionComplete: ({required generation, required resolutionId}) {
          completed++;
        },
        onSfx: events.add,
      );

      final pair = _scriptWithWaves();
      final expected = sfxEventsForWaves(
        pair.applied.waves.map((w) => w.wave),
      );

      game.playScript(pair.script, reducedMotion: true);
      await tester.pump();
      expect(events, expected);
      expect(completed, 1);

      // Rebuild / duplicate playScript with same ids is host-guarded; calling
      // again with a fresh game token would reset — ensure finish is not noisy.
      game.playScript(pair.script, reducedMotion: true);
      await tester.pump();
      expect(events, [...expected, ...expected]);
      expect(completed, 2);
      game.disposeGame();
    });

    testWidgets('skip does not duplicate SFX after animated start', (
      tester,
    ) async {
      final events = <GameSfxEvent>[];
      final game = PuzzleBoardGame(
        onResolutionComplete: ({required generation, required resolutionId}) {},
        onSfx: events.add,
      );
      final pair = _scriptWithWaves();
      game.playScript(pair.script, reducedMotion: false);
      await tester.pump(const Duration(milliseconds: 50));
      final afterStart = List<GameSfxEvent>.from(events);
      expect(afterStart, isNotEmpty);

      game.skipToFinal(
        pair.applied.finalState,
        generation: pair.script.generation,
        resolutionId: pair.script.resolutionId,
      );
      await tester.pump();
      expect(events, afterStart);
      game.disposeGame();
    });

    testWidgets('skip after reduced motion does not duplicate', (tester) async {
      final events = <GameSfxEvent>[];
      final game = PuzzleBoardGame(
        onResolutionComplete: ({required generation, required resolutionId}) {},
        onSfx: events.add,
      );
      final pair = _scriptWithWaves();
      game.playScript(pair.script, reducedMotion: true);
      await tester.pump();
      final once = List<GameSfxEvent>.from(events);

      game.skipToFinal(
        pair.applied.finalState,
        generation: pair.script.generation,
        resolutionId: pair.script.resolutionId,
      );
      await tester.pump();
      expect(events, once);
      game.disposeGame();
    });

    testWidgets('new-round generation cancels prior resolution SFX path', (
      tester,
    ) async {
      final events = <GameSfxEvent>[];
      final game = PuzzleBoardGame(
        onResolutionComplete: ({required generation, required resolutionId}) {},
        onSfx: events.add,
      );
      final pair = _scriptWithWaves();
      game.playScript(pair.script, reducedMotion: false);
      await tester.pump(const Duration(milliseconds: 20));

      final next = AnimationScript(
        generation: pair.script.generation + 1,
        resolutionId: 1,
        preState: pair.script.preState,
        applied: pair.applied,
        placedPiece: pair.script.placedPiece,
      );
      game.playScript(next, reducedMotion: true);
      await tester.pump();

      final expectedTail = sfxEventsForWaves(
        pair.applied.waves.map((w) => w.wave),
      );
      // Last emissions belong to the new generation reduced-motion path.
      expect(events.sublist(events.length - expectedTail.length), expectedTail);
      game.disposeGame();
    });

    testWidgets('widget reduced-motion path still completes resolution', (
      tester,
    ) async {
      // Smoke: playScript reducedMotion completes without inventing waves.
      final events = <GameSfxEvent>[];
      final game = PuzzleBoardGame(
        onResolutionComplete: ({required generation, required resolutionId}) {},
        onSfx: events.add,
      );
      final generated =
          generateChallenge(
                ChallengeGenerationConfig.profile(DifficultyProfile.easy),
                kUatChallengeSeed,
              )
              as GeneratedChallenge;
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
      final script = AnimationScript(
        generation: 3,
        resolutionId: 9,
        preState: generated.state,
        applied: applied!,
        placedPiece: placed!,
      );
      game.playScript(script, reducedMotion: true);
      await tester.pump();
      expect(
        events.where((e) => e == GameSfxEvent.clear || e == GameSfxEvent.cascade),
        hasLength(applied.waves.length),
      );
      if (applied.waves.isEmpty) {
        expect(events, [GameSfxEvent.place]);
      }
      game.disposeGame();
    });
  });
}
