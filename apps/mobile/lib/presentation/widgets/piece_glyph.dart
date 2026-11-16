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

    final arrowStroke = math.max(2.4, size.shortestSide * 0.09);
    final arrowPaint = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = arrowStroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (piece.shape) {
      case Shape.triangle:
        // Shape-aware chevron: stays inside the upright triangle silhouette.
        // Do not rotate the triangle — only the internal direction mark.
        final glyph = triangleArrowGlyph(
          shapeCenter: center,
          radius: radius,
          direction: piece.direction,
          strokeWidth: arrowStroke,
        );
        canvas.drawPath(glyph.path, arrowPaint);
      case Shape.circle:
      case Shape.diamond:
        final len = radius * 0.58;
        canvas.drawPath(arrowPath(center, len, piece.direction), arrowPaint);
        canvas.drawCircle(
          tipOf(center, len, piece.direction),
          1.6,
          Paint()..color = stroke,
        );
    }
  }

  /// Equilateral-ish upright triangle matching [shapePath] for [Shape.triangle].
  static ({Offset apex, Offset bottomRight, Offset bottomLeft}) triangleVertices(
    Offset c,
    double r,
  ) {
    return (
      apex: Offset(c.dx, c.dy - r),
      bottomRight: Offset(c.dx + r * 0.95, c.dy + r * 0.82),
      bottomLeft: Offset(c.dx - r * 0.95, c.dy + r * 0.82),
    );
  }

  /// Barycenter of the upright triangle (visual balance point for the arrow).
  static Offset triangleCentroid(Offset c, double r) {
    final v = triangleVertices(c, r);
    return Offset(
      (v.apex.dx + v.bottomRight.dx + v.bottomLeft.dx) / 3,
      (v.apex.dy + v.bottomRight.dy + v.bottomLeft.dy) / 3,
    );
  }

  /// True when [p] lies inside or on the triangle defined by [shapePath].
  static bool pointInTriangle(Offset p, Offset c, double r) {
    final v = triangleVertices(c, r);
    return _barycentricInside(p, v.apex, v.bottomRight, v.bottomLeft);
  }

  /// Chevron path + tip for triangle pieces, inset so stroke stays inside.
  static ({Path path, Offset tip, Offset left, Offset right, Offset origin})
  triangleArrowGlyph({
    required Offset shapeCenter,
    required double radius,
    required Direction direction,
    required double strokeWidth,
  }) {
    final origin = triangleCentroid(shapeCenter, radius);
    // Half-stroke clearance + pad so tip/wings never kiss the silhouette.
    final edgeInset = strokeWidth * 0.55 + math.max(2.2, radius * 0.1);

    final unit = switch (direction) {
      Direction.up => const Offset(0, -1),
      Direction.right => const Offset(1, 0),
      Direction.down => const Offset(0, 1),
      Direction.left => const Offset(-1, 0),
    };

    // One shared tip length (tightest cardinal) keeps all four marks balanced
    // on the barycenter — avoids asymmetric per-wing inset on L/R.
    final tightestReach = Direction.values
        .map(
          (d) => _rayDistanceToTriangleEdge(
            origin,
            switch (d) {
              Direction.up => const Offset(0, -1),
              Direction.right => const Offset(1, 0),
              Direction.down => const Offset(0, 1),
              Direction.left => const Offset(-1, 0),
            },
            shapeCenter,
            radius,
          ),
        )
        .reduce(math.min);
    final tipLen = (tightestReach - edgeInset).clamp(
      radius * 0.2,
      radius * 0.34,
    );
    final tip = origin + unit * tipLen;

    // Wings sit behind the tip toward the centroid; symmetric about [unit].
    final wingDepth = tipLen * 0.58;
    final wingSpread = tipLen * 0.34;
    final back = tip - unit * wingDepth;
    final perp = Offset(-unit.dy, unit.dx);
    final left = back + perp * wingSpread;
    final right = back - perp * wingSpread;

    final path = Path()
      ..moveTo(left.dx, left.dy)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(right.dx, right.dy);

    return (path: path, tip: tip, left: left, right: right, origin: origin);
  }

  /// Samples the chevron polyline expanded by half [strokeWidth].
  /// Every sample must remain inside the triangle (geometric safety).
  static bool triangleArrowStrokeContained({
    required Offset shapeCenter,
    required double radius,
    required Direction direction,
    required double strokeWidth,
  }) {
    final glyph = triangleArrowGlyph(
      shapeCenter: shapeCenter,
      radius: radius,
      direction: direction,
      strokeWidth: strokeWidth,
    );
    final half = strokeWidth * 0.5;
    final centerline = <Offset>[
      glyph.tip,
      glyph.left,
      glyph.right,
      glyph.origin,
      ..._sampleSegment(glyph.left, glyph.tip, 10),
      ..._sampleSegment(glyph.right, glyph.tip, 10),
    ];
    for (final p in centerline) {
      if (!pointInTriangle(p, shapeCenter, radius)) return false;
      // Stroke centerline must keep ≥ half-stroke clearance from edges.
      if (_minDistanceToEdges(p, shapeCenter, radius) < half - 0.05) {
        return false;
      }
    }
    // Cap discs may reach the safe boundary but must stay inside the fill.
    for (final p in [
      ..._sampleDisc(glyph.tip, half, 16),
      ..._sampleDisc(glyph.left, half, 12),
      ..._sampleDisc(glyph.right, half, 12),
    ]) {
      if (!pointInTriangle(p, shapeCenter, radius)) return false;
    }
    return true;
  }

  static Offset tipOf(Offset c, double len, Direction d) => switch (d) {
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
        final v = triangleVertices(c, r);
        return Path()
          ..moveTo(v.apex.dx, v.apex.dy)
          ..lineTo(v.bottomRight.dx, v.bottomRight.dy)
          ..lineTo(v.bottomLeft.dx, v.bottomLeft.dy)
          ..close();
    }
  }

  static Path arrowPath(Offset c, double len, Direction direction) {
    final tip = tipOf(c, len, direction);
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

  static bool _barycentricInside(Offset p, Offset a, Offset b, Offset c) {
    final v0x = c.dx - a.dx;
    final v0y = c.dy - a.dy;
    final v1x = b.dx - a.dx;
    final v1y = b.dy - a.dy;
    final v2x = p.dx - a.dx;
    final v2y = p.dy - a.dy;
    final dot00 = v0x * v0x + v0y * v0y;
    final dot01 = v0x * v1x + v0y * v1y;
    final dot02 = v0x * v2x + v0y * v2y;
    final dot11 = v1x * v1x + v1y * v1y;
    final dot12 = v1x * v2x + v1y * v2y;
    final denom = dot00 * dot11 - dot01 * dot01;
    if (denom.abs() < 1e-9) return false;
    final u = (dot11 * dot02 - dot01 * dot12) / denom;
    final v = (dot00 * dot12 - dot01 * dot02) / denom;
    return u >= -1e-6 && v >= -1e-6 && (u + v) <= 1 + 1e-6;
  }

  static double _rayDistanceToTriangleEdge(
    Offset origin,
    Offset unit,
    Offset shapeCenter,
    double radius,
  ) {
    final v = triangleVertices(shapeCenter, radius);
    final edges = [
      (v.apex, v.bottomRight),
      (v.bottomRight, v.bottomLeft),
      (v.bottomLeft, v.apex),
    ];
    var best = double.infinity;
    for (final (a, b) in edges) {
      final hit = _raySegmentIntersection(origin, unit, a, b);
      if (hit != null && hit > 1e-6 && hit < best) best = hit;
    }
    return best.isFinite ? best : radius * 0.4;
  }

  /// Ray origin+t*unit vs segment a→b; returns t > 0 or null.
  static double? _raySegmentIntersection(
    Offset origin,
    Offset unit,
    Offset a,
    Offset b,
  ) {
    final rx = unit.dx;
    final ry = unit.dy;
    final sx = b.dx - a.dx;
    final sy = b.dy - a.dy;
    final denom = rx * sy - ry * sx;
    if (denom.abs() < 1e-9) return null;
    final qpx = a.dx - origin.dx;
    final qpy = a.dy - origin.dy;
    final t = (qpx * sy - qpy * sx) / denom;
    final u = (qpx * ry - qpy * rx) / denom;
    if (t > 1e-6 && u >= -1e-6 && u <= 1 + 1e-6) return t;
    return null;
  }

  static Offset _insetToward(
    Offset point,
    Offset origin,
    Offset shapeCenter,
    double radius,
    double inset,
  ) {
    var p = point;
    for (var i = 0; i < 8; i++) {
      if (_minDistanceToEdges(p, shapeCenter, radius) >= inset &&
          pointInTriangle(p, shapeCenter, radius)) {
        return p;
      }
      p = Offset.lerp(p, origin, 0.18)!;
    }
    return origin;
  }

  static double _minDistanceToEdges(Offset p, Offset c, double r) {
    final v = triangleVertices(c, r);
    return math.min(
      _distancePointToSegment(p, v.apex, v.bottomRight),
      math.min(
        _distancePointToSegment(p, v.bottomRight, v.bottomLeft),
        _distancePointToSegment(p, v.bottomLeft, v.apex),
      ),
    );
  }

  static double _distancePointToSegment(Offset p, Offset a, Offset b) {
    final abx = b.dx - a.dx;
    final aby = b.dy - a.dy;
    final apx = p.dx - a.dx;
    final apy = p.dy - a.dy;
    final abLen2 = abx * abx + aby * aby;
    if (abLen2 < 1e-9) return math.sqrt(apx * apx + apy * apy);
    final t = ((apx * abx + apy * aby) / abLen2).clamp(0.0, 1.0);
    final proj = Offset(a.dx + abx * t, a.dy + aby * t);
    final dx = p.dx - proj.dx;
    final dy = p.dy - proj.dy;
    return math.sqrt(dx * dx + dy * dy);
  }

  static List<Offset> _sampleSegment(Offset a, Offset b, int n) {
    return [
      for (var i = 1; i < n; i++) Offset.lerp(a, b, i / n)!,
    ];
  }

  static List<Offset> _sampleDisc(Offset c, double r, int n) {
    return [
      for (var i = 0; i < n; i++)
        Offset(
          c.dx + r * math.cos(2 * math.pi * i / n),
          c.dy + r * math.sin(2 * math.pi * i / n),
        ),
    ];
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
