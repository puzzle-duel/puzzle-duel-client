import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/piece_glyph.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/premium_shape_materials.dart';
import 'package:puzzle_duel_mobile/theme/game_tokens.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

/// See `pzd47_golden_artifacts_test.dart` for always-on CI coverage.
bool get _skipCiPixelGoldens {
  final force = Platform.environment['PZD47_FORCE_GOLDENS'] == '1';
  final onCi =
      Platform.environment['CI'] == 'true' ||
      Platform.environment['GITHUB_ACTIONS'] == 'true';
  return onCi && !force;
}

Widget _matrixCell(Piece piece, double size) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: ColoredBox(
      color: GameTokens.bgDeep,
      child: Center(
        child: PieceGlyph(piece: piece, size: size),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('canonical materials version and source hash are pinned', () {
    expect(PremiumShapeMaterials.version, 'pzd47-hexagon-identity-v1');
    expect(
      PremiumShapeMaterials.sourceSha256,
      'dff57723ed17a469f5bd437a589c0f51e5ef970c657248d59638de77c99b689c',
    );
  });

  test('diamond silhouette is 45° (axis vertices), never axis-aligned square', () {
    const c = Offset(50, 50);
    const r = 40.0;
    final v = PiecePainter.diamondVertices(c, r);
    // N/E/S/W vertices ⇒ square rotated 45° about Z.
    expect(v.north.dx, closeTo(c.dx, 1e-9));
    expect(v.south.dx, closeTo(c.dx, 1e-9));
    expect(v.east.dy, closeTo(c.dy, 1e-9));
    expect(v.west.dy, closeTo(c.dy, 1e-9));
    expect(v.east.dx, greaterThan(c.dx));
    expect(v.west.dx, lessThan(c.dx));
    // Axis-aligned square would place corners at (±r, ±r); ensure those
    // corners are outside the diamond silhouette.
    expect(
      PiecePainter.pointInShape(Offset(c.dx + r, c.dy + r), c, r, Shape.diamond),
      isFalse,
    );
  });

  group('12 direction combinations — geometry', () {
    for (final shape in Shape.values) {
      for (final direction in Direction.values) {
        test('${shape.wire} × ${direction.wire}', () {
          const size = 64.0;
          final center = const Offset(size / 2, size / 2);
          final radius = size * 0.42;
          final stroke = PiecePainter.directionArrowStroke(size);
          expect(
            PiecePainter.directionArrowStrokeContained(
              shape: shape,
              shapeCenter: center,
              radius: radius,
              direction: direction,
              strokeWidth: stroke,
            ),
            isTrue,
          );
          final glyph = PiecePainter.directionGlyph(
            shape: shape,
            shapeCenter: center,
            radius: radius,
            direction: direction,
            strokeWidth: stroke,
          );
          final origin = PiecePainter.glyphOrigin(center, radius, shape);
          switch (direction) {
            case Direction.up:
              expect(glyph.tip.dy, lessThan(origin.dy));
            case Direction.down:
              expect(glyph.tip.dy, greaterThan(origin.dy));
            case Direction.left:
              expect(glyph.tip.dx, lessThan(origin.dx));
            case Direction.right:
              expect(glyph.tip.dx, greaterThan(origin.dx));
          }
        });
      }
    }
  });

  group('12 direction combinations — goldens', () {
    for (final shape in Shape.values) {
      for (final direction in Direction.values) {
        testWidgets('${shape.wire}_${direction.wire}', (tester) async {
          await tester.pumpWidget(
            RepaintBoundary(
              child: SizedBox(
                width: 96,
                height: 96,
                child: _matrixCell(
                  Piece(shape: shape, direction: direction),
                  72,
                ),
              ),
            ),
          );
          await tester.pump();
          await expectLater(
            find.byType(RepaintBoundary).first,
            matchesGoldenFile(
              'goldens/pzd47_${shape.wire}_${direction.wire}.png',
            ),
          );
        }, skip: _skipCiPixelGoldens);
      }
    }

    testWidgets('direction matrix strip 3×4', (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

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
                    for (final shape in Shape.values)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (final direction in Direction.values)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                child: SizedBox(
                                  width: 80,
                                  height: 80,
                                  child: _matrixCell(
                                    Piece(
                                      shape: shape,
                                      direction: direction,
                                    ),
                                    64,
                                  ),
                                ),
                              ),
                          ],
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
        matchesGoldenFile('goldens/pzd47_direction_matrix_3x4.png'),
      );
    }, skip: _skipCiPixelGoldens);
  });

  testWidgets('piece painter paints within bounds (no overflow)', (tester) async {
    for (final shape in Shape.values) {
      for (final direction in Direction.values) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        const size = Size.square(72);
        PiecePainter(
          piece: Piece(shape: shape, direction: direction),
          fill: PremiumShapeMaterials.fill(shape),
          deep: PremiumShapeMaterials.deep(shape),
          stroke: PremiumShapeMaterials.directionInset,
          selected: false,
        ).paint(canvas, size);
        final picture = recorder.endRecording();
        final image = await picture.toImage(72, 72);
        expect(image.width, 72);
        expect(image.height, 72);
        image.dispose();
      }
    }
  });
}
