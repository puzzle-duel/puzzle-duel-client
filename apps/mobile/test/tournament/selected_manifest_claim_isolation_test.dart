import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/tournament/practice_identity.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_controller.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_nav.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';
import 'package:puzzle_duel_mobile/tournament/weekly_tournament_overview.dart';

import 'tournament_command_test.dart' show ScriptedUatApi;

void main() {
  test('resume without selected/active identity does not silent-claim today',
      () async {
    final dir = Directory.systemTemp.createTempSync('pzd55-resume-no-id');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final identity = PracticeIdentityStore(dir);
    await identity.load();
    final api = ScriptedUatApi((method, path, body) async {
      if (method == 'POST' && path.endsWith('/session')) {
        return const UatHttpResult(201, {
          'playerId': '11111111-1111-4111-8111-111111111111',
          'sessionSecret': 'secret',
        });
      }
      if (path.endsWith('/claims/daily')) {
        return const UatHttpResult(201, {
          'seriesId': 'should-not-claim',
          'status': 'ACTIVE',
          'original': true,
          'originalUtcDate': '2099-01-01',
        });
      }
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });
    final controller = TournamentController(
      config: const UatConfig(
        baseUrl: 'http://127.0.0.1',
        bearer: 'Bearer test',
        playerLabel: 'resume-iso',
      ),
      api: api,
      stateDirectory: dir,
      identity: identity,
      haptics: const SilentTournamentHaptics(),
    );
    // Boot calendar only (default fixture), then wipe selection/overview so
    // resume has no claimable identity — must not invent `_today()`.
    await controller.start();
    controller.weeklyOverview = null;
    controller.selectedTournamentDate = null;
    controller.activeManifestUtcDate = null;
    controller.day = null;
    controller.seriesId = null;
    controller.tournamentSync = TournamentSyncState.ready;
    controller.rankedWriterLocked = false;
    controller.rankedAuthRequired = false;
    final claimsBefore = api.claimPosts;
    await controller.resume();
    expect(api.claimPosts, claimsBefore);
    expect(controller.day, isNull);
    expect(controller.seriesId, isNull);
    expect(controller.tournamentNoticeCode, 'TOURNAMENT_UNAVAILABLE');
  });

  test('loadDay without claim date refuses instead of inventing today', () async {
    final dir = Directory.systemTemp.createTempSync('pzd55-load-no-date');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final identity = PracticeIdentityStore(dir);
    await identity.load();
    final api = ScriptedUatApi((method, path, body) async {
      if (path.endsWith('/claims/daily')) {
        return const UatHttpResult(201, {
          'seriesId': 'should-not-claim',
          'status': 'ACTIVE',
          'original': true,
        });
      }
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });
    final controller = TournamentController(
      config: const UatConfig(
        baseUrl: 'http://127.0.0.1',
        bearer: 'Bearer test',
        playerLabel: 'load-iso',
      ),
      api: api,
      stateDirectory: dir,
      identity: identity,
      haptics: const SilentTournamentHaptics(),
    );
    controller.weeklyOverview = null;
    controller.selectedTournamentDate = null;
    await controller.loadDay(presentHome: true);
    expect(api.claimPosts, 0);
    expect(controller.tournamentNoticeCode, 'MALFORMED_REQUEST');
    expect(controller.day, isNull);
  });

  test('delayed claim after account switch does not mutate new scope', () async {
    final dir = Directory.systemTemp.createTempSync('pzd55-stale-claim');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final identity = PracticeIdentityStore(dir);
    await identity.load();
    final gate = Completer<void>();
    final api = ScriptedUatApi((method, path, body) async {
      if (method == 'POST' && path.endsWith('/session')) {
        return const UatHttpResult(201, {
          'playerId': '11111111-1111-4111-8111-111111111111',
          'sessionSecret': 'secret',
        });
      }
      if (path.endsWith('/claims/daily')) {
        await gate.future;
        return const UatHttpResult(201, {
          'seriesId': 'stale-series',
          'status': 'ACTIVE',
          'original': true,
          'originalUtcDate': '2026-11-28',
        });
      }
      if (path.endsWith('/board')) {
        return const UatHttpResult(200, {
          'ordinal': 3,
          'ordinalLabel': 'M1',
          'seriesScore': 2100,
          'awaitAdvance': false,
          'resultsPublished': false,
          'state': {'turnsUsed': 1, 'moveLimit': 15, 'boardSize': 5},
        });
      }
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });
    final controller = TournamentController(
      config: const UatConfig(
        baseUrl: 'http://127.0.0.1',
        bearer: 'Bearer test',
        playerLabel: 'stale-claim',
      ),
      api: api,
      stateDirectory: dir,
      identity: identity,
      haptics: const SilentTournamentHaptics(),
    );
    controller.weeklyOverview = WeeklyTournamentOverview.tryParse({
      'weekStartUtc': '2026-11-23',
      'weekEndUtc': '2026-11-29',
      'serverNowMs': 1,
      'currentTournamentDate': '2026-11-28',
      'completedDayCount': 0,
      'playablePastDayCount': 0,
      'accountScoped': true,
      'days': [
        {
          'date': '2026-11-28',
          'status': 'AVAILABLE_TODAY',
          'isToday': true,
          'canStart': true,
          'canResume': false,
          'canViewResults': false,
          'completedBoardCount': 0,
          'totalBoardCount': 6,
        },
      ],
    });
    controller.selectedTournamentDate = '2026-11-28';
    final pending = controller.loadDay(
      presentHome: false,
      originalUtcDate: '2026-11-28',
    );
    await Future<void>.delayed(Duration.zero);
    controller.invalidateAccountScopedPresentation(reason: 'account_transition');
    expect(controller.day, isNull);
    expect(controller.route.place, TournamentPlace.home);
    gate.complete();
    await pending;
    expect(controller.day, isNull);
    expect(controller.seriesId, isNull);
    expect(controller.activeManifestUtcDate, isNull);
    expect(controller.route.place, TournamentPlace.home);
  });
}
