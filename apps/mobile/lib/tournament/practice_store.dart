import 'dart:convert';
import 'dart:io';

import 'package:puzzle_duel_mobile/tournament/local_kv_store.dart';
import 'package:puzzle_duel_mobile/tournament/practice_identity.dart';

/// One finished practice puzzle. This is not a ranked or server-verified result.
final class PracticeRecord {
  const PracticeRecord({
    required this.sessionId,
    required this.difficulty,
    required this.rulesVersion,
    required this.generatorVersion,
    required this.seed,
    required this.score,
    required this.terminalReason,
    required this.completedAt,
    this.moveCount,
    this.source = PracticeSource.localPractice,
  });

  final String sessionId;
  final String difficulty;
  final String rulesVersion;
  final String generatorVersion;
  final int seed;
  final int score;
  final String terminalReason;
  final String completedAt;
  final int? moveCount;
  final PracticeSource source;

  String get versionKey => '$difficulty|$rulesVersion|$generatorVersion';

  Map<String, Object?> toJson() => {
    'sessionId': sessionId,
    'difficulty': difficulty,
    'rulesVersion': rulesVersion,
    'generatorVersion': generatorVersion,
    'seed': seed,
    'score': score,
    'terminalReason': terminalReason,
    'completedAt': completedAt,
    'moveCount': ?moveCount,
    'source': source.wire,
    'verifiedRank': false,
  };

  static PracticeRecord? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final sessionId = raw['sessionId']?.toString() ?? '';
    if (sessionId.isEmpty) return null;
    return PracticeRecord(
      sessionId: sessionId,
      difficulty: raw['difficulty']?.toString() ?? '',
      rulesVersion: raw['rulesVersion']?.toString() ?? '',
      generatorVersion: raw['generatorVersion']?.toString() ?? '',
      seed: raw['seed'] is num ? (raw['seed'] as num).toInt() : 0,
      score: raw['score'] is num ? (raw['score'] as num).toInt() : 0,
      terminalReason: raw['terminalReason']?.toString() ?? '',
      completedAt: raw['completedAt']?.toString() ?? '',
      moveCount: raw['moveCount'] is num
          ? (raw['moveCount'] as num).toInt()
          : null,
      source: PracticeSource.fromWire(raw['source']?.toString()),
    );
  }
}

enum PracticeSource {
  localPractice('local_practice');

  const PracticeSource(this.wire);
  final String wire;

  static PracticeSource fromWire(String? value) {
    for (final item in PracticeSource.values) {
      if (item.wire == value) return item;
    }
    return PracticeSource.localPractice;
  }
}

/// Version-aware personal best for one difficulty/ruleset/generator key.
final class PracticeBest {
  const PracticeBest({
    required this.difficulty,
    required this.rulesVersion,
    required this.generatorVersion,
    required this.score,
    required this.completedAt,
    required this.sessionId,
    this.moveCount,
    this.source = PracticeSource.localPractice,
  });

  final String difficulty;
  final String rulesVersion;
  final String generatorVersion;
  final int score;
  final String completedAt;
  final String sessionId;
  final int? moveCount;
  final PracticeSource source;

  String get versionKey => '$difficulty|$rulesVersion|$generatorVersion';

  Map<String, Object?> toJson() => {
    'difficulty': difficulty,
    'rulesVersion': rulesVersion,
    'generatorVersion': generatorVersion,
    'score': score,
    'completedAt': completedAt,
    'sessionId': sessionId,
    'moveCount': ?moveCount,
    'source': source.wire,
    'verifiedRank': false,
  };

  static PracticeBest fromRecord(PracticeRecord record) => PracticeBest(
    difficulty: record.difficulty,
    rulesVersion: record.rulesVersion,
    generatorVersion: record.generatorVersion,
    score: record.score,
    completedAt: record.completedAt,
    sessionId: record.sessionId,
    moveCount: record.moveCount,
    source: record.source,
  );

  static PracticeBest? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final difficulty = raw['difficulty']?.toString() ?? '';
    final rulesVersion = raw['rulesVersion']?.toString() ?? '';
    final generatorVersion = raw['generatorVersion']?.toString() ?? '';
    if (difficulty.isEmpty || rulesVersion.isEmpty) return null;
    return PracticeBest(
      difficulty: difficulty,
      rulesVersion: rulesVersion,
      generatorVersion: generatorVersion,
      score: raw['score'] is num ? (raw['score'] as num).toInt() : 0,
      completedAt: raw['completedAt']?.toString() ?? '',
      sessionId: raw['sessionId']?.toString() ?? '',
      moveCount: raw['moveCount'] is num
          ? (raw['moveCount'] as num).toInt()
          : null,
      source: PracticeSource.fromWire(raw['source']?.toString()),
    );
  }
}

final class PracticeStats {
  const PracticeStats({
    required this.completedCount,
    required this.difficultyCounts,
  });

  final int completedCount;
  final Map<String, int> difficultyCounts;
}

/// Bounded on-device practice history keyed by [PracticeIdentityScope].
///
/// Never uses display names. Never sends scores to ranked APIs. Guest records
/// are never auto-merged into authenticated player scopes.
///
/// Disk access goes through [LocalKvStore]. Production [DirectoryKvStore] runs
/// filesystem work in a worker isolate. Tests inject [MemoryKvStore].
final class PracticeStore {
  PracticeStore({
    required this.scope,
    LocalKvStore? store,
    Directory? directory,
    this._identity,
  }) : assert(store != null || directory != null),
       _kv = store ?? DirectoryKvStore(directory!);

  /// History retention. Personal bests survive pruning via [_bestsName].
  static const int maxRecords = 40;
  static const int schemaVersion = 2;

  final PracticeIdentityScope scope;
  final LocalKvStore _kv;
  final PracticeIdentityStore? _identity;

  String get _recordsName => 'practice-records-${scope.storageKey}.json';
  String get _bestsName => 'practice-bests-${scope.storageKey}.json';
  String get _seedName => 'practice-seed-${scope.storageKey}.txt';

  Future<int> nextSeed() async {
    await _migrateLegacyIntoGuestIfNeeded();
    final raw = await _kv.read(_seedName);
    var current = int.tryParse((raw ?? '').trim()) ?? 1;
    if (current < 1 || current > 4294967294) current = 1;
    final issued = current;
    await _kv.writeAtomic(_seedName, '${issued + 1}');
    return issued;
  }

  Future<int?> bestScore(
    String difficulty, {
    required String rulesVersion,
    required String generatorVersion,
  }) async {
    return (await personalBest(
      difficulty,
      rulesVersion: rulesVersion,
      generatorVersion: generatorVersion,
    ))?.score;
  }

  Future<PracticeBest?> personalBest(
    String difficulty, {
    required String rulesVersion,
    required String generatorVersion,
  }) async {
    final key = '$difficulty|$rulesVersion|$generatorVersion';
    return (await loadBests())[key];
  }

  Future<PracticeBest?> personalBestForDifficulty(
    String difficulty, {
    required String rulesVersion,
    String? preferredGeneratorVersion,
  }) async {
    final matches = (await loadBests()).values.where(
      (best) =>
          best.difficulty == difficulty && best.rulesVersion == rulesVersion,
    );
    if (matches.isEmpty) return null;
    if (preferredGeneratorVersion != null) {
      for (final best in matches) {
        if (best.generatorVersion == preferredGeneratorVersion) return best;
      }
      return null;
    }
    return null;
  }

  /// True when local practice has completions or any stored personal best.
  static Future<bool> hasMeaningfulLocalProgress(PracticeStore store) async {
    final stats = await store.stats();
    if (stats.completedCount > 0) return true;
    final bests = await store.loadBests();
    return bests.isNotEmpty;
  }

  Future<PracticeStats> stats() async {
    final records = await load();
    final counts = <String, int>{};
    for (final record in records) {
      counts[record.difficulty] = (counts[record.difficulty] ?? 0) + 1;
    }
    final bests = await loadBests();
    var completed = records.length;
    for (final best in bests.values) {
      final inHistory = records.any(
        (record) => record.sessionId == best.sessionId,
      );
      if (!inHistory) {
        completed += 1;
        counts[best.difficulty] = (counts[best.difficulty] ?? 0) + 1;
      } else {
        counts.putIfAbsent(best.difficulty, () => 0);
      }
    }
    return PracticeStats(completedCount: completed, difficultyCounts: counts);
  }

  /// Appends a completed practice result. Duplicate [sessionId] is ignored.
  Future<bool> append(PracticeRecord record) async {
    if (record.sessionId.isEmpty) return false;
    if (record.source != PracticeSource.localPractice) return false;
    await _migrateLegacyIntoGuestIfNeeded();
    final all = await _loadRecords();
    if (all.any((item) => item.sessionId == record.sessionId)) {
      return false;
    }
    all.add(record);
    final kept = all.length > maxRecords
        ? all.sublist(all.length - maxRecords)
        : all;
    await _writeRecords(kept);
    await _updateBest(record);
    return true;
  }

  Future<List<PracticeRecord>> load() async {
    await _migrateLegacyIntoGuestIfNeeded();
    return _loadRecords();
  }

  Future<Map<String, PracticeBest>> loadBests() async {
    await _migrateLegacyIntoGuestIfNeeded();
    return _loadBests();
  }

  Future<List<PracticeRecord>> _loadRecords() async {
    final rawText = await _kv.read(_recordsName);
    if (rawText == null) return [];
    try {
      final raw = jsonDecode(rawText);
      if (raw is! List) return [];
      return [for (final item in raw) ?PracticeRecord.tryParse(item)];
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, PracticeBest>> _loadBests() async {
    final rawText = await _kv.read(_bestsName);
    if (rawText != null) {
      try {
        final raw = jsonDecode(rawText);
        if (raw is Map && raw['bests'] is Map) {
          final bests = <String, PracticeBest>{};
          for (final entry in (raw['bests'] as Map).entries) {
            final parsed = PracticeBest.tryParse(entry.value);
            if (parsed != null) bests[parsed.versionKey] = parsed;
          }
          return bests;
        }
      } catch (_) {
        // Corrupt bests: rebuild from history without discarding valid scores.
      }
    }
    final rebuilt = <String, PracticeBest>{};
    for (final record in await _loadRecords()) {
      final existing = rebuilt[record.versionKey];
      if (existing == null || record.score > existing.score) {
        rebuilt[record.versionKey] = PracticeBest.fromRecord(record);
      }
    }
    if (rebuilt.isNotEmpty) {
      await _writeBests(rebuilt);
    }
    return rebuilt;
  }

  Future<void> _updateBest(PracticeRecord record) async {
    final bests = Map<String, PracticeBest>.of(await _loadBests());
    final existing = bests[record.versionKey];
    if (existing == null || record.score > existing.score) {
      bests[record.versionKey] = PracticeBest.fromRecord(record);
      await _writeBests(bests);
    }
  }

  Future<void> _writeRecords(List<PracticeRecord> records) async {
    await _kv.writeAtomic(
      _recordsName,
      jsonEncode([for (final item in records) item.toJson()]),
    );
  }

  Future<void> _writeBests(Map<String, PracticeBest> bests) async {
    await _kv.writeAtomic(
      _bestsName,
      jsonEncode({
        'schemaVersion': schemaVersion,
        'scope': scope.storageKey,
        'bests': {
          for (final entry in bests.entries) entry.key: entry.value.toJson(),
        },
      }),
    );
  }

  /// Legacy unscoped / label-scoped files migrate only into the active guest
  /// scope, never into an authenticated player scope.
  Future<void> _migrateLegacyIntoGuestIfNeeded() async {
    if (scope.kind != PracticeIdentityKind.guest) return;
    final identity = _identity;
    if (identity != null && identity.legacyLabelScopesMigratedToGuest) {
      return;
    }
    if (await _kv.exists(_recordsName)) {
      await identity?.markLegacyLabelScopesMigratedToGuest();
      return;
    }

    final names = await _kv.listFileNames();
    final sources = <String>['practice-records.json'];
    for (final name in names) {
      final match = RegExp(r'^practice-records-(.+)\.json$').firstMatch(name);
      if (match == null) continue;
      final token = match.group(1)!;
      if (PracticeIdentityScope.tryParseStorageKey(token) != null) continue;
      sources.add(name);
    }

    final merged = <PracticeRecord>[];
    final seen = <String>{};
    for (final name in sources) {
      final text = await _kv.read(name);
      if (text == null) continue;
      try {
        final raw = jsonDecode(text);
        if (raw is! List) continue;
        for (final item in raw) {
          final record = PracticeRecord.tryParse(item);
          if (record == null || !seen.add(record.sessionId)) continue;
          merged.add(record);
        }
      } catch (_) {
        // Leave corrupt legacy sources untouched.
      }
    }
    if (merged.isNotEmpty) {
      final kept = merged.length > maxRecords
          ? merged.sublist(merged.length - maxRecords)
          : merged;
      await _writeRecords(kept);
      final bests = <String, PracticeBest>{};
      for (final record in kept) {
        final existing = bests[record.versionKey];
        if (existing == null || record.score > existing.score) {
          bests[record.versionKey] = PracticeBest.fromRecord(record);
        }
      }
      await _writeBests(bests);
    }

    if (!await _kv.exists(_seedName)) {
      final legacySeed = await _kv.read('practice-seed.txt');
      if (legacySeed != null) {
        await _kv.writeAtomic(_seedName, legacySeed);
      }
    }
    await identity?.markLegacyLabelScopesMigratedToGuest();
  }
}
