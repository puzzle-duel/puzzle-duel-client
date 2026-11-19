import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/tournament/practice_identity.dart';
import 'package:puzzle_duel_mobile/tournament/practice_store.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('pzd43-identity');
  });

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  test('rejects display names and invalid identifiers as scopes', () {
    expect(PracticeIdentityScope.tryParseStorageKey('alice'), isNull);
    expect(PracticeIdentityScope.tryParseStorageKey('guest'), isNull);
    expect(
      PracticeIdentityScope.tryParseStorageKey('player_not-a-uuid'),
      isNull,
    );
    expect(PracticeIdentityScope.tryParseStorageKey('guest_'), isNull);
    expect(
      PracticeIdentityScope.tryParseStorageKey('guest_${'a' * 200}'),
      isNull,
    );
    expect(PracticeIdentityScope.tryPlayer('Player A'), isNull);
  });

  test('persists a random guest id and never uses labels', () async {
    final identity = PracticeIdentityStore(directory, random: Random(1));
    await identity.load();
    expect(
      PracticeIdentityScope.uuidPattern.hasMatch(identity.guestLocalId),
      isTrue,
    );
    expect(identity.activeScope.kind, PracticeIdentityKind.guest);
    expect(identity.activeScope.storageKey.startsWith('guest_'), isTrue);

    final reloaded = PracticeIdentityStore(directory, random: Random(2));
    await reloaded.load();
    expect(reloaded.guestLocalId, identity.guestLocalId);
  });

  test(
    'authenticated bind uses server player id and does not merge guest',
    () async {
      final identity = PracticeIdentityStore(directory, random: Random(3));
      await identity.load();
      final guestStore = PracticeStore(
        directory: directory,
        scope: identity.activeScope,
        identity: identity,
      );
      await guestStore.append(
        PracticeRecord(
          sessionId: 'g1',
          difficulty: 'easy',
          rulesVersion: 'core-001.v2',
          generatorVersion: 'gen-001.v1',
          seed: 1,
          score: 55,
          terminalReason: 'ended',
          completedAt: '2026-11-19T00:00:00.000Z',
        ),
      );

      const playerId = '11111111-1111-4111-8111-111111111111';
      expect(await identity.bindAuthenticatedPlayer(playerId), isTrue);
      expect(identity.activeScope.storageKey, 'player_$playerId');

      final playerStore = PracticeStore(
        directory: directory,
        scope: identity.activeScope,
        identity: identity,
      );
      expect(await playerStore.load(), isEmpty);
      expect(
        await playerStore.bestScore(
          'easy',
          rulesVersion: 'core-001.v2',
          generatorVersion: 'gen-001.v1',
        ),
        isNull,
      );

      await identity.clearAuthenticatedPlayer();
      final guestAgain = PracticeStore(
        directory: directory,
        scope: identity.activeScope,
        identity: identity,
      );
      expect((await guestAgain.load()).single.score, 55);
    },
  );

  test(
    'two authenticated players stay isolated after switch and restart',
    () async {
      final identity = PracticeIdentityStore(directory, random: Random(4));
      await identity.load();
      const alice = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
      const bob = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

      await identity.bindAuthenticatedPlayer(alice);
      await PracticeStore(
        directory: directory,
        scope: identity.activeScope,
        identity: identity,
      ).append(
        PracticeRecord(
          sessionId: 'a1',
          difficulty: 'hard',
          rulesVersion: 'core-001.v2',
          generatorVersion: 'gen-001.v1',
          seed: 1,
          score: 90,
          terminalReason: 'ended',
          completedAt: '2026-11-19T00:00:00.000Z',
        ),
      );

      await identity.bindAuthenticatedPlayer(bob);
      final bobStore = PracticeStore(
        directory: directory,
        scope: identity.activeScope,
        identity: identity,
      );
      expect(await bobStore.load(), isEmpty);
      await bobStore.append(
        PracticeRecord(
          sessionId: 'b1',
          difficulty: 'hard',
          rulesVersion: 'core-001.v2',
          generatorVersion: 'gen-001.v1',
          seed: 2,
          score: 11,
          terminalReason: 'ended',
          completedAt: '2026-11-19T00:00:00.000Z',
        ),
      );

      final restarted = PracticeIdentityStore(directory, random: Random(5));
      await restarted.load();
      // Restart keeps the last authenticated binding until explicit logout.
      expect(restarted.isAuthenticated, isTrue);
      expect(restarted.activePlayerId, bob);
      expect(
        (await PracticeStore(
          directory: directory,
          scope: restarted.activeScope,
          identity: restarted,
        ).load()).single.score,
        11,
      );

      await restarted.clearAuthenticatedPlayer();
      expect(restarted.isAuthenticated, isFalse);
      expect(
        await PracticeStore(
          directory: directory,
          scope: restarted.activeScope,
          identity: restarted,
        ).load(),
        isEmpty,
      );

      await restarted.bindAuthenticatedPlayer(alice);
      expect(
        (await PracticeStore(
          directory: directory,
          scope: restarted.activeScope,
          identity: restarted,
        ).load()).single.score,
        90,
      );
    },
  );

  test('same display name cannot collide scopes; label legacy migrates only to guest', () async {
    File('${directory.path}/practice-records-Player A.json').writeAsStringSync(
      '[{"sessionId":"legacy","difficulty":"easy","rulesVersion":"core-001.v2",'
      '"generatorVersion":"gen-001.v1","seed":1,"score":33,'
      '"terminalReason":"ended","completedAt":"2026-11-01T00:00:00.000Z","verifiedRank":false}]',
    );
    final identity = PracticeIdentityStore(directory, random: Random(6));
    await identity.load();
    final guest = PracticeStore(
      directory: directory,
      scope: identity.activeScope,
      identity: identity,
    );
    expect((await guest.load()).single.score, 33);

    const playerId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
    await identity.bindAuthenticatedPlayer(playerId);
    final player = PracticeStore(
      directory: directory,
      scope: identity.activeScope,
      identity: identity,
    );
    expect(await player.load(), isEmpty);
  });
}
