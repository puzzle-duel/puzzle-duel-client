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

  final Future<UatHttpResult> Function(
    String method,
    String path,
    Object? body,
  ) _onRequest;

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
    final payload = base64Url.encode(utf8.encode(jsonEncode({
      'iss': 'https://staging.puzzle-duel.app',
      'aud': 'puzzle-duel-api',
      'sub': playerId,
      'account_type': 'verified',
    })));
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

  PracticeStore practiceStore() => PracticeStore(
    store: kv,
    scope: identity.activeScope,
    identity: identity,
  );

  PersonalRecordsRepository repo({
    required GuestAuthClient session,
    required UatApi api,
  }) {
    return PersonalRecordsRepository(
      kv: kv,
      api: api,
      sessionAuth: session,
      practiceStore: practiceStore,
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

  test('pending ack clears only when remote meets score and revision matches',
      () async {
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: _MemStore(),
    );
    session.debugSeedAccess(GuestAccess.parse(
      accessToken: verifiedJwt(playerA),
      expiresAt: DateTime.utc(2030),
    ));
    final api = _OriginScriptedApi(
      (_, __, ___) async => const UatHttpResult(404, {'error': 'NOT_FOUND'}),
    );
    final repository = repo(session: session, api: api);
    final scopeKey = PersonalRecordsRepository.accountScopeKey(
      apiOrigin: origin,
      sessionAuth: session,
    )!;
    final record = PracticeRecord(
      sessionId: 'p-new',
      difficulty: 'easy',
      rulesVersion: personalRecordsPracticeRules,
      generatorVersion: personalRecordsPracticeGenerator,
      seed: 1,
      score: 88,
      terminalReason: 'ended',
      completedAt: '2026-11-20T00:00:00.000Z',
    );
    await repository.notifyLocalPracticeBest(record: record, improved: true);
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
    expect(pending.syncStatus, isNot(PersonalRecordsSyncStatus.pendingUpload));
  });

  test('older ack must not clear newer pending revision', () async {
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: _MemStore(),
    );
    session.debugSeedAccess(GuestAccess.parse(
      accessToken: verifiedJwt(playerA),
      expiresAt: DateTime.utc(2030),
    ));
    final api = _OriginScriptedApi(
      (_, __, ___) async => const UatHttpResult(404, {'error': 'NOT_FOUND'}),
    );
    final repository = repo(session: session, api: api);
    final scopeKey = PersonalRecordsRepository.accountScopeKey(
      apiOrigin: origin,
      sessionAuth: session,
    )!;
    await repository.notifyLocalPracticeBest(
      record: PracticeRecord(
        sessionId: 'p1',
        difficulty: 'easy',
        rulesVersion: personalRecordsPracticeRules,
        generatorVersion: personalRecordsPracticeGenerator,
        seed: 1,
        score: 40,
        terminalReason: 'ended',
        completedAt: '2026-11-20T00:00:00.000Z',
      ),
      improved: true,
    );
    await repository.notifyLocalPracticeBest(
      record: PracticeRecord(
        sessionId: 'p2',
        difficulty: 'easy',
        rulesVersion: personalRecordsPracticeRules,
        generatorVersion: personalRecordsPracticeGenerator,
        seed: 2,
        score: 90,
        terminalReason: 'ended',
        completedAt: '2026-11-21T00:00:00.000Z',
      ),
      improved: true,
    );
    await repository.debugApplyAcknowledgement(
      scopeKey: scopeKey,
      difficulty: 'easy',
      localRevision: 1,
      remoteScore: 90,
    );
    final view = await repository.loadViewModel();
    expect(view.practice['easy']!.score, 90);
  });

  test('account isolation keeps pending under original player scope', () async {
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: _MemStore(),
    );
    session.debugSeedAccess(GuestAccess.parse(
      accessToken: verifiedJwt(playerA),
      expiresAt: DateTime.utc(2030),
    ));
    final api = UatApi(baseUrl: origin, bearer: 'Bearer x');
    final repository = PersonalRecordsRepository(
      kv: kv,
      api: api,
      sessionAuth: session,
      practiceStore: practiceStore,
    );
    final scopeA = PersonalRecordsRepository.accountScopeKey(
      apiOrigin: origin,
      sessionAuth: session,
    )!;
    final record = PracticeRecord(
      sessionId: 'only-a',
      difficulty: 'hard',
      rulesVersion: personalRecordsPracticeRules,
      generatorVersion: personalRecordsPracticeGenerator,
      seed: 1,
      score: 70,
      terminalReason: 'ended',
      completedAt: '2026-11-20T00:00:00.000Z',
    );
    await practiceStore().append(record);
    await repository.notifyLocalPracticeBest(record: record, improved: true);
    repository.fenceSync();
    session.debugSeedAccess(GuestAccess.parse(
      accessToken: verifiedJwt(playerB),
      expiresAt: DateTime.utc(2030),
    ));
    await identity.bindAuthenticatedPlayer(playerB);
    final scopeB = PersonalRecordsRepository.accountScopeKey(
      apiOrigin: origin,
      sessionAuth: session,
    )!;
    expect(scopeA, isNot(scopeB));
    final viewB = await repository.loadViewModel();
    expect(viewB.practice['hard'], isNull);

    await identity.bindAuthenticatedPlayer(playerA);
    session.debugSeedAccess(GuestAccess.parse(
      accessToken: verifiedJwt(playerA),
      expiresAt: DateTime.utc(2030),
    ));
    final viewA = await repository.loadViewModel();
    expect(viewA.practice['hard']?.score, 70);
  });
}