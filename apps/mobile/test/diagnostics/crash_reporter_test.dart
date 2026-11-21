import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/diagnostics/crash_reporter.dart';
import 'package:puzzle_duel_mobile/diagnostics/puzzle_duel_logger.dart';

final class _Reporter implements CrashReporter {
  int fatal = 0;
  int nonFatal = 0;
  @override
  Future<void> recordFatal(Object error, StackTrace stack) async => fatal++;
  @override
  Future<void> recordNonFatal(Object error, StackTrace stack) async => nonFatal++;
}

final class _StalledSink implements LogSink {
  final Completer<void> gate = Completer<void>();
  @override
  Future<void> write(LogEvent event) => gate.future;
}

void main() {
  test('crash handler routes fatal and nonfatal without raw exception logs', () async {
    final buffer = RingBufferLogSink();
    final reporter = _Reporter();
    final logger = PuzzleDuelLogger(sinks: [buffer]);
    final handler = DiagnosticCrashHandler(logger: logger, reporter: reporter);
    await handler.capture(StateError('sensitive-secret'), StackTrace.empty, fatal: true);
    await handler.capture(StateError('sensitive-secret'), StackTrace.empty);
    await logger.flush();
    expect(reporter.fatal, 1);
    expect(reporter.nonFatal, 1);
    expect(buffer.snapshot(), hasLength(2));
    expect(buffer.snapshot().first.toJson().toString(), isNot(contains('sensitive-secret')));
  });

  test('stalled sink is bounded and flush times out', () async {
    final sink = _StalledSink();
    final logger = PuzzleDuelLogger(sinks: [sink], maxPendingPerSink: 2);
    for (var i = 0; i < 10; i++) {
      await logger.log(LogEvent(
        level: LogLevel.error,
        code: LogCode.diagnosticFailure,
        operation: 'sink_failure',
      ));
    }
    await expectLater(
      logger.flush(timeout: const Duration(milliseconds: 20)),
      throwsA(isA<TimeoutException>()),
    );
    expect(logger.droppedFor(sink), 8);
    expect(logger.totalDropped, 8);
    sink.gate.complete();
    await logger.flush();
  });
}
