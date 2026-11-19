import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

/// Sampled material tokens from
/// `PZD-47-premium-shapes-reference.png`
/// SHA-256 `e1ad23104bdff8302434bdbcfbcec81d7ccbd70f9bfa02387ed8d94a70992cb6`.
///
/// Production PZD-47 premium material tokens (owner-approved prototype).
abstract final class ProtoMaterialPalette {
  static const String referenceSha256 =
      'e1ad23104bdff8302434bdbcfbcec81d7ccbd70f9bfa02387ed8d94a70992cb6';
  static const String version = 'pzd47-premium-material-v1';

  static const Color bgPlate = Color(0xFF120D31);

  // —— Circle ——
  static const Color circleFaceUl = Color(0xFF92F9C6);
  static const Color circleFace = Color(0xFF27C99A);
  static const Color circleFaceUr = Color(0xFF17AC7D);
  static const Color circleFaceLl = Color(0xFF018966);
  static const Color circleFaceLr = Color(0xFF09AAAB);
  static const Color circleBevelHi = Color(0xFFC8FFE8);
  static const Color circleBevelLo = Color(0xFF0A6B5C);
  static const Color circleExtrusion = Color(0xFF064A3C);
  static const Color circleShade = Color(0xFF03352C);
  static const Color circleChevron = Color(0xFF002B18);
  static const Color circleBounce = Color(0x6627C99A);

  // —— Diamond ——
  static const Color diamondFaceUl = Color(0xFFEC91FA);
  static const Color diamondFace = Color(0xFFB533E9);
  static const Color diamondFaceUr = Color(0xFF9A20D9);
  static const Color diamondFaceLl = Color(0xFF710BBC);
  static const Color diamondFaceLr = Color(0xFFA81FE2);
  static const Color diamondBevelHi = Color(0xFFF3C8FF);
  static const Color diamondBevelLo = Color(0xFF3A0568);
  static const Color diamondExtrusion = Color(0xFF1A083E);
  static const Color diamondShade = Color(0xFF12052E);
  static const Color diamondChevron = Color(0xFF1C0045);
  static const Color diamondBounce = Color(0x66B533E9);

  // —— Triangle ——
  static const Color triangleFaceUl = Color(0xFFFFF0A8);
  static const Color triangleFace = Color(0xFFFFC22A);
  static const Color triangleFaceUr = Color(0xFFE08A00);
  static const Color triangleFaceLl = Color(0xFFFFB400);
  static const Color triangleFaceLr = Color(0xFFFF8A00);
  static const Color triangleBevelHi = Color(0xFFFFF3C0);
  static const Color triangleBevelLo = Color(0xFF8A3E08);
  static const Color triangleExtrusion = Color(0xFF6A2E06);
  static const Color triangleShade = Color(0xFF4A1E04);
  /// Dark cavity (parity with circle/diamond depth; avoid muddy mid-brown).
  static const Color triangleChevron = Color(0xFF140A02);
  static const Color triangleBounce = Color(0x66E8B020);

  static const Color rimLip = Color(0x88FFFFFF);

  static Color faceUl(Shape s) => switch (s) {
    Shape.circle => circleFaceUl,
    Shape.diamond => diamondFaceUl,
    Shape.triangle => triangleFaceUl,
  };

  static Color face(Shape s) => switch (s) {
    Shape.circle => circleFace,
    Shape.diamond => diamondFace,
    Shape.triangle => triangleFace,
  };

  static Color faceUr(Shape s) => switch (s) {
    Shape.circle => circleFaceUr,
    Shape.diamond => diamondFaceUr,
    Shape.triangle => triangleFaceUr,
  };

  static Color faceLl(Shape s) => switch (s) {
    Shape.circle => circleFaceLl,
    Shape.diamond => diamondFaceLl,
    Shape.triangle => triangleFaceLl,
  };

  static Color faceLr(Shape s) => switch (s) {
    Shape.circle => circleFaceLr,
    Shape.diamond => diamondFaceLr,
    Shape.triangle => triangleFaceLr,
  };

  static Color bevelHi(Shape s) => switch (s) {
    Shape.circle => circleBevelHi,
    Shape.diamond => diamondBevelHi,
    Shape.triangle => triangleBevelHi,
  };

  static Color bevelLo(Shape s) => switch (s) {
    Shape.circle => circleBevelLo,
    Shape.diamond => diamondBevelLo,
    Shape.triangle => triangleBevelLo,
  };

  static Color extrusion(Shape s) => switch (s) {
    Shape.circle => circleExtrusion,
    Shape.diamond => diamondExtrusion,
    Shape.triangle => triangleExtrusion,
  };

  static Color shade(Shape s) => switch (s) {
    Shape.circle => circleShade,
    Shape.diamond => diamondShade,
    Shape.triangle => triangleShade,
  };

  static Color chevron(Shape s) => switch (s) {
    Shape.circle => circleChevron,
    Shape.diamond => diamondChevron,
    Shape.triangle => triangleChevron,
  };

  static Color bounce(Shape s) => switch (s) {
    Shape.circle => circleBounce,
    Shape.diamond => diamondBounce,
    Shape.triangle => triangleBounce,
  };
}
