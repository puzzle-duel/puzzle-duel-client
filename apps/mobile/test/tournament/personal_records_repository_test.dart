import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/tournament/guest_auth.dart';
import 'package:puzzle_duel_mobile/tournament/local_kv_store.dart';
import 'package:puzzle_duel_mobile/tournament/personal_records_repository.dart';
import 'package:puzzle_duel_mobile/tournament/practice_identity.dart';
import 'package:puzzle_duel_mobile/tournament/practice_store.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';

final class _MemStore implements GuestCredentialStore {
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<void> writeRefreshToken(String token) async {}
  @override
  Future<void> clearRefreshToken() async {}
  @override
  Future<String?> readPendingRotationId() async => null;
  @override
  Future<void> writePendingRotationId(String id) async {}
  @override
  Future<void> clearPendingRotationId() async {}
  @override
  Future<String?> readPendingLinkProvider() async => null;
  @override
  Future<void> writePendingLinkProvider(String encoded) async {}
  @override
  Future<void> clearPendingLinkProvider() async {}
  @override
  Future<String?> readIdentityBinding() async => null;
  @override
  Future<void> writeIdentityBinding(String encoded) async {}
  @override
  Future<void> clearIdentityBinding() async {}
  @override
  Future<String?> readVaultJournal() async => null;
  @override
  Future<void> writeVaultJournal(String encoded) async {}
  @override
  Future<void> clearVaultJournal() async {}
}

final class _OriginScriptedApi extends UatApi {
  _OriginScriptedApi(this._onRequest)
    : super(baseUrl: 'https://staging.test', bearer: 'Bearer test');

  final Future<UatHttpResult> Function(String method, String path, Object? body)
  _onRequest;

  @override
  Future<UatHttpResult> get(String path) => _onRequest('GET', path, null);

  @override
  Future<UatHttpResult> post(String path, [Object? body]) =>
      _onRequest('POST', path, body);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const playerA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const playerB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  const origin = 'https://staging.test';

  String verifiedJwt(String playerId) {
    final header = base64Url.encode(utf8.encode('{"alg":"none"}'));
    final payload = base64Url.encode(
      utf8.encode(
        jsonEncode({
          'iss': 'https://staging.puzzle-duel.app',
          'aud': 'puzzle-duel-api',
          'sub': playerId,
          'account_type': 'verified',
        }),
      ),
    );
    return '$header.$payload.sig';
  }

  late MemoryKvStore kv;
  late Directory directory;
  late PracticeIdentityStore identity;

  setUp(() async {
    kv = MemoryKvStore();
    directory = Directory.systemTemp.createTempSync('pzd53-records');
    identity = PracticeIdentityStore(directory);
    await identity.load();
    await identity.bindAuthenticatedPlayer(playerA);
  });

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  PracticeStore practiceStore() =>
      PracticeStore(store: kv, scope: identity.activeScope, identity: identity);

  PersonalRecordsRepository repo({
    required GuestAuthClient session,
    required UatApi api,
    Future<void> Function(Duration duration)? sleeper,
  }) {
    return PersonalRecordsRepository(
      kv: kv,
      api: api,
      sessionAuth: session,
      practiceStore: practiceStore,
      sleeper: sleeper ?? (_) async {},
    );
  }

  GuestAuthClient verifiedSession(String playerId) {
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: _MemStore(),
    );
    session.debugSeedAccess(
      GuestAccess.parse(
        accessToken: verifiedJwt(playerId),
        expiresAt: DateTime.utc(2030),
      ),
    );
    return session;
  }

  PracticeRecord practiceRecord({
    required String sessionId,
    required int score,
    String difficulty = 'easy',
  }) {
    return PracticeRecord(
      sessionId: sessionId,
      difficulty: difficulty,
      rulesVersion: personalRecordsPracticeRules,
      generatorVersion: personalRecordsPracticeGenerator,
      seed: 1,
      score: score,
      terminalReason: 'ended',
      completedAt: '2026-11-20T00:00:00.000Z',
    );
  }

  test('deriveAllSegment picks max practice vs tournament with source', () {
    final practice = {
      'easy': PersonalRecordCardModel(
        difficulty: 'easy',
        score: 40,
        rulesVersion: personalRecordsPracticeRules,
        generatorVersion: personalRecordsPracticeGenerator,
        displaySource: PersonalRecordDisplaySource.practice,
      ),
      'medium': null,
      'hard': null,
    };
    final tournament = {
      'easy': PersonalRecordCardModel(
        difficulty: 'easy',
        score: 55,
        rulesVersion: personalRecordsTournamentRules,
        generatorVersion: personalRecordsTournamentGenerator,
        displaySource: PersonalRecordDisplaySource.tournament,
      ),
      'medium': PersonalRecordCardModel(
        difficulty: 'medium',
        score: 12,
        rulesVersion: personalRecordsTournamentRules,
        generatorVersion: personalRecordsTournamentGenerator,
        displaySource: PersonalRecordDisplaySource.tournament,
      ),
      'hard': null,
    };
    final all = PersonalRecordsRepository.deriveAllSegment(
      practice: practice,
      tournament: tournament,
    );
    expect(all['easy']!.score, 55);
    expect(all['easy']!.displaySource, PersonalRecordDisplaySource.tournament);
    expect(all['medium']!.score, 12);
    expect(all['hard'], isNull);
  });

  test(
    'pending ack clears only when remote meets score and revision matches',
    () async {
      final session = verifiedSession(playerA);
      final api = _OriginScriptedApi(
        (method, path, body) async =>
            const UatHttpResult(404, {'error': 'NOT_FOUND'}),
      );
      final repository = repo(session: session, api: api);
      final scopeKey = PersonalRecordsRepository.accountScopeKey(
        apiOrigin: origin,
        sessionAuth: session,
      )!;
      await repository.notifyLocalPracticeBest(
        record: practiceRecord(sessionId: 'p-new', score: 88),
        improved: true,
      );
      await repository.debugApplyAcknowledgement(
        scopeKey: scopeKey,
        difficulty: 'easy',
        localRevision: 1,
        remoteScore: 50,
      );
      var pending = await repository.loadViewModel();
      expect(pending.syncStatus, PersonalRecordsSyncStatus.pendingUpload);

      await repository.debugApplyAcknowledgement(
        scopeKey: scopeKey,
        difficulty: 'easy',
        localRevision: 1,
        remoteScore: 88,
      );
      pending = await repository.loadViewModel();
      expect(
        pending.syncStatus,
        isNot(PersonalRecordsSyncStatus.pendingUpload),
      );
    },
  );

  test('in-flight sync ack for PB 100 cannot clear durable PB 150', () async {
    final session = verifiedSession(playerA);
    final firstPostStarted = Completer<void>();
    final releaseFirstPost = Completer<UatHttpResult>();
    final secondPostStarted = Completer<void>();
    final releaseSecondPost = Completer<UatHttpResult>();
    var postCount = 0;
    Object? firstPostBody;
    Object? secondPostBody;

    final api = _OriginScriptedApi((method, path, body) async {
      if (method == 'GET') {
        return const UatHttpResult(200, {
          'records': <Object>[],
          'schemaReady': true,
        });
      }
      if (method == 'POST' &&
          path.endsWith('/personal-records/practice/sync')) {
        postCount += 1;
        if (postCount == 1) {
          firstPostBody = body;
          firstPostStarted.complete();
          return releaseFirstPost.future;
        }
        secondPostBody = body;
        if (!secondPostStarted.isCompleted) secondPostStarted.complete();
        return releaseSecondPost.future;
      }
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });

    final repository = repo(session: session, api: api);
    final scopeKey = PersonalRecordsRepository.accountScopeKey(
      apiOrigin: origin,
      sessionAuth: session,
    )!;

    await repository.notifyLocalPracticeBest(
      record: practiceRecord(sessionId: 'p-100', score: 100),
      improved: true,
    );
    await firstPostStarted.future.timeout(const Duration(seconds: 2));

    await repository.notifyLocalPracticeBest(
      record: practiceRecord(sessionId: 'p-150', score: 150),
      improved: true,
    );

    final firstRecord =
        ((firstPostBody as Map)['records'] as List).first as Map;
    expect(firstRecord['score'], 100);
    releaseFirstPost.complete(
      UatHttpResult(200, {
        'schemaReady': true,
        'records': [
          {
            'difficulty': 'easy',
            'source': 'practice',
            'score': 100,
            'rulesVersion': personalRecordsPracticeRules,
            'generatorVersion': personalRecordsPracticeGenerator,
            'achievedAt': '2026-11-20T00:00:00.000Z',
            'provenance': 'client_reported_practice',
          },
        ],
        'acknowledgements': [
          {
            'difficulty': 'easy',
            'rulesVersion': personalRecordsPracticeRules,
            'generatorVersion': personalRecordsPracticeGenerator,
            'completionId': firstRecord['completionId'],
            'localRevision': firstRecord['localRevision'],
            'acceptedScore': 100,
            'remoteScore': 100,
            'improved': true,
          },
        ],
      }),
    );

    // Chained sync for 150 starts but stays blocked — pending must remain.
    await secondPostStarted.future.timeout(const Duration(seconds: 2));
    final pendingAfterAck = await repository.debugPendingScores(scopeKey);
    expect(pendingAfterAck['easy'], 150);
    final chained150 =
        ((secondPostBody as Map)['records'] as List).first as Map;
    expect(chained150['score'], 150);

    // Process restart: fence abandons in-flight chain; durable pending survives.
    repository.fenceSync();
    // Unblock abandoned request so it cannot hang the test isolate.
    releaseSecondPost.complete(const UatHttpResult(0, {'error': 'ABANDONED'}));

    Object? restartBody;
    final restartApi = _OriginScriptedApi((method, path, body) async {
      if (method == 'GET') {
        return const UatHttpResult(200, {
          'records': <Object>[],
          'schemaReady': true,
        });
      }
      if (method == 'POST') {
        restartBody = body;
        final record = ((body as Map)['records'] as List).first as Map;
        expect(record['score'], 150);
        return UatHttpResult(200, {
          'schemaReady': true,
          'records': [
            {
              'difficulty': 'easy',
              'source': 'practice',
              'score': 150,
              'rulesVersion': personalRecordsPracticeRules,
              'generatorVersion': personalRecordsPracticeGenerator,
              'achievedAt': '2026-11-20T00:00:00.000Z',
              'provenance': 'client_reported_practice',
            },
          ],
          'acknowledgements': [
            {
              'difficulty': 'easy',
              'rulesVersion': personalRecordsPracticeRules,
              'generatorVersion': personalRecordsPracticeGenerator,
              'completionId': record['completionId'],
              'localRevision': record['localRevision'],
              'acceptedScore': 150,
              'remoteScore': 150,
              'improved': true,
            },
          ],
        });
      }
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });

    final restarted = repo(session: session, api: restartApi);
    final pendingAfterRestart = await restarted.debugPendingScores(scopeKey);
    expect(pendingAfterRestart['easy'], 150);

    await restarted.scheduleSyncIfNeeded();
    expect(restartBody, isNotNull);
    final cleared = await restarted.debugPendingScores(scopeKey);
    expect(cleared.containsKey('easy'), isFalse);
    final view = await restarted.loadViewModel();
    expect(view.practice['easy']!.score, 150);
    expect(postCount, greaterThanOrEqualTo(2));
  });

  test('A to B while POST in flight discards stale ack for A', () async {
    final session = verifiedSession(playerA);
    final syncStarted = Completer<void>();
    final releaseSync = Completer<UatHttpResult>();
    var appliedForB = false;

    final api = _OriginScriptedApi((method, path, body) async {
      if (method == 'GET') {
        return const UatHttpResult(200, {
          'records': <Object>[],
          'schemaReady': true,
        });
      }
      if (method == 'POST') {
        syncStarted.complete();
        return releaseSync.future;
      }
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });

    final repository = repo(session: session, api: api);
    final scopeA = PersonalRecordsRepository.accountScopeKey(
      apiOrigin: origin,
      sessionAuth: session,
    )!;
    await repository.notifyLocalPracticeBest(
      record: practiceRecord(sessionId: 'a-only', score: 77),
      improved: true,
    );
    await syncStarted.future.timeout(const Duration(seconds: 2));

    repository.fenceSync();
    session.debugSeedAccess(
      GuestAccess.parse(
        accessToken: verifiedJwt(playerB),
        expiresAt: DateTime.utc(2030),
      ),
    );
    await identity.bindAuthenticatedPlayer(playerB);

    releaseSync.complete(
      const UatHttpResult(200, {
        'schemaReady': true,
        'records': [
          {
            'difficulty': 'easy',
            'source': 'practice',
            'score': 77,
            'rulesVersion': personalRecordsPracticeRules,
            'generatorVersion': personalRecordsPracticeGenerator,
            'achievedAt': '2026-11-20T00:00:00.000Z',
          },
        ],
        'acknowledgements': [
          {
            'difficulty': 'easy',
            'localRevision': 1,
            'acceptedScore': 77,
            'remoteScore': 77,
            'rulesVersion': personalRecordsPracticeRules,
            'generatorVersion': personalRecordsPracticeGenerator,
          },
        ],
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // A's pending must remain durable under A's scope.
    final pendingA = await repository.debugPendingScores(scopeA);
    expect(pendingA['easy'], 77);

    final viewB = await repository.loadViewModel();
    expect(viewB.practice['easy'], isNull);
    appliedForB = viewB.practice['easy'] != null;
    expect(appliedForB, isFalse);
  });

  test('A to B while GET in flight cannot publish A remote into B', () async {
    final session = verifiedSession(playerA);
    final getStarted = Completer<void>();
    final releaseGet = Completer<UatHttpResult>();

    final api = _OriginScriptedApi((method, path, body) async {
      if (method == 'GET' && path.endsWith('/personal-records')) {
        getStarted.complete();
        return releaseGet.future;
      }
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });

    final repository = repo(session: session, api: api);
    final gen = repository.accountSyncGeneration;
    final refresh = repository.refreshRemote(expectedGeneration: gen);
    await getStarted.future.timeout(const Duration(seconds: 2));

    repository.fenceSync();
    session.debugSeedAccess(
      GuestAccess.parse(
        accessToken: verifiedJwt(playerB),
        expiresAt: DateTime.utc(2030),
      ),
    );
    await identity.bindAuthenticatedPlayer(playerB);

    releaseGet.complete(
      const UatHttpResult(200, {
        'schemaReady': true,
        'records': [
          {
            'difficulty': 'hard',
            'source': 'tournament',
            'score': 999,
            'rulesVersion': personalRecordsTournamentRules,
            'generatorVersion': personalRecordsTournamentGenerator,
            'achievedAt': '2026-11-20T00:00:00.000Z',
          },
        ],
      }),
    );
    await refresh;
    final viewB = await repository.loadViewModel();
    expect(viewB.tournament['hard'], isNull);
  });

  test(
    'logout during retry backoff does not resume with stale generation',
    () async {
      final session = verifiedSession(playerA);
      var posts = 0;
      final api = _OriginScriptedApi((method, path, body) async {
        if (method == 'POST') {
          posts += 1;
          return const UatHttpResult(0, {'error': 'OFFLINE'});
        }
        return const UatHttpResult(200, {
          'records': <Object>[],
          'schemaReady': true,
        });
      });
      final repository = repo(session: session, api: api);
      await repository.notifyLocalPracticeBest(
        record: practiceRecord(sessionId: 'retry', score: 40),
        improved: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      repository.fenceSync();
      session.debugSeedAccess(
        GuestAccess.parse(
          accessToken: verifiedJwt(playerB),
          expiresAt: DateTime.utc(2030),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final postsAfterFence = posts;
      await Future<void>.delayed(const Duration(milliseconds: 900));
      // No additional POST should be attributed to the fenced generation.
      expect(posts, postsAfterFence);
    },
  );

  test(
    'seedPendingFromLocalBests recovers PracticeStore after crash gap',
    () async {
      final session = verifiedSession(playerA);
      final api = _OriginScriptedApi(
        (method, path, body) async => const UatHttpResult(200, {
          'records': <Object>[],
          'schemaReady': true,
        }),
      );
      final store = practiceStore();
      final record = practiceRecord(sessionId: 'survived', score: 123);
      await store.append(record);
      // Simulate crash: PracticeStore has best, pending never written.
      final repository = repo(session: session, api: api);
      final scopeKey = PersonalRecordsRepository.accountScopeKey(
        apiOrigin: origin,
        sessionAuth: session,
      )!;
      expect(await repository.debugPendingScores(scopeKey), isEmpty);
      await repository.seedPendingFromLocalBests(
        scopeKey: scopeKey,
        expectedGeneration: repository.accountSyncGeneration,
      );
      expect(await repository.debugPendingScores(scopeKey), {'easy': 123});
    },
  );

  test('account isolation keeps pending under original player scope', () async {
    final session = verifiedSession(playerA);
    final api = UatApi(baseUrl: origin, bearer: 'Bearer x');
    final repository = PersonalRecordsRepository(
      kv: kv,
      api: api,
      sessionAuth: session,
      practiceStore: practiceStore,
      sleeper: (_) async {},
    );
    final scopeA = PersonalRecordsRepository.accountScopeKey(
      apiOrigin: origin,
      sessionAuth: session,
    )!;
    final record = practiceRecord(
      sessionId: 'only-a',
      score: 70,
      difficulty: 'hard',
    );
    await practiceStore().append(record);
    await repository.notifyLocalPracticeBest(record: record, improved: true);
    repository.fenceSync();
    session.debugSeedAccess(
      GuestAccess.parse(
        accessToken: verifiedJwt(playerB),
        expiresAt: DateTime.utc(2030),
      ),
    );
    await identity.bindAuthenticatedPlayer(playerB);
    final scopeB = PersonalRecordsRepository.accountScopeKey(
      apiOrigin: origin,
      sessionAuth: session,
    )!;
    expect(scopeA, isNot(scopeB));
    final viewB = await repository.loadViewModel();
    expect(viewB.practice['hard'], isNull);
    expect(await repository.debugPendingScores(scopeA), {'hard': 70});

    await identity.bindAuthenticatedPlayer(playerA);
    session.debugSeedAccess(
      GuestAccess.parse(
        accessToken: verifiedJwt(playerA),
        expiresAt: DateTime.utc(2030),
      ),
    );
    final viewA = await repository.loadViewModel();
    expect(viewA.practice['hard']?.score, 70);
  });

  test('persistent 503 does not storm scheduleSyncIfNeeded', () async {
    final session = verifiedSession(playerA);
    var posts = 0;
    final api = _OriginScriptedApi((method, path, body) async {
      if (method == 'POST') {
        posts += 1;
        return const UatHttpResult(503, {'error': 'SCHEMA_NOT_READY'});
      }
      return const UatHttpResult(200, {
        'records': <Object>[],
        'schemaReady': true,
      });
    });
    final repository = repo(session: session, api: api);
    final scopeKey = PersonalRecordsRepository.accountScopeKey(
      apiOrigin: origin,
      sessionAuth: session,
    )!;
    await repository.notifyLocalPracticeBest(
      record: practiceRecord(sessionId: 's503', score: 11),
      improved: true,
    );
    await repository.scheduleSyncIfNeeded();
    await repository.scheduleSyncIfNeeded();
    await repository.scheduleSyncIfNeeded();
    expect(posts, 1);
    expect(
      repository.debugLastSyncOutcome,
      PersonalRecordsSyncOutcome.schemaNotReady,
    );
    expect(await repository.debugPendingScores(scopeKey), {'easy': 11});
  });

  test('persistent 401/403 does not immediately retry-loop', () async {
    final session = verifiedSession(playerA);
    var posts = 0;
    final api = _OriginScriptedApi((method, path, body) async {
      if (method == 'POST') {
        posts += 1;
        return const UatHttpResult(401, {'error': 'UNAUTHORIZED'});
      }
      return const UatHttpResult(200, {
        'records': <Object>[],
        'schemaReady': true,
      });
    });
    final repository = repo(session: session, api: api);
    final scopeKey = PersonalRecordsRepository.accountScopeKey(
      apiOrigin: origin,
      sessionAuth: session,
    )!;
    await repository.notifyLocalPracticeBest(
      record: practiceRecord(sessionId: 's401', score: 22),
      improved: true,
    );
    await Future<void>.delayed(Duration.zero);
    await repository.scheduleSyncIfNeeded();
    await repository.scheduleSyncIfNeeded();
    expect(posts, 1);
    expect(
      repository.debugLastSyncOutcome,
      PersonalRecordsSyncOutcome.unauthorized,
    );
    expect(await repository.debugPendingScores(scopeKey), {'easy': 22});

    posts = 0;
    final forbiddenApi = _OriginScriptedApi((method, path, body) async {
      if (method == 'POST') {
        posts += 1;
        return const UatHttpResult(403, {'error': 'FORBIDDEN'});
      }
      return const UatHttpResult(200, {
        'records': <Object>[],
        'schemaReady': true,
      });
    });
    final forbiddenRepo = repo(session: session, api: forbiddenApi);
    await forbiddenRepo.notifyLocalPracticeBest(
      record: practiceRecord(sessionId: 's403', score: 23),
      improved: true,
    );
    await Future<void>.delayed(Duration.zero);
    await forbiddenRepo.scheduleSyncIfNeeded();
    expect(posts, 1);
    expect(
      forbiddenRepo.debugLastSyncOutcome,
      PersonalRecordsSyncOutcome.unauthorized,
    );
  });

  test('persistent offline/500 exhausts bounded retry budget', () async {
    final session = verifiedSession(playerA);
    var posts = 0;
    final api = _OriginScriptedApi((method, path, body) async {
      if (method == 'POST') {
        posts += 1;
        return posts.isOdd
            ? const UatHttpResult(0, {'error': 'OFFLINE'})
            : const UatHttpResult(500, {'error': 'SERVER'});
      }
      return const UatHttpResult(200, {
        'records': <Object>[],
        'schemaReady': true,
      });
    });
    final repository = repo(session: session, api: api);
    final scopeKey = PersonalRecordsRepository.accountScopeKey(
      apiOrigin: origin,
      sessionAuth: session,
    )!;
    await repository.notifyLocalPracticeBest(
      record: practiceRecord(sessionId: 'sbudget', score: 33),
      improved: true,
    );
    await repository.scheduleSyncIfNeeded();
    await repository.scheduleSyncIfNeeded();
    expect(posts, 4);
    expect(
      repository.debugLastSyncOutcome,
      PersonalRecordsSyncOutcome.retryExhausted,
    );
    expect(await repository.debugPendingScores(scopeKey), {'easy': 33});
  });

  test(
    'successful response without acknowledgement progress does not loop',
    () async {
      final session = verifiedSession(playerA);
      var posts = 0;
      final api = _OriginScriptedApi((method, path, body) async {
        if (method == 'POST') {
          posts += 1;
          return const UatHttpResult(200, {
            'schemaReady': true,
            'records': <Object>[],
            'acknowledgements': <Object>[],
          });
        }
        return const UatHttpResult(200, {
          'records': <Object>[],
          'schemaReady': true,
        });
      });
      final repository = repo(session: session, api: api);
      final scopeKey = PersonalRecordsRepository.accountScopeKey(
        apiOrigin: origin,
        sessionAuth: session,
      )!;
      await repository.notifyLocalPracticeBest(
        record: practiceRecord(sessionId: 'noprogress', score: 44),
        improved: true,
      );
      await repository.scheduleSyncIfNeeded();
      await repository.scheduleSyncIfNeeded();
      expect(posts, 1);
      expect(
        repository.debugLastSyncOutcome,
        PersonalRecordsSyncOutcome.noProgress,
      );
      expect(await repository.debugPendingScores(scopeKey), {'easy': 44});
    },
  );

  test(
    'PB 150 arriving during successful PB 100 sync automatically uploads',
    () async {
      final session = verifiedSession(playerA);
      final firstPostStarted = Completer<void>();
      final releaseFirstPost = Completer<UatHttpResult>();
      final postedScores = <int>[];
      var postCount = 0;

      final api = _OriginScriptedApi((method, path, body) async {
        if (method == 'GET') {
          return const UatHttpResult(200, {
            'records': <Object>[],
            'schemaReady': true,
          });
        }
        if (method == 'POST') {
          postCount += 1;
          final record = ((body as Map)['records'] as List).first as Map;
          final score = (record['score'] as num).toInt();
          postedScores.add(score);
          if (postCount == 1) {
            firstPostStarted.complete();
            return releaseFirstPost.future;
          }
          return UatHttpResult(200, {
            'schemaReady': true,
            'records': [
              {
                'difficulty': 'easy',
                'source': 'practice',
                'score': score,
                'rulesVersion': personalRecordsPracticeRules,
                'generatorVersion': personalRecordsPracticeGenerator,
                'achievedAt': '2026-11-20T00:00:00.000Z',
              },
            ],
            'acknowledgements': [
              {
                'difficulty': 'easy',
                'rulesVersion': personalRecordsPracticeRules,
                'generatorVersion': personalRecordsPracticeGenerator,
                'completionId': record['completionId'],
                'localRevision': record['localRevision'],
                'acceptedScore': score,
                'remoteScore': score,
                'improved': true,
              },
            ],
          });
        }
        return const UatHttpResult(404, {'error': 'NOT_FOUND'});
      });

      final repository = repo(session: session, api: api);
      final scopeKey = PersonalRecordsRepository.accountScopeKey(
        apiOrigin: origin,
        sessionAuth: session,
      )!;

      await repository.notifyLocalPracticeBest(
        record: practiceRecord(sessionId: 'p-100b', score: 100),
        improved: true,
      );
      await firstPostStarted.future.timeout(const Duration(seconds: 2));
      await repository.notifyLocalPracticeBest(
        record: practiceRecord(sessionId: 'p-150b', score: 150),
        improved: true,
      );

      final firstRecordScore = postedScores.first;
      expect(firstRecordScore, 100);
      releaseFirstPost.complete(
        UatHttpResult(200, {
          'schemaReady': true,
          'records': [
            {
              'difficulty': 'easy',
              'source': 'practice',
              'score': 100,
              'rulesVersion': personalRecordsPracticeRules,
              'generatorVersion': personalRecordsPracticeGenerator,
              'achievedAt': '2026-11-20T00:00:00.000Z',
            },
          ],
          'acknowledgements': [
            {
              'difficulty': 'easy',
              'rulesVersion': personalRecordsPracticeRules,
              'generatorVersion': personalRecordsPracticeGenerator,
              'completionId': 'p-100b',
              'localRevision': 1,
              'acceptedScore': 100,
              'remoteScore': 100,
              'improved': true,
            },
          ],
        }),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(postedScores, containsAll([100, 150]));
      expect(await repository.debugPendingScores(scopeKey), isEmpty);
    },
  );

  test(
    'connectivity restored eventually synchronizes durable pending',
    () async {
      final session = verifiedSession(playerA);
      var online = false;
      var posts = 0;
      final api = _OriginScriptedApi((method, path, body) async {
        if (method == 'POST') {
          posts += 1;
          if (!online) {
            return const UatHttpResult(0, {'error': 'OFFLINE'});
          }
          final record = ((body as Map)['records'] as List).first as Map;
          return UatHttpResult(200, {
            'schemaReady': true,
            'records': [
              {
                'difficulty': 'easy',
                'source': 'practice',
                'score': record['score'],
                'rulesVersion': personalRecordsPracticeRules,
                'generatorVersion': personalRecordsPracticeGenerator,
                'achievedAt': '2026-11-20T00:00:00.000Z',
              },
            ],
            'acknowledgements': [
              {
                'difficulty': 'easy',
                'rulesVersion': personalRecordsPracticeRules,
                'generatorVersion': personalRecordsPracticeGenerator,
                'completionId': record['completionId'],
                'localRevision': record['localRevision'],
                'acceptedScore': record['score'],
                'remoteScore': record['score'],
                'improved': true,
              },
            ],
          });
        }
        return const UatHttpResult(200, {
          'records': <Object>[],
          'schemaReady': true,
        });
      });
      final repository = repo(session: session, api: api);
      final scopeKey = PersonalRecordsRepository.accountScopeKey(
        apiOrigin: origin,
        sessionAuth: session,
      )!;
      await repository.notifyLocalPracticeBest(
        record: practiceRecord(sessionId: 'offline-then-on', score: 55),
        improved: true,
      );
      await repository.scheduleSyncIfNeeded();
      expect(posts, 4);
      expect(await repository.debugPendingScores(scopeKey), {'easy': 55});

      online = true;
      posts = 0;
      await repository.refreshAndSync(
        expectedGeneration: repository.accountSyncGeneration,
      );
      expect(posts, 1);
      expect(await repository.debugPendingScores(scopeKey), isEmpty);
    },
  );

  test('logout/account switch stops stale retries', () async {
    final session = verifiedSession(playerA);
    var posts = 0;
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<UatHttpResult>();
    final api = _OriginScriptedApi((method, path, body) async {
      if (method == 'POST') {
        posts += 1;
        if (posts == 1) {
          firstStarted.complete();
          return releaseFirst.future;
        }
        return const UatHttpResult(0, {'error': 'OFFLINE'});
      }
      return const UatHttpResult(200, {
        'records': <Object>[],
        'schemaReady': true,
      });
    });
    final repository = repo(session: session, api: api);
    final scopeA = PersonalRecordsRepository.accountScopeKey(
      apiOrigin: origin,
      sessionAuth: session,
    )!;
    await repository.notifyLocalPracticeBest(
      record: practiceRecord(sessionId: 'stale-stop', score: 66),
      improved: true,
    );
    await firstStarted.future.timeout(const Duration(seconds: 2));
    repository.fenceSync();
    session.debugSeedAccess(
      GuestAccess.parse(
        accessToken: verifiedJwt(playerB),
        expiresAt: DateTime.utc(2030),
      ),
    );
    releaseFirst.complete(const UatHttpResult(0, {'error': 'OFFLINE'}));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final postsAfterFence = posts;
    await repository.scheduleSyncIfNeeded();
    expect(posts, postsAfterFence);
    expect(await repository.debugPendingScores(scopeA), {'easy': 66});
  });

  test(
    'tournament cards and remote keys respect rules/generator versions',
    () async {
      final session = verifiedSession(playerA);
      final api = _OriginScriptedApi((method, path, body) async {
        if (method == 'GET') {
          return const UatHttpResult(200, {
            'schemaReady': true,
            'records': [
              {
                'difficulty': 'easy',
                'source': 'tournament',
                'score': 10,
                'rulesVersion': 'core-001.v2',
                'generatorVersion': personalRecordsTournamentGenerator,
                'achievedAt': '2026-11-20T00:00:00.000Z',
              },
              {
                'difficulty': 'easy',
                'source': 'tournament',
                'score': 90,
                'rulesVersion': personalRecordsTournamentRules,
                'generatorVersion': personalRecordsTournamentGenerator,
                'achievedAt': '2026-11-21T00:00:00.000Z',
              },
              {
                'difficulty': 'easy',
                'source': 'tournament',
                'score': 999,
                'rulesVersion': personalRecordsTournamentRules,
                'generatorVersion': 'gen-other.v9',
                'achievedAt': '2026-11-22T00:00:00.000Z',
              },
            ],
          });
        }
        return const UatHttpResult(404, {'error': 'NOT_FOUND'});
      });
      final repository = repo(session: session, api: api);
      final scopeA = PersonalRecordsRepository.accountScopeKey(
        apiOrigin: origin,
        sessionAuth: session,
      )!;
      final scopeB = PersonalRecordsRepository.accountScopeKey(
        apiOrigin: origin,
        sessionAuth: verifiedSession(playerB),
      )!;
      expect(scopeA.contains(playerA), isTrue);
      expect(scopeB.contains(playerB), isTrue);
      expect(scopeA, isNot(scopeB));

      await repository.refreshRemote(
        expectedGeneration: repository.accountSyncGeneration,
      );
      final view = await repository.loadViewModel();
      expect(view.tournament['easy']?.score, 90);
      expect(
        view.tournament['easy']?.rulesVersion,
        personalRecordsTournamentRules,
      );
      expect(
        view.tournament['easy']?.generatorVersion,
        personalRecordsTournamentGenerator,
      );
    },
  );
}
