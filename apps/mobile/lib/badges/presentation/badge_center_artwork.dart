import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:puzzle_duel_mobile/badges/domain/badge_definition.dart';
import 'package:puzzle_duel_mobile/badges/presentation/badge_prestige_palette.dart';
import 'package:puzzle_duel_mobile/badges/presentation/badge_vector_geometry.dart';

/// Badge-specific center artwork for the shared medallion frame.
final class BadgeCenterArtwork {
  const BadgeCenterArtwork._();

  static void paint(
    Canvas canvas, {
    required BadgeId id,
    required BadgePrestigeColors colors,
    required bool locked,
  }) {
    final stroke = locked ? BadgePrestigeColors.locked.highlight : colors.highlight;
    final metal = locked ? BadgePrestigeColors.locked : colors;
    switch (id) {
      case BadgeId.onTime:
        _paintClock(canvas, stroke);
      case BadgeId.loyalty:
        _paintHeartShield(canvas, stroke, metal);
      case BadgeId.practiceMaster:
        _paintPieces(canvas, locked);
      case BadgeId.tournamentGuru:
        _paintCrown(canvas, stroke, metal);
      case BadgeId.champion:
        _paintTrophy(canvas, stroke, metal);
      case BadgeId.risingStar:
        _paintRisingStar(canvas, stroke, metal);
      case BadgeId.unstoppable:
        _paintFlame(canvas, stroke, metal);
    }
  }

  static void _paintClock(Canvas canvas, Color stroke) {
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = stroke;
    canvas.drawCircle(const Offset(140, 100), 31, outline);

    final hands = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = stroke;
    canvas.drawPath(
      BadgeVectorGeometry.parseSvgPath('M140 80 V101 L155 111'),
      hands,
    );

    final marker = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = stroke;
    final markerPath = BadgeVectorGeometry.parseSvgPath('M140 72 V77');
    for (final degrees in const [0.0, 90.0, 180.0, 270.0]) {
      canvas.save();
      canvas.translate(140, 100);
      canvas.rotate(degrees * math.pi / 180);
      canvas.translate(-140, -100);
      canvas.drawPath(markerPath, marker);
      canvas.restore();
    }
  }

  static void _paintHeartShield(
    Canvas canvas,
    Color stroke,
    BadgePrestigeColors metal,
  ) {
    final shield = BadgeVectorGeometry.parseSvgPath(
      'M140 64 L175 78 V101 Q175 125 140 143 Q105 125 105 101 V78 Z',
    );
    canvas.drawPath(
      shield,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round
        ..color = stroke,
    );

    final heart = BadgeVectorGeometry.parseSvgPath(
      'M140 118 C130 110 115 101 119 90 C123 80 135 82 140 91 '
      'C145 82 157 80 161 90 C165 101 150 110 140 118 Z',
    );
    final bounds = heart.getBounds();
    canvas.drawPath(heart, BadgePrestigePalette.metallicFillPaint(bounds, metal));
    canvas.drawPath(
      heart,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = stroke,
    );
  }

  static void _paintPieces(Canvas canvas, bool locked) {
    Color fill(Color c) => locked ? c.withValues(alpha: 0.35) : c;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = locked
          ? BadgePrestigeColors.locked.highlight
          : const Color(0xFFE8EEF8);

    final square = RRect.fromRectAndRadius(
      const Rect.fromLTWH(107, 73, 29, 29),
      const Radius.circular(5),
    );
    canvas.drawRRect(
      square,
      Paint()..color = fill(BadgePrestigePalette.piecePurple),
    );
    canvas.drawRRect(square, stroke);

    canvas.drawCircle(
      const Offset(157, 87),
      15,
      Paint()..color = fill(BadgePrestigePalette.pieceGreen),
    );
    canvas.drawCircle(const Offset(157, 87), 15, stroke);

    final triangle = BadgeVectorGeometry.parseSvgPath('M122 112 L139 139 H105 Z');
    canvas.drawPath(
      triangle,
      Paint()..color = fill(BadgePrestigePalette.pieceYellow),
    );
    canvas.drawPath(triangle, stroke);

    final hex = BadgeVectorGeometry.parseSvgPath(
      'M157 108 L173 117 V135 L157 144 L141 135 V117 Z',
    );
    canvas.drawPath(hex, Paint()..color = fill(BadgePrestigePalette.pieceBlue));
    canvas.drawPath(hex, stroke);
  }

  static void _paintCrown(
    Canvas canvas,
    Color stroke,
    BadgePrestigeColors metal,
  ) {
    final crown = BadgeVectorGeometry.parseSvgPath(
      'M107 84 L117 111 H163 L173 84 L153 96 L140 77 L127 96 Z',
    );
    canvas.drawPath(
      crown,
      BadgePrestigePalette.metallicFillPaint(crown.getBounds(), metal),
    );
    canvas.drawPath(
      crown,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = stroke,
    );

    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = stroke;
    canvas.drawPath(BadgeVectorGeometry.parseSvgPath('M117 117 H163'), base);
    canvas.drawPath(BadgeVectorGeometry.parseSvgPath('M124 128 H156'), base);

    final diamond = BadgeVectorGeometry.parseSvgPath(
      'M140 58 L145 66 L140 74 L135 66 Z',
    );
    canvas.drawPath(diamond, Paint()..color = metal.highlight);
    canvas.drawPath(
      diamond,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = stroke,
    );

    canvas.drawCircle(
      const Offset(140, 101),
      4,
      Paint()..color = BadgePrestigePalette.jewelFill,
    );
    canvas.drawCircle(
      const Offset(140, 101),
      4,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = stroke,
    );
  }

  static void _paintTrophy(
    Canvas canvas,
    Color stroke,
    BadgePrestigeColors metal,
  ) {
    final body = BadgeVectorGeometry.parseSvgPath(
      'M119 75 H161 V96 Q161 116 140 119 Q119 116 119 96 Z',
    );
    canvas.drawPath(
      body,
      BadgePrestigePalette.metallicFillPaint(body.getBounds(), metal),
    );
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = stroke,
    );

    final handles = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = stroke;
    canvas.drawPath(
      BadgeVectorGeometry.parseSvgPath('M119 81 H105 V91 Q105 105 122 105'),
      handles,
    );
    canvas.drawPath(
      BadgeVectorGeometry.parseSvgPath('M161 81 H175 V91 Q175 105 158 105'),
      handles,
    );

    canvas.drawPath(
      BadgeVectorGeometry.parseSvgPath('M140 119 V133'),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = stroke,
    );
    final base = BadgeVectorGeometry.parseSvgPath('M124 139 H156 L151 133 H129 Z');
    canvas.drawPath(
      base,
      BadgePrestigePalette.metallicFillPaint(base.getBounds(), metal),
    );
    canvas.drawPath(
      base,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = stroke,
    );

    final star = BadgeVectorGeometry.parseSvgPath(
      'M140 84 L143 91 L151 92 L145 97 L147 105 L140 101 '
      'L133 105 L135 97 L129 92 L137 91 Z',
    );
    canvas.drawPath(star, Paint()..color = BadgePrestigePalette.starFill);
    canvas.drawPath(
      star,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = stroke,
    );
  }

  static void _paintRisingStar(
    Canvas canvas,
    Color stroke,
    BadgePrestigeColors metal,
  ) {
    final star = BadgeVectorGeometry.parseSvgPath(
      'M140 64 L150 86 L175 89 L156 106 L162 131 L140 118 '
      'L118 131 L124 106 L105 89 L130 86 Z',
    );
    canvas.drawPath(
      star,
      BadgePrestigePalette.metallicFillPaint(star.getBounds(), metal),
    );
    canvas.drawPath(
      star,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = stroke,
    );

    final chevrons = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = stroke;
    canvas.drawPath(
      BadgeVectorGeometry.parseSvgPath('M112 143 L140 132 L168 143'),
      chevrons,
    );
    canvas.drawPath(
      BadgeVectorGeometry.parseSvgPath('M123 149 L140 142 L157 149'),
      chevrons,
    );

    final facets = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = BadgePrestigePalette.starFill.withValues(alpha: 0.35);
    for (final d in const [
      'M140 64 L140 102 L175 89',
      'M140 102 L162 131',
      'M140 102 L118 131',
      'M140 102 L105 89',
    ]) {
      canvas.drawPath(BadgeVectorGeometry.parseSvgPath(d), facets);
    }
  }

  static void _paintFlame(
    Canvas canvas,
    Color stroke,
    BadgePrestigeColors metal,
  ) {
    final outer = BadgeVectorGeometry.parseSvgPath(
      'M145 63 C149 85 172 94 171 112 C170 131 155 140 140 140 '
      'C117 140 106 126 110 109 C113 96 122 90 126 78 '
      'C127 94 134 96 137 87 C143 76 145 63 145 63 Z',
    );
    canvas.drawPath(
      outer,
      BadgePrestigePalette.metallicFillPaint(outer.getBounds(), metal),
    );
    canvas.drawPath(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = stroke,
    );

    final inner = BadgeVectorGeometry.parseSvgPath(
      'M142 102 C142 116 155 119 151 129 Q140 143 129 129 '
      'C125 119 138 114 142 102 Z',
    );
    canvas.drawPath(inner, Paint()..color = BadgePrestigePalette.starFill);
    canvas.drawPath(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = stroke,
    );
  }
}
