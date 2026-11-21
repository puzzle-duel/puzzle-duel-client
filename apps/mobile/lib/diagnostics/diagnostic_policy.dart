import 'puzzle_duel_logger.dart';

/// Build-time diagnostics policy. No runtime override can enable sensitive
/// payload logging; LogEvent has a fixed field schema.
enum DiagnosticEnvironment { staging, production }

class DiagnosticPolicy {
  const DiagnosticPolicy._({
    required this.minimumLevel,
    required this.captureMemory,
    required this.manualReportEnabled,
  });

  final LogLevel minimumLevel;
  final bool captureMemory;
  final bool manualReportEnabled;

  static DiagnosticPolicy forEnvironment(DiagnosticEnvironment environment) {
    switch (environment) {
      case DiagnosticEnvironment.staging:
        return const DiagnosticPolicy._(
          minimumLevel: LogLevel.debug,
          captureMemory: true,
          manualReportEnabled: true,
        );
      case DiagnosticEnvironment.production:
        return const DiagnosticPolicy._(
          minimumLevel: LogLevel.warning,
          captureMemory: false,
          manualReportEnabled: false,
        );
    }
  }

  static DiagnosticEnvironment fromBuild() {
    const value = String.fromEnvironment(
      'PZD_DIAGNOSTIC_ENV',
      defaultValue: 'production',
    );
    return value == 'staging'
        ? DiagnosticEnvironment.staging
        : DiagnosticEnvironment.production;
  }
}
