import 'diagnostic_policy.dart';
import 'firebase_crashlytics_adapter.dart';
import 'puzzle_duel_logger.dart';

/// Process-local diagnostic lifecycle. Never persists secrets or payloads.
final class DiagnosticRuntime {
  DiagnosticRuntime._();

  static final DiagnosticPolicy policy =
      DiagnosticPolicy.forEnvironment(DiagnosticPolicy.fromBuild());
  static final RingBufferLogSink? buffer = policy.captureMemory
      ? RingBufferLogSink(maxEvents: 100, maxBytes: 64 * 1024, maxAge: const Duration(minutes: 30))
      : null;
  static final PuzzleDuelLogger logger = PuzzleDuelLogger(
    minimumLevel: LogLevel.info,
    sinks: [
      const ConsoleLogSink(),
      CrashlyticsLogSink(),
      ?buffer,
    ],
  );

  static Future<List<LogEvent>> snapshot() async {
    if (!policy.captureMemory || buffer == null) return const [];
    await logger.flush();
    return buffer!.snapshot();
  }
}
