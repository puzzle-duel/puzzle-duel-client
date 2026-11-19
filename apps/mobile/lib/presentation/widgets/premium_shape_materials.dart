import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/premium/material_palette.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

/// Convenience material accessors aligned with the owner-approved premium
/// renderer ([ProtoMaterialPalette] / [PremiumPieceRenderer]).
///
/// Kept for board/tray call sites and goldens that still reference these
/// tokens. Body painting is owned by [PremiumPieceRenderer].
abstract final class PremiumShapeMaterials {
  static const String sourceAsset =
      'docs/features/pzd-47/prototype/reference/PZD-47-premium-shapes-reference.png';
  static const String sourceSha256 = ProtoMaterialPalette.referenceSha256;
  static const String version = ProtoMaterialPalette.version;

  /// Direction glyph fill — dark cavity from the premium reference.
  static const Color directionInset = Color(0xFF061018);

  /// Soft highlight rim that sells the engraved chevron.
  static const Color directionInsetRim = Color(0x33000000);

  static const Color contactShadow = Color(0x99000000);

  static Color highlight(Shape shape) => switch (shape) {
    Shape.circle => ProtoMaterialPalette.circleBevelHi,
    Shape.diamond => ProtoMaterialPalette.diamondBevelHi,
    Shape.triangle => ProtoMaterialPalette.triangleBevelHi,
  };

  static Color fill(Shape shape) => switch (shape) {
    Shape.circle => ProtoMaterialPalette.circleFace,
    Shape.diamond => ProtoMaterialPalette.diamondFace,
    Shape.triangle => ProtoMaterialPalette.triangleFace,
  };

  static Color mid(Shape shape) => switch (shape) {
    Shape.circle => ProtoMaterialPalette.circleFaceUr,
    Shape.diamond => ProtoMaterialPalette.diamondFaceUr,
    Shape.triangle => ProtoMaterialPalette.triangleFaceUr,
  };

  static Color deep(Shape shape) => switch (shape) {
    Shape.circle => ProtoMaterialPalette.circleExtrusion,
    Shape.diamond => ProtoMaterialPalette.diamondExtrusion,
    Shape.triangle => ProtoMaterialPalette.triangleExtrusion,
  };

  static Color bevel(Shape shape) => switch (shape) {
    Shape.circle => ProtoMaterialPalette.circleBevelHi,
    Shape.diamond => ProtoMaterialPalette.diamondBevelHi,
    Shape.triangle => ProtoMaterialPalette.triangleBevelHi,
  };
}
