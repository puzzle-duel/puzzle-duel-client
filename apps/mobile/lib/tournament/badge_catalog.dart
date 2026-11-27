import 'package:puzzle_duel_mobile/tournament/tournament_copy.dart';

/// Data-driven badge definitions. New authorized types append here without
/// rebuilding the profile layout. Earned state comes only from authoritative
/// server grants (or an explicit unavailable/offline state).
enum BadgeId {
  onTime('on_time');

  const BadgeId(this.wire);
  final String wire;

  static BadgeId? tryParse(String? value) {
    for (final item in BadgeId.values) {
      if (item.wire == value) return item;
    }
    return null;
  }
}

enum BadgeProvenance {
  f2bPublication('f2b_publication'),
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

final class BadgeDefinition {
  const BadgeDefinition({required this.id, required this.iconName});

  final BadgeId id;
  final String iconName;

  String name(TournamentCopy copy) => switch (id) {
    BadgeId.onTime => copy.onTime,
  };

  String description(TournamentCopy copy) => switch (id) {
    BadgeId.onTime => copy.onTimeBadgeDescription,
  };

  String rule(TournamentCopy copy) => switch (id) {
    BadgeId.onTime => copy.onTimeBadgeRule,
  };
}

/// Authoritative (or explicitly unavailable) earned state for one catalog badge.
final class BadgeProgress {
  const BadgeProgress({
    required this.definition,
    required this.earnedCount,
    required this.repeatable,
    required this.provenance,
    this.lastEarnedAt,
    this.verified = false,
  });

  final BadgeDefinition definition;
  final int earnedCount;
  final bool repeatable;
  final BadgeProvenance provenance;
  final String? lastEarnedAt;

  /// True only when the count came from a successful authenticated server read.
  final bool verified;

  bool get earned => verified && earnedCount > 0;
  bool get locked => !earned;
}

/// Fixed v1 catalog. Do not invent earned categories to fill the grid.
const List<BadgeDefinition> kBadgeCatalog = [
  BadgeDefinition(id: BadgeId.onTime, iconName: 'schedule'),
];

final class BadgeCollectionSnapshot {
  const BadgeCollectionSnapshot({
    required this.badges,
    required this.status,
    this.errorCode,
  });

  final List<BadgeProgress> badges;
  final BadgeCollectionStatus status;
  final String? errorCode;

  static BadgeCollectionSnapshot lockedCatalog({
    required BadgeCollectionStatus status,
    String? errorCode,
  }) {
    return BadgeCollectionSnapshot(
      status: status,
      errorCode: errorCode,
      badges: [
        for (final definition in kBadgeCatalog)
          BadgeProgress(
            definition: definition,
            earnedCount: 0,
            repeatable: true,
            provenance: BadgeProvenance.unavailable,
            verified: false,
          ),
      ],
    );
  }

  static BadgeCollectionSnapshot fromServerPayload(Map<String, Object?> map) {
    final rawBadges = map['badges'];
    final byId = <String, Map<String, Object?>>{};
    if (rawBadges is List) {
      for (final item in rawBadges) {
        if (item is Map) {
          final mapped = item.map(
            (key, value) => MapEntry(key.toString(), value),
          );
          final id = mapped['badgeId']?.toString();
          if (id != null) byId[id] = mapped;
        }
      }
    }
    return BadgeCollectionSnapshot(
      status: BadgeCollectionStatus.ready,
      badges: [
        for (final definition in kBadgeCatalog)
          _progressFromServer(definition, byId[definition.id.wire]),
      ],
    );
  }
}

BadgeProgress _progressFromServer(
  BadgeDefinition definition,
  Map<String, Object?>? row,
) {
  if (row == null) {
    return BadgeProgress(
      definition: definition,
      earnedCount: 0,
      repeatable: true,
      provenance: BadgeProvenance.f2bPublication,
      verified: true,
    );
  }
  final count = row['earnedCount'];
  return BadgeProgress(
    definition: definition,
    earnedCount: count is num ? count.toInt() : 0,
    repeatable: row['repeatable'] == true,
    provenance: BadgeProvenance.fromWire(row['provenance']?.toString()),
    lastEarnedAt: row['lastEarnedAt']?.toString(),
    verified: true,
  );
}

enum BadgeCollectionStatus {
  loading,
  ready,
  /// Last successful account-scoped snapshot retained during a transient failure.
  stale,
  offline,
  unauthorized,
  serverError,
}
