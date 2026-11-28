import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/badges/domain/badge_definition.dart';
import 'package:puzzle_duel_mobile/badges/domain/badge_prestige.dart';
import 'package:puzzle_duel_mobile/badges/domain/badge_progress.dart';
import 'package:puzzle_duel_mobile/badges/presentation/badge_medallion.dart';
import 'package:puzzle_duel_mobile/badges/presentation/badge_prestige_palette.dart';
import 'package:puzzle_duel_mobile/theme/game_tokens.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_copy.dart';

/// Detail sheet body for one badge: medallion, progress, prestige previews.
final class BadgeDetailContent extends StatelessWidget {
  const BadgeDetailContent({
    super.key,
    required this.badge,
    required this.copy,
  });

  final BadgeProgress badge;
  final TournamentCopy copy;

  String _upperPrestige(BadgePrestige prestige) {
    final name = copy.badgePrestigeName(prestige);
    if (copy.isTurkish) {
      return name.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();
    }
    return name.toUpperCase();
  }

  BadgeProvenanceLabel _provenanceLabel() {
    return switch (badge.provenance) {
      BadgeProvenance.f2bPublication => BadgeProvenanceLabel.f2bPublication,
      BadgeProvenance.serverAward => BadgeProvenanceLabel.serverAward,
      BadgeProvenance.localGuest => BadgeProvenanceLabel.localGuest,
      BadgeProvenance.unavailable => BadgeProvenanceLabel.unavailable,
    };
  }

  @override
  Widget build(BuildContext context) {
    final name = badge.definition.name(copy);
    final resolution = badge.resolvePrestige();
    final prestige = resolution.prestige;
    final prestigeLabel =
        prestige == null ? '' : _upperPrestige(prestige);
    final colors = prestige == null
        ? BadgePrestigeColors.locked
        : BadgePrestigeColors.forPrestige(prestige);

    return SingleChildScrollView(
      key: Key('badge-detail-${badge.definition.id.wire}'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: BadgeMedallion(
              badgeId: badge.definition.id,
              prestige: prestige,
              earnedCount: badge.earnedCount,
              prestigeLabel: prestigeLabel,
              semanticLabel: name,
              width: 220,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 20,
              color: GameTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            badge.earned
                ? badge.definition.description(copy)
                : badge.definition.unlockRequirement(copy),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: GameTokens.textSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            badge.earned
                ? copy.badgeEarnedCount(badge.earnedCount)
                : copy.badgeLocked,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: badge.earned ? GameTokens.accent : GameTokens.textMuted,
            ),
          ),
          if (badge.lastEarnedAt != null) ...[
            const SizedBox(height: 4),
            Text(
              copy.badgeLastEarned(badge.lastEarnedAt!),
              textAlign: TextAlign.center,
              style: const TextStyle(color: GameTokens.textSecondary),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            copy.badgeProvenanceLabel(_provenanceLabel()),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: GameTokens.textMuted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          if (badge.earned) ...[
            Text(
              resolution.isMaxPrestige
                  ? copy.badgeMaxPrestige
                  : copy.badgeNextPrestige,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: GameTokens.textPrimary,
              ),
            ),
            if (!resolution.isMaxPrestige &&
                resolution.nextThreshold != null) ...[
              const SizedBox(height: 4),
              Text(
                copy.badgeRemainingToNext(resolution.remainingToNext),
                style: const TextStyle(color: GameTokens.textSecondary),
              ),
            ],
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 7,
                child: LinearProgressIndicator(
                  value: resolution.visualProgress,
                  backgroundColor: BadgePrestigePalette.progressTrack,
                  color: colors.primary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final tier in BadgePrestige.values)
                  Opacity(
                    opacity: (prestige?.index ?? -1) >= tier.index ? 1 : 0.45,
                    child: BadgeMedallion(
                      key: Key(
                        'badge-prestige-preview-${badge.definition.id.wire}-${tier.wire}',
                      ),
                      badgeId: badge.definition.id,
                      prestige: tier,
                      earnedCount: badge.definition.thresholds.forPrestige(tier),
                      prestigeLabel: _upperPrestige(tier),
                      semanticLabel: copy.badgePrestigeName(tier),
                      width: 72,
                      showPrestigeLabel: false,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
