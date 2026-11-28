import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/badges/domain/badge_definition.dart';
import 'package:puzzle_duel_mobile/badges/domain/badge_milestones.dart';
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

  test('unstoppable: days 2–8 then day 1 = exactly one persisted award', () async {
    for (var day = 2; day <= 8; day++) {
      await recordPractice('s-$day', '2026-11-${day.toString().padLeft(2, '0')}');
    }
    var counts = await ledger.earnedCounts();
    expect(counts[BadgeId.unstoppable], 1);
    await recordPractice('s-1', '2026-11-01');
    counts = await ledger.earnedCounts();
    expect(counts[BadgeId.unstoppable], 1);
    expect(
      BadgeMilestones.unstoppableOccurrenceEvidenceKey(1),
      'unstoppable:occurrence:1',
    );
  });

  test('unstoppable: 7 + miss + 7 = 2; fill gap later stays 2', () async {
    for (var day = 1; day <= 7; day++) {
      await recordPractice('a-$day', '2026-11-${day.toString().padLeft(2, '0')}');
    }
    for (var day = 9; day <= 15; day++) {
      await recordPractice('b-$day', '2026-11-${day.toString().padLeft(2, '0')}');
    }
    expect((await ledger.earnedCounts())[BadgeId.unstoppable], 2);
    await recordPractice('gap', '2026-11-08');
    expect((await ledger.earnedCounts())[BadgeId.unstoppable], 2);
  });

  test('fourteen consecutive days = 2 awards', () async {
    for (var day = 1; day <= 14; day++) {
      await recordPractice('d-$day', '2026-11-${day.toString().padLeft(2, '0')}');
    }
    expect((await ledger.earnedCounts())[BadgeId.unstoppable], 2);
  });

  test('repeated rebuild is idempotent on persisted counts', () async {
    for (var day = 1; day <= 7; day++) {
      await recordPractice('r-$day', '2026-11-${day.toString().padLeft(2, '0')}');
    }
    expect((await ledger.earnedCounts())[BadgeId.unstoppable], 1);
    await recordPractice('r-7b', '2026-11-07');
    expect((await ledger.earnedCounts())[BadgeId.unstoppable], 1);
  });

  test('single journal: pending recovered from completions without separate write',
      () async {
    await recordPractice('q-1', '2026-11-10');
    expect(await ledger.pendingCount(), 1);
    final batch = await ledger.peekPendingCompletions();
    expect(batch, hasLength(1));
    await ledger.acknowledgeSyncedCompletions({'q-1'});
    expect(await ledger.pendingCount(), 0);
  });

  test('pending queue retains overflow beyond sync batch', () async {
    for (var i = 0; i < 45; i++) {
      await recordPractice(
        'q-$i',
        '2026-12-${((i % 28) + 1).toString().padLeft(2, '0')}',
      );
    }
    expect(await ledger.pendingCount(), 45);
    final batch = await ledger.peekPendingCompletions(limit: 40);
    expect(batch, hasLength(40));
    await ledger.acknowledgeSyncedCompletions({
      for (final row in batch) row['completionId']!.toString(),
    });
    expect(await ledger.pendingCount(), 5);
  });

  test('authorized guest adoption is durable and not re-imported', () async {
    await recordPractice('guest-1', '2026-11-10');
    await recordPractice('guest-2', '2026-11-11');
    final guestId = identity.guestLocalId;
    ledger.fence();
    await identity.bindAuthenticatedPlayer(
      'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    );
    final auth = BadgeGuestAdoptionAuthorization(
      sourceGuestLocalId: guestId,
      targetPlayerId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    );
    expect(await ledger.adoptGuestProgressIntoActivePlayer(auth), isTrue);
    expect(await ledger.pendingCount(), 2);
    expect((await ledger.earnedCounts())[BadgeId.loyalty], 2);
    // Repeat adoption must not duplicate pending.
    expect(await ledger.adoptGuestProgressIntoActivePlayer(auth), isTrue);
    expect(await ledger.pendingCount(), 2);
    await ledger.acknowledgeSyncedCompletions({'guest-1', 'guest-2'});
    expect(await ledger.pendingCount(), 0);
    expect(await ledger.adoptGuestProgressIntoActivePlayer(auth), isTrue);
    expect(await ledger.pendingCount(), 0);
  });

  test('guest cannot transfer to unrelated verified B after export to A', () async {
    await recordPractice('g1', '2026-11-01');
    final guestId = identity.guestLocalId;
    ledger.fence();
    await identity.bindAuthenticatedPlayer(
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    );
    expect(
      await ledger.adoptGuestProgressIntoActivePlayer(
        BadgeGuestAdoptionAuthorization(
          sourceGuestLocalId: guestId,
          targetPlayerId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        ),
      ),
      isTrue,
    );
    ledger.fence();
    await identity.bindAuthenticatedPlayer(
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    );
    expect(
      await ledger.adoptGuestProgressIntoActivePlayer(
        BadgeGuestAdoptionAuthorization(
          sourceGuestLocalId: guestId,
          targetPlayerId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        ),
      ),
      isFalse,
    );
    expect(await ledger.pendingCount(), 0);
  });

  test('unauthorized adoption without matching guest id fails', () async {
    ledger.fence();
    await identity.bindAuthenticatedPlayer(
      'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    );
    expect(
      await ledger.adoptGuestProgressIntoActivePlayer(
        const BadgeGuestAdoptionAuthorization(
          sourceGuestLocalId: '11111111-1111-4111-8111-111111111111',
          targetPlayerId: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
        ),
      ),
      isFalse,
    );
  });

  test('concurrent same-scope completions serialize without lost updates', () async {
    await Future.wait([
      for (var i = 0; i < 8; i++)
        recordPractice(
          'par-$i',
          '2026-11-${(10 + i).toString().padLeft(2, '0')}',
        ),
    ]);
    final counts = await ledger.earnedCounts();
    expect(counts[BadgeId.loyalty], 8);
    expect(await ledger.pendingCount(), 8);
  });

  test('does not invent tournament-only awards', () async {
    await recordPractice('p-1', '2026-11-20');
    final counts = await ledger.earnedCounts();
    expect(counts[BadgeId.onTime], 0);
    expect(counts[BadgeId.champion], 0);
    expect(counts[BadgeId.tournamentGuru], 0);
    expect(counts[BadgeId.risingStar], 0);
  });
}
