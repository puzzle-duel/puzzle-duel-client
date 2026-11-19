import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/tournament/practice_store.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('pzd43-practice-store');
  });

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

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

  test('starts empty and persists completions', () {
    final store = PracticeStore(directory, playerScope: 'alice');
    expect(store.load(), isEmpty);
    expect(store.stats().completedCount, 0);
    expect(
      store.append(record(sessionId: 'a1', difficulty: 'easy', score: 40)),
      isTrue,
    );
    expect(store.load(), hasLength(1));
    expect(store.stats().completedCount, 1);
    expect(
      store.bestScore(
        'easy',
        rulesVersion: 'core-001.v2',
        generatorVersion: 'gen-001.v1',
      ),
      40,
    );
  });

  test('replaces personal best and ignores lower scores', () {
    final store = PracticeStore(directory, playerScope: 'alice');
    store.append(record(sessionId: 'a1', difficulty: 'medium', score: 50));
    store.append(record(sessionId: 'a2', difficulty: 'medium', score: 80));
    store.append(record(sessionId: 'a3', difficulty: 'medium', score: 70));
    expect(
      store.bestScore(
        'medium',
        rulesVersion: 'core-001.v2',
        generatorVersion: 'gen-001.v1',
      ),
      80,
    );
  });

  test('isolates difficulties and incompatible versions', () {
    final store = PracticeStore(directory, playerScope: 'alice');
    store.append(record(sessionId: 'e', difficulty: 'easy', score: 10));
    store.append(record(sessionId: 'h', difficulty: 'hard', score: 90));
    store.append(
      record(
        sessionId: 'e-old',
        difficulty: 'easy',
        score: 999,
        rulesVersion: 'core-001.v1',
      ),
    );
    expect(
      store.bestScore(
        'easy',
        rulesVersion: 'core-001.v2',
        generatorVersion: 'gen-001.v1',
      ),
      10,
    );
    expect(
      store.personalBestForDifficulty('easy', rulesVersion: 'core-001.v3'),
      isNull,
    );
    expect(
      store.bestScore(
        'hard',
        rulesVersion: 'core-001.v2',
        generatorVersion: 'gen-001.v1',
      ),
      90,
    );
  });

  test('rejects duplicate session ids', () {
    final store = PracticeStore(directory, playerScope: 'alice');
    final first = record(sessionId: 'same', difficulty: 'easy', score: 20);
    expect(store.append(first), isTrue);
    expect(store.append(first), isFalse);
    expect(store.load(), hasLength(1));
  });

  test('survives restart and preserves bests when history is pruned', () {
    final writing = PracticeStore(directory, playerScope: 'alice');
    for (var i = 0; i < PracticeStore.maxRecords + 5; i++) {
      writing.append(
        record(sessionId: 's$i', difficulty: 'easy', score: i == 0 ? 1000 : i),
      );
    }
    expect(writing.load(), hasLength(PracticeStore.maxRecords));
    expect(
      writing.bestScore(
        'easy',
        rulesVersion: 'core-001.v2',
        generatorVersion: 'gen-001.v1',
      ),
      1000,
    );

    final reloaded = PracticeStore(directory, playerScope: 'alice');
    expect(
      reloaded.bestScore(
        'easy',
        rulesVersion: 'core-001.v2',
        generatorVersion: 'gen-001.v1',
      ),
      1000,
    );
    expect(reloaded.load().any((item) => item.score == 1000), isFalse);
  });

  test('isolates players and does not merge guest into signed-in', () {
    final guest = PracticeStore(directory, playerScope: 'guest');
    guest.append(record(sessionId: 'g1', difficulty: 'easy', score: 55));
    final alice = PracticeStore(directory, playerScope: 'alice');
    expect(alice.load(), isEmpty);
    expect(
      alice.bestScore(
        'easy',
        rulesVersion: 'core-001.v2',
        generatorVersion: 'gen-001.v1',
      ),
      isNull,
    );
    alice.append(record(sessionId: 'a1', difficulty: 'easy', score: 12));
    expect(guest.load(), hasLength(1));
    expect(alice.load(), hasLength(1));
  });

  test('migrates legacy unscoped files only into guest scope', () {
    File('${directory.path}/practice-records.json').writeAsStringSync(
      '[{"sessionId":"legacy","difficulty":"hard","rulesVersion":"core-001.v2",'
      '"generatorVersion":"gen-001.v1","seed":1,"score":33,'
      '"terminalReason":"ended","completedAt":"2026-11-01T00:00:00.000Z","verifiedRank":false}]',
    );
    final guest = PracticeStore(directory, playerScope: 'guest');
    expect(guest.load().single.score, 33);
    final bob = PracticeStore(directory, playerScope: 'bob');
    expect(bob.load(), isEmpty);
  });
}
