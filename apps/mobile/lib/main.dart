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
import 'package:puzzle_duel_mobile/tournament/named_staging_enrollment.dart';
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
  await _launchStaging();
}

Future<void> _launchStaging() async {
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
      final namedPlayer = guestSlot == 'gokhan' || guestSlot == 'serap';
      final store = SecureGuestCredentialStore(slot: slot);
      // Named staging identities must never silently become new guests.
      // The matching Oracle-issued refresh token must first be imported
      // through a separate, approved secure device enrollment flow.
      if (namedPlayer && (await store.readRefreshToken()) == null) {
        runApp(NamedStagingEnrollmentScreen(
          origin: staging,
          store: store,
          slot: guestSlot,
          onEnrolled: _launchStaging,
        ));
        return;
      }
      // A named slot is bound to its server-issued subject, not a UI label.
      // The expected UUID is non-secret configuration, obtained from the
      // authoritative staging DB via the approved enrollment workflow.
      final expectedSubject = namedPlayer ? (await store.readNamedPlayerId() ?? '') : '';
      const configuredExpectedSubject = String.fromEnvironment('PZD_STAGING_EXPECTED_PLAYER_ID');
      if (namedPlayer && configuredExpectedSubject.isNotEmpty &&
          configuredExpectedSubject.toLowerCase() != expectedSubject.toLowerCase()) {
        runApp(const StagingStartupErrorScreen('NAMED_PLAYER_IDENTITY_MISMATCH'));
        return;
      }
      if (namedPlayer && !RegExp(r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$').hasMatch(expectedSubject)) {
        runApp(const StagingStartupErrorScreen('NAMED_PLAYER_BINDING_REQUIRED'));
        return;
      }
      final auth = GuestAuthClient(
        origin: staging,
        credentials: store,
      );
      final access = await auth.authenticate();
      if (namedPlayer && access.sessionVaultBinding != 'staging-guest:$expectedSubject') {
        runApp(const StagingStartupErrorScreen('NAMED_PLAYER_IDENTITY_MISMATCH'));
        return;
      }
      await runTournamentUatApp(UatConfig(
        baseUrl: staging,
        bearer: access.accessToken,
        playerLabel: guestSlot == 'gokhan' ? 'Gökhan Aydın' : guestSlot == 'serap' ? 'Serap Nazlı Aydın' : 'Guest',
        stagingSessionBinding: access.sessionVaultBinding,
      ), api: UatApi(
        baseUrl: UatApi.apiOrigin(staging),
        bearer: access.accessToken,
        accessTokenProvider: () async {
          final refreshed = await auth.authenticate();
          if (namedPlayer && refreshed.sessionVaultBinding != 'staging-guest:$expectedSubject') {
            throw const GuestAuthException('NAMED_PLAYER_IDENTITY_MISMATCH');
          }
          return refreshed.accessToken;
        },
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

