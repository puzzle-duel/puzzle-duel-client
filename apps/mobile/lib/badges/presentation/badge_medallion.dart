import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/badges/domain/badge_definition.dart';
import 'package:puzzle_duel_mobile/badges/domain/badge_prestige.dart';
import 'package:puzzle_duel_mobile/badges/presentation/badge_medallion_painter.dart';
import 'package:puzzle_duel_mobile/badges/presentation/badge_vector_geometry.dart';

/// Production badge medallion used by Profile, detail sheets, and Studio.
final class BadgeMedallion extends StatelessWidget {
  const BadgeMedallion({
    super.key,
    required this.badgeId,
    required this.prestige,
    required this.earnedCount,
    required this.prestigeLabel,
    required this.semanticLabel,
    this.width = 140,
    this.showCountCapsule = true,
    this.showPrestigeLabel = true,
    this.paintBackground = false,
  });

  final BadgeId badgeId;
  final BadgePrestige? prestige;
  final int earnedCount;
  final String prestigeLabel;
  final String semanticLabel;
  final double width;
  final bool showCountCapsule;
  final bool showPrestigeLabel;
  final bool paintBackground;

  double get height =>
      width *
      (BadgeVectorGeometry.viewBoxHeight / BadgeVectorGeometry.viewBoxWidth);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          painter: BadgeMedallionPainter(
            badgeId: badgeId,
            prestige: prestige,
            earnedCount: earnedCount,
            prestigeLabel: prestigeLabel,
            showCountCapsule: showCountCapsule && prestige != null,
            showPrestigeLabel: showPrestigeLabel && prestige != null,
            paintBackground: paintBackground,
          ),
        ),
      ),
    );
  }
}
