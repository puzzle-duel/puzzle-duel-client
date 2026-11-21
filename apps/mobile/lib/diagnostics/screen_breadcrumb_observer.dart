import 'dart:async';
import 'package:flutter/widgets.dart';
import 'diagnostic_runtime.dart';
import 'puzzle_duel_logger.dart';

/// Navigation-only instrumentation; does not change transitions or widgets.
final class ScreenBreadcrumbObserver extends NavigatorObserver {
  void _opened(Route<dynamic>? route) {
    final raw = route?.settings.name;
    final name = raw == null || raw.isEmpty ? 'root' : raw;
    final safe = name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    unawaited(DiagnosticRuntime.logger.log(LogEvent(
      level: LogLevel.info, code: LogCode.screenOpened,
      operation: safe.length > 64 ? safe.substring(0, 64) : safe,
    )));
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _opened(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _opened(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _opened(newRoute);
  }
}
