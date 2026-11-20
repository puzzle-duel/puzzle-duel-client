import 'dart:ui';

import 'package:puzzle_duel_mobile/presentation/widgets/piece_glyph.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/premium_shape_materials.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

/// Board Flame path into the same canonical [PiecePainter] used by the tray.
void paintPieceGlyph(
  Canvas canvas, {
  required Offset center,
  required double size,
  required Piece piece,
  required Color fill,
  required Color stroke,
}) {
  final painter = PiecePainter(
    piece: piece,
    fill: fill,
    deep: PremiumShapeMaterials.deep(piece.shape),
    stroke: stroke,
    selected: false,
  );
  canvas.save();
  canvas.translate(center.dx - size / 2, center.dy - size / 2);
  painter.paint(canvas, Size.square(size));
  canvas.restore();
}
