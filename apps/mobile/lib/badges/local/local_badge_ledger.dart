import 'dart:convert';

import 'package:puzzle_duel_mobile/badges/domain/badge_definition.dart';
import 'package:puzzle_duel_mobile/badges/domain/badge_prestige_resolver.dart';
import 'package:puzzle_duel_mobile/tournament/local_kv_store.dart';
import 'package:puzzle_duel_mobile/tournament/practice_identity.dart';

/// Guest-compatible durable award evidence for loyalty / practice_master / unstoppable.
/// Never grants tournament-only badges. Deduplicates by evidence key.
final class LocalBadgeLedger {
  LocalBadgeLedger({
    required this.store,
    required this.identity,
  });

  final LocalKvStore store;
  final PracticeIdentityStore identity;

  static const _filePrefix = 'badge-ledger';

  String get _fileName => '$_filePrefix-${identity.activeScope.storageKey}.json';

  Future<Map<String, Object?>> _read() async {
    final raw = await store.read(_fileName);
    if (raw == null || raw.isEmpty) {
      return {
        'version': 1,
        'evidence': <String, Object?>{},
        'activeUtcDates': <String>[],
        'practiceCompletionIds': <String>[],
      };
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) return Map<String, Object?>.from(decoded);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {
      // Rebuild empty ledger rather than crash.
    }
    return {
      'version': 1,
      'evidence': <String, Object?>{},
      'activeUtcDates': <String>[],
      'practiceCompletionIds': <String>[],
    };
  }

  Future<void> _write(Map<String, Object?> data) async {
    await store.writeAtomic(_fileName, jsonEncode(data));
  }

  Future<_LedgerSnapshot> _snapshot() async {
    await identity.load();
    final data = await _read();
    final evidence = <String, String>{};
    final evidenceRaw = data['evidence'];
    if (evidenceRaw is Map) {
      for (final entry in evidenceRaw.entries) {
        evidence[entry.key.toString()] = entry.value.toString();
      }
    }
    final dates = <String>{};
    final datesRaw = data['activeUtcDates'];
    if (datesRaw is List) {
      for (final d in datesRaw) {
        dates.add(d.toString());
      }
    }
    final completions = <String>{};
    final completionsRaw = data['practiceCompletionIds'];
    if (completionsRaw is List) {
      for (final id in completionsRaw) {
        completions.add(id.toString());
      }
    }
    return _LedgerSnapshot(
      evidence: evidence,
      activeUtcDates: dates,
      practiceCompletionIds: completions,
    );
  }

  Future<void> _persist(_LedgerSnapshot snap) async {
    await _write({
      'version': 1,
      'evidence': snap.evidence,
      'activeUtcDates': snap.activeUtcDates.toList()..sort(),
      'practiceCompletionIds': snap.practiceCompletionIds.toList(),
    });
  }

  Future<Map<BadgeId, int>> earnedCounts() async {
    final snap = await _snapshot();
    final counts = <BadgeId, int>{
      for (final id in BadgeId.values) id: 0,
    };
    for (final entry in snap.evidence.entries) {
      final badgeId = BadgeId.tryParse(entry.value);
      if (badgeId == null || !badgeId.guestEligible) continue;
      counts[badgeId] = (counts[badgeId] ?? 0) + 1;
    }
    return counts;
  }

  /// Record an eligible completed game day + optional practice completion.
  Future<void> recordEligibleCompletion({
    required String utcDate,
    String? practiceCompletionId,
  }) async {
    final snap = await _snapshot();
    snap.activeUtcDates.add(utcDate);
    final loyaltyKey = 'loyalty:utc:$utcDate';
    snap.evidence.putIfAbsent(loyaltyKey, () => BadgeId.loyalty.wire);

    if (practiceCompletionId != null &&
        snap.practiceCompletionIds.add(practiceCompletionId)) {
      final occurrences = BadgePrestigeResolver.practiceMasterOccurrences(
        snap.practiceCompletionIds.length,
      );
      for (var i = 1; i <= occurrences; i++) {
        final key = 'practice_master:occurrence:$i';
        snap.evidence.putIfAbsent(key, () => BadgeId.practiceMaster.wire);
      }
    }

    final streak = streakEndingAt(snap.activeUtcDates, utcDate);
    final unstoppable =
        BadgePrestigeResolver.unstoppableOccurrencesFromStreakDays(streak);
    for (var i = 1; i <= unstoppable; i++) {
      final key = 'unstoppable:occurrence:$i';
      snap.evidence.putIfAbsent(key, () => BadgeId.unstoppable.wire);
    }

    await _persist(snap);
  }

  /// Export evidence keys for verified-account sync (dedupe on server).
  Future<List<Map<String, String>>> exportGuestEvidence() async {
    final snap = await _snapshot();
    return [
      for (final entry in snap.evidence.entries)
        if (BadgeId.tryParse(entry.value)?.guestEligible == true)
          {
            'badgeId': entry.value,
            'evidenceKey': entry.key,
          },
    ];
  }

  static int streakEndingAt(Set<String> dates, String end) {
    var streak = 0;
    var cursor = end;
    while (dates.contains(cursor)) {
      streak += 1;
      cursor = shiftUtcDate(cursor, -1);
    }
    return streak;
  }

  static String shiftUtcDate(String utcDate, int delta) {
    final parsed = DateTime.parse('${utcDate}T00:00:00.000Z');
    final next = parsed.add(Duration(days: delta));
    return next.toIso8601String().substring(0, 10);
  }
}

final class _LedgerSnapshot {
  _LedgerSnapshot({
    required this.evidence,
    required this.activeUtcDates,
    required this.practiceCompletionIds,
  });

  final Map<String, String> evidence;
  final Set<String> activeUtcDates;
  final Set<String> practiceCompletionIds;
}
