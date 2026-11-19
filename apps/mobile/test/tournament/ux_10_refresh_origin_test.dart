import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/theme/game_tokens.dart';
import 'package:puzzle_duel_mobile/tournament/practice_identity.dart';
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

  testWidgets('successful startup shows no informational banner', (tester) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-ux10-ok');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final api = ScriptedUatApi((method, path, body) async => _ok(method, path));
    await _pumpHome(tester, api, directory);
    expect(find.byKey(const Key('tournament-status-info')), findsNothing);
    expect(find.byKey(const Key('tournament-status')), findsNothing);
    expect(find.byKey(const Key('practice')), findsOneWidget);
  });

  testWidgets('startup syncing stays silent (no blue loading toast)', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-ux10-sync');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final gate = Completer<void>();
    final api = ScriptedUatApi((method, path, body) async {
      await gate.future;
      return _ok(method, path);
    });
    await _pumpHome(tester, api, directory);
    expect(find.byKey(const Key('tournament-status-info')), findsNothing);
    expect(find.byKey(const Key('home-daily-card')), findsOneWidget);
    gate.complete();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const Key('tournament-status-info')), findsNothing);
  });

  testWidgets('startup failure shows red error then offline icon', (tester) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-ux10-fail');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final api = ScriptedUatApi(
      (_, _, _) async => const UatHttpResult(0, {'error': 'OFFLINE'}),
    );
    await _pumpHome(tester, api, directory);
    await _waitFor(tester, find.text('No internet connection.'));
    expect(find.byKey(const Key('tournament-status-error')), findsOneWidget);
    expect(_bannerAccent(tester), GameTokens.notifyError);
    expect(find.byKey(const Key('daily-offline-icon')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 4500));
    await tester.pump();
    expect(find.byKey(const Key('tournament-status')), findsNothing);
    expect(find.byKey(const Key('daily-offline-icon')), findsOneWidget);
    expect(find.byKey(const Key('practice')), findsOneWidget);
  });

  testWidgets('pull-to-refresh shows blue completion without loading toast', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-ux10-pull');
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
    // UX-11: native spinner only while refreshing — no blue loading toast.
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
    expect(find.byKey(const Key('daily-offline-icon')), findsNothing);
  });

  testWidgets('failed pull shows red error banner', (tester) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-ux10-pull-err');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    var online = true;
    final api = ScriptedUatApi((method, path, body) async {
      if (!online) return const UatHttpResult(0, {'error': 'TIMEOUT'});
      return _ok(method, path);
    });
    await _pumpHome(tester, api, directory);
    online = false;
    final refresh = tester.widget<RefreshIndicator>(
      find.byKey(const Key('home-refresh')),
    );
    await refresh.onRefresh();
    await tester.pump();
    expect(find.textContaining('timed out'), findsOneWidget);
    expect(find.byKey(const Key('tournament-status-error')), findsOneWidget);
  });

  testWidgets('pull joining in-flight startup upgrades to blue feedback', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-ux10-join');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final gate = Completer<void>();
    var sessions = 0;
    final api = ScriptedUatApi((method, path, body) async {
      if (path.endsWith('/session') && method == 'POST') {
        sessions += 1;
        await gate.future;
        return const UatHttpResult(201, {
          'playerId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'sessionSecret': 'secret',
        });
      }
      return _ok(method, path);
    });
    await _pumpHome(tester, api, directory);
    expect(find.byKey(const Key('tournament-status-info')), findsNothing);
    expect(sessions, 1);
    final refresh = tester.widget<RefreshIndicator>(
      find.byKey(const Key('home-refresh')),
    );
    final joined = refresh.onRefresh();
    await tester.pump();
    expect(find.byKey(const Key('tournament-status-info')), findsNothing);
    expect(sessions, 1);
    gate.complete();
    await joined;
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const Key('tournament-status')),
        matching: find.text('Tournament info updated.'),
      ),
      findsOneWidget,
    );
    expect(sessions, 1);
  });

  test('refresh origin gates info banners', () async {
    final directory = Directory.systemTemp.createTempSync('pzd43-ux10-origin');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final gate = Completer<void>();
    final api = ScriptedUatApi((method, path, body) async {
      if (path.endsWith('/session') && method == 'POST') {
        await gate.future;
      }
      return _ok(method, path);
    });
    final identity = PracticeIdentityStore(directory);
    await identity.load();
    final controller = TournamentController(
      config: const UatConfig(
        baseUrl: 'http://127.0.0.1',
        bearer: 'Bearer test',
        playerLabel: 'ux10-origin',
      ),
      api: api,
      stateDirectory: directory,
      identity: identity,
      haptics: const SilentTournamentHaptics(),
    );
    addTearDown(controller.dispose);
    await controller.beginLocal();
    final background = controller.refreshTournament(
      origin: TournamentRefreshOrigin.background,
    );
    expect(controller.tournamentInfoBannersEnabled, isFalse);
    expect(controller.tournamentRefreshOrigin, TournamentRefreshOrigin.background);
    // Pull joining background upgrades visible feedback without a second HTTP.
    final joined = controller.refreshTournament(
      origin: TournamentRefreshOrigin.pullToRefresh,
    );
    expect(controller.tournamentInfoBannersEnabled, isTrue);
    expect(identical(background, joined), isTrue);
    gate.complete();
    await joined;
    expect(controller.tournamentReady, isTrue);

    final silent = controller.refreshTournament(
      origin: TournamentRefreshOrigin.background,
    );
    expect(controller.tournamentInfoBannersEnabled, isFalse);
    await silent;
    expect(controller.tournamentInfoBannersEnabled, isFalse);
  });

  test('writer copy is not a connectivity message', () {
    const en = TournamentCopy(Locale('en'));
    const tr = TournamentCopy(Locale('tr'));
    expect(
      en.writerBlocked,
      "Today's challenge is open in another session. Continue from the session where you started.",
    );
    expect(
      tr.writerBlocked,
      'Günlük mücadele başka bir oturumda açık. Başladığın oturumdan devam edebilirsin.',
    );
    for (final copy in [en, tr]) {
      final text = copy.forError('WRITER_NOT_AUTHORIZED').toLowerCase();
      expect(text.contains('internet'), isFalse);
      expect(text.contains('timed out'), isFalse);
      expect(text.contains('bağlantı yok'), isFalse);
      expect(text.contains('writer_not_authorized'), isFalse);
      expect(copy.connectionUnavailable.toLowerCase().contains('internet') ||
          copy.connectionUnavailable.contains('bağlantı'), isTrue);
    }
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

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 80; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsOneWidget);
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
        playerLabel: 'ux10',
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
