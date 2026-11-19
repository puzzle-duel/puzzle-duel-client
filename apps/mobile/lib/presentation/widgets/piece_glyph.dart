import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/premium_shape_atlas.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/premium_shape_materials.dart';
import 'package:puzzle_duel_mobile/theme/game_tokens.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

/// Canonical premium piece glyph (PZD-47).
///
/// Board and tray share [PiecePainter], which draws the same full-piece
/// sprites extracted from the app icon ([PremiumShapeAtlas]). Direction is
/// applied by rotating the whole sprite so the icon object stays identical
/// (flattened raster has no separable chevron layer).
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
    final alpha = muted ? 0.35 : 1.0;
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
            fill: PremiumShapeMaterials.fill(piece.shape).withValues(alpha: alpha),
            deep: PremiumShapeMaterials.deep(piece.shape).withValues(alpha: alpha),
            stroke: selected
                ? GameTokens.textPrimary
                : PremiumShapeMaterials.directionInset,
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
    final side = size.shortestSide;
    final shape = piece.shape;
    final atlas = PremiumShapeAtlas.isLoaded ? PremiumShapeAtlas.instance : null;

    // Soft contact shadow without MaskFilter.blur (avoids iOS first-frame hitch).
    canvas.drawPath(
      path.shift(Offset(side * 0.028, side * 0.055)),
      Paint()
        ..color = PremiumShapeMaterials.contactShadow.withValues(
          alpha: selected ? 0.42 : 0.30,
        )
        ..style = PaintingStyle.fill,
    );

    if (atlas != null) {
      _paintCanonicalRaster(canvas, size, center, radius, side, shape, atlas);
    } else {
      _paintProceduralFallback(canvas, center, radius, side, shape);
    }

    if (selected) {
      canvas.drawPath(
        path,
        Paint()
          ..color = stroke.withValues(alpha: 0.95)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2.6, side * 0.065),
      );
    }
  }

  /// Draws clipped icon-quadrant sprites (same attachment pixels as the app icon).
  ///
  /// Direction rotates the whole sprite relative to icon-native orientation
  /// (circle/triangle UP, diamond LEFT). Flattened raster has no separable
  /// chevron layer — see AC03_DELTA_AND_CANONICAL_FIX.md.
  void _paintCanonicalRaster(
    Canvas canvas,
    Size size,
    Offset center,
    double radius,
    double side,
    Shape shape,
    PremiumShapeAtlas atlas,
  ) {
    final desiredTurns = switch (piece.direction) {
      Direction.up => 0,
      Direction.right => 1,
      Direction.down => 2,
      Direction.left => 3,
    };
    final deltaTurns =
        (desiredTurns - PremiumShapeAtlas.nativeTurnsFromUp(shape)) % 4;
    final body = atlas.bodyFor(shape);
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..isAntiAlias = true
      ..color = Color.fromRGBO(255, 255, 255, fill.a);
    final dstSide = radius * 2.15;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    final origin = glyphOrigin(Offset.zero, radius, shape);
    canvas.translate(origin.dx, origin.dy);
    if (deltaTurns != 0) {
      canvas.rotate(deltaTurns * math.pi / 2);
    }
    canvas.drawImageRect(
      body,
      Rect.fromLTWH(0, 0, body.width.toDouble(), body.height.toDouble()),
      Rect.fromCenter(center: Offset.zero, width: dstSide, height: dstSide),
      paint,
    );
    canvas.restore();
  }

  /// Used only if atlas is not loaded yet (should be rare; tests preload).
  void _paintProceduralFallback(
    Canvas canvas,
    Offset center,
    double radius,
    double side,
    Shape shape,
  ) {
    final path = shapePath(center, radius, shape);
    final bounds = Rect.fromCircle(center: center, radius: radius);
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [fill, deep],
        ).createShader(bounds),
    );
    final arrowStroke = directionArrowStroke(side);
    final glyph = directionGlyph(
      shape: shape,
      shapeCenter: center,
      radius: radius,
      direction: piece.direction,
      strokeWidth: arrowStroke,
    );
    final inset = PremiumShapeMaterials.directionInset.withValues(alpha: fill.a);
    canvas.drawPath(glyph.filled, Paint()..color = inset);
    canvas.drawPath(
      glyph.path,
      Paint()
        ..color = inset
        ..style = PaintingStyle.stroke
        ..strokeWidth = arrowStroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  /// Shared stroke scale for the direction family (Hard 7×7 readable).
  static double directionArrowStroke(double side) =>
      math.max(2.4, side * 0.082);

  /// Backward-compatible alias used by triangle-focused tests.
  static double triangleArrowStroke(double side) => directionArrowStroke(side);

  /// Visual balance point for the direction mark inside [shape].
  static Offset glyphOrigin(Offset c, double r, Shape shape) => switch (shape) {
    Shape.triangle => triangleCentroid(c, r),
    Shape.circle || Shape.diamond => c,
  };

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

  static ({Offset north, Offset east, Offset south, Offset west}) diamondVertices(
    Offset c,
    double r,
  ) {
    return (
      north: Offset(c.dx, c.dy - r),
      east: Offset(c.dx + r, c.dy),
      south: Offset(c.dx, c.dy + r),
      west: Offset(c.dx - r, c.dy),
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

  static bool pointInShape(Offset p, Offset c, double r, Shape shape) {
    switch (shape) {
      case Shape.circle:
        final dx = p.dx - c.dx;
        final dy = p.dy - c.dy;
        return dx * dx + dy * dy <= r * r + 1e-6;
      case Shape.diamond:
        final dx = (p.dx - c.dx).abs() / r;
        final dy = (p.dy - c.dy).abs() / r;
        return dx + dy <= 1 + 1e-6;
      case Shape.triangle:
        return pointInTriangle(p, c, r);
    }
  }

  /// True when [p] lies inside or on the triangle defined by [shapePath].
  static bool pointInTriangle(Offset p, Offset c, double r) {
    final v = triangleVertices(c, r);
    return _barycentricInside(p, v.apex, v.bottomRight, v.bottomLeft);
  }

  /// Unified filled-chevron direction mark for all piece shapes.
  static ({
    Path path,
    Path filled,
    Offset tip,
    Offset left,
    Offset right,
    Offset origin,
  })
  directionGlyph({
    required Shape shape,
    required Offset shapeCenter,
    required double radius,
    required Direction direction,
    required double strokeWidth,
  }) {
    final origin = glyphOrigin(shapeCenter, radius, shape);
    final edgeInset = strokeWidth * 0.5 + math.max(1.2, radius * 0.045);

    Offset unitFor(Direction d) => switch (d) {
      Direction.up => const Offset(0, -1),
      Direction.right => const Offset(1, 0),
      Direction.down => const Offset(0, 1),
      Direction.left => const Offset(-1, 0),
    };
    final unit = unitFor(direction);

    final tightestReach = Direction.values
        .map(
          (d) => _rayDistanceToShapeEdge(
            origin,
            unitFor(d),
            shapeCenter,
            radius,
            shape,
          ),
        )
        .reduce(math.min);

    var tipLen = (tightestReach - edgeInset) * 0.98;
    tipLen = tipLen.clamp(radius * 0.3, radius * 0.52);
    var wingDepthFactor = 0.82;
    var wingSpreadFactor = 0.56;

    late Offset tip;
    late Offset left;
    late Offset right;
    for (var attempt = 0; attempt < 16; attempt++) {
      tip = origin + unit * tipLen;
      final wingDepth = tipLen * wingDepthFactor;
      final wingSpread = tipLen * wingSpreadFactor;
      final back = tip - unit * wingDepth;
      final perp = Offset(-unit.dy, unit.dx);
      left = back + perp * wingSpread;
      right = back - perp * wingSpread;

      if (_arrowPointsContained(
        shape: shape,
        shapeCenter: shapeCenter,
        radius: radius,
        strokeWidth: strokeWidth,
        tip: tip,
        left: left,
        right: right,
        origin: origin,
      )) {
        break;
      }
      if (wingSpreadFactor > 0.4) {
        wingSpreadFactor *= 0.94;
      } else if (wingDepthFactor > 0.65) {
        wingDepthFactor *= 0.96;
      } else {
        tipLen *= 0.94;
      }
    }

    final path = Path()
      ..moveTo(left.dx, left.dy)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(right.dx, right.dy);
    final filled = Path()
      ..moveTo(left.dx, left.dy)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(right.dx, right.dy)
      ..close();

    return (
      path: path,
      filled: filled,
      tip: tip,
      left: left,
      right: right,
      origin: origin,
    );
  }

  /// Triangle wrapper kept for existing geometry tests.
  static ({
    Path path,
    Path filled,
    Offset tip,
    Offset left,
    Offset right,
    Offset origin,
  })
  triangleArrowGlyph({
    required Offset shapeCenter,
    required double radius,
    required Direction direction,
    required double strokeWidth,
  }) {
    return directionGlyph(
      shape: Shape.triangle,
      shapeCenter: shapeCenter,
      radius: radius,
      direction: direction,
      strokeWidth: strokeWidth,
    );
  }

  static bool directionArrowStrokeContained({
    required Shape shape,
    required Offset shapeCenter,
    required double radius,
    required Direction direction,
    required double strokeWidth,
  }) {
    final glyph = directionGlyph(
      shape: shape,
      shapeCenter: shapeCenter,
      radius: radius,
      direction: direction,
      strokeWidth: strokeWidth,
    );
    return _arrowPointsContained(
      shape: shape,
      shapeCenter: shapeCenter,
      radius: radius,
      strokeWidth: strokeWidth,
      tip: glyph.tip,
      left: glyph.left,
      right: glyph.right,
      origin: glyph.origin,
    );
  }

  static bool triangleArrowStrokeContained({
    required Offset shapeCenter,
    required double radius,
    required Direction direction,
    required double strokeWidth,
  }) {
    return directionArrowStrokeContained(
      shape: Shape.triangle,
      shapeCenter: shapeCenter,
      radius: radius,
      direction: direction,
      strokeWidth: strokeWidth,
    );
  }

  static bool _arrowPointsContained({
    required Shape shape,
    required Offset shapeCenter,
    required double radius,
    required double strokeWidth,
    required Offset tip,
    required Offset left,
    required Offset right,
    required Offset origin,
  }) {
    final half = strokeWidth * 0.5;
    final centerline = <Offset>[
      tip,
      left,
      right,
      origin,
      ..._sampleSegment(left, tip, 10),
      ..._sampleSegment(right, tip, 10),
      Offset.lerp(left, right, 0.5)!,
      Offset.lerp(Offset.lerp(left, right, 0.5)!, tip, 0.5)!,
    ];
    for (final p in centerline) {
      if (!pointInShape(p, shapeCenter, radius, shape)) return false;
      if (_minDistanceToShapeEdges(p, shapeCenter, radius, shape) < half - 0.05) {
        return false;
      }
    }
    for (final p in [
      ..._sampleDisc(tip, half, 16),
      ..._sampleDisc(left, half, 12),
      ..._sampleDisc(right, half, 12),
    ]) {
      if (!pointInShape(p, shapeCenter, radius, shape)) return false;
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
        // Square rotated 45° about Z with soft corners (icon diamond).
        final v = diamondVertices(c, r);
        return roundedPolygon(
          [v.north, v.east, v.south, v.west],
          r * 0.22,
        );
      case Shape.triangle:
        final v = triangleVertices(c, r);
        return roundedPolygon(
          [v.apex, v.bottomRight, v.bottomLeft],
          r * 0.20,
        );
    }
  }

  /// Rounded polygon used by icon-faithful diamond / triangle silhouettes.
  static Path roundedPolygon(List<Offset> points, double cornerRadius) {
    assert(points.length >= 3);
    final path = Path();
    final n = points.length;
    for (var i = 0; i < n; i++) {
      final prev = points[(i - 1 + n) % n];
      final curr = points[i];
      final next = points[(i + 1) % n];
      final toPrev = prev - curr;
      final toNext = next - curr;
      final lenPrev = toPrev.distance;
      final lenNext = toNext.distance;
      if (lenPrev < 1e-6 || lenNext < 1e-6) continue;
      final r = math.min(cornerRadius, math.min(lenPrev, lenNext) * 0.45);
      final p1 = curr + (toPrev / lenPrev) * r;
      final p2 = curr + (toNext / lenNext) * r;
      if (i == 0) {
        path.moveTo(p1.dx, p1.dy);
      } else {
        path.lineTo(p1.dx, p1.dy);
      }
      path.quadraticBezierTo(curr.dx, curr.dy, p2.dx, p2.dy);
    }
    path.close();
    return path;
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

  static double _rayDistanceToShapeEdge(
    Offset origin,
    Offset unit,
    Offset shapeCenter,
    double radius,
    Shape shape,
  ) {
    switch (shape) {
      case Shape.circle:
        // |origin + t*unit - center|^2 = radius^2
        final ox = origin.dx - shapeCenter.dx;
        final oy = origin.dy - shapeCenter.dy;
        final a = unit.dx * unit.dx + unit.dy * unit.dy;
        final b = 2 * (ox * unit.dx + oy * unit.dy);
        final c = ox * ox + oy * oy - radius * radius;
        final disc = b * b - 4 * a * c;
        if (disc < 0 || a.abs() < 1e-9) return radius * 0.4;
        final sqrtDisc = math.sqrt(disc);
        final t1 = (-b - sqrtDisc) / (2 * a);
        final t2 = (-b + sqrtDisc) / (2 * a);
        final candidates = [t1, t2].where((t) => t > 1e-6);
        return candidates.isEmpty
            ? radius * 0.4
            : candidates.reduce(math.min);
      case Shape.diamond:
        final v = diamondVertices(shapeCenter, radius);
        return _rayDistanceToEdges(origin, unit, [
          (v.north, v.east),
          (v.east, v.south),
          (v.south, v.west),
          (v.west, v.north),
        ], fallback: radius * 0.4);
      case Shape.triangle:
        final v = triangleVertices(shapeCenter, radius);
        return _rayDistanceToEdges(origin, unit, [
          (v.apex, v.bottomRight),
          (v.bottomRight, v.bottomLeft),
          (v.bottomLeft, v.apex),
        ], fallback: radius * 0.4);
    }
  }

  static double _rayDistanceToEdges(
    Offset origin,
    Offset unit,
    List<(Offset, Offset)> edges, {
    required double fallback,
  }) {
    var best = double.infinity;
    for (final (a, b) in edges) {
      final hit = _raySegmentIntersection(origin, unit, a, b);
      if (hit != null && hit > 1e-6 && hit < best) best = hit;
    }
    return best.isFinite ? best : fallback;
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

  static double _minDistanceToShapeEdges(
    Offset p,
    Offset c,
    double r,
    Shape shape,
  ) {
    switch (shape) {
      case Shape.circle:
        final dx = p.dx - c.dx;
        final dy = p.dy - c.dy;
        return r - math.sqrt(dx * dx + dy * dy);
      case Shape.diamond:
        final v = diamondVertices(c, r);
        return [
          _distancePointToSegment(p, v.north, v.east),
          _distancePointToSegment(p, v.east, v.south),
          _distancePointToSegment(p, v.south, v.west),
          _distancePointToSegment(p, v.west, v.north),
        ].reduce(math.min);
      case Shape.triangle:
        final v = triangleVertices(c, r);
        return [
          _distancePointToSegment(p, v.apex, v.bottomRight),
          _distancePointToSegment(p, v.bottomRight, v.bottomLeft),
          _distancePointToSegment(p, v.bottomLeft, v.apex),
        ].reduce(math.min);
    }
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
