import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/presentation/audio/game_sfx.dart';
import 'package:puzzle_duel_mobile/tournament/local_settings.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_controller.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

import 'tournament_command_test.dart' show ScriptedUatApi;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an accepted scoring move plays one clear cue and one haptic', () async {
    final feel = await _play(score: 40, status: 200);
    expect(feel.sfx.events, [GameSfxEvent.clear]);
    expect(feel.haptics.events, ['cleared']);
    expect(feel.controller.scoreDelta, 40);
  });

  test('a zero-score acceptance plays placement once and shows no score banner', () async {
    final feel = await _play(score: 0, status: 200);
    expect(feel.sfx.events, [GameSfxEvent.place]);
    expect(feel.haptics.events, ['accepted']);
    expect(feel.controller.scoreDelta, isNull);
  });

  test('a rejection is one sound and does not play an acceptance', () async {
    final feel = await _play(score: 0, status: 400, error: 'ILLEGAL_MOVE');
    expect(feel.sfx.events, [GameSfxEvent.reject]);
    expect(feel.haptics.events, ['rejected']);
    expect(feel.controller.scoreDelta, isNull);
  });

  test('muted sound and disabled haptics suppress both', () async {
    final feel = await _play(score: 40, status: 200, sound: false, haptics: false);
    expect(feel.sfx.events, isEmpty);
    expect(feel.haptics.events, isEmpty);
  });

  test('selection is one event and a later rebuild does not replay it', () async {
    final feel = await _play(score: 0, status: 200, submit: false);
    feel.controller.noteSelection();
    feel.controller.notifyListeners();
    expect(feel.sfx.events, [GameSfxEvent.place]);
    expect(feel.haptics.events, ['selection']);
  });

  test('device haptics honor the preference and reduced-motion gate', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add('${call.method}:${call.arguments}');
        return null;
      },
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    final off = DeviceTournamentHaptics(enabled: () => false, successAllowed: () => true);
    off.selection();
    off.cleared();
    expect(calls, isEmpty);

    final quiet = DeviceTournamentHaptics(enabled: () => true, successAllowed: () => false);
    quiet.accepted();
    quiet.cleared();
    quiet.completed();
    expect(calls.where((call) => call.contains('mediumImpact') || call.contains('heavyImpact')), isEmpty);
    expect(calls.where((call) => call.contains('lightImpact')), hasLength(1));
  });
}

final class _RecordingHaptics implements TournamentHaptics {
  final events = <String>[];

  @override
  void selection() => events.add('selection');

  @override
  void accepted() => events.add('accepted');

  @override
  void rejected() => events.add('rejected');

  @override
  void cleared() => events.add('cleared');

  @override
  void completed() => events.add('completed');
}

final class _Feel {
  const _Feel(this.controller, this.sfx, this.haptics);

  final TournamentController controller;
  final RecordingGameSfx sfx;
  final _RecordingHaptics haptics;
}

Future<_Feel> _play({
  required int score,
  required int status,
  String? error,
  bool sound = true,
  bool haptics = true,
  bool submit = true,
}) async {
  final document =
      jsonDecode(File('test/tournament/fixtures/V3-02-single-wave.json').readAsStringSync()) as Map<String, Object?>;
  var served = 0;
  final api = ScriptedUatApi((method, path, body) async {
    if (method == 'POST' && path.endsWith('/session')) {
      return const UatHttpResult(201, {'sessionSecret': 'secret'});
    }
    if (path.endsWith('/claims/daily')) {
      return const UatHttpResult(201, {
        'seriesId': '11111111-1111-4111-8111-111111111111',
        'status': 'ACTIVE',
        'original': true,
      });
    }
    if (path.endsWith('/board')) {
      return UatHttpResult(200, {
        'ordinal': 1,
        'ordinalLabel': 'E1',
        'seriesScore': served,
        'score': served,
        'awaitAdvance': false,
        'resultsPublished': false,
        'boardRevision': 1,
        'writerGeneration': 1,
        'state': document['initialState'],
      });
    }
    if (path.endsWith('/commands')) {
      if (status == 200) served = score;
      return UatHttpResult(status, {'error': error});
    }
    return const UatHttpResult(404, {'error': 'NOT_FOUND'});
  });
  final sfx = RecordingGameSfx();
  final recorded = _RecordingHaptics();
  final directory = Directory.systemTemp.createTempSync('pzd42-feel');
  final settings = LocalSettings.load(directory)
    ..sound = sound
    ..haptics = haptics;
  final controller = TournamentController(
    config: const UatConfig(baseUrl: 'http://127.0.0.1', bearer: 'Bearer test', playerLabel: 'feel'),
    api: api,
    stateDirectory: directory,
    sfx: sfx,
    settings: settings,
    haptics: recorded,
  );
  await controller.start();
  await controller.resume();
  if (submit) {
    controller.session.selectOffer(0);
    expect(controller.session.submitTap(Coordinate(row: 0, column: 2)), isTrue);
    await pumpEventQueue();
    await pumpEventQueue();
  }
  return _Feel(controller, sfx, recorded);
}
