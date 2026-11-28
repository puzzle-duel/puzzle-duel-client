import 'dart:io';

import 'package:flutter/services.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';

/// Server-authoritative recovery result. No writer entitlement is inferred
/// from a readable board or a successful device registration.
final class RecoveryAttempt {
  const RecoveryAttempt(this.succeeded, this.errorCode);
  final bool succeeded;
  final String? errorCode;
}

/// UAT-only same-device recovery. Private keys stay in the platform keystore.
/// Backend decides writer entitlement; this class never mutates local scores.
final class SameDeviceRecovery {
  const SameDeviceRecovery({this.isSupportedDevice});

  /// Test seam only. Production supports iOS and Android device signing.
  final bool Function()? isSupportedDevice;
  bool get _isSupported => isSupportedDevice?.call() ?? (Platform.isIOS || Platform.isAndroid);

  static const MethodChannel _signer = MethodChannel('pzd/device_signing');

  /// Must execute after a new verified session, before the original claim.
  /// Returns false when server candidate is disabled or device signing fails.
  Future<bool> register({
    required UatApi api,
    required String playerId,
    required String sessionId,
    required String origin,
  }) async =>
      (await registerDetailed(
        api: api,
        playerId: playerId,
        sessionId: sessionId,
        origin: origin,
      )).succeeded;

  /// Propagates the actual server/platform failure reason — never fabricates
  /// NOT_FOUND when registration was skipped or signed locally.
  Future<RecoveryAttempt> registerDetailed({
    required UatApi api,
    required String playerId,
    required String sessionId,
    required String origin,
  }) async {
    if (!_isSupported || playerId.isEmpty || sessionId.isEmpty) {
      return const RecoveryAttempt(false, 'RECOVERY_NOT_ELIGIBLE');
    }
    try {
      final proof = await _signer.invokeMapMethod<String, String>(
        'registerProof',
        {
          'playerId': playerId,
          'sessionId': sessionId,
          'origin': origin,
        },
      );
      if (proof == null) {
        return const RecoveryAttempt(false, 'RECOVERY_PROOF_INVALID');
      }
      final spki = proof['spkiBase64Url'];
      final signature = proof['signatureBase64Url'];
      if (spki == null || signature == null) {
        return const RecoveryAttempt(false, 'RECOVERY_PROOF_INVALID');
      }
      final response = await api.post('/v1/tournament/devices/register', {
        'spkiBase64Url': spki,
        'signatureBase64Url': signature,
      });
      if (response.status == 200 &&
          response.map['deviceCredentialId'] is String) {
        return const RecoveryAttempt(true, null);
      }
      return RecoveryAttempt(false, response.error);
    } on PlatformException {
      return const RecoveryAttempt(false, 'RECOVERY_PROOF_INVALID');
    } on MissingPluginException {
      return const RecoveryAttempt(false, 'RECOVERY_NOT_ELIGIBLE');
    }
  }

  /// Verified-account reclaim for legacy unanchored writers only.
  /// Server decides eligibility; never fabricates device proof.
  Future<RecoveryAttempt> reclaimUnanchored({
    required UatApi api,
    required String seriesId,
  }) async {
    if (seriesId.isEmpty) {
      return const RecoveryAttempt(false, 'RECOVERY_NOT_ELIGIBLE');
    }
    final response = await api.post(
      '/v1/tournament/series/$seriesId/reclaim-writer',
    );
    return RecoveryAttempt(
      response.status == 200 && response.map['writerGeneration'] is int,
      response.status == 200 ? null : response.error,
    );
  }

  /// A successful recovery changes ONLY the server-owned writer binding.
  /// Callers must reload the authoritative board before sending commands.
  /// Compatibility API for existing callers and tests.
  Future<bool> recover({
    required UatApi api,
    required String playerId,
    required String newSessionId,
    required String origin,
    required String seriesId,
  }) async => (await recoverDetailed(
    api: api,
    playerId: playerId,
    newSessionId: newSessionId,
    origin: origin,
    seriesId: seriesId,
  )).succeeded;

  Future<RecoveryAttempt> recoverDetailed({
    required UatApi api,
    required String playerId,
    required String newSessionId,
    required String origin,
    required String seriesId,
  }) async {
    if (!_isSupported ||
        playerId.isEmpty ||
        newSessionId.isEmpty ||
        seriesId.isEmpty) {
      return const RecoveryAttempt(false, 'RECOVERY_NOT_ELIGIBLE');
    }
    final issued = await api.post(
      '/v1/tournament/series/$seriesId/recovery-challenge',
    );
    if (issued.status != 200) {
      return RecoveryAttempt(false, issued.error);
    }
    final data = issued.map;
    final challengeId = data['challengeId'];
    final credentialId = data['deviceCredentialId'];
    final nonce = data['nonce'];
    final generation = data['expectedWriterGeneration'];
    final expiresAtMs = data['expiresAtMs'];
    if (challengeId is! String ||
        credentialId is! String ||
        nonce is! String ||
        generation is! int ||
        expiresAtMs is! int) {
      return const RecoveryAttempt(false, 'MALFORMED_BODY');
    }
    try {
      final signature = await _signer.invokeMethod<String>(
        'signRecovery',
        {
          'playerId': playerId,
          'origin': origin,
          'seriesId': seriesId,
          'newSessionId': newSessionId,
          'deviceCredentialId': credentialId,
          'challengeId': challengeId,
          'nonce': nonce,
          'expectedWriterGeneration': generation,
          'expiresAtMs': expiresAtMs,
        },
      );
      if (signature == null) {
        return const RecoveryAttempt(false, 'RECOVERY_PROOF_INVALID');
      }
      final response = await api.post(
        '/v1/tournament/series/$seriesId/recover-writer',
        {
          'proof': {
            'playerId': playerId,
            'seriesId': seriesId,
            'newSessionId': newSessionId,
            'deviceCredentialId': credentialId,
            'challengeId': challengeId,
            'nonce': nonce,
            'expectedWriterGeneration': generation,
            'expiresAtMs': expiresAtMs,
          },
          'signatureBase64Url': signature,
        },
      );
      return RecoveryAttempt(
        response.status == 200 && response.map['writerGeneration'] is int,
        response.status == 200 ? null : response.error,
      );
    } on PlatformException {
      return const RecoveryAttempt(false, 'RECOVERY_PROOF_INVALID');
    } on MissingPluginException {
      return const RecoveryAttempt(false, 'RECOVERY_NOT_ELIGIBLE');
    }
  }
}

