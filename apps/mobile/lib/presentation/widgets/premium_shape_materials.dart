import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

/// Canonical PZD-47 material tokens reconstructed from
/// `Neon_Puzzle_Trophy_Icon.png` (Jira attachment 10000).
///
/// Body gradients, bevel rim, specular highlight, contact shadow and the dark
/// inset direction glyph share this definition for board, tray and icon
/// composition. Trophy remains icon-only artwork and is not a playable piece.
abstract final class PremiumShapeMaterials {
  static const String sourceAsset =
      'docs/features/pzd-47/reference/Neon_Puzzle_Trophy_Icon.png';
  static const String sourceSha256 =
      '32d53c61874e1c7a6e19c51bcf96cfb0f70d4ddbbe753df6695ace1fc8f5e48b';
  static const String version = 'pzd47-canonical-shapes-v1';

  /// Direction glyph fill — dark navy/black inset cutout from the icon.
  static const Color directionInset = Color(0xFF061018);

  /// Soft highlight rim that sells the engraved chevron.
  static const Color directionInsetRim = Color(0x33000000);

  static const Color circleHighlight = Color(0xFFF5FFFE);
  static const Color circleFill = Color(0xFF47F5D4);
  static const Color circleMid = Color(0xFF12D9A8);
  static const Color circleDeep = Color(0xFF0A8F78);
  static const Color circleBevel = Color(0xFF9AFFF0);

  static const Color diamondHighlight = Color(0xFFF3E9FF);
  static const Color diamondFill = Color(0xFFB06BFF);
  static const Color diamondMid = Color(0xFF7A3DFA);
  static const Color diamondDeep = Color(0xFF3B128A);
  static const Color diamondBevel = Color(0xFFD2A6FF);

  static const Color triangleHighlight = Color(0xFFFFF8D0);
  static const Color triangleFill = Color(0xFFFFD84A);
  static const Color triangleMid = Color(0xFFFFB000);
  static const Color triangleDeep = Color(0xFFD06500);
  static const Color triangleBevel = Color(0xFFFFF0A0);

  static const Color contactShadow = Color(0x99000000);

  static Color highlight(Shape shape) => switch (shape) {
    Shape.circle => circleHighlight,
    Shape.diamond => diamondHighlight,
    Shape.triangle => triangleHighlight,
  };

  static Color fill(Shape shape) => switch (shape) {
    Shape.circle => circleFill,
    Shape.diamond => diamondFill,
    Shape.triangle => triangleFill,
  };

  static Color mid(Shape shape) => switch (shape) {
    Shape.circle => circleMid,
    Shape.diamond => diamondMid,
    Shape.triangle => triangleMid,
  };

  static Color deep(Shape shape) => switch (shape) {
    Shape.circle => circleDeep,
    Shape.diamond => diamondDeep,
    Shape.triangle => triangleDeep,
  };

  static Color bevel(Shape shape) => switch (shape) {
    Shape.circle => circleBevel,
    Shape.diamond => diamondBevel,
    Shape.triangle => triangleBevel,
  };
}
