import 'dart:async';
import 'dart:convert';

import 'package:puzzle_duel_mobile/badges/domain/badge_definition.dart';
import 'package:puzzle_duel_mobile/badges/domain/badge_milestones.dart';
import 'package:puzzle_duel_mobile/diagnostics/diagnostic_runtime.dart';
import 'package:puzzle_duel_mobile/diagnostics/puzzle_duel_logger.dart';
import 'package:puzzle_duel_mobile/tournament/local_kv_store.dart';
import 'package:puzzle_duel_mobile/tournament/practice_identity.dart';

/// Durable practice completion evidence for guest-compatible badges.
///
/// Account isolation: every async op captures immutable [PracticeIdentityScope]
/// + generation at start and refuses to write if scope/generation changed.
final class LocalBadgeLedger {
  LocalBadgeLedger({
    required this.store,
    required this.identity,
  });

  final LocalKvStore store;
  final PracticeIdentityStore identity;

  static const _filePrefix = 'badge-ledger';
  static const _pendingPrefix = 'badge-pending-sync';

  int _generation = 0;
  final Map<String, Future<void>> _scopeLocks = {};

  /// Bump on logout / account switch — in-flight ops must abort.
  void fence() {
    _generation++;
    unawaited(
      DiagnosticRuntime.logger.log(
        LogEvent(
          level: LogLevel.info,
          code: LogCode.screenOpened,
          operation: 'badge_ledger_fenced',
        ),
      ),
    );
  }

  int get generation => _generation;

  String _ledgerFile(PracticeIdentityScope scope) =>
      '$_filePrefix-${scope.storageKey}.json';

  String _pendingFile(PracticeIdentityScope scope) =>
      '$_pendingPrefix-${scope.storageKey}.json';

  bool _stillActive(PracticeIdentityScope scope, int generation) {
    return generation == _generation && identity.activeScope == scope;
  }

  Future<T> _withScopeLock<T>(
    PracticeIdentityScope scope,
    Future<T> Function() body,
  ) async {
    final key = scope.storageKey;
    final previous = _scopeLocks[key] ?? Future<void>.value();
    final gate = Completer<void>();
    _scopeLocks[key] = gate.future;
    await previous;
    try {
      return await body();
    } finally {
      gate.complete();
      if (identical(_scopeLocks[key], gate.future)) {
        _scopeLocks.remove(key);
      }
    }
  }

  Future<Map<String, Object?>> _readFile(String name) async {
    final raw = await store.read(name);
    if (raw == null || raw.isEmpty) {
      return {
        'version': 2,
        'evidence': <String, Object?>{},
        'activeUtcDates': <String>[],
        'practiceCompletions': <Object>[],
      };
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) return Map<String, Object?>.from(decoded);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {}
    return {
      'version': 2,
      'evidence': <String, Object?>{},
      'activeUtcDates': <String>[],
      'practiceCompletions': <Object>[],
    };
  }

  Future<_LedgerSnapshot> _loadSnapshot(PracticeIdentityScope scope) async {
    final data = await _readFile(_ledgerFile(scope));
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
    final completions = <_PracticeCompletionEvidence>[];
    final seenIds = <String>{};
    final completionsRaw = data['practiceCompletions'];
    if (completionsRaw is List) {
      for (final raw in completionsRaw) {
        final parsed = _PracticeCompletionEvidence.tryParse(raw);
        if (parsed != null && seenIds.add(parsed.completionId)) {
          completions.add(parsed);
        }
      }
    }
    // Migrate v1 practiceCompletionIds → empty structured list (ids only lost
    // milestone identity is rebuilt from surviving evidence keys).
    return _LedgerSnapshot(
      evidence: evidence,
      activeUtcDates: dates,
      practiceCompletions: completions,
    );
  }

  Future<void> _persist(
    PracticeIdentityScope scope,
    int generation,
    _LedgerSnapshot snap,
  ) async {
    if (!_stillActive(scope, generation)) {
      unawaited(
        DiagnosticRuntime.logger.log(
          LogEvent(
            level: LogLevel.info,
            code: LogCode.screenOpened,
            operation: 'badge_ledger_stale_write_rejected',
          ),
        ),
      );
      return;
    }
    await store.writeAtomic(
      _ledgerFile(scope),
      jsonEncode({
        'version': 2,
        'evidence': snap.evidence,
        'activeUtcDates': snap.activeUtcDates.toList()..sort(),
        'practiceCompletions': [
          for (final c in snap.practiceCompletions) c.toJson(),
        ],
      }),
    );
  }

  Future<Map<BadgeId, int>> earnedCounts() async {
    final generation = _generation;
    final scope = identity.activeScope;
    return _withScopeLock(scope, () async {
      if (!_stillActive(scope, generation)) {
        return {for (final id in BadgeId.values) id: 0};
      }
      final snap = await _loadSnapshot(scope);
      if (!_stillActive(scope, generation)) {
        return {for (final id in BadgeId.values) id: 0};
      }
      final counts = <BadgeId, int>{
        for (final id in BadgeId.values) id: 0,
      };
      for (final entry in snap.evidence.entries) {
        final badgeId = BadgeId.tryParse(entry.value);
        if (badgeId == null || !badgeId.guestEligible) continue;
        counts[badgeId] = (counts[badgeId] ?? 0) + 1;
      }
      return counts;
    });
  }

  /// Record an eligible Practice completion using the actual UTC completion day.
  Future<void> recordPracticeCompletion({
    required String completionId,
    required int completedAtMs,
    required String difficulty,
    required String rulesVersion,
    required String generatorVersion,
  }) async {
    final generation = _generation;
    final scope = identity.activeScope;
    final utcDate = BadgeMilestones.utcDayFromEpochMs(completedAtMs);

    await _withScopeLock(scope, () async {
      if (!_stillActive(scope, generation)) return;
      final snap = await _loadSnapshot(scope);
      if (!_stillActive(scope, generation)) return;

      final evidence = _PracticeCompletionEvidence(
        completionId: completionId,
        completedAtMs: completedAtMs,
        utcDate: utcDate,
        difficulty: difficulty,
        rulesVersion: rulesVersion,
        generatorVersion: generatorVersion,
      );
      final existed = snap.practiceCompletions.any(
        (c) => c.completionId == completionId,
      );
      if (!existed) {
        snap.practiceCompletions.add(evidence);
      }
      snap.activeUtcDates.add(utcDate);
      _rebuildDerivedEvidence(snap);
      await _persist(scope, generation, snap);
      if (!_stillActive(scope, generation)) return;
      await _enqueuePending(scope, generation, evidence);
    });
  }

  /// Tournament activity day = UTC day of actual completion (not manifest date).
  Future<void> recordTournamentActivityDay({
    required String activityUtcDate,
  }) async {
    final generation = _generation;
    final scope = identity.activeScope;
    final day = BadgeMilestones.assertUtcDate(activityUtcDate);
    await _withScopeLock(scope, () async {
      if (!_stillActive(scope, generation)) return;
      final snap = await _loadSnapshot(scope);
      if (!_stillActive(scope, generation)) return;
      snap.activeUtcDates.add(day);
      _rebuildDerivedEvidence(snap);
      await _persist(scope, generation, snap);
    });
  }

  void _rebuildDerivedEvidence(_LedgerSnapshot snap) {
    // Loyalty
    for (final day in snap.activeUtcDates) {
      snap.evidence.putIfAbsent(
        BadgeMilestones.loyaltyEvidenceKey(day),
        () => BadgeId.loyalty.wire,
      );
    }
    // Practice Master
    final occurrences = BadgeMilestones.practiceMasterOccurrences(
      snap.practiceCompletions.length,
    );
    for (var i = 1; i <= occurrences; i++) {
      snap.evidence.putIfAbsent(
        BadgeMilestones.practiceMasterEvidenceKey(i),
        () => BadgeId.practiceMaster.wire,
      );
    }
    // Unstoppable — lifetime non-overlapping windows (never revoke).
    for (final window
        in BadgeMilestones.nonOverlappingSevenDayWindows(snap.activeUtcDates)) {
      snap.evidence.putIfAbsent(
        window.evidenceKey,
        () => BadgeId.unstoppable.wire,
      );
    }
  }

  Future<void> _enqueuePending(
    PracticeIdentityScope scope,
    int generation,
    _PracticeCompletionEvidence evidence,
  ) async {
    if (!_stillActive(scope, generation)) return;
    final data = await _readFile(_pendingFile(scope));
    final list = <Map<String, Object?>>[];
    final raw = data['completions'];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          list.add(item.map((k, v) => MapEntry(k.toString(), v)));
        }
      }
    }
    if (list.any((e) => e['completionId'] == evidence.completionId)) {
      return;
    }
    list.add(evidence.toJson());
    if (!_stillActive(scope, generation)) return;
    await store.writeAtomic(
      _pendingFile(scope),
      jsonEncode({'version': 1, 'completions': list}),
    );
  }

  /// Pending completions for verified sync (bounded batches, never discard silently).
  Future<List<Map<String, Object?>>> peekPendingCompletions({
    int limit = BadgeMilestones.practiceBadgeSyncMaxCompletions,
  }) async {
    final generation = _generation;
    final scope = identity.activeScope;
    return _withScopeLock(scope, () async {
      if (!_stillActive(scope, generation)) return const [];
      final data = await _readFile(_pendingFile(scope));
      if (!_stillActive(scope, generation)) return const [];
      final out = <Map<String, Object?>>[];
      final raw = data['completions'];
      if (raw is List) {
        for (final item in raw) {
          if (out.length >= limit) break;
          if (item is Map) {
            out.add(item.map((k, v) => MapEntry(k.toString(), v)));
          }
        }
      }
      return out;
    });
  }

  Future<int> pendingCount() async {
    final generation = _generation;
    final scope = identity.activeScope;
    return _withScopeLock(scope, () async {
      if (!_stillActive(scope, generation)) return 0;
      final data = await _readFile(_pendingFile(scope));
      final raw = data['completions'];
      return raw is List ? raw.length : 0;
    });
  }

  Future<void> acknowledgeSyncedCompletions(
    Set<String> completionIds,
  ) async {
    if (completionIds.isEmpty) return;
    final generation = _generation;
    final scope = identity.activeScope;
    await _withScopeLock(scope, () async {
      if (!_stillActive(scope, generation)) return;
      final data = await _readFile(_pendingFile(scope));
      if (!_stillActive(scope, generation)) return;
      final remaining = <Map<String, Object?>>[];
      final raw = data['completions'];
      if (raw is List) {
        for (final item in raw) {
          if (item is! Map) continue;
          final map = item.map((k, v) => MapEntry(k.toString(), v));
          final id = map['completionId']?.toString();
          if (id == null || !completionIds.contains(id)) {
            remaining.add(map);
          }
        }
      }
      if (!_stillActive(scope, generation)) return;
      await store.writeAtomic(
        _pendingFile(scope),
        jsonEncode({'version': 1, 'completions': remaining}),
      );
    });
  }

  /// After guest→verified link, adopt guest-scope completion evidence into the
  /// active player scope so pending sync and local counts survive. Guest files
  /// remain untouched (idempotent union). Call before [BadgeSyncRepository].
  Future<void> adoptGuestProgressIntoActivePlayer() async {
    final generation = _generation;
    final scope = identity.activeScope;
    if (scope.kind != PracticeIdentityKind.player) return;
    final guestScope = PracticeIdentityScope.guest(identity.guestLocalId);

    await _withScopeLock(scope, () async {
      if (!_stillActive(scope, generation)) return;
      final guestSnap = await _loadSnapshot(guestScope);
      final playerSnap = await _loadSnapshot(scope);
      if (!_stillActive(scope, generation)) return;

      final seen = {
        for (final c in playerSnap.practiceCompletions) c.completionId,
      };
      for (final c in guestSnap.practiceCompletions) {
        if (seen.add(c.completionId)) {
          playerSnap.practiceCompletions.add(c);
        }
      }
      playerSnap.activeUtcDates.addAll(guestSnap.activeUtcDates);
      // Preserve already-earned evidence keys (never revoke).
      for (final entry in guestSnap.evidence.entries) {
        playerSnap.evidence.putIfAbsent(entry.key, () => entry.value);
      }
      _rebuildDerivedEvidence(playerSnap);
      await _persist(scope, generation, playerSnap);
      if (!_stillActive(scope, generation)) return;

      // Merge pending sync queues.
      final guestPending = await _readFile(_pendingFile(guestScope));
      final playerPending = await _readFile(_pendingFile(scope));
      if (!_stillActive(scope, generation)) return;
      final merged = <Map<String, Object?>>[];
      final pendingSeen = <String>{};
      for (final source in [playerPending['completions'], guestPending['completions']]) {
        if (source is! List) continue;
        for (final item in source) {
          if (item is! Map) continue;
          final map = item.map((k, v) => MapEntry(k.toString(), v));
          final id = map['completionId']?.toString() ?? '';
          if (id.isEmpty || !pendingSeen.add(id)) continue;
          merged.add(map);
        }
      }
      await store.writeAtomic(
        _pendingFile(scope),
        jsonEncode({'version': 1, 'completions': merged}),
      );
    });
  }
}

final class _PracticeCompletionEvidence {
  const _PracticeCompletionEvidence({
    required this.completionId,
    required this.completedAtMs,
    required this.utcDate,
    required this.difficulty,
    required this.rulesVersion,
    required this.generatorVersion,
  });

  final String completionId;
  final int completedAtMs;
  final String utcDate;
  final String difficulty;
  final String rulesVersion;
  final String generatorVersion;

  Map<String, Object?> toJson() => {
    'completionId': completionId,
    'completedAtMs': completedAtMs,
    'utcDate': utcDate,
    'difficulty': difficulty,
    'rulesVersion': rulesVersion,
    'generatorVersion': generatorVersion,
  };

  static _PracticeCompletionEvidence? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final completionId = raw['completionId']?.toString() ?? '';
    final completedAtMs = raw['completedAtMs'];
    final utcDate = raw['utcDate']?.toString() ?? '';
    final difficulty = raw['difficulty']?.toString() ?? '';
    final rulesVersion = raw['rulesVersion']?.toString() ?? '';
    final generatorVersion = raw['generatorVersion']?.toString() ?? '';
    if (completionId.isEmpty ||
        completedAtMs is! num ||
        utcDate.isEmpty ||
        difficulty.isEmpty ||
        rulesVersion.isEmpty ||
        generatorVersion.isEmpty) {
      return null;
    }
    return _PracticeCompletionEvidence(
      completionId: completionId,
      completedAtMs: completedAtMs.toInt(),
      utcDate: utcDate,
      difficulty: difficulty,
      rulesVersion: rulesVersion,
      generatorVersion: generatorVersion,
    );
  }
}

final class _LedgerSnapshot {
  _LedgerSnapshot({
    required this.evidence,
    required this.activeUtcDates,
    required this.practiceCompletions,
  });

  final Map<String, String> evidence;
  final Set<String> activeUtcDates;
  final List<_PracticeCompletionEvidence> practiceCompletions;
}
