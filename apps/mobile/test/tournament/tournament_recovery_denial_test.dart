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

  test('IDLE_EXPIRED recovery denial leaves existing board readable but '
      'does not grant ready/writer status or send ranked commands', () async {
    final dir = Directory.systemTemp.createTempSync('pzd-recovery-denied-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final identity = PracticeIdentityStore(dir);
    await identity.load();
    var boardReads = 0;
    var commands = 0;
    final api = ScriptedUatApi((method, path, body) async {
      if (path == '/v1/tournament/session' && method == 'POST') {
        return const UatHttpResult(201, {
          'playerId': '11111111-1111-4111-8111-111111111111',
          'sessionId': '33333333-3333-4333-8333-333333333333',
          'sessionSecret': 'test-session',
        });
      }
      if (path == '/v1/tournament/devices/register') {
        return const UatHttpResult(200, {
          'deviceCredentialId': '44444444-4444-4444-8444-444444444444',
        });
      }
      if (path == '/v1/tournament/claims/daily') {
        return const UatHttpResult(200, {
          'seriesId': '22222222-2222-4222-8222-222222222222',
          'status': 'ACTIVE',
          'original': false,
        });
      }
      if (path.endsWith('/recovery-challenge')) {
        return const UatHttpResult(409, {'error': 'IDLE_EXPIRED'});
      }
      if (path.endsWith('/board')) {
        boardReads++;
        return const UatHttpResult(200, {
          'ordinal': 2,
          'ordinalLabel': 'E2',
          'seriesScore': 3300,
          'score': 1200,
          'awaitAdvance': true,
          'boardRevision': 14,
          'writerGeneration': 1,
          'idleDeadlineAtMs': 1,
          'serverNowMs': 500000,
        });
      }
      if (path.endsWith('/commands')) commands++;
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
    expect(boardReads, 1);
    expect(controller.seriesId, '22222222-2222-4222-8222-222222222222');
    expect(controller.tournamentSync, TournamentSyncState.degraded);
    expect(controller.tournamentReady, isFalse);
    expect(controller.rankedWriterLocked, isTrue);
    expect(controller.tournamentNoticeCode, 'IDLE_EXPIRED');
    await controller.resume();
    await controller.advance();
    expect(commands, 0);
  });
  test('writer still active: retry after expiry recovers same signed session', () async {
    final dir = Directory.systemTemp.createTempSync('pzd50-writer-retry-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final identity = PracticeIdentityStore(dir);
    await identity.load();
    var attempts = 0;
    var writerMatches = false;
    final api = ScriptedUatApi((method, path, body) async {
      if (path == '/v1/tournament/session' && method == 'POST') {
        return const UatHttpResult(201, {
          'playerId': '11111111-1111-4111-8111-111111111111',
          'sessionId': '33333333-3333-4333-8333-333333333333',
          'sessionSecret': 'test-session',
        });
      }
      if (path == '/v1/tournament/session' && method == 'GET') {
        return const UatHttpResult(200, {
          'playerId': '11111111-1111-4111-8111-111111111111',
          'sessionId': '33333333-3333-4333-8333-333333333333',
        });
      }
      if (path == '/v1/tournament/devices/register') {
        return const UatHttpResult(200, {
          'deviceCredentialId': '44444444-4444-4444-8444-444444444444',
        });
      }
      if (path == '/v1/tournament/claims/daily') {
        return const UatHttpResult(200, {
          'seriesId': '22222222-2222-4222-8222-222222222222',
          'status': 'ACTIVE',
          'original': false,
        });
      }
      if (path.endsWith('/board')) {
        return UatHttpResult(200, {
          'ordinal': 1, 'ordinalLabel': 'E1',
          'seriesScore': 2000, 'score': 2000,
          'awaitAdvance': true, 'writerGeneration': writerMatches ? 2 : 1,
          'writerSessionMatches': writerMatches,
          'boardRevision': 12,
        });
      }
      if (path.endsWith('/recovery-challenge')) {
        attempts++;
        if (attempts == 1) {
          return const UatHttpResult(409, {'error': 'WRITER_STILL_ACTIVE'});
        }
        return const UatHttpResult(200, {
          'challengeId': '55555555-5555-4555-8555-555555555555',
          'deviceCredentialId': '44444444-4444-4444-8444-444444444444',
          'nonce': 'abcdefghijklmnopqrstuvwxyzABCDEF0123456789',
          'expectedWriterGeneration': 1,
          'expiresAtMs': 1800000000000,
        });
      }
      if (path.endsWith('/recover-writer')) {
        writerMatches = true;
        return const UatHttpResult(200, {'writerGeneration': 2});
      }
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });
    final controller = TournamentController(
      config: const UatConfig(
        baseUrl: 'http://127.0.0.1',
        bearer: 'Bearer test',
        playerLabel: 'Guest B',
      ),
      api: api,
      deviceRecovery: const SameDeviceRecovery(isSupportedDevice: _yes),
      stateDirectory: dir,
      identity: identity,
      haptics: const SilentTournamentHaptics(),
    );
    addTearDown(controller.dispose);
    await controller.start();
    expect(attempts, 1);
    expect(controller.tournamentSync, TournamentSyncState.degraded);
    expect(controller.rankedWriterLocked, true);
    await controller.resume();
    expect(attempts, 2);
    expect(writerMatches, true);
    expect(controller.tournamentReady, true);
    expect(controller.rankedWriterLocked, false);
    expect(controller.tournamentNoticeCode, isNull);
  });

}

bool _yes() => true;
