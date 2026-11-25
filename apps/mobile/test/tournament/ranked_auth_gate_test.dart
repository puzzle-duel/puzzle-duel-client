import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/tournament/guest_auth.dart';
import 'package:puzzle_duel_mobile/tournament/practice_identity.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_controller.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';

String _jwt({required String sub, required String accountType}) {
  final header = base64Url
      .encode(utf8.encode(jsonEncode({'alg': 'none'})))
      .replaceAll('=', '');
  final payload = base64Url
      .encode(utf8.encode(jsonEncode({
        'iss': 'https://staging.puzzle-duel.app',
        'aud': 'puzzle-duel-api',
        'sub': sub,
        'account_type': accountType,
        'fid': 'test-fid',
      })))
      .replaceAll('=', '');
  return '$header.$payload.sig';
}

final class _MemStore implements GuestCredentialStore {
  String? token;
  String? rotationId;
  String? pendingLink;
  @override
  Future<String?> readRefreshToken() async => token;
  @override
  Future<void> writeRefreshToken(String value) async => token = value;
  @override
  Future<void> clearRefreshToken() async => token = null;
  @override
  Future<String?> readPendingRotationId() async => rotationId;
  @override
  Future<void> writePendingRotationId(String id) async => rotationId = id;
  @override
  Future<void> clearPendingRotationId() async => rotationId = null;
  @override
  Future<String?> readPendingLinkProvider() async => pendingLink;
  @override
  Future<void> writePendingLinkProvider(String provider) async {
    pendingLink = provider;
  }
  @override
  Future<void> clearPendingLinkProvider() async => pendingLink = null;
}

final class _RecordingApi extends UatApi {
  _RecordingApi({required super.baseUrl, required super.bearer});
  final posts = <String>[];
  @override
  Future<UatHttpResult> post(String path, [Object? body]) async {
    posts.add(path);
    if (path == '/v1/tournament/claims/daily') {
      fail('claim must not run for guest ranked gate');
    }
    return const UatHttpResult(200, {}, category: UatFailureCategory.ok);
  }

  @override
  Future<UatHttpResult> get(String path) async {
    return const UatHttpResult(200, {}, category: UatFailureCategory.ok);
  }
}

void main() {
  test('guest loadDay sets RANKED_AUTH_REQUIRED without claiming', () async {
    final dir = await Directory.systemTemp.createTemp('pzd27-gate');
    addTearDown(() => dir.delete(recursive: true));
    const guestId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    final store = _MemStore()..token = 'guest-refresh';
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    final token = _jwt(sub: guestId, accountType: 'guest');
    session.debugSeedAccess(GuestAccess.parse(
      accessToken: token,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    ));
    final api = _RecordingApi(
      baseUrl: 'https://staging.puzzle-duel.app',
      bearer: token,
    );
    final identity = PracticeIdentityStore(dir);
    await identity.load();
    final controller = TournamentController(
      config: UatConfig(
        baseUrl: 'https://staging.puzzle-duel.app',
        bearer: token,
        playerLabel: 'Guest',
      ),
      api: api,
      stateDirectory: dir,
      identity: identity,
      sessionAuth: session,
      haptics: const SilentTournamentHaptics(),
    );
    await controller.beginLocal();
    await controller.loadDay(presentHome: true);
    expect(controller.rankedAuthRequired, isTrue);
    expect(controller.tournamentNoticeCode, 'RANKED_AUTH_REQUIRED');
    expect(api.posts, isEmpty);
    controller.dispose();
  });

  test('requestRankedEntry for guest opens auth hook without claim', () async {
    final dir = await Directory.systemTemp.createTemp('pzd27-entry');
    addTearDown(() => dir.delete(recursive: true));
    const guestId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: _MemStore()..token = 'guest-refresh',
    );
    final token = _jwt(sub: guestId, accountType: 'guest');
    session.debugSeedAccess(GuestAccess.parse(
      accessToken: token,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    ));
    var authRequested = 0;
    final api = _RecordingApi(
      baseUrl: 'https://staging.puzzle-duel.app',
      bearer: token,
    );
    final identity = PracticeIdentityStore(dir);
    await identity.load();
    final controller = TournamentController(
      config: UatConfig(
        baseUrl: 'https://staging.puzzle-duel.app',
        bearer: token,
        playerLabel: 'Guest',
      ),
      api: api,
      stateDirectory: dir,
      identity: identity,
      sessionAuth: session,
      haptics: const SilentTournamentHaptics(),
    );
    controller.onRequestRankedAuth = () => authRequested++;
    await controller.beginLocal();
    await controller.requestRankedEntry();
    expect(authRequested, 1);
    expect(controller.rankedAuthRequired, isTrue);
    expect(api.posts, isEmpty);
    controller.dispose();
  });
}
