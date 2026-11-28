import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/badges/domain/badge_definition.dart';
import 'package:puzzle_duel_mobile/badges/domain/badge_prestige.dart';
import 'package:puzzle_duel_mobile/badges/domain/badge_prestige_resolver.dart';

void main() {
  const resolver = BadgePrestigeResolver();
  final thresholds = kBadgeThresholds[BadgeId.onTime]!;

  group('BadgePrestigeResolver thresholds', () {
    test('zero is locked without Bronze', () {
      final r = resolver.resolve(thresholds: thresholds, earnedCount: 0);
      expect(r.isLocked, isTrue);
      expect(r.prestige, isNull);
      expect(r.visualProgress, 0);
    });

    test('boundaries for on_time ladder', () {
      expect(
        resolver.resolve(thresholds: thresholds, earnedCount: 1).prestige,
        BadgePrestige.bronze,
      );
      expect(
        resolver.resolve(thresholds: thresholds, earnedCount: 9).prestige,
        BadgePrestige.bronze,
      );
      expect(
        resolver.resolve(thresholds: thresholds, earnedCount: 10).prestige,
        BadgePrestige.silver,
      );
      expect(
        resolver.resolve(thresholds: thresholds, earnedCount: 50).prestige,
        BadgePrestige.gold,
      );
      expect(
        resolver.resolve(thresholds: thresholds, earnedCount: 100).prestige,
        BadgePrestige.platinum,
      );
      expect(
        resolver.resolve(thresholds: thresholds, earnedCount: 250).prestige,
        BadgePrestige.diamond,
      );
      final mythic = resolver.resolve(
        thresholds: thresholds,
        earnedCount: 1000,
      );
      expect(mythic.prestige, BadgePrestige.mythic);
      expect(mythic.isMaxPrestige, isTrue);
      expect(mythic.visualProgress, 1);

      final beyond = resolver.resolve(
        thresholds: thresholds,
        earnedCount: 1500,
      );
      expect(beyond.prestige, BadgePrestige.mythic);
      expect(beyond.earnedCount, 1500);
    });

    test('tournament_guru uses distinct ladder', () {
      final t = kBadgeThresholds[BadgeId.tournamentGuru]!;
      expect(
        resolver.resolve(thresholds: t, earnedCount: 4).prestige,
        BadgePrestige.silver,
      );
      expect(
        resolver.resolve(thresholds: t, earnedCount: 12).prestige,
        BadgePrestige.gold,
      );
    });
  });

  group('occurrence helpers', () {
    test('practice master every 10 games', () {
      expect(BadgePrestigeResolver.practiceMasterOccurrences(9), 0);
      expect(BadgePrestigeResolver.practiceMasterOccurrences(10), 1);
      expect(BadgePrestigeResolver.practiceMasterOccurrences(19), 1);
      expect(BadgePrestigeResolver.practiceMasterOccurrences(20), 2);
    });

    test('unstoppable from lifetime windows', () {
      expect(
        BadgePrestigeResolver.unstoppableOccurrencesFromActiveDates([
          for (var i = 1; i <= 6; i++) '2026-11-0$i',
        ]),
        0,
      );
      expect(
        BadgePrestigeResolver.unstoppableOccurrencesFromActiveDates([
          for (var i = 1; i <= 7; i++) '2026-11-0$i',
        ]),
        1,
      );
      expect(
        BadgePrestigeResolver.unstoppableOccurrencesFromActiveDates([
          for (var i = 1; i <= 7; i++) '2026-11-${i.toString().padLeft(2, '0')}',
          for (var i = 9; i <= 15; i++) '2026-11-${i.toString().padLeft(2, '0')}',
        ]),
        2,
      );
    });
  });
}
