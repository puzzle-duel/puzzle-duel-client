import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/badges/domain/badge_definition.dart';
import 'package:puzzle_duel_mobile/badges/local/local_badge_ledger.dart';
import 'package:puzzle_duel_mobile/tournament/local_kv_store.dart';
import 'package:puzzle_duel_mobile/tournament/practice_identity.dart';

void main() {
  late Directory dir;
  late PracticeIdentityStore identity;
  late MemoryKvStore store;
  late LocalBadgeLedger ledger;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pzd56-badge-ledger');
    identity = PracticeIdentityStore(dir);
    await identity.load();
    store = MemoryKvStore();
    ledger = LocalBadgeLedger(store: store, identity: identity);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('loyalty awards once per UTC day', () async {
    await ledger.recordEligibleCompletion(utcDate: '2026-11-20');
    await ledger.recordEligibleCompletion(utcDate: '2026-11-20');
    await ledger.recordEligibleCompletion(utcDate: '2026-11-21');
    final counts = await ledger.earnedCounts();
    expect(counts[BadgeId.loyalty], 2);
  });

  test('practice master milestones every 10 completions', () async {
    for (var i = 0; i < 20; i++) {
      await ledger.recordEligibleCompletion(
        utcDate: '2026-11-${(20 + (i ~/ 10)).toString().padLeft(2, '0')}',
        practiceCompletionId: 'p-$i',
      );
    }
    final counts = await ledger.earnedCounts();
    expect(counts[BadgeId.practiceMaster], 2);
  });

  test('unstoppable streak resets on miss but keeps prior awards', () async {
    for (var day = 1; day <= 7; day++) {
      await ledger.recordEligibleCompletion(
        utcDate: '2026-11-${day.toString().padLeft(2, '0')}',
        practiceCompletionId: 's-$day',
      );
    }
    var counts = await ledger.earnedCounts();
    expect(counts[BadgeId.unstoppable], 1);

    // Miss a day then resume — prior award remains; new streak incomplete.
    await ledger.recordEligibleCompletion(
      utcDate: '2026-11-09',
      practiceCompletionId: 's-9',
    );
    counts = await ledger.earnedCounts();
    expect(counts[BadgeId.unstoppable], 1);
  });

  test('does not invent tournament-only awards', () async {
    await ledger.recordEligibleCompletion(
      utcDate: '2026-11-20',
      practiceCompletionId: 'p-1',
    );
    final counts = await ledger.earnedCounts();
    expect(counts[BadgeId.onTime], 0);
    expect(counts[BadgeId.champion], 0);
    expect(counts[BadgeId.tournamentGuru], 0);
    expect(counts[BadgeId.risingStar], 0);
  });
}
