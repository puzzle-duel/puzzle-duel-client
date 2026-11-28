import 'package:flutter/painting.dart';
import 'package:puzzle_duel_mobile/badges/domain/badge_prestige.dart';

/// Exact approved prestige metal colors (PZD-56 design golden rule).
final class BadgePrestigeColors {
  const BadgePrestigeColors({
    required this.primary,
    required this.highlight,
  });

  final Color primary;
  final Color highlight;

  static const bronze = BadgePrestigeColors(
    primary: Color(0xFFB77B4C),
    highlight: Color(0xFFF0BD83),
  );
  static const silver = BadgePrestigeColors(
    primary: Color(0xFF8D9FB6),
    highlight: Color(0xFFE3EDF9),
  );
  static const gold = BadgePrestigeColors(
    primary: Color(0xFFC99832),
    highlight: Color(0xFFFFE7A1),
  );
  static const platinum = BadgePrestigeColors(
    primary: Color(0xFF70AECB),
    highlight: Color(0xFFE0FBFF),
  );
  static const diamond = BadgePrestigeColors(
    primary: Color(0xFF9866E1),
    highlight: Color(0xFFE8D0FF),
  );
  static const mythic = BadgePrestigeColors(
    primary: Color(0xFFED9B51),
    highlight: Color(0xFFFFF2B0),
  );

  static BadgePrestigeColors forPrestige(BadgePrestige prestige) =>
      switch (prestige) {
        BadgePrestige.bronze => bronze,
        BadgePrestige.silver => silver,
        BadgePrestige.gold => gold,
        BadgePrestige.platinum => platinum,
        BadgePrestige.diamond => diamond,
        BadgePrestige.mythic => mythic,
      };

  /// Locked / muted silhouette palette (not an earned Bronze frame).
  static const locked = BadgePrestigeColors(
    primary: Color(0xFF4A5568),
    highlight: Color(0xFF718096),
  );
}

final class BadgePrestigePalette {
  const BadgePrestigePalette._();

  static const Color canvasBackground = Color(0xFF111929);
  static const Color medallionCenter = Color(0xFF344358);
  static const Color medallionEdge = Color(0xFF131C30);
  static const Color capsuleFill = Color(0xFF121B2B);
  static const Color progressTrack = Color(0xFF344054);
  static const Color mythicOrbit = Color(0xFFE3A6FF);
  static const Color jewelFill = Color(0xFF17243B);
  static const Color starFill = Color(0xFF26334A);
  static const Color piecePurple = Color(0xFF9975DF);
  static const Color pieceGreen = Color(0xFF57B795);
  static const Color pieceYellow = Color(0xFFEFC85B);
  static const Color pieceBlue = Color(0xFF6A92CC);

  static Paint metallicFillPaint(Rect bounds, BadgePrestigeColors colors) {
    return Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          colors.highlight,
          colors.primary,
          colors.highlight,
          colors.primary,
        ],
        stops: const [0.0, 0.45, 0.70, 1.0],
      ).createShader(bounds);
  }

  static Paint metallicStrokePaint(
    Rect bounds,
    BadgePrestigeColors colors, {
    required double strokeWidth,
  }) {
    return Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          colors.highlight,
          colors.primary,
          colors.highlight,
          colors.primary,
        ],
        stops: const [0.0, 0.45, 0.70, 1.0],
      ).createShader(bounds);
  }
}
