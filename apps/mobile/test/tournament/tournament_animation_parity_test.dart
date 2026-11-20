import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/application/animation_script.dart';
import 'package:puzzle_duel_mobile/application/game_constants.dart';
import 'package:puzzle_duel_mobile/application/game_session.dart';
import 'package:puzzle_duel_mobile/tournament/practice_identity.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_controller.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_nav.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

import 'tournament_command_test.dart' show ScriptedUatApi;

Map<String, Object?> _fixture(String name) {
  return jsonDecode(File('test/tournament/fixtures/$name').readAsStringSync())
      as Map<String, Object?>;
}

({GameState initial, MoveApplied applied, Coordinate tap, int offer})
_localResolve(String fixtureName) {
  final document = _fixture(fixtureName);
  final initial = parseGameState(document['initialState']);
  final moveJson = (document['moves'] as List).first as Map;
  final offer = moveJson['offerIndex'] as int;
  final tapList = moveJson['tap'] as List;
  final tap = Coordinate(row: tapList[0] as int, column: tapList[1] as int);
  final result = applyMove(initial, Move(offerIndex: offer, tap: tap));
  expect(result, isA<MoveApplied>());
  return (
    initial: initial,
    applied: result as MoveApplied,
    tap: tap,
    offer: offer,
  );
}

Future<TournamentController> _boot({
  required ScriptedUatApi api,
  required Directory directory,
  bool Function()? reduceMotion,
}) async {
  final identity = PracticeIdentityStore(directory);
  await identity.load();
  final controller = TournamentController(
    config: const UatConfig(
      baseUrl: 'http://127.0.0.1',
      bearer: 'Bearer test',
      playerLabel: 'anim',
    ),
    api: api,
    stateDirectory: directory,
    identity: identity,
    haptics: const SilentTournamentHaptics(),
    reduceMotion: reduceMotion,
  );
  await controller.start();
  await controller.resume();
  return controller;
}

ScriptedUatApi _boardApi({
  required Object Function() initialState,
  required Object Function() finalState,
  required int Function() commandStatus,
  Map<String, Object?> Function(int posts)? commandBody,
  bool awaitAdvanceAfter = false,
  bool resultsPublishedAfter = false,
  int ordinal = 1,
}) {
  var posts = 0;
  return ScriptedUatApi((method, path, body) async {
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
      final after = posts > 0;
      return UatHttpResult(200, {
        'ordinal': ordinal,
        'ordinalLabel': ordinal == 6 ? 'H1' : 'E$ordinal',
        'seriesScore': after ? 300 : 0,
        'score': after ? 300 : 0,
        'awaitAdvance': after && awaitAdvanceAfter,
        'resultsPublished': after && resultsPublishedAfter,
        'status': after && resultsPublishedAfter ? 'COMPLETED' : 'ACTIVE',
        'boardRevision': after ? 2 : 1,
        'writerGeneration': 1,
        'idleDeadlineAtMs': 5000,
        'serverNowMs': 1000,
        'state': after ? finalState() : initialState(),
      });
    }
    if (path.endsWith('/results')) {
      return const UatHttpResult(200, {
        'all': true,
        'onTimeAwarded': true,
      });
    }
    if (path.endsWith('/commands')) {
      posts += 1;
      final status = commandStatus();
      if (status == 200) {
        return UatHttpResult(200, commandBody?.call(posts) ?? const {'ok': true});
      }
      if (status == 401) {
        return const UatHttpResult(401, {'error': 'UNAUTHENTICATED'});
      }
      if (status == 409) {
        return const UatHttpResult(409, {'error': 'WRITER_NOT_AUTHORIZED'});
      }
      return UatHttpResult(status, {'error': 'REQUEST_FAILED'});
    }
    return const UatHttpResult(404, {'error': 'NOT_FOUND'});
  });
}

Future<void> _awaitMoveSettled(TournamentController controller) async {
  // Authoritative tap is async; drain without testWidgets FakeAsync traps.
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(Duration.zero);
    if (!controller.moveInFlight &&
        controller.session.view.phase != GameScreenPhase.resolving) {
      // Rejection / mismatch settled.
      return;
    }
    if (!controller.moveInFlight &&
        controller.session.view.activeScript != null) {
      return;
    }
    if (!controller.moveInFlight &&
        controller.awaitingResolutionNavigation &&
        controller.session.view.phase != GameScreenPhase.resolving) {
      return;
    }
  }
}

void main() {
  test('authoritative single-wave arms the same AnimationScript as Practice', () {
    final resolved = _localResolve('V3-02-single-wave.json');
    final session = GameSession();
    session.showAuthoritative(resolved.initial);
    final applied = session.applyAuthoritativeResolution(
      preState: resolved.initial,
      offerIndex: resolved.offer,
      tap: resolved.tap,
      authoritative: resolved.applied.finalState,
    );
    expect(applied, isNotNull);
    expect(applied!.scoreDelta, resolved.applied.scoreDelta);
    expect(session.view.phase, GameScreenPhase.resolving);
    expect(session.view.activeScript, isNotNull);
    final steps = buildAnimationSteps(session.view.activeScript!);
    expect(steps.first.kind, AnimationStepKind.place);
    expect(steps.where((s) => s.kind == AnimationStepKind.clearWave), isNotEmpty);
    expect(steps.last.kind, AnimationStepKind.settle);
    expect(session.view.score, resolved.applied.finalState.score);
  });

  test('authoritative multi-wave cascade keeps Practice step sequencing', () {
    final resolved = _localResolve('V3-03-multi-wave.json');
    expect(resolved.applied.waves.length, greaterThan(1));
    final session = GameSession();
    session.showAuthoritative(resolved.initial);
    final applied = session.applyAuthoritativeResolution(
      preState: resolved.initial,
      offerIndex: resolved.offer,
      tap: resolved.tap,
      authoritative: resolved.applied.finalState,
    );
    expect(applied, isNotNull);
    expect(applied!.waves.length, resolved.applied.waves.length);
    final steps = buildAnimationSteps(session.view.activeScript!);
    final clears = steps
        .where((s) => s.kind == AnimationStepKind.clearWave)
        .length;
    expect(clears, resolved.applied.waves.length);
  });

  test('mismatched authoritative state settles without success animation', () {
    final resolved = _localResolve('V3-02-single-wave.json');
    final session = GameSession();
    session.showAuthoritative(resolved.initial);
    final forged = parseGameState({
      ...resolved.applied.finalState.toJson(),
      'score': resolved.applied.finalState.score + 99,
    });
    final applied = session.applyAuthoritativeResolution(
      preState: resolved.initial,
      offerIndex: resolved.offer,
      tap: resolved.tap,
      authoritative: forged,
    );
    expect(applied, isNull);
    expect(session.view.activeScript, isNull);
    expect(session.view.phase, isNot(GameScreenPhase.resolving));
    expect(session.view.score, forged.score);
  });

  test(
    'challenge completion waits for resolution + 420ms before Transition',
    () async {
      final resolved = _localResolve('V3-02-single-wave.json');
      final directory = Directory.systemTemp.createTempSync('pzd-anim-trans');
      addTearDown(() {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });
      final api = _boardApi(
        initialState: () => resolved.initial.toJson(),
        finalState: () => resolved.applied.finalState.toJson(),
        commandStatus: () => 200,
        awaitAdvanceAfter: true,
      );
      final controller = await _boot(api: api, directory: directory);
      addTearDown(controller.dispose);

      controller.session.selectOffer(resolved.offer);
      expect(controller.session.submitTap(resolved.tap), isTrue);
      await _awaitMoveSettled(controller);

      expect(controller.route.place, TournamentPlace.playing);
      expect(controller.session.view.phase, GameScreenPhase.resolving);
      expect(controller.session.view.activeScript, isNotNull);
      expect(controller.scoreDelta, greaterThan(0));

      final script = controller.session.view.activeScript!;
      controller.session.completeResolution(
        generation: script.generation,
        resolutionId: script.resolutionId,
      );
      expect(controller.route.place, TournamentPlace.playing);

      await Future<void>.delayed(kResolutionCompletionBeat);
      // Allow the Timer callback microtask to run.
      await Future<void>.delayed(Duration.zero);
      expect(controller.route.place, TournamentPlace.transition);
    },
  );

  test('sixth challenge completion waits before Results', () async {
    final resolved = _localResolve('V3-02-single-wave.json');
    final directory = Directory.systemTemp.createTempSync('pzd-anim-results');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final api = _boardApi(
      initialState: () => resolved.initial.toJson(),
      finalState: () => resolved.applied.finalState.toJson(),
      commandStatus: () => 200,
      resultsPublishedAfter: true,
      ordinal: 6,
    );
    final controller = await _boot(api: api, directory: directory);
    addTearDown(controller.dispose);

    controller.session.selectOffer(resolved.offer);
    expect(controller.session.submitTap(resolved.tap), isTrue);
    await _awaitMoveSettled(controller);
    expect(controller.route.place, TournamentPlace.playing);

    final script = controller.session.view.activeScript!;
    controller.session.completeResolution(
      generation: script.generation,
      resolutionId: script.resolutionId,
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(controller.route.place, TournamentPlace.playing);

    await Future<void>.delayed(kResolutionCompletionBeat);
    await Future<void>.delayed(Duration.zero);
    expect(controller.route.place, TournamentPlace.results);
  });

  test('reduce motion skips the 420ms beat', () async {
    final resolved = _localResolve('V3-02-single-wave.json');
    final directory = Directory.systemTemp.createTempSync('pzd-anim-rm');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final api = _boardApi(
      initialState: () => resolved.initial.toJson(),
      finalState: () => resolved.applied.finalState.toJson(),
      commandStatus: () => 200,
      awaitAdvanceAfter: true,
    );
    final controller = await _boot(
      api: api,
      directory: directory,
      reduceMotion: () => true,
    );
    addTearDown(controller.dispose);

    controller.session.selectOffer(resolved.offer);
    expect(controller.session.submitTap(resolved.tap), isTrue);
    await _awaitMoveSettled(controller);
    final script = controller.session.view.activeScript;
    if (script != null) {
      controller.session.completeResolution(
        generation: script.generation,
        resolutionId: script.resolutionId,
      );
    }
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(controller.route.place, TournamentPlace.transition);
  });

  test('HTTP 401 does not arm a success animation', () async {
    final resolved = _localResolve('V3-02-single-wave.json');
    final directory = Directory.systemTemp.createTempSync('pzd-anim-401');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final api = _boardApi(
      initialState: () => resolved.initial.toJson(),
      finalState: () => resolved.applied.finalState.toJson(),
      commandStatus: () => 401,
    );
    final controller = await _boot(api: api, directory: directory);
    addTearDown(controller.dispose);

    controller.session.selectOffer(resolved.offer);
    expect(controller.session.submitTap(resolved.tap), isTrue);
    await _awaitMoveSettled(controller);
    expect(controller.session.view.activeScript, isNull);
    expect(controller.session.view.phase, isNot(GameScreenPhase.resolving));
    expect(controller.scoreDelta, isNull);
  });

  test('HTTP 409 writer fence does not arm a success animation', () async {
    final resolved = _localResolve('V3-02-single-wave.json');
    final directory = Directory.systemTemp.createTempSync('pzd-anim-409');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final api = _boardApi(
      initialState: () => resolved.initial.toJson(),
      finalState: () => resolved.applied.finalState.toJson(),
      commandStatus: () => 409,
    );
    final controller = await _boot(api: api, directory: directory);
    addTearDown(controller.dispose);

    controller.session.selectOffer(resolved.offer);
    expect(controller.session.submitTap(resolved.tap), isTrue);
    await _awaitMoveSettled(controller);
    expect(controller.rankedWriterLocked, isTrue);
    expect(controller.session.view.activeScript, isNull);
    expect(controller.session.view.phase, GameScreenPhase.playing);
    expect(controller.scoreDelta, isNull);
  });

  test('stale resolution callback does not double-navigate', () async {
    final resolved = _localResolve('V3-02-single-wave.json');
    final directory = Directory.systemTemp.createTempSync('pzd-anim-stale');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final api = _boardApi(
      initialState: () => resolved.initial.toJson(),
      finalState: () => resolved.applied.finalState.toJson(),
      commandStatus: () => 200,
      awaitAdvanceAfter: true,
    );
    final controller = await _boot(api: api, directory: directory);
    addTearDown(controller.dispose);

    controller.session.selectOffer(resolved.offer);
    expect(controller.session.submitTap(resolved.tap), isTrue);
    await _awaitMoveSettled(controller);
    final script = controller.session.view.activeScript!;
    controller.session.completeResolution(
      generation: script.generation,
      resolutionId: script.resolutionId,
    );
    // Stale duplicate complete is a no-op.
    controller.session.completeResolution(
      generation: script.generation,
      resolutionId: script.resolutionId,
    );
    await Future<void>.delayed(kResolutionCompletionBeat);
    await Future<void>.delayed(Duration.zero);
    expect(controller.route.place, TournamentPlace.transition);
    // Further beats must not bounce the route.
    await Future<void>.delayed(kResolutionCompletionBeat);
    await Future<void>.delayed(Duration.zero);
    expect(controller.route.place, TournamentPlace.transition);
  });

  test('zero scoreDelta move does not fabricate a bonus', () {
    final session = GameSession();
    final generated =
        generateChallenge(
              ChallengeGenerationConfig.profile(DifficultyProfile.easy),
              kUatChallengeSeed,
            )
            as GeneratedChallenge;
    MoveApplied? zero;
    Coordinate? tap;
    var offer = 0;
    outer:
    for (var o = 0; o < 3; o++) {
      if (!generated.state.offers[o].isSelectable) continue;
      for (var r = 0; r < generated.state.boardSize; r++) {
        for (var c = 0; c < generated.state.boardSize; c++) {
          final coord = Coordinate(row: r, column: c);
          if (generated.state.cells[r][c] != null) continue;
          if (generated.state.blocked.contains(coord)) continue;
          final result = applyMove(
            generated.state,
            Move(offerIndex: o, tap: coord),
          );
          if (result is MoveApplied && result.scoreDelta == 0) {
            zero = result;
            tap = coord;
            offer = o;
            break outer;
          }
        }
      }
    }
    expect(zero, isNotNull);
    session.showAuthoritative(generated.state);
    final applied = session.applyAuthoritativeResolution(
      preState: generated.state,
      offerIndex: offer,
      tap: tap!,
      authoritative: zero!.finalState,
    );
    expect(applied, isNotNull);
    expect(applied!.scoreDelta, 0);
    expect(session.view.activeScript!.applied.scoreDelta, 0);
  });
}
