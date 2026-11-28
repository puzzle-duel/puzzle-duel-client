import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/tournament/practice_identity.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_controller.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';
import 'package:puzzle_duel_mobile/tournament/weekly_tournament_overview.dart';

import 'tournament_command_test.dart' show ScriptedUatApi;

void main() {
  test('RC-04 locked/closed/unavailable never claim; no silent today fallback', () async {
    final dir = Directory.systemTemp.createTempSync('pzd55-elig');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final api = ScriptedUatApi((method, path, body) async {
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });
    final identity = PracticeIdentityStore(dir);
    final controller = TournamentController(
      config: const UatConfig(
        baseUrl: 'https://staging.puzzle-duel.app',
        bearer: 'Bearer test',
        playerLabel: 'Verified',
      ),
      api: api,
      stateDirectory: dir,
      identity: identity,
      haptics: const SilentTournamentHaptics(),
    );
    await controller.beginLocal();
    controller.weeklyOverview = WeeklyTournamentOverview.tryParse({
      'weekStartUtc': '2026-11-23',
      'weekEndUtc': '2026-11-29',
      'serverNowMs': 1,
      'currentTournamentDate': '2026-11-28',
      'completedDayCount': 0,
      'playablePastDayCount': 0,
      'accountScoped': true,
      'days': [
        for (final d in [
          ('2026-11-23', 'CLOSED'),
          ('2026-11-24', 'UNAVAILABLE'),
          ('2026-11-25', 'UNKNOWN_STATUS'),
          ('2026-11-26', 'LOCKED_FUTURE'),
          ('2026-11-27', 'AVAILABLE_PAST'),
          ('2026-11-28', 'AVAILABLE_TODAY'),
          ('2026-11-29', 'LOCKED_FUTURE'),
        ])
          {
            'date': d.$1,
            'status': d.$2,
            'isToday': d.$1 == '2026-11-28',
            'canStart': false,
            'canResume': false,
            'canViewResults': false,
            'completedBoardCount': 0,
            'totalBoardCount': 6,
          },
      ],
    });
    controller.selectedTournamentDate = '2026-11-26';
    await controller.startSelectedManifest();
    expect(api.claimPosts, 0);
    expect(controller.tournamentNoticeCode, 'CLAIM_WINDOW_CLOSED');

    controller.selectedTournamentDate = '2026-11-23';
    await controller.startSelectedManifest();
    expect(api.claimPosts, 0);
    expect(controller.tournamentNoticeCode, 'TOURNAMENT_UNAVAILABLE');

    controller.selectedTournamentDate = null;
    controller.tournamentNoticeCode = null;
    await controller.startSelectedManifest();
    expect(api.claimPosts, 0);
    expect(controller.tournamentNoticeCode, 'TOURNAMENT_UNAVAILABLE');
    controller.dispose();
  });

  test('RC-04 start claims selected past date only when canStart', () async {
    final dir = Directory.systemTemp.createTempSync('pzd55-claim-date');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    Object? claimBody;
    final api = ScriptedUatApi((method, path, body) async {
      if (path.endsWith('/claims/daily') && method == 'POST') {
        claimBody = body;
        return const UatHttpResult(201, {
          'seriesId': 'series-mon',
          'status': 'ACTIVE',
          'original': true,
          'originalUtcDate': '2026-11-23',
        });
      }
      if (path.contains('/board')) {
        return const UatHttpResult(200, {
          'ordinal': 1,
          'ordinalLabel': 'E1',
          'seriesScore': 0,
          'awaitAdvance': false,
          'resultsPublished': false,
          'state': {'turnsUsed': 0, 'moveLimit': 15, 'boardSize': 5},
        });
      }
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });
    final identity = PracticeIdentityStore(dir);
    final controller = TournamentController(
      config: const UatConfig(
        baseUrl: 'https://staging.puzzle-duel.app',
        bearer: 'Bearer test',
        playerLabel: 'Verified',
      ),
      api: api,
      stateDirectory: dir,
      identity: identity,
      haptics: const SilentTournamentHaptics(),
    );
    await controller.beginLocal();
    controller.weeklyOverview = WeeklyTournamentOverview.tryParse({
      'weekStartUtc': '2026-11-23',
      'weekEndUtc': '2026-11-29',
      'serverNowMs': 1,
      'currentTournamentDate': '2026-11-28',
      'completedDayCount': 0,
      'playablePastDayCount': 1,
      'accountScoped': true,
      'days': [
        {
          'date': '2026-11-23',
          'status': 'AVAILABLE_PAST',
          'isToday': false,
          'canStart': true,
          'canResume': false,
          'canViewResults': false,
          'completedBoardCount': 0,
          'totalBoardCount': 6,
        },
        for (final date in [
          '2026-11-24',
          '2026-11-25',
          '2026-11-26',
          '2026-11-27',
          '2026-11-28',
          '2026-11-29',
        ])
          {
            'date': date,
            'status': date == '2026-11-29' ? 'LOCKED_FUTURE' : 'AVAILABLE_PAST',
            'isToday': date == '2026-11-28',
            'canStart': date != '2026-11-29',
            'canResume': false,
            'canViewResults': false,
            'completedBoardCount': 0,
            'totalBoardCount': 6,
          },
      ],
    });
    controller.selectedTournamentDate = '2026-11-23';
    await controller.startSelectedManifest();
    expect(api.claimPosts, 1);
    expect(claimBody, containsPair('originalUtcDate', '2026-11-23'));
    expect(controller.activeManifestUtcDate, '2026-11-23');
    controller.dispose();
  });
}
