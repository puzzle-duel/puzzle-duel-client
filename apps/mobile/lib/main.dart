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
  // Guest-first offline bootstrap: no network, auth, ads, or analytics.
  runPuzzleDuelApp(GameSession());
}
