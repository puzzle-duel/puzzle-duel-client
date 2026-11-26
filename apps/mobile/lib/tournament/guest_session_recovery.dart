import 'package:puzzle_duel_mobile/tournament/guest_auth.dart';

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

  /// Codes that must never hard-lock the app behind a config error screen.
  static bool isRecoverableStartup(String code) {
    if (code == 'GUEST_RECOVERY_REQUIRED' ||
        code == 'REFRESH_EXPIRED' ||
        code == 'REFRESH_REPLAY' ||
        code == 'INVALID_REFRESH') {
      return true;
    }
    return code.startsWith('PROVIDER_LINK_RECOVERY_');
  }
}
