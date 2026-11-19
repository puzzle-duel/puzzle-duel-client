import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/tournament/practice_store.dart';
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

  testWidgets('Home opens Profile and back returns without stacking', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-profile-nav');
    final api = _api();
    await _pumpHome(tester, api, directory);

    await tester.tap(find.byKey(const Key('profile')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-header')), findsOneWidget);
    expect(find.byKey(const Key('profile-best-easy')), findsOneWidget);
    expect(find.byKey(const Key('profile-best-medium')), findsOneWidget);
    expect(find.byKey(const Key('profile-best-hard')), findsOneWidget);
    expect(find.text('Henüz rekorun yok.'), findsNothing);
    expect(find.text('No record yet.'), findsWidgets);

    await tester.tap(find.byKey(const Key('nav-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile')), findsOneWidget);
    expect(find.byKey(const Key('profile-header')), findsNothing);

    await tester.tap(find.byKey(const Key('profile')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-header')), findsOneWidget);
    await tester.tap(find.byKey(const Key('nav-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-header')), findsNothing);
  });

  testWidgets('shows personal bests, locked badge, and offline badge retry', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-profile-data');
    final store = PracticeStore(directory, playerScope: 'profile');
    store.append(
      PracticeRecord(
        sessionId: 'p1',
        difficulty: 'easy',
        rulesVersion: 'core-001.v2',
        generatorVersion: 'gen-001.v1',
        seed: 1,
        score: 42,
        terminalReason: 'move_limit_reached',
        completedAt: '2026-11-18T10:00:00.000Z',
        moveCount: 15,
      ),
    );

    final api = ScriptedUatApi((method, path, body) async {
      if (path == '/v1/tournament/session' && method == 'POST') {
        return const UatHttpResult(201, {
          'sessionSecret': 'secret',
          'sessionId': 's1',
        });
      }
      if (path == '/v1/tournament/claims/daily' && method == 'POST') {
        return const UatHttpResult(200, {
          'seriesId': '11111111-1111-4111-8111-111111111111',
          'originalUtcDate': '2026-11-19',
          'status': 'ACTIVE',
          'original': false,
          'writerGeneration': 1,
        });
      }
      if (path.startsWith('/v1/tournament/series/') && method == 'GET') {
        return const UatHttpResult(200, {
          'seriesId': '11111111-1111-4111-8111-111111111111',
          'status': 'ACTIVE',
          'boardRevision': 1,
        });
      }
      if (path == '/v1/tournament/me/badges') {
        return const UatHttpResult(0, {'error': 'OFFLINE'});
      }
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });

    await _pumpHome(tester, api, directory);
    await tester.tap(find.byKey(const Key('profile')));
    await tester.pumpAndSettle();

    expect(find.textContaining('42'), findsWidgets);
    expect(find.text('No record yet.'), findsNWidgets(2));
    expect(find.byKey(const Key('badge-status-banner')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('badge-tile-on_time')),
      200,
      scrollable: find.byType(Scrollable).hitTestable(),
    );
    expect(find.byKey(const Key('badge-tile-on_time')), findsOneWidget);
    expect(find.text('Locked'), findsWidgets);

    await tester.tap(find.byKey(const Key('badge-tile-on_time')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('badge-detail-title')), findsOneWidget);
    expect(find.textContaining('Server-authoritative'), findsOneWidget);
    await tester.tap(find.byKey(const Key('badge-detail-close')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('badge-retry')),
      200,
      scrollable: find.byType(Scrollable).hitTestable(),
    );
    await tester.tap(find.byKey(const Key('badge-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('badge-status-banner')), findsOneWidget);
  });

  testWidgets('earned On-Time badge renders verified count', (tester) async {
    final directory = Directory.systemTemp.createTempSync(
      'pzd43-profile-badge',
    );
    final api = ScriptedUatApi((method, path, body) async {
      if (path == '/v1/tournament/session' && method == 'POST') {
        return const UatHttpResult(201, {
          'sessionSecret': 'secret',
          'sessionId': 's1',
        });
      }
      if (path == '/v1/tournament/claims/daily' && method == 'POST') {
        return const UatHttpResult(200, {
          'seriesId': '11111111-1111-4111-8111-111111111111',
          'originalUtcDate': '2026-11-19',
          'status': 'ACTIVE',
          'original': false,
          'writerGeneration': 1,
        });
      }
      if (path.startsWith('/v1/tournament/series/') && method == 'GET') {
        return const UatHttpResult(200, {
          'seriesId': '11111111-1111-4111-8111-111111111111',
          'status': 'ACTIVE',
          'boardRevision': 1,
        });
      }
      if (path == '/v1/tournament/me/badges') {
        return const UatHttpResult(200, {
          'playerScoped': true,
          'catalogVersion': 1,
          'badges': [
            {
              'badgeId': 'on_time',
              'earnedCount': 2,
              'lastEarnedAt': '2026-11-18',
              'repeatable': true,
              'provenance': 'f2b_publication',
              'grants': [],
            },
          ],
        });
      }
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });

    await _pumpHome(tester, api, directory, locale: const Locale('tr'));
    await tester.tap(find.byKey(const Key('profile')));
    await tester.pumpAndSettle();
    expect(find.text('Profil'), findsWidgets);
    expect(find.text('2 kez kazanıldı'), findsOneWidget);
    expect(find.text('Henüz rekorun yok.'), findsWidgets);
  });

  testWidgets('large text keeps profile cards reachable', (tester) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-profile-a11y');
    await _pumpHome(
      tester,
      _api(),
      directory,
      textScaler: const TextScaler.linear(1.6),
      surfaceSize: const Size(320, 700),
    );
    await tester.tap(find.byKey(const Key('profile')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('profile-best-hard')),
      200,
      scrollable: find.byType(Scrollable).hitTestable(),
    );
    expect(find.byKey(const Key('profile-best-hard')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('badge-grid')),
      200,
      scrollable: find.byType(Scrollable).hitTestable(),
    );
    expect(find.byKey(const Key('badge-grid')), findsOneWidget);
  });
}

ScriptedUatApi _api() {
  return ScriptedUatApi((method, path, body) async {
    if (path == '/v1/tournament/session' && method == 'POST') {
      return const UatHttpResult(201, {
        'sessionSecret': 'secret',
        'sessionId': 's1',
      });
    }
    if (path == '/v1/tournament/claims/daily' && method == 'POST') {
      return const UatHttpResult(200, {
        'seriesId': '11111111-1111-4111-8111-111111111111',
        'originalUtcDate': '2026-11-19',
        'status': 'ACTIVE',
        'original': false,
        'writerGeneration': 1,
      });
    }
    if (path.startsWith('/v1/tournament/series/') && method == 'GET') {
      return const UatHttpResult(200, {
        'seriesId': '11111111-1111-4111-8111-111111111111',
        'status': 'ACTIVE',
        'boardRevision': 1,
      });
    }
    if (path == '/v1/tournament/me/badges') {
      return const UatHttpResult(200, {
        'playerScoped': true,
        'catalogVersion': 1,
        'badges': [
          {
            'badgeId': 'on_time',
            'earnedCount': 0,
            'lastEarnedAt': null,
            'repeatable': true,
            'provenance': 'f2b_publication',
            'grants': [],
          },
        ],
      });
    }
    return const UatHttpResult(404, {'error': 'NOT_FOUND'});
  });
}

Future<void> _pumpHome(
  WidgetTester tester,
  UatApi api,
  Directory directory, {
  Locale? locale,
  TextScaler? textScaler,
  Size surfaceSize = const Size(390, 844),
}) async {
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    TournamentUatApp(
      config: const UatConfig(
        baseUrl: 'http://127.0.0.1',
        bearer: 'Bearer test',
        playerLabel: 'profile',
      ),
      api: api,
      stateDirectory: directory,
      haptics: const SilentTournamentHaptics(),
      locale: locale,
      textScaler: textScaler,
    ),
  );
  await tester.pumpAndSettle();
}
