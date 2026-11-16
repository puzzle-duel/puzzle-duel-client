import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/app/puzzle_duel_app.dart';
import 'package:puzzle_duel_mobile/application/game_constants.dart';
import 'package:puzzle_duel_mobile/application/game_session.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

const _captureKey = ValueKey('pzd23-visual-capture');

Future<void> _pumpPhone(WidgetTester tester, GameSession session) async {
  tester.view.physicalSize = const Size(780, 1688);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: PuzzleDuelApp(session: session),
    ),
  );
  await tester.pump(const Duration(milliseconds: 16));
}

Future<void> _golden(WidgetTester tester, String name) async {
  await expectLater(
    find.byKey(_captureKey),
    matchesGoldenFile(
      '../../../../docs/mobile/uat-evidence/pzd23-visual/$name.png',
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture home menu', (tester) async {
    await _pumpPhone(tester, GameSession());
    await _golden(tester, '01-home-menu');
  });

  testWidgets('capture easy medium hard boards', (tester) async {
    for (final entry in [
      (DifficultyProfile.easy, '02-easy-board'),
      (DifficultyProfile.medium, '03-medium-board'),
      (DifficultyProfile.hard, '04-hard-board'),
    ]) {
      final session = GameSession()
        ..startRound(profile: entry.$1, seed: kUatChallengeSeed);
      await _pumpPhone(tester, session);
      await _golden(tester, entry.$2);
    }
  });

  testWidgets('capture selected offer', (tester) async {
    final session = GameSession()
      ..startRound(profile: DifficultyProfile.easy, seed: kUatChallengeSeed);
    await _pumpPhone(tester, session);
    await tester.tap(find.bySemanticsLabel(RegExp(r'Offer slot 1,')));
    await tester.pump(const Duration(milliseconds: 160));
    await _golden(tester, '05-selected-piece');
  });

  testWidgets('capture resolving and end overlay', (tester) async {
    final session = GameSession();
    var found = false;
    for (var seed = 0; seed < 200 && !found; seed++) {
      final probe = GameSession()
        ..startRound(profile: DifficultyProfile.easy, seed: seed);
      final state = probe.view.canonicalState!;
      for (var offer = 0; offer < 3 && !found; offer++) {
        if (state.offers[offer] == null) continue;
        for (var r = 0; r < state.boardSize && !found; r++) {
          for (var c = 0; c < state.boardSize && !found; c++) {
            final tap = Coordinate(row: r, column: c);
            if (state.blocked.contains(tap) || state.cells[r][c] != null) {
              continue;
            }
            final result = applyMove(
              state,
              Move(offerIndex: offer, tap: tap),
            );
            if (result is MoveApplied && result.waves.isNotEmpty) {
              found = true;
              session.startRound(profile: DifficultyProfile.easy, seed: seed);
              session.selectOffer(offer);
              session.submitTap(tap);
            }
          }
        }
      }
    }

    await _pumpPhone(tester, session);
    if (session.view.isResolving) {
      await tester.pump(const Duration(milliseconds: 100));
      await _golden(tester, '06-match-clear-resolving');
      await tester.pump(const Duration(milliseconds: 260));
      await _golden(tester, '07-directional-shift');
      session.completeResolution(
        generation: session.view.generation,
        resolutionId: session.view.activeResolutionId,
      );
      await tester.pump();
    }

    for (var i = 0; i < 40; i++) {
      if (session.view.phase == GameScreenPhase.ended) break;
      if (session.view.isResolving) {
        session.completeResolution(
          generation: session.view.generation,
          resolutionId: session.view.activeResolutionId,
        );
        continue;
      }
      if (!session.view.acceptsInput) break;
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
    }
    await tester.pump();
    await _golden(
      tester,
      session.view.phase == GameScreenPhase.ended
          ? '08-completed-round'
          : '08-completed-round-fallback',
    );
  });
}
