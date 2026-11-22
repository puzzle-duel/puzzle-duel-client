import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:puzzle_duel_mobile/tournament/guest_auth.dart';

/// Refresh credentials never enter application-support JSON, logs or backups.
final class SecureGuestCredentialStore implements GuestCredentialStore {
  const SecureGuestCredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'pzd.staging.guest.refresh.v1';
  static const _rotationKey = 'pzd.staging.guest.rotation.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> readRefreshToken() => _storage.read(key: _key);

  @override
  Future<void> writeRefreshToken(String token) =>
      _storage.write(key: _key, value: token);

  @override
  Future<void> clearRefreshToken() => _storage.delete(key: _key);

  @override
  Future<String?> readPendingRotationId() => _storage.read(key: _rotationKey);

  @override
  Future<void> writePendingRotationId(String id) =>
      _storage.write(key: _rotationKey, value: id);

  @override
  Future<void> clearPendingRotationId() => _storage.delete(key: _rotationKey);
}
