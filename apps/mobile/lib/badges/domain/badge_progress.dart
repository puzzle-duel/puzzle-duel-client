import 'package:puzzle_duel_mobile/badges/domain/badge_definition.dart';
import 'package:puzzle_duel_mobile/badges/domain/badge_prestige.dart';
import 'package:puzzle_duel_mobile/badges/domain/badge_prestige_resolver.dart';

/// Authoritative (or explicit unavailable) earned state for one catalog badge.
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

  /// True when the count came from a successful authenticated server read,
  /// or a guest-eligible local ledger for guest-compatible badges.
  final bool verified;

  bool get earned => verified && earnedCount > 0;
  bool get locked => !earned;

  BadgePrestigeResolution resolvePrestige([
    BadgePrestigeResolver resolver = const BadgePrestigeResolver(),
  ]) {
    return resolver.resolve(
      thresholds: definition.thresholds,
      earnedCount: earned ? earnedCount : 0,
    );
  }

  BadgePrestige? get prestige => resolvePrestige().prestige;
}

final class BadgeCollectionSnapshot {
  const BadgeCollectionSnapshot({
    required this.badges,
    required this.status,
    this.errorCode,
    this.catalogVersion = 2,
  });

  final List<BadgeProgress> badges;
  final BadgeCollectionStatus status;
  final String? errorCode;
  final int catalogVersion;

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
    final version = map['catalogVersion'];
    return BadgeCollectionSnapshot(
      status: BadgeCollectionStatus.ready,
      catalogVersion: version is num ? version.toInt() : 2,
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
      provenance: BadgeProvenance.serverAward,
      verified: true,
    );
  }
  final count = row['earnedCount'];
  return BadgeProgress(
    definition: definition,
    earnedCount: count is num ? count.toInt() : 0,
    repeatable: row['repeatable'] != false,
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
