import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:puzzle_duel_mobile/badges/domain/badge_definition.dart';
import 'package:puzzle_duel_mobile/badges/domain/badge_prestige.dart';
import 'package:puzzle_duel_mobile/badges/presentation/badge_center_artwork.dart';
import 'package:puzzle_duel_mobile/badges/presentation/badge_prestige_palette.dart';
import 'package:puzzle_duel_mobile/badges/presentation/badge_vector_geometry.dart';

/// Canonical Badge Evolution medallion painter (viewBox 280×240).
final class BadgeMedallionPainter extends CustomPainter {
  BadgeMedallionPainter({
    required this.badgeId,
    required this.prestige,
    required this.earnedCount,
    required this.prestigeLabel,
    this.showCountCapsule = true,
    this.showPrestigeLabel = true,
    this.paintBackground = false,
  });

  final BadgeId badgeId;
  final BadgePrestige? prestige;
  final int earnedCount;
  final String prestigeLabel;
  final bool showCountCapsule;
  final bool showPrestigeLabel;
  final bool paintBackground;

  static final Path _firstOrnament = BadgeVectorGeometry.firstOrnamentBase();
  static final Path _secondOrnament = BadgeVectorGeometry.secondOrnamentBase();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(
      size.width / BadgeVectorGeometry.viewBoxWidth,
      size.height / BadgeVectorGeometry.viewBoxHeight,
    );
    final dx =
        (size.width - BadgeVectorGeometry.viewBoxWidth * scale) / 2;
    final dy =
        (size.height - BadgeVectorGeometry.viewBoxHeight * scale) / 2;

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);

    if (paintBackground) {
      canvas.drawRect(
        const Rect.fromLTWH(
          0,
          0,
          BadgeVectorGeometry.viewBoxWidth,
          BadgeVectorGeometry.viewBoxHeight,
        ),
        Paint()..color = BadgePrestigePalette.canvasBackground,
      );
    }

    final locked = prestige == null;
    final colors = locked
        ? BadgePrestigeColors.locked
        : BadgePrestigeColors.forPrestige(prestige!);

    if (!locked) {
      _paintAura(canvas, colors);
      if (prestige!.showsSecondOrnamentLayer) {
        _paintSecondOrnaments(canvas, colors);
      }
      if (prestige!.showsFirstOrnamentLayer) {
        _paintFirstOrnaments(canvas, colors, prestige!.firstOrnamentOpacity);
      }
      if (prestige!.showsMythicOrbit) {
        _paintMythicOrbit(canvas);
      }
    }

    _paintMedallion(canvas, colors, prestige);
    BadgeCenterArtwork.paint(
      canvas,
      id: badgeId,
      colors: colors,
      locked: locked,
    );

    if (!locked && showCountCapsule) {
      _paintCountCapsule(canvas, colors, earnedCount);
    }
    if (!locked && showPrestigeLabel && prestigeLabel.isNotEmpty) {
      _paintPrestigeLabel(canvas, colors, prestigeLabel);
    }

    canvas.restore();
  }

  void _paintAura(Canvas canvas, BadgePrestigeColors colors) {
    final center = BadgeVectorGeometry.medallionCenter;
    final paint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        BadgeVectorGeometry.auraRadius,
        [
          colors.primary.withValues(alpha: 0.28),
          colors.primary.withValues(alpha: 0.0),
        ],
      );
    canvas.drawCircle(center, BadgeVectorGeometry.auraRadius, paint);
  }

  void _paintFirstOrnaments(
    Canvas canvas,
    BadgePrestigeColors colors,
    double opacity,
  ) {
    final bounds = _firstOrnament.getBounds();
    final fill = BadgePrestigePalette.metallicFillPaint(bounds, colors)
      ..colorFilter = ColorFilter.mode(
        const Color(0xFFFFFFFF).withValues(alpha: opacity),
        BlendMode.modulate,
      );
    for (var i = 0; i < 12; i++) {
      canvas.save();
      canvas.translate(
        BadgeVectorGeometry.medallionCenter.dx,
        BadgeVectorGeometry.medallionCenter.dy,
      );
      canvas.rotate(i * 30 * math.pi / 180);
      canvas.translate(
        -BadgeVectorGeometry.medallionCenter.dx,
        -BadgeVectorGeometry.medallionCenter.dy,
      );
      canvas.drawPath(_firstOrnament, fill);
      canvas.restore();
    }
  }

  void _paintSecondOrnaments(Canvas canvas, BadgePrestigeColors colors) {
    final fill = Paint()..color = colors.highlight;
    for (var i = 0; i < 8; i++) {
      canvas.save();
      canvas.translate(
        BadgeVectorGeometry.medallionCenter.dx,
        BadgeVectorGeometry.medallionCenter.dy,
      );
      canvas.rotate(i * 45 * math.pi / 180);
      canvas.translate(
        -BadgeVectorGeometry.medallionCenter.dx,
        -BadgeVectorGeometry.medallionCenter.dy,
      );
      canvas.drawPath(_secondOrnament, fill);
      canvas.restore();
    }
  }

  void _paintMythicOrbit(Canvas canvas) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = BadgePrestigePalette.mythicOrbit;
    _drawDashedCircle(
      canvas,
      BadgeVectorGeometry.medallionCenter,
      BadgeVectorGeometry.mythicOrbitRadius,
      paint,
      dash: 3,
      gap: 9,
    );
  }

  void _drawDashedCircle(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint, {
    required double dash,
    required double gap,
  }) {
    final circumference = 2 * math.pi * radius;
    final pattern = dash + gap;
    final count = (circumference / pattern).floor();
    final path = Path();
    for (var i = 0; i < count; i++) {
      final start = (i * pattern) / radius;
      final end = (i * pattern + dash) / radius;
      path.addArc(
        Rect.fromCircle(center: center, radius: radius),
        start - math.pi / 2,
        end - start,
      );
    }
    canvas.drawPath(path, paint);
  }

  void _paintMedallion(
    Canvas canvas,
    BadgePrestigeColors colors,
    BadgePrestige? prestige,
  ) {
    final center = BadgeVectorGeometry.medallionCenter;
    final r = BadgeVectorGeometry.medallionRadius;
    final fill = Paint()
      ..shader = ui.Gradient.radial(
        center,
        r,
        [
          BadgePrestigePalette.medallionCenter,
          BadgePrestigePalette.medallionEdge,
        ],
      );
    canvas.drawCircle(center, r, fill);

    final strokeWidth = prestige?.outerStrokeWidth ?? 5;
    final ringBounds = Rect.fromCircle(center: center, radius: r);
    canvas.drawCircle(
      center,
      r,
      BadgePrestigePalette.metallicStrokePaint(
        ringBounds,
        colors,
        strokeWidth: strokeWidth,
      ),
    );

    canvas.drawCircle(
      center,
      BadgeVectorGeometry.innerBorderRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = colors.primary.withValues(alpha: 0.7),
    );
  }

  void _paintCountCapsule(
    Canvas canvas,
    BadgePrestigeColors colors,
    int count,
  ) {
    var capsule = BadgeVectorGeometry.countCapsule;
    final text = '×$count';
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: colors.highlight,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
    )..layout();

    final needed = painter.width + 16;
    if (needed > capsule.width) {
      final expand = needed - capsule.width;
      capsule = Rect.fromCenter(
        center: capsule.center,
        width: capsule.width + expand,
        height: capsule.height,
      );
    }

    final rrect = RRect.fromRectAndRadius(
      capsule,
      const Radius.circular(BadgeVectorGeometry.countCapsuleRadius),
    );
    canvas.drawRRect(
      rrect,
      Paint()..color = BadgePrestigePalette.capsuleFill,
    );
    canvas.drawRRect(
      rrect,
      BadgePrestigePalette.metallicStrokePaint(
        capsule,
        colors,
        strokeWidth: 2,
      ),
    );

    final baseline = BadgeVectorGeometry.countTextCenter.dy;
    painter.paint(
      canvas,
      Offset(
        BadgeVectorGeometry.countTextCenter.dx - painter.width / 2,
        baseline - painter.computeDistanceToActualBaseline(TextBaseline.alphabetic),
      ),
    );
  }

  void _paintPrestigeLabel(
    Canvas canvas,
    BadgePrestigeColors colors,
    String label,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: colors.highlight,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
    )..layout();
    final baseline = BadgeVectorGeometry.prestigeLabelBaseline.dy;
    painter.paint(
      canvas,
      Offset(
        BadgeVectorGeometry.prestigeLabelBaseline.dx - painter.width / 2,
        baseline - painter.computeDistanceToActualBaseline(TextBaseline.alphabetic),
      ),
    );
  }

  @override
  bool shouldRepaint(covariant BadgeMedallionPainter oldDelegate) {
    return oldDelegate.badgeId != badgeId ||
        oldDelegate.prestige != prestige ||
        oldDelegate.earnedCount != earnedCount ||
        oldDelegate.prestigeLabel != prestigeLabel ||
        oldDelegate.showCountCapsule != showCountCapsule ||
        oldDelegate.showPrestigeLabel != showPrestigeLabel ||
        oldDelegate.paintBackground != paintBackground;
  }
}
