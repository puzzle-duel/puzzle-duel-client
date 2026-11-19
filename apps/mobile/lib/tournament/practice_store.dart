import 'dart:convert';
import 'dart:io';

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
    final sourceWire = raw['source']?.toString();
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
      source: PracticeSource.fromWire(sourceWire),
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

/// Aggregate counts derived only from persisted practice records and bests.
final class PracticeStats {
  const PracticeStats({
    required this.completedCount,
    required this.difficultyCounts,
  });

  final int completedCount;
  final Map<String, int> difficultyCounts;
}

/// Bounded on-device practice history, immortalized personal bests, and next seed.
///
/// Uninstall and a wiped app directory delete these files. Records are never
/// sent to tournament claim, publication, or leaderboard APIs. Scopes isolate
/// players on a shared device; guest records are never auto-merged on login.
final class PracticeStore {
  PracticeStore(Directory directory, {String playerScope = 'guest'})
    : playerScope = sanitizePlayerScope(playerScope),
      _directory = directory,
      _records = File(
        '${directory.path}/practice-records-${sanitizePlayerScope(playerScope)}.json',
      ),
      _bests = File(
        '${directory.path}/practice-bests-${sanitizePlayerScope(playerScope)}.json',
      ),
      _seed = File(
        '${directory.path}/practice-seed-${sanitizePlayerScope(playerScope)}.txt',
      ),
      _legacyRecords = File('${directory.path}/practice-records.json'),
      _legacySeed = File('${directory.path}/practice-seed.txt');

  /// History retention. Personal bests survive pruning via [_bests].
  static const int maxRecords = 40;
  static const int schemaVersion = 1;

  final String playerScope;
  final Directory _directory;
  final File _records;
  final File _bests;
  final File _seed;
  final File _legacyRecords;
  final File _legacySeed;

  static String sanitizePlayerScope(String raw) {
    final cleaned = raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (cleaned.isEmpty || cleaned.length > 64) return 'guest';
    return cleaned;
  }

  int nextSeed() {
    var current = 1;
    final seedFile = _seed.existsSync()
        ? _seed
        : (playerScope == 'guest' && _legacySeed.existsSync()
              ? _legacySeed
              : _seed);
    if (seedFile.existsSync()) {
      current = int.tryParse(seedFile.readAsStringSync().trim()) ?? 1;
    }
    if (current < 1 || current > 4294967294) current = 1;
    final issued = current;
    _seed.parent.createSync(recursive: true);
    _seed.writeAsStringSync('${issued + 1}');
    return issued;
  }

  /// Highest score for [difficulty] under an exact rules/generator match.
  /// Incompatible versions are never compared.
  int? bestScore(
    String difficulty, {
    required String rulesVersion,
    required String generatorVersion,
  }) {
    return personalBest(
      difficulty,
      rulesVersion: rulesVersion,
      generatorVersion: generatorVersion,
    )?.score;
  }

  PracticeBest? personalBest(
    String difficulty, {
    required String rulesVersion,
    required String generatorVersion,
  }) {
    final key = '$difficulty|$rulesVersion|$generatorVersion';
    return loadBests()[key];
  }

  /// Best available for [difficulty] under [rulesVersion], preferring the
  /// requested generator when present.
  PracticeBest? personalBestForDifficulty(
    String difficulty, {
    required String rulesVersion,
    String? preferredGeneratorVersion,
  }) {
    final matches = loadBests().values.where(
      (best) =>
          best.difficulty == difficulty && best.rulesVersion == rulesVersion,
    );
    if (matches.isEmpty) return null;
    if (preferredGeneratorVersion != null) {
      for (final best in matches) {
        if (best.generatorVersion == preferredGeneratorVersion) return best;
      }
    }
    return null;
  }

  PracticeStats stats() {
    final records = load();
    final counts = <String, int>{};
    for (final record in records) {
      counts[record.difficulty] = (counts[record.difficulty] ?? 0) + 1;
    }
    // Bests may outlive pruned history; count at least one completion per best.
    final bests = loadBests();
    var completed = records.length;
    for (final best in bests.values) {
      final inHistory = records.any(
        (record) => record.sessionId == best.sessionId,
      );
      if (!inHistory) completed += 1;
      counts.putIfAbsent(best.difficulty, () => 0);
      if (!inHistory) {
        counts[best.difficulty] = (counts[best.difficulty] ?? 0) + 1;
      }
    }
    return PracticeStats(completedCount: completed, difficultyCounts: counts);
  }

  /// Appends a completed practice result. Duplicate [sessionId] is ignored.
  /// Incomplete games must never call this.
  bool append(PracticeRecord record) {
    if (record.sessionId.isEmpty) return false;
    if (record.source != PracticeSource.localPractice) return false;
    final all = load();
    if (all.any((item) => item.sessionId == record.sessionId)) {
      return false;
    }
    all.add(record);
    final kept = all.length > maxRecords
        ? all.sublist(all.length - maxRecords)
        : all;
    _writeRecords(kept);
    _updateBest(record);
    return true;
  }

  List<PracticeRecord> load() {
    _maybeMigrateLegacyGuest();
    if (!_records.existsSync()) return [];
    try {
      final raw = jsonDecode(_records.readAsStringSync());
      if (raw is! List) return [];
      return [for (final item in raw) ?PracticeRecord.tryParse(item)];
    } catch (_) {
      return [];
    }
  }

  Map<String, PracticeBest> loadBests() {
    _maybeMigrateLegacyGuest();
    final fromFile = <String, PracticeBest>{};
    if (_bests.existsSync()) {
      try {
        final raw = jsonDecode(_bests.readAsStringSync());
        if (raw is Map && raw['bests'] is Map) {
          final bests = raw['bests'] as Map;
          for (final entry in bests.entries) {
            final parsed = PracticeBest.tryParse(entry.value);
            if (parsed != null) fromFile[parsed.versionKey] = parsed;
          }
        }
      } catch (_) {
        // Fall through and rebuild from history.
      }
    }
    if (fromFile.isNotEmpty) return fromFile;
    final rebuilt = <String, PracticeBest>{};
    for (final record in load()) {
      final existing = rebuilt[record.versionKey];
      if (existing == null || record.score > existing.score) {
        rebuilt[record.versionKey] = PracticeBest.fromRecord(record);
      }
    }
    if (rebuilt.isNotEmpty) _writeBests(rebuilt);
    return rebuilt;
  }

  void _updateBest(PracticeRecord record) {
    final bests = Map<String, PracticeBest>.of(loadBests());
    final existing = bests[record.versionKey];
    if (existing == null || record.score > existing.score) {
      bests[record.versionKey] = PracticeBest.fromRecord(record);
      _writeBests(bests);
    }
  }

  void _writeRecords(List<PracticeRecord> records) {
    _records.parent.createSync(recursive: true);
    _records.writeAsStringSync(
      jsonEncode([for (final item in records) item.toJson()]),
    );
  }

  void _writeBests(Map<String, PracticeBest> bests) {
    _bests.parent.createSync(recursive: true);
    _bests.writeAsStringSync(
      jsonEncode({
        'schemaVersion': schemaVersion,
        'playerScope': playerScope,
        'bests': {
          for (final entry in bests.entries) entry.key: entry.value.toJson(),
        },
      }),
    );
  }

  /// Legacy unscoped files belong only to the guest scope. Never merge into a
  /// signed-in player scope automatically.
  void _maybeMigrateLegacyGuest() {
    if (playerScope != 'guest') return;
    if (_records.existsSync()) return;
    if (!_legacyRecords.existsSync()) return;
    try {
      _directory.createSync(recursive: true);
      _legacyRecords.copySync(_records.path);
      if (_legacySeed.existsSync() && !_seed.existsSync()) {
        _legacySeed.copySync(_seed.path);
      }
    } catch (_) {
      // Leave legacy files untouched when migration fails.
    }
  }
}
