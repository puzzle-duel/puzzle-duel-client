import 'package:puzzle_duel_mobile/badges/domain/badge_definition.dart';
import 'package:puzzle_duel_mobile/badges/domain/badge_milestones.dart';
import 'package:puzzle_duel_mobile/badges/domain/badge_prestige.dart';

/// Pure prestige math — no Flutter / animation / localization.
final class BadgePrestigeResolution {
  const BadgePrestigeResolution({
    required this.earnedCount,
    required this.prestige,
    required this.nextPrestige,
    required this.currentThreshold,
    required this.nextThreshold,
    required this.remainingToNext,
    required this.visualProgress,
    required this.isLocked,
    required this.isMaxPrestige,
  });

  final int earnedCount;
  final BadgePrestige? prestige;
  final BadgePrestige? nextPrestige;
  final int? currentThreshold;
  final int? nextThreshold;
  final int remainingToNext;
  final double visualProgress;
  final bool isLocked;
  final bool isMaxPrestige;
}

final class BadgePrestigeResolver {
  const BadgePrestigeResolver();

  BadgePrestigeResolution resolve({
    required BadgeThresholds thresholds,
    required int earnedCount,
  }) {
    final count = earnedCount < 0 ? 0 : earnedCount;
    if (count <= 0) {
      return const BadgePrestigeResolution(
        earnedCount: 0,
        prestige: null,
        nextPrestige: BadgePrestige.bronze,
        currentThreshold: null,
        nextThreshold: 1,
        remainingToNext: 1,
        visualProgress: 0,
        isLocked: true,
        isMaxPrestige: false,
      );
    }

    BadgePrestige? current;
    for (final prestige in BadgePrestige.values) {
      if (count >= thresholds.forPrestige(prestige)) {
        current = prestige;
      }
    }

    if (current == null) {
      // Defensive: thresholds.bronze is always >= 1 and count > 0.
      return BadgePrestigeResolution(
        earnedCount: count,
        prestige: null,
        nextPrestige: BadgePrestige.bronze,
        currentThreshold: null,
        nextThreshold: thresholds.bronze,
        remainingToNext: thresholds.bronze - count,
        visualProgress: (count / thresholds.bronze).clamp(0.0, 1.0),
        isLocked: true,
        isMaxPrestige: false,
      );
    }

    if (current == BadgePrestige.mythic) {
      return BadgePrestigeResolution(
        earnedCount: count,
        prestige: current,
        nextPrestige: null,
        currentThreshold: thresholds.mythic,
        nextThreshold: null,
        remainingToNext: 0,
        visualProgress: 1,
        isLocked: false,
        isMaxPrestige: true,
      );
    }

    final nextIndex = current.index + 1;
    final next = BadgePrestige.values[nextIndex];
    final nextThreshold = thresholds.forPrestige(next);
    final currentThreshold = thresholds.forPrestige(current);
    final span = nextThreshold - currentThreshold;
    final into = count - currentThreshold;
    final progress = span <= 0 ? 1.0 : (into / span).clamp(0.0, 1.0);

    return BadgePrestigeResolution(
      earnedCount: count,
      prestige: current,
      nextPrestige: next,
      currentThreshold: currentThreshold,
      nextThreshold: nextThreshold,
      remainingToNext: (nextThreshold - count).clamp(0, nextThreshold),
      visualProgress: progress,
      isLocked: false,
      isMaxPrestige: false,
    );
  }

  /// Practice Master occurrences from distinct completed practice games.
  static int practiceMasterOccurrences(int completedPracticeGames) =>
      BadgeMilestones.practiceMasterOccurrences(completedPracticeGames);

  /// Lifetime Unstoppable awards from non-overlapping 7-day windows.
  static int unstoppableOccurrencesFromActiveDates(
    Iterable<String> distinctActiveUtcDates,
  ) =>
      BadgeMilestones.nonOverlappingSevenDayWindows(
        distinctActiveUtcDates,
      ).length;
}
