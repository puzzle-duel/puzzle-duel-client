import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';

void main() {
  test('recovery and writer rejection codes are safe to diagnose', () {
    expect(UatApi.diagnosticErrorCode('WRITER_STILL_ACTIVE'),
        'WRITER_STILL_ACTIVE');
    expect(UatApi.diagnosticErrorCode('RECOVERY_NOT_ELIGIBLE'),
        'RECOVERY_NOT_ELIGIBLE');
    expect(UatApi.diagnosticErrorCode('IDLE_EXPIRED'), 'IDLE_EXPIRED');
    expect(UatApi.diagnosticErrorCode('WRITER_NOT_AUTHORIZED'),
        'WRITER_NOT_AUTHORIZED');
  });

  test('arbitrary HTTP response strings are never exposed', () {
    expect(UatApi.diagnosticErrorCode(null), isNull);
    expect(UatApi.diagnosticErrorCode('Bearer secret'), isNull);
    expect(UatApi.diagnosticErrorCode('sessionSecret=abc'), isNull);
    expect(UatApi.diagnosticErrorCode('UNKNOWN_SERVER_RESPONSE'), isNull);
  });
}
