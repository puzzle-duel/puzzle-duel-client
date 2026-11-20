import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/premium/optical_tier.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/premium/shape_geometry.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

void main() {
  group('hexagon presentation + shared chevron', () {
    const c = Offset(50, 50);
    const r = 40.0;

    test('domain triangle paints as flat-top hexagon (6 vertices)', () {
      final pts = ProtoShapeGeometry.flatTopHexagon(c, r);
      expect(pts.length, 6);
      // Top edge is horizontal.
      expect(pts[0].dy, closeTo(pts[1].dy, 1e-9));
      // Bottom edge is horizontal.
      expect(pts[3].dy, closeTo(pts[4].dy, 1e-9));
      expect(pts[0].dy, lessThan(pts[3].dy));
    });

    test('outerPath for Shape.triangle is hexagon, not triangle', () {
      final path = ProtoShapeGeometry.outerPath(c, r, Shape.triangle);
      final bounds = path.getBounds();
      // Hexagon is wider than a tall triangle at same r.
      expect(bounds.width, greaterThan(bounds.height * 0.95));
    });

    test('spine has clear V opening for all shapes × dirs × tiers', () {
      for (final shape in Shape.values) {
        for (final tier in ProtoOpticalTier.values) {
          for (final d in Direction.values) {
            final layout = ProtoShapeGeometry.chevronLayout(
              bodyCenter: c,
              bodyRadius: r,
              shape: shape,
              direction: d,
              tier: tier,
            );
            final path = ProtoShapeGeometry.chevronSpine(
              origin: layout.origin,
              radius: layout.radius,
              direction: d,
            );
            final len = path
                .computeMetrics()
                .fold<double>(0, (a, m) => a + m.length);
            expect(len, greaterThan(layout.radius * 0.7));
          }
        }
      }
    });

    test('single shared ink color', () {
      expect(ProtoShapeGeometry.directionInk, const Color(0xFF18201F));
    });
  });
}
