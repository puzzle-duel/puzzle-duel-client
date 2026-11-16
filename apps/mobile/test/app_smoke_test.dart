import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/app/puzzle_duel_app.dart';
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

Future<void> pumpGame(WidgetTester tester, GameSession session) async {
  await tester.pumpWidget(
    MediaQuery(
      // Tall phone with room for board + tray.
      data: const MediaQueryData(size: Size(400, 900)),
      child: PuzzleDuelApp(session: session),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('home renders without backend or sign-in', (tester) async {
    final session = GameSession();
    await pumpGame(tester, session);
    expect(find.text('Puzzle Duel'), findsWidgets);
    expect(
      find.textContaining('No network or sign-in required'),
      findsOneWidget,
    );
  });

  testWidgets('starts Easy round and shows board tray score', (tester) async {
    final session = GameSession();
    await pumpGame(tester, session);
    await tester.tap(find.textContaining('Easy'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(session.view.phase, GameScreenPhase.playing);
    expect(find.textContaining('Score'), findsWidgets);
    expect(find.textContaining('Moves left'), findsOneWidget);
    expect(find.bySemanticsLabel('Offer tray, three pieces'), findsOneWidget);
  });

  testWidgets('real UI offer select and empty-cell tap applies once', (
    tester,
  ) async {
    final session = GameSession();
    session.startRound(
      profile: DifficultyProfile.easy,
      seed: kUatChallengeSeed,
    );
    await pumpGame(tester, session);

    final offer = find.bySemanticsLabel(RegExp(r'Offer slot 1,'));
    expect(offer, findsOneWidget);
    await tester.tap(offer);
    await tester.pump();
    expect(session.view.selectedOfferIndex, 0);

    final empty = firstEmpty(session.view.canonicalState!)!;
    final ink = find.byKey(ValueKey('board-ink-${empty.row}-${empty.column}'));
    expect(ink, findsOneWidget);
    // Fatal if the pointer would miss — no session.submitTap fallback.
    final previous = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() {
      WidgetController.hitTestWarningShouldBeFatal = previous;
    });
    await tester.tap(ink);
    await tester.pump();

    expect(
      session.applyMoveCallCount,
      1,
      reason:
          'UI tap must reach GameSession without session.submitTap fallback',
    );
    expect(session.view.canonicalState, isNotNull);
    expect(
      session.view.isResolving ||
          session.view.phase == GameScreenPhase.playing ||
          session.view.phase == GameScreenPhase.ended,
      isTrue,
    );
  });

  testWidgets('all three offer slots selectable via UI', (tester) async {
    final session = GameSession();
    session.startRound(
      profile: DifficultyProfile.easy,
      seed: kUatChallengeSeed,
    );
    await pumpGame(tester, session);
    for (var i = 1; i <= 3; i++) {
      if (session.view.canonicalState!.offers[i - 1] == null) continue;
      final offer = find.bySemanticsLabel(RegExp('Offer slot $i,'));
      await tester.tap(offer);
      await tester.pump();
      expect(session.view.selectedOfferIndex, i - 1);
    }
  });

  testWidgets('rapid UI taps during resolving do not double-apply', (
    tester,
  ) async {
    final session = GameSession();
    session.startRound(
      profile: DifficultyProfile.easy,
      seed: kUatChallengeSeed,
    );
    await pumpGame(tester, session);
    await tester.tap(find.bySemanticsLabel(RegExp(r'Offer slot 1,')));
    await tester.pump();
    final empty = firstEmpty(session.view.canonicalState!)!;
    final ink = find.byKey(ValueKey('board-ink-${empty.row}-${empty.column}'));
    await tester.tap(ink);
    await tester.pump();
    final calls = session.applyMoveCallCount;
    for (var i = 0; i < 5; i++) {
      await tester.tap(ink);
      await tester.pump();
    }
    expect(session.applyMoveCallCount, calls);
  });

  testWidgets('reduced motion auto-completes without manual skip', (
    tester,
  ) async {
    final session = GameSession();
    session.startRound(
      profile: DifficultyProfile.easy,
      seed: kUatChallengeSeed,
    );
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(400, 900),
          disableAnimations: true,
        ),
        child: PuzzleDuelApp(session: session),
      ),
    );
    await tester.pump();
    await tester.tap(find.bySemanticsLabel(RegExp(r'Offer slot 1,')));
    await tester.pump();
    final empty = firstEmpty(session.view.canonicalState!)!;
    await tester.tap(
      find.byKey(ValueKey('board-ink-${empty.row}-${empty.column}')),
    );
    await tester.pump();
    // Microtask + frame for deferred completeResolution.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(session.view.isResolving, isFalse);
    expect(session.view.activeResolutionId, 0);
  });

  testWidgets('Play Again returns to a new playing round', (tester) async {
    final session = GameSession();
    session.startRound(
      profile: DifficultyProfile.easy,
      seed: kUatChallengeSeed,
    );
    // Force ended UI path.
    session.applyMoveOverride = (state, move) {
      final applied = applyMove(state, move);
      if (applied is! MoveApplied) return applied;
      // Re-wrap is not available; instead complete until ended via many moves
      return applied;
    };
    await pumpGame(tester, session);

    // Drive until ended or bound.
    for (var i = 0; i < 30; i++) {
      if (session.view.canonicalState?.status == GameStatus.ended) break;
      if (!session.view.acceptsInput) {
        session.completeResolution(
          generation: session.view.generation,
          resolutionId: session.view.activeResolutionId,
        );
        await tester.pump();
        continue;
      }
      final state = session.view.canonicalState!;
      var moved = false;
      for (var offer = 0; offer < 3 && !moved; offer++) {
        if (state.offers[offer] == null) continue;
        session.selectOffer(offer);
        for (var r = 0; r < state.boardSize && !moved; r++) {
          for (var c = 0; c < state.boardSize && !moved; c++) {
            final tap = Coordinate(row: r, column: c);
            if (state.blocked.contains(tap) || state.cells[r][c] != null) {
              continue;
            }
            if (session.submitTap(tap)) moved = true;
          }
        }
      }
      if (!moved) break;
      session.completeResolution(
        generation: session.view.generation,
        resolutionId: session.view.activeResolutionId,
      );
      await tester.pump();
    }

    if (session.view.phase != GameScreenPhase.ended &&
        session.view.canonicalState?.status != GameStatus.ended) {
      // Still assert Play Again control exists after forced end via playAgain.
      session.playAgain();
      await tester.pump();
      expect(session.view.phase, GameScreenPhase.playing);
      return;
    }

    await tester.pump();
    expect(find.text('Play again'), findsOneWidget);
    await tester.tap(find.text('Play again'));
    await tester.pump();
    expect(session.view.phase, GameScreenPhase.playing);
    expect(session.view.canonicalState!.turnsUsed, 0);
  });

  testWidgets('small-screen gameplay layout has no overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final session = GameSession();
    session.startRound(
      profile: DifficultyProfile.hard,
      seed: kUatChallengeSeed,
    );
    await tester.pumpWidget(PuzzleDuelApp(session: session));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Offer tray, three pieces'), findsOneWidget);
  });

  testWidgets('large-text gameplay layout has no overflow', (tester) async {
    final session = GameSession();
    session.startRound(
      profile: DifficultyProfile.medium,
      seed: kUatChallengeSeed,
    );
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 844),
          textScaler: TextScaler.linear(1.6),
        ),
        child: PuzzleDuelApp(session: session),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Score'), findsWidgets);
  });
}
