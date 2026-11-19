import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/tournament/local_kv_store.dart';
import 'package:puzzle_duel_mobile/tournament/practice_identity.dart';
import 'package:puzzle_duel_mobile/tournament/practice_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late PracticeIdentityStore identity;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('pzd43-practice-store');
    identity = PracticeIdentityStore(directory, random: Random(9));
    await identity.load();
  });

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  PracticeStore store() => PracticeStore(
    store: DirectoryKvStore(directory),
    scope: identity.activeScope,
    identity: identity,
  );

  PracticeRecord record({
    required String sessionId,
    required String difficulty,
    required int score,
    String rulesVersion = 'core-001.v2',
    String generatorVersion = 'gen-001.v1',
  }) {
    return PracticeRecord(
      sessionId: sessionId,
      difficulty: difficulty,
      rulesVersion: rulesVersion,
      generatorVersion: generatorVersion,
      seed: 1,
      score: score,
      terminalReason: 'move_limit_reached',
      completedAt: '2026-11-19T12:00:00.000Z',
      moveCount: 10,
    );
  }

  test('starts empty and persists completions asynchronously', () async {
    final practice = store();
    expect(await practice.load(), isEmpty);
    expect((await practice.stats()).completedCount, 0);
    expect(
      await practice.append(
        record(sessionId: 'a1', difficulty: 'easy', score: 40),
      ),
      isTrue,
    );
    expect(await practice.load(), hasLength(1));
    expect(
      await practice.bestScore(
        'easy',
        rulesVersion: 'core-001.v2',
        generatorVersion: 'gen-001.v1',
      ),
      40,
    );
  });

  test('preserves personal bests when history is pruned', () async {
    final practice = store();
    for (var i = 0; i < PracticeStore.maxRecords + 5; i++) {
      await practice.append(
        record(sessionId: 's$i', difficulty: 'easy', score: i == 0 ? 1000 : i),
      );
    }
    expect(await practice.load(), hasLength(PracticeStore.maxRecords));
    expect(
      await practice.bestScore(
        'easy',
        rulesVersion: 'core-001.v2',
        generatorVersion: 'gen-001.v1',
      ),
      1000,
    );
  });

  test('corrupt bests file does not erase valid history bests permanently', () async {
    final practice = store();
    await practice.append(
      record(sessionId: 'ok', difficulty: 'medium', score: 77),
    );
    final bests = File(
      '${directory.path}/practice-bests-${identity.activeScope.storageKey}.json',
    );
    await bests.writeAsString('{not-json');
    expect(
      await practice.bestScore(
        'medium',
        rulesVersion: 'core-001.v2',
        generatorVersion: 'gen-001.v1',
      ),
      77,
    );
  });

  test('rejects duplicates and isolates incompatible versions', () async {
    final practice = store();
    final first = record(sessionId: 'same', difficulty: 'easy', score: 20);
    expect(await practice.append(first), isTrue);
    expect(await practice.append(first), isFalse);
    await practice.append(
      record(
        sessionId: 'old',
        difficulty: 'easy',
        score: 999,
        rulesVersion: 'core-001.v1',
      ),
    );
    expect(
      await practice.bestScore(
        'easy',
        rulesVersion: 'core-001.v2',
        generatorVersion: 'gen-001.v1',
      ),
      20,
    );
  });
}
