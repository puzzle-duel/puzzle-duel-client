import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:puzzle_duel_mobile/tournament/guest_auth.dart';

/// Separate staging UAT identities. No legacy token is copied or deleted.
enum StagingGuestSlot {
  legacy,
  playerA,
  playerB;

  static StagingGuestSlot parse(String name) => switch (name) {
    'legacy' => StagingGuestSlot.legacy,
    'player-a' => StagingGuestSlot.playerA,
    'player-b' => StagingGuestSlot.playerB,
    _ => throw const GuestAuthException('INVALID_GUEST_SLOT'),
  };
}

/// Pure policy; all keys are stable across app process termination and rebuilds.
final class StagingGuestCredentialKeys {
  const StagingGuestCredentialKeys._(this.refresh, this.rotation);
  final String refresh;
  final String rotation;

  static StagingGuestCredentialKeys forSlot(StagingGuestSlot slot) =>
      switch (slot) {
        StagingGuestSlot.legacy => const StagingGuestCredentialKeys._(
            'pzd.staging.guest.refresh.v1',
            'pzd.staging.guest.rotation.v1',
          ),
        StagingGuestSlot.playerA => const StagingGuestCredentialKeys._(
            'pzd.staging.guest.player-a.refresh.v1',
            'pzd.staging.guest.player-a.rotation.v1',
          ),
        StagingGuestSlot.playerB => const StagingGuestCredentialKeys._(
            'pzd.staging.guest.player-b.refresh.v1',
            'pzd.staging.guest.player-b.rotation.v1',
          ),
      };
}

/// Refresh credentials never enter application-support JSON, logs or backups.
final class SecureGuestCredentialStore implements GuestCredentialStore {
  const SecureGuestCredentialStore({
    FlutterSecureStorage? storage,
    this.slot = StagingGuestSlot.legacy,
  }) : _storage = storage ?? const FlutterSecureStorage();

  final StagingGuestSlot slot;
  final FlutterSecureStorage _storage;

  String get _refreshKey => StagingGuestCredentialKeys.forSlot(slot).refresh;
  String get _rotationKey => StagingGuestCredentialKeys.forSlot(slot).rotation;

  @override
  Future<String?> readRefreshToken() => _storage.read(key: _refreshKey);

  @override
  Future<void> writeRefreshToken(String token) =>
      _storage.write(key: _refreshKey, value: token);

  @override
  Future<void> clearRefreshToken() => _storage.delete(key: _refreshKey);

  @override
  Future<String?> readPendingRotationId() => _storage.read(key: _rotationKey);

  @override
  Future<void> writePendingRotationId(String id) =>
      _storage.write(key: _rotationKey, value: id);

  @override
  Future<void> clearPendingRotationId() => _storage.delete(key: _rotationKey);
}
