import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/badges/domain/badge_progress.dart';
import 'package:puzzle_duel_mobile/badges/presentation/badge_medallion.dart';
import 'package:puzzle_duel_mobile/theme/game_tokens.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_copy.dart';

/// Profile grid tile: one evolving medallion + localized name.
final class BadgeCollectionItem extends StatelessWidget {
  const BadgeCollectionItem({
    super.key,
    required this.badge,
    required this.copy,
    required this.onTap,
  });

  final BadgeProgress badge;
  final TournamentCopy copy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = badge.definition.name(copy);
    final resolution = badge.resolvePrestige();
    final prestige = resolution.prestige;
    final earned = badge.earned;
    final prestigeLabel = prestige == null
        ? ''
        : copy.badgePrestigeName(prestige).toLocaleUpperCase(copy.locale);

    final semantic = earned
        ? '$name, ${copy.badgeEarnedCount(badge.earnedCount)}, $prestigeLabel'
        : '$name, ${copy.badgeLocked}';

    return Semantics(
      button: true,
      label: semantic,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('badge-tile-${badge.definition.id.wire}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(GameTokens.radiusMd),
          child: Ink(
            decoration: BoxDecoration(
              color: earned ? GameTokens.surfaceHigh : GameTokens.surface,
              borderRadius: BorderRadius.circular(GameTokens.radiusMd),
              border: Border.all(
                color: earned
                    ? GameTokens.success.withValues(alpha: 0.45)
                    : GameTokens.border,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(
                    child: BadgeMedallion(
                      badgeId: badge.definition.id,
                      prestige: prestige,
                      earnedCount: badge.earnedCount,
                      prestigeLabel: prestigeLabel,
                      semanticLabel: semantic,
                      width: 72,
                      showPrestigeLabel: false,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: earned
                          ? GameTokens.textPrimary
                          : GameTokens.textMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    earned
                        ? copy.badgeEarnedCount(badge.earnedCount)
                        : copy.badgeLocked,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: earned ? GameTokens.accent : GameTokens.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

extension on String {
  String toLocaleUpperCase(Locale locale) {
    // Turkish locale-aware uppercasing for İ/i and similar.
    if (locale.languageCode.toLowerCase() == 'tr') {
      return replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();
    }
    return toUpperCase();
  }
}
