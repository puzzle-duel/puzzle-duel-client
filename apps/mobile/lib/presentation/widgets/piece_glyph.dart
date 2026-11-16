import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

/// Color-independent piece glyph: filled shape + distinct chevron arrow.
final class PieceGlyph extends StatelessWidget {
  const PieceGlyph({
    super.key,
    required this.piece,
    this.size = 40,
    this.selected = false,
    this.muted = false,
  });

  final Piece piece;
  final double size;
  final bool selected;
  final bool muted;

  static String semanticsLabel(Piece piece) {
    return '${_shapeLabel(piece.shape)} pointing ${_directionLabel(piece.direction)}';
  }

  static String _shapeLabel(Shape shape) => switch (shape) {
    Shape.circle => 'circle',
    Shape.diamond => 'diamond',
    Shape.triangle => 'triangle',
  };

  static String _directionLabel(Direction direction) => switch (direction) {
    Direction.up => 'up',
    Direction.right => 'right',
    Direction.down => 'down',
    Direction.left => 'left',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = muted
        ? scheme.onSurface.withValues(alpha: 0.35)
        : switch (piece.shape) {
            Shape.circle => scheme.primary,
            Shape.diamond => scheme.tertiary,
            Shape.triangle => scheme.secondary,
          };
    final stroke = selected ? scheme.onPrimaryContainer : scheme.onSurface;
    return Semantics(
      label: semanticsLabel(piece),
      excludeSemantics: true,
      child: CustomPaint(
        size: Size.square(size),
        painter: _PiecePainter(
          piece: piece,
          fill: fill,
          stroke: stroke,
          selected: selected,
        ),
      ),
    );
  }
}

final class _PiecePainter extends CustomPainter {
  _PiecePainter({
    required this.piece,
    required this.fill,
    required this.stroke,
    required this.selected,
  });

  final Piece piece;
  final Color fill;
  final Color stroke;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * 0.38;
    final shapePaint = Paint()
      ..color = fill
      ..style = PaintingStyle.fill;
    final border = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 3 : 1.5;

    final path = _shapePath(center, radius, piece.shape);
    canvas.drawPath(path, shapePaint);
    canvas.drawPath(path, border);

    // Chevron arrow — large enough for 7×7 density.
    final arrowPaint = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.0, size.shortestSide * 0.08)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final arrow = _arrowPath(center, radius * 0.55, piece.direction);
    canvas.drawPath(arrow, arrowPaint);
  }

  Path _shapePath(Offset c, double r, Shape shape) {
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

  Path _arrowPath(Offset c, double len, Direction direction) {
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

  @override
  bool shouldRepaint(covariant _PiecePainter oldDelegate) {
    return oldDelegate.piece != piece ||
        oldDelegate.fill != fill ||
        oldDelegate.stroke != stroke ||
        oldDelegate.selected != selected;
  }
}
