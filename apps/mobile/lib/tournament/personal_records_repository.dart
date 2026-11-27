import 'dart:async';
import 'dart:convert';

import 'package:puzzle_duel_mobile/diagnostics/diagnostic_runtime.dart';
import 'package:puzzle_duel_mobile/diagnostics/puzzle_duel_logger.dart';
import 'package:puzzle_duel_mobile/tournament/guest_auth.dart';
import 'package:puzzle_duel_mobile/tournament/local_kv_store.dart';
import 'package:puzzle_duel_mobile/tournament/practice_store.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';

/// Practice ruleset wired in ranked-free play (CORE-001 v2 on device).
const personalRecordsPracticeRules = 'core-001.v2';
const personalRecordsPracticeGenerator = 'gen-001.v1';

/// Tournament publication ruleset (server F2-B subgame scores).
const personalRecordsTournamentRules = 'core-001.v3';
const personalRecordsTournamentGenerator = 'gen-001.v1';

const personalRecordDifficulties = ['easy', 'medium', 'hard'];

enum PersonalRecordSegment { all, practice, tournament }

enum PersonalRecordDisplaySource { practice, tournament }

enum PersonalRecordsSyncStatus {
  idle,
  syncing,
  pendingUpload,
  upToDate,
  offline,
  unauthorized,
  serverError,
}

/// One difficulty row for profile display (may combine practice + tournament).
final class PersonalRecordCardModel {
  const PersonalRecordCardModel({
    required this.difficulty,
    required this.score,
    required this.rulesVersion,
    required this.generatorVersion,
    this.achievedAt,
    this.completionId,
    this.moveCount,
    this.displaySource,
    this.localOnly = false,
  });

  final String difficulty;
  final int score;
  final String rulesVersion;
  final String generatorVersion;
  final String? achievedAt;
  final String? completionId;
  final int? moveCount;
  final PersonalRecordDisplaySource? displaySource;
  final bool localOnly;
}

final class PersonalRecordsViewModel {
  const PersonalRecordsViewModel({
    required this.practice,
    required this.tournament,
    required this.combined,
    required this.syncStatus,
    required this.schemaReady,
    required this.practiceStats,
  });

  final Map<String, PersonalRecordCardModel?> practice;
  final Map<String, PersonalRecordCardModel?> tournament;
  final Map<String, PersonalRecordCardModel?> combined;
  final PersonalRecordsSyncStatus syncStatus;
  final bool schemaReady;
  final PracticeStats practiceStats;

  Map<String, PersonalRecordCardModel?> forSegment(PersonalRecordSegment segment) {
    return switch (segment) {
      PersonalRecordSegment.all => combined,
      PersonalRecordSegment.practice => practice,
      PersonalRecordSegment.tournament => tournament,
    };
  }
}

final class PendingPracticeSyncEntry {
  const PendingPracticeSyncEntry({
    required this.difficulty,
    required this.score,
    required this.rulesVersion,
    required this.generatorVersion,
    required this.achievedAt,
    required this.completionId,
    required this.localRevision,
  });

  final String difficulty;
  final int score;
  final String rulesVersion;
  final String generatorVersion;
  final String achievedAt;
  final String completionId;
  final int localRevision;

  Map<String, Object?> toJson() => {
    'difficulty': difficulty,
    'score': score,
    'rulesVersion': rulesVersion,
    'generatorVersion': generatorVersion,
    'achievedAt': achievedAt,
    'completionId': completionId,
    'localRevision': localRevision,
  };

  static PendingPracticeSyncEntry? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final difficulty = raw['difficulty']?.toString() ?? '';
    if (!personalRecordDifficulties.contains(difficulty)) return null;
    final score = raw['score'] is num ? (raw['score'] as num).toInt() : -1;
    if (score < 0) return null;
    final rules = raw['rulesVersion']?.toString() ?? '';
    final gen = raw['generatorVersion']?.toString() ?? '';
    if (rules.isEmpty || gen.isEmpty) return null;
    final completionId = raw['completionId']?.toString() ?? '';
    if (completionId.isEmpty) return null;
    final revision = raw['localRevision'] is num
        ? (raw['localRevision'] as num).toInt()
        : 0;
    if (revision < 1) return null;
    return PendingPracticeSyncEntry(
      difficulty: difficulty,
      score: score,
      rulesVersion: rules,
      generatorVersion: gen,
      achievedAt: raw['achievedAt']?.toString() ?? '',
      completionId: completionId,
      localRevision: revision,
    );
  }
}

final class CachedRemotePersonalRecord {
  const CachedRemotePersonalRecord({
    required this.difficulty,
    required this.source,
    required this.score,
    required this.rulesVersion,
    required this.generatorVersion,
    required this.achievedAt,
    this.completionId,
  });

  final String difficulty;
  final String source;
  final int score;
  final String rulesVersion;
  final String generatorVersion;
  final String achievedAt;
  final String? completionId;

  static CachedRemotePersonalRecord? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final difficulty = raw['difficulty']?.toString() ?? '';
    if (!personalRecordDifficulties.contains(difficulty)) return null;
    final source = raw['source']?.toString() ?? '';
    if (source != 'practice' && source != 'tournament') return null;
    final score = raw['score'] is num ? (raw['score'] as num).toInt() : -1;
    if (score < 0) return null;
    return CachedRemotePersonalRecord(
      difficulty: difficulty,
      source: source,
      score: score,
      rulesVersion: raw['rulesVersion']?.toString() ?? '',
      generatorVersion: raw['generatorVersion']?.toString() ?? '',
      achievedAt: raw['achievedAt']?.toString() ?? '',
      completionId: raw['completionId']?.toString(),
    );
  }
}

/// Account-scoped practice sync + remote snapshot. PracticeStore remains the
/// local practice best source of truth; this layer reconciles and uploads.
final class PersonalRecordsRepository {
  // ignore: prefer_initializing_formals — public ctor names are kv/practiceStore
  PersonalRecordsRepository({
    required LocalKvStore kv,
    required this.api,
    required this.sessionAuth,
    required PracticeStore Function() practiceStore,
    DateTime Function()? clock,
  }) : _kv = kv,
       _practiceStore = practiceStore,
       _clock = clock ?? DateTime.now;

  static const _pendingSchema = 1;
  static const _remoteSchema = 1;
  static const _maxSyncAttempts = 4;
  static const _baseBackoffMs = 800;

  final LocalKvStore _kv;
  final UatApi api;
  final GuestAuthClient? sessionAuth;
  final PracticeStore Function() _practiceStore;
  final DateTime Function() _clock;

  int _accountSyncGeneration = 0;
  Future<void>? _syncInFlight;
  String? _syncInFlightKey;
  PersonalRecordsSyncStatus _lastSyncStatus = PersonalRecordsSyncStatus.idle;
  bool _schemaReady = true;
  Map<String, CachedRemotePersonalRecord> _remoteByKey = {};

  int get accountSyncGeneration => _accountSyncGeneration;

  /// Discards in-flight sync responses after logout / account switch.
  void fenceSync() {
    _accountSyncGeneration++;
    _syncInFlight = null;
    _syncInFlightKey = null;
  }

  static String? accountScopeKey({
    required String apiOrigin,
    required GuestAuthClient? sessionAuth,
  }) {
    final access = sessionAuth?.cachedAccess;
    if (access == null || !access.isVerified) return null;
    final playerId = access.playerId.trim().toLowerCase();
    if (playerId.isEmpty) return null;
    return '$apiOrigin|player:$playerId';
  }

  static String _storageToken(String scopeKey) =>
      UatApi.authBinding(scopeKey);

  String _pendingFile(String scopeKey) =>
      'personal-records-pending-${_storageToken(scopeKey)}.json';

  String _remoteFile(String scopeKey) =>
      'personal-records-remote-${_storageToken(scopeKey)}.json';

  Future<PersonalRecordsViewModel> loadViewModel() async {
    final scopeKey = scopeKeyForActiveAccount();
    if (scopeKey != null) {
      await hydrateRemoteCacheForScope(scopeKey);
    } else {
      _remoteByKey = {};
    }
    final store = _practiceStore();
    final stats = await store.stats();
    final practice = await _practiceCardsFromStore(store);
    final tournament = _tournamentCardsFromRemote();
    final combined = deriveAllSegment(practice: practice, tournament: tournament);
    final pending = await _loadPending(scopeKey);
    final syncStatus = _deriveSyncStatus(pending);
    return PersonalRecordsViewModel(
      practice: practice,
      tournament: tournament,
      combined: combined,
      syncStatus: syncStatus,
      schemaReady: _schemaReady,
      practiceStats: stats,
    );
  }

  PersonalRecordsSyncStatus _deriveSyncStatus(
    Map<String, PendingPracticeSyncEntry> pending,
  ) {
    if (!_isVerified) return PersonalRecordsSyncStatus.idle;
    if (_lastSyncStatus == PersonalRecordsSyncStatus.syncing) {
      return PersonalRecordsSyncStatus.syncing;
    }
    if (pending.isNotEmpty) return PersonalRecordsSyncStatus.pendingUpload;
    return _lastSyncStatus;
  }

  bool get _isVerified {
    final access = sessionAuth?.cachedAccess;
    return access != null && access.isVerified;
  }

  String? scopeKeyForActiveAccount() {
    if (!_isVerified) return null;
    return accountScopeKey(
      apiOrigin: api.baseUrl,
      sessionAuth: sessionAuth,
    );
  }

  /// After [PracticeStore.append] when the finished score is a new local best.
  Future<void> notifyLocalPracticeBest({
    required PracticeRecord record,
    required bool improved,
  }) async {
    if (!improved || !_isVerified) return;
    final scopeKey = scopeKeyForActiveAccount();
    if (scopeKey == null) return;
    final pending = await _loadPending(scopeKey);
    final revision = _nextRevision(pending, record.difficulty);
    final entry = PendingPracticeSyncEntry(
      difficulty: record.difficulty,
      score: record.score,
      rulesVersion: record.rulesVersion,
      generatorVersion: record.generatorVersion,
      achievedAt: record.completedAt,
      completionId: record.sessionId,
      localRevision: revision,
    );
    pending[record.difficulty] = _maxPending(pending[record.difficulty], entry);
    await _savePending(scopeKey, pending);
    _lastSyncStatus = PersonalRecordsSyncStatus.pendingUpload;
    unawaited(scheduleSyncIfNeeded());
  }

  static PendingPracticeSyncEntry _maxPending(
    PendingPracticeSyncEntry? existing,
    PendingPracticeSyncEntry incoming,
  ) {
    if (existing == null || incoming.score > existing.score) return incoming;
    if (incoming.score < existing.score) return existing;
    return incoming.localRevision >= existing.localRevision
        ? incoming
        : existing;
  }

  int _nextRevision(
    Map<String, PendingPracticeSyncEntry> pending,
    String difficulty,
  ) {
    final current = pending[difficulty]?.localRevision ?? 0;
    var max = current;
    for (final entry in pending.values) {
      if (entry.localRevision > max) max = entry.localRevision;
    }
    return max + 1;
  }

  Future<void> refreshRemote({required int expectedGeneration}) async {
    if (!_isVerified) return;
    final scopeKey = scopeKeyForActiveAccount();
    if (scopeKey == null) return;
    unawaited(DiagnosticRuntime.logger.log(LogEvent(
      level: LogLevel.info,
      code: LogCode.screenOpened,
      operation: 'fetchPersonalRecords',
    )));
    final result = await api.get('/v1/profile/me/personal-records');
    if (expectedGeneration != _accountSyncGeneration) return;
    if (result.status == 0) {
      _lastSyncStatus = PersonalRecordsSyncStatus.offline;
      unawaited(DiagnosticRuntime.logger.log(LogEvent(
        level: LogLevel.warning,
        code: LogCode.httpFailed,
        operation: 'fetchPersonalRecords',
        errorCode: result.error,
      )));
      return;
    }
    if (result.status == 401 || result.status == 403) {
      _lastSyncStatus = PersonalRecordsSyncStatus.unauthorized;
      unawaited(DiagnosticRuntime.logger.log(LogEvent(
        level: LogLevel.warning,
        code: LogCode.authExpired,
        operation: 'fetchPersonalRecords',
        httpStatus: result.status,
        errorCode: result.error,
      )));
      return;
    }
    if (result.status < 200 || result.status >= 300) {
      _lastSyncStatus = PersonalRecordsSyncStatus.serverError;
      unawaited(DiagnosticRuntime.logger.log(LogEvent(
        level: LogLevel.warning,
        code: LogCode.httpFailed,
        operation: 'fetchPersonalRecords',
        httpStatus: result.status,
        errorCode: result.error,
      )));
      return;
    }
    final map = result.map;
    _schemaReady = map['schemaReady'] == true;
    final records = _parseRemoteRecords(map['records']);
    _remoteByKey = records;
    await _saveRemoteCache(scopeKey, records);
    _reconcileLocalWithRemote(scopeKey, records);
    unawaited(DiagnosticRuntime.logger.log(LogEvent(
      level: LogLevel.info,
      code: LogCode.httpCompleted,
      operation: 'fetchPersonalRecords',
      httpStatus: result.status,
    )));
    final remaining = await _loadPending(scopeKey);
    if (remaining.isEmpty) {
      _lastSyncStatus = PersonalRecordsSyncStatus.upToDate;
    }
  }

  Future<void> scheduleSyncIfNeeded() async {
    if (!_isVerified) return;
    final scopeKey = scopeKeyForActiveAccount();
    if (scopeKey == null) return;
    final pending = await _loadPending(scopeKey);
    if (pending.isEmpty) return;
    if (_syncInFlight != null && _syncInFlightKey == scopeKey) {
      return _syncInFlight;
    }
    final generation = _accountSyncGeneration;
    final operation = _syncPendingBody(scopeKey, pending, generation);
    _syncInFlight = operation;
    _syncInFlightKey = scopeKey;
    await operation;
    if (identical(_syncInFlight, operation)) {
      _syncInFlight = null;
      _syncInFlightKey = null;
    }
  }

  Future<void> refreshAndSync({required int expectedGeneration}) async {
    await refreshRemote(expectedGeneration: expectedGeneration);
    if (expectedGeneration != _accountSyncGeneration) return;
    await scheduleSyncIfNeeded();
  }

  Future<void> _syncPendingBody(
    String scopeKey,
    Map<String, PendingPracticeSyncEntry> pending,
    int generation,
  ) async {
    if (pending.isEmpty || generation != _accountSyncGeneration) return;
    _lastSyncStatus = PersonalRecordsSyncStatus.syncing;
    unawaited(DiagnosticRuntime.logger.log(LogEvent(
      level: LogLevel.info,
      code: LogCode.screenOpened,
      operation: 'syncPracticeRecords',
    )));
    var attempt = 0;
    while (attempt < _maxSyncAttempts && generation == _accountSyncGeneration) {
      final batch = pending.values.toList();
      final body = {
        'records': [
          for (final entry in batch)
            {
              'difficulty': entry.difficulty,
              'score': entry.score,
              'rulesVersion': entry.rulesVersion,
              'generatorVersion': entry.generatorVersion,
              'achievedAt': entry.achievedAt,
              'completionId': entry.completionId,
              'localRevision': entry.localRevision,
            },
        ],
      };
      final result = await api.post(
        '/v1/profile/me/personal-records/practice/sync',
        body,
      );
      if (generation != _accountSyncGeneration) return;
      if (result.status == 0) {
        _lastSyncStatus = PersonalRecordsSyncStatus.offline;
        unawaited(DiagnosticRuntime.logger.log(LogEvent(
          level: LogLevel.warning,
          code: LogCode.httpFailed,
          operation: 'syncPracticeRecords',
          errorCode: result.error,
        )));
        await _backoff(attempt++);
        continue;
      }
      if (result.status == 401 || result.status == 403) {
        _lastSyncStatus = PersonalRecordsSyncStatus.unauthorized;
        return;
      }
      if (result.status == 503) {
        _schemaReady = false;
        _lastSyncStatus = PersonalRecordsSyncStatus.serverError;
        return;
      }
      if (result.status < 200 || result.status >= 300) {
        _lastSyncStatus = PersonalRecordsSyncStatus.serverError;
        await _backoff(attempt++);
        continue;
      }
      final map = result.map;
      _schemaReady = map['schemaReady'] == true;
      await _applySyncResponse(
        scopeKey: scopeKey,
        pending: pending,
        acknowledgements: map['acknowledgements'],
        records: map['records'],
      );
      unawaited(DiagnosticRuntime.logger.log(LogEvent(
        level: LogLevel.info,
        code: LogCode.httpCompleted,
        operation: 'syncPracticeRecords',
        httpStatus: result.status,
      )));
      final remaining = await _loadPending(scopeKey);
      _lastSyncStatus = remaining.isEmpty
          ? PersonalRecordsSyncStatus.upToDate
          : PersonalRecordsSyncStatus.pendingUpload;
      return;
    }
  }

  Future<void> _applySyncResponse({
    required String scopeKey,
    required Map<String, PendingPracticeSyncEntry> pending,
    required Object? acknowledgements,
    required Object? records,
  }) async {
    if (acknowledgements is List) {
      for (final raw in acknowledgements) {
        if (raw is! Map) continue;
        final difficulty = raw['difficulty']?.toString() ?? '';
        final revision = raw['localRevision'] is num
            ? (raw['localRevision'] as num).toInt()
            : 0;
        final remoteScore = raw['remoteScore'] is num
            ? (raw['remoteScore'] as num).toInt()
            : -1;
        final entry = pending[difficulty];
        if (entry == null || entry.localRevision != revision) continue;
        if (remoteScore >= entry.score) {
          pending.remove(difficulty);
        }
      }
    }
    await _savePending(scopeKey, pending);
    final parsed = _parseRemoteRecords(records);
    if (parsed.isNotEmpty) {
      _remoteByKey = parsed;
      await _saveRemoteCache(scopeKey, parsed);
    }
  }

  Future<void> _backoff(int attempt) async {
    final ms = _baseBackoffMs * (1 << attempt.clamp(0, 4));
    await Future<void>.delayed(Duration(milliseconds: ms));
  }

  Future<void> hydrateRemoteCacheForScope(String scopeKey) async {
    _remoteByKey = await _loadRemote(scopeKey);
  }

  Future<Map<String, PendingPracticeSyncEntry>> _loadPending(
    String? scopeKey,
  ) async {
    if (scopeKey == null) return {};
    final text = await _kv.read(_pendingFile(scopeKey));
    if (text == null) return {};
    try {
      final raw = jsonDecode(text);
      if (raw is! Map || raw['schemaVersion'] != _pendingSchema) return {};
      final entries = raw['pending'];
      if (entries is! Map) return {};
      final out = <String, PendingPracticeSyncEntry>{};
      for (final item in entries.values) {
        final parsed = PendingPracticeSyncEntry.tryParse(item);
        if (parsed != null) {
          out[parsed.difficulty] = _maxPending(out[parsed.difficulty], parsed);
        }
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> _savePending(
    String scopeKey,
    Map<String, PendingPracticeSyncEntry> pending,
  ) async {
    await _kv.writeAtomic(
      _pendingFile(scopeKey),
      jsonEncode({
        'schemaVersion': _pendingSchema,
        'scopeKey': scopeKey,
        'pending': {
          for (final entry in pending.entries)
            entry.key: entry.value.toJson(),
        },
      }),
    );
  }

  Future<Map<String, CachedRemotePersonalRecord>> _loadRemote(
    String scopeKey,
  ) async {
    final text = await _kv.read(_remoteFile(scopeKey));
    if (text == null) return {};
    try {
      final raw = jsonDecode(text);
      if (raw is! Map || raw['schemaVersion'] != _remoteSchema) return {};
      return _parseRemoteRecords(raw['records']);
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveRemoteCache(
    String scopeKey,
    Map<String, CachedRemotePersonalRecord> records,
  ) async {
    await _kv.writeAtomic(
      _remoteFile(scopeKey),
      jsonEncode({
        'schemaVersion': _remoteSchema,
        'scopeKey': scopeKey,
        'fetchedAtMs': _clock().toUtc().millisecondsSinceEpoch,
        'records': [
          for (final record in records.values)
            {
              'difficulty': record.difficulty,
              'source': record.source,
              'score': record.score,
              'rulesVersion': record.rulesVersion,
              'generatorVersion': record.generatorVersion,
              'achievedAt': record.achievedAt,
              if (record.completionId != null)
                'completionId': record.completionId,
            },
        ],
      }),
    );
  }

  static Map<String, CachedRemotePersonalRecord> _parseRemoteRecords(
    Object? raw,
  ) {
    if (raw is! List) return {};
    final out = <String, CachedRemotePersonalRecord>{};
    for (final item in raw) {
      final parsed = CachedRemotePersonalRecord.tryParse(item);
      if (parsed == null) continue;
      final key = _remoteKey(parsed);
      final existing = out[key];
      if (existing == null || parsed.score > existing.score) {
        out[key] = parsed;
      }
    }
    return out;
  }

  static String _remoteKey(CachedRemotePersonalRecord record) =>
      '${record.source}|${record.difficulty}|${record.rulesVersion}|${record.generatorVersion}';

  void _reconcileLocalWithRemote(
    String scopeKey,
    Map<String, CachedRemotePersonalRecord> remote,
  ) {
    // Maximum-only: remote cache never lowers local PracticeStore scores.
    // Pending upload still wins when higher than remote until acked.
    unawaited(_loadPending(scopeKey));
    _remoteByKey = remote;
  }

  Future<Map<String, PersonalRecordCardModel?>> _practiceCardsFromStore(
    PracticeStore store,
  ) async {
    final remote = _remoteByKey;
    final scopeKey = scopeKeyForActiveAccount();
    final pending = await _loadPending(scopeKey);
    final out = <String, PersonalRecordCardModel?>{};
    for (final difficulty in personalRecordDifficulties) {
      final local = await store.personalBestForDifficulty(
        difficulty,
        rulesVersion: personalRecordsPracticeRules,
        preferredGeneratorVersion: personalRecordsPracticeGenerator,
      );
      final remotePractice = remote.values.where(
        (r) =>
            r.source == 'practice' &&
            r.difficulty == difficulty &&
            r.rulesVersion == personalRecordsPracticeRules &&
            r.generatorVersion == personalRecordsPracticeGenerator,
      );
      CachedRemotePersonalRecord? remoteBest;
      for (final r in remotePractice) {
        if (remoteBest == null || r.score > remoteBest.score) remoteBest = r;
      }
      final pend = pending[difficulty];
      final scores = <int, PersonalRecordCardModel>{};
      if (local != null) {
        scores[local.score] = PersonalRecordCardModel(
          difficulty: difficulty,
          score: local.score,
          rulesVersion: local.rulesVersion,
          generatorVersion: local.generatorVersion,
          achievedAt: local.completedAt,
          completionId: local.sessionId,
          moveCount: local.moveCount,
          displaySource: PersonalRecordDisplaySource.practice,
          localOnly: !_isVerified,
        );
      }
      if (remoteBest != null) {
        final card = PersonalRecordCardModel(
          difficulty: difficulty,
          score: remoteBest.score,
          rulesVersion: remoteBest.rulesVersion,
          generatorVersion: remoteBest.generatorVersion,
          achievedAt: remoteBest.achievedAt,
          completionId: remoteBest.completionId,
          displaySource: PersonalRecordDisplaySource.practice,
        );
        final existing = scores[remoteBest.score];
        if (existing == null || remoteBest.score > existing.score) {
          scores[remoteBest.score] = card;
        }
      }
      if (pend != null) {
        final card = PersonalRecordCardModel(
          difficulty: difficulty,
          score: pend.score,
          rulesVersion: pend.rulesVersion,
          generatorVersion: pend.generatorVersion,
          achievedAt: pend.achievedAt,
          completionId: pend.completionId,
          displaySource: PersonalRecordDisplaySource.practice,
          localOnly: true,
        );
        final maxScore = scores.keys.fold<int>(0, (a, b) => a > b ? a : b);
        if (pend.score >= maxScore) {
          scores[pend.score] = card;
        }
      }
      PersonalRecordCardModel? best;
      for (final card in scores.values) {
        if (best == null || card.score > best.score) best = card;
      }
      out[difficulty] = best;
    }
    return out;
  }

  Map<String, PersonalRecordCardModel?> _tournamentCardsFromRemote() {
    final out = <String, PersonalRecordCardModel?>{};
    for (final difficulty in personalRecordDifficulties) {
      CachedRemotePersonalRecord? best;
      for (final record in _remoteByKey.values) {
        if (record.source != 'tournament' || record.difficulty != difficulty) {
          continue;
        }
        if (record.rulesVersion != personalRecordsTournamentRules) continue;
        if (record.generatorVersion != personalRecordsTournamentGenerator) {
          continue;
        }
        if (best == null || record.score > best.score) best = record;
      }
      out[difficulty] = best == null
          ? null
          : PersonalRecordCardModel(
              difficulty: difficulty,
              score: best.score,
              rulesVersion: best.rulesVersion,
              generatorVersion: best.generatorVersion,
              achievedAt: best.achievedAt,
              completionId: best.completionId,
              displaySource: PersonalRecordDisplaySource.tournament,
            );
    }
    return out;
  }

  /// Public for unit tests: max(practice, tournament) per difficulty with source.
  static Map<String, PersonalRecordCardModel?> deriveAllSegment({
    required Map<String, PersonalRecordCardModel?> practice,
    required Map<String, PersonalRecordCardModel?> tournament,
  }) {
    final out = <String, PersonalRecordCardModel?>{};
    for (final difficulty in personalRecordDifficulties) {
      final p = practice[difficulty];
      final t = tournament[difficulty];
      if (p == null && t == null) {
        out[difficulty] = null;
        continue;
      }
      if (p == null) {
        out[difficulty] = t;
        continue;
      }
      if (t == null) {
        out[difficulty] = p;
        continue;
      }
      if (p.score >= t.score) {
        out[difficulty] = PersonalRecordCardModel(
          difficulty: difficulty,
          score: p.score,
          rulesVersion: p.rulesVersion,
          generatorVersion: p.generatorVersion,
          achievedAt: p.achievedAt,
          completionId: p.completionId,
          moveCount: p.moveCount,
          displaySource: PersonalRecordDisplaySource.practice,
          localOnly: p.localOnly,
        );
      } else {
        out[difficulty] = PersonalRecordCardModel(
          difficulty: difficulty,
          score: t.score,
          rulesVersion: t.rulesVersion,
          generatorVersion: t.generatorVersion,
          achievedAt: t.achievedAt,
          completionId: t.completionId,
          displaySource: PersonalRecordDisplaySource.tournament,
        );
      }
    }
    return out;
  }

  /// Test hook: apply ack without HTTP.
  Future<void> debugApplyAcknowledgement({
    required String scopeKey,
    required String difficulty,
    required int localRevision,
    required int remoteScore,
  }) async {
    final pending = await _loadPending(scopeKey);
    final entry = pending[difficulty];
    if (entry == null || entry.localRevision != localRevision) return;
    if (remoteScore >= entry.score) {
      pending.remove(difficulty);
      await _savePending(scopeKey, pending);
    }
  }
}