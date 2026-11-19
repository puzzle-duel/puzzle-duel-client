import 'dart:async';
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

  testWidgets('info banner is blue for syncing and tournament updated', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-ux05f-info');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final gate = Completer<void>();
    final api = ScriptedUatApi((method, path, body) async {
      await gate.future;
      return _ok(method, path);
    });
    await _pumpHome(tester, api, directory);
    gate.complete();
    await _waitFor(tester, find.text('Updating tournament info…'));
    expect(find.byKey(const Key('tournament-status-info')), findsOneWidget);
    expect(find.byKey(const Key('tournament-status-success')), findsNothing);
    expect(_bannerAccent(tester), GameTokens.notifyInfo);

    await _waitFor(tester, find.text('Tournament info updated.'));
    expect(find.byKey(const Key('tournament-status-info')), findsOneWidget);
    expect(find.byKey(const Key('tournament-status-success')), findsNothing);
    expect(_bannerAccent(tester), GameTokens.notifyInfo);
  });

  testWidgets('offline and timeout use red error banners that auto-dismiss', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-ux05f-err');
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
    expect(find.byKey(const Key('tournament-retry')), findsNothing);
    expect(find.byKey(const Key('daily-offline-icon')), findsOneWidget);

    final dailyBefore = tester.getTopLeft(
      find.byKey(const Key('home-daily-card')),
    );
    await tester.pump(const Duration(milliseconds: 3600));
    await tester.pump();
    expect(find.byKey(const Key('tournament-status')), findsNothing);
    expect(find.byKey(const Key('daily-offline-icon')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('home-daily-card'))),
      dailyBefore,
    );
  });

  testWidgets('timeout copy is red and distinct from offline', (tester) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-ux05f-to');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final api = ScriptedUatApi(
      (_, _, _) async => const UatHttpResult(
        0,
        {'error': 'TIMEOUT'},
        category: UatFailureCategory.connectTimeout,
      ),
    );
    await _pumpHome(tester, api, directory);
    await _waitFor(tester, find.text('Connection timed out.'));
    expect(find.byKey(const Key('tournament-status-error')), findsOneWidget);
    expect(find.byKey(const Key('daily-offline-icon')), findsOneWidget);
  });

  testWidgets('Home layout does not shift while banner animates', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-ux05f-shift');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final api = ScriptedUatApi(
      (_, _, _) async => const UatHttpResult(0, {'error': 'OFFLINE'}),
    );
    await _pumpHome(tester, api, directory);
    final title = tester.getTopLeft(find.byKey(const Key('home-title')));
    final daily = tester.getTopLeft(find.byKey(const Key('home-daily-card')));
    final practice = tester.getTopLeft(find.byKey(const Key('practice')));
    await _waitFor(tester, find.byKey(const Key('tournament-status')));
    expect(tester.getTopLeft(find.byKey(const Key('home-title'))), title);
    expect(tester.getTopLeft(find.byKey(const Key('home-daily-card'))), daily);
    expect(tester.getTopLeft(find.byKey(const Key('practice'))), practice);
    await tester.pump(const Duration(milliseconds: 3600));
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(const Key('home-title'))), title);
    expect(tester.getTopLeft(find.byKey(const Key('home-daily-card'))), daily);
  });

  testWidgets('offline icon clears only after authoritative refresh', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-ux05f-icon');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    var online = false;
    final api = ScriptedUatApi((method, path, body) async {
      if (!online) return const UatHttpResult(0, {'error': 'OFFLINE'});
      return _ok(method, path);
    });
    await _pumpHome(tester, api, directory);
    await _waitFor(tester, find.byKey(const Key('daily-offline-icon')));
    await tester.pump(const Duration(milliseconds: 3600));
    await tester.pump();
    expect(find.byKey(const Key('daily-offline-icon')), findsOneWidget);

    online = true;
    await _pullToRefresh(tester);
    for (var i = 0; i < 80; i++) {
      if (find.byKey(const Key('daily-offline-icon')).evaluate().isEmpty) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const Key('daily-offline-icon')), findsNothing);
    expect(find.text('Tournament info updated.'), findsOneWidget);
    expect(find.byKey(const Key('tournament-status-info')), findsOneWidget);
  });

  testWidgets('pull-to-refresh dedupes in-flight tournament refresh', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-ux05f-pull');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    var claims = 0;
    var sessions = 0;
    final gate = Completer<void>();
    final api = ScriptedUatApi((method, path, body) async {
      if (path.endsWith('/session') && method == 'POST') {
        sessions += 1;
        await gate.future;
        return const UatHttpResult(201, {
          'playerId': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
          'sessionSecret': 'secret',
        });
      }
      if (path.endsWith('/claims/daily')) {
        claims += 1;
        return const UatHttpResult(201, {
          'seriesId': 'series-pull',
          'status': 'ACTIVE',
          'original': true,
        });
      }
      return _ok(method, path);
    });
    await _pumpHome(tester, api, directory);
    expect(find.byKey(const Key('home-refresh')), findsOneWidget);
    expect(sessions, 1);
    // First boot refresh still in-flight; extra pulls must join it.
    await _pullToRefresh(tester);
    await _pullToRefresh(tester);
    expect(sessions, 1);
    gate.complete();
    for (var i = 0; i < 80; i++) {
      if (find.text('Tournament info updated.').evaluate().isNotEmpty) break;
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(claims, 1);
    expect(find.byKey(const Key('practice')), findsOneWidget);
  });

  testWidgets('401 is not shown as offline wifi outage', (tester) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-ux05f-401');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final api = ScriptedUatApi((method, path, body) async {
      if (path.endsWith('/session')) {
        return const UatHttpResult(401, {'error': 'UNAUTHENTICATED'});
      }
      return const UatHttpResult(401, {'error': 'UNAUTHENTICATED'});
    });
    await _pumpHome(tester, api, directory);
    await _waitFor(
      tester,
      find.text('Sign in again to update tournament info.'),
    );
    expect(find.byKey(const Key('tournament-status-error')), findsOneWidget);
    expect(find.byKey(const Key('daily-offline-icon')), findsNothing);
    expect(find.text('No internet connection.'), findsNothing);
  });

  testWidgets('failed refresh keeps last-known summary and practice', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-ux05f-keep');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    var online = true;
    final api = ScriptedUatApi((method, path, body) async {
      if (!online) return const UatHttpResult(0, {'error': 'OFFLINE'});
      return _ok(method, path, seriesScore: 1200);
    });
    await _pumpHome(tester, api, directory);
    await _waitFor(tester, find.textContaining('1,200'));
    online = false;
    await _pullToRefresh(tester);
    await _waitFor(tester, find.text('No internet connection.'));
    expect(find.textContaining('1,200'), findsOneWidget);
    expect(find.byKey(const Key('practice')), findsOneWidget);
    expect(find.byKey(const Key('daily-offline-icon')), findsOneWidget);
  });

  test('TR/EN notification copy matches product strings', () {
    const en = TournamentCopy(Locale('en'));
    const tr = TournamentCopy(Locale('tr'));
    expect(en.tournamentSyncing, 'Updating tournament info…');
    expect(en.tournamentRefreshSuccess, 'Tournament info updated.');
    expect(en.connectionUnavailable, 'No internet connection.');
    expect(en.timedOut, 'Connection timed out.');
    expect(en.noConnection, 'No connection');
    expect(tr.tournamentSyncing, 'Turnuva bilgileri güncelleniyor…');
    expect(tr.tournamentRefreshSuccess, 'Turnuva bilgileri güncellendi.');
    expect(tr.connectionUnavailable, 'İnternet bağlantısı yok.');
    expect(tr.timedOut, 'Bağlantı zaman aşımına uğradı.');
    expect(tr.noConnection, 'Bağlantı yok');
    for (final copy in [en, tr]) {
      final blob = [
        copy.tournamentSyncing,
        copy.tournamentRefreshSuccess,
        copy.connectionUnavailable,
        copy.timedOut,
        copy.noConnection,
      ].join(' ').toLowerCase();
      expect(blob.contains('server'), isFalse);
      expect(blob.contains('backend'), isFalse);
      expect(blob.contains('api'), isFalse);
      expect(blob.contains('cache'), isFalse);
      expect(blob.contains('sunucu'), isFalse);
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

UatHttpResult _ok(String method, String path, {int seriesScore = 0}) {
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
    return UatHttpResult(200, {
      'ordinal': 1,
      'ordinalLabel': 'E1',
      'seriesScore': seriesScore,
      'awaitAdvance': false,
      'resultsPublished': false,
      'state': {'turnsUsed': 0, 'moveLimit': 15, 'boardSize': 5},
    });
  }
  return const UatHttpResult(404, {'error': 'NOT_FOUND'});
}

Future<void> _pullToRefresh(WidgetTester tester) async {
  await tester.fling(
    find.byKey(const Key('home-scroll')),
    const Offset(0, 400),
    1000,
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
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
        playerLabel: 'ux05f',
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
