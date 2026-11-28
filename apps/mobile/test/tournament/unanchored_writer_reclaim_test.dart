import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/tournament/practice_identity.dart';
import 'package:puzzle_duel_mobile/tournament/same_device_recovery.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_controller.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';

import 'tournament_command_test.dart' show ScriptedUatApi;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const signer = MethodChannel('pzd/device_signing');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(signer, (call) async {
          if (call.method == 'registerProof') {
            return <String, String>{
              'spkiBase64Url': 'public-key',
              'signatureBase64Url': 'signature',
            };
          }
          if (call.method == 'signRecovery') return 'signature';
          throw PlatformException(code: 'UNEXPECTED_METHOD');
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(signer, null);
  });

  test(
    'same-account logout/login resume uses unanchored reclaim when '
    'device registration is absent',
    () async {
      final dir = Directory.systemTemp.createTempSync('pzd55-reclaim-logout-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final identity = PracticeIdentityStore(dir);
      await identity.load();
      var deletes = 0;
      var reclaimPosts = 0;
      var writerMatches = false;
      final api = ScriptedUatApi((method, path, body) async {
        if (path == '/v1/tournament/session' && method == 'POST') {
          return const UatHttpResult(201, {
            'playerId': '11111111-1111-4111-8111-111111111111',
            'sessionId': '33333333-3333-4333-8333-333333333333',
            'sessionSecret': 'test-session-secret-012345678901234567',
          });
        }
        if (path == '/v1/tournament/session' && method == 'DELETE') {
          deletes++;
          return const UatHttpResult(204, null);
        }
        if (path == '/v1/tournament/devices/register') {
          return const UatHttpResult(404, {'error': 'NOT_FOUND'});
        }
        if (path == '/v1/tournament/claims/daily') {
          return const UatHttpResult(200, {
            'seriesId': '22222222-2222-4222-8222-222222222222',
            'status': 'ACTIVE',
            'original': false,
            'originalUtcDate': '2026-11-26',
          });
        }
        if (path.endsWith('/reclaim-writer')) {
          reclaimPosts++;
          writerMatches = true;
          return const UatHttpResult(200, {
            'seriesId': '22222222-2222-4222-8222-222222222222',
            'writerGeneration': 2,
            'boardRevision': 14,
          });
        }
        if (path.endsWith('/board')) {
          return UatHttpResult(200, {
            'ordinal': 4,
            'ordinalLabel': 'E4',
            'seriesScore': 4800,
            'score': 1200,
            'awaitAdvance': true,
            'boardRevision': 14,
            'writerGeneration': writerMatches ? 2 : 1,
            'writerSessionMatches': writerMatches,
          });
        }
        return const UatHttpResult(404, {'error': 'NOT_FOUND'});
      });
      final controller = TournamentController(
        config: const UatConfig(
          baseUrl: 'http://127.0.0.1',
          bearer: 'Bearer test',
          playerLabel: 'Player A',
        ),
        api: api,
        deviceRecovery: const SameDeviceRecovery(isSupportedDevice: _yes),
        stateDirectory: dir,
        identity: identity,
        haptics: const SilentTournamentHaptics(),
      );
      addTearDown(controller.dispose);
      await controller.start();
      await controller.revokeTournamentGameplaySession(reason: 'logout');
      expect(deletes, 1);
      await controller.resume();
      expect(reclaimPosts, 1);
      expect(controller.tournamentReady, isTrue);
      expect(controller.rankedWriterLocked, isFalse);
      expect(controller.day?.seriesScore, 4800);
      expect(controller.tournamentNoticeCode, isNull);
    },
  );

  test('concurrent active writer reclaim denial preserves board progress', () async {
    final dir = Directory.systemTemp.createTempSync('pzd55-reclaim-active-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final identity = PracticeIdentityStore(dir);
    await identity.load();
    var reclaimPosts = 0;
    final api = ScriptedUatApi((method, path, body) async {
      if (path == '/v1/tournament/session' && method == 'POST') {
        return const UatHttpResult(201, {
          'playerId': '11111111-1111-4111-8111-111111111111',
          'sessionId': '33333333-3333-4333-8333-333333333333',
          'sessionSecret': 'test-session-secret-012345678901234567',
        });
      }
      if (path == '/v1/tournament/devices/register') {
        return const UatHttpResult(404, {'error': 'NOT_FOUND'});
      }
      if (path == '/v1/tournament/claims/daily') {
        return const UatHttpResult(200, {
          'seriesId': '22222222-2222-4222-8222-222222222222',
          'status': 'ACTIVE',
          'original': false,
        });
      }
      if (path.endsWith('/reclaim-writer')) {
        reclaimPosts++;
        return const UatHttpResult(409, {'error': 'WRITER_STILL_ACTIVE'});
      }
      if (path.endsWith('/board')) {
        return const UatHttpResult(200, {
          'ordinal': 3,
          'ordinalLabel': 'E3',
          'seriesScore': 4800,
          'score': 1600,
          'awaitAdvance': true,
          'boardRevision': 9,
          'writerGeneration': 1,
          'writerSessionMatches': false,
        });
      }
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });
    final controller = TournamentController(
      config: const UatConfig(
        baseUrl: 'http://127.0.0.1',
        bearer: 'Bearer test',
        playerLabel: 'Player A',
      ),
      api: api,
      deviceRecovery: const SameDeviceRecovery(isSupportedDevice: _yes),
      stateDirectory: dir,
      identity: identity,
      haptics: const SilentTournamentHaptics(),
    );
    addTearDown(controller.dispose);
    await controller.start();
    await controller.resume();
    expect(reclaimPosts, greaterThanOrEqualTo(1));
    expect(controller.rankedWriterLocked, isTrue);
    expect(controller.tournamentNoticeCode, 'WRITER_STILL_ACTIVE');
    expect(controller.day?.seriesScore, 4800);
    expect(controller.tournamentReady, isFalse);
  });

  test('account A then B then A isolation does not unlock mismatched writer', () async {
    final dir = Directory.systemTemp.createTempSync('pzd55-reclaim-isolation-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final identity = PracticeIdentityStore(dir);
    await identity.load();
    var player = 'A';
    final api = ScriptedUatApi((method, path, body) async {
      if (path == '/v1/tournament/session' && method == 'POST') {
        return UatHttpResult(201, {
          'playerId': player == 'A'
              ? 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
              : 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
          'sessionId': player == 'A'
              ? '11111111-1111-4111-8111-111111111111'
              : '22222222-2222-4222-8222-222222222222',
          'sessionSecret': 'test-session-secret-012345678901234567',
        });
      }
      if (path == '/v1/tournament/session' && method == 'DELETE') {
        return const UatHttpResult(204, null);
      }
      if (path == '/v1/tournament/devices/register') {
        return const UatHttpResult(404, {'error': 'NOT_FOUND'});
      }
      if (path == '/v1/tournament/claims/daily') {
        if (player == 'B') {
          return const UatHttpResult(200, {
            'seriesId': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
            'status': 'ACTIVE',
            'original': true,
          });
        }
        return const UatHttpResult(200, {
          'seriesId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'status': 'ACTIVE',
          'original': false,
        });
      }
      if (path.endsWith('/reclaim-writer')) {
        if (player != 'A') {
          return const UatHttpResult(409, {'error': 'SERIES_NOT_OWNED'});
        }
        return const UatHttpResult(200, {
          'seriesId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'writerGeneration': 2,
          'boardRevision': 4,
        });
      }
      if (path.endsWith('/board')) {
        if (player == 'B') {
          return const UatHttpResult(200, {
            'ordinal': 1,
            'ordinalLabel': 'E1',
            'seriesScore': 0,
            'score': 0,
            'awaitAdvance': false,
            'boardRevision': 0,
            'writerGeneration': 1,
            'writerSessionMatches': true,
          });
        }
        return const UatHttpResult(200, {
          'ordinal': 2,
          'ordinalLabel': 'E2',
          'seriesScore': 2100,
          'score': 900,
          'awaitAdvance': true,
          'boardRevision': 4,
          'writerGeneration': 2,
          'writerSessionMatches': true,
        });
      }
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });
    final controller = TournamentController(
      config: const UatConfig(
        baseUrl: 'http://127.0.0.1',
        bearer: 'Bearer test-a',
        playerLabel: 'Player A',
      ),
      api: api,
      deviceRecovery: const SameDeviceRecovery(isSupportedDevice: _yes),
      stateDirectory: dir,
      identity: identity,
      haptics: const SilentTournamentHaptics(),
    );
    addTearDown(controller.dispose);
    await controller.start();
    await controller.resume();
    expect(controller.seriesId, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    expect(controller.day?.seriesScore, 2100);

    player = 'B';
    await controller.revokeTournamentGameplaySession(reason: 'account_transition');
    controller.invalidateAccountScopedPresentation(reason: 'account_transition');
    controller.markAccountStateUpdated();
    await controller.refreshTournament(
      origin: TournamentRefreshOrigin.pullToRefresh,
    );
    await controller.resume();
    expect(controller.seriesId, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
    expect(controller.day?.seriesScore, 0);

    player = 'A';
    await controller.revokeTournamentGameplaySession(reason: 'account_transition');
    controller.invalidateAccountScopedPresentation(reason: 'account_transition');
    controller.markAccountStateUpdated();
    await controller.refreshTournament(
      origin: TournamentRefreshOrigin.pullToRefresh,
    );
    await controller.resume();
    expect(controller.seriesId, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    expect(controller.day?.seriesScore, 2100);
    expect(controller.rankedWriterLocked, isFalse);
  });
}

bool _yes() => true;
