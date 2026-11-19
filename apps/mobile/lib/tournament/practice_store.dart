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
  });

  final String sessionId;
  final String difficulty;
  final String rulesVersion;
  final String generatorVersion;
  final int seed;
  final int score;
  final String terminalReason;
  final String completedAt;

  Map<String, Object?> toJson() => {
    'sessionId': sessionId,
    'difficulty': difficulty,
    'rulesVersion': rulesVersion,
    'generatorVersion': generatorVersion,
    'seed': seed,
    'score': score,
    'terminalReason': terminalReason,
    'completedAt': completedAt,
    'verifiedRank': false,
  };
}

/// Bounded on-device practice history and the next fresh seed.
///
/// Uninstall and a wiped app directory delete this file. It is never sent to
/// the tournament claim, publication, or leaderboard APIs.
final class PracticeStore {
  PracticeStore(Directory directory)
    : _records = File('${directory.path}/practice-records.json'),
      _seed = File('${directory.path}/practice-seed.txt');

  static const int maxRecords = 40;

  final File _records;
  final File _seed;

  int nextSeed() {
    var current = 1;
    if (_seed.existsSync()) {
      current = int.tryParse(_seed.readAsStringSync().trim()) ?? 1;
    }
    if (current < 1 || current > 4294967294) current = 1;
    final issued = current;
    _seed.parent.createSync(recursive: true);
    _seed.writeAsStringSync('${issued + 1}');
    return issued;
  }

  int? bestScore(String difficulty) {
    final scores = [
      for (final record in load())
        if (record.difficulty == difficulty) record.score,
    ];
    if (scores.isEmpty) return null;
    return scores.reduce((best, score) => score > best ? score : best);
  }

  void append(PracticeRecord record) {
    final all = load();
    all.add(record);
    final kept = all.length > maxRecords ? all.sublist(all.length - maxRecords) : all;
    _records.parent.createSync(recursive: true);
    _records.writeAsStringSync(jsonEncode([for (final item in kept) item.toJson()]));
  }

  List<PracticeRecord> load() {
    if (!_records.existsSync()) return [];
    try {
      final raw = jsonDecode(_records.readAsStringSync());
      if (raw is! List) return [];
      return [
        for (final item in raw)
          if (item is Map)
            PracticeRecord(
              sessionId: item['sessionId']?.toString() ?? '',
              difficulty: item['difficulty']?.toString() ?? '',
              rulesVersion: item['rulesVersion']?.toString() ?? '',
              generatorVersion: item['generatorVersion']?.toString() ?? '',
              seed: item['seed'] is num ? (item['seed'] as num).toInt() : 0,
              score: item['score'] is num ? (item['score'] as num).toInt() : 0,
              terminalReason: item['terminalReason']?.toString() ?? '',
              completedAt: item['completedAt']?.toString() ?? '',
            ),
      ];
    } catch (_) {
      return [];
    }
  }
}
