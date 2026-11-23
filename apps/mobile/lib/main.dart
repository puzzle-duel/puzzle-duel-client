import 'dart:async';
import 'dart:ui';
import 'dart:math';

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
      final namedPlayer = guestSlot == 'gokhan' || guestSlot == 'serap';
      final store = SecureGuestCredentialStore(slot: slot);
      // Named staging identities must never silently become new guests.
      // The matching Oracle-issued refresh token must first be imported
      // through a separate, approved secure device enrollment flow.
      if (namedPlayer && (await store.readRefreshToken()) == null) {
        runApp(NamedPlayerEnrollmentScreen(
          origin: staging,
          slot: slot,
          onComplete: () { unawaited(main()); },
        ));
        return;
      }
      // Binding is pinned on-device during the one-time authorized enrollment.
      // Neither a Dart define nor a display name is an authentication proof.
      final expectedSubject = namedPlayer ? await store.readNamedPlayerId() : null;
      if (namedPlayer && (expectedSubject == null ||
          !RegExp(r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}
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
final class NamedPlayerEnrollmentScreen extends StatefulWidget {
  const NamedPlayerEnrollmentScreen({
    required this.origin,
    required this.slot,
    required this.onComplete,
    super.key,
  });

  final String origin;
  final StagingGuestSlot slot;
  final VoidCallback onComplete;

  @override
  State<NamedPlayerEnrollmentScreen> createState() => _NamedPlayerEnrollmentScreenState();
}

final class _NamedPlayerEnrollmentScreenState extends State<NamedPlayerEnrollmentScreen> {
  late final String code = List<int>.generate(16, (_) => Random.secure().nextInt(256))
      .map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  bool working = false;
  String? error;

  Future<void> enroll() async {
    if (working) return;
    setState(() { working = true; error = null; });
    try {
      final store = SecureGuestCredentialStore(slot: widget.slot);
      final access = await GuestAuthClient(origin: widget.origin, credentials: store)
          .enrollNamedDevice(code);
      final subject = access.sessionVaultBinding.substring('staging-guest:'.length);
      await store.saveNamedPlayerId(subject);
      if (!mounted) return;
      widget.onComplete();
    } on Exception {
      if (mounted) setState(() => error = 'Authorization not ready or expired. Check the staging workflow.');
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Puzzle Duel Staging',
    home: Scaffold(
      appBar: AppBar(title: const Text('Staging device pairing')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.slot == StagingGuestSlot.gokhan ? 'Gökhan Aydın' : 'Serap Nazlı Aydın'),
              const SizedBox(height: 20),
              const Text('In GitHub Actions run "Authorize named iOS staging enrollment" '
                  'on version/0.0.2. Select the matching player and enter this device code:'),
              const SizedBox(height: 16),
              SelectableText(code, key: const Key('named-enrollment-code')),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: working ? null : enroll,
                child: Text(working ? 'Connecting…' : 'Complete pairing'),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!, key: const Key('named-enrollment-error')),
              ],
            ],
          ),
        ),
      ),
    ),
  );
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

).hasMatch(expectedSubject))) {
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

