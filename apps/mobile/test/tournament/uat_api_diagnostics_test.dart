import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/diagnostics/puzzle_duel_logger.dart';
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
  test('logout and local-only error codes cannot poison a report', () {
    final logout = LogEvent(
      level: LogLevel.info,
      code: LogCode.sessionRestored,
      operation: 'account_scoped_state_invalidated',
      errorCode: 'LOGOUT',
    );
    final failure = LogEvent(
      level: LogLevel.warning,
      code: LogCode.httpFailed,
      operation: 'tournament_http',
      errorCode: 'UNAUTHENTICATED',
      requestId: '00112233445566778899aabbccddeeff',
      httpStatus: 401,
    );
    final report = UatApi.diagnosticReportEvents([logout, failure]);
    expect(report, hasLength(2));
    expect(report.first.containsKey('errorCode'), isFalse);
    expect(report.first['operation'], logout.operation);
    expect(logout.toJson()['errorCode'], 'LOGOUT');
    expect(report.last, failure.toJson());
  });

  test('report retains valid correlation and removes incompatible metadata', () {
    final report = UatApi.diagnosticReportEvents([
      LogEvent(
        level: LogLevel.info,
        code: LogCode.httpStarted,
        operation: 'http_start',
      ),
      LogEvent(
        level: LogLevel.warning,
        code: LogCode.diagnosticFailure,
        operation: 'diagnostic_report_failed',
        requestId: 'local-id',
        traceId: '00112233445566778899aabbccddeeff',
        errorCode: 'AUTH_SQLSTATE_23505',
      ),
    ]);
    expect(report, hasLength(1));
    expect(report.single.containsKey('requestId'), isFalse);
    expect(report.single['traceId'], '00112233445566778899aabbccddeeff');
    expect(report.single['errorCode'], 'AUTH_SQLSTATE_23505');
  });

  test('report includes at most 64 newest eligible events', () {
    final events = List.generate(
      70,
      (i) => LogEvent(
        level: LogLevel.info,
        code: LogCode.httpCompleted,
        operation: 'request_$i',
      ),
    );
    final report = UatApi.diagnosticReportEvents(events);
    expect(report, hasLength(64));
    expect(report.first['operation'], 'request_6');
    expect(report.last['operation'], 'request_69');
  });
}
