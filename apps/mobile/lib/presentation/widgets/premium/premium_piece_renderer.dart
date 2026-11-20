import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/premium/material_palette.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/premium/optical_tier.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/premium/shape_geometry.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

/// PZD-47 premium piece glyph — pixel-reference-driven layered paint.
///
/// Body lighting stays fixed;
/// only the chevron follows [direction].
final class ProtoPremiumPiece extends StatelessWidget {
  const ProtoPremiumPiece({
    super.key,
    required this.shape,
    this.direction = Direction.up,
    this.size = 180,
    this.tier,
  });

  final Shape shape;
  final Direction direction;
  final double size;
  final ProtoOpticalTier? tier;

  @override
  Widget build(BuildContext context) {
    final resolved = tier ?? ProtoOpticalTierX.forSize(size);
    return CustomPaint(
      size: Size.square(size),
      painter: PremiumPieceRenderer(
        shape: shape,
        direction: direction,
        tier: resolved,
      ),
    );
  }
}

/// Layered CustomPainter implementing L1–L12 material stack.
final class PremiumPieceRenderer extends CustomPainter {
  PremiumPieceRenderer({
    required this.shape,
    required this.direction,
    required this.tier,
  });

  final Shape shape;
  final Direction direction;
  final ProtoOpticalTier tier;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    // Leave room for shadow + extrusion inside the box.
    final radius = side * 0.38;
    final center = Offset(size.width / 2, size.height / 2 - side * 0.02);
    final outer = ProtoShapeGeometry.outerPath(center, radius, shape);
    final extrude = side * tier.extrusionFrac;
    final faceInset = 1.0 - tier.bevelFrac * 1.35;
    final face = ProtoShapeGeometry.facePath(center, radius, shape, faceInset);
    final bounds = Rect.fromCircle(center: center, radius: radius);

    _paintAmbientBounce(canvas, outer, side);
    _paintContactShadow(canvas, outer, side);
    _paintExtrusion(canvas, center, radius, extrude);
    _paintOuterBevel(canvas, outer, bounds);
    _paintFace(canvas, face, center, radius * faceInset);
    _paintInnerShade(canvas, face, center, radius * faceInset);
    _paintSpecular(canvas, face, center, radius * faceInset);
    if (tier.drawEdgeStreaks) {
      _paintEdgeStreaks(canvas, outer, face, side);
    }
    if (tier.drawGlints) {
      _paintGlints(canvas, center, radius);
    }
    _paintChevron(canvas, center, radius, side);
  }

  // —— L2 ambient bounce ——
  void _paintAmbientBounce(Canvas canvas, Path outer, double side) {
    final alpha = tier.bounceAlpha;
    if (alpha < 0.02) return;
    final glow = outer.shift(Offset(side * 0.01, side * 0.06));
    final paint = Paint()
      ..color = ProtoMaterialPalette.bounce(shape).withValues(alpha: alpha);
    // Avoid MaskFilter on board tier (GPU hitch + noise at cell size).
    if (tier != ProtoOpticalTier.board) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, side * 0.055);
    }
    canvas.drawPath(glow, paint);
  }

  // —— L1 contact shadow ——
  void _paintContactShadow(Canvas canvas, Path outer, double side) {
    canvas.drawPath(
      outer.shift(Offset(side * 0.028, side * 0.055)),
      Paint()..color = const Color(0x66000000),
    );
    canvas.drawPath(
      outer.shift(Offset(side * 0.012, side * 0.028)),
      Paint()..color = const Color(0x33000000),
    );
  }

  // —— L3 extrusion ——
  void _paintExtrusion(Canvas canvas, Offset c, double r, double extrude) {
    final back = ProtoShapeGeometry.outerPath(
      c.translate(0, extrude),
      r,
      shape,
    );
    final front = ProtoShapeGeometry.outerPath(c, r, shape);
    // Side band = back minus roughly the overlapping front projection.
    canvas.drawPath(
      back,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            ProtoMaterialPalette.extrusion(shape),
            ProtoMaterialPalette.shade(shape),
          ],
        ).createShader(Rect.fromCircle(center: c.translate(0, extrude), radius: r)),
    );
    // Ensure front silhouette will cover the upper part of extrusion.
    canvas.drawPath(front, Paint()..color = ProtoMaterialPalette.shade(shape));
  }

  // —— L4 outer bevel ——
  void _paintOuterBevel(Canvas canvas, Path outer, Rect bounds) {
    canvas.drawPath(
      outer,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ProtoMaterialPalette.bevelHi(shape),
            ProtoMaterialPalette.face(shape),
            ProtoMaterialPalette.bevelLo(shape),
            ProtoMaterialPalette.shade(shape),
          ],
          stops: const [0.0, 0.28, 0.72, 1.0],
        ).createShader(bounds),
    );
  }

  // —— L5 main face ——
  void _paintFace(Canvas canvas, Path face, Offset c, double r) {
    final bounds = Rect.fromCircle(center: c, radius: r);
    // Primary diagonal ramp.
    canvas.drawPath(
      face,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ProtoMaterialPalette.faceUl(shape),
            ProtoMaterialPalette.face(shape),
            ProtoMaterialPalette.faceUr(shape),
            ProtoMaterialPalette.faceLl(shape),
            ProtoMaterialPalette.faceLr(shape),
          ],
          stops: const [0.0, 0.28, 0.48, 0.72, 1.0],
        ).createShader(bounds),
    );
    // Secondary curvature wash (screen — keeps chroma lively).
    canvas.drawPath(
      face,
      Paint()
        ..blendMode = BlendMode.screen
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          radius: 1.05,
          colors: [
            Colors.white.withValues(alpha: 0.42),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(bounds),
    );
  }

  // —— L6 inner LR shade ——
  void _paintInnerShade(Canvas canvas, Path face, Offset c, double r) {
    canvas.save();
    canvas.clipPath(face);
    final rect = Rect.fromCenter(
      center: c.translate(r * 0.35, r * 0.42),
      width: r * 1.4,
      height: r * 1.2,
    );
    canvas.drawOval(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            ProtoMaterialPalette.shade(shape).withValues(alpha: 0.5),
            ProtoMaterialPalette.shade(shape).withValues(alpha: 0.0),
          ],
        ).createShader(rect),
    );
    canvas.restore();
  }

  // —— L7/L8 specular (shape-specific) ——
  void _paintSpecular(Canvas canvas, Path face, Offset c, double r) {
    canvas.save();
    canvas.clipPath(face);
    switch (shape) {
      case Shape.circle:
        _circleSpecular(canvas, c, r);
      case Shape.diamond:
        _diamondSpecular(canvas, c, r);
      case Shape.triangle:
        _hexagonSpecular(canvas, c, r);
    }
    canvas.restore();
  }

  void _circleSpecular(Canvas canvas, Offset c, double r) {
    // Large curved UL bloom — crescent-ish via offset ovals.
    final main = Rect.fromCenter(
      center: c.translate(-r * 0.28, -r * 0.38),
      width: r * 1.35,
      height: r * 0.85,
    );
    canvas.drawOval(
      main,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.92),
            const Color(0xFFC8FFE8).withValues(alpha: 0.35),
            Colors.white.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.4, 1.0],
        ).createShader(main),
    );
    if (tier.drawSecondarySpecular) {
      final sec = Rect.fromCenter(
        center: c.translate(-r * 0.48, -r * 0.18),
        width: r * 0.55,
        height: r * 0.38,
      );
      canvas.drawOval(
        sec,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.7),
              Colors.white.withValues(alpha: 0.0),
            ],
          ).createShader(sec),
      );
      // LR cyan rim wash.
      final rim = Rect.fromCenter(
        center: c.translate(r * 0.42, r * 0.38),
        width: r * 0.7,
        height: r * 0.45,
      );
      canvas.drawOval(
        rim,
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFF09AAAB).withValues(alpha: 0.65),
              const Color(0xFF09AAAB).withValues(alpha: 0.0),
            ],
          ).createShader(rim),
      );
    }
  }

  void _diamondSpecular(Canvas canvas, Offset c, double r) {
    // Elongated highlight along UL diagonal.
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-math.pi / 4);
    final band = Rect.fromCenter(
      center: Offset(-r * 0.15, -r * 0.35),
      width: r * 1.55,
      height: r * 0.42,
    );
    canvas.drawOval(
      band,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.95),
            const Color(0xFFF3C8FF).withValues(alpha: 0.4),
            Colors.white.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.35, 1.0],
        ).createShader(band),
    );
    canvas.restore();

    if (tier.drawSecondarySpecular) {
      final patch = Rect.fromCenter(
        center: c.translate(-r * 0.12, -r * 0.08),
        width: r * 0.85,
        height: r * 0.55,
      );
      canvas.drawOval(
        patch,
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFFEC91FA).withValues(alpha: 0.55),
              const Color(0xFFEC91FA).withValues(alpha: 0.0),
            ],
          ).createShader(patch),
      );
      final lr = Rect.fromCenter(
        center: c.translate(r * 0.38, r * 0.42),
        width: r * 0.55,
        height: r * 0.35,
      );
      canvas.drawOval(
        lr,
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFFE0A0FF).withValues(alpha: 0.55),
              Colors.transparent,
            ],
          ).createShader(lr),
      );
    }
  }

  void _hexagonSpecular(Canvas canvas, Offset c, double r) {
    // Broad UL soft bloom across flat-top face.
    final main = Rect.fromCenter(
      center: c.translate(-r * 0.18, -r * 0.28),
      width: r * 1.25,
      height: r * 0.72,
    );
    canvas.drawOval(
      main,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.9),
            const Color(0xFFFFF8D0).withValues(alpha: 0.38),
            Colors.transparent,
          ],
          stops: const [0.0, 0.42, 1.0],
        ).createShader(main),
    );

    if (tier.drawSecondarySpecular) {
      final base = Rect.fromCenter(
        center: c.translate(0, r * 0.48),
        width: r * 1.2,
        height: r * 0.28,
      );
      canvas.drawOval(
        base,
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFFFFD060).withValues(alpha: 0.55),
              Colors.transparent,
            ],
          ).createShader(base),
      );
      final adj = Rect.fromCenter(
        center: c.translate(-r * 0.22, -r * 0.05),
        width: r * 0.55,
        height: r * 0.4,
      );
      canvas.drawOval(
        adj,
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFFFBEA98).withValues(alpha: 0.45),
              Colors.transparent,
            ],
          ).createShader(adj),
      );
    }
  }

  // —— L9 edge streaks ——
  void _paintEdgeStreaks(Canvas canvas, Path outer, Path face, double side) {
    canvas.save();
    canvas.clipPath(outer);
    canvas.drawPath(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.4, side * 0.028)
        ..shader = SweepGradient(
          colors: [
            Colors.white.withValues(alpha: 0.0),
            Colors.white.withValues(alpha: 0.7),
            Colors.white.withValues(alpha: 0.15),
            ProtoMaterialPalette.faceLr(shape).withValues(alpha: 0.55),
            Colors.white.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.12, 0.35, 0.72, 1.0],
          transform: const GradientRotation(-0.9),
        ).createShader(outer.getBounds()),
    );
    canvas.drawPath(
      face,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, side * 0.016)
        ..color = Colors.white.withValues(alpha: 0.22),
    );
    canvas.restore();
  }

  // —— L10 glints (hero only) ——
  void _paintGlints(Canvas canvas, Offset c, double r) {
    final spots = switch (shape) {
      Shape.circle => [
        c.translate(-r * 0.42, -r * 0.48),
        c.translate(r * 0.52, r * 0.28),
      ],
      Shape.diamond => [
        c.translate(-r * 0.08, -r * 0.72),
        c.translate(-r * 0.55, -r * 0.15),
        c.translate(r * 0.55, r * 0.35),
      ],
      Shape.triangle => [
        c.translate(-r * 0.28, -r * 0.42),
        c.translate(r * 0.42, r * 0.18),
      ],
    };
    for (final p in spots) {
      canvas.drawCircle(
        p,
        r * 0.035,
        Paint()..color = Colors.white.withValues(alpha: 0.85),
      );
    }
  }

  // —— L11 direction arrow: ONE solid chevron stroke (no cavity / rim / glow)
  void _paintChevron(Canvas canvas, Offset c, double r, double side) {
    final layout = ProtoShapeGeometry.chevronLayout(
      bodyCenter: c,
      bodyRadius: r,
      shape: shape,
      direction: direction,
      tier: tier,
    );
    final path = ProtoShapeGeometry.chevronSpine(
      origin: layout.origin,
      radius: layout.radius,
      direction: direction,
      scale: 1.0,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = ProtoShapeGeometry.directionInk
        ..style = PaintingStyle.stroke
        ..strokeWidth = ProtoShapeGeometry.chevronStrokeWidth(side, tier)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant PremiumPieceRenderer oldDelegate) {
    return oldDelegate.shape != shape ||
        oldDelegate.direction != direction ||
        oldDelegate.tier != tier;
  }
}

/// Convenience: rasterize a prototype piece to [ui.Image] for metrics/tests.
Future<ui.Image> renderProtoPieceImage({
  required Shape shape,
  required Direction direction,
  required double size,
  ProtoOpticalTier? tier,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  PremiumPieceRenderer(
    shape: shape,
    direction: direction,
    tier: tier ?? ProtoOpticalTierX.forSize(size),
  ).paint(canvas, Size.square(size));
  final picture = recorder.endRecording();
  return picture.toImage(size.ceil(), size.ceil());
}
