import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'crash_reporter.dart';
import 'puzzle_duel_logger.dart';

/// Explicitly opt in only after platform Firebase files are provisioned.
/// Builds without Firebase configuration keep the no-op crash reporter.
final class FirebaseDiagnostics {
  FirebaseDiagnostics._();
  static bool enabled = false;
  static const bool stagingDiagnosticsEnabled =
      bool.fromEnvironment('PZD_STAGING_DIAGNOSTICS', defaultValue: false) &&
      bool.fromEnvironment('PZD_FIREBASE_CONFIGURED', defaultValue: false) &&
      const String.fromEnvironment('PZD_DIAGNOSTIC_ENV') == 'staging';

  static Future<void> sendTestNonFatal() async {
    if (!stagingDiagnosticsEnabled || !enabled) return;
    await FirebaseCrashlytics.instance.log('PZDProfile:: test_nonfatal called');
    await FirebaseCrashlytics.instance.recordError(
      StateError('PZD_STAGING_TEST_NONFATAL'), StackTrace.current,
      reason: 'Staging diagnostics verification', fatal: false,
    );
  }

  static Future<void> forceTestCrash() async {
    if (!stagingDiagnosticsEnabled || !enabled) return;
    await FirebaseCrashlytics.instance.log('PZDProfile:: test_crash called');
    FirebaseCrashlytics.instance.crash();
  }
  static Future<CrashReporter> initialize() async {
    const configured = bool.fromEnvironment('PZD_FIREBASE_CONFIGURED', defaultValue: false);
    if (!configured) return const NoopCrashReporter();
    try {
      await Firebase.initializeApp();
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
      enabled = true;
      return FirebaseCrashReporter();
    } catch (_) {
      enabled = false;
      return const NoopCrashReporter();
    }
  }
}

final class FirebaseCrashReporter implements CrashReporter {
  @override
  Future<void> recordFatal(Object error, StackTrace stack) =>
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  @override
  Future<void> recordNonFatal(Object error, StackTrace stack) =>
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: false);
}

/// Crash breadcrumbs only; no arbitrary user-provided text.
final class CrashlyticsLogSink implements LogSink {
  @override
  Future<void> write(LogEvent event) async {
    if (!FirebaseDiagnostics.enabled) return;
    final phase = switch (event.code) {
      LogCode.httpStarted => 'called',
      LogCode.httpCompleted => 'success',
      LogCode.httpFailed => 'failed',
      LogCode.screenOpened => 'screenOpened called',
      _ => event.code.name,
    };
    final details = [
      if (event.requestId != null) 'requestId=${event.requestId}',
      if (event.traceId != null) 'traceId=${event.traceId}',
      if (event.httpStatus != null) 'status=${event.httpStatus}',
      if (event.durationMs != null) 'durationMs=${event.durationMs}',
    ].join(' ');
    await FirebaseCrashlytics.instance.log(
      '${event.operation}:: $phase${details.isEmpty ? '' : ' $details'}',
    );
    if (event.requestId != null) {
      await FirebaseCrashlytics.instance.setCustomKey('last_request_id', event.requestId!);
    }
  }
}
