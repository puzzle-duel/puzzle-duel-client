import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/diagnostics/puzzle_duel_logger.dart';
import 'package:puzzle_duel_mobile/presentation/feedback/app_top_banner.dart';
import 'package:puzzle_duel_mobile/tournament/guest_auth.dart';
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

    final onTimeTile = find.byKey(
      const Key('badge-tile-on_time'),
      skipOffstage: false,
    );
    await tester.scrollUntilVisible(
      onTimeTile,
      120,
      scrollable: find.byType(Scrollable).hitTestable(),
    );
    await tester.pumpAndSettle();
    await tester.tap(onTimeTile, warnIfMissed: false);
    await tester.pumpAndSettle();
    // Detail sheet may require a second frame after modal route push.
    for (var i = 0; i < 20 && find.byKey(const Key('badge-detail-title')).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      find.byKey(const Key('badge-detail-title'), skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.textContaining('Server-authoritative', skipOffstage: false),
      findsWidgets,
    );
    await tester.tap(find.byKey(const Key('badge-detail-close')));
    await tester.pumpAndSettle();

    final retry = find.byKey(const Key('badge-retry'), skipOffstage: false);
    await tester.scrollUntilVisible(
      retry,
      200,
      scrollable: find.byType(Scrollable).hitTestable(),
    );
    await tester.tap(retry, warnIfMissed: false);
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
    await tester.scrollUntilVisible(
      find.byKey(const Key('badge-tile-on_time'), skipOffstage: false),
      200,
      scrollable: find.byType(Scrollable).hitTestable(),
    );
    await tester.pumpAndSettle();
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

  testWidgets('RC1 default All + HTTP 503 + no cache is not false empty', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd53-rc1-all-503');
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
    // Default segment is All — must not show genuine empty after 503.
    expect(find.text('Could not refresh records.'), findsWidgets);
    expect(find.text('No record yet.'), findsNothing);
  });

  testWidgets('RC2 Tournament + HTTP 503 + no cache is not false empty', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd53-rc2-t-503');
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
    expect(find.text('No record yet.'), findsNothing);
  });

  testWidgets('RC3 All shows loading before first successful GET', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd53-rc3-loading');
    final release = Completer<UatHttpResult>();
    await _pumpHome(
      tester,
      _api(personalRecordsFuture: () => release.future),
      directory,
      verified: true,
    );
    await tester.tap(find.byKey(const Key('profile')));
    var sawLoading = false;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('Syncing records…').evaluate().isNotEmpty ||
          find.text('Loading records…').evaluate().isNotEmpty) {
        sawLoading = true;
        break;
      }
    }
    expect(sawLoading, isTrue);
    expect(find.text('No record yet.'), findsNothing);
    release.complete(
      const UatHttpResult(200, {'records': <Object>[], 'schemaReady': true}),
    );
    await _pumpProfile(tester);
    expect(find.text('No record yet.'), findsWidgets);
  });

  testWidgets('RC4 Tournament shows loading before first successful GET', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd53-rc4-t-load');
    final release = Completer<UatHttpResult>();
    await _pumpHome(
      tester,
      _api(personalRecordsFuture: () => release.future),
      directory,
      verified: true,
    );
    await tester.tap(find.byKey(const Key('profile')));
    await tester.pump();
    // Switch to Tournament while GET is still blocked.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byKey(const Key('profile-records-segment')).evaluate().isNotEmpty) {
        break;
      }
    }
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('profile-records-segment')),
        matching: find.text('Tournament'),
      ),
    );
    await tester.pump();
    expect(find.text('No record yet.'), findsNothing);
    expect(
      find.text('Syncing records…').evaluate().isNotEmpty ||
          find.text('Loading records…').evaluate().isNotEmpty,
      isTrue,
    );
    release.complete(
      const UatHttpResult(200, {'records': <Object>[], 'schemaReady': true}),
    );
    await _pumpProfile(tester);
  });

  testWidgets('RC5 All + successful empty response shows genuine empty', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd53-rc5-empty');
    await _pumpHome(
      tester,
      _api(
        personalRecords: const UatHttpResult(200, {
          'records': <Object>[],
          'schemaReady': true,
        }),
      ),
      directory,
      verified: true,
    );
    await tester.tap(find.byKey(const Key('profile')));
    await _pumpProfile(tester);
    expect(find.text('No record yet.'), findsWidgets);
  });

  testWidgets('RC6 All + HTTP 503 keeps valid Practice records', (tester) async {
    final directory = Directory.systemTemp.createTempSync('pzd53-rc6-practice');
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
        sessionId: 'rc6',
        difficulty: 'easy',
        rulesVersion: 'core-001.v2',
        generatorVersion: 'gen-001.v1',
        seed: 1,
        score: 88,
        terminalReason: 'move_limit_reached',
        completedAt: '2026-11-28T10:00:00.000Z',
        moveCount: 10,
      ),
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
    expect(find.textContaining('88'), findsWidgets);
    expect(find.text('Could not refresh records.'), findsWidgets);
    expect(find.text('No record yet.'), findsNothing);
  });

  testWidgets('RC7 HTTP 503 preserves active account remote cache', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd53-rc7-cache');
    var getCount = 0;
    await _pumpHome(
      tester,
      _api(
        personalRecordsFuture: () async {
          getCount++;
          if (getCount == 1) {
            return const UatHttpResult(200, {
              'schemaReady': true,
              'records': [
                {
                  'difficulty': 'hard',
                  'source': 'tournament',
                  'score': 9100,
                  'rulesVersion': 'core-001.v3',
                  'generatorVersion': 'gen-001.v1',
                  'achievedAt': '2026-11-20T10:00:00.000Z',
                  'provenance': 'tournament_f2b_verified_subgame',
                },
              ],
            });
          }
          return const UatHttpResult(503, {'error': 'AUTH_UNAVAILABLE'});
        },
      ),
      directory,
      verified: true,
    );
    await tester.tap(find.byKey(const Key('profile')));
    await _pumpProfile(tester);
    expect(find.textContaining('9,100'), findsWidgets);

    await tester.fling(find.byType(ListView).first, const Offset(0, 400), 800);
    await _pumpProfile(tester);
    expect(find.textContaining('9,100'), findsWidgets);
    expect(find.text('Could not refresh records.'), findsWidgets);
  });

  testWidgets('RC8 logout while remote GET in flight discards stale records', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd53-rc8-logout');
    final release = Completer<UatHttpResult>();
    final started = Completer<void>();
    final harness = await _pumpHome(
      tester,
      _api(
        personalRecordsFuture: () async {
          if (!started.isCompleted) started.complete();
          return release.future;
        },
      ),
      directory,
      verified: true,
      withSession: true,
    );
    await tester.tap(find.byKey(const Key('profile')));
    var sawRemoteStart = false;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (started.isCompleted) {
        sawRemoteStart = true;
        break;
      }
    }
    expect(sawRemoteStart, isTrue);

    final controller = _controllerOf(tester);
    const guestId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    harness.session!.debugSeedAccess(
      GuestAccess.parse(
        accessToken: _jwt(sub: guestId, accountType: 'guest'),
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
    );
    await controller.clearAuthenticatedPracticeScope();
    controller.applyGuestSessionAfterLogout(rankedAuthRequired: true);
    await _pumpProfile(tester);

    expect(find.byKey(const Key('profile-records-segment')), findsNothing);
    expect(find.text('Practice records'), findsOneWidget);

    release.complete(
      const UatHttpResult(200, {
        'schemaReady': true,
        'records': [
          {
            'difficulty': 'easy',
            'source': 'tournament',
            'score': 8888,
            'rulesVersion': 'core-001.v3',
            'generatorVersion': 'gen-001.v1',
            'achievedAt': '2026-11-20T10:00:00.000Z',
            'provenance': 'tournament_f2b_verified_subgame',
          },
        ],
      }),
    );
    await _pumpProfile(tester);
    expect(find.textContaining('8,888'), findsNothing);
    expect(find.byKey(const Key('profile-records-segment')), findsNothing);
    expect(find.text('Practice records'), findsOneWidget);
  });

  testWidgets('RC9 verified login while Profile open refreshes remote', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd53-rc9-login');
    const playerId = '11111111-1111-4111-8111-111111111111';
    final harness = await _pumpHome(
      tester,
      _api(
        personalRecords: const UatHttpResult(200, {
          'schemaReady': true,
          'records': [
            {
              'difficulty': 'hard',
              'source': 'tournament',
              'score': 6600,
              'rulesVersion': 'core-001.v3',
              'generatorVersion': 'gen-001.v1',
              'achievedAt': '2026-11-20T10:00:00.000Z',
              'provenance': 'tournament_f2b_verified_subgame',
            },
          ],
        }),
      ),
      directory,
      verified: false,
      withSession: true,
    );
    await tester.tap(find.byKey(const Key('profile')));
    await _pumpProfile(tester);
    expect(find.byKey(const Key('profile-records-segment')), findsNothing);
    expect(find.textContaining('6,600'), findsNothing);

    final controller = _controllerOf(tester);
    harness.session!.debugSeedAccess(
      GuestAccess.parse(
        accessToken: _jwt(sub: playerId, accountType: 'verified'),
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
    );
    controller.api.bearer = 'Bearer verified';
    await controller.identity.bindAuthenticatedPlayer(playerId);
    controller.invalidateAccountScopedPresentation(reason: 'account_transition');
    controller.markAccountStateUpdated();
    await _pumpProfile(tester);

    expect(find.byKey(const Key('profile-records-segment')), findsOneWidget);
    expect(find.textContaining('6,600'), findsWidgets);
    expect(find.text('Personal records'), findsOneWidget);
  });

  testWidgets('RC10 account switch discards delayed remote for prior account', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd53-rc10-switch');
    const playerA = '11111111-1111-4111-8111-111111111111';
    const playerB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
    var getCount = 0;
    final releaseA = Completer<UatHttpResult>();
    final releaseB = Completer<UatHttpResult>();
    final harness = await _pumpHome(
      tester,
      _api(
        personalRecordsFuture: () async {
          getCount++;
          if (getCount == 1) return releaseA.future;
          return releaseB.future;
        },
      ),
      directory,
      verified: true,
      withSession: true,
      verifiedPlayerId: playerA,
    );
    await tester.tap(find.byKey(const Key('profile')));
    for (var i = 0; i < 40 && getCount < 1; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(getCount, greaterThanOrEqualTo(1));

    final controller = _controllerOf(tester);
    harness.session!.debugSeedAccess(
      GuestAccess.parse(
        accessToken: _jwt(sub: playerB, accountType: 'verified'),
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
    );
    await controller.identity.bindAuthenticatedPlayer(playerB);
    controller.invalidateAccountScopedPresentation(reason: 'account_transition');
    controller.markAccountStateUpdated();
    await tester.pump();

    releaseA.complete(
      const UatHttpResult(200, {
        'schemaReady': true,
        'records': [
          {
            'difficulty': 'easy',
            'source': 'tournament',
            'score': 1111,
            'rulesVersion': 'core-001.v3',
            'generatorVersion': 'gen-001.v1',
            'achievedAt': '2026-11-20T10:00:00.000Z',
            'provenance': 'tournament_f2b_verified_subgame',
          },
        ],
      }),
    );
    await _pumpProfile(tester);
    expect(find.textContaining('1,111'), findsNothing);

    releaseB.complete(
      const UatHttpResult(200, {
        'schemaReady': true,
        'records': [
          {
            'difficulty': 'easy',
            'source': 'tournament',
            'score': 2222,
            'rulesVersion': 'core-001.v3',
            'generatorVersion': 'gen-001.v1',
            'achievedAt': '2026-11-21T10:00:00.000Z',
            'provenance': 'tournament_f2b_verified_subgame',
          },
        ],
      }),
    );
    await _pumpProfile(tester);
    expect(find.textContaining('2,222'), findsWidgets);
    expect(find.textContaining('1,111'), findsNothing);
  });

  test('RC11 diagnostic report schema keeps personal-records failure correlation',
      () {
    final failure = LogEvent(
      level: LogLevel.warning,
      code: LogCode.httpFailed,
      operation: 'fetchPersonalRecords',
      errorCode: 'AUTH_UNAVAILABLE',
      requestId: '00112233445566778899aabbccddeeff',
      httpStatus: 503,
    );
    final report = UatApi.diagnosticReportEvents([failure]);
    expect(report, hasLength(1));
    expect(report.single['requestId'], '00112233445566778899aabbccddeeff');
    expect(report.single['httpStatus'], 503);
    expect(report.single['errorCode'], 'AUTH_UNAVAILABLE');
    expect(report.single['operation'], 'fetchPersonalRecords');
  });

  testWidgets('PR20 segment selection retained during verified refresh', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pzd53-pr20-segment');
    await _pumpHome(
      tester,
      _api(
        personalRecords: const UatHttpResult(200, {
          'schemaReady': true,
          'records': [
            {
              'difficulty': 'medium',
              'source': 'tournament',
              'score': 4400,
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
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('profile-records-segment')),
        matching: find.text('Tournament'),
      ),
    );
    await _pumpProfile(tester);
    expect(find.textContaining('4,400'), findsWidgets);

    await tester.fling(find.byType(ListView).first, const Offset(0, 400), 800);
    await _pumpProfile(tester);
    // Segment retained across refresh: tournament-sourced score still visible.
    expect(find.textContaining('4,400'), findsWidgets);
    expect(find.byKey(const Key('profile-records-segment')), findsOneWidget);
  });

  testWidgets('PR21 new verified account scope defaults to All', (tester) async {
    final directory = Directory.systemTemp.createTempSync('pzd53-pr21-all');
    const playerA = '11111111-1111-4111-8111-111111111111';
    const playerB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
    final harness = await _pumpHome(
      tester,
      _api(
        personalRecords: const UatHttpResult(200, {
          'records': <Object>[],
          'schemaReady': true,
        }),
      ),
      directory,
      verified: true,
      withSession: true,
      verifiedPlayerId: playerA,
    );
    await tester.tap(find.byKey(const Key('profile')));
    await _pumpProfile(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('profile-records-segment')),
        matching: find.text('Practice'),
      ),
    );
    await _pumpProfile(tester);

    final controller = _controllerOf(tester);
    harness.session!.debugSeedAccess(
      GuestAccess.parse(
        accessToken: _jwt(sub: playerB, accountType: 'verified'),
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
    );
    await controller.identity.bindAuthenticatedPlayer(playerB);
    controller.invalidateAccountScopedPresentation(reason: 'account_transition');
    controller.markAccountStateUpdated();
    await _pumpProfile(tester);

    // New scope resets to All — genuine empty after successful settle.
    expect(find.byKey(const Key('profile-records-segment')), findsOneWidget);
    expect(find.text('No record yet.'), findsWidgets);
  });
}

final class _ProfileHarness {
  GuestAuthClient? session;
}

TournamentController _controllerOf(WidgetTester tester) {
  return tester
      .widget<AppTopBannerHost>(find.byKey(const Key('tournament-status-host')))
      .controller;
}

ScriptedUatApi _api({
  UatHttpResult? personalRecords,
  Future<UatHttpResult> Function()? personalRecordsFuture,
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
      if (personalRecordsFuture != null) return personalRecordsFuture();
      return personalRecords ??
          const UatHttpResult(200, {
            'records': <Object>[],
            'schemaReady': true,
          });
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

Future<_ProfileHarness> _pumpHome(
  WidgetTester tester,
  UatApi api,
  Directory directory, {
  Locale? locale,
  TextScaler? textScaler,
  Size surfaceSize = const Size(390, 844),
  bool verified = false,
  bool withSession = false,
  String verifiedPlayerId = '11111111-1111-4111-8111-111111111111',
}) async {
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final harness = _ProfileHarness();
  GuestAuthClient? sessionAuth;
  final needsSession = verified || withSession;
  if (needsSession) {
    final playerId = verified
        ? verifiedPlayerId
        : 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    final accountType = verified ? 'verified' : 'guest';
    final token = _jwt(sub: playerId, accountType: accountType);
    final store = _MemStore()..token = verified ? 'v' * 64 : 'g' * 64;
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
    harness.session = sessionAuth;
    if (verified) {
      final identity = PracticeIdentityStore(directory);
      await identity.load();
      await identity.bindAuthenticatedPlayer(playerId);
    }
  }

  await tester.pumpWidget(
    TournamentUatApp(
      config: UatConfig(
        baseUrl: needsSession
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
  return harness;
}
