import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/theme/game_tokens.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

/// Premium geometric piece: silhouette + deep shade + bold chevron.
final class PieceGlyph extends StatelessWidget {
  const PieceGlyph({
    super.key,
    required this.piece,
    this.size = 48,
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
    return Semantics(
      label: semanticsLabel(piece),
      excludeSemantics: true,
      child: AnimatedScale(
        scale: selected ? 1.08 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutBack,
        child: CustomPaint(
          size: Size.square(size),
          painter: PiecePainter(
            piece: piece,
            fill: muted
                ? GameTokens.pieceFill(piece.shape).withValues(alpha: 0.35)
                : GameTokens.pieceFill(piece.shape),
            deep: muted
                ? GameTokens.pieceDeep(piece.shape).withValues(alpha: 0.35)
                : GameTokens.pieceDeep(piece.shape),
            stroke: selected ? GameTokens.textPrimary : const Color(0xFF061018),
            selected: selected,
          ),
        ),
      ),
    );
  }
}

final class PiecePainter extends CustomPainter {
  PiecePainter({
    required this.piece,
    required this.fill,
    required this.deep,
    required this.stroke,
    required this.selected,
  });

  final Piece piece;
  final Color fill;
  final Color deep;
  final Color stroke;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * 0.42;
    final path = shapePath(center, radius, piece.shape);

    // Soft lift shadow
    canvas.drawPath(
      path.shift(const Offset(0, 2.5)),
      Paint()
        ..color = Colors.black.withValues(alpha: selected ? 0.45 : 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    final rect = Rect.fromCircle(center: center, radius: radius);
    final shader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [fill, deep],
    ).createShader(rect);

    canvas.drawPath(
      path,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.fill,
    );

    // Inner highlight rim (not hue-only cue)
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, size.shortestSide * 0.03),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected
            ? math.max(2.8, size.shortestSide * 0.07)
            : math.max(1.8, size.shortestSide * 0.045),
    );

    final arrowPaint = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.4, size.shortestSide * 0.09)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(arrowPath(center, radius * 0.58, piece.direction), arrowPaint);

    // Arrow fill tip for stronger silhouette at 7×7
    final tipFill = Paint()..color = stroke;
    canvas.drawCircle(_tip(center, radius * 0.58, piece.direction), 1.6, tipFill);
  }

  static Offset _tip(Offset c, double len, Direction d) => switch (d) {
    Direction.up => Offset(c.dx, c.dy - len),
    Direction.right => Offset(c.dx + len, c.dy),
    Direction.down => Offset(c.dx, c.dy + len),
    Direction.left => Offset(c.dx - len, c.dy),
  };

  static Path shapePath(Offset c, double r, Shape shape) {
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
          ..lineTo(c.dx + r * 0.95, c.dy + r * 0.82)
          ..lineTo(c.dx - r * 0.95, c.dy + r * 0.82)
          ..close();
    }
  }

  static Path arrowPath(Offset c, double len, Direction direction) {
    final tip = _tip(c, len, direction);
    final wing = len * 0.48;
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
  bool shouldRepaint(covariant PiecePainter oldDelegate) {
    return oldDelegate.piece != piece ||
        oldDelegate.fill != fill ||
        oldDelegate.deep != deep ||
        oldDelegate.stroke != stroke ||
        oldDelegate.selected != selected;
  }
}
