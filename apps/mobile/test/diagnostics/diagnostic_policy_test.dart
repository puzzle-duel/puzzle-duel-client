import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/diagnostics/diagnostic_policy.dart';
import 'package:puzzle_duel_mobile/diagnostics/puzzle_duel_logger.dart';

void main() {
  test('staging enables bounded diagnostics', () {
    final policy = DiagnosticPolicy.forEnvironment(DiagnosticEnvironment.staging);
    expect(policy.minimumLevel, LogLevel.debug);
    expect(policy.captureMemory, isTrue);
    expect(policy.manualReportEnabled, isTrue);
  });

  test('production is privacy-first by default', () {
    final policy = DiagnosticPolicy.forEnvironment(DiagnosticEnvironment.production);
    expect(policy.minimumLevel, LogLevel.warning);
    expect(policy.captureMemory, isFalse);
    expect(policy.manualReportEnabled, isFalse);
  });
}
