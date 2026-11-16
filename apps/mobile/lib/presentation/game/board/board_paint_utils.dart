import 'dart:math' as math;
import 'dart:ui';

import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

void paintPieceGlyph(
  Canvas canvas, {
  required Offset center,
  required double size,
  required Piece piece,
  required Color fill,
  required Color stroke,
}) {
  final radius = size * 0.38;
  final shapePaint = Paint()
    ..color = fill
    ..style = PaintingStyle.fill;
  final border = Paint()
    ..color = stroke
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1.5, size * 0.04);

  final path = shapePath(center, radius, piece.shape);
  canvas.drawPath(path, shapePaint);
  canvas.drawPath(path, border);

  final arrowPaint = Paint()
    ..color = stroke
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(2.0, size * 0.08)
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  canvas.drawPath(
    arrowPath(center, radius * 0.55, piece.direction),
    arrowPaint,
  );
}

Path shapePath(Offset c, double r, Shape shape) {
  switch (shape) {
    case Shape.circle:
      return Path()..addOval(Rect.fromCircle(center: c, radius: r));
    case Shape.diamond:
      return Path()
        ..moveTo(c.dx, c.dy - r)
        ..lineTo(c.dx + r, c.dy)
        ..lineTo(c.dx, c.dy + r)
        ..lineTo(c.dx - r, c.dy)
        ..close();
    case Shape.triangle:
      return Path()
        ..moveTo(c.dx, c.dy - r)
        ..lineTo(c.dx + r * 0.95, c.dy + r * 0.85)
        ..lineTo(c.dx - r * 0.95, c.dy + r * 0.85)
        ..close();
  }
}

Path arrowPath(Offset c, double len, Direction direction) {
  final tip = switch (direction) {
    Direction.up => Offset(c.dx, c.dy - len),
    Direction.right => Offset(c.dx + len, c.dy),
    Direction.down => Offset(c.dx, c.dy + len),
    Direction.left => Offset(c.dx - len, c.dy),
  };
  final wing = len * 0.45;
  final left = switch (direction) {
    Direction.up => Offset(tip.dx - wing, tip.dy + wing),
    Direction.right => Offset(tip.dx - wing, tip.dy - wing),
    Direction.down => Offset(tip.dx + wing, tip.dy - wing),
    Direction.left => Offset(tip.dx + wing, tip.dy + wing),
  };
  final right = switch (direction) {
    Direction.up => Offset(tip.dx + wing, tip.dy + wing),
    Direction.right => Offset(tip.dx - wing, tip.dy + wing),
    Direction.down => Offset(tip.dx - wing, tip.dy - wing),
    Direction.left => Offset(tip.dx + wing, tip.dy - wing),
  };
  return Path()
    ..moveTo(left.dx, left.dy)
    ..lineTo(tip.dx, tip.dy)
    ..lineTo(right.dx, right.dy);
}
