import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;

/// SDK-independent, allowlisted diagnostic events. Never accept arbitrary
/// request bodies, headers, user identifiers or exception.toString() here.
enum LogLevel { verbose, debug, info, warning, error, fatal }
enum LogCode {
  applicationStarted,
  screenOpened,
  httpStarted,
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
    'requestId': ?requestId,
    'traceId': ?traceId,
    'httpMethod': ?httpVerb?.name.toUpperCase(),
    'httpStatus': ?httpStatus,
    'durationMs': ?durationMs,
  };
}

abstract interface class LogSink {
  FutureOr<void> write(LogEvent event);
}

class ConsoleLogSink implements LogSink {
  const ConsoleLogSink();
  @override
  void write(LogEvent event) => developer.log(jsonEncode(event.toJson()), name: 'PuzzleDuelLogger');
}

/// Bounded by both event count and age. No disk persistence.
class RingBufferLogSink implements LogSink {
  RingBufferLogSink({
    this.maxEvents = 10000,
    this.maxBytes = 2 * 1024 * 1024,
    this.maxAge = const Duration(hours: 1),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    if (maxEvents < 1 || maxBytes < 1 || maxAge <= Duration.zero) {
      throw ArgumentError('Invalid ring buffer limits');
    }
  }

  final int maxEvents;
  final int maxBytes;
  int _bytes = 0;
  final Queue<int> _sizes = Queue<int>();
  final Duration maxAge;
  final DateTime Function() _clock;
  final Queue<LogEvent> _events = Queue<LogEvent>();

  @override
  void write(LogEvent event) {
    _evict();
    if (_clock().toUtc().difference(event.timestamp) > maxAge) return;
    final size = utf8.encode(jsonEncode(event.toJson())).length;
    if (size > maxBytes) return;
    _events.addLast(event);
    _sizes.addLast(size);
    _bytes += size;
    while (_events.length > maxEvents || _bytes > maxBytes) {
      _removeOldest();
    }
  }

  List<LogEvent> snapshot() {
    _evict();
    return List.unmodifiable(_events);
  }

  int get retainedBytes => _bytes;

  void clear() {
    _events.clear();
    _sizes.clear();
    _bytes = 0;
  }

  void _removeOldest() {
    _events.removeFirst();
    _bytes -= _sizes.removeFirst();
  }

  void _evict() {
    final cutoff = _clock().toUtc().subtract(maxAge);
    // Preserve FIFO alignment between events and encoded byte sizes.
    // Expired entries may occur out of order with injected timestamps.
    final retained = <LogEvent>[];
    final sizes = <int>[];
    while (_events.isNotEmpty) {
      final event = _events.removeFirst();
      final size = _sizes.removeFirst();
      if (!event.timestamp.isBefore(cutoff)) {
        retained.add(event);
        sizes.add(size);
      } else {
        _bytes -= size;
      }
    }
    _events.addAll(retained);
    _sizes.addAll(sizes);
  }
}

class PuzzleDuelLogger {
  PuzzleDuelLogger({
    required List<LogSink> sinks,
    this.minimumLevel = LogLevel.info,
    this.maxPendingPerSink = 1024,
  }) : _sinks = List.unmodifiable(sinks) {
    if (maxPendingPerSink < 1) throw ArgumentError('Invalid pending sink limit');
  }

  final List<LogSink> _sinks;
  final LogLevel minimumLevel;
  final int maxPendingPerSink;
  final Map<LogSink, Future<void>> _tails = {};
  final Map<LogSink, int> _pending = {};
  final Map<LogSink, int> _dropped = {};

  /// Number of events rejected by each sink's bounded queue.
  int droppedFor(LogSink sink) => _dropped[sink] ?? 0;

  int get totalDropped => _dropped.values.fold(0, (sum, count) => sum + count);


  /// Queues events in FIFO order independently per sink. A failing or slow
  /// sink cannot delay another sink or the caller.
  Future<void> log(LogEvent event) {
    if (event.level.index < minimumLevel.index) return Future<void>.value();
    for (final sink in _sinks) {
      final count = _pending[sink] ?? 0;
      if (count >= maxPendingPerSink) {
        _dropped[sink] = (_dropped[sink] ?? 0) + 1;
        continue;
      }
      _pending[sink] = count + 1;
      final previous = _tails[sink] ?? Future<void>.value();
      final next = previous.then((_) async {
        try {
          await sink.write(event);
        } catch (_) {
          // Telemetry is best-effort and must not affect application logic.
        } finally {
          _pending[sink] = (_pending[sink] ?? 1) - 1;
        }
      });
      _tails[sink] = next;
    }
    return Future<void>.value();
  }

  /// Await pending writes before taking a diagnostic snapshot.
  /// A permanently stalled sink will also stall flush; callers must set
  /// their own timeout when using this method.
  Future<void> flush({Duration timeout = const Duration(seconds: 2)}) async {
    await Future.wait(_tails.values.toList()).timeout(timeout);
  }
}
