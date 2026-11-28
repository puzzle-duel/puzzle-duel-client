import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/presentation/feedback/app_top_banner.dart';
import 'package:puzzle_duel_mobile/tournament/auth_coordinator.dart';
import 'package:puzzle_duel_mobile/tournament/guest_auth.dart';
import 'package:puzzle_duel_mobile/tournament/provider_auth.dart';
import 'package:puzzle_duel_mobile/tournament/provider_sign_in.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_nav.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_uat_app.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';

import 'tournament_command_test.dart' show ScriptedUatApi;

String _jwt({
  required String sub,
  required String accountType,
  String fid = 'test-fid',
}) {
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
            'fid': fid,
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

final class _ScriptedProviders implements ProviderAuthPort {
  _ScriptedProviders({
    this.continueError,
    this.logoutError,
    this.logoutDelay,
    this.loginPlayerId = '11111111-1111-1111-1111-111111111111',
    this.continuePlayerId = '11111111-1111-1111-1111-111111111111',
  });

  ProviderAuthException? linkError;
  ProviderAuthException? continueError;
  ProviderAuthException? logoutError;
  Completer<void>? logoutDelay;
  String loginPlayerId;
  String continuePlayerId;
  static const linkPlayerId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  var logoutCalls = 0;
  var linkCalls = 0;
  var loginCalls = 0;
  var continueCalls = 0;
  var confirmContinueCalls = 0;

  @override
  Future<ProviderChallenge> challenge({
    required AuthProviderKind provider,
    required ProviderAuthPurpose purpose,
    String? guestBearer,
  }) async {
    final needsBinding =
        purpose == ProviderAuthPurpose.login ||
        purpose == ProviderAuthPurpose.continueWith;
    return ProviderChallenge(
      provider: provider,
      purpose: purpose,
      nonce: 'n' * 43,
      binding: needsBinding ? 'binding' : null,
    );
  }

  @override
  Future<ProviderCredentialBundle> login({
    required AuthProviderKind provider,
    required String idToken,
    required String nonce,
    required String binding,
  }) async {
    loginCalls++;
    return ProviderCredentialBundle(
      playerId: loginPlayerId,
      accountType: 'verified',
      accessToken: _jwt(
        sub: loginPlayerId,
        accountType: 'verified',
        fid: 'login-fid',
      ),
      refreshToken: 'v' * 64,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      linkedProviders: [provider.name],
    );
  }

  @override
  Future<ProviderCredentialBundle> link({
    required AuthProviderKind provider,
    required String idToken,
    required String nonce,
    required String guestBearer,
  }) async {
    linkCalls++;
    if (linkError != null) throw linkError!;
    return ProviderCredentialBundle(
      playerId: linkPlayerId,
      accountType: 'verified',
      accessToken: _jwt(
        sub: linkPlayerId,
        accountType: 'verified',
        fid: 'link-fid',
      ),
      refreshToken: 'l' * 64,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      linkedProviders: [provider.name],
    );
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

  String? lastRecoverOperationId;
  String? lastContinueOperationId;
  String? lastConfirmOperationId;
  var recoverLinkedCalls = 0;

  @override
  Future<ProviderCredentialBundle> recoverLinked({
    required AuthProviderKind provider,
    required String idToken,
    required String nonce,
    required String binding,
    required String operationId,
    String? sourceGuestPlayerId,
    String? expectedTargetPlayerId,
  }) async {
    recoverLinkedCalls++;
    lastRecoverOperationId = operationId;
    return ProviderCredentialBundle(
      playerId: continuePlayerId,
      accountType: 'verified',
      accessToken: _jwt(
        sub: continuePlayerId,
        accountType: 'verified',
        fid: 'recover-fid',
      ),
      refreshToken: 'r' * 64,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      linkedProviders: [provider.name],
    );
  }

  @override
  Future<ProviderCredentialBundle> continueWithProvider({
    required AuthProviderKind provider,
    required String idToken,
    required String nonce,
    required String binding,
    required String operationId,
    bool localProgressProtected = false,
    String? guestBearer,
  }) async {
    continueCalls++;
    lastContinueOperationId = operationId;
    if (continueError != null) throw continueError!;
    return ProviderCredentialBundle(
      playerId: continuePlayerId,
      accountType: 'verified',
      accessToken: _jwt(
        sub: continuePlayerId,
        accountType: 'verified',
        fid: 'continue-fid',
      ),
      refreshToken: 'c' * 64,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      linkedProviders: [provider.name],
      resolution: 'existing_account',
    );
  }

  @override
  Future<ProviderCredentialBundle> confirmContinue({
    required String continuationToken,
    required String operationId,
  }) async {
    confirmContinueCalls++;
    lastConfirmOperationId = operationId;
    return ProviderCredentialBundle(
      playerId: continuePlayerId,
      accountType: 'verified',
      accessToken: _jwt(
        sub: continuePlayerId,
        accountType: 'verified',
        fid: 'continue-fid',
      ),
      refreshToken: 'c' * 64,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      linkedProviders: ['google'],
      resolution: 'existing_account',
    );
  }

  @override
  Future<void> logout({
    required String refreshToken,
    String? accessBearer,
  }) async {
    logoutCalls++;
    final delay = logoutDelay;
    if (delay != null) await delay.future;
    if (logoutError != null) throw logoutError!;
  }
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

  testWidgets('logout confirm cancel keeps verified profile state', (
    tester,
  ) async {
    await _pumpApp(tester, verified: true);
    await tester.tap(find.byKey(const Key('profile')));
    await _settle(tester);
    expect(find.byKey(const Key('profile-account-verified')), findsOneWidget);

    await tester.tap(find.byKey(const Key('profile-sign-out')));
    await _settle(tester);
    expect(find.byKey(const Key('profile-sign-out-dialog')), findsOneWidget);

    await tester.tap(find.byKey(const Key('profile-sign-out-cancel')));
    await _settle(tester);
    expect(find.byKey(const Key('profile-sign-out-dialog')), findsNothing);
    expect(find.byKey(const Key('profile-account-verified')), findsOneWidget);
    expect(find.byKey(const Key('profile-header')), findsOneWidget);
  });

  testWidgets('logout confirm shows loading and updates to guest live', (
    tester,
  ) async {
    final delay = Completer<void>();
    final providers = _ScriptedProviders(logoutDelay: delay);
    await _pumpApp(tester, verified: true, providers: providers);
    await tester.tap(find.byKey(const Key('profile')));
    await _settle(tester);

    await tester.tap(find.byKey(const Key('profile-sign-out')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('profile-sign-out-confirm')));
    // Dialog dismiss animation; logout remains blocked on Completer.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('profile-sign-out-dialog')), findsNothing);
    expect(find.byKey(const Key('profile-auth-busy')), findsOneWidget);
    // Sign-out is disabled while busy — no second dialog.
    expect(find.byKey(const Key('profile-sign-out')), findsNothing);

    delay.complete();
    await _settle(tester);
    expect(find.byKey(const Key('profile-auth-busy')), findsNothing);
    expect(find.byKey(const Key('profile-account-guest')), findsOneWidget);
    expect(find.byKey(const Key('auth-logout-success')), findsOneWidget);
    expect(find.byKey(const Key('profile-header')), findsOneWidget);
    expect(providers.logoutCalls, 1);
  });

  testWidgets(
    'PZD-54 real logout UI clears account-scoped day and shows Top Banner',
    (tester) async {
      await _pumpApp(tester, verified: true);
      final controller = tester
          .widget<AppTopBannerHost>(
            find.byKey(const Key('tournament-status-host')),
          )
          .controller;
      controller.day = TournamentDay(
        seriesId: 'series-logout-ui',
        original: true,
        claimStatus: 'COMPLETED',
        ordinal: 6,
        ordinalLabel: 'H1',
        seriesScore: 10200,
        resultsPublished: true,
      );
      controller.results = {'all': 10200, 'onTimeAwarded': true};
      controller.notifyListeners();

      await tester.tap(find.byKey(const Key('profile')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('profile-sign-out')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('profile-sign-out-confirm')));
      await _settle(tester);

      expect(controller.day, isNull);
      expect(controller.results, isEmpty);
      expect(find.byKey(const Key('auth-logout-success')), findsOneWidget);
      expect(find.byKey(const Key('profile-account-guest')), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets('failed logout shows localized failure feedback', (tester) async {
    final providers = _ScriptedProviders(
      logoutError: const ProviderAuthException('AUTH_UNAVAILABLE'),
    );
    await _pumpApp(tester, verified: true, providers: providers);
    await tester.tap(find.byKey(const Key('profile')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('profile-sign-out')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('profile-sign-out-confirm')));
    await _settle(tester);
    expect(find.byKey(const Key('auth-logout-failure')), findsOneWidget);
    expect(find.byKey(const Key('profile-account-verified')), findsOneWidget);
  });

  testWidgets('auth sheet shows only unified provider buttons', (tester) async {
    await _pumpApp(tester, verified: false);
    await tester.tap(find.byKey(const Key('profile')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('profile-sign-in')));
    await _settle(tester);
    expect(find.byKey(const Key('auth-link-section')), findsNothing);
    expect(find.byKey(const Key('auth-login-section')), findsNothing);
    expect(find.byKey(const Key('auth-google')), findsOneWidget);
    expect(find.byKey(const Key('auth-apple')), findsOneWidget);
    expect(find.byKey(const Key('auth-login-google')), findsNothing);
  });

  testWidgets(
    'existing Google continue after logout succeeds for empty guest',
    (tester) async {
      final providers = _ScriptedProviders(
        continuePlayerId: '11111111-1111-1111-1111-111111111111',
      );
      await _pumpApp(tester, verified: true, providers: providers);

      await tester.tap(find.byKey(const Key('profile')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('profile-sign-out')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('profile-sign-out-confirm')));
      await _settle(tester);
      expect(find.byKey(const Key('profile-account-guest')), findsOneWidget);

      await tester.tap(find.byKey(const Key('profile-sign-in')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('auth-google')));
      await _settle(tester);

      expect(find.byKey(const Key('auth-sheet-title')), findsNothing);
      expect(find.byKey(const Key('profile-account-verified')), findsOneWidget);
      expect(providers.continueCalls, 1);
      expect(providers.linkCalls, 0);
      expect(providers.loginCalls, 0);
      expect(find.byKey(const Key('offer-tray')), findsNothing);
      expect(find.byKey(const Key('profile-header')), findsOneWidget);
    },
  );

  testWidgets(
    'existing provider continue succeeds without guest-switch dialog',
    (tester) async {
      final providers = _ScriptedProviders();
      await _pumpApp(tester, verified: false, providers: providers);
      await tester.tap(find.byKey(const Key('profile')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('profile-sign-in')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('auth-google')));
      await _settle(tester);

      expect(find.byKey(const Key('account-switch-dialog')), findsNothing);
      expect(find.byKey(const Key('profile-account-verified')), findsOneWidget);
      expect(providers.continueCalls, 1);
      expect(providers.confirmContinueCalls, 0);
    },
  );

  testWidgets(
    'legacy account switch confirmation when continue requires confirm',
    (tester) async {
      final providers = _ScriptedProviders(
        continueError: const ProviderAuthException(
          'ACCOUNT_SWITCH_CONFIRMATION_REQUIRED',
          httpStatus: 409,
          continuationToken: 'switch-token-opaque',
          targetPlayerId: '11111111-1111-1111-1111-111111111111',
        ),
      );
      await _pumpApp(tester, verified: false, providers: providers);
      await tester.tap(find.byKey(const Key('profile')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('profile-sign-in')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('auth-google')));
      await _settle(tester);

      expect(find.byKey(const Key('account-switch-dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('account-switch-confirm')));
      await _settle(tester);

      expect(find.byKey(const Key('auth-sheet-title')), findsNothing);
      expect(find.byKey(const Key('profile-account-verified')), findsOneWidget);
      expect(providers.continueCalls, 1);
      expect(providers.confirmContinueCalls, 1);
    },
  );

  testWidgets('profile-only continue does not auto-start ranked play', (
    tester,
  ) async {
    final providers = _ScriptedProviders();
    await _pumpApp(tester, verified: false, providers: providers);
    await tester.tap(find.byKey(const Key('profile')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('profile-sign-in')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('auth-google')));
    await _settle(tester);
    expect(find.byKey(const Key('profile-account-verified')), findsOneWidget);
    expect(find.byKey(const Key('offer-tray')), findsNothing);
    expect(find.byKey(const Key('profile-header')), findsOneWidget);
    expect(providers.continueCalls, 1);
  });

  testWidgets('profile header and account card stay consistent after logout', (
    tester,
  ) async {
    // Static config label must not stick as "Verified" after guest switch.
    await _pumpApp(tester, verified: true, playerLabel: 'Verified');
    await tester.tap(find.byKey(const Key('profile')));
    await _settle(tester);
    expect(find.byKey(const Key('profile-header-verified')), findsOneWidget);
    expect(find.byKey(const Key('profile-account-verified')), findsOneWidget);
    expect(find.text('Doğrulanmış hesap'), findsNWidgets(2));

    await tester.tap(find.byKey(const Key('profile-sign-out')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('profile-sign-out-confirm')));
    await _settle(tester);

    expect(find.byKey(const Key('profile-header-guest')), findsOneWidget);
    expect(find.byKey(const Key('profile-account-guest')), findsOneWidget);
    expect(find.text('Misafir hesap'), findsNWidgets(2));
    expect(find.byKey(const Key('profile-header-verified')), findsNothing);
    expect(find.text('Verified'), findsNothing);
  });

  testWidgets(
    'delayed pre-logout badge response is discarded after account switch',
    (tester) async {
      final badgeGate = Completer<void>();
      final harness = await _pumpApp(
        tester,
        verified: true,
        badgeDelay: badgeGate,
        verifiedBadgeEarnedCount: 9,
      );
      await tester.tap(find.byKey(const Key('profile')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(harness.badgeRequests, greaterThanOrEqualTo(1));

      await tester.tap(find.byKey(const Key('profile-sign-out')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('profile-sign-out-confirm')));
      await _settle(tester);
      expect(find.byKey(const Key('profile-header-guest')), findsOneWidget);
      expect(find.byKey(const Key('profile-account-guest')), findsOneWidget);

      // Old verified badge payload arrives late — must be ignored.
      badgeGate.complete();
      await _settle(tester);
      expect(find.byKey(const Key('profile-header-guest')), findsOneWidget);
      expect(find.byKey(const Key('profile-account-guest')), findsOneWidget);
      expect(find.textContaining('9'), findsNothing);
      expect(find.text('9 kez kazanıldı', skipOffstage: false), findsNothing);
    },
  );

  testWidgets('cancel switch clears awaiting marker and keeps guest', (
    tester,
  ) async {
    final providers = _ScriptedProviders(
      continueError: const ProviderAuthException(
        'ACCOUNT_SWITCH_CONFIRMATION_REQUIRED',
        httpStatus: 409,
        continuationToken: 'switch-token-opaque',
        targetPlayerId: '11111111-1111-1111-1111-111111111111',
      ),
    );
    final harness = await _pumpApp(
      tester,
      verified: false,
      providers: providers,
    );
    await tester.tap(find.byKey(const Key('profile')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('profile-sign-in')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('auth-google')));
    await _settle(tester);
    expect(find.byKey(const Key('account-switch-dialog')), findsOneWidget);
    expect(harness.store.pendingLink, startsWith('awaiting|'));
    final awaiting = PendingLinkRecovery.tryParse(harness.store.pendingLink);
    expect(awaiting?.hasOperationBinding, isTrue);
    expect(providers.lastContinueOperationId, awaiting?.operationId);

    await tester.tap(find.byKey(const Key('account-switch-keep-guest')));
    await _settle(tester);
    expect(harness.store.pendingLink, isNull);
    expect(find.byKey(const Key('profile-account-guest')), findsOneWidget);
    expect(providers.confirmContinueCalls, 0);
  });

  test('confirm without durable awaiting/confirm intent is rejected', () async {
    final store = _MemStore()..token = 'g' * 64;
    const guestId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    session.debugSeedAccess(
      GuestAccess.parse(
        accessToken: _jwt(sub: guestId, accountType: 'guest', fid: 'guest-fid'),
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
    );
    final providers = _ScriptedProviders();
    final coordinator = AuthCoordinator(
      session: session,
      providers: providers,
      signIn: FakeProviderSignIn(),
    );
    final rejected = await coordinator.confirmAccountSwitch(
      'switch-token-opaque',
      targetPlayerId: '11111111-1111-1111-1111-111111111111',
      provider: AuthProviderKind.google,
    );
    expect(rejected.outcome, AuthFlowOutcome.failed);
    expect(rejected.errorCode, 'CONFIRM_INTENT_MISSING');
    expect(providers.confirmContinueCalls, 0);

    const operationId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
    await session.markPendingUnifiedAwaitingSwitch(
      provider: 'google',
      targetPlayerId: '11111111-1111-1111-1111-111111111111',
      operationId: operationId,
    );
    final cancelled = await coordinator.cancelAccountSwitch();
    expect(cancelled.errorCode, 'ACCOUNT_SWITCH_CANCELLED');
    expect(store.pendingLink, isNull);

    // Kill-before-confirm simulation: awaiting survives restart, recovery clears.
    await session.markPendingUnifiedAwaitingSwitch(
      provider: 'google',
      targetPlayerId: '11111111-1111-1111-1111-111111111111',
      operationId: operationId,
    );
    final restarted = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    restarted.debugSeedAccess(
      GuestAccess.parse(
        accessToken: _jwt(sub: guestId, accountType: 'guest', fid: 'guest-fid'),
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
    );
    final recoverCoordinator = AuthCoordinator(
      session: restarted,
      providers: providers,
      signIn: FakeProviderSignIn(),
    );
    final recovered = await recoverCoordinator.recoverPendingLink(
      AuthProviderKind.google,
    );
    expect(recovered.outcome, AuthFlowOutcome.cancelled);
    expect(recovered.errorCode, 'ACCOUNT_SWITCH_CANCELLED');
    expect(store.pendingLink, isNull);
    expect(providers.continueCalls, 0);
  });

  test(
    'confirm recovery carries exact operation binding; wrong binding rejected',
    () async {
      final store = _MemStore()..token = 'g' * 64;
      const guestId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
      const targetId = '11111111-1111-1111-1111-111111111111';
      const operationB = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
      final session = GuestAuthClient(
        origin: 'https://staging.puzzle-duel.app',
        credentials: store,
      );
      session.debugSeedAccess(
        GuestAccess.parse(
          accessToken: _jwt(
            sub: guestId,
            accountType: 'guest',
            fid: 'guest-fid',
          ),
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
      );
      session.debugTransport = (path, body) async {
        expect(path, '/v1/auth/refresh');
        return (status: 401, body: {'error': 'INVALID_REFRESH'});
      };
      final providers = _ScriptedProviders(continuePlayerId: targetId);
      final coordinator = AuthCoordinator(
        session: session,
        providers: providers,
        signIn: FakeProviderSignIn(),
      );

      await session.markPendingUnifiedConfirm(
        provider: 'google',
        targetPlayerId: targetId,
        operationId: operationB,
      );
      final recovered = await coordinator.recoverPendingLink(
        AuthProviderKind.google,
      );
      expect(recovered.outcome, AuthFlowOutcome.loggedIn);
      expect(providers.recoverLinkedCalls, 1);
      expect(providers.lastRecoverOperationId, operationB);
      expect(store.pendingLink, isNull);

      // Marker without operation binding must not authorize recovery.
      store.pendingLink = 'confirm|google|$targetId';
      expect(PendingLinkRecovery.tryParse(store.pendingLink), isNull);
      final session2 = GuestAuthClient(
        origin: 'https://staging.puzzle-duel.app',
        credentials: store,
      );
      session2.debugSeedAccess(
        GuestAccess.parse(
          accessToken: _jwt(
            sub: guestId,
            accountType: 'guest',
            fid: 'guest-fid',
          ),
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
      );
      final rejected = await AuthCoordinator(
        session: session2,
        providers: providers,
        signIn: FakeProviderSignIn(),
      ).recoverPendingLink(AuthProviderKind.google);
      expect(rejected.outcome, AuthFlowOutcome.failed);
      expect(rejected.errorCode, 'RECOVERY_MARKER_MISSING');
      expect(providers.recoverLinkedCalls, 1);
    },
  );

  test(
    'continue marker binds operation id used by mutate and recovery',
    () async {
      final store = _MemStore()..token = 'g' * 64;
      const guestId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
      final session = GuestAuthClient(
        origin: 'https://staging.puzzle-duel.app',
        credentials: store,
      );
      session.debugSeedAccess(
        GuestAccess.parse(
          accessToken: _jwt(
            sub: guestId,
            accountType: 'guest',
            fid: 'guest-fid',
          ),
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
      );
      session.debugTransport = (path, body) async {
        expect(path, '/v1/auth/refresh');
        return (status: 401, body: {'error': 'INVALID_REFRESH'});
      };
      final providers = _ScriptedProviders(
        continueError: const ProviderAuthException(
          'AUTH_NETWORK_UNAVAILABLE',
          httpStatus: 0,
        ),
      );
      final coordinator = AuthCoordinator(
        session: session,
        providers: providers,
        signIn: FakeProviderSignIn(),
      );
      final result = await coordinator.continueWithProvider(
        AuthProviderKind.google,
        localProgressProtected: false,
      );
      expect(result.outcome, AuthFlowOutcome.recoveryRequired);
      final pending = PendingLinkRecovery.tryParse(store.pendingLink);
      expect(pending?.kind, PendingAuthRecoveryKind.unifiedContinue);
      expect(pending?.hasOperationBinding, isTrue);
      expect(providers.lastContinueOperationId, pending?.operationId);

      final recovered = await coordinator.recoverPendingLink(
        AuthProviderKind.google,
      );
      expect(recovered.outcome, AuthFlowOutcome.loggedIn);
      expect(providers.lastRecoverOperationId, pending?.operationId);
    },
  );

  test('session survives restart after existing-account login', () async {
    final store = _MemStore()..token = 'g' * 64;
    const guestId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    const verifiedId = '11111111-1111-1111-1111-111111111111';
    final session = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    session.debugSeedAccess(
      GuestAccess.parse(
        accessToken: _jwt(sub: guestId, accountType: 'guest'),
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
    );
    final providers = _ScriptedProviders(loginPlayerId: verifiedId);
    final coordinator = AuthCoordinator(
      session: session,
      providers: providers,
      signIn: FakeProviderSignIn(),
    );
    final result = await coordinator.loginExisting(AuthProviderKind.google);
    expect(result.outcome, AuthFlowOutcome.loggedIn);
    expect(store.token, 'v' * 64);

    // Simulate process restart with the same vault.
    final restarted = GuestAuthClient(
      origin: 'https://staging.puzzle-duel.app',
      credentials: store,
    );
    restarted.debugTransport = (path, body) async {
      expect(path, '/v1/auth/refresh');
      return (
        status: 200,
        body: {
          'accessToken': _jwt(
            sub: verifiedId,
            accountType: 'verified',
            fid: 'login-fid',
          ),
          'refreshToken': 'v' * 64,
          'expiresAt': DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .toIso8601String(),
        },
      );
    };
    await restarted.reconcilePersistedVault();
    final restored = await restarted.authenticate(allowGuestCreate: false);
    expect(restored.isVerified, isTrue);
    expect(restored.playerId, verifiedId);
  });
}

final class _Harness {
  var claimPosts = 0;
  var badgeRequests = 0;
  late GuestAuthClient session;
  late _MemStore store;
}

Future<_Harness> _pumpApp(
  WidgetTester tester, {
  required bool verified,
  _ScriptedProviders? providers,
  String? playerLabel,
  Completer<void>? badgeDelay,
  int verifiedBadgeEarnedCount = 2,
}) async {
  final directory = Directory.systemTemp.createTempSync(
    'pzd27-login-logout-ux',
  );
  addTearDown(() => directory.deleteSync(recursive: true));

  const guestId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  const verifiedId = '11111111-1111-1111-1111-111111111111';
  final playerId = verified ? verifiedId : guestId;
  final token = _jwt(
    sub: playerId,
    accountType: verified ? 'verified' : 'guest',
    fid: verified ? 'verified-fid' : 'guest-fid',
  );
  final store = _MemStore()..token = verified ? 'v' * 64 : 'g' * 64;
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

  final scripted = providers ?? _ScriptedProviders();
  final guestSession = GuestAuthClient(
    origin: 'https://staging.puzzle-duel.app',
    credentials: store,
  );
  guestSession.debugTransport = (path, body) async {
    if (path == '/v1/auth/guest') {
      final newId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
      return (
        status: 201,
        body: {
          'accessToken': _jwt(sub: newId, accountType: 'guest'),
          'refreshToken': 'n' * 64,
          'expiresAt': DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .toIso8601String(),
        },
      );
    }
    if (path == '/v1/auth/refresh') {
      return (
        status: 200,
        body: {
          'accessToken': token,
          'refreshToken': store.token ?? 'g' * 64,
          'expiresAt': DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .toIso8601String(),
        },
      );
    }
    return (status: 404, body: <String, dynamic>{'error': 'NOT_FOUND'});
  };
  guestSession.debugSeedAccess(
    GuestAccess.parse(
      accessToken: token,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    ),
  );

  final coordinator = AuthCoordinator(
    session: guestSession,
    providers: scripted,
    signIn: FakeProviderSignIn(),
  );

  final harness = _Harness()
    ..session = guestSession
    ..store = store;
  var firstBadgeDelayed = false;
  final api = ScriptedUatApi((method, path, body) async {
    if (path == '/v1/tournament/claims/daily' && method == 'POST') {
      harness.claimPosts++;
      if (verified) {
        return const UatHttpResult(200, {
          'seriesId': '11111111-1111-4111-8111-111111111111',
          'originalUtcDate': '2026-11-19',
          'status': 'ACTIVE',
          'original': false,
          'writerGeneration': 1,
        });
      }
      fail('guest ranked gate must not claim from profile auth sheet');
    }
    if (path == '/v1/tournament/session' && method == 'POST') {
      return UatHttpResult(201, {
        'playerId': playerId,
        'sessionSecret': 'secret',
        'sessionId': 's1',
      });
    }
    if (path.startsWith('/v1/tournament/series/') && method == 'GET') {
      return const UatHttpResult(200, {
        'seriesId': '11111111-1111-4111-8111-111111111111',
        'status': 'ACTIVE',
        'boardRevision': 1,
      });
    }
    if (path == '/v1/profile/me/badges' || path == '/v1/tournament/me/badges') {
      harness.badgeRequests++;
      final delay = badgeDelay;
      if (delay != null && !firstBadgeDelayed) {
        firstBadgeDelayed = true;
        await delay.future;
        // Always return the pre-switch verified payload for the delayed call.
        return UatHttpResult(200, {
          'playerScoped': true,
          'catalogVersion': 1,
          'badges': [
            {
              'badgeId': 'on_time',
              'earnedCount': verifiedBadgeEarnedCount,
              'lastEarnedAt': '2026-11-18',
              'repeatable': true,
              'provenance': 'f2b_publication',
              'grants': [],
            },
          ],
        });
      }
      final showVerifiedBadges = guestSession.cachedAccess?.isVerified == true;
      return UatHttpResult(200, {
        'playerScoped': true,
        'catalogVersion': 1,
        'badges': [
          if (showVerifiedBadges)
            {
              'badgeId': 'on_time',
              'earnedCount': verifiedBadgeEarnedCount,
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

  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    TournamentUatApp(
      config: UatConfig(
        baseUrl: 'https://staging.puzzle-duel.app',
        bearer: token,
        playerLabel: playerLabel ?? (verified ? 'Verified' : 'Guest'),
      ),
      api: api,
      stateDirectory: directory,
      sessionAuth: guestSession,
      authCoordinator: coordinator,
      haptics: const SilentTournamentHaptics(),
      locale: const Locale('tr'),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 80; i++) {
    if (find.byKey(const Key('profile')).evaluate().isNotEmpty) break;
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(find.byKey(const Key('profile')), findsOneWidget);
  return harness;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 50; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
