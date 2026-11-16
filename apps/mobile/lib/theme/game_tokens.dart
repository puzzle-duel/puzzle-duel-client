import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

/// Premium arcade puzzle design tokens (PZD-23 visual overhaul).
abstract final class GameTokens {
  static const Color bgDeep = Color(0xFF070B14);
  static const Color bgMid = Color(0xFF0E1628);
  static const Color surface = Color(0xFF152038);
  static const Color surfaceHigh = Color(0xFF1C2B48);
  static const Color border = Color(0xFF2E4060);
  static const Color borderBright = Color(0xFF4A6FA5);
  static const Color textPrimary = Color(0xFFF2F6FF);
  static const Color textSecondary = Color(0xFFA8B6D4);
  static const Color textMuted = Color(0xFF6E7F9E);
  static const Color accent = Color(0xFF5CE1E6);
  static const Color danger = Color(0xFFFF6B7A);
  static const Color success = Color(0xFF5CFFB0);
  static const Color scoreGlow = Color(0xFFFFD166);

  static const Color cellEmpty = Color(0xFF18253D);
  static const Color cellBlocked = Color(0xFF0A101C);
  static const Color cellFlash = Color(0xFFFFF1A8);
  static const Color gridLine = Color(0xFF334866);

  static const Color circleFill = Color(0xFF2EE6A8);
  static const Color circleDeep = Color(0xFF0F8F6A);
  static const Color diamondFill = Color(0xFF8B7CFF);
  static const Color diamondDeep = Color(0xFF4A3DB8);
  static const Color triangleFill = Color(0xFFFFB347);
  static const Color triangleDeep = Color(0xFFC26A12);

  static const Color easyCard = Color(0xFF163A3A);
  static const Color easyAccent = Color(0xFF2EE6A8);
  static const Color mediumCard = Color(0xFF2A2450);
  static const Color mediumAccent = Color(0xFF8B7CFF);
  static const Color hardCard = Color(0xFF3A2614);
  static const Color hardAccent = Color(0xFFFFB347);

  static const double radiusSm = 10;
  static const double radiusMd = 16;
  static const double radiusLg = 22;
  static const double spaceXs = 6;
  static const double spaceSm = 10;
  static const double spaceMd = 16;
  static const double spaceLg = 24;

  static Color pieceFill(Shape shape) => switch (shape) {
    Shape.circle => circleFill,
    Shape.diamond => diamondFill,
    Shape.triangle => triangleFill,
  };

  static Color pieceDeep(Shape shape) => switch (shape) {
    Shape.circle => circleDeep,
    Shape.diamond => diamondDeep,
    Shape.triangle => triangleDeep,
  };

  static Color difficultyAccent(DifficultyProfile profile) => switch (profile) {
    DifficultyProfile.easy => easyAccent,
    DifficultyProfile.medium => mediumAccent,
    DifficultyProfile.hard => hardAccent,
  };

  static Color difficultyCard(DifficultyProfile profile) => switch (profile) {
    DifficultyProfile.easy => easyCard,
    DifficultyProfile.medium => mediumCard,
    DifficultyProfile.hard => hardCard,
  };
}
