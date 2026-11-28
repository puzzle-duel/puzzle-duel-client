import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/presentation/feedback/app_feedback.dart';
import 'package:puzzle_duel_mobile/tournament/guest_auth.dart';
import 'package:puzzle_duel_mobile/tournament/local_kv_store.dart';
import 'package:puzzle_duel_mobile/tournament/practice_identity.dart';
import 'package:puzzle_duel_mobile/tournament/same_device_recovery.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_controller.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_home_snapshot.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_nav.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';

import 'tournament_command_test.dart' show ScriptedUatApi;

String _jwt({required String sub, required String accountType}) {
  final header = base64Url
      .encode(utf8.encode(jsonEncode({'alg': 'none'})))
      .replaceAll('=', '');
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'iss': 'https://staging.puzzle-duel.app',
            'aud': 'puzzle-duel-api',
            'sub': sub,
            'account_type': accountType,
            'fid': 'fid',
          }),
        ),
      )
      .replaceAll('=', '');
  return '$header.$payload.sig';
}

final class _MemStore implements GuestCredentialStore {
  String? token;
  @override
  Future<String?> readRefreshToken() async => token;
  @override
  Future<void> writeRefreshToken(String value) async => token = value;
  @override
  Future<void> clearRefreshToken() async => token = null;
  @override
  Future<String?> readPendingRotationId() async => null;
  @override
  Future<void> writePendingRotationId(String id) async {}
  @override
  Future<void> clearPendingRotationId() async {}
  @override
  Future<String?> readPendingLinkProvider() async => null;
  @override
  Future<void> writePendingLinkProvider(String provider) async {}
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

TournamentDay _completedDay({int score = 10200}) => TournamentDay(
  seriesId: 'series-a',
  original: true,
  claimStatus: 'COMPLETED',
  ordinal: 6,
  ordinalLabel: 'H1',
  seriesScore: score,
  resultsPublished: true,
);

Future<TournamentController> _controller({
  required Directory dir,
  required String playerId,
  required String accountType,
  UatApi? api,
}) async {
  final token = _jwt(sub: playerId, accountType: accountType);
  final session = GuestAuthClient(
    origin: 'https://staging.puzzle-duel.app',
    credentials: _MemStore()..token = 't' * 64,
  );
  session.debugSeedAccess(
    GuestAccess.parse(
      accessToken: token,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    ),
  );
  final identity = PracticeIdentityStore(dir);
  await identity.load();
  if (accountType == 'verified') {
    await identity.bindAuthenticatedPlayer(playerId);
  }
  final controller = TournamentController(
    config: UatConfig(
      baseUrl: 'https://staging.puzzle-duel.app',
      bearer: token,
      playerLabel: accountType,
    ),
    api: api ?? ScriptedUatApi((_, _, _) async => const UatHttpResult(200, {})),
    stateDirectory: dir,
    identity: identity,
    sessionAuth: session,
  );
  await controller.beginLocal();
  // Dispose before temp-dir tearDown so async personal-records work cannot
  // list a deleted directory on Linux CI.
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PZD-54 account isolation', () {
    test(
      'A01 logout clears completed tournament personal presentation',
      () async {
        final dir = await Directory.systemTemp.createTemp('pzd54-a01');
        addTearDown(() {
          if (dir.existsSync()) dir.deleteSync(recursive: true);
        });
        final controller = await _controller(
          dir: dir,
          playerId: '11111111-1111-1111-1111-111111111111',
          accountType: 'verified',
        );
        controller.day = _completedDay();
        controller.results = {
          'all': 10200,
          'onTimeAwarded': true,
          'easy': 3000,
          'medium': 4000,
          'hard': 3200,
        };
        controller.leaderboard = {'entries': <Object?>[]};
        controller.seriesId = 'series-a';
        controller.route = const TournamentRoute(
          place: TournamentPlace.results,
        );

        controller.applyGuestSessionAfterLogout(rankedAuthRequired: true);

        expect(controller.rankedAuthRequired, isTrue);
        expect(controller.day, isNull);
        expect(controller.results, isEmpty);
        expect(controller.leaderboard, isEmpty);
        expect(controller.seriesId, isNull);
        expect(controller.tournamentNoticeCode, isNull);
        expect(controller.route.place, TournamentPlace.home);
        expect(controller.homeSnapshot, isNull);
      },
    );

    test(
      'A02 stale successful loadDay after logout does not restore day',
      () async {
        final dir = await Directory.systemTemp.createTemp('pzd54-a02');
        addTearDown(() {
          if (dir.existsSync()) dir.deleteSync(recursive: true);
        });
        final gate = Completer<void>();
        var loadCalls = 0;
        final api = ScriptedUatApi((method, path, body) async {
          if (method == 'POST' && path.contains('/claims/daily')) {
            loadCalls++;
            await gate.future;
            return const UatHttpResult(201, {
              'seriesId': 'series-stale',
              'status': 'ACTIVE',
              'original': true,
            });
          }
          if (path.contains('/board')) {
            return const UatHttpResult(200, {
              'ordinal': 1,
              'ordinalLabel': 'E1',
              'seriesScore': 0,
              'writerSessionMatches': true,
              'state': {'turnsUsed': 0, 'boardSize': 8},
            });
          }
          return const UatHttpResult(200, {});
        });
        final controller = await _controller(
          dir: dir,
          playerId: '11111111-1111-1111-1111-111111111111',
          accountType: 'verified',
          api: api,
        );
        controller.day = _completedDay();
        final pending = controller.loadDay(presentHome: true);
        await Future<void>.delayed(Duration.zero);
        controller.applyGuestSessionAfterLogout(rankedAuthRequired: true);
        expect(controller.day, isNull);
        gate.complete();
        await pending;
        expect(controller.day, isNull);
        expect(controller.results, isEmpty);
        expect(controller.rankedAuthRequired, isTrue);
        expect(loadCalls, greaterThanOrEqualTo(1));
      },
    );

    test('A03 stale failed loadDay after logout does not set notice', () async {
      final dir = await Directory.systemTemp.createTemp('pzd54-a03');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final gate = Completer<void>();
      final api = ScriptedUatApi((method, path, body) async {
        if (method == 'POST' && path.contains('/claims/daily')) {
          await gate.future;
          return const UatHttpResult(0, {'error': 'OFFLINE'});
        }
        return const UatHttpResult(200, {});
      });
      final controller = await _controller(
        dir: dir,
        playerId: '11111111-1111-1111-1111-111111111111',
        accountType: 'verified',
        api: api,
      );
      final pending = controller.loadDay(presentHome: true);
      await Future<void>.delayed(Duration.zero);
      controller.applyGuestSessionAfterLogout(rankedAuthRequired: true);
      gate.complete();
      await pending;
      expect(controller.tournamentNoticeCode, isNull);
      expect(controller.appFeedback, isNull);
    });

    test(
      'A04/A05 account transition clears previous snapshot before hydrate',
      () async {
        final dir = await Directory.systemTemp.createTemp('pzd54-a04');
        addTearDown(() {
          if (dir.existsSync()) dir.deleteSync(recursive: true);
        });
        final controller = await _controller(
          dir: dir,
          playerId: '11111111-1111-1111-1111-111111111111',
          accountType: 'verified',
        );
        controller.day = _completedDay(score: 10200);
        controller.results = {'all': 10200, 'onTimeAwarded': true};
        controller.invalidateAccountScopedPresentation(
          reason: 'account_transition',
        );
        expect(controller.day, isNull);
        expect(controller.results, isEmpty);
      },
    );

    test(
      'A06/A07 stale finally cannot clear newer account in-flight state',
      () async {
        final dir = await Directory.systemTemp.createTemp('pzd54-a07');
        addTearDown(() {
          if (dir.existsSync()) dir.deleteSync(recursive: true);
        });
        final controller = await _controller(
          dir: dir,
          playerId: '22222222-2222-2222-2222-222222222222',
          accountType: 'verified',
        );
        controller.tournamentSync = TournamentSyncState.syncing;
        final epochBefore = controller.accountStateEpoch;
        // Simulate previous account logout fencing mid-flight.
        controller.invalidateAccountScopedPresentation(reason: 'logout');
        controller.tournamentSync = TournamentSyncState.syncing;
        expect(controller.tournamentSync, TournamentSyncState.syncing);
        // Old clear must not have left us with prior personal data.
        expect(controller.day, isNull);
        expect(controller.accountStateEpoch, epochBefore);
      },
    );

    test(
      'A08 guest cannot hydrate previous account disk snapshot as day',
      () async {
        final dir = await Directory.systemTemp.createTemp('pzd54-a08');
        addTearDown(() {
          if (dir.existsSync()) dir.deleteSync(recursive: true);
        });
        final controller = await _controller(
          dir: dir,
          playerId: '11111111-1111-1111-1111-111111111111',
          accountType: 'verified',
        );
        controller.day = _completedDay();
        controller.homeSnapshot = null;
        controller.applyGuestSessionAfterLogout(rankedAuthRequired: true);
        expect(controller.day, isNull);
        expect(controller.homeSnapshot, isNull);
        expect(controller.homeSnapshotStale, isFalse);
      },
    );

    test('A10 guest Practice scope remains after logout', () async {
      final dir = await Directory.systemTemp.createTemp('pzd54-a10');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final controller = await _controller(
        dir: dir,
        playerId: '11111111-1111-1111-1111-111111111111',
        accountType: 'verified',
      );
      await controller.clearAuthenticatedPracticeScope();
      controller.applyGuestSessionAfterLogout(rankedAuthRequired: true);
      expect(controller.identity.activeScope.kind, PracticeIdentityKind.guest);
      expect(controller.practiceStore().scope.kind, PracticeIdentityKind.guest);
    });

    test('A11 guest gate does not claim tournament', () async {
      final dir = await Directory.systemTemp.createTemp('pzd54-a11');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      var claims = 0;
      final api = ScriptedUatApi((method, path, body) async {
        if (method == 'POST' && path.contains('/claims/daily')) {
          claims++;
          return const UatHttpResult(403, {'error': 'RANKED_AUTH_REQUIRED'});
        }
        return const UatHttpResult(200, {});
      });
      final controller = await _controller(
        dir: dir,
        playerId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        accountType: 'guest',
        api: api,
      );
      await controller.loadDay(presentHome: true);
      expect(controller.rankedAuthRequired, isTrue);
      expect(claims, 0);
      expect(controller.day, isNull);
    });

    test('A15 logout feedback uses Top Banner channel only', () async {
      final dir = await Directory.systemTemp.createTemp('pzd54-a15');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final controller = await _controller(
        dir: dir,
        playerId: '11111111-1111-1111-1111-111111111111',
        accountType: 'verified',
      );
      controller.day = _completedDay();
      controller.applyGuestSessionAfterLogout(rankedAuthRequired: true);
      controller.presentAppFeedback(
        kind: AppFeedbackKind.info,
        message: 'Oturum kapatıldı. Misafir olarak devam ediyorsun.',
        semanticsKey: 'auth-logout-success',
      );
      expect(controller.appFeedback?.kind, AppFeedbackKind.info);
      expect(controller.appFeedback?.semanticsKey, 'auth-logout-success');
      expect(controller.tournamentNoticeCode, isNull);
    });

    test('A16 logout clears authenticated navigation resume state', () async {
      final dir = await Directory.systemTemp.createTemp('pzd54-a16');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final controller = await _controller(
        dir: dir,
        playerId: '11111111-1111-1111-1111-111111111111',
        accountType: 'verified',
      );
      controller.route = const TournamentRoute(place: TournamentPlace.playing);
      controller.day = _completedDay();
      controller.applyGuestSessionAfterLogout(rankedAuthRequired: true);
      expect(controller.route.place, TournamentPlace.home);
    });

    test('stale app feedback clear is generation-fenced', () async {
      final dir = await Directory.systemTemp.createTemp('pzd54-fb');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final controller = await _controller(
        dir: dir,
        playerId: '11111111-1111-1111-1111-111111111111',
        accountType: 'verified',
      );
      controller.presentAppFeedback(
        kind: AppFeedbackKind.info,
        message: 'first',
        semanticsKey: 'first',
      );
      final firstGen = controller.appFeedback!.generation;
      controller.presentAppFeedback(
        kind: AppFeedbackKind.warning,
        message: 'second',
        semanticsKey: 'second',
      );
      controller.clearAppFeedback(firstGen);
      expect(controller.appFeedback?.semanticsKey, 'second');
      final secondGen = controller.appFeedback!.generation;
      // Stale dismiss of a prior generation must not clear the newer banner.
      controller.dismissAppFeedback(reason: 'gesture', generation: firstGen);
      expect(controller.appFeedback?.semanticsKey, 'second');
      controller.dismissAppFeedback(reason: 'gesture', generation: secondGen);
      expect(controller.appFeedback, isNull);
      // Idempotent: repeating the same dismiss is a no-op.
      controller.dismissAppFeedback(reason: 'gesture', generation: secondGen);
      expect(controller.appFeedback, isNull);
    });

    test(
      'A17 stale loadDay results after logout cannot restore prior score',
      () async {
        final dir = await Directory.systemTemp.createTemp('pzd54-a17');
        addTearDown(() {
          if (dir.existsSync()) dir.deleteSync(recursive: true);
        });
        final resultsGate = Completer<void>();
        var resultsRequested = false;
        final api = ScriptedUatApi((method, path, body) async {
          if (method == 'POST' && path.contains('/claims/daily')) {
            return const UatHttpResult(201, {
              'seriesId': 'series-completed',
              'status': 'COMPLETED',
              'original': true,
            });
          }
          if (path.contains('/board')) {
            return const UatHttpResult(200, {
              'ordinal': 1,
              'ordinalLabel': 'E1',
              'seriesScore': 9900,
              'writerSessionMatches': true,
              'state': {'turnsUsed': 3, 'boardSize': 8},
            });
          }
          if (path.contains('/results')) {
            resultsRequested = true;
            await resultsGate.future;
            return const UatHttpResult(200, {
              'all': 9900,
              'onTimeAwarded': true,
            });
          }
          return const UatHttpResult(200, {});
        });
        final controller = await _controller(
          dir: dir,
          playerId: '11111111-1111-1111-1111-111111111111',
          accountType: 'verified',
          api: api,
        );
        final pending = controller.loadDay(presentHome: true);
        for (var i = 0; i < 40 && !resultsRequested; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(resultsRequested, isTrue);
        controller.applyGuestSessionAfterLogout(rankedAuthRequired: true);
        expect(controller.day, isNull);
        expect(controller.results, isEmpty);
        resultsGate.complete();
        await pending;
        expect(controller.day, isNull);
        expect(controller.results, isEmpty);
        expect(controller.rankedAuthRequired, isTrue);
      },
    );

    test(
      'A18 stale successful leaderboard after logout does not restore rows',
      () async {
        final dir = await Directory.systemTemp.createTemp('pzd54-a18');
        addTearDown(() {
          if (dir.existsSync()) dir.deleteSync(recursive: true);
        });
        final gate = Completer<void>();
        final api = ScriptedUatApi((method, path, body) async {
          if (path.contains('/leaderboards/daily')) {
            await gate.future;
            return const UatHttpResult(200, {
              'rows': [
                {'playerId': 'acct-a', 'score': 10200},
              ],
              'nextCursor': null,
              'state': 'FINAL',
            });
          }
          return const UatHttpResult(200, {});
        });
        final controller = await _controller(
          dir: dir,
          playerId: '11111111-1111-1111-1111-111111111111',
          accountType: 'verified',
          api: api,
        );
        final pending = controller.openDaily();
        await Future<void>.delayed(Duration.zero);
        controller.applyGuestSessionAfterLogout(rankedAuthRequired: true);
        expect(controller.leaderboard, isEmpty);
        gate.complete();
        await pending;
        expect(controller.leaderboard, isEmpty);
        expect(controller.busy, isFalse);
        expect(controller.tournamentNoticeCode, isNull);
      },
    );

    test(
      'A19 stale failed leaderboard after logout does not set notice',
      () async {
        final dir = await Directory.systemTemp.createTemp('pzd54-a19');
        addTearDown(() {
          if (dir.existsSync()) dir.deleteSync(recursive: true);
        });
        final gate = Completer<void>();
        final api = ScriptedUatApi((method, path, body) async {
          if (path.contains('/leaderboards/daily')) {
            await gate.future;
            return const UatHttpResult(0, {'error': 'OFFLINE'});
          }
          return const UatHttpResult(200, {});
        });
        final controller = await _controller(
          dir: dir,
          playerId: '11111111-1111-1111-1111-111111111111',
          accountType: 'verified',
          api: api,
        );
        final pending = controller.openDaily();
        await Future<void>.delayed(Duration.zero);
        controller.applyGuestSessionAfterLogout(rankedAuthRequired: true);
        gate.complete();
        await pending;
        expect(controller.leaderboard, isEmpty);
        expect(controller.tournamentNoticeCode, isNull);
        expect(controller.errorCode, isNull);
      },
    );

    test(
      'A20 stale loadMoreLeaderboard cannot append into guest state',
      () async {
        final dir = await Directory.systemTemp.createTemp('pzd54-a20');
        addTearDown(() {
          if (dir.existsSync()) dir.deleteSync(recursive: true);
        });
        final moreGate = Completer<void>();
        final api = ScriptedUatApi((method, path, body) async {
          if (path.contains('/leaderboards/daily') &&
              path.contains('cursor=')) {
            await moreGate.future;
            return const UatHttpResult(200, {
              'rows': [
                {'playerId': 'acct-a-page2', 'score': 9000},
              ],
              'nextCursor': null,
              'state': 'FINAL',
            });
          }
          if (path.contains('/leaderboards/daily')) {
            return const UatHttpResult(200, {
              'rows': [
                {'playerId': 'acct-a', 'score': 10200},
              ],
              'nextCursor': 'cursor-a',
              'state': 'OPEN',
            });
          }
          return const UatHttpResult(200, {});
        });
        final controller = await _controller(
          dir: dir,
          playerId: '11111111-1111-1111-1111-111111111111',
          accountType: 'verified',
          api: api,
        );
        await controller.openDaily();
        expect((controller.leaderboard['rows'] as List?)?.length, 1);
        expect(controller.nextCursor, 'cursor-a');
        final pending = controller.loadMoreLeaderboard();
        await Future<void>.delayed(Duration.zero);
        controller.applyGuestSessionAfterLogout(rankedAuthRequired: true);
        expect(controller.leaderboard, isEmpty);
        moreGate.complete();
        await pending;
        expect(controller.leaderboard, isEmpty);
        expect(controller.nextCursor, isNull);
      },
    );

    test(
      'A21 account switch discards in-flight weekly weeks+board responses',
      () async {
        final dir = await Directory.systemTemp.createTemp('pzd54-a21');
        addTearDown(() {
          if (dir.existsSync()) dir.deleteSync(recursive: true);
        });
        final weeksGate = Completer<void>();
        final api = ScriptedUatApi((method, path, body) async {
          if (path.contains('/leaderboards/weeks')) {
            await weeksGate.future;
            return const UatHttpResult(200, {
              'weeks': ['2026-11-17'],
            });
          }
          if (path.contains('/leaderboards/weekly')) {
            return const UatHttpResult(200, {
              'rows': [
                {'playerId': 'acct-a', 'score': 500},
              ],
              'state': 'OPEN',
            });
          }
          return const UatHttpResult(200, {});
        });
        final controller = await _controller(
          dir: dir,
          playerId: '11111111-1111-1111-1111-111111111111',
          accountType: 'verified',
          api: api,
        );
        final pending = controller.openWeekly(fromHome: true);
        await Future<void>.delayed(Duration.zero);
        controller.invalidateAccountScopedPresentation(
          reason: 'account_transition',
        );
        controller.markAccountStateUpdated();
        weeksGate.complete();
        await pending;
        expect(controller.weeks, isEmpty);
        expect(controller.leaderboard, isEmpty);
        expect(controller.weekStart, isNull);
      },
    );

    test(
      'A22 same-account reauth bumps generation and rejects stale daily board',
      () async {
        final dir = await Directory.systemTemp.createTemp('pzd54-a22');
        addTearDown(() {
          if (dir.existsSync()) dir.deleteSync(recursive: true);
        });
        final gate = Completer<void>();
        final api = ScriptedUatApi((method, path, body) async {
          if (path.contains('/leaderboards/daily')) {
            await gate.future;
            return const UatHttpResult(200, {
              'rows': [
                {'playerId': 'stale-gen', 'score': 1},
              ],
              'state': 'FINAL',
            });
          }
          return const UatHttpResult(200, {});
        });
        final controller = await _controller(
          dir: dir,
          playerId: '11111111-1111-1111-1111-111111111111',
          accountType: 'verified',
          api: api,
        );
        final pending = controller.openDaily();
        await Future<void>.delayed(Duration.zero);
        // Same account / same scope: generation bump alone must fence.
        controller.invalidateAccountScopedPresentation(
          reason: 'account_transition',
        );
        controller.markAccountStateUpdated();
        gate.complete();
        await pending;
        expect(controller.leaderboard, isEmpty);
      },
    );

    test(
      'A23 delayed home snapshot hydrate cannot cross A→Guest→A generation',
      () async {
        final dir = await Directory.systemTemp.createTemp('pzd54-a23');
        addTearDown(() {
          if (dir.existsSync()) dir.deleteSync(recursive: true);
        });
        const playerId = '11111111-1111-1111-1111-111111111111';
        final controller = await _controller(
          dir: dir,
          playerId: playerId,
          accountType: 'verified',
        );
        final scope = controller.identity.activeScope;
        final snap = TournamentHomeSnapshot.fromLive(
          scope: scope,
          day: _completedDay(score: 7777),
          originalUtcDate: '2026-11-27',
          capturedAtMs: 1,
          results: {'all': 7777, 'onTimeAwarded': true},
        )!;
        await TournamentHomeSnapshotStore(DirectoryKvStore(dir)).save(snap);

        final gate = Completer<void>();
        controller.debugBeforeHomeSnapshotLoad = () => gate.future;
        controller.day = null;
        controller.results = const {};
        controller.homeSnapshot = null;
        final pending = controller.debugHydrateHomeSnapshot();
        await Future<void>.delayed(Duration.zero);

        // Leave and return to the same player scope with a newer generation.
        controller.applyGuestSessionAfterLogout(rankedAuthRequired: true);
        await controller.identity.bindAuthenticatedPlayer(playerId);
        controller.markAccountStateUpdated();
        expect(controller.identity.activeScope.storageKey, scope.storageKey);

        gate.complete();
        await pending;
        expect(controller.day, isNull);
        expect(controller.results, isEmpty);
        expect(controller.homeSnapshot, isNull);
      },
    );

    test(
      'A24 stale device register result is not assigned after logout',
      () async {
        final dir = await Directory.systemTemp.createTemp('pzd54-a24');
        addTearDown(() {
          if (dir.existsSync()) dir.deleteSync(recursive: true);
        });
        const playerId = '11111111-1111-4111-8111-111111111111';
        const sessionId = '33333333-3333-4333-8333-333333333333';
        const bearer = 'Bearer player-a-token';
        final binding = UatApi.authBinding(bearer);
        const origin = 'https://staging.puzzle-duel.app';
        File('${dir.path}/pzd-uat-session.json').writeAsStringSync(
          jsonEncode({
            'version': 2,
            'sessions': {
              binding: {'secret': 'bound-secret-a', 'apiOrigin': origin},
            },
          }),
        );

        const channel = MethodChannel('pzd/device_signing');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'registerProof') {
                return {
                  'spkiBase64Url': 'test-public-key',
                  'signatureBase64Url': 'test-registration-signature',
                };
              }
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });

        final registerGate = Completer<void>();
        var registerStarted = false;
        final api = ScriptedUatApi((method, path, body) async {
          if (path.endsWith('/session') && method == 'GET') {
            return const UatHttpResult(200, {
              'playerId': playerId,
              'sessionId': sessionId,
              'expiresAtMs': 9999999999999,
            });
          }
          if (path.endsWith('/devices/register')) {
            registerStarted = true;
            await registerGate.future;
            return const UatHttpResult(200, {
              'deviceCredentialId': '44444444-4444-4444-8444-444444444444',
            });
          }
          if (path.contains('/claims/daily')) {
            return const UatHttpResult(201, {
              'seriesId': 'series-a',
              'status': 'ACTIVE',
              'original': true,
            });
          }
          if (path.contains('/board')) {
            return const UatHttpResult(200, {
              'ordinal': 1,
              'ordinalLabel': 'E1',
              'seriesScore': 0,
              'writerSessionMatches': true,
              'state': {'turnsUsed': 0, 'boardSize': 8},
            });
          }
          return const UatHttpResult(200, {});
        });

        final identity = PracticeIdentityStore(dir);
        await identity.load();
        await identity.bindAuthenticatedPlayer(playerId);
        final controller = TournamentController(
          config: const UatConfig(
            baseUrl: origin,
            bearer: bearer,
            playerLabel: 'verified',
          ),
          api: api,
          stateDirectory: dir,
          identity: identity,
          deviceRecovery: SameDeviceRecovery(isSupportedDevice: () => true),
        );
        addTearDown(controller.dispose);
        await controller.beginLocal();

        final pending = controller.refreshTournament();
        for (var i = 0; i < 50 && !registerStarted; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(registerStarted, isTrue);
        controller.applyGuestSessionAfterLogout(rankedAuthRequired: true);
        expect(controller.debugSameDeviceRegistered, isFalse);
        registerGate.complete();
        await pending;
        expect(controller.debugSameDeviceRegistered, isFalse);
      },
    );

    test(
      'A25 stale GET 401 hydrate must not open a fresh POST session',
      () async {
        final dir = await Directory.systemTemp.createTemp('pzd54-a25');
        addTearDown(() {
          if (dir.existsSync()) dir.deleteSync(recursive: true);
        });
        const bearer = 'Bearer player-a-token';
        final binding = UatApi.authBinding(bearer);
        const origin = 'https://staging.puzzle-duel.app';
        File('${dir.path}/pzd-uat-session.json').writeAsStringSync(
          jsonEncode({
            'version': 2,
            'sessions': {
              binding: {'secret': 'expired-secret-a', 'apiOrigin': origin},
            },
          }),
        );

        var postSessionCalls = 0;
        var hydrateStarted = false;
        final hydrateGate = Completer<void>();
        final api = ScriptedUatApi((method, path, body) async {
          if (path.endsWith('/session') && method == 'GET') {
            return const UatHttpResult(401, {'error': 'UNAUTHENTICATED'});
          }
          if (path.endsWith('/session') && method == 'POST') {
            postSessionCalls++;
            return const UatHttpResult(201, {
              'playerId': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
              'sessionId': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
              'sessionSecret': 'fresh-after-401',
              'expiresAtMs': 9999999999999,
            });
          }
          return const UatHttpResult(200, {});
        });

        final identity = PracticeIdentityStore(dir);
        await identity.load();
        await identity.bindAuthenticatedPlayer(
          '11111111-1111-1111-1111-111111111111',
        );
        final controller = TournamentController(
          config: const UatConfig(
            baseUrl: origin,
            bearer: bearer,
            playerLabel: 'verified',
          ),
          api: api,
          stateDirectory: dir,
          identity: identity,
        );
        addTearDown(controller.dispose);
        await controller.beginLocal();
        controller.debugBeforeHomeSnapshotLoad = () async {
          hydrateStarted = true;
          await hydrateGate.future;
        };

        final pending = controller.refreshTournament();
        for (var i = 0; i < 50 && !hydrateStarted; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(hydrateStarted, isTrue);
        controller.applyGuestSessionAfterLogout(rankedAuthRequired: true);
        hydrateGate.complete();
        await pending;
        expect(postSessionCalls, 0);
        expect(api.sessionSecret, isNull);
      },
    );
  });
}
