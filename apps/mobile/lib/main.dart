import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:puzzle_duel_mobile/diagnostics/crash_reporter.dart';
import 'package:puzzle_duel_mobile/diagnostics/firebase_crashlytics_adapter.dart';
import 'package:puzzle_duel_mobile/diagnostics/diagnostic_runtime.dart';
import 'package:puzzle_duel_mobile/diagnostics/puzzle_duel_logger.dart';
import 'package:puzzle_duel_mobile/app/portrait_lock.dart';
import 'package:puzzle_duel_mobile/app/puzzle_duel_app.dart';
import 'package:puzzle_duel_mobile/application/game_session.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_uat_app.dart';
import 'package:puzzle_duel_mobile/tournament/guest_auth.dart';
import 'package:puzzle_duel_mobile/tournament/guest_secure_store.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final crashReporter = await FirebaseDiagnostics.initialize();
  final crashHandler = DiagnosticCrashHandler(
    logger: DiagnosticRuntime.logger,
    reporter: crashReporter,
  );
  final previousFlutterHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    previousFlutterHandler?.call(details);
    unawaited(crashHandler.capture(details.exception, details.stack ?? StackTrace.empty, fatal: true));
  };
  final previousPlatformHandler = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(crashHandler.capture(error, stack, fatal: true));
    return previousPlatformHandler?.call(error, stack) ?? false;
  };
  unawaited(DiagnosticRuntime.logger.log(LogEvent(
    level: LogLevel.info,
    code: LogCode.applicationStarted,
    operation: 'app_bootstrap',
  )));
  await lockPortraitOrientation();
  const base = String.fromEnvironment('PZD_UAT_BASE_URL');
  const bearer = String.fromEnvironment('PZD_UAT_BEARER');
  const player = String.fromEnvironment('PZD_UAT_PLAYER');
  if (base.isNotEmpty && bearer.isNotEmpty) {
    await runTournamentUatApp(
      UatConfig(
        baseUrl: base,
        bearer: bearer,
        // Display-only label. Never used as practice persistence identity.
        playerLabel: player.isEmpty ? 'UAT player' : player,
      ),
    );
    return;
  }
  // Staging guest mode is explicit. A failed auth must never generate an
  // alternate identity or block offline practice.
  const staging = String.fromEnvironment('PZD_STAGING_BASE_URL');
  if (staging.isNotEmpty) {
    try {
      final auth = GuestAuthClient(
        origin: staging,
        credentials: const SecureGuestCredentialStore(),
      );
      final access = await auth.authenticate();
      await runTournamentUatApp(UatConfig(
        baseUrl: staging,
        bearer: access.accessToken,
        playerLabel: 'Guest',
        stagingSessionBinding: access.sessionVaultBinding,
      ), api: UatApi(
        baseUrl: UatApi.apiOrigin(staging),
        bearer: access.accessToken,
        accessTokenProvider: () async => (await auth.authenticate()).accessToken,
      ));
      return;
    } on GuestAuthException {
      // Offline Practice remains available; no credentials in diagnostics.
    } on Exception {
      // Configuration/storage errors also fail closed to offline Practice.
    }
  }
  runPuzzleDuelApp(GameSession());
}
