import 'dart:async';
import 'dart:collection';
import 'dart:convert';

/// SDK-independent, allowlisted diagnostic events. Never accept arbitrary
/// request bodies, headers, user identifiers or exception.toString() here.
enum LogLevel { verbose, debug, info, warning, error, fatal }
enum LogCode {
  applicationStarted,
  httpCompleted,
  httpFailed,
  authExpired,
  authRefreshSucceeded,
  authRefreshFailed,
  sessionRestored,
  sessionRestoreFailed,
  writerBindingRejected,
  diagnosticFailure,
}

enum HttpVerb { get, post, put, patch, delete }

class LogEvent {
  LogEvent({
    required this.level,
    required this.code,
    required this.operation,
    DateTime? timestamp,
    this.requestId,
    this.traceId,
    this.httpVerb,
    this.httpStatus,
    this.durationMs,
  }) : timestamp = (timestamp ?? DateTime.now()).toUtc() {
    if (!_safeIdentifier.hasMatch(operation)) {
      throw ArgumentError.value(operation, 'operation', 'Must be an allowlisted-style identifier');
    }
    for (final id in [requestId, traceId]) {
      if (id != null && !_safeIdentifier.hasMatch(id)) {
        throw ArgumentError('Unsafe correlation identifier');
      }
    }
    if (httpStatus != null && (httpStatus! < 100 || httpStatus! > 599)) {
      throw ArgumentError('Invalid HTTP status');
    }
    if (durationMs != null && durationMs! < 0) {
      throw ArgumentError('Negative duration');
    }
  }

  static final _safeIdentifier = RegExp(r'^[a-zA-Z0-9_-]{1,64}$');
  final LogLevel level;
  final LogCode code;
  final String operation;
  final DateTime timestamp;
  final String? requestId;
  final String? traceId;
  final HttpVerb? httpVerb;
  final int? httpStatus;
  final int? durationMs;

  Map<String, Object> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'level': level.name,
    'code': code.name,
    'operation': operation,
    if (requestId != null) 'requestId': requestId!,
    if (traceId != null) 'traceId': traceId!,
    if (httpVerb != null) 'httpMethod': httpVerb!.name.toUpperCase(),
    if (httpStatus != null) 'httpStatus': httpStatus!,
    if (durationMs != null) 'durationMs': durationMs!,
  };
}

abstract interface class LogSink {
  FutureOr<void> write(LogEvent event);
}

class ConsoleLogSink implements LogSink {
  const ConsoleLogSink();
  @override
  void write(LogEvent event) => print(jsonEncode(event.toJson()));
}

/// Bounded by both event count and age. No disk persistence.
class RingBufferLogSink implements LogSink {
  RingBufferLogSink({
    this.maxEvents = 300,
    this.maxAge = const Duration(hours: 1),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    if (maxEvents < 1 || maxAge <= Duration.zero) {
      throw ArgumentError('Invalid ring buffer limits');
    }
  }

  final int maxEvents;
  final Duration maxAge;
  final DateTime Function() _clock;
  final Queue<LogEvent> _events = Queue<LogEvent>();

  @override
  void write(LogEvent event) {
    _evict();
    if (_clock().toUtc().difference(event.timestamp) > maxAge) return;
    _events.addLast(event);
    while (_events.length > maxEvents) {
      _events.removeFirst();
    }
  }

  List<LogEvent> snapshot() {
    _evict();
    return List.unmodifiable(_events);
  }

  void clear() => _events.clear();

  void _evict() {
    final cutoff = _clock().toUtc().subtract(maxAge);
    _events.removeWhere((event) => event.timestamp.isBefore(cutoff));
  }
}

class PuzzleDuelLogger {
  PuzzleDuelLogger({
    required List<LogSink> sinks,
    this.minimumLevel = LogLevel.info,
  }) : _sinks = List.unmodifiable(sinks);

  final List<LogSink> _sinks;
  final LogLevel minimumLevel;

  /// Logging is best-effort: failing sinks must never affect app behavior.
  Future<void> log(LogEvent event) async {
    if (event.level.index < minimumLevel.index) return;
    for (final sink in _sinks) {
      try {
        await sink.write(event);
      } catch (_) {
        // Intentionally suppress telemetry errors; never recursively log.
      }
    }
  }
}
