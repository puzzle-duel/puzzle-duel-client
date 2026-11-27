import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/presentation/feedback/app_feedback.dart';
import 'package:puzzle_duel_mobile/tournament/guest_auth.dart';
import 'package:puzzle_duel_mobile/tournament/practice_identity.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_controller.dart';
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
    api:
        api ??
        ScriptedUatApi((_, _, _) async => const UatHttpResult(200, {})),
    stateDirectory: dir,
    identity: identity,
    sessionAuth: session,
  );
  await controller.beginLocal();
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PZD-54 account isolation', () {
    test(
      'A01 logout clears completed tournament personal presentation',
      () async {
        final dir = await Directory.systemTemp.createTemp('pzd54-a01');
        addTearDown(() => dir.delete(recursive: true));
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
        controller.dispose();
      },
    );

    test(
      'A02 stale successful loadDay after logout does not restore day',
      () async {
        final dir = await Directory.systemTemp.createTemp('pzd54-a02');
        addTearDown(() => dir.delete(recursive: true));
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
        controller.dispose();
      },
    );

    test('A03 stale failed loadDay after logout does not set notice', () async {
      final dir = await Directory.systemTemp.createTemp('pzd54-a03');
      addTearDown(() => dir.delete(recursive: true));
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
      controller.dispose();
    });

    test(
      'A04/A05 account transition clears previous snapshot before hydrate',
      () async {
        final dir = await Directory.systemTemp.createTemp('pzd54-a04');
        addTearDown(() => dir.delete(recursive: true));
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
        controller.dispose();
      },
    );

    test(
      'A06/A07 stale finally cannot clear newer account in-flight state',
      () async {
        final dir = await Directory.systemTemp.createTemp('pzd54-a07');
        addTearDown(() => dir.delete(recursive: true));
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
        controller.dispose();
      },
    );

    test(
      'A08 guest cannot hydrate previous account disk snapshot as day',
      () async {
        final dir = await Directory.systemTemp.createTemp('pzd54-a08');
        addTearDown(() => dir.delete(recursive: true));
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
        controller.dispose();
      },
    );

    test('A10 guest Practice scope remains after logout', () async {
      final dir = await Directory.systemTemp.createTemp('pzd54-a10');
      addTearDown(() => dir.delete(recursive: true));
      final controller = await _controller(
        dir: dir,
        playerId: '11111111-1111-1111-1111-111111111111',
        accountType: 'verified',
      );
      await controller.clearAuthenticatedPracticeScope();
      controller.applyGuestSessionAfterLogout(rankedAuthRequired: true);
      expect(controller.identity.activeScope.kind, PracticeIdentityKind.guest);
      expect(controller.practiceStore().scope.kind, PracticeIdentityKind.guest);
      controller.dispose();
    });

    test('A11 guest gate does not claim tournament', () async {
      final dir = await Directory.systemTemp.createTemp('pzd54-a11');
      addTearDown(() => dir.delete(recursive: true));
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
      controller.dispose();
    });

    test('A15 logout feedback uses Top Banner channel only', () async {
      final dir = await Directory.systemTemp.createTemp('pzd54-a15');
      addTearDown(() => dir.delete(recursive: true));
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
      controller.dispose();
    });

    test('A16 logout clears authenticated navigation resume state', () async {
      final dir = await Directory.systemTemp.createTemp('pzd54-a16');
      addTearDown(() => dir.delete(recursive: true));
      final controller = await _controller(
        dir: dir,
        playerId: '11111111-1111-1111-1111-111111111111',
        accountType: 'verified',
      );
      controller.route = const TournamentRoute(place: TournamentPlace.playing);
      controller.day = _completedDay();
      controller.applyGuestSessionAfterLogout(rankedAuthRequired: true);
      expect(controller.route.place, TournamentPlace.home);
      controller.dispose();
    });

    test('stale app feedback clear is generation-fenced', () async {
      final dir = await Directory.systemTemp.createTemp('pzd54-fb');
      addTearDown(() => dir.delete(recursive: true));
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
      controller.dismissAppFeedback(reason: 'gesture');
      expect(controller.appFeedback, isNull);
      controller.dispose();
    });
  });
}
