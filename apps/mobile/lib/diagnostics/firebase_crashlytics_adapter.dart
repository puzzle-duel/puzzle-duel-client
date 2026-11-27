import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:puzzle_duel_mobile/diagnostics/crash_reporter.dart';
import 'package:puzzle_duel_mobile/diagnostics/diagnostic_policy.dart';
import 'package:puzzle_duel_mobile/diagnostics/diagnostic_runtime.dart';
import 'package:puzzle_duel_mobile/diagnostics/puzzle_duel_logger.dart';

/// Privacy-safe Firebase Crashlytics initialization state for Settings/UAT.
enum FirebaseInitState {
  notConfigured,
  unsupportedEnvironment,
  started,
  succeeded,
  failed,
  collectionUnavailable,
  enabled,
}

/// Explicitly opt in only after platform Firebase files are provisioned.
/// Builds without Firebase configuration keep the no-op crash reporter.
final class FirebaseDiagnostics {
  FirebaseDiagnostics._();
  static bool enabled = false;
  static FirebaseInitState initState = FirebaseInitState.notConfigured;
  static String? initFailureCode;

  static bool get stagingDiagnosticsEnabled =>
      bool.fromEnvironment('PZD_STAGING_DIAGNOSTICS', defaultValue: false) &&
      bool.fromEnvironment('PZD_FIREBASE_CONFIGURED', defaultValue: false) &&
      DiagnosticPolicy.fromBuild() == DiagnosticEnvironment.staging;

  static String get readinessMessage {
    switch (initState) {
      case FirebaseInitState.enabled:
      case FirebaseInitState.succeeded:
        return 'Crashlytics hazır';
      case FirebaseInitState.started:
        return 'Crashlytics başlatılıyor';
      case FirebaseInitState.notConfigured:
        return 'Firebase Crashlytics staging yapılandırması gerekli';
      case FirebaseInitState.unsupportedEnvironment:
        return 'Crashlytics yalnızca staging build\'de etkin';
      case FirebaseInitState.collectionUnavailable:
        return 'Crashlytics koleksiyonu kullanılamıyor';
      case FirebaseInitState.failed:
        return 'Crashlytics başlatılamadı'
            '${initFailureCode == null ? '' : ' ($initFailureCode)'}';
    }
  }

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
    if (!configured) {
      initState = FirebaseInitState.notConfigured;
      initFailureCode = 'FIREBASE_NOT_CONFIGURED';
      enabled = false;
      return const NoopCrashReporter(
        reason: CrashRecordOutcome.skippedNotConfigured,
      );
    }
    try {
      if (DiagnosticPolicy.fromBuild() != DiagnosticEnvironment.staging) {
        initState = FirebaseInitState.unsupportedEnvironment;
        initFailureCode = 'FIREBASE_UNSUPPORTED_ENV';
        enabled = false;
        return const NoopCrashReporter(
          reason: CrashRecordOutcome.skippedDisabled,
        );
      }
      initState = FirebaseInitState.started;
      initFailureCode = null;
      unawaited(DiagnosticRuntime.logger.log(LogEvent(
        level: LogLevel.info,
        code: LogCode.applicationStarted,
        operation: 'firebase_initialization_started',
      )));
      final options = Platform.isIOS
          ? const FirebaseOptions(
              apiKey: 'AIzaSyBkSs4k4ELH9YrHoYuB4PPXACyhKZNBVyU',
              appId: '1:450107669068:ios:9ad1bc000cda2b217052e9',
              messagingSenderId: '450107669068',
              projectId: 'puzzle-duel-staging',
              storageBucket: 'puzzle-duel-staging.firebasestorage.app',
              iosBundleId: 'app.puzzleduel.puzzleDuelMobile',
            )
          : const FirebaseOptions(
              apiKey: 'AIzaSyBPGargd2FzUAmIUUiVNCHTLmMDA8SZNII',
              appId: '1:450107669068:android:0eec2e5e3208c0747052e9',
              messagingSenderId: '450107669068',
              projectId: 'puzzle-duel-staging',
              storageBucket: 'puzzle-duel-staging.firebasestorage.app',
            );
      await Firebase.initializeApp(options: options);
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
      enabled = true;
      initState = FirebaseInitState.enabled;
      unawaited(DiagnosticRuntime.logger.log(LogEvent(
        level: LogLevel.info,
        code: LogCode.applicationStarted,
        operation: 'firebase_initialization_completed',
      )));
      return FirebaseCrashReporter();
    } catch (_) {
      enabled = false;
      initState = FirebaseInitState.failed;
      initFailureCode = 'FIREBASE_INIT_FAILED';
      unawaited(DiagnosticRuntime.logger.log(LogEvent(
        level: LogLevel.warning,
        code: LogCode.diagnosticFailure,
        operation: 'firebase_initialization_failed',
        errorCode: 'FIREBASE_INIT_FAILED',
      )));
      return const NoopCrashReporter(
        reason: CrashRecordOutcome.failed,
      );
    }
  }
}

final class FirebaseCrashReporter implements CrashReporter {
  @override
  bool get isActive => true;

  @override
  Future<CrashRecordOutcome> recordFatal(Object error, StackTrace stack) async {
    try {
      await FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return CrashRecordOutcome.recorded;
    } catch (_) {
      return CrashRecordOutcome.failed;
    }
  }

  @override
  Future<CrashRecordOutcome> recordNonFatal(
    Object error,
    StackTrace stack,
  ) async {
    try {
      await FirebaseCrashlytics.instance.recordError(error, stack, fatal: false);
      return CrashRecordOutcome.recorded;
    } catch (_) {
      return CrashRecordOutcome.failed;
    }
  }
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
      if (event.errorCode != null) 'errorCode=${event.errorCode}',
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
