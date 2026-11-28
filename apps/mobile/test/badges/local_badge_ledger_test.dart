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

  int completedAtMsFor(String utcDate) =>
      DateTime.parse('${utcDate}T12:00:00.000Z').millisecondsSinceEpoch;

  Future<void> recordPractice(String id, String utcDate) {
    return ledger.recordPracticeCompletion(
      completionId: id,
      completedAtMs: completedAtMsFor(utcDate),
      difficulty: 'easy',
      rulesVersion: 'core-001.v3',
      generatorVersion: 'gen-001.v1',
    );
  }

  test('loyalty awards once per UTC activity day', () async {
    await recordPractice('p1', '2026-11-20');
    await recordPractice('p2', '2026-11-20');
    await recordPractice('p3', '2026-11-21');
    final counts = await ledger.earnedCounts();
    expect(counts[BadgeId.loyalty], 2);
  });

  test('practice master milestones every 10 completions', () async {
    for (var i = 0; i < 20; i++) {
      await recordPractice('p-$i', '2026-11-${(20 + (i ~/ 10)).toString().padLeft(2, '0')}');
    }
    final counts = await ledger.earnedCounts();
    expect(counts[BadgeId.practiceMaster], 2);
  });

  test('unstoppable: 7 + miss + 7 = 2 lifetime awards', () async {
    for (var day = 1; day <= 7; day++) {
      await recordPractice('s-$day', '2026-11-${day.toString().padLeft(2, '0')}');
    }
    var counts = await ledger.earnedCounts();
    expect(counts[BadgeId.unstoppable], 1);

    for (var day = 9; day <= 15; day++) {
      await recordPractice('t-$day', '2026-11-${day.toString().padLeft(2, '0')}');
    }
    counts = await ledger.earnedCounts();
    expect(counts[BadgeId.unstoppable], 2);
  });

  test('fence + account switch isolates ledger files', () async {
    await recordPractice('a1', '2026-11-01');
    final guestCounts = await ledger.earnedCounts();
    expect(guestCounts[BadgeId.loyalty], 1);
    ledger.fence();
    await identity.bindAuthenticatedPlayer(
      '22222222-2222-4222-8222-222222222222',
    );
    await recordPractice('b1', '2026-11-02');
    final playerCounts = await ledger.earnedCounts();
    // New scope starts empty aside from b1.
    expect(playerCounts[BadgeId.loyalty], 1);
  });

  test('pending queue retains overflow beyond sync batch', () async {
    for (var i = 0; i < 45; i++) {
      await recordPractice('q-$i', '2026-12-${((i % 28) + 1).toString().padLeft(2, '0')}');
    }
    expect(await ledger.pendingCount(), 45);
    final batch = await ledger.peekPendingCompletions(limit: 40);
    expect(batch, hasLength(40));
    await ledger.acknowledgeSyncedCompletions({
      for (final row in batch) row['completionId']!.toString(),
    });
    expect(await ledger.pendingCount(), 5);
  });

  test('does not invent tournament-only awards', () async {
    await recordPractice('p-1', '2026-11-20');
    final counts = await ledger.earnedCounts();
    expect(counts[BadgeId.onTime], 0);
    expect(counts[BadgeId.champion], 0);
    expect(counts[BadgeId.tournamentGuru], 0);
    expect(counts[BadgeId.risingStar], 0);
  });

  test('A→B→A during fence keeps player ledgers isolated', () async {
    await recordPractice('g1', '2026-11-01');
    ledger.fence();
    await identity.bindAuthenticatedPlayer(
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    );
    await recordPractice('a1', '2026-11-02');
    ledger.fence();
    await identity.clearAuthenticatedPlayer();
    final guest = await ledger.earnedCounts();
    expect(guest[BadgeId.loyalty], 1);
    ledger.fence();
    await identity.bindAuthenticatedPlayer(
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    );
    final emptyB = await ledger.earnedCounts();
    expect(emptyB[BadgeId.loyalty], 0);
    ledger.fence();
    await identity.bindAuthenticatedPlayer(
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    );
    final restoredA = await ledger.earnedCounts();
    expect(restoredA[BadgeId.loyalty], 1);
  });

  test('adoptGuestProgressIntoActivePlayer unions pending completions', () async {
    await recordPractice('guest-1', '2026-11-10');
    await recordPractice('guest-2', '2026-11-11');
    expect(await ledger.pendingCount(), 2);
    ledger.fence();
    await identity.bindAuthenticatedPlayer(
      'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    );
    await ledger.adoptGuestProgressIntoActivePlayer();
    expect(await ledger.pendingCount(), 2);
    final counts = await ledger.earnedCounts();
    expect(counts[BadgeId.loyalty], 2);
  });

  test('concurrent same-scope completions serialize without lost updates', () async {
    await Future.wait([
      for (var i = 0; i < 8; i++)
        recordPractice('par-$i', '2026-11-${(10 + i).toString().padLeft(2, '0')}'),
    ]);
    final counts = await ledger.earnedCounts();
    expect(counts[BadgeId.loyalty], 8);
    expect(await ledger.pendingCount(), 8);
  });
}
