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
      if (call.method == 'signRecovery') return 'signed-proof';
      throw PlatformException(code: 'UNEXPECTED_METHOD');
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(signer, null);
  });

  test('proactive foreground renewal extends same session without writer '
      'takeover or blocked commands', () async {
    final dir = Directory.systemTemp.createTempSync('pzd-proactive-renewal-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final identity = PracticeIdentityStore(dir);
    await identity.load();
    final firstExpiry = DateTime.now().millisecondsSinceEpoch + 45000;
    const originalSessionId = '33333333-3333-4333-8333-333333333333';
    const playerId = '11111111-1111-4111-8111-111111111111';
    var sessionOpens = 0;
    var renewals = 0;
    var challenges = 0;
    var commands = 0;
    final api = ScriptedUatApi((method, path, body) async {
      if (path == '/v1/tournament/session' && method == 'POST') {
        sessionOpens++;
        return UatHttpResult(201, {
          'playerId': playerId,
          'sessionId': originalSessionId,
          'sessionSecret': 'session-1',
          'expiresAtMs': firstExpiry,
        });
      }
      if (path == '/v1/tournament/session' && method == 'PATCH') {
        renewals++;
        return UatHttpResult(200, {
          'playerId': playerId,
          'sessionId': originalSessionId,
          'expiresAtMs': DateTime.now().millisecondsSinceEpoch + 45000,
        });
      }
      if (path.endsWith('/devices/register')) {
        return const UatHttpResult(200, {});
      }
      if (path.endsWith('/claims/daily')) {
        return const UatHttpResult(201, {
          'seriesId': '22222222-2222-4222-8222-222222222222',
          'status': 'ACTIVE',
          'original': true,
        });
      }
      if (path.endsWith('/recovery-challenge') ||
          path.endsWith('/recover-writer')) {
        challenges++;
        return const UatHttpResult(409, {'error': 'WRITER_STILL_ACTIVE'});
      }
      if (path.endsWith('/board')) {
        return const UatHttpResult(200, {
          'ordinal': 1,
          'awaitAdvance': true,
          'boardRevision': 4,
          'writerGeneration': 1,
        });
      }
      if (path.endsWith('/commands')) {
        commands++;
        return const UatHttpResult(200, {});
      }
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });
    final controller = TournamentController(
      config: const UatConfig(
        baseUrl: 'http://127.0.0.1',
        bearer: 'Bearer test',
        playerLabel: 'continuity',
      ),
      api: api,
      stateDirectory: dir,
      identity: identity,
      haptics: const SilentTournamentHaptics(),
    );
    addTearDown(controller.dispose);
    await controller.start();
    await controller.resume();
    controller.setAppForeground(false);
    controller.setAppForeground(true);
    // Foreground refresh runs off the input path.
    for (var attempt = 0; attempt < 20 && renewals == 0; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(renewals, 1);
    expect(sessionOpens, 1);
    expect(challenges, 0);
    await controller.advance();
    expect(commands, 1);
    expect(sessionOpens, 1);
    expect(challenges, 0);
  });

  test('expired session renews and recovers writer before advance command '
      'without a rejected command or duplicate submission', () async {
    final dir = Directory.systemTemp.createTempSync('pzd-session-continuity-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final identity = PracticeIdentityStore(dir);
    await identity.load();
    final initialExpiry = DateTime.now().millisecondsSinceEpoch + 150;
    var sessionsOpened = 0;
    var recoveryChallenges = 0;
    var writerRecoveries = 0;
    var commandPosts = 0;
    var expiredCommandPosts = 0;
    final api = ScriptedUatApi((method, path, body) async {
      if (path == '/v1/tournament/session' && method == 'POST') {
        sessionsOpened++;
        return UatHttpResult(201, {
          'playerId': '11111111-1111-4111-8111-111111111111',
          'sessionId': sessionsOpened == 1
              ? '33333333-3333-4333-8333-333333333333'
              : '55555555-5555-4555-8555-555555555555',
          'sessionSecret': 'session-$sessionsOpened',
          'expiresAtMs': sessionsOpened == 1
              ? initialExpiry
              : DateTime.now().millisecondsSinceEpoch + 45000,
        });
      }
      if (path == '/v1/tournament/session' && method == 'GET') {
        return const UatHttpResult(401, {'error': 'UNAUTHENTICATED'});
      }
      if (path.endsWith('/devices/register')) {
        return const UatHttpResult(200, {
          'deviceCredentialId': '44444444-4444-4444-8444-444444444444',
        });
      }
      if (path.endsWith('/claims/daily')) {
        return UatHttpResult(sessionsOpened == 1 ? 201 : 200, {
          'seriesId': '22222222-2222-4222-8222-222222222222',
          'status': 'ACTIVE',
          'original': sessionsOpened == 1,
        });
      }
      if (path.endsWith('/recovery-challenge')) {
        recoveryChallenges++;
        return const UatHttpResult(200, {
          'challengeId': '66666666-6666-4666-8666-666666666666',
          'deviceCredentialId': '44444444-4444-4444-8444-444444444444',
          'nonce': 'abcdefghijklmnopqrstuvwxyzABCDEF0123456789',
          'expectedWriterGeneration': 1,
          'expiresAtMs': 1800000000000,
        });
      }
      if (path.endsWith('/recover-writer')) {
        writerRecoveries++;
        return const UatHttpResult(200, {'writerGeneration': 2});
      }
      if (path.endsWith('/board')) {
        return UatHttpResult(200, {
          'ordinal': 1,
          'ordinalLabel': 'E1',
          'seriesScore': 100,
          'score': 100,
          'awaitAdvance': true,
          'resultsPublished': false,
          'boardRevision': 4,
          'writerGeneration': sessionsOpened == 1 ? 1 : 2,
        });
      }
      if (path.endsWith('/commands')) {
        commandPosts++;
        if (sessionsOpened == 1) {
          expiredCommandPosts++;
          return const UatHttpResult(401, {'error': 'UNAUTHENTICATED'});
        }
        return const UatHttpResult(200, {'ok': true});
      }
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });
    final controller = TournamentController(
      config: const UatConfig(
        baseUrl: 'http://127.0.0.1',
        bearer: 'Bearer test',
        playerLabel: 'continuity',
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
    expect(controller.tournamentReady, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    await controller.advance();
    expect(sessionsOpened, 2);
    expect(recoveryChallenges, 1);
    expect(writerRecoveries, 1);
    expect(commandPosts, 1);
    expect(expiredCommandPosts, 0);
    expect(controller.tournamentReady, isTrue);
    expect(controller.rankedWriterLocked, isFalse);
  });
}

bool _yes() => true;
