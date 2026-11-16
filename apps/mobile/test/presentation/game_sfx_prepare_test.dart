import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/app/puzzle_duel_app.dart';
import 'package:puzzle_duel_mobile/application/game_constants.dart';
import 'package:puzzle_duel_mobile/application/game_session.dart';
import 'package:puzzle_duel_mobile/presentation/audio/game_sfx.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

void main() {
  group('AssetGameSfx prepare', () {
    testWidgets('prepare is idempotent', (tester) async {
      var loads = 0;
      final loadGate = Completer<void>();
      final sfx = AssetGameSfx(
        playOverride: (path, volume) async {},
        cacheLoadAll: (paths) async {
          loads++;
          await loadGate.future;
        },
      );

      final a = sfx.prepare();
      final b = sfx.prepare();
      final c = sfx.prepare();
      expect(sfx.prepareCallCount, 1);
      loadGate.complete();
      await Future.wait([a, b, c]);
      expect(loads, 1);
      expect(sfx.isPrepared, isTrue);

      await sfx.prepare();
      expect(sfx.prepareCallCount, 1);
      sfx.dispose();
    });

    testWidgets('play during slow prepare does not wait', (tester) async {
      final gate = Completer<void>();
      final played = <String>[];
      final sfx = AssetGameSfx(
        playOverride: (path, volume) async {
          played.add(path);
        },
        cacheLoadAll: (paths) async {
          await gate.future;
        },
      );

      final prepareFuture = sfx.prepare();
      expect(sfx.isPrepared, isFalse);

      // First interaction must not block on prepare.
      sfx.play(GameSfxEvent.place);
      await tester.pump();
      expect(played, ['sfx/place.wav']);

      gate.complete();
      await prepareFuture;
      expect(sfx.isPrepared, isTrue);
      sfx.dispose();
    });

    testWidgets('mute during prepare prevents completion side effects', (
      tester,
    ) async {
      final gate = Completer<void>();
      final sfx = AssetGameSfx(
        playOverride: (path, volume) async {},
        cacheLoadAll: (paths) async {
          await gate.future;
        },
      );

      final future = sfx.prepare();
      sfx.muted = true;
      gate.complete();
      await future;
      expect(sfx.isPrepared, isFalse);
      sfx.play(GameSfxEvent.reject);
      await tester.pump();
      sfx.dispose();
    });

    testWidgets('dispose during prepare is safe', (tester) async {
      final gate = Completer<void>();
      final sfx = AssetGameSfx(
        playOverride: (path, volume) async {},
        cacheLoadAll: (paths) async {
          await gate.future;
        },
      );
      final future = sfx.prepare();
      expect(() => sfx.dispose(), returnsNormally);
      gate.complete();
      await future;
    });

    testWidgets('fail-soft prepare then play still works via override', (
      tester,
    ) async {
      var failLoad = true;
      final played = <String>[];
      final sfx = AssetGameSfx(
        playOverride: (path, volume) async {
          played.add(path);
        },
        cacheLoadAll: (paths) async {
          if (failLoad) {
            failLoad = false;
            throw Exception('cache miss');
          }
        },
      );

      await sfx.prepare();
      expect(sfx.isPrepared, isFalse);
      sfx.play(GameSfxEvent.clear);
      await tester.pump();
      expect(played, ['sfx/clear.wav']);
      sfx.dispose();
    });
  });

  group('first interaction before audio readiness', () {
    testWidgets('offer select and board tap work while prepare gated', (
      tester,
    ) async {
      final gate = Completer<void>();
      final sfx = RecordingGameSfx()
        ..isPrepared = false
        ..prepareGate = gate;

      final session = GameSession()
        ..startRound(profile: DifficultyProfile.easy, seed: kUatChallengeSeed);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(400, 900)),
          child: PuzzleDuelApp(session: session, sfx: sfx),
        ),
      );
      await tester.pump();

      // Prepare started from app first frame but is gated.
      expect(sfx.prepareCallCount, greaterThanOrEqualTo(1));
      expect(sfx.isPrepared, isFalse);

      await tester.tap(find.bySemanticsLabel(RegExp(r'Offer slot 1,')));
      await tester.pump();
      expect(session.view.selectedOfferIndex, 0);

      Coordinate? empty;
      final state = session.view.canonicalState!;
      for (var r = 0; r < state.boardSize; r++) {
        for (var c = 0; c < state.boardSize; c++) {
          final tap = Coordinate(row: r, column: c);
          if (!state.blocked.contains(tap) && state.cells[r][c] == null) {
            empty = tap;
            break;
          }
        }
        if (empty != null) break;
      }

      await tester.tap(
        find.byKey(ValueKey('board-ink-${empty!.row}-${empty.column}')),
      );
      await tester.pump();
      expect(session.applyMoveCallCount, 1);
      expect(
        session.view.isResolving ||
            session.view.phase == GameScreenPhase.playing ||
            session.view.phase == GameScreenPhase.ended,
        isTrue,
      );

      gate.complete();
      await tester.pump();
      expect(sfx.isPrepared, isTrue);
    });

    testWidgets('rapid taps while unprepared do not crash', (tester) async {
      final sfx = RecordingGameSfx()..isPrepared = false;
      final session = GameSession()
        ..startRound(profile: DifficultyProfile.easy, seed: kUatChallengeSeed);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(400, 900)),
          child: PuzzleDuelApp(session: session, sfx: sfx),
        ),
      );
      await tester.pump();

      for (var i = 0; i < 8; i++) {
        await tester.tap(find.bySemanticsLabel(RegExp(r'Offer slot 1,')));
        await tester.pump();
      }
      expect(session.view.selectedOfferIndex, 0);
      expect(tester.takeException(), isNull);
    });
  });
}
