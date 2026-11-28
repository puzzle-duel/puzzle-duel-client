import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/tournament/guest_auth.dart';
import 'package:puzzle_duel_mobile/tournament/local_kv_store.dart';
import 'package:puzzle_duel_mobile/tournament/practice_identity.dart';
import 'package:puzzle_duel_mobile/tournament/practice_store.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_uat_app.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';

import 'tournament_command_test.dart' show ScriptedUatApi;

String _jwt({required String sub, required String accountType}) {
  final header = base64Url
      .encode(utf8.encode(jsonEncode({'alg': 'none'})))
      .replaceAll('=', '');
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'iss': 'https://staging.puzzle-duel.app',
            'aud': 'puzzle-duel-api',
            'sub': sub,
            'account_type': accountType,
            'fid': 'fid',
          }),
        ),
      )
      .replaceAll('=', '');
  return '$header.$payload.sig';
}

final class _MemStore implements GuestCredentialStore {
  String? token;
  @override
  Future<String?> readRefreshToken() async => token;
  @override
  Future<void> writeRefreshToken(String value) async => token = value;
  @override
  Future<void> clearRefreshToken() async => token = null;
  @override
  Future<String?> readPendingRotationId() async => null;
  @override
  Future<void> writePendingRotationId(String id) async {}
  @override
  Future<void> clearPendingRotationId() async {}
  @override
  Future<String?> readPendingLinkProvider() async => null;
  @override
  Future<void> writePendingLinkProvider(String provider) async {}
  @override
  Future<void> clearPendingLinkProvider() async {}
  @override
  Future<String?> readIdentityBinding() async => null;
  @override
  Future<void> writeIdentityBinding(String encoded) async {}
  @override
  Future<void> clearIdentityBinding() async {}
  @override
  Future<String?> readVaultJournal() async => null;
  @override
  Future<void> writeVaultJournal(String encoded) async {}
  @override
  Future<void> clearVaultJournal() async {}
}

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
    await _pumpProfile(tester);
    expect(find.byKey(const Key('profile-header')), findsOneWidget);
    expect(find.byKey(const Key('profile-best-easy')), findsOneWidget);
    expect(find.byKey(const Key('profile-best-medium')), findsOneWidget);
    expect(find.byKey(const Key('profile-best-hard')), findsOneWidget);
    expect(find.text('Henüz rekorun yok.'), findsNothing);
    expect(find.text('No record yet.'), findsWidgets);

    await tester.tap(find.byKey(const Key('nav-back')));
    await _pumpProfile(tester);
    expect(find.byKey(const Key('profile')), findsOneWidget);
    expect(find.byKey(const Key('profile-header')), findsNothing);

    await tester.tap(find.byKey(const Key('profile')));
    await _pumpProfile(tester);
    expect(find.byKey(const Key('profile-header')), findsOneWidget);
    await tester.tap(find.byKey(const Key('nav-back')));
    await _pumpProfile(tester);
    expect(find.byKey(const Key('profile-header')), findsNothing);
  });

  testWidgets('PR01 guest profile has no segmented control (Practice-only)', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'pzd53-profile-guest-segments',
    );
    await _pumpHome(tester, _api(), directory);
    await tester.tap(find.byKey(const Key('profile')));
    await _pumpProfile(tester);
    expect(find.byKey(const Key('profile-records-segment')), findsNothing);
    expect(find.text('Practice records'), findsOneWidget);
    expect(
      find.text(
        'Your best scores from completed practice games on this device.',
      ),
      findsOneWidget,
    );
    expect(find.text('Personal records'), findsNothing);
    expect(find.byKey(const Key('profile-best-easy')), findsOneWidget);
    expect(find.byKey(const Key('profile-best-medium')), findsOneWidget);
    expect(find.byKey(const Key('profile-best-hard')), findsOneWidget);
  });

  testWidgets('PR04 guest TR title and description for practice records', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'pzd53-profile-guest-tr',
    );
    await _pumpHome(tester, _api(), directory, locale: const Locale('tr'));
    await tester.tap(find.byKey(const Key('profile')));
    await _pumpProfile(tester);
    expect(find.byKey(const Key('profile-records-segment')), findsNothing);
    expect(find.text('Pratik rekorları'), findsOneWidget);
    expect(
      find.text('Bu cihazda tamamladığın pratik oyunlarındaki en iyi skorlar.'),
      findsOneWidget,
    );
  });

  testWidgets('shows personal bests, locked badge, and offline badge retry', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd43-profile-data');
    const playerId = '11111111-1111-4111-8111-111111111111';
    final identity = PracticeIdentityStore(directory);
    await identity.load();
    await identity.bindAuthenticatedPlayer(playerId);
    await PracticeStore(
      directory: directory,
      scope: identity.activeScope,
      identity: identity,
    ).append(
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
          'playerId': '11111111-1111-4111-8111-111111111111',
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
    await _pumpProfile(tester);

    expect(find.textContaining('42'), findsWidgets);
    expect(find.text('No record yet.'), findsNWidgets(2));
    expect(
      find.byKey(const Key('badge-status-banner'), skipOffstage: false),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('badge-grid'), skipOffstage: false),
      200,
      scrollable: find.byType(Scrollable).hitTestable(),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('badge-tile-on_time'), skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('Locked', skipOffstage: false), findsWidgets);

    await tester.tap(find.byKey(const Key('badge-tile-on_time')));
    await _pumpProfile(tester);
    expect(find.byKey(const Key('badge-detail-title')), findsOneWidget);
    expect(find.textContaining('Server-authoritative'), findsOneWidget);
    await tester.tap(find.byKey(const Key('badge-detail-close')));
    await _pumpProfile(tester);

    await tester.scrollUntilVisible(
      find.byKey(const Key('badge-retry'), skipOffstage: false),
      200,
      scrollable: find.byType(Scrollable).hitTestable(),
    );
    await tester.tap(find.byKey(const Key('badge-retry')));
    await _pumpProfile(tester);
    expect(
      find.byKey(const Key('badge-status-banner'), skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('earned On-Time badge renders verified count', (tester) async {
    final directory = Directory.systemTemp.createTempSync(
      'pzd43-profile-badge',
    );
    final api = ScriptedUatApi((method, path, body) async {
      if (path == '/v1/tournament/session' && method == 'POST') {
        return const UatHttpResult(201, {
          'playerId': '11111111-1111-4111-8111-111111111111',
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
    await _pumpProfile(tester);
    expect(find.text('Profil'), findsWidgets);
    expect(find.text('2 kez kazanıldı', skipOffstage: false), findsOneWidget);
    expect(find.text('Henüz rekorun yok.', skipOffstage: false), findsWidgets);
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
    await _pumpProfile(tester);
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

  testWidgets(
    'local Practice records render before blocked remote personal-records',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'pzd53-local-first',
      );
      const playerId = '11111111-1111-4111-8111-111111111111';
      final identity = PracticeIdentityStore(directory);
      await identity.load();
      await identity.bindAuthenticatedPlayer(playerId);
      await PracticeStore(
        directory: directory,
        scope: identity.activeScope,
        identity: identity,
      ).append(
        PracticeRecord(
          sessionId: 'local-first',
          difficulty: 'easy',
          rulesVersion: 'core-001.v2',
          generatorVersion: 'gen-001.v1',
          seed: 1,
          score: 77,
          terminalReason: 'move_limit_reached',
          completedAt: '2026-11-27T10:00:00.000Z',
          moveCount: 12,
        ),
      );

      final releasePersonalRecords = Completer<UatHttpResult>();
      final personalRecordsStarted = Completer<void>();
      final api = ScriptedUatApi((method, path, body) async {
        if (path == '/v1/tournament/session' && method == 'POST') {
          return const UatHttpResult(201, {
            'playerId': '11111111-1111-4111-8111-111111111111',
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
        if (path == '/v1/tournament/me/badges' ||
            path == '/v1/profile/me/badges') {
          return const UatHttpResult(200, {
            'playerScoped': true,
            'catalogVersion': 1,
            'badges': <Object>[],
          });
        }
        if (path == '/v1/profile/me/personal-records' && method == 'GET') {
          if (!personalRecordsStarted.isCompleted) {
            personalRecordsStarted.complete();
          }
          return releasePersonalRecords.future;
        }
        if (path.endsWith('/personal-records/practice/sync') &&
            method == 'POST') {
          return releasePersonalRecords.future;
        }
        return const UatHttpResult(404, {'error': 'NOT_FOUND'});
      });

      await _pumpHome(tester, api, directory);
      await tester.tap(find.byKey(const Key('profile')));
      // Local paint must win before the blocked remote resolves.
      var sawLocal = false;
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.textContaining('77').evaluate().isNotEmpty) {
          sawLocal = true;
          break;
        }
      }
      expect(sawLocal, isTrue);
      expect(releasePersonalRecords.isCompleted, isFalse);

      releasePersonalRecords.complete(
        const UatHttpResult(200, {'records': <Object>[], 'schemaReady': true}),
      );
      await _pumpProfile(tester);
      expect(find.textContaining('77'), findsWidgets);
    },
  );

  testWidgets('PR05 verified profile shows All/Practice/Tournament segments', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'pzd53-profile-verified-segments',
    );
    await _pumpHome(
      tester,
      _api(
        personalRecords: const UatHttpResult(200, {
          'schemaReady': true,
          'records': [
            {
              'difficulty': 'easy',
              'source': 'tournament',
              'score': 5500,
              'rulesVersion': 'core-001.v3',
              'generatorVersion': 'gen-001.v1',
              'achievedAt': '2026-11-20T10:00:00.000Z',
              'provenance': 'tournament_f2b_verified_subgame',
            },
          ],
        }),
      ),
      directory,
      verified: true,
    );
    await tester.tap(find.byKey(const Key('profile')));
    await _pumpProfile(tester);
    expect(find.byKey(const Key('profile-records-segment')), findsOneWidget);
    expect(find.text('Personal records'), findsOneWidget);
    expect(find.text('All'), findsWidgets);
    expect(find.text('Practice'), findsWidgets);
    expect(find.text('Tournament'), findsWidgets);
    // groupedScore inserts locale thousands separators (EN: 5,500).
    expect(find.textContaining('5,500'), findsWidgets);
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('profile-records-segment')),
        matching: find.text('Tournament'),
      ),
    );
    await _pumpProfile(tester);
    expect(find.textContaining('5,500'), findsWidgets);
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('profile-records-segment')),
        matching: find.text('Practice'),
      ),
    );
    await _pumpProfile(tester);
    expect(find.text('No record yet.'), findsWidgets);
  });

  testWidgets('PR15 HTTP 503 does not show false empty on Tournament', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'pzd53-profile-503',
    );
    await _pumpHome(
      tester,
      _api(
        personalRecords: const UatHttpResult(503, {
          'error': 'AUTH_UNAVAILABLE',
        }),
      ),
      directory,
      verified: true,
    );
    await tester.tap(find.byKey(const Key('profile')));
    await _pumpProfile(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('profile-records-segment')),
        matching: find.text('Tournament'),
      ),
    );
    await _pumpProfile(tester);
    expect(find.text('Could not refresh records.'), findsWidgets);
    // Must not present genuine empty copy for failed tournament fetch.
    expect(find.text('No record yet.'), findsNothing);
  });
}

ScriptedUatApi _api({
  UatHttpResult personalRecords = const UatHttpResult(200, {
    'records': <Object>[],
    'schemaReady': true,
  }),
}) {
  return ScriptedUatApi((method, path, body) async {
    if (path == '/v1/tournament/session' && method == 'POST') {
      return const UatHttpResult(201, {
        'playerId': '11111111-1111-4111-8111-111111111111',
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
    if (path == '/v1/tournament/me/badges' || path == '/v1/profile/me/badges') {
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
    if (path == '/v1/profile/me/personal-records' && method == 'GET') {
      return personalRecords;
    }
    if (path.endsWith('/personal-records/practice/sync') && method == 'POST') {
      return const UatHttpResult(200, {
        'records': <Object>[],
        'schemaReady': true,
        'acknowledgements': <Object>[],
      });
    }
    return const UatHttpResult(404, {'error': 'NOT_FOUND'});
  });
}

Future<void> _pumpProfile(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpHome(
  WidgetTester tester,
  UatApi api,
  Directory directory, {
  Locale? locale,
  TextScaler? textScaler,
  Size surfaceSize = const Size(390, 844),
  bool verified = false,
}) async {
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  GuestAuthClient? sessionAuth;
  if (verified) {
    const playerId = '11111111-1111-4111-8111-111111111111';
    final token = _jwt(sub: playerId, accountType: 'verified');
    final store = _MemStore()..token = 'v' * 64;
    sessionAuth = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    sessionAuth.debugSeedAccess(
      GuestAccess.parse(
        accessToken: token,
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
    );
    final identity = PracticeIdentityStore(directory);
    await identity.load();
    await identity.bindAuthenticatedPlayer(playerId);
  }

  await tester.pumpWidget(
    TournamentUatApp(
      config: UatConfig(
        baseUrl: verified
            ? 'https://staging.puzzle-duel.app'
            : 'http://127.0.0.1',
        bearer: verified ? 'Bearer verified' : 'Bearer test',
        playerLabel: 'profile',
      ),
      api: api,
      stateDirectory: directory,
      haptics: const SilentTournamentHaptics(),
      locale: locale,
      textScaler: textScaler,
      sessionAuth: sessionAuth,
    ),
  );
  await tester.pump();
  for (var i = 0; i < 40; i++) {
    if (find.byKey(const Key('profile')).evaluate().isNotEmpty) break;
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(find.byKey(const Key('profile')), findsOneWidget);
}
