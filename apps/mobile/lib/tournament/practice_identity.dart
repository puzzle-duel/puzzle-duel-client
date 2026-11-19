import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Authoritative practice-storage scope. Never derived from display names.
enum PracticeIdentityKind { guest, player }

final class PracticeIdentityScope {
  const PracticeIdentityScope._(this.kind, this.id);

  final PracticeIdentityKind kind;
  final String id;

  /// File-safe token used in practice filenames.
  String get storageKey => switch (kind) {
    PracticeIdentityKind.guest => 'guest_$id',
    PracticeIdentityKind.player => 'player_$id',
  };

  static final RegExp uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  static PracticeIdentityScope? tryParseStorageKey(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.startsWith('guest_')) {
      final id = value.substring('guest_'.length);
      if (!uuidPattern.hasMatch(id)) return null;
      return PracticeIdentityScope._(PracticeIdentityKind.guest, id);
    }
    if (value.startsWith('player_')) {
      final id = value.substring('player_'.length);
      if (!uuidPattern.hasMatch(id)) return null;
      return PracticeIdentityScope._(PracticeIdentityKind.player, id);
    }
    return null;
  }

  static PracticeIdentityScope guest(String id) {
    final normalized = id.trim().toLowerCase();
    if (!uuidPattern.hasMatch(normalized)) {
      throw ArgumentError.value(id, 'id', 'guest id must be a UUID');
    }
    return PracticeIdentityScope._(PracticeIdentityKind.guest, normalized);
  }

  static PracticeIdentityScope? tryPlayer(String? playerId) {
    if (playerId == null) return null;
    final normalized = playerId.trim().toLowerCase();
    if (!uuidPattern.hasMatch(normalized)) return null;
    return PracticeIdentityScope._(PracticeIdentityKind.player, normalized);
  }

  @override
  bool operator ==(Object other) =>
      other is PracticeIdentityScope && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

/// Local guest UUID + optional verified server player id for practice isolation.
///
/// Guest → authenticated migration never copies or merges records automatically.
/// Display names / UAT player labels are never persistence identities.
final class PracticeIdentityStore {
  PracticeIdentityStore(this.directory, {Random? random})
    : _file = File('${directory.path}/practice-identity.json'),
      _random = random ?? Random.secure();

  static const schemaVersion = 1;

  final Directory directory;
  final File _file;
  final Random _random;

  String? _guestLocalId;
  String? _activePlayerId;
  var _legacyMigrated = false;

  PracticeIdentityScope get activeScope {
    final player = PracticeIdentityScope.tryPlayer(_activePlayerId);
    if (player != null) return player;
    return PracticeIdentityScope.guest(_requireGuestId());
  }

  String get guestLocalId => _requireGuestId();

  String? get activePlayerId => _activePlayerId;

  bool get isAuthenticated =>
      PracticeIdentityScope.tryPlayer(_activePlayerId) != null;

  Future<void> load() async {
    _loadSync();
  }

  void _loadSync() {
    if (!_file.existsSync()) {
      _guestLocalId = _newUuid();
      _activePlayerId = null;
      _legacyMigrated = false;
      _persistSync();
      return;
    }
    try {
      final raw = jsonDecode(_file.readAsStringSync());
      if (raw is! Map) {
        _resetGuestOnlySync();
        return;
      }
      final guest = raw['guestLocalId']?.toString();
      if (guest != null && PracticeIdentityScope.uuidPattern.hasMatch(guest)) {
        _guestLocalId = guest.trim().toLowerCase();
      } else {
        _guestLocalId = _newUuid();
      }
      final player = raw['activePlayerId']?.toString();
      _activePlayerId = PracticeIdentityScope.tryPlayer(player)?.id;
      _legacyMigrated = raw['legacyLabelScopesMigratedToGuest'] == true;
      _persistSync();
    } catch (_) {
      _resetGuestOnlySync();
    }
  }

  /// Bind practice reads/writes to the verified internal player id from session.
  /// Does not copy guest records into the player scope.
  Future<bool> bindAuthenticatedPlayer(String playerId) async {
    final scope = PracticeIdentityScope.tryPlayer(playerId);
    if (scope == null) return false;
    _requireGuestId();
    _activePlayerId = scope.id;
    _persistSync();
    return true;
  }

  /// Clear authenticated binding after logout. Guest scope becomes active again.
  /// Player-scoped files remain on disk but are not read while logged out.
  Future<void> clearAuthenticatedPlayer() async {
    _requireGuestId();
    _activePlayerId = null;
    _persistSync();
  }

  bool get legacyLabelScopesMigratedToGuest => _legacyMigrated;

  Future<void> markLegacyLabelScopesMigratedToGuest() async {
    _legacyMigrated = true;
    _persistSync();
  }

  void _resetGuestOnlySync() {
    _guestLocalId = _newUuid();
    _activePlayerId = null;
    _legacyMigrated = false;
    _persistSync();
  }

  String _requireGuestId() {
    final existing = _guestLocalId;
    if (existing != null &&
        PracticeIdentityScope.uuidPattern.hasMatch(existing)) {
      return existing;
    }
    final created = _newUuid();
    _guestLocalId = created;
    return created;
  }

  void _persistSync() {
    directory.createSync(recursive: true);
    final payload = jsonEncode({
      'schemaVersion': schemaVersion,
      'guestLocalId': _requireGuestId(),
      'activePlayerId': _activePlayerId,
      'legacyLabelScopesMigratedToGuest': _legacyMigrated,
      'guestToPlayerAutoMerge': false,
    });
    final tmp = File('${_file.path}.tmp');
    tmp.writeAsStringSync(payload, flush: true);
    if (_file.existsSync()) {
      _file.deleteSync();
    }
    tmp.renameSync(_file.path);
  }

  String _newUuid() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int value) => value.toRadixString(16).padLeft(2, '0');
    final b = bytes.map(hex).join();
    return '${b.substring(0, 8)}-${b.substring(8, 12)}-${b.substring(12, 16)}-'
        '${b.substring(16, 20)}-${b.substring(20, 32)}';
  }
}
