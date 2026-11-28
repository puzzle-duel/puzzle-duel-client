import 'package:puzzle_duel_mobile/badges/domain/badge_prestige.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_copy.dart';

/// Canonical badge identities. Wire values are stable persistence keys.
enum BadgeId {
  loyalty('loyalty'),
  onTime('on_time'),
  practiceMaster('practice_master'),
  tournamentGuru('tournament_guru'),
  champion('champion'),
  risingStar('rising_star'),
  unstoppable('unstoppable');

  const BadgeId(this.wire);
  final String wire;

  static BadgeId? tryParse(String? value) {
    for (final item in BadgeId.values) {
      if (item.wire == value) return item;
    }
    return null;
  }

  /// Guest-compatible awards may accumulate locally before verified sync.
  bool get guestEligible => switch (this) {
    BadgeId.loyalty ||
    BadgeId.practiceMaster ||
    BadgeId.unstoppable => true,
    BadgeId.onTime ||
    BadgeId.tournamentGuru ||
    BadgeId.champion ||
    BadgeId.risingStar => false,
  };

  bool get verifiedAccountRequired => !guestEligible;
}

/// Authoritative or local provenance for a badge progress row.
enum BadgeProvenance {
  f2bPublication('f2b_publication'),
  serverAward('server_award'),
  localGuest('local_guest'),
  unavailable('unavailable');

  const BadgeProvenance(this.wire);
  final String wire;

  static BadgeProvenance fromWire(String? value) {
    for (final item in BadgeProvenance.values) {
      if (item.wire == value) return item;
    }
    return BadgeProvenance.unavailable;
  }
}

/// Per-badge prestige threshold ladder (strictly increasing, six values).
final class BadgeThresholds {
  const BadgeThresholds({
    required this.bronze,
    required this.silver,
    required this.gold,
    required this.platinum,
    required this.diamond,
    required this.mythic,
  }) : assert(bronze > 0),
       assert(silver > bronze),
       assert(gold > silver),
       assert(platinum > gold),
       assert(diamond > platinum),
       assert(mythic > diamond);

  final int bronze;
  final int silver;
  final int gold;
  final int platinum;
  final int diamond;
  final int mythic;

  int forPrestige(BadgePrestige prestige) => switch (prestige) {
    BadgePrestige.bronze => bronze,
    BadgePrestige.silver => silver,
    BadgePrestige.gold => gold,
    BadgePrestige.platinum => platinum,
    BadgePrestige.diamond => diamond,
    BadgePrestige.mythic => mythic,
  };

  List<int> get ordered => [
    bronze,
    silver,
    gold,
    platinum,
    diamond,
    mythic,
  ];
}

final class BadgeDefinition {
  const BadgeDefinition({
    required this.id,
    required this.thresholds,
  });

  final BadgeId id;
  final BadgeThresholds thresholds;

  String name(TournamentCopy copy) => switch (id) {
    BadgeId.loyalty => copy.loyaltyBadgeName,
    BadgeId.onTime => copy.onTime,
    BadgeId.practiceMaster => copy.practiceMasterBadgeName,
    BadgeId.tournamentGuru => copy.tournamentGuruBadgeName,
    BadgeId.champion => copy.championBadgeName,
    BadgeId.risingStar => copy.risingStarBadgeName,
    BadgeId.unstoppable => copy.unstoppableBadgeName,
  };

  String description(TournamentCopy copy) => switch (id) {
    BadgeId.loyalty => copy.loyaltyBadgeDescription,
    BadgeId.onTime => copy.onTimeBadgeDescription,
    BadgeId.practiceMaster => copy.practiceMasterBadgeDescription,
    BadgeId.tournamentGuru => copy.tournamentGuruBadgeDescription,
    BadgeId.champion => copy.championBadgeDescription,
    BadgeId.risingStar => copy.risingStarBadgeDescription,
    BadgeId.unstoppable => copy.unstoppableBadgeDescription,
  };

  String unlockRequirement(TournamentCopy copy) => switch (id) {
    BadgeId.loyalty => copy.loyaltyBadgeUnlock,
    BadgeId.onTime => copy.onTimeBadgeRule,
    BadgeId.practiceMaster => copy.practiceMasterBadgeUnlock,
    BadgeId.tournamentGuru => copy.tournamentGuruBadgeUnlock,
    BadgeId.champion => copy.championBadgeUnlock,
    BadgeId.risingStar => copy.risingStarBadgeUnlock,
    BadgeId.unstoppable => copy.unstoppableBadgeUnlock,
  };
}

/// Fixed PZD-56 catalogue. Append only with owner-approved center artwork.
const Map<BadgeId, BadgeThresholds> kBadgeThresholds = {
  BadgeId.loyalty: BadgeThresholds(
    bronze: 1,
    silver: 10,
    gold: 50,
    platinum: 100,
    diamond: 250,
    mythic: 1000,
  ),
  BadgeId.onTime: BadgeThresholds(
    bronze: 1,
    silver: 10,
    gold: 50,
    platinum: 100,
    diamond: 250,
    mythic: 1000,
  ),
  BadgeId.practiceMaster: BadgeThresholds(
    bronze: 1,
    silver: 10,
    gold: 50,
    platinum: 100,
    diamond: 250,
    mythic: 1000,
  ),
  BadgeId.tournamentGuru: BadgeThresholds(
    bronze: 1,
    silver: 4,
    gold: 12,
    platinum: 26,
    diamond: 52,
    mythic: 104,
  ),
  BadgeId.champion: BadgeThresholds(
    bronze: 1,
    silver: 3,
    gold: 10,
    platinum: 25,
    diamond: 50,
    mythic: 100,
  ),
  BadgeId.risingStar: BadgeThresholds(
    bronze: 1,
    silver: 3,
    gold: 5,
    platinum: 10,
    diamond: 20,
    mythic: 50,
  ),
  BadgeId.unstoppable: BadgeThresholds(
    bronze: 1,
    silver: 4,
    gold: 12,
    platinum: 26,
    diamond: 52,
    mythic: 104,
  ),
};

final List<BadgeDefinition> kBadgeCatalog = [
  for (final id in BadgeId.values)
    BadgeDefinition(id: id, thresholds: kBadgeThresholds[id]!),
];
