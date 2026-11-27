import 'dart:async';

import 'puzzle_duel_logger.dart';

/// Outcome of an attempted crash/non-fatal record. Callers must not treat a
/// completed Future alone as Firebase acceptance — Noop completes without SDK.
enum CrashRecordOutcome {
  recorded,
  skippedNotConfigured,
  skippedDisabled,
  failed,
}

/// SDK-independent crash reporting port. The Firebase implementation can be
/// installed later without changing event schema or logging credentials.
abstract interface class CrashReporter {
  /// True only when a real Crashlytics SDK sink is active.
  bool get isActive;

  Future<CrashRecordOutcome> recordFatal(Object error, StackTrace stack);
  Future<CrashRecordOutcome> recordNonFatal(Object error, StackTrace stack);
}

final class NoopCrashReporter implements CrashReporter {
  const NoopCrashReporter({
    this.reason = CrashRecordOutcome.skippedNotConfigured,
  });

  final CrashRecordOutcome reason;

  @override
  bool get isActive => false;

  @override
  Future<CrashRecordOutcome> recordFatal(Object error, StackTrace stack) async =>
      reason;

  @override
  Future<CrashRecordOutcome> recordNonFatal(
    Object error,
    StackTrace stack,
  ) async =>
      reason;
}

final class DiagnosticCrashHandler {
  DiagnosticCrashHandler({
    required this.logger,
    required this.reporter,
  });

  final PuzzleDuelLogger logger;
  final CrashReporter reporter;

  Future<void> capture(Object error, StackTrace stack, {bool fatal = false}) async {
    await logger.log(LogEvent(
      level: fatal ? LogLevel.fatal : LogLevel.error,
      code: LogCode.diagnosticFailure,
      operation: 'uncaught_exception',
    ));
    try {
      final outcome = fatal
          ? await reporter.recordFatal(error, stack)
          : await reporter.recordNonFatal(error, stack);
      if (outcome == CrashRecordOutcome.skippedNotConfigured ||
          outcome == CrashRecordOutcome.skippedDisabled) {
        await logger.log(LogEvent(
          level: LogLevel.info,
          code: LogCode.diagnosticFailure,
          operation: 'crashlytics_record_skipped',
          errorCode: outcome == CrashRecordOutcome.skippedDisabled
              ? 'CRASHLYTICS_DISABLED'
              : 'CRASHLYTICS_NOT_CONFIGURED',
        ));
      } else if (outcome == CrashRecordOutcome.failed) {
        await logger.log(LogEvent(
          level: LogLevel.warning,
          code: LogCode.diagnosticFailure,
          operation: 'crashlytics_record_failed',
          errorCode: 'CRASHLYTICS_RECORD_FAILED',
        ));
      }
    } catch (_) {
      // Reporting failures must not recursively crash the application.
    }
  }
}
