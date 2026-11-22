import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart';
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
  // A staging build must NEVER silently switch to offline Practice.
  // Fail visibly when the HTTPS endpoint is missing or authentication fails.
  const staging = String.fromEnvironment('PZD_STAGING_BASE_URL');
  const diagnosticEnv = String.fromEnvironment('PZD_DIAGNOSTIC_ENV');
  const stagingBuild = diagnosticEnv == 'staging' ||
      bool.fromEnvironment('PZD_STAGING_DIAGNOSTICS');
  if (staging.isEmpty && stagingBuild) {
    runApp(const StagingStartupErrorScreen('STAGING_BASE_URL_MISSING'));
    return;
  }
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
    } on GuestAuthException catch (error) {
      // A guest identity must never be replaced by an offline session.
      runApp(StagingStartupErrorScreen(error.code));
    } on Exception {
      // Never show raw exceptions, URLs, tokens, or response bodies.
      runApp(const StagingStartupErrorScreen('STAGING_CONFIGURATION_UNAVAILABLE'));
    }
    return;
  }
  runPuzzleDuelApp(GameSession());
}

/// This is shown ONLY for staging configuration/auth failures.
@visibleForTesting
final class StagingStartupErrorScreen extends StatelessWidget {
  const StagingStartupErrorScreen(this.errorCode, {super.key});

  final String errorCode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Puzzle Duel Staging',
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Tournament staging unavailable'),
              const SizedBox(height: 12),
              Text(errorCode, key: const Key('staging-startup-error')),
              const SizedBox(height: 12),
              const Text('Check staging HTTPS configuration and restart the app.'),
            ],
          ),
        ),
      ),
    );
  }
}

