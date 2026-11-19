import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

/// Pure geometry helpers for the PZD-47 prototype renderer.
abstract final class ProtoShapeGeometry {
  static Path outerPath(Offset c, double r, Shape shape) {
    switch (shape) {
      case Shape.circle:
        return Path()..addOval(Rect.fromCircle(center: c, radius: r));
      case Shape.diamond:
        final v = diamondVertices(c, r);
        return roundedPolygon([v.north, v.east, v.south, v.west], r * 0.18);
      case Shape.triangle:
        final v = triangleVertices(c, r);
        return roundedPolygon(
          [v.apex, v.bottomRight, v.bottomLeft],
          r * 0.22,
        );
    }
  }

  static Path facePath(Offset c, double r, Shape shape, double inset) =>
      outerPath(c, r * inset, shape);

  static ({Offset north, Offset east, Offset south, Offset west})
  diamondVertices(Offset c, double r) => (
    north: Offset(c.dx, c.dy - r),
    east: Offset(c.dx + r, c.dy),
    south: Offset(c.dx, c.dy + r),
    west: Offset(c.dx - r, c.dy),
  );

  static ({Offset apex, Offset bottomRight, Offset bottomLeft})
  triangleVertices(Offset c, double r) => (
    apex: Offset(c.dx, c.dy - r),
    bottomRight: Offset(c.dx + r * 0.95, c.dy + r * 0.82),
    bottomLeft: Offset(c.dx - r * 0.95, c.dy + r * 0.82),
  );

  /// Optical balance point (triangle uses centroid).
  static Offset glyphOrigin(Offset c, double r, Shape shape) => switch (shape) {
    Shape.triangle => () {
      final v = triangleVertices(c, r);
      return Offset(
        (v.apex.dx + v.bottomRight.dx + v.bottomLeft.dx) / 3,
        (v.apex.dy + v.bottomRight.dy + v.bottomLeft.dy) / 3,
      );
    }(),
    Shape.circle || Shape.diamond => c,
  };

  static Path roundedPolygon(List<Offset> points, double cornerRadius) {
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
      final rr = math.min(cornerRadius, math.min(lenPrev, lenNext) * 0.45);
      final p1 = curr + (toPrev / lenPrev) * rr;
      final p2 = curr + (toNext / lenNext) * rr;
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

  /// Filled chevron cavity (independent of body rotation).
  static ({Path filled, Path spine}) chevron({
    required Offset origin,
    required double radius,
    required Direction direction,
    required double stroke,
    required double scale,
  }) {
    final unit = switch (direction) {
      Direction.up => const Offset(0, -1),
      Direction.right => const Offset(1, 0),
      Direction.down => const Offset(0, 1),
      Direction.left => const Offset(-1, 0),
    };
    final tipLen = radius * 0.50 * scale;
    final wingDepth = tipLen * 0.80;
    final wingSpread = tipLen * 0.58;
    final tip = origin + unit * tipLen;
    final back = tip - unit * wingDepth;
    final perp = Offset(-unit.dy, unit.dx);
    final left = back + perp * wingSpread;
    final right = back - perp * wingSpread;

    // Inflate V into a thick filled cavity via stroke outline approximation.
    final spine = Path()
      ..moveTo(left.dx, left.dy)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(right.dx, right.dy);

    final half = stroke * 0.55;
    final filled = _strokeToFilled(left, tip, right, half);

    return (filled: filled, spine: spine);
  }

  static Path _strokeToFilled(Offset left, Offset tip, Offset right, double half) {
    // Build a rounded chevron polygon around the V centerline.
    Offset n(Offset a, Offset b) {
      final d = b - a;
      final len = d.distance;
      if (len < 1e-6) return Offset.zero;
      return Offset(-d.dy / len, d.dx / len);
    }

    final n1 = n(left, tip);
    final n2 = n(tip, right);
    final outer = <Offset>[
      left + n1 * half,
      tip + ((n1 + n2) / 2) * half * 1.15,
      right + n2 * half,
      right - n2 * half,
      tip - ((n1 + n2) / 2) * half * 0.85,
      left - n1 * half,
    ];
    return roundedPolygon(outer, half * 0.9);
  }
}
