import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/piece_glyph.dart';
import 'package:puzzle_duel_mobile/theme/game_tokens.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

/// Board-cell → piece size used by Flame (`cell * 0.9`).
double pieceSizeForBoard(int boardSize, {double boardSide = 360}) {
  final cell = boardSide / boardSize;
  return cell * 0.9;
}

bool get _skipGoldensOnCi =>
    Platform.environment['CI'] == 'true' ||
    Platform.environment['GITHUB_ACTIONS'] == 'true';

Widget _glyph(Piece piece, double size) {
  return ColoredBox(
    color: GameTokens.bgDeep,
    child: Center(
      child: CustomPaint(
        size: Size.square(size),
        painter: PiecePainter(
          piece: piece,
          fill: GameTokens.pieceFill(piece.shape),
          deep: GameTokens.pieceDeep(piece.shape),
          stroke: const Color(0xFF061018),
          selected: false,
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('triangle arrow geometry', () {
    for (final board in [5, 6, 7]) {
      final size = pieceSizeForBoard(board);
      final radius = size * 0.42;
      final stroke = PiecePainter.triangleArrowStroke(size);

      for (final direction in Direction.values) {
        test('board ${board}x$board $direction stroke stays inside', () {
          final center = Offset(size / 2, size / 2);
          expect(
            PiecePainter.triangleArrowStrokeContained(
              shapeCenter: center,
              radius: radius,
              direction: direction,
              strokeWidth: stroke,
            ),
            isTrue,
            reason:
                'arrow stroke must remain in triangle safe area '
                '($board×$board, size=$size, $direction)',
          );
        });

        test('board ${board}x$board $direction tipLen is readable', () {
          final center = Offset(size / 2, size / 2);
          final glyph = PiecePainter.triangleArrowGlyph(
            shapeCenter: center,
            radius: radius,
            direction: direction,
            strokeWidth: stroke,
          );
          final tipLen = (glyph.tip - glyph.origin).distance;
          expect(
            tipLen,
            greaterThanOrEqualTo(radius * 0.28),
            reason: 'chevron must stay large enough at $board×$board',
          );
        });
      }
    }

    test('arrow tip moves with Direction (not shape rotation)', () {
      const size = 60.0;
      final c = const Offset(30, 30);
      const r = size * 0.42;
      final stroke = PiecePainter.triangleArrowStroke(size);

      Offset tip(Direction d) => PiecePainter.triangleArrowGlyph(
        shapeCenter: c,
        radius: r,
        direction: d,
        strokeWidth: stroke,
      ).tip;

      final up = tip(Direction.up);
      final down = tip(Direction.down);
      final left = tip(Direction.left);
      final right = tip(Direction.right);
      final origin = PiecePainter.triangleCentroid(c, r);

      expect(up.dy, lessThan(origin.dy));
      expect(down.dy, greaterThan(origin.dy));
      expect(left.dx, lessThan(origin.dx));
      expect(right.dx, greaterThan(origin.dx));
      // Horizontal tips share centroid Y; vertical tips share centroid X.
      expect(left.dy, closeTo(origin.dy, 0.01));
      expect(right.dy, closeTo(origin.dy, 0.01));
      expect(up.dx, closeTo(origin.dx, 0.01));
      expect(down.dx, closeTo(origin.dx, 0.01));
    });

    test('triangle silhouette vertices are upright (not direction-rotated)', () {
      final c = const Offset(40, 40);
      const r = 20.0;
      final v = PiecePainter.triangleVertices(c, r);
      expect(v.apex.dy, lessThan(v.bottomLeft.dy));
      expect(v.apex.dy, lessThan(v.bottomRight.dy));
      expect(v.bottomLeft.dy, closeTo(v.bottomRight.dy, 1e-9));
      expect(v.apex.dx, closeTo(c.dx, 1e-9));
    });
  });

  group('triangle arrow goldens', () {
    for (final board in [5, 6, 7]) {
      final size = pieceSizeForBoard(board);
      for (final direction in Direction.values) {
        testWidgets(
          '${board}x$board triangle $direction',
          (tester) async {
            final piece = Piece(shape: Shape.triangle, direction: direction);
            await tester.pumpWidget(
              RepaintBoundary(
                child: SizedBox(
                  width: size + 16,
                  height: size + 16,
                  child: _glyph(piece, size),
                ),
              ),
            );
            await tester.pump();
            await expectLater(
              find.byType(RepaintBoundary).first,
              matchesGoldenFile(
                'goldens/triangle_${board}x${board}_${direction.wire}.png',
              ),
            );
          },
          skip: _skipGoldensOnCi,
        );
      }
    }

    testWidgets(
      'four triangle directions comparison strip',
      (tester) async {
        const size = 64.0;
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: RepaintBoundary(
              child: ColoredBox(
                color: GameTokens.bgDeep,
                child: SizedBox(
                  width: size * 4 + 40,
                  height: size + 24,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final d in Direction.values)
                        SizedBox(
                          width: size,
                          height: size,
                          child: _glyph(
                            Piece(shape: Shape.triangle, direction: d),
                            size,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await expectLater(
          find.byType(RepaintBoundary).first,
          matchesGoldenFile('goldens/triangle_directions_strip.png'),
        );
      },
      skip: _skipGoldensOnCi,
    );

    /// Real board-cell and tray slot scales (not oversized hero art).
    testWidgets(
      'real-scale board cells and tray slots four directions',
      (tester) async {
        const traySlot = 56.0;
        final sizes = {
          5: pieceSizeForBoard(5),
          6: pieceSizeForBoard(6),
          7: pieceSizeForBoard(7),
        };
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: RepaintBoundary(
              child: ColoredBox(
                color: GameTokens.bgDeep,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final board in [5, 6, 7]) ...[
                        Text(
                          '$board×$board board cell',
                          style: const TextStyle(
                            color: GameTokens.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final d in Direction.values)
                              Padding(
                                padding: const EdgeInsets.all(3),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: GameTokens.cellEmpty,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: GameTokens.gridLine,
                                    ),
                                  ),
                                  child: SizedBox.square(
                                    dimension: sizes[board]!,
                                    child: _glyph(
                                      Piece(
                                        shape: Shape.triangle,
                                        direction: d,
                                      ),
                                      sizes[board]!,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                      const Text(
                        'Offer tray slots',
                        style: TextStyle(
                          color: GameTokens.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final d in Direction.values)
                            Padding(
                              padding: const EdgeInsets.all(4),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: GameTokens.surfaceHigh,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: GameTokens.border,
                                  ),
                                ),
                                child: SizedBox.square(
                                  dimension: traySlot,
                                  child: _glyph(
                                    Piece(
                                      shape: Shape.triangle,
                                      direction: d,
                                    ),
                                    traySlot,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await expectLater(
          find.byType(RepaintBoundary).first,
          matchesGoldenFile('goldens/triangle_real_scale_board_tray.png'),
        );
      },
      skip: _skipGoldensOnCi,
    );
  });

  group('circle and diamond golden regression', () {
    for (final shape in [Shape.circle, Shape.diamond]) {
      for (final direction in Direction.values) {
        testWidgets(
          '$shape $direction unchanged',
          (tester) async {
            const size = 56.0;
            await tester.pumpWidget(
              RepaintBoundary(
                child: SizedBox(
                  width: size + 16,
                  height: size + 16,
                  child: _glyph(
                    Piece(shape: shape, direction: direction),
                    size,
                  ),
                ),
              ),
            );
            await tester.pump();
            await expectLater(
              find.byType(RepaintBoundary).first,
              matchesGoldenFile(
                'goldens/${shape.wire}_${direction.wire}.png',
              ),
            );
          },
          skip: _skipGoldensOnCi,
        );
      }
    }
  });
}
