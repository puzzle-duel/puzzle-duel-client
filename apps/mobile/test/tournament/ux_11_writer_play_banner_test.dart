import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/theme/game_tokens.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_copy.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_uat_app.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';

import 'tournament_command_test.dart' show ScriptedUatApi;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .accessibilityFeaturesTestValue = FakeAccessibilityFeatures(
      disableAnimations: true,
      reduceMotion: true,
    );
  });

  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
        .clearAccessibilityFeaturesTestValue();
  });

  testWidgets('ranked 409 shows floating red banner without inline clip text', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-ux11-writer');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final document = jsonDecode(
      File('test/tournament/fixtures/V3-02-single-wave.json').readAsStringSync(),
    ) as Map<String, Object?>;
    var commands = 0;
    final api = ScriptedUatApi((method, path, body) async {
      if (path.endsWith('/session') && method == 'POST') {
        return const UatHttpResult(201, {
          'playerId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'sessionSecret': 'secret',
        });
      }
      if (path.endsWith('/claims/daily')) {
        return const UatHttpResult(201, {
          'seriesId': 'series-writer',
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
          'boardRevision': 1,
          'writerGeneration': 1,
          'state': document['initialState'],
        });
      }
      if (path.endsWith('/commands')) {
        commands += 1;
        return const UatHttpResult(409, {'error': 'WRITER_NOT_AUTHORIZED'});
      }
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });

    await _pumpPlay(tester, api, directory);
    expect(find.byKey(const Key('play-board')), findsOneWidget);
    final boardBefore = tester.getTopLeft(find.byKey(const Key('play-board')));
    final offersBefore =
        tester.getTopLeft(find.byKey(const Key('offer-tray-frame')));

    await tester.tap(find.byKey(const ValueKey('offer-slot-0')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('board-ink-0-2')));
    await tester.pump();
    for (var i = 0; i < 40; i++) {
      if (find.byKey(const Key('tournament-status-error')).evaluate().isNotEmpty) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 50));
    }

    const message =
        "Today's challenge is open in another session. Continue from the session where you started.";
    expect(find.byKey(const Key('tournament-status-error')), findsOneWidget);
    expect(_bannerAccent(tester), GameTokens.notifyError);
    expect(
      find.descendant(
        of: find.byKey(const Key('tournament-status')),
        matching: find.text(message),
      ),
      findsOneWidget,
    );
    expect(find.text('WRITER_NOT_AUTHORIZED'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('play-feedback')),
        matching: find.textContaining('challenge is open'),
      ),
      findsNothing,
    );
    expect(commands, 1);
    expect(tester.getTopLeft(find.byKey(const Key('play-board'))), boardBefore);
    expect(
      tester.getTopLeft(find.byKey(const Key('offer-tray-frame'))),
      offersBefore,
    );

    // Second interaction must not spam network or banners.
    await tester.tap(find.byKey(const ValueKey('offer-slot-0')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('board-ink-0-2')));
    await tester.pump();
    expect(commands, 1);
    expect(find.byKey(const Key('tournament-status-error')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 4500));
    await tester.pump();
    expect(find.byKey(const Key('tournament-status')), findsNothing);
    expect(tester.getTopLeft(find.byKey(const Key('play-board'))), boardBefore);
  });

  testWidgets('UX-11 pull shows updated toast without updating loading toast', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-ux11-pull');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final gate = Completer<void>();
    var ready = false;
    final api = ScriptedUatApi((method, path, body) async {
      if (!ready) return const UatHttpResult(0, {'error': 'OFFLINE'});
      if (path.endsWith('/session') && method == 'POST') {
        await gate.future;
      }
      return _ok(method, path);
    });
    await _pumpHome(tester, api, directory);
    await tester.pump(const Duration(milliseconds: 4500));
    await tester.pump();
    ready = true;
    final refresh = tester.widget<RefreshIndicator>(
      find.byKey(const Key('home-refresh')),
    );
    final pending = refresh.onRefresh();
    await tester.pump();
    expect(find.byKey(const Key('tournament-status-info')), findsNothing);
    expect(find.byKey(const Key('tournament-status')), findsNothing);
    gate.complete();
    await pending;
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const Key('tournament-status')),
        matching: find.text('Tournament info updated.'),
      ),
      findsOneWidget,
    );
    expect(_bannerAccent(tester), GameTokens.notifyInfo);
  });

  test('writer copy wraps without raw codes', () {
    const en = TournamentCopy(Locale('en'));
    const tr = TournamentCopy(Locale('tr'));
    expect(en.forError('WRITER_NOT_AUTHORIZED').contains('WRITER'), isFalse);
    expect(tr.forError('WRITER_NOT_AUTHORIZED').contains('WRITER'), isFalse);
    expect(en.writerBlocked.split(' ').length, greaterThan(8));
    expect(tr.writerBlocked.split(' ').length, greaterThan(8));
  });
}

Color _bannerAccent(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find.byKey(const Key('tournament-status')),
  );
  final decoration = box.decoration as BoxDecoration;
  return decoration.border!.top.color.withValues(alpha: 1);
}

UatHttpResult _ok(String method, String path) {
  if (path.endsWith('/session') && method == 'POST') {
    return const UatHttpResult(201, {
      'playerId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'sessionSecret': 'secret',
    });
  }
  if (path.endsWith('/claims/daily')) {
    return const UatHttpResult(201, {
      'seriesId': 'series-1',
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
}

Future<void> _pumpHome(
  WidgetTester tester,
  ScriptedUatApi api,
  Directory directory,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    TournamentUatApp(
      config: const UatConfig(
        baseUrl: 'http://127.0.0.1',
        bearer: 'Bearer test',
        playerLabel: 'ux11',
      ),
      api: api,
      stateDirectory: directory,
      haptics: const SilentTournamentHaptics(),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 60; i++) {
    if (find.byKey(const Key('practice')).evaluate().isNotEmpty) break;
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(find.byKey(const Key('practice')), findsOneWidget);
}

Future<void> _pumpPlay(
  WidgetTester tester,
  ScriptedUatApi api,
  Directory directory,
) async {
  await _pumpHome(tester, api, directory);
  for (var i = 0; i < 80; i++) {
    if (find.byKey(const Key('primary-action')).evaluate().isNotEmpty) break;
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(find.byKey(const Key('primary-action')), findsOneWidget);
  await tester.tap(find.byKey(const Key('primary-action')));
  await tester.pump();
  for (var i = 0; i < 80; i++) {
    if (find.byKey(const Key('play-board')).evaluate().isNotEmpty) break;
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(find.byKey(const Key('play-board')), findsOneWidget);
}
