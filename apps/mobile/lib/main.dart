import 'dart:async';
import 'dart:ui';

import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/diagnostics/crash_reporter.dart';
import 'package:puzzle_duel_mobile/diagnostics/firebase_crashlytics_adapter.dart';
import 'package:puzzle_duel_mobile/diagnostics/diagnostic_runtime.dart';
import 'package:puzzle_duel_mobile/diagnostics/puzzle_duel_logger.dart';
import 'package:puzzle_duel_mobile/app/portrait_lock.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_uat_app.dart';
import 'package:puzzle_duel_mobile/tournament/guest_auth.dart';
import 'package:puzzle_duel_mobile/tournament/guest_secure_store.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Render a native Flutter frame immediately, before Firebase/network auth.
  // A cold launch must never sit on a black screen while HTTPS times out.
  runApp(const StagingStartupLoadingScreen());
  final CrashReporter crashReporter;
  try {
    crashReporter = await FirebaseDiagnostics.initialize();
  } on Exception {
    // Never strand the device on a loading screen if native Firebase fails.
    runApp(const StagingStartupErrorScreen('FIREBASE_STARTUP_UNAVAILABLE'));
    return;
  }
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
  // Staging release entrypoint: the tournament shell is the only application.
  // Never route to the legacy offline difficulty menu, even with missing flags.
  const staging = String.fromEnvironment('PZD_STAGING_BASE_URL');
  if (staging.isEmpty) {
    runApp(const StagingStartupErrorScreen('STAGING_BASE_URL_MISSING'));
    return;
  }
  if (staging.isNotEmpty) {
    try {
      // Explicit UAT selection, independent of Git worktree and iOS bundle ID.
      // Legacy remains the default so existing Player B tokens are not moved.
      const guestSlot = String.fromEnvironment(
        'PZD_STAGING_GUEST_SLOT',
        defaultValue: 'legacy',
      );
      final slot = StagingGuestSlot.parse(guestSlot);
      final auth = GuestAuthClient(
        origin: staging,
        credentials: SecureGuestCredentialStore(slot: slot),
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
      ), stagingGuestSlot: guestSlot);
    } on GuestAuthException catch (error) {
      // A guest identity must never be replaced by an offline session.
      runApp(StagingStartupErrorScreen(error.code));
    } on Exception {
      // Never show raw exceptions, URLs, tokens, or response bodies.
      runApp(const StagingStartupErrorScreen('STAGING_CONFIGURATION_UNAVAILABLE'));
    }
    return;
  }
  runApp(const StagingStartupErrorScreen('STAGING_CONFIGURATION_UNAVAILABLE'));
}


@visibleForTesting
final class StagingStartupLoadingScreen extends StatelessWidget {
  const StagingStartupLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Puzzle Duel',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Connecting to tournament…'),
            ],
          ),
        ),
      ),
    );
  }
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

