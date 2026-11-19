import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_uat_app.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';

import 'tournament_command_test.dart' show ScriptedUatApi;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sound and haptics move to Settings and persist', (tester) async {
    final directory = Directory.systemTemp.createTempSync('pzd42-settings');
    final api = ScriptedUatApi((method, path, body) async {
      if (method == 'POST' && path.endsWith('/session')) {
        return const UatHttpResult(201, {'sessionSecret': 'secret'});
      }
      if (path.endsWith('/claims/daily')) {
        return const UatHttpResult(201, {
          'seriesId': '77777777-7777-4777-8777-777777777777',
          'status': 'ACTIVE',
          'original': true,
        });
      }
      if (path.endsWith('/board')) {
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

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> pump() {
      return tester.pumpWidget(
        TournamentUatApp(
          config: const UatConfig(baseUrl: 'http://127.0.0.1', bearer: 'Bearer test', playerLabel: 'settings'),
          api: api,
          stateDirectory: directory,
          haptics: const SilentTournamentHaptics(),
        ),
      );
    }

    await pump();
    await _pumpFrames(tester);
    expect(find.byType(SwitchListTile), findsNothing);
    await tester.tap(find.byKey(const Key('settings')));
    await _pumpFrames(tester);
    expect(find.text('Sounds for placements, clears, and results.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-sound')));
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const Key('settings-haptics')));
    await _pumpFrames(tester);

    final saved = jsonDecode(File('${directory.path}/pzd-settings.json').readAsStringSync()) as Map;
    expect(saved['sound'], isFalse);
    expect(saved['haptics'], isFalse);

    await tester.tap(find.byKey(const Key('nav-back')));
    await _pumpFrames(tester);
    expect(find.byKey(const Key('home-title')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await pump();
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const Key('settings')));
    await _pumpFrames(tester);
    final sound = tester.widget<SwitchListTile>(find.byKey(const Key('settings-sound')));
    final haptics = tester.widget<SwitchListTile>(find.byKey(const Key('settings-haptics')));
    expect(sound.value, isFalse);
    expect(haptics.value, isFalse);
  });
}

Future<void> _pumpFrames(WidgetTester tester, [int frames = 20]) async {
  await tester.pump();
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

