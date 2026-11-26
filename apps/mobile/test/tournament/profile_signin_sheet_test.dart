import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/tournament/auth_coordinator.dart';
import 'package:puzzle_duel_mobile/tournament/guest_auth.dart';
import 'package:puzzle_duel_mobile/tournament/provider_auth.dart';
import 'package:puzzle_duel_mobile/tournament/provider_sign_in.dart';
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
            'fid': 'test-fid',
          }),
        ),
      )
      .replaceAll('=', '');
  return '$header.$payload.sig';
}

final class _MemStore implements GuestCredentialStore {
  String? token;
  String? rotationId;
  String? pendingLink;
  String? identityBinding;
  String? vaultJournal;

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
  @override
  Future<String?> readIdentityBinding() async => identityBinding;
  @override
  Future<void> writeIdentityBinding(String encoded) async {
    identityBinding = encoded;
  }

  @override
  Future<void> clearIdentityBinding() async => identityBinding = null;
  @override
  Future<String?> readVaultJournal() async => vaultJournal;
  @override
  Future<void> writeVaultJournal(String encoded) async =>
      vaultJournal = encoded;
  @override
  Future<void> clearVaultJournal() async => vaultJournal = null;
}

/// Minimal provider port — sheet presentation must not hit the network.
final class _StubProviders implements ProviderAuthPort {
  @override
  Future<ProviderChallenge> challenge({
    required AuthProviderKind provider,
    required ProviderAuthPurpose purpose,
    String? guestBearer,
  }) async {
    return ProviderChallenge(
      provider: provider,
      purpose: purpose,
      nonce: 'n' * 43,
      binding: purpose == ProviderAuthPurpose.login ? 'binding' : null,
    );
  }

  @override
  Future<ProviderCredentialBundle> login({
    required AuthProviderKind provider,
    required String idToken,
    required String nonce,
    required String binding,
  }) async {
    throw const ProviderAuthException('NOT_USED');
  }

  @override
  Future<ProviderCredentialBundle> link({
    required AuthProviderKind provider,
    required String idToken,
    required String nonce,
    required String guestBearer,
  }) async {
    throw const ProviderAuthException('NOT_USED');
  }

  @override
  Future<ProviderCredentialBundle> recover({
    required AuthProviderKind provider,
    required String idToken,
    required String nonce,
    required String binding,
    required String expectedPlayerId,
  }) async {
    throw const ProviderAuthException('NOT_USED');
  }

  @override
  Future<void> logout({
    required String refreshToken,
    String? accessBearer,
  }) async {}
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

  testWidgets(
    'Profile sign-in opens Google/Apple auth sheet via Navigator context',
    (tester) async {
      final harness = await _pumpGuestAuthApp(tester);
      await tester.tap(find.byKey(const Key('profile')));
      await _settle(tester);
      expect(find.byKey(const Key('profile-sign-in')), findsOneWidget);

      await tester.tap(find.byKey(const Key('profile-sign-in')));
      await _settle(tester);

      expect(find.byKey(const Key('auth-sheet-title')), findsOneWidget);
      expect(find.byKey(const Key('auth-google')), findsOneWidget);
      expect(find.byKey(const Key('auth-apple')), findsOneWidget);
      // Profile-only must not claim tournament attempts.
      expect(harness.claimPosts, 0);
    },
  );

  testWidgets('Home sign-in opens the same Google/Apple auth sheet', (
    tester,
  ) async {
    final harness = await _pumpGuestAuthApp(tester);
    expect(find.byKey(const Key('primary-action')), findsOneWidget);

    await tester.tap(find.byKey(const Key('primary-action')));
    await _settle(tester);

    expect(find.byKey(const Key('auth-sheet-title')), findsOneWidget);
    expect(find.byKey(const Key('auth-google')), findsOneWidget);
    expect(find.byKey(const Key('auth-apple')), findsOneWidget);
    expect(harness.claimPosts, 0);
  });

  testWidgets(
    'Profile auth sheet cancel leaves home ungated and does not start ranked',
    (tester) async {
      final harness = await _pumpGuestAuthApp(tester);
      await tester.tap(find.byKey(const Key('profile')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('profile-sign-in')));
      await _settle(tester);
      expect(find.byKey(const Key('auth-sheet-title')), findsOneWidget);

      await tester.tap(find.byKey(const Key('auth-cancel')));
      await _settle(tester);

      expect(find.byKey(const Key('auth-sheet-title')), findsNothing);
      expect(find.byKey(const Key('profile-header')), findsOneWidget);
      expect(find.byKey(const Key('offer-tray')), findsNothing);
      expect(harness.claimPosts, 0);
    },
  );
}

final class _Harness {
  var claimPosts = 0;
}

Future<_Harness> _pumpGuestAuthApp(WidgetTester tester) async {
  final directory = Directory.systemTemp.createTempSync('pzd27-profile-signin');
  addTearDown(() => directory.deleteSync(recursive: true));

  const guestId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  final token = _jwt(sub: guestId, accountType: 'guest');
  final store = _MemStore()..token = 'g' * 64;
  final session = GuestAuthClient(
    origin: 'https://staging.puzzle-duel.app',
    credentials: store,
  );
  session.debugSeedAccess(
    GuestAccess.parse(
      accessToken: token,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    ),
  );
  final coordinator = AuthCoordinator(
    session: session,
    providers: _StubProviders(),
    signIn: FakeProviderSignIn(),
  );

  final harness = _Harness();
  final api = ScriptedUatApi((method, path, body) async {
    if (path == '/v1/tournament/claims/daily' && method == 'POST') {
      harness.claimPosts++;
      fail('guest ranked gate must not claim from profile/home auth sheet');
    }
    if (path == '/v1/tournament/session' && method == 'POST') {
      return const UatHttpResult(201, {
        'playerId': guestId,
        'sessionSecret': 'secret',
        'sessionId': 's1',
      });
    }
    if (path == '/v1/tournament/me/badges') {
      return const UatHttpResult(200, {
        'playerScoped': true,
        'catalogVersion': 1,
        'badges': <Object>[],
      });
    }
    return const UatHttpResult(404, {'error': 'NOT_FOUND'});
  });

  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    TournamentUatApp(
      config: UatConfig(
        baseUrl: 'https://staging.puzzle-duel.app',
        bearer: token,
        playerLabel: 'Guest',
      ),
      api: api,
      stateDirectory: directory,
      sessionAuth: session,
      authCoordinator: coordinator,
      haptics: const SilentTournamentHaptics(),
      locale: const Locale('tr'),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 60; i++) {
    if (find.byKey(const Key('profile')).evaluate().isNotEmpty &&
        find.byKey(const Key('primary-action')).evaluate().isNotEmpty) {
      break;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(find.byKey(const Key('profile')), findsOneWidget);
  expect(find.byKey(const Key('primary-action')), findsOneWidget);

  return harness;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
