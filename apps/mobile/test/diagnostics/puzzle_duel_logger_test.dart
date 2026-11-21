import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/diagnostics/puzzle_duel_logger.dart';

class _FailingSink implements LogSink {
  @override
  Future<void> write(LogEvent event) async => throw StateError('sink down');
}

class _RecordingSink implements LogSink {
  final events = <LogEvent>[];
  @override
  void write(LogEvent event) => events.add(event);
}

void main() {
  test('UTC and strict metadata allowlist', () {
    final event = LogEvent(
      level: LogLevel.warning,
      code: LogCode.httpFailed,
      operation: 'tournament_load',
      timestamp: DateTime.parse('2026-11-21T11:00:00+03:00'),
      httpStatus: 401,
    );
    expect(event.toJson()['timestamp'], '2026-11-21T08:00:00.000Z');
    expect(event.toJson().containsKey('headers'), false);
    expect(() => LogEvent(level: LogLevel.info, code: LogCode.httpFailed,
      operation: 'Bearer secret'), throwsArgumentError);
    expect(() => LogEvent(level: LogLevel.info, code: LogCode.httpFailed,
      operation: 'request', traceId: 'token.with.dots'), throwsArgumentError);
  });

  test('ring buffer caps and expires entries', () {
    var now = DateTime.utc(2026, 11, 21, 12);
    final sink = RingBufferLogSink(maxEvents: 2, clock: () => now);
    LogEvent event() => LogEvent(
      level: LogLevel.info, code: LogCode.applicationStarted,
      operation: 'startup', timestamp: now);
    sink.write(event());
    sink.write(event());
    sink.write(event());
    expect(sink.snapshot(), hasLength(2));
    now = now.add(const Duration(minutes: 61));
    expect(sink.snapshot(), isEmpty);
  });

  test('sink failure does not block other sinks', () async {
    final recording = _RecordingSink();
    final logger = PuzzleDuelLogger(sinks: [_FailingSink(), recording]);
    await logger.log(LogEvent(level: LogLevel.error,
      code: LogCode.authRefreshFailed, operation: 'auth_refresh'));
    expect(recording.events, hasLength(1));
  });

  test('minimum log level filters verbose in production', () async {
    final recording = _RecordingSink();
    final logger = PuzzleDuelLogger(sinks: [recording]);
    await logger.log(LogEvent(level: LogLevel.debug,
      code: LogCode.applicationStarted, operation: 'startup'));
    expect(recording.events, isEmpty);
  });
}
