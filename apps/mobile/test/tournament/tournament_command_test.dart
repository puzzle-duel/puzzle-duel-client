import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/application/game_session.dart';
import 'package:puzzle_duel_mobile/tournament/practice_identity.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_controller.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_nav.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

Map<String, Object?> _fixture(String name) {
  return jsonDecode(File('test/tournament/fixtures/$name').readAsStringSync())
      as Map<String, Object?>;
}

final class ScriptedUatApi extends UatApi {
  ScriptedUatApi(this.onRequest)
    : super(baseUrl: 'http://127.0.0.1', bearer: 'Bearer test');

  final List<Object?> commandBodies = [];
  int claimPosts = 0;
  final Future<UatHttpResult> Function(String method, String path, Object? body)
  onRequest;

  @override
  Future<UatHttpResult> get(String path) async {
    final result = await onRequest('GET', path, null);
    // PZD-55 Home refresh uses calendar; keep legacy scripts that omit it.
    // Do not mask transport failures (status 0) as a successful overview.
    if (path.endsWith('/calendar') && result.status == 404) {
      return UatHttpResult(200, _defaultCalendarFixture());
    }
    return result;
  }

  @override
  Future<UatHttpResult> patch(String path) => onRequest('PATCH', path, null);

  @override
  Future<UatHttpResult> delete(String path) => onRequest('DELETE', path, null);

  @override
  Future<UatHttpResult> post(String path, [Object? body]) {
    if (path.endsWith('/commands')) commandBodies.add(body);
    if (path.endsWith('/claims/daily')) claimPosts += 1;
    return onRequest('POST', path, body);
  }
}

Map<String, Object?> _defaultCalendarFixture({bool accountScoped = true}) {
  final today = DateTime.now().toUtc();
  final dayStart = DateTime.utc(today.year, today.month, today.day);
  final mondayOffset = (dayStart.weekday + 6) % 7;
  final monday = dayStart.subtract(Duration(days: mondayOffset));
  final days = <Map<String, Object?>>[];
  for (var i = 0; i < 7; i++) {
    final date = monday.add(Duration(days: i));
    final iso = date.toIso8601String().substring(0, 10);
    final isToday = date == dayStart;
    final isFuture = date.isAfter(dayStart);
    days.add({
      'date': iso,
      'status': isFuture
          ? 'LOCKED_FUTURE'
          : isToday
          ? 'AVAILABLE_TODAY'
          : 'AVAILABLE_PAST',
      'isToday': isToday,
      'canStart': accountScoped && !isFuture,
      'canResume': false,
      'canViewResults': false,
      'completedBoardCount': 0,
      'totalBoardCount': 6,
    });
  }
  return {
    'weekStartUtc': monday.toIso8601String().substring(0, 10),
    'weekEndUtc': monday
        .add(const Duration(days: 6))
        .toIso8601String()
        .substring(0, 10),
    'serverNowMs': DateTime.now().toUtc().millisecondsSinceEpoch,
    'currentTournamentDate': dayStart.toIso8601String().substring(0, 10),
    'completedDayCount': 0,
    'playablePastDayCount': accountScoped ? mondayOffset : 0,
    'accountScoped': accountScoped,
    'days': days,
  };
}

void main() {
  test(
    'a second tap is ignored while an authoritative command is in flight',
    () async {
      final initial = parseGameState(
        _fixture('V3-02-single-wave.json')['initialState'],
      );
      final session = GameSession();
      final gate = Completer<void>();
      var calls = 0;
      session.onAuthoritativeTap = (offer, tap) {
        calls += 1;
        return gate.future;
      };
      session.showAuthoritative(initial);
      session.selectOffer(0);
      expect(session.submitTap(Coordinate(row: 0, column: 2)), isTrue);
      expect(session.submitTap(Coordinate(row: 1, column: 1)), isFalse);
      expect(calls, 1);
      expect(session.applyMoveCallCount, 0);
      gate.complete();
      await Future<void>.delayed(Duration.zero);
    },
  );

  test('an unknown outcome blocks a different move', () {
    final initial = parseGameState(
      _fixture('V3-02-single-wave.json')['initialState'],
    );
    final session = GameSession();
    session.onAuthoritativeTap = (offer, tap) async {};
    session.showAuthoritative(initial);
    session.selectOffer(0);
    session.markAuthoritativeUnknown();
    expect(session.submitTap(Coordinate(row: 0, column: 2)), isFalse);
    expect(session.applyMoveCallCount, 0);
  });

  test(
    'the same command is retried and the local engine does not score it',
    () async {
      final document = _fixture('V3-02-single-wave.json');
      final directory = Directory.systemTemp.createTempSync('pzd42-command');
      final identity = PracticeIdentityStore(directory);
      await identity.load();
      var commandPosts = 0;
      final api = ScriptedUatApi((method, path, body) async {
        if (method == 'POST' && path.endsWith('/session')) {
          return const UatHttpResult(201, {
            'playerId': '11111111-1111-4111-8111-111111111111',
            'sessionSecret': 'secret',
          });
        }
        if (path.endsWith('/claims/daily')) {
          return const UatHttpResult(201, {
            'seriesId': '11111111-1111-4111-8111-111111111111',
            'status': 'ACTIVE',
            'original': true,
          });
        }
        if (path.endsWith('/board')) {
          final state = commandPosts == 0
              ? document['initialState']
              : (document['expected']! as Map)['finalState'];
          return UatHttpResult(200, {
            'ordinal': 1,
            'ordinalLabel': 'E1',
            'seriesScore': commandPosts == 0 ? 0 : 300,
            'score': commandPosts == 0 ? 0 : 300,
            'awaitAdvance': false,
            'resultsPublished': false,
            'boardRevision': commandPosts == 0 ? 1 : 2,
            'writerGeneration': 1,
            'idleDeadlineAtMs': 5000,
            'serverNowMs': 1000,
            'state': state,
          });
        }
        if (path.endsWith('/commands')) {
          commandPosts += 1;
          if (commandPosts == 1) {
            return const UatHttpResult(0, {'error': 'TIMEOUT'});
          }
          return const UatHttpResult(200, {'ok': true});
        }
        return const UatHttpResult(404, {'error': 'NOT_FOUND'});
      });
      final controller = TournamentController(
        config: const UatConfig(
          baseUrl: 'http://127.0.0.1',
          bearer: 'Bearer test',
          playerLabel: 'command',
        ),
        api: api,
        stateDirectory: directory,
        identity: identity,
        haptics: const SilentTournamentHaptics(),
      );
      await controller.start();
      await controller.resume();
      controller.session.selectOffer(0);
      expect(
        controller.session.submitTap(Coordinate(row: 0, column: 2)),
        isTrue,
      );
      await pumpEventQueue();
      expect(controller.hasPendingCommand, isTrue);
      final first = controller.pendingCommand;
      await controller.retryUnknown();
      expect(api.commandBodies, hasLength(2));
      expect(identical(api.commandBodies[0], api.commandBodies[1]), isTrue);
      expect(identical(api.commandBodies[0], first), isTrue);
      // Local apply is used only to arm AnimationScript; ranked score is server.
      expect(controller.session.applyMoveCallCount, 1);
      expect(controller.session.view.phase, GameScreenPhase.resolving);
      expect(controller.scoreDelta, 300);
      expect(controller.session.view.score, 300);
      final script = controller.session.view.activeScript!;
      controller.session.completeResolution(
        generation: script.generation,
        resolutionId: script.resolutionId,
      );
      expect(controller.session.view.score, 300);
    },
  );

  test('a stale rejection reloads the server score', () async {
    final document = _fixture('V3-02-single-wave.json');
    final directory = Directory.systemTemp.createTempSync('pzd42-stale');
    final identity = PracticeIdentityStore(directory);
    await identity.load();
    final api = ScriptedUatApi((method, path, body) async {
      if (method == 'POST' && path.endsWith('/session')) {
        return const UatHttpResult(201, {
          'playerId': '11111111-1111-4111-8111-111111111111',
          'sessionSecret': 'secret',
        });
      }
      if (path.endsWith('/claims/daily')) {
        return const UatHttpResult(200, {
          'seriesId': '11111111-1111-4111-8111-111111111111',
          'status': 'ACTIVE',
          'original': true,
        });
      }
      if (path.endsWith('/board')) {
        return UatHttpResult(200, {
          'ordinal': 1,
          'ordinalLabel': 'E1',
          'seriesScore': 0,
          'score': 0,
          'awaitAdvance': false,
          'resultsPublished': false,
          'boardRevision': 4,
          'writerGeneration': 1,
          'state': document['initialState'],
        });
      }
      if (path.endsWith('/commands')) {
        return const UatHttpResult(409, {'error': 'STATE_CONFLICT'});
      }
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });
    final controller = TournamentController(
      config: const UatConfig(
        baseUrl: 'http://127.0.0.1',
        bearer: 'Bearer test',
        playerLabel: 'stale',
      ),
      api: api,
      stateDirectory: directory,
      identity: identity,
      haptics: const SilentTournamentHaptics(),
    );
    await controller.start();
    await controller.resume();
    controller.session.selectOffer(0);
    expect(controller.session.submitTap(Coordinate(row: 0, column: 2)), isTrue);
    await pumpEventQueue();
    expect(controller.noticeCode, 'STATE_CONFLICT');
    expect(controller.session.view.score, 0);
    expect(controller.session.applyMoveCallCount, 0);
    expect(controller.scoreDelta, isNull);
  });
  test('resuming an await-advance board enters the transition screen', () async {
    final document = _fixture('V3-02-single-wave.json');
    final directory = Directory.systemTemp.createTempSync('pzd50-resume');
    addTearDown(() => directory.deleteSync(recursive: true));
    final identity = PracticeIdentityStore(directory);
    await identity.load();
    final api = ScriptedUatApi((method, path, body) async {
      if (method == 'POST' && path.endsWith('/session')) {
        return const UatHttpResult(201, {
          'playerId': '11111111-1111-4111-8111-111111111111',
          'sessionSecret': 'secret',
        });
      }
      if (path.endsWith('/claims/daily')) {
        return const UatHttpResult(200, {
          'seriesId': '11111111-1111-4111-8111-111111111111',
          'status': 'ACTIVE',
          'original': true,
        });
      }
      if (path.endsWith('/board')) {
        return UatHttpResult(200, {
          'ordinal': 1, 'ordinalLabel': 'E1',
          'seriesScore': 100, 'score': 100,
          'awaitAdvance': true,
          'resultsPublished': false,
          'boardRevision': 2,
          'writerGeneration': 1,
          'idleDeadlineAtMs': 5000,
          'serverNowMs': 1000,
          'state': (document['expected'] as Map)['finalState'],
        });
      }
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });
    final controller = TournamentController(
      config: const UatConfig(
        baseUrl: 'http://127.0.0.1',
        bearer: 'Bearer test',
        playerLabel: 'resume',
      ),
      api: api,
      stateDirectory: directory,
      identity: identity,
      haptics: const SilentTournamentHaptics(),
    );
    addTearDown(controller.dispose);
    await controller.start();
    expect(controller.route.place, TournamentPlace.home);
    await controller.resume();
    expect(controller.route.place, TournamentPlace.transition);
  });

  test('accepted move uses matching authoritativeBoard without second GET', () async {
    final document = _fixture('V3-02-single-wave.json');
    final directory = Directory.systemTemp.createTempSync('pzd50-embedded');
    addTearDown(() => directory.deleteSync(recursive: true));
    final identity = PracticeIdentityStore(directory);
    await identity.load();
    var boardReads = 0;
    final api = ScriptedUatApi((method, path, body) async {
      if (method == 'POST' && path.endsWith('/session')) {
        return const UatHttpResult(201, {
          'playerId': '11111111-1111-4111-8111-111111111111',
          'sessionSecret': 'secret',
        });
      }
      if (path.endsWith('/claims/daily')) {
        return const UatHttpResult(201, {
          'seriesId': '11111111-1111-4111-8111-111111111111',
          'status': 'ACTIVE', 'original': true,
        });
      }
      if (path.endsWith('/board')) {
        boardReads++;
        return UatHttpResult(200, {
          'seriesId': '11111111-1111-4111-8111-111111111111',
          'ordinal': 1, 'ordinalLabel': 'E1',
          'seriesScore': 0, 'score': 0,
          'awaitAdvance': false,
          'resultsPublished': false,
          'boardRevision': 1,
          'stateHash': 'before',
          'writerGeneration': 1,
          'idleDeadlineAtMs': 5000, 'serverNowMs': 1000,
          'state': document['initialState'],
        });
      }
      if (path.endsWith('/commands')) {
        return UatHttpResult(200, {
          'decision': 'apply', 'boardRevision': 2, 'stateHash': 'after',
          'score': 300, 'scoreDelta': 300,
          'authoritativeBoard': {
            'seriesId': '11111111-1111-4111-8111-111111111111',
            'ordinal': 1, 'ordinalLabel': 'E1',
            'seriesScore': 300, 'score': 300,
            'awaitAdvance': false, 'resultsPublished': false,
            'boardRevision': 2, 'stateHash': 'after',
            'writerGeneration': 1,
            'idleDeadlineAtMs': 5000, 'serverNowMs': 1000,
            'state': (document['expected'] as Map)['finalState'],
          },
        });
      }
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });
    final controller = TournamentController(
      config: const UatConfig(
        baseUrl: 'http://127.0.0.1',
        bearer: 'Bearer test',
        playerLabel: 'embedded',
      ),
      api: api,
      stateDirectory: directory,
      identity: identity,
      haptics: const SilentTournamentHaptics(),
    );
    addTearDown(controller.dispose);
    await controller.start();
    await controller.resume();
    expect(boardReads, 2);
    controller.session.selectOffer(0);
    expect(controller.session.submitTap(Coordinate(row: 0, column: 2)), isTrue);
    await pumpEventQueue();
    expect(boardReads, 2);
    expect(controller.session.applyMoveCallCount, 1);
  });

}
