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

  bool get canAttemptProviderRecover =>
      expectedPlayerId != null && expectedPlayerId!.isNotEmpty;

  bool get isTransientNetwork => isTransientNetworkCode(code);

  /// Codes that must never hard-lock the app behind a config error screen.
  static bool isRecoverableStartup(String code) =>
      isHardRecoveryCode(code) ||
      isTransientNetworkCode(code) ||
      code.startsWith('PROVIDER_LINK_RECOVERY_');

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
    this.serverReportId,
    this.serverStatus,
    this.requestId,
    this.failureCode,
  });

  final bool breadcrumbLogged;
  final bool crashlyticsRecorded;
  final String? serverReportId;
  final int? serverStatus;
  final String? requestId;
  final String? failureCode;

  bool get serverDelivered =>
      serverReportId != null && serverReportId!.isNotEmpty;

  /// Honest operator-facing status; never claims server delivery from crumbs alone.
  String get userMessage {
    if (failureCode != null && !serverDelivered && !crashlyticsRecorded) {
      return 'Log gönderilemedi ($failureCode).';
    }
    if (serverDelivered) {
      return 'Sunucu raporu alındı: $serverReportId';
    }
    if (crashlyticsRecorded) {
      final rid = requestId;
      return rid == null
          ? 'Crashlytics kaydı alındı; sunucu raporu yok (oturum gerekli).'
          : 'Crashlytics kaydı alındı; sunucu raporu yok. requestId=$rid';
    }
    if (breadcrumbLogged) {
      return 'Yalnızca yerel breadcrumb yazıldı; gönderim doğrulanmadı.';
    }
    return 'Log gönderilemedi.';
  }
}

Future<StagingManualDiagnosticResult> sendStagingManualDiagnostics({
  required String operation,
  String? requestId,
  String? errorCode,
  CrashReporter? crashReporter,
  UatApi? api,
}) async {
  var breadcrumbLogged = false;
  var crashlyticsRecorded = false;
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
      await crashReporter.recordNonFatal(
        StateError('STAGING_MANUAL_DIAGNOSTIC'),
        StackTrace.current,
      );
      crashlyticsRecorded = true;
    } catch (_) {
      failureCode ??= 'CRASHLYTICS_RECORD_FAILED';
    }
  }

  String? serverReportId;
  int? serverStatus;
  final bearer = api?.bearer.trim() ?? '';
  if (api != null && bearer.isNotEmpty) {
    try {
      final result = await api.sendDiagnosticReport();
      serverStatus = result.status;
      final reportId = result.map['reportId'];
      if (result.status == 201 && reportId is String && reportId.isNotEmpty) {
        serverReportId = reportId;
        failureCode = null;
      } else {
        failureCode ??= 'SERVER_REPORT_${result.status}';
      }
    } catch (_) {
      failureCode ??= 'SERVER_REPORT_FAILED';
    }
  }

  return StagingManualDiagnosticResult(
    breadcrumbLogged: breadcrumbLogged,
    crashlyticsRecorded: crashlyticsRecorded,
    serverReportId: serverReportId,
    serverStatus: serverStatus,
    requestId: requestId,
    failureCode: failureCode,
  );
}
