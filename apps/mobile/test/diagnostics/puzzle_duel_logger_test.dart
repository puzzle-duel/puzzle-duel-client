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

class _AsyncOrderedSink implements LogSink {
  _AsyncOrderedSink(this.seen);
  final List<int> seen;
  @override
  Future<void> write(LogEvent event) async {
    await Future<void>.delayed(Duration(milliseconds: 10 - event.durationMs!));
    seen.add(event.durationMs!);
  }
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

  test('writer rejection emits correlatable and strictly bounded error code', () {
    final event = LogEvent(
      level: LogLevel.warning,
      code: LogCode.writerBindingRejected,
      operation: 'tournament_session',
      requestId: '5c24f6868a73df6ed3c5e9513774bef3',
      httpStatus: 409,
      errorCode: 'WRITER_NOT_AUTHORIZED',
    );
    expect(event.toJson()['errorCode'], 'WRITER_NOT_AUTHORIZED');
    expect(event.toJson()['requestId'], '5c24f6868a73df6ed3c5e9513774bef3');
    expect(
      () => LogEvent(level: LogLevel.warning,
        code: LogCode.writerBindingRejected, operation: 'tournament_session',
        errorCode: 'Bearer private-secret'),
      throwsArgumentError,
    );
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

  test('byte cap evicts oldest events and remains bounded', () {
    final now = DateTime.utc(2026, 11, 21, 12);
    final sink = RingBufferLogSink(maxBytes: 300, clock: () => now);
    for (var i = 0; i < 20; i++) {
      sink.write(LogEvent(level: LogLevel.info,
        code: LogCode.httpCompleted, operation: 'http_request',
        timestamp: now, durationMs: i));
    }
    expect(sink.retainedBytes, lessThanOrEqualTo(300));
    expect(sink.snapshot().length, lessThan(20));
  });

  test('sink failure does not block other sinks', () async {
    final recording = _RecordingSink();
    final logger = PuzzleDuelLogger(sinks: [_FailingSink(), recording]);
    await logger.log(LogEvent(level: LogLevel.error,
      code: LogCode.authRefreshFailed, operation: 'auth_refresh'));
    await logger.flush();
    expect(recording.events, hasLength(1));
  });

  test('flush preserves FIFO ordering for asynchronous sink', () async {
    final seen = <int>[];
    final sink = _AsyncOrderedSink(seen);
    final logger = PuzzleDuelLogger(sinks: [sink]);
    for (var i = 0; i < 10; i++) {
      await logger.log(LogEvent(
        level: LogLevel.info,
        code: LogCode.httpCompleted,
        operation: 'http_request',
        durationMs: i,
      ));
    }
    await logger.flush();
    expect(seen, List<int>.generate(10, (i) => i));
  });

  test('minimum log level filters verbose in production', () async {
    final recording = _RecordingSink();
    final logger = PuzzleDuelLogger(sinks: [recording]);
    await logger.log(LogEvent(level: LogLevel.debug,
      code: LogCode.applicationStarted, operation: 'startup'));
    expect(recording.events, isEmpty);
  });
}
