import 'dart:async';

import 'package:puzzle_duel_mobile/diagnostics/crash_reporter.dart';
import 'package:puzzle_duel_mobile/diagnostics/diagnostic_runtime.dart';
import 'package:puzzle_duel_mobile/diagnostics/puzzle_duel_logger.dart';
import 'package:puzzle_duel_mobile/tournament/guest_auth.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';

/// Durable non-secret identity binding for recovery UX.
/// Never stores tokens, nonces, emails, or provider subjects.
final class GuestIdentityBinding {
  const GuestIdentityBinding({
    required this.playerId,
    required this.accountType,
    this.familyId,
  });

  final String playerId;
  final AccountType accountType;
  final String? familyId;

  String encode() {
    final type = accountType == AccountType.verified ? 'verified' : 'guest';
    final fid = familyId ?? '';
    return '$playerId|$fid|$type';
  }

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static GuestIdentityBinding? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split('|');
    if (parts.length != 3) return null;
    final playerId = parts[0];
    final familyId = parts[1];
    final typeRaw = parts[2];
    if (!_uuid.hasMatch(playerId)) return null;
    if (familyId.isNotEmpty && !_uuid.hasMatch(familyId)) return null;
    final AccountType accountType;
    if (typeRaw == 'guest') {
      accountType = AccountType.guest;
    } else if (typeRaw == 'verified') {
      accountType = AccountType.verified;
    } else {
      return null;
    }
    return GuestIdentityBinding(
      playerId: playerId,
      familyId: familyId.isEmpty ? null : familyId,
      accountType: accountType,
    );
  }
}

/// Startup / session recovery gate. Practice stays open; ranked stays closed.
final class GuestSessionRecovery {
  const GuestSessionRecovery({
    required this.code,
    this.lastRequestId,
    this.binding,
    this.pendingLink,
  });

  final String code;
  final String? lastRequestId;
  final GuestIdentityBinding? binding;
  final PendingLinkRecovery? pendingLink;

  String? get expectedPlayerId =>
      pendingLink?.playerId ?? binding?.playerId;

  /// Provider Google/Apple recovery: pending link or previously verified account.
  /// Pure guest bindings alone must not imply a provider can restore the family.
  bool get canAttemptProviderRecover {
    if (pendingLink != null && expectedPlayerId != null) return true;
    return binding?.accountType == AccountType.verified &&
        binding!.playerId.isNotEmpty;
  }

  /// Explicit "start as new guest" is only for hard recovery of pure guests.
  /// Never for transient network, pending link, or verified recovery paths.
  bool get allowsExplicitNewGuest =>
      !isTransientNetwork &&
      isHardRecoveryCode(code) &&
      pendingLink == null &&
      binding?.accountType != AccountType.verified;

  bool get isTransientNetwork => isTransientNetworkCode(code);

  /// Codes that must never hard-lock the app behind a config error screen.
  static bool isRecoverableStartup(String code) =>
      isHardRecoveryCode(code) ||
      isTransientNetworkCode(code) ||
      code.startsWith('PROVIDER_LINK_RECOVERY_') ||
      code == 'SECURE_STORE_RECOVERY_FAILED';

  static bool isTransientNetworkCode(String code) =>
      code == 'REFRESH_UNAVAILABLE' || code == 'AUTH_NETWORK_UNAVAILABLE';

  static bool isHardRecoveryCode(String code) {
    if (code == 'GUEST_RECOVERY_REQUIRED' ||
        code == 'REFRESH_EXPIRED' ||
        code == 'REFRESH_REPLAY' ||
        code == 'INVALID_REFRESH') {
      return true;
    }
    return code.startsWith('PROVIDER_LINK_RECOVERY_');
  }
}

/// Separates local Crashlytics recording from authenticated server delivery.
final class StagingManualDiagnosticResult {
  const StagingManualDiagnosticResult({
    required this.breadcrumbLogged,
    required this.crashlyticsRecorded,
    this.crashlyticsOutcome,
    this.serverReportId,
    this.serverStatus,
    this.requestId,
    this.failureCode,
  });

  final bool breadcrumbLogged;
  final bool crashlyticsRecorded;
  final CrashRecordOutcome? crashlyticsOutcome;
  final String? serverReportId;
  final int? serverStatus;
  final String? requestId;
  final String? failureCode;

  bool get serverDelivered =>
      serverReportId != null && serverReportId!.isNotEmpty;

  /// Honest operator-facing status; never claims server delivery from crumbs alone.
  String get userMessage {
    if (serverDelivered) {
      return 'Sunucu raporu alındı: $serverReportId';
    }
    final parts = <String>[];
    if (crashlyticsRecorded) {
      parts.add('Crashlytics SDK kaydı kabul edildi');
    } else if (crashlyticsOutcome == CrashRecordOutcome.skippedNotConfigured) {
      parts.add('Crashlytics yapılandırılmadı');
    } else if (crashlyticsOutcome == CrashRecordOutcome.skippedDisabled) {
      parts.add('Crashlytics devre dışı');
    } else if (crashlyticsOutcome == CrashRecordOutcome.failed) {
      parts.add('Crashlytics kaydı başarısız');
    }
    if (failureCode == 'AUTH_BEARER_MISSING') {
      parts.add('sunucu raporu yok (hesap oturumu gerekli)');
    } else if (failureCode != null) {
      parts.add('sunucu raporu yok ($failureCode)');
    } else if (!breadcrumbLogged) {
      parts.add('gönderim doğrulanmadı');
    } else if (parts.isEmpty) {
      parts.add('yalnızca yerel breadcrumb yazıldı');
    }
    return parts.join('; ');
  }
}

Future<StagingManualDiagnosticResult> sendStagingManualDiagnostics({
  required String operation,
  String? requestId,
  String? errorCode,
  CrashReporter? crashReporter,
  UatApi? api,
}) async {
  unawaited(DiagnosticRuntime.logger.log(LogEvent(
    level: LogLevel.info,
    code: LogCode.diagnosticFailure,
    operation: 'diagnostic_report_requested',
    requestId: requestId,
    errorCode: errorCode,
  )));

  var breadcrumbLogged = false;
  var crashlyticsRecorded = false;
  CrashRecordOutcome? crashlyticsOutcome;
  String? failureCode;
  try {
    await DiagnosticRuntime.logger.log(LogEvent(
      level: LogLevel.warning,
      code: LogCode.diagnosticFailure,
      operation: operation,
      requestId: requestId,
      errorCode: errorCode,
    ));
    breadcrumbLogged = true;
  } catch (_) {
    failureCode = 'BREADCRUMB_FAILED';
  }

  if (crashReporter != null) {
    try {
      crashlyticsOutcome = await crashReporter.recordNonFatal(
        StateError('STAGING_MANUAL_DIAGNOSTIC'),
        StackTrace.current,
      );
      crashlyticsRecorded = crashlyticsOutcome == CrashRecordOutcome.recorded;
      if (crashlyticsRecorded) {
        unawaited(DiagnosticRuntime.logger.log(LogEvent(
          level: LogLevel.info,
          code: LogCode.diagnosticFailure,
          operation: 'crashlytics_record_accepted',
          requestId: requestId,
        )));
      } else {
        unawaited(DiagnosticRuntime.logger.log(LogEvent(
          level: LogLevel.info,
          code: LogCode.diagnosticFailure,
          operation: 'crashlytics_record_skipped',
          requestId: requestId,
          errorCode: crashlyticsOutcome == CrashRecordOutcome.failed
              ? 'CRASHLYTICS_RECORD_FAILED'
              : 'CRASHLYTICS_NOT_CONFIGURED',
        )));
      }
    } catch (_) {
      crashlyticsOutcome = CrashRecordOutcome.failed;
      failureCode ??= 'CRASHLYTICS_RECORD_FAILED';
    }
  }

  String? serverReportId;
  int? serverStatus;
  final bearer = api?.bearer.trim() ?? '';
  if (api == null || bearer.isEmpty) {
    failureCode ??= 'AUTH_BEARER_MISSING';
    unawaited(DiagnosticRuntime.logger.log(LogEvent(
      level: LogLevel.warning,
      code: LogCode.diagnosticFailure,
      operation: 'diagnostic_report_auth_unavailable',
      requestId: requestId,
      errorCode: 'AUTH_BEARER_MISSING',
    )));
  } else {
    // Account bearer is sufficient; tournament gameplay session is not required.
    try {
      final result = await api.sendDiagnosticReport();
      serverStatus = result.status;
      final reportId = result.map['reportId'];
      if (result.status == 201 && reportId is String && reportId.isNotEmpty) {
        serverReportId = reportId;
        failureCode = null;
        unawaited(DiagnosticRuntime.logger.log(LogEvent(
          level: LogLevel.info,
          code: LogCode.httpCompleted,
          operation: 'diagnostic_report_completed',
          requestId: requestId,
          httpStatus: 201,
        )));
      } else {
        failureCode ??= result.status == 401 || result.status == 403
            ? 'SERVER_REPORT_AUTH_${result.status}'
            : 'SERVER_REPORT_${result.status}';
        unawaited(DiagnosticRuntime.logger.log(LogEvent(
          level: LogLevel.warning,
          code: LogCode.httpFailed,
          operation: 'diagnostic_report_failed',
          requestId: requestId,
          httpStatus: result.status == 0 ? null : result.status,
          errorCode: failureCode,
        )));
      }
    } catch (_) {
      failureCode ??= 'SERVER_REPORT_FAILED';
      unawaited(DiagnosticRuntime.logger.log(LogEvent(
        level: LogLevel.warning,
        code: LogCode.httpFailed,
        operation: 'diagnostic_report_failed',
        requestId: requestId,
        errorCode: 'SERVER_REPORT_FAILED',
      )));
    }
  }

  return StagingManualDiagnosticResult(
    breadcrumbLogged: breadcrumbLogged,
    crashlyticsRecorded: crashlyticsRecorded,
    crashlyticsOutcome: crashlyticsOutcome,
    serverReportId: serverReportId,
    serverStatus: serverStatus,
    requestId: requestId,
    failureCode: failureCode,
  );
}
