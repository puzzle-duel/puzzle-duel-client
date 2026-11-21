import 'dart:async';

import 'puzzle_duel_logger.dart';

/// SDK-independent crash reporting port. The Firebase implementation can be
/// installed later without changing event schema or logging credentials.
abstract interface class CrashReporter {
  Future<void> recordFatal(Object error, StackTrace stack);
  Future<void> recordNonFatal(Object error, StackTrace stack);
}

final class NoopCrashReporter implements CrashReporter {
  const NoopCrashReporter();
  @override
  Future<void> recordFatal(Object error, StackTrace stack) async {}
  @override
  Future<void> recordNonFatal(Object error, StackTrace stack) async {}
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
      if (fatal) {
        await reporter.recordFatal(error, stack);
      } else {
        await reporter.recordNonFatal(error, stack);
      }
    } catch (_) {
      // Reporting failures must not recursively crash the application.
    }
  }
}
