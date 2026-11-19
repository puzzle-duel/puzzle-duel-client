import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/premium/optical_tier.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/premium/shape_geometry.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

void main() {
  group('triangle chevron optical layout', () {
    const c = Offset(50, 50);
    const r = 40.0;

    test('silhouette stays apex-up for all chevron directions', () {
      final v = ProtoShapeGeometry.triangleVertices(c, r);
      expect(v.apex.dy, lessThan(v.bottomLeft.dy));
      expect(v.apex.dy, lessThan(v.bottomRight.dy));
      expect(v.apex.dx, closeTo(c.dx, 1e-9));
    });

    test('direction origins are not a single shared vertical offset', () {
      final origins = {
        for (final d in Direction.values)
          d: ProtoShapeGeometry.triangleChevronOrigin(
            c,
            r,
            direction: d,
            tier: ProtoOpticalTier.board,
          ),
      };
      expect(origins[Direction.up]!.dy, isNot(origins[Direction.down]!.dy));
      expect(origins[Direction.left]!.dx, isNot(origins[Direction.right]!.dx));
      // Distinct pair-wise positions.
      final pts = origins.values.toSet();
      expect(pts.length, 4);
    });

    test('filled chevron stays inside inset face for all dirs × tiers', () {
      for (final tier in ProtoOpticalTier.values) {
        for (final d in Direction.values) {
          final faceFrac = ProtoShapeGeometry.triangleSafeFaceFrac(tier);
          final face = ProtoShapeGeometry.facePath(c, r, Shape.triangle, faceFrac);
          final stroke = 4.0 * tier.chevronScale;
          final glyph = ProtoShapeGeometry.triangleChevron(
            bodyCenter: c,
            bodyRadius: r,
            direction: d,
            stroke: stroke,
            scale: tier.chevronScale * 0.94,
            tier: tier,
          );
          final bounds = glyph.filled.getBounds();
          // Sample corners of the chevron AABB must lie in/near the face.
          final samples = <Offset>[
            bounds.center,
            bounds.topCenter,
            bounds.bottomCenter,
            bounds.centerLeft,
            bounds.centerRight,
          ];
          for (final p in samples) {
            expect(
              face.contains(p),
              isTrue,
              reason: 'tier=$tier dir=$d sample=$p outside face',
            );
          }
        }
      }
    });
  });
}
