import 'package:flutter/foundation.dart';

/// Lightweight first-interaction timing marks.
///
/// Enable with `--dart-define=PZD_PERF=true` (profile/release) or debug asserts.
/// Hot paths stay quiet unless enabled.
abstract final class InteractionPerf {
  static const enabled = bool.fromEnvironment('PZD_PERF');

  static final Map<String, int> _marksUs = {};
  static final Stopwatch _sinceStart = Stopwatch()..start();

  static void mark(String name) {
    if (!_active) return;
    final us = _sinceStart.elapsedMicroseconds;
    _marksUs[name] = us;
    debugPrint('PZD_PERF $name +${(us / 1000).toStringAsFixed(1)}ms');
  }

  static void span(String name, void Function() body) {
    if (!_active) {
      body();
      return;
    }
    final sw = Stopwatch()..start();
    body();
    debugPrint('PZD_PERF span $name ${sw.elapsedMicroseconds}us');
  }

  static T spanSync<T>(String name, T Function() body) {
    if (!_active) return body();
    final sw = Stopwatch()..start();
    final value = body();
    debugPrint('PZD_PERF span $name ${sw.elapsedMicroseconds}us');
    return value;
  }

  static Map<String, int> snapshotUs() => Map.unmodifiable(_marksUs);

  static bool get _active => enabled || (kDebugMode && _debugForce);
  static bool _debugForce = false;

  @visibleForTesting
  static void debugEnable(bool value) => _debugForce = value;

  @visibleForTesting
  static void debugReset() {
    _marksUs.clear();
    _sinceStart
      ..reset()
      ..start();
  }
}
