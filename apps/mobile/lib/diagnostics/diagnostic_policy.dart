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

  /// A build targeting the staging API must always offer safe diagnostic
  /// reporting. Keeping this independent of PZD_DIAGNOSTIC_ENV prevents local
  /// debug/release builds from silently hiding the Log Gönder action.
  static DiagnosticEnvironment resolveEnvironment({
    required String stagingBaseUrl,
    required String diagnosticEnvironment,
  }) {
    if (stagingBaseUrl.trim().isNotEmpty ||
        diagnosticEnvironment == 'staging') {
      return DiagnosticEnvironment.staging;
    }
    return DiagnosticEnvironment.production;
  }

  static DiagnosticEnvironment fromBuild() {
    return resolveEnvironment(
      stagingBaseUrl: const String.fromEnvironment('PZD_STAGING_BASE_URL'),
      diagnosticEnvironment: const String.fromEnvironment(
        'PZD_DIAGNOSTIC_ENV',
        defaultValue: 'production',
      ),
    );
  }
}
