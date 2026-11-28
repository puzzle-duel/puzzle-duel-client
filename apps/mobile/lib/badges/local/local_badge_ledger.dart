import 'dart:async';
import 'dart:convert';

import 'package:puzzle_duel_mobile/badges/domain/badge_definition.dart';
import 'package:puzzle_duel_mobile/badges/domain/badge_milestones.dart';
import 'package:puzzle_duel_mobile/diagnostics/diagnostic_runtime.dart';
import 'package:puzzle_duel_mobile/diagnostics/puzzle_duel_logger.dart';
import 'package:puzzle_duel_mobile/tournament/local_kv_store.dart';
import 'package:puzzle_duel_mobile/tournament/practice_identity.dart';

/// Authorization for one guest→verified badge adoption.
///
/// Must be produced only after successful guest-to-verified linking that
/// preserves the expected guest identity — never from a bare verified token.
final class BadgeGuestAdoptionAuthorization {
  const BadgeGuestAdoptionAuthorization({
    required this.sourceGuestLocalId,
    required this.targetPlayerId,
  });

  final String sourceGuestLocalId;
  final String targetPlayerId;
}

/// Durable practice completion evidence for guest-compatible badges.
///
/// Single-file journal (v3): completions + ack set + evidence + adoption
/// stamp written atomically so crash between steps cannot orphan sync work.
final class LocalBadgeLedger {
  LocalBadgeLedger({
    required this.store,
    required this.identity,
  });

  final LocalKvStore store;
  final PracticeIdentityStore identity;

  static const _filePrefix = 'badge-ledger';
  static const _legacyPendingPrefix = 'badge-pending-sync';

  int _generation = 0;
  final Map<String, Future<void>> _scopeLocks = {};

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

  String _legacyPendingFile(PracticeIdentityScope scope) =>
      '$_legacyPendingPrefix-${scope.storageKey}.json';

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

  Future<Map<String, Object?>> _readRaw(String name) async {
    final raw = await store.read(name);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) return Map<String, Object?>.from(decoded);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {}
    return {};
  }

  Future<_LedgerSnapshot> _loadSnapshot(PracticeIdentityScope scope) async {
    final data = await _readRaw(_ledgerFile(scope));
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
    final synced = <String>{};
    final syncedRaw = data['syncedCompletionIds'];
    if (syncedRaw is List) {
      for (final id in syncedRaw) {
        synced.add(id.toString());
      }
    }
    // Recover orphaned legacy pending file into synced/pending model once.
    if (data['version'] is! num || (data['version'] as num).toInt() < 3) {
      final legacy = await _readRaw(_legacyPendingFile(scope));
      final legacyList = legacy['completions'];
      if (legacyList is List) {
        for (final item in legacyList) {
          final parsed = _PracticeCompletionEvidence.tryParse(item);
          if (parsed != null && seenIds.add(parsed.completionId)) {
            completions.add(parsed);
          }
        }
      }
    }
    BadgeGuestAdoptionRecord? adoption;
    final adoptionRaw = data['guestAdoption'];
    if (adoptionRaw is Map) {
      adoption = BadgeGuestAdoptionRecord.tryParse(adoptionRaw);
    }
    final exportedTo = data['exportedToPlayerId']?.toString();
    return _LedgerSnapshot(
      evidence: evidence,
      activeUtcDates: dates,
      practiceCompletions: completions,
      syncedCompletionIds: synced,
      guestAdoption: adoption,
      exportedToPlayerId: exportedTo,
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
        'version': 3,
        'evidence': snap.evidence,
        'activeUtcDates': snap.activeUtcDates.toList()..sort(),
        'practiceCompletions': [
          for (final c in snap.practiceCompletions) c.toJson(),
        ],
        'syncedCompletionIds': snap.syncedCompletionIds.toList()..sort(),
        if (snap.guestAdoption != null)
          'guestAdoption': snap.guestAdoption!.toJson(),
        if (snap.exportedToPlayerId != null)
          'exportedToPlayerId': snap.exportedToPlayerId,
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
      return _countsFromEvidence(snap.evidence);
    });
  }

  Map<BadgeId, int> _countsFromEvidence(Map<String, String> evidence) {
    final counts = <BadgeId, int>{
      for (final id in BadgeId.values) id: 0,
    };
    var unstoppableOcc = 0;
    var unstoppableWindow = 0;
    for (final entry in evidence.entries) {
      final badgeId = BadgeId.tryParse(entry.value);
      if (badgeId == null || !badgeId.guestEligible) continue;
      if (badgeId == BadgeId.unstoppable) {
        if (BadgeMilestones.isUnstoppableOccurrenceKey(entry.key)) {
          unstoppableOcc += 1;
        } else if (BadgeMilestones.isLegacyUnstoppableWindowKey(entry.key)) {
          unstoppableWindow += 1;
        }
        continue;
      }
      counts[badgeId] = (counts[badgeId] ?? 0) + 1;
    }
    counts[BadgeId.unstoppable] =
        unstoppableOcc > 0 ? unstoppableOcc : unstoppableWindow;
    return counts;
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
      final existingIndex = snap.practiceCompletions.indexWhere(
        (c) => c.completionId == completionId,
      );
      if (existingIndex >= 0) {
        final prior = snap.practiceCompletions[existingIndex];
        if (prior.completedAtMs != completedAtMs || prior.utcDate != utcDate) {
          // Conflicting replay — keep first durable payload.
          return;
        }
      } else {
        snap.practiceCompletions.add(evidence);
      }
      snap.activeUtcDates.add(utcDate);
      // New completion is pending until acknowledged (not in synced set).
      _rebuildDerivedEvidence(snap);
      await _persist(scope, generation, snap);
    });
  }

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
    for (final day in snap.activeUtcDates) {
      snap.evidence.putIfAbsent(
        BadgeMilestones.loyaltyEvidenceKey(day),
        () => BadgeId.loyalty.wire,
      );
    }
    final occurrences = BadgeMilestones.practiceMasterOccurrences(
      snap.practiceCompletions.length,
    );
    for (var i = 1; i <= occurrences; i++) {
      snap.evidence.putIfAbsent(
        BadgeMilestones.practiceMasterEvidenceKey(i),
        () => BadgeId.practiceMaster.wire,
      );
    }
    final total = BadgeMilestones.totalCompleteSevenDayWindows(
      snap.activeUtcDates,
    );
    for (var i = 1; i <= total; i++) {
      snap.evidence.putIfAbsent(
        BadgeMilestones.unstoppableOccurrenceEvidenceKey(i),
        () => BadgeId.unstoppable.wire,
      );
    }
  }

  Future<List<Map<String, Object?>>> peekPendingCompletions({
    int limit = BadgeMilestones.practiceBadgeSyncMaxCompletions,
  }) async {
    final generation = _generation;
    final scope = identity.activeScope;
    return _withScopeLock(scope, () async {
      if (!_stillActive(scope, generation)) return const [];
      final snap = await _loadSnapshot(scope);
      if (!_stillActive(scope, generation)) return const [];
      final out = <Map<String, Object?>>[];
      for (final c in snap.practiceCompletions) {
        if (snap.syncedCompletionIds.contains(c.completionId)) continue;
        out.add(c.toJson());
        if (out.length >= limit) break;
      }
      return out;
    });
  }

  Future<int> pendingCount() async {
    final generation = _generation;
    final scope = identity.activeScope;
    return _withScopeLock(scope, () async {
      if (!_stillActive(scope, generation)) return 0;
      final snap = await _loadSnapshot(scope);
      return snap.practiceCompletions
          .where((c) => !snap.syncedCompletionIds.contains(c.completionId))
          .length;
    });
  }

  Future<void> acknowledgeSyncedCompletions(Set<String> completionIds) async {
    if (completionIds.isEmpty) return;
    final generation = _generation;
    final scope = identity.activeScope;
    await _withScopeLock(scope, () async {
      if (!_stillActive(scope, generation)) return;
      final snap = await _loadSnapshot(scope);
      if (!_stillActive(scope, generation)) return;
      snap.syncedCompletionIds.addAll(completionIds);
      await _persist(scope, generation, snap);
    });
  }

  /// Authorized guest→verified adoption. Idempotent per (guest, player) pair.
  Future<bool> adoptGuestProgressIntoActivePlayer(
    BadgeGuestAdoptionAuthorization authorization,
  ) async {
    final generation = _generation;
    final scope = identity.activeScope;
    if (scope.kind != PracticeIdentityKind.player) return false;
    if (scope.id != authorization.targetPlayerId.trim().toLowerCase()) {
      return false;
    }
    final guestId = authorization.sourceGuestLocalId.trim().toLowerCase();
    if (guestId.isEmpty || guestId != identity.guestLocalId) return false;
    final guestScope = PracticeIdentityScope.guest(guestId);

    return _withScopeLock(scope, () async {
      if (!_stillActive(scope, generation)) return false;
      final playerSnap = await _loadSnapshot(scope);
      if (!_stillActive(scope, generation)) return false;

      final prior = playerSnap.guestAdoption;
      if (prior != null &&
          prior.sourceGuestLocalId == guestId &&
          prior.targetPlayerId == scope.id) {
        // Already adopted this guest into this player — do not re-import.
        return true;
      }
      if (prior != null && prior.targetPlayerId == scope.id) {
        // Different guest already adopted into this player scope.
        return false;
      }

      final guestSnap = await _loadSnapshot(guestScope);
      if (guestSnap.exportedToPlayerId != null &&
          guestSnap.exportedToPlayerId != scope.id) {
        // Guest already exported to another verified account.
        return false;
      }
      if (guestSnap.exportedToPlayerId == scope.id) {
        playerSnap.guestAdoption = BadgeGuestAdoptionRecord(
          sourceGuestLocalId: guestId,
          targetPlayerId: scope.id,
          completedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
        );
        await _persist(scope, generation, playerSnap);
        return true;
      }

      final seen = {
        for (final c in playerSnap.practiceCompletions) c.completionId,
      };
      for (final c in guestSnap.practiceCompletions) {
        if (seen.add(c.completionId)) {
          playerSnap.practiceCompletions.add(c);
        }
        // Keep unsynced guest completions pending on the player until ack.
        if (!guestSnap.syncedCompletionIds.contains(c.completionId)) {
          playerSnap.syncedCompletionIds.remove(c.completionId);
        } else {
          playerSnap.syncedCompletionIds.add(c.completionId);
        }
      }
      playerSnap.activeUtcDates.addAll(guestSnap.activeUtcDates);
      for (final entry in guestSnap.evidence.entries) {
        if (BadgeMilestones.isLegacyUnstoppableWindowKey(entry.key)) {
          continue; // rebuild occurrence keys below
        }
        playerSnap.evidence.putIfAbsent(entry.key, () => entry.value);
      }
      _rebuildDerivedEvidence(playerSnap);
      playerSnap.guestAdoption = BadgeGuestAdoptionRecord(
        sourceGuestLocalId: guestId,
        targetPlayerId: scope.id,
        completedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      );
      await _persist(scope, generation, playerSnap);
      if (!_stillActive(scope, generation)) return false;

      // Mark guest exported without deleting progress.
      guestSnap.exportedToPlayerId = scope.id;
      await store.writeAtomic(
        _ledgerFile(guestScope),
        jsonEncode({
          'version': 3,
          'evidence': guestSnap.evidence,
          'activeUtcDates': guestSnap.activeUtcDates.toList()..sort(),
          'practiceCompletions': [
            for (final c in guestSnap.practiceCompletions) c.toJson(),
          ],
          'syncedCompletionIds': guestSnap.syncedCompletionIds.toList()..sort(),
          'exportedToPlayerId': scope.id,
        }),
      );
      unawaited(
        DiagnosticRuntime.logger.log(
          LogEvent(
            level: LogLevel.info,
            code: LogCode.screenOpened,
            operation: 'badge_guest_adoption_completed',
          ),
        ),
      );
      return true;
    });
  }
}

final class BadgeGuestAdoptionRecord {
  const BadgeGuestAdoptionRecord({
    required this.sourceGuestLocalId,
    required this.targetPlayerId,
    required this.completedAtMs,
  });

  final String sourceGuestLocalId;
  final String targetPlayerId;
  final int completedAtMs;

  Map<String, Object?> toJson() => {
    'sourceGuestLocalId': sourceGuestLocalId,
    'targetPlayerId': targetPlayerId,
    'completedAtMs': completedAtMs,
  };

  static BadgeGuestAdoptionRecord? tryParse(Map raw) {
    final guest = raw['sourceGuestLocalId']?.toString() ?? '';
    final player = raw['targetPlayerId']?.toString() ?? '';
    final ms = raw['completedAtMs'];
    if (guest.isEmpty || player.isEmpty || ms is! num) return null;
    return BadgeGuestAdoptionRecord(
      sourceGuestLocalId: guest,
      targetPlayerId: player,
      completedAtMs: ms.toInt(),
    );
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
    required this.syncedCompletionIds,
    this.guestAdoption,
    this.exportedToPlayerId,
  });

  final Map<String, String> evidence;
  final Set<String> activeUtcDates;
  final List<_PracticeCompletionEvidence> practiceCompletions;
  final Set<String> syncedCompletionIds;
  BadgeGuestAdoptionRecord? guestAdoption;
  String? exportedToPlayerId;
}
