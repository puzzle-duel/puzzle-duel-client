import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/premium/optical_tier.dart';
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
        // Presentation mapping: domain `Shape.triangle` → golden flat-top hexagon.
        return roundedPolygon(flatTopHexagon(c, r), r * 0.14);
    }
  }

  /// Flat-top regular hexagon (fixed orientation; does not rotate with direction).
  ///
  /// Top and bottom edges are horizontal. Vertex order clockwise from top-left.
  static List<Offset> flatTopHexagon(Offset c, double r) {
    // Flat-top: width = 2R, height = √3·R where R is center→vertex distance.
    final R = r * 0.95;
    final w = R;
    final h = R * math.sqrt(3) / 2;
    return [
      Offset(c.dx - w * 0.5, c.dy - h), // top-left
      Offset(c.dx + w * 0.5, c.dy - h), // top-right
      Offset(c.dx + w, c.dy), // right
      Offset(c.dx + w * 0.5, c.dy + h), // bottom-right
      Offset(c.dx - w * 0.5, c.dy + h), // bottom-left
      Offset(c.dx - w, c.dy), // left
    ];
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

  /// Legacy upright-triangle vertices retained for historical API parity.
  ///
  /// Not used by [outerPath] — presentation for [Shape.triangle] is [flatTopHexagon].
  static ({Offset apex, Offset bottomRight, Offset bottomLeft})
  triangleVertices(Offset c, double r) => (
    apex: Offset(c.dx, c.dy - r),
    bottomRight: Offset(c.dx + r * 0.95, c.dy + r * 0.82),
    bottomLeft: Offset(c.dx - r * 0.95, c.dy + r * 0.82),
  );

  /// Optical balance point — circle / diamond / hexagon use geometric center.
  static Offset glyphOrigin(Offset c, double r, Shape shape) => c;

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

  /// Shared dark chevron ink (one stroke for all shapes).
  static const Color directionInk = Color(0xFF18201F);

  /// Canonical V-spine for one clean stroke — no filled cavity.
  ///
  /// Proportions are identical across circle / diamond / triangle so the arrow
  /// language stays recognizable; only [origin] / usable [radius] vary.
  static Path chevronSpine({
    required Offset origin,
    required double radius,
    required Direction direction,
    double scale = 1.0,
  }) {
    final unit = switch (direction) {
      Direction.up => const Offset(0, -1),
      Direction.right => const Offset(1, 0),
      Direction.down => const Offset(0, 1),
      Direction.left => const Offset(-1, 0),
    };
    // Long readable arms with a clear V opening (not a collapsed blob).
    final tipLen = radius * 0.48 * scale;
    final wingDepth = tipLen * 0.74;
    final wingSpread = tipLen * 0.62;
    final tip = origin + unit * tipLen;
    final back = tip - unit * wingDepth;
    final perp = Offset(-unit.dy, unit.dx);
    final left = back + perp * wingSpread;
    final right = back - perp * wingSpread;
    return Path()
      ..moveTo(left.dx, left.dy)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(right.dx, right.dy);
  }

  /// Stroke width for the single chevron ink path.
  /// Board stays slightly thinner so the V opening remains readable at 7×7.
  static double chevronStrokeWidth(double side, ProtoOpticalTier tier) {
    final base = math.max(2.2, side * 0.065);
    return switch (tier) {
      ProtoOpticalTier.hero => base * 1.02,
      ProtoOpticalTier.tray => base * 1.05,
      ProtoOpticalTier.board => base * 1.0,
    };
  }

  /// Origin + usable radius for the shared spine on any shape.
  static ({Offset origin, double radius}) chevronLayout({
    required Offset bodyCenter,
    required double bodyRadius,
    required Shape shape,
    required Direction direction,
    ProtoOpticalTier? tier,
  }) {
    // All three presentation silhouettes are centered; direction-only chevron.
    return (origin: bodyCenter, radius: bodyRadius * 0.95);
  }

  /// Legacy filled helper retained for geometry/containment tests only.
  static ({Path filled, Path spine}) chevron({
    required Offset origin,
    required double radius,
    required Direction direction,
    required double stroke,
    required double scale,
    bool compact = false,
    double armThick = 1.0,
  }) {
    final spine = chevronSpine(
      origin: origin,
      radius: radius * (compact ? 0.88 : 1.0),
      direction: direction,
      scale: scale,
    );
    // Approximate fill metrics for older containment probes.
    final unit = switch (direction) {
      Direction.up => const Offset(0, -1),
      Direction.right => const Offset(1, 0),
      Direction.down => const Offset(0, 1),
      Direction.left => const Offset(-1, 0),
    };
    final tipLen = radius * (compact ? 0.40 : 0.46) * scale;
    final wingDepth = tipLen * 0.78;
    final wingSpread = tipLen * 0.56;
    final tip = origin + unit * tipLen;
    final back = tip - unit * wingDepth;
    final perp = Offset(-unit.dy, unit.dx);
    final left = back + perp * wingSpread;
    final right = back - perp * wingSpread;
    final half = stroke * 0.55 * armThick;
    return (filled: _strokeToFilled(left, tip, right, half), spine: spine);
  }

  static Path _strokeToFilled(Offset left, Offset tip, Offset right, double half) {
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
