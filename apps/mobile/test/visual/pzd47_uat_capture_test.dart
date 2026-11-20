import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/app/puzzle_duel_app.dart';
import 'package:puzzle_duel_mobile/application/game_constants.dart';
import 'package:puzzle_duel_mobile/application/game_session.dart';
import 'package:puzzle_duel_mobile/presentation/audio/game_sfx.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/piece_glyph.dart';
import 'package:puzzle_duel_mobile/theme/game_tokens.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

/// PZD-47 owner visual UAT captures (macOS local; skipped on CI).
const _captureKey = ValueKey('pzd47-visual-capture');

bool get _skipOnCi =>
    Platform.environment['CI'] == 'true' ||
    Platform.environment['GITHUB_ACTIONS'] == 'true';

Future<void> _pumpPhone(WidgetTester tester, GameSession session) async {
  tester.view.physicalSize = const Size(780, 1688);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: PuzzleDuelApp(session: session, sfx: RecordingGameSfx()),
    ),
  );
  await tester.pump(const Duration(milliseconds: 16));
}

Future<void> _golden(WidgetTester tester, String name) async {
  await expectLater(
    find.byKey(_captureKey),
    matchesGoldenFile(
      '../../../../docs/features/pzd-47/uat/$name.png',
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('uat 5x5 6x6 7x7 boards', (tester) async {
    for (final entry in [
      (DifficultyProfile.easy, '03-board-5x5'),
      (DifficultyProfile.medium, '04-board-6x6'),
      (DifficultyProfile.hard, '05-board-7x7-dense'),
    ]) {
      final session = GameSession()
        ..startRound(profile: entry.$1, seed: kUatChallengeSeed);
      await _pumpPhone(tester, session);
      await _golden(tester, entry.$2);
    }
  }, skip: _skipOnCi);

  testWidgets('uat tray selected state', (tester) async {
    final session = GameSession()
      ..startRound(profile: DifficultyProfile.easy, seed: kUatChallengeSeed);
    await _pumpPhone(tester, session);
    await tester.tap(find.bySemanticsLabel(RegExp(r'Offer slot 1,')));
    await tester.pump(const Duration(milliseconds: 160));
    await _golden(tester, '06-tray-selected');
  }, skip: _skipOnCi);

  testWidgets('uat renderer shape strip for parity', (tester) async {
    tester.view.physicalSize = const Size(900, 320);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: _captureKey,
          child: ColoredBox(
            color: GameTokens.bgDeep,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final piece in [
                  const Piece(shape: Shape.circle, direction: Direction.up),
                  const Piece(shape: Shape.diamond, direction: Direction.left),
                  const Piece(shape: Shape.triangle, direction: Direction.up),
                ])
                  PieceGlyph(piece: piece, size: 96),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await _golden(tester, '07-renderer-shapes-strip');
  }, skip: _skipOnCi);
}
