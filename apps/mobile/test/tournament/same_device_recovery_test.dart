import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/tournament/same_device_recovery.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';

import 'tournament_command_test.dart' show ScriptedUatApi;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pzd/device_signing');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'registerProof') {
            return {
              'spkiBase64Url': 'test-public-key',
              'signatureBase64Url': 'test-registration-signature',
            };
          }
          if (call.method == 'signRecovery') return 'test-recovery-signature';
          throw PlatformException(code: 'UNEXPECTED_METHOD');
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  final recovery = SameDeviceRecovery(isSupportedDevice: () => true);

  test('registers public key for verified session before claim', () async {
    final paths = <String>[];
    final api = ScriptedUatApi((method, path, body) async {
      paths.add(path);
      if (path.endsWith('/devices/register')) {
        expect((body as Map)['spkiBase64Url'], 'test-public-key');
        expect(body['signatureBase64Url'], 'test-registration-signature');
        return const UatHttpResult(200, {
          'deviceCredentialId': '44444444-4444-4444-8444-444444444444',
        });
      }
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });
    expect(await recovery.register(
      api: api,
      playerId: '11111111-1111-4111-8111-111111111111',
      sessionId: '33333333-3333-4333-8333-333333333333',
      origin: 'http://127.0.0.1',
    ), true);
    expect(paths, ['/v1/tournament/devices/register']);
  });

  test('recovery signs exact server challenge and never sends commands', () async {
    final paths = <String>[];
    final api = ScriptedUatApi((method, path, body) async {
      paths.add(path);
      if (path.endsWith('/recovery-challenge')) {
        return const UatHttpResult(200, {
          'challengeId': '55555555-5555-4555-8555-555555555555',
          'deviceCredentialId': '44444444-4444-4444-8444-444444444444',
          'nonce': 'abcdefghijklmnopqrstuvwxyzABCDEF0123456789',
          'expectedWriterGeneration': 1,
          'expiresAtMs': 1800000000000,
        });
      }
      if (path.endsWith('/recover-writer')) {
        final data = body as Map;
        expect(data['signatureBase64Url'], 'test-recovery-signature');
        expect((data['proof'] as Map)['expectedWriterGeneration'], 1);
        return const UatHttpResult(200, {
          'writerGeneration': 2,
          'boardRevision': 0,
        });
      }
      return const UatHttpResult(404, {'error': 'NOT_FOUND'});
    });
    expect(await recovery.recover(
      api: api,
      playerId: '11111111-1111-4111-8111-111111111111',
      newSessionId: '33333333-3333-4333-8333-333333333333',
      origin: 'http://127.0.0.1',
      seriesId: '22222222-2222-4222-8222-222222222222',
    ), true);
    expect(paths, [
      '/v1/tournament/series/22222222-2222-4222-8222-222222222222/recovery-challenge',
      '/v1/tournament/series/22222222-2222-4222-8222-222222222222/recover-writer',
    ]);
  });

  test('writer fence denial cannot be bypassed by client', () async {
    var commands = 0;
    final api = ScriptedUatApi((method, path, body) async {
      if (path.endsWith('/commands')) commands += 1;
      return const UatHttpResult(409, {'error': 'WRITER_STILL_ACTIVE'});
    });
    expect(await recovery.recover(
      api: api,
      playerId: '11111111-1111-4111-8111-111111111111',
      newSessionId: '33333333-3333-4333-8333-333333333333',
      origin: 'http://127.0.0.1',
      seriesId: '22222222-2222-4222-8222-222222222222',
    ), false);
    expect(commands, 0);
  });

  test('malformed server challenge never reaches signing or commands', () async {
    final paths = <String>[];
    final api = ScriptedUatApi((method, path, body) async {
      paths.add(path);
      return const UatHttpResult(200, {'challengeId': 'missing fields'});
    });
    expect(await recovery.recover(
      api: api,
      playerId: '11111111-1111-4111-8111-111111111111',
      newSessionId: '33333333-3333-4333-8333-333333333333',
      origin: 'http://127.0.0.1',
      seriesId: '22222222-2222-4222-8222-222222222222',
    ), false);
    expect(paths, hasLength(1));
    expect(paths.single, endsWith('/recovery-challenge'));
  });

  test('missing platform signer never sends a registration request', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    var httpCalls = 0;
    final api = ScriptedUatApi((method, path, body) async {
      httpCalls++;
      return const UatHttpResult(200, {});
    });
    expect(await recovery.register(
      api: api,
      playerId: '11111111-1111-4111-8111-111111111111',
      sessionId: '33333333-3333-4333-8333-333333333333',
      origin: 'https://staging.puzzle-duel.app',
    ), false);
    expect(httpCalls, 0);
  });

  test('default platform guard is fail closed outside supported mobile OSes', () async {
    final api = ScriptedUatApi((method, path, body) async {
      fail('Must not call HTTP on unsupported platform');
    });
    expect(await const SameDeviceRecovery().register(
      api: api, playerId: 'a', sessionId: 's', origin: 'http://127.0.0.1',
    ), false);
  });
}
