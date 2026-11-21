import 'diagnostic_policy.dart';
import 'puzzle_duel_logger.dart';

/// Process-local diagnostic lifecycle. Never persists secrets or payloads.
final class DiagnosticRuntime {
  DiagnosticRuntime._();

  static final DiagnosticPolicy policy =
      DiagnosticPolicy.forEnvironment(DiagnosticPolicy.fromBuild());
  static final RingBufferLogSink? buffer = policy.captureMemory
      ? RingBufferLogSink()
      : null;
  static final PuzzleDuelLogger logger = PuzzleDuelLogger(
    minimumLevel: policy.minimumLevel,
    sinks: [
      const ConsoleLogSink(),
      if (buffer case final value?) value,
    ],
  );

  static Future<List<LogEvent>> snapshot() async {
    if (!policy.captureMemory || buffer == null) return const [];
    await logger.flush();
    return buffer!.snapshot();
  }
}
