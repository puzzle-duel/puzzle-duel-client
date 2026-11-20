import 'dart:io';

import 'package:flutter/services.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';

/// UAT-only same-device recovery. Keys never leave iOS Secure Enclave.
/// Backend decides writer entitlement; this class never mutates local scores.
final class SameDeviceRecovery {
  const SameDeviceRecovery();

  static const MethodChannel _signer = MethodChannel('pzd/device_signing');

  /// Must execute after a new verified session, before the original claim.
  /// Returns false when server candidate is disabled or device signing fails.
  Future<bool> register({
    required UatApi api,
    required String playerId,
    required String sessionId,
    required String origin,
  }) async {
    if (!Platform.isIOS || playerId.isEmpty || sessionId.isEmpty) return false;
    try {
      final proof = await _signer.invokeMapMethod<String, String>(
        'registerProof',
        {
          'playerId': playerId,
          'sessionId': sessionId,
          'origin': origin,
        },
      );
      if (proof == null) return false;
      final spki = proof['spkiBase64Url'];
      final signature = proof['signatureBase64Url'];
      if (spki == null || signature == null) return false;
      final response = await api.post('/v1/tournament/devices/register', {
        'spkiBase64Url': spki,
        'signatureBase64Url': signature,
      });
      return response.status == 200 &&
          response.map['deviceCredentialId'] is String;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// A successful recovery changes ONLY the server-owned writer binding.
  /// Callers must reload the authoritative board before sending commands.
  Future<bool> recover({
    required UatApi api,
    required String playerId,
    required String newSessionId,
    required String origin,
    required String seriesId,
  }) async {
    if (!Platform.isIOS ||
        playerId.isEmpty ||
        newSessionId.isEmpty ||
        seriesId.isEmpty) {
      return false;
    }
    final issued = await api.post(
      '/v1/tournament/series/$seriesId/recovery-challenge',
    );
    if (issued.status != 200) return false;
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
      return false;
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
      if (signature == null) return false;
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
      return response.status == 200 &&
          response.map['writerGeneration'] is int;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
