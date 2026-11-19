import 'dart:convert';
import 'dart:io';

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
final class PracticeStore {
  PracticeStore({
    required Directory directory,
    required this.scope,
    PracticeIdentityStore? identity,
  }) : _directory = directory,
       _identity = identity,
       _records = File(
         '${directory.path}/practice-records-${scope.storageKey}.json',
       ),
       _bests = File(
         '${directory.path}/practice-bests-${scope.storageKey}.json',
       ),
       _seed = File('${directory.path}/practice-seed-${scope.storageKey}.txt');

  /// History retention. Personal bests survive pruning via [_bests].
  static const int maxRecords = 40;
  static const int schemaVersion = 2;

  final PracticeIdentityScope scope;
  final Directory _directory;
  final PracticeIdentityStore? _identity;
  final File _records;
  final File _bests;
  final File _seed;

  Future<int> nextSeed() async {
    await _maybeMigrateLegacyIntoGuest();
    var current = 1;
    if (_seed.existsSync()) {
      current = int.tryParse(_seed.readAsStringSync().trim()) ?? 1;
    }
    if (current < 1 || current > 4294967294) current = 1;
    final issued = current;
    _atomicWrite(_seed, '${issued + 1}');
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
    await _maybeMigrateLegacyIntoGuest();
    final all = await load();
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
    await _maybeMigrateLegacyIntoGuest();
    if (!_records.existsSync()) return [];
    try {
      final raw = jsonDecode(_records.readAsStringSync());
      if (raw is! List) return [];
      return [for (final item in raw) ?PracticeRecord.tryParse(item)];
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, PracticeBest>> loadBests() async {
    await _maybeMigrateLegacyIntoGuest();
    if (_bests.existsSync()) {
      try {
        final raw = jsonDecode(_bests.readAsStringSync());
        if (raw is Map && raw['bests'] is Map) {
          final bests = <String, PracticeBest>{};
          for (final entry in (raw['bests'] as Map).entries) {
            final parsed = PracticeBest.tryParse(entry.value);
            if (parsed != null) bests[parsed.versionKey] = parsed;
          }
          return bests;
        }
      } catch (_) {
        // Corrupt bests: rebuild from history without deleting the corrupt file
        // until a successful rewrite completes.
      }
    }
    final rebuilt = <String, PracticeBest>{};
    for (final record in await load()) {
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
    final bests = Map<String, PracticeBest>.of(await loadBests());
    final existing = bests[record.versionKey];
    if (existing == null || record.score > existing.score) {
      bests[record.versionKey] = PracticeBest.fromRecord(record);
      await _writeBests(bests);
    }
  }

  Future<void> _writeRecords(List<PracticeRecord> records) async {
    _atomicWrite(
      _records,
      jsonEncode([for (final item in records) item.toJson()]),
    );
  }

  Future<void> _writeBests(Map<String, PracticeBest> bests) async {
    _atomicWrite(
      _bests,
      jsonEncode({
        'schemaVersion': schemaVersion,
        'scope': scope.storageKey,
        'bests': {
          for (final entry in bests.entries) entry.key: entry.value.toJson(),
        },
      }),
    );
  }

  void _atomicWrite(File file, String contents) {
    file.parent.createSync(recursive: true);
    final tmp = File('${file.path}.tmp');
    tmp.writeAsStringSync(contents, flush: true);
    if (file.existsSync()) {
      file.deleteSync();
    }
    tmp.renameSync(file.path);
  }

  /// Legacy unscoped / label-scoped files migrate only into the active guest
  /// scope, never into an authenticated player scope.
  Future<void> _maybeMigrateLegacyIntoGuest() async {
    if (scope.kind != PracticeIdentityKind.guest) return;
    final identity = _identity;
    if (identity != null && identity.legacyLabelScopesMigratedToGuest) {
      return;
    }
    if (_records.existsSync()) {
      await identity?.markLegacyLabelScopesMigratedToGuest();
      return;
    }

    final sources = <File>[File('${_directory.path}/practice-records.json')];
    if (_directory.existsSync()) {
      for (final entity in _directory.listSync(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.isEmpty
            ? entity.path
            : entity.uri.pathSegments.last;
        final match = RegExp(r'^practice-records-(.+)\.json$').firstMatch(name);
        if (match == null) continue;
        final token = match.group(1)!;
        if (PracticeIdentityScope.tryParseStorageKey(token) != null) continue;
        sources.add(entity);
      }
    }

    final merged = <PracticeRecord>[];
    final seen = <String>{};
    for (final source in sources) {
      if (!source.existsSync()) continue;
      try {
        final raw = jsonDecode(source.readAsStringSync());
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

    final legacySeed = File('${_directory.path}/practice-seed.txt');
    if (!_seed.existsSync() && legacySeed.existsSync()) {
      try {
        _atomicWrite(_seed, legacySeed.readAsStringSync());
      } catch (_) {}
    }
    await identity?.markLegacyLabelScopesMigratedToGuest();
  }
}
