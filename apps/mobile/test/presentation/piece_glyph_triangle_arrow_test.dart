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

  group('direction glyph geometry — all shapes', () {
    for (final shape in Shape.values) {
      for (final board in [5, 6, 7]) {
        final size = pieceSizeForBoard(board);
        final radius = size * 0.42;
        final stroke = PiecePainter.directionArrowStroke(size);

        for (final direction in Direction.values) {
          test('$shape board ${board}x$board $direction contained', () {
            final center = Offset(size / 2, size / 2);
            expect(
              PiecePainter.directionArrowStrokeContained(
                shape: shape,
                shapeCenter: center,
                radius: radius,
                direction: direction,
                strokeWidth: stroke,
              ),
              isTrue,
              reason: '$shape $direction must stay inside at $board×$board',
            );
          });

          test('$shape board ${board}x$board $direction tipLen readable', () {
            final center = Offset(size / 2, size / 2);
            final glyph = PiecePainter.directionGlyph(
              shape: shape,
              shapeCenter: center,
              radius: radius,
              direction: direction,
              strokeWidth: stroke,
            );
            final tipLen = (glyph.tip - glyph.origin).distance;
            expect(
              tipLen,
              greaterThanOrEqualTo(radius * 0.28),
              reason: '$shape chevron readable at $board×$board',
            );
          });
        }
      }
    }

    test('arrow tip tracks Direction for every shape', () {
      const size = 60.0;
      final c = const Offset(30, 30);
      const r = size * 0.42;
      final stroke = PiecePainter.directionArrowStroke(size);

      for (final shape in Shape.values) {
        Offset tip(Direction d) => PiecePainter.directionGlyph(
          shape: shape,
          shapeCenter: c,
          radius: r,
          direction: d,
          strokeWidth: stroke,
        ).tip;
        final origin = PiecePainter.glyphOrigin(c, r, shape);

        expect(tip(Direction.up).dy, lessThan(origin.dy), reason: '$shape');
        expect(tip(Direction.down).dy, greaterThan(origin.dy), reason: '$shape');
        expect(tip(Direction.left).dx, lessThan(origin.dx), reason: '$shape');
        expect(tip(Direction.right).dx, greaterThan(origin.dx), reason: '$shape');
      }
    });

    test('triangle silhouette stays upright', () {
      final c = const Offset(40, 40);
      const r = 20.0;
      final v = PiecePainter.triangleVertices(c, r);
      expect(v.apex.dy, lessThan(v.bottomLeft.dy));
      expect(v.bottomLeft.dy, closeTo(v.bottomRight.dy, 1e-9));
      expect(v.apex.dx, closeTo(c.dx, 1e-9));
    });

    test('semantics labels use presentation names', () {
      for (final shape in Shape.values) {
        for (final d in Direction.values) {
          final label = PieceGlyph.semanticsLabel(
            Piece(shape: shape, direction: d),
          );
          final presentation = switch (shape) {
            Shape.circle => 'circle',
            Shape.diamond => 'diamond',
            // Domain wire remains triangle; UI presents hexagon.
            Shape.triangle => 'hexagon',
          };
          expect(label, contains(presentation));
          expect(label, contains(d.wire));
          expect(label, contains('pointing'));
        }
      }
    });
  });

  group('direction family goldens', () {
    for (final shape in Shape.values) {
      for (final board in [5, 6, 7]) {
        final size = pieceSizeForBoard(board);
        for (final direction in Direction.values) {
          testWidgets(
            '${shape.wire} ${board}x$board $direction',
            (tester) async {
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
                  'goldens/${shape.wire}_${board}x${board}_${direction.wire}.png',
                ),
              );
            },
            skip: _skipGoldensOnCi,
          );
        }
      }
    }

    testWidgets(
      '3 shapes × 4 directions real-scale board and tray family',
      (tester) async {
        // Tall surface for 3 board densities × 3 shapes × tray.
        tester.view.physicalSize = const Size(1000, 2800);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

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
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final board in [5, 6, 7]) ...[
                        Text(
                          '$board×$board board cells',
                          style: const TextStyle(
                            color: GameTokens.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 4),
                        for (final shape in Shape.values) ...[
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 64,
                                child: Text(
                                  shape.wire,
                                  style: const TextStyle(
                                    color: GameTokens.textMuted,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                              for (final d in Direction.values)
                                Padding(
                                  padding: const EdgeInsets.all(2),
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
                                        Piece(shape: shape, direction: d),
                                        sizes[board]!,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                        ],
                        const SizedBox(height: 8),
                      ],
                      const Text(
                        'Offer tray slots',
                        style: TextStyle(
                          color: GameTokens.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (final shape in Shape.values) ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 64,
                              child: Text(
                                shape.wire,
                                style: const TextStyle(
                                  color: GameTokens.textMuted,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            for (final d in Direction.values)
                              Padding(
                                padding: const EdgeInsets.all(3),
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
                                      Piece(shape: shape, direction: d),
                                      traySlot,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                      ],
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
          matchesGoldenFile('goldens/direction_family_board_tray.png'),
        );
      },
      skip: _skipGoldensOnCi,
    );

    testWidgets(
      'triangle directions strip',
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
  });
}
