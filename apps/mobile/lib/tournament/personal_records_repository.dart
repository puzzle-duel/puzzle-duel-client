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

/// Internal sync terminal outcomes used to gate immediate reschedule.
enum PersonalRecordsSyncOutcome {
  idle,
  clearedAll,
  madeProgressRemaining,
  noProgress,
  unauthorized,
  schemaNotReady,

  /// HTTP 404 — non-retryable ingress/config failure (not transport flake).
  routeNotFound,
  retryExhausted,
  aborted,
  failed,
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

  Map<String, PersonalRecordCardModel?> forSegment(
    PersonalRecordSegment segment,
  ) {
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

  String get versionKey => '$difficulty|$rulesVersion|$generatorVersion';

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

final class _ScopedCache {
  Map<String, CachedRemotePersonalRecord> remoteByKey = {};
  bool schemaReady = true;
  PersonalRecordsSyncStatus syncStatus = PersonalRecordsSyncStatus.idle;
}

/// Account-scoped practice sync + remote snapshot. PracticeStore remains the
/// local practice best source of truth; this layer reconciles and uploads.
final class PersonalRecordsRepository {
  PersonalRecordsRepository({
    required this.kv,
    required this.api,
    required this.sessionAuth,
    required this.practiceStore,
    DateTime Function()? clock,
    Future<void> Function(Duration duration)? sleeper,
  }) : _clock = clock ?? DateTime.now,
       _sleeper = sleeper ?? Future<void>.delayed;

  static const _pendingSchema = 1;
  static const _remoteSchema = 1;
  static const _maxSyncAttempts = 4;
  static const _baseBackoffMs = 800;

  final LocalKvStore kv;
  final UatApi api;
  final GuestAuthClient? sessionAuth;
  final PracticeStore Function() practiceStore;
  final DateTime Function() _clock;
  final Future<void> Function(Duration duration) _sleeper;

  int _accountSyncGeneration = 0;
  Future<void>? _syncInFlight;
  String? _syncInFlightKey;
  int? _syncInFlightGeneration;
  PersonalRecordsSyncOutcome? _lastSyncOutcome;
  String? _lastSyncOutcomeKey;

  /// When set, [scheduleSyncIfNeeded] will not start another flight until an
  /// explicit resume (refresh/auth/connectivity/new local best with force).
  bool _syncBlockedUntilResume = false;

  /// Per-scope serialized pending read-modify-write chain.
  final Map<String, Future<void>> _pendingLocks = {};

  /// In-memory caches keyed by account scope — never shared across accounts.
  final Map<String, _ScopedCache> _scopedCaches = {};

  int get accountSyncGeneration => _accountSyncGeneration;

  /// Test/inspection hook for the most recent sync terminal outcome.
  PersonalRecordsSyncOutcome? get debugLastSyncOutcome => _lastSyncOutcome;

  bool get debugSyncBlockedUntilResume => _syncBlockedUntilResume;

  _ScopedCache _cacheFor(String? scopeKey) {
    if (scopeKey == null) return _ScopedCache();
    return _scopedCaches.putIfAbsent(scopeKey, _ScopedCache.new);
  }

  /// Discards in-flight sync responses after logout / account switch.
  void fenceSync() {
    _accountSyncGeneration++;
    _syncInFlight = null;
    _syncInFlightKey = null;
    _syncInFlightGeneration = null;
    _lastSyncOutcome = PersonalRecordsSyncOutcome.aborted;
    _lastSyncOutcomeKey = null;
    _syncBlockedUntilResume = true;
  }

  static bool _blocksImmediateReschedule(PersonalRecordsSyncOutcome outcome) {
    return outcome == PersonalRecordsSyncOutcome.unauthorized ||
        outcome == PersonalRecordsSyncOutcome.schemaNotReady ||
        outcome == PersonalRecordsSyncOutcome.routeNotFound ||
        outcome == PersonalRecordsSyncOutcome.retryExhausted ||
        outcome == PersonalRecordsSyncOutcome.noProgress ||
        outcome == PersonalRecordsSyncOutcome.failed;
  }

  void _allowSyncResume() {
    _syncBlockedUntilResume = false;
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

  static String _storageToken(String scopeKey) => UatApi.authBinding(scopeKey);

  String _pendingFile(String scopeKey) =>
      'personal-records-pending-${_storageToken(scopeKey)}.json';

  String _remoteFile(String scopeKey) =>
      'personal-records-remote-${_storageToken(scopeKey)}.json';

  bool get _isVerified {
    final access = sessionAuth?.cachedAccess;
    return access != null && access.isVerified;
  }

  String? scopeKeyForActiveAccount() {
    if (!_isVerified) return null;
    return accountScopeKey(apiOrigin: api.baseUrl, sessionAuth: sessionAuth);
  }

  bool _scopeStillActive(String scopeKey, int generation) {
    if (generation != _accountSyncGeneration) return false;
    final current = scopeKeyForActiveAccount();
    return current == scopeKey;
  }

  Future<T> _withPendingLock<T>(String scopeKey, Future<T> Function() action) {
    final previous = _pendingLocks[scopeKey] ?? Future<void>.value();
    final gate = Completer<void>();
    _pendingLocks[scopeKey] = gate.future;
    return previous.catchError((_) {}).then((_) => action()).whenComplete(() {
      gate.complete();
      if (identical(_pendingLocks[scopeKey], gate.future)) {
        _pendingLocks.remove(scopeKey);
      }
    });
  }

  Future<PersonalRecordsViewModel> loadViewModel() async {
    final generation = _accountSyncGeneration;
    final scopeKey = scopeKeyForActiveAccount();

    if (scopeKey != null) {
      await hydrateRemoteCacheForScope(
        scopeKey,
        expectedGeneration: generation,
      );
      if (!_scopeStillActive(scopeKey, generation)) {
        return loadViewModel();
      }
    }

    final activeScope = scopeKeyForActiveAccount();
    if (generation != _accountSyncGeneration) {
      return loadViewModel();
    }
    final store = practiceStore();
    final stats = await store.stats();
    if (generation != _accountSyncGeneration) {
      return loadViewModel();
    }
    final practice = await _practiceCardsFromStore(
      store,
      scopeKey: activeScope,
      generation: generation,
    );
    if (generation != _accountSyncGeneration) {
      return loadViewModel();
    }
    final cache = _cacheFor(activeScope);
    final tournament = _tournamentCardsFromRemote(cache);
    final combined = deriveAllSegment(
      practice: practice,
      tournament: tournament,
    );
    final pending = await _loadPending(activeScope);
    if (generation != _accountSyncGeneration) {
      return loadViewModel();
    }
    return PersonalRecordsViewModel(
      practice: practice,
      tournament: tournament,
      combined: combined,
      syncStatus: _deriveSyncStatus(cache, pending, activeScope),
      schemaReady: cache.schemaReady,
      practiceStats: stats,
    );
  }

  PersonalRecordsSyncStatus _deriveSyncStatus(
    _ScopedCache cache,
    Map<String, PendingPracticeSyncEntry> pending,
    String? scopeKey,
  ) {
    if (scopeKey == null || !_isVerified) {
      return PersonalRecordsSyncStatus.idle;
    }
    if (cache.syncStatus == PersonalRecordsSyncStatus.syncing) {
      return PersonalRecordsSyncStatus.syncing;
    }
    // Prefer explicit failure states over pendingUpload so a failed sync is
    // never presented as healthy progress (durable pending still retained).
    if (cache.syncStatus == PersonalRecordsSyncStatus.unauthorized ||
        cache.syncStatus == PersonalRecordsSyncStatus.offline ||
        cache.syncStatus == PersonalRecordsSyncStatus.serverError) {
      return cache.syncStatus;
    }
    if (pending.isNotEmpty) return PersonalRecordsSyncStatus.pendingUpload;
    return cache.syncStatus;
  }

  /// After [PracticeStore.append] when the finished score is a new local best.
  Future<void> notifyLocalPracticeBest({
    required PracticeRecord record,
    required bool improved,
  }) async {
    if (!improved || !_isVerified) return;
    final generation = _accountSyncGeneration;
    final scopeKey = scopeKeyForActiveAccount();
    if (scopeKey == null) return;

    await _withPendingLock(scopeKey, () async {
      if (!_scopeStillActive(scopeKey, generation)) return;
      final pending = await _loadPending(scopeKey);
      if (!_scopeStillActive(scopeKey, generation)) return;
      final revision = _nextRevision(pending);
      final entry = PendingPracticeSyncEntry(
        difficulty: record.difficulty,
        score: record.score,
        rulesVersion: record.rulesVersion,
        generatorVersion: record.generatorVersion,
        achievedAt: record.completedAt,
        completionId: record.sessionId,
        localRevision: revision,
      );
      final keyed = Map<String, PendingPracticeSyncEntry>.of(pending);
      final existing = keyed[record.difficulty];
      // Keep higher score; never let equal/lower overwrite a better pending.
      keyed[record.difficulty] = _maxPending(existing, entry);
      await _savePending(scopeKey, keyed);
    });

    if (!_scopeStillActive(scopeKey, generation)) return;
    final cache = _cacheFor(scopeKey);
    cache.syncStatus = PersonalRecordsSyncStatus.pendingUpload;
    // New durable work is an explicit resume trigger.
    unawaited(scheduleSyncIfNeeded(force: true));
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

  int _nextRevision(Map<String, PendingPracticeSyncEntry> pending) {
    var max = 0;
    for (final entry in pending.values) {
      if (entry.localRevision > max) max = entry.localRevision;
    }
    return max + 1;
  }

  /// Seeds durable pending rows from PracticeStore bests that exceed remote.
  /// Covers crash between append and notify, and existing local bests on login.
  Future<void> seedPendingFromLocalBests({
    required String scopeKey,
    required int expectedGeneration,
  }) async {
    if (!_scopeStillActive(scopeKey, expectedGeneration)) return;
    final store = practiceStore();
    await _withPendingLock(scopeKey, () async {
      if (!_scopeStillActive(scopeKey, expectedGeneration)) return;
      final pending = Map<String, PendingPracticeSyncEntry>.of(
        await _loadPending(scopeKey),
      );
      final cache = _cacheFor(scopeKey);
      var changed = false;
      for (final difficulty in personalRecordDifficulties) {
        final local = await store.personalBestForDifficulty(
          difficulty,
          rulesVersion: personalRecordsPracticeRules,
          preferredGeneratorVersion: personalRecordsPracticeGenerator,
        );
        if (local == null) continue;
        final remoteBest = _bestRemotePractice(cache.remoteByKey, difficulty);
        if (remoteBest != null && local.score <= remoteBest.score) continue;
        final existing = pending[difficulty];
        if (existing != null && existing.score >= local.score) continue;
        pending[difficulty] = PendingPracticeSyncEntry(
          difficulty: difficulty,
          score: local.score,
          rulesVersion: local.rulesVersion,
          generatorVersion: local.generatorVersion,
          achievedAt: local.completedAt,
          completionId: local.sessionId,
          localRevision: _nextRevision(pending),
        );
        changed = true;
      }
      if (changed && _scopeStillActive(scopeKey, expectedGeneration)) {
        await _savePending(scopeKey, pending);
        cache.syncStatus = PersonalRecordsSyncStatus.pendingUpload;
      }
    });
  }

  CachedRemotePersonalRecord? _bestRemotePractice(
    Map<String, CachedRemotePersonalRecord> remote,
    String difficulty,
  ) {
    CachedRemotePersonalRecord? best;
    for (final r in remote.values) {
      if (r.source != 'practice' || r.difficulty != difficulty) continue;
      if (r.rulesVersion != personalRecordsPracticeRules) continue;
      if (r.generatorVersion != personalRecordsPracticeGenerator) continue;
      if (best == null || r.score > best.score) best = r;
    }
    return best;
  }

  /// Returns the outcome of *this* GET — callers must not consult historical
  /// [_lastSyncOutcome] to decide whether to chain Practice sync.
  Future<PersonalRecordsSyncOutcome> refreshRemote({
    required int expectedGeneration,
  }) async {
    final scopeKey = scopeKeyForActiveAccount();
    if (scopeKey == null || !_scopeStillActive(scopeKey, expectedGeneration)) {
      return PersonalRecordsSyncOutcome.aborted;
    }
    final cache = _cacheFor(scopeKey);
    unawaited(
      DiagnosticRuntime.logger.log(
        LogEvent(
          level: LogLevel.info,
          code: LogCode.screenOpened,
          operation: 'fetchPersonalRecords',
        ),
      ),
    );
    final result = await api.get('/v1/profile/me/personal-records');
    if (!_scopeStillActive(scopeKey, expectedGeneration)) {
      unawaited(
        DiagnosticRuntime.logger.log(
          LogEvent(
            level: LogLevel.info,
            code: LogCode.screenOpened,
            operation: 'fetchPersonalRecords_stale_discarded',
          ),
        ),
      );
      return PersonalRecordsSyncOutcome.aborted;
    }
    if (result.status == 0) {
      cache.syncStatus = PersonalRecordsSyncStatus.offline;
      unawaited(
        DiagnosticRuntime.logger.log(
          LogEvent(
            level: LogLevel.warning,
            code: LogCode.httpFailed,
            operation: 'fetchPersonalRecords',
            errorCode: result.error,
          ),
        ),
      );
      return PersonalRecordsSyncOutcome.retryExhausted;
    }
    if (result.status == 401 || result.status == 403) {
      cache.syncStatus = PersonalRecordsSyncStatus.unauthorized;
      unawaited(
        DiagnosticRuntime.logger.log(
          LogEvent(
            level: LogLevel.warning,
            code: LogCode.authExpired,
            operation: 'fetchPersonalRecords',
            httpStatus: result.status,
            errorCode: result.error,
          ),
        ),
      );
      return PersonalRecordsSyncOutcome.unauthorized;
    }
    if (result.status == 404) {
      // Ingress/config miss — never retry as transport flake; keep local rows.
      cache.syncStatus = PersonalRecordsSyncStatus.serverError;
      if (_scopeStillActive(scopeKey, expectedGeneration)) {
        _lastSyncOutcome = PersonalRecordsSyncOutcome.routeNotFound;
        _lastSyncOutcomeKey = scopeKey;
        _syncBlockedUntilResume = true;
      }
      unawaited(
        DiagnosticRuntime.logger.log(
          LogEvent(
            level: LogLevel.warning,
            code: LogCode.httpFailed,
            operation: 'fetchPersonalRecords',
            httpStatus: result.status,
            errorCode: 'NOT_FOUND',
          ),
        ),
      );
      return PersonalRecordsSyncOutcome.routeNotFound;
    }
    if (result.status < 200 || result.status >= 300) {
      cache.syncStatus = PersonalRecordsSyncStatus.serverError;
      unawaited(
        DiagnosticRuntime.logger.log(
          LogEvent(
            level: LogLevel.warning,
            code: LogCode.httpFailed,
            operation: 'fetchPersonalRecords',
            httpStatus: result.status,
            errorCode: result.error,
          ),
        ),
      );
      return PersonalRecordsSyncOutcome.failed;
    }
    final map = result.map;
    cache.schemaReady = map['schemaReady'] == true;
    final records = _parseRemoteRecords(map['records']);
    // Max-only merge: never allow a stale GET to lower a known remote score.
    cache.remoteByKey = _mergeRemoteMax(cache.remoteByKey, records);
    await _saveRemoteCache(scopeKey, cache.remoteByKey);
    if (!_scopeStillActive(scopeKey, expectedGeneration)) {
      return PersonalRecordsSyncOutcome.aborted;
    }
    unawaited(
      DiagnosticRuntime.logger.log(
        LogEvent(
          level: LogLevel.info,
          code: LogCode.httpCompleted,
          operation: 'fetchPersonalRecords',
          httpStatus: result.status,
        ),
      ),
    );
    final remaining = await _loadPending(scopeKey);
    if (!_scopeStillActive(scopeKey, expectedGeneration)) {
      return PersonalRecordsSyncOutcome.aborted;
    }
    if (remaining.isEmpty) {
      cache.syncStatus = PersonalRecordsSyncStatus.upToDate;
      return PersonalRecordsSyncOutcome.clearedAll;
    }
    cache.syncStatus = PersonalRecordsSyncStatus.pendingUpload;
    return PersonalRecordsSyncOutcome.idle;
  }

  static Map<String, CachedRemotePersonalRecord> _mergeRemoteMax(
    Map<String, CachedRemotePersonalRecord> existing,
    Map<String, CachedRemotePersonalRecord> incoming,
  ) {
    final out = Map<String, CachedRemotePersonalRecord>.of(existing);
    for (final entry in incoming.entries) {
      final prior = out[entry.key];
      if (prior == null || entry.value.score > prior.score) {
        out[entry.key] = entry.value;
      }
    }
    return out;
  }

  Future<void> scheduleSyncIfNeeded({bool force = false}) async {
    final generation = _accountSyncGeneration;
    final scopeKey = scopeKeyForActiveAccount();
    if (scopeKey == null) return;
    if (!_scopeStillActive(scopeKey, generation)) return;
    if (force) _allowSyncResume();

    if (_syncInFlight != null &&
        _syncInFlightKey == scopeKey &&
        _syncInFlightGeneration == generation) {
      await _syncInFlight;
      if (!_scopeStillActive(scopeKey, generation)) return;
      // Hard-stop outcomes must not restart immediately (no 401/403/503 storms).
      if (_syncBlockedUntilResume ||
          (_lastSyncOutcomeKey == scopeKey &&
              _lastSyncOutcome != null &&
              _blocksImmediateReschedule(_lastSyncOutcome!))) {
        return;
      }
      // Successful clear + newly arrived pending may fall through below.
    }

    if (_syncBlockedUntilResume && !force) return;

    final pending = await _loadPending(scopeKey);
    if (!_scopeStillActive(scopeKey, generation)) return;
    if (pending.isEmpty) return;

    if (_syncInFlight != null &&
        _syncInFlightKey == scopeKey &&
        _syncInFlightGeneration == generation) {
      return _syncInFlight;
    }

    // Ensure bearer still belongs to this verified account before POST.
    final access = sessionAuth?.cachedAccess;
    if (access == null || !access.isVerified) return;
    final expectedPlayer = scopeKey.split('player:').last;
    if (access.playerId.trim().toLowerCase() != expectedPlayer) return;

    late final Future<void> operation;
    operation = () async {
      var outcome = PersonalRecordsSyncOutcome.aborted;
      try {
        outcome = await _syncPendingBody(scopeKey, generation);
      } catch (_) {
        outcome = PersonalRecordsSyncOutcome.failed;
        if (_scopeStillActive(scopeKey, generation)) {
          _cacheFor(scopeKey).syncStatus =
              PersonalRecordsSyncStatus.serverError;
        }
      } finally {
        // Stale account completions must not mutate the active account's
        // outcome / retry-block / in-flight markers.
        final stillActive = _scopeStillActive(scopeKey, generation);
        if (stillActive) {
          _lastSyncOutcome = outcome;
          _lastSyncOutcomeKey = scopeKey;
          if (_blocksImmediateReschedule(outcome)) {
            _syncBlockedUntilResume = true;
          }
        }
        if (identical(_syncInFlight, operation) &&
            _syncInFlightKey == scopeKey &&
            _syncInFlightGeneration == generation) {
          _syncInFlight = null;
          _syncInFlightKey = null;
          _syncInFlightGeneration = null;
        }
        // Immediate chain ONLY after acknowledgement progress with remaining work.
        if (stillActive &&
            outcome == PersonalRecordsSyncOutcome.madeProgressRemaining &&
            (_syncInFlight == null || _syncInFlightKey != scopeKey)) {
          unawaited(scheduleSyncIfNeeded(force: true));
        }
      }
    }();
    _syncInFlight = operation;
    _syncInFlightKey = scopeKey;
    _syncInFlightGeneration = generation;
    await operation;
  }

  Future<void> refreshAndSync({required int expectedGeneration}) async {
    final scopeKey = scopeKeyForActiveAccount();
    if (scopeKey == null) return;
    // Auth / connectivity / lifecycle refresh is an explicit resume trigger.
    _allowSyncResume();
    final refreshOutcome = await refreshRemote(
      expectedGeneration: expectedGeneration,
    );
    if (!_scopeStillActive(scopeKey, expectedGeneration)) return;
    // Only the CURRENT GET outcome gates sync — a prior 404 must not block
    // recovery after the route becomes available again.
    if (refreshOutcome == PersonalRecordsSyncOutcome.routeNotFound) {
      return;
    }
    await seedPendingFromLocalBests(
      scopeKey: scopeKey,
      expectedGeneration: expectedGeneration,
    );
    if (!_scopeStillActive(scopeKey, expectedGeneration)) return;
    await scheduleSyncIfNeeded(force: true);
  }

  Future<PersonalRecordsSyncOutcome> _syncPendingBody(
    String scopeKey,
    int generation,
  ) async {
    if (!_scopeStillActive(scopeKey, generation)) {
      return PersonalRecordsSyncOutcome.aborted;
    }
    final cache = _cacheFor(scopeKey);
    cache.syncStatus = PersonalRecordsSyncStatus.syncing;
    unawaited(
      DiagnosticRuntime.logger.log(
        LogEvent(
          level: LogLevel.info,
          code: LogCode.screenOpened,
          operation: 'syncPracticeRecords',
        ),
      ),
    );

    var attempt = 0;
    while (attempt < _maxSyncAttempts &&
        _scopeStillActive(scopeKey, generation)) {
      final pending = await _loadPending(scopeKey);
      if (!_scopeStillActive(scopeKey, generation)) {
        return PersonalRecordsSyncOutcome.aborted;
      }
      if (pending.isEmpty) {
        cache.syncStatus = PersonalRecordsSyncStatus.upToDate;
        return PersonalRecordsSyncOutcome.clearedAll;
      }

      final access = sessionAuth?.cachedAccess;
      if (access == null || !access.isVerified) {
        cache.syncStatus = PersonalRecordsSyncStatus.unauthorized;
        return PersonalRecordsSyncOutcome.unauthorized;
      }
      final expectedPlayer = scopeKey.split('player:').last;
      if (access.playerId.trim().toLowerCase() != expectedPlayer) {
        unawaited(
          DiagnosticRuntime.logger.log(
            LogEvent(
              level: LogLevel.warning,
              code: LogCode.screenOpened,
              operation: 'syncPracticeRecords_account_mismatch',
            ),
          ),
        );
        return PersonalRecordsSyncOutcome.aborted;
      }

      final batch = pending.values.toList();
      final postedSnapshot = <String, PendingPracticeSyncEntry>{
        for (final entry in batch) entry.difficulty: entry,
      };
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
      if (!_scopeStillActive(scopeKey, generation)) {
        unawaited(
          DiagnosticRuntime.logger.log(
            LogEvent(
              level: LogLevel.info,
              code: LogCode.screenOpened,
              operation: 'syncPracticeRecords_stale_discarded',
            ),
          ),
        );
        return PersonalRecordsSyncOutcome.aborted;
      }
      if (result.status == 0) {
        cache.syncStatus = PersonalRecordsSyncStatus.offline;
        unawaited(
          DiagnosticRuntime.logger.log(
            LogEvent(
              level: LogLevel.warning,
              code: LogCode.httpFailed,
              operation: 'syncPracticeRecords',
              errorCode: result.error,
            ),
          ),
        );
        await _backoff(attempt++);
        if (!_scopeStillActive(scopeKey, generation)) {
          return PersonalRecordsSyncOutcome.aborted;
        }
        continue;
      }
      if (result.status == 401 || result.status == 403) {
        cache.syncStatus = PersonalRecordsSyncStatus.unauthorized;
        unawaited(
          DiagnosticRuntime.logger.log(
            LogEvent(
              level: LogLevel.warning,
              code: LogCode.authExpired,
              operation: 'syncPracticeRecords',
              httpStatus: result.status,
              errorCode: result.error,
            ),
          ),
        );
        return PersonalRecordsSyncOutcome.unauthorized;
      }
      if (result.status == 503) {
        cache.schemaReady = false;
        cache.syncStatus = PersonalRecordsSyncStatus.serverError;
        unawaited(
          DiagnosticRuntime.logger.log(
            LogEvent(
              level: LogLevel.warning,
              code: LogCode.httpFailed,
              operation: 'syncPracticeRecords',
              httpStatus: result.status,
              errorCode: 'SCHEMA_NOT_READY',
            ),
          ),
        );
        return PersonalRecordsSyncOutcome.schemaNotReady;
      }
      if (result.status == 404) {
        cache.syncStatus = PersonalRecordsSyncStatus.serverError;
        unawaited(
          DiagnosticRuntime.logger.log(
            LogEvent(
              level: LogLevel.warning,
              code: LogCode.httpFailed,
              operation: 'syncPracticeRecords',
              httpStatus: result.status,
              errorCode: 'NOT_FOUND',
            ),
          ),
        );
        return PersonalRecordsSyncOutcome.routeNotFound;
      }
      if (result.status < 200 || result.status >= 300) {
        cache.syncStatus = PersonalRecordsSyncStatus.serverError;
        unawaited(
          DiagnosticRuntime.logger.log(
            LogEvent(
              level: LogLevel.warning,
              code: LogCode.httpFailed,
              operation: 'syncPracticeRecords',
              httpStatus: result.status,
              errorCode: result.error,
            ),
          ),
        );
        await _backoff(attempt++);
        if (!_scopeStillActive(scopeKey, generation)) {
          return PersonalRecordsSyncOutcome.aborted;
        }
        continue;
      }
      final map = result.map;
      cache.schemaReady = map['schemaReady'] == true;
      final clearedAny = await _applySyncResponse(
        scopeKey: scopeKey,
        generation: generation,
        acknowledgements: map['acknowledgements'],
        records: map['records'],
      );
      if (!_scopeStillActive(scopeKey, generation)) {
        return PersonalRecordsSyncOutcome.aborted;
      }
      unawaited(
        DiagnosticRuntime.logger.log(
          LogEvent(
            level: LogLevel.info,
            code: LogCode.httpCompleted,
            operation: 'syncPracticeRecords',
            httpStatus: result.status,
          ),
        ),
      );
      final remaining = await _loadPending(scopeKey);
      if (!_scopeStillActive(scopeKey, generation)) {
        return PersonalRecordsSyncOutcome.aborted;
      }
      cache.syncStatus = remaining.isEmpty
          ? PersonalRecordsSyncStatus.upToDate
          : PersonalRecordsSyncStatus.pendingUpload;
      if (remaining.isEmpty) {
        return clearedAny
            ? PersonalRecordsSyncOutcome.clearedAll
            : PersonalRecordsSyncOutcome.noProgress;
      }
      // Follow-up when acks cleared work, or pending was superseded in-flight
      // (e.g. higher PB arrived while the POST was outstanding).
      final superseded = remaining.values.any((entry) {
        final posted = postedSnapshot[entry.difficulty];
        if (posted == null) return true;
        return posted.score != entry.score ||
            posted.localRevision != entry.localRevision ||
            posted.completionId != entry.completionId;
      });
      if (clearedAny || superseded) {
        return PersonalRecordsSyncOutcome.madeProgressRemaining;
      }
      return PersonalRecordsSyncOutcome.noProgress;
    }
    return PersonalRecordsSyncOutcome.retryExhausted;
  }

  /// Reloads durable pending before applying acks so an in-flight higher PB
  /// written while the request was outstanding cannot be overwritten.
  /// Returns true when at least one durable pending entry was cleared.
  Future<bool> _applySyncResponse({
    required String scopeKey,
    required int generation,
    required Object? acknowledgements,
    required Object? records,
  }) async {
    var clearedAny = false;
    await _withPendingLock(scopeKey, () async {
      if (!_scopeStillActive(scopeKey, generation)) return;
      final pending = Map<String, PendingPracticeSyncEntry>.of(
        await _loadPending(scopeKey),
      );
      if (!_scopeStillActive(scopeKey, generation)) return;

      if (acknowledgements is List) {
        for (final raw in acknowledgements) {
          if (raw is! Map) continue;
          final difficulty = raw['difficulty']?.toString() ?? '';
          final rulesVersion = raw['rulesVersion']?.toString() ?? '';
          final generatorVersion = raw['generatorVersion']?.toString() ?? '';
          final revision = raw['localRevision'] is num
              ? (raw['localRevision'] as num).toInt()
              : 0;
          final remoteScore = raw['remoteScore'] is num
              ? (raw['remoteScore'] as num).toInt()
              : -1;
          final acceptedScore = raw['acceptedScore'] is num
              ? (raw['acceptedScore'] as num).toInt()
              : remoteScore;
          final entry = pending[difficulty];
          if (entry == null) continue;
          if (entry.localRevision != revision) continue;
          if (rulesVersion.isNotEmpty && entry.rulesVersion != rulesVersion) {
            continue;
          }
          if (generatorVersion.isNotEmpty &&
              entry.generatorVersion != generatorVersion) {
            continue;
          }
          // Clear only when the ack covers this exact pending score/revision.
          if (remoteScore >= entry.score && acceptedScore <= entry.score) {
            pending.remove(difficulty);
            clearedAny = true;
          } else if (remoteScore >= entry.score) {
            pending.remove(difficulty);
            clearedAny = true;
          }
        }
      }

      await _savePending(scopeKey, pending);
      final parsed = _parseRemoteRecords(records);
      if (parsed.isNotEmpty && _scopeStillActive(scopeKey, generation)) {
        final cache = _cacheFor(scopeKey);
        cache.remoteByKey = _mergeRemoteMax(cache.remoteByKey, parsed);
        await _saveRemoteCache(scopeKey, cache.remoteByKey);
      }
    });
    return clearedAny;
  }

  Future<void> _backoff(int attempt) async {
    final ms = _baseBackoffMs * (1 << attempt.clamp(0, 4));
    await _sleeper(Duration(milliseconds: ms));
  }

  Future<void> hydrateRemoteCacheForScope(
    String scopeKey, {
    required int expectedGeneration,
  }) async {
    if (!_scopeStillActive(scopeKey, expectedGeneration) &&
        scopeKeyForActiveAccount() != scopeKey) {
      // Allow hydrate when called with matching active scope even if generation
      // was captured just before — still require scope match.
      if (scopeKeyForActiveAccount() != scopeKey) return;
    }
    final loaded = await _loadRemote(scopeKey);
    if (scopeKeyForActiveAccount() != scopeKey) return;
    final cache = _cacheFor(scopeKey);
    cache.remoteByKey = _mergeRemoteMax(cache.remoteByKey, loaded);
  }

  Future<Map<String, PendingPracticeSyncEntry>> _loadPending(
    String? scopeKey,
  ) async {
    if (scopeKey == null) return {};
    final text = await kv.read(_pendingFile(scopeKey));
    if (text == null) return {};
    try {
      final raw = jsonDecode(text);
      if (raw is! Map || raw['schemaVersion'] != _pendingSchema) return {};
      final storedScope = raw['scopeKey']?.toString();
      if (storedScope != null && storedScope != scopeKey) return {};
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
    await kv.writeAtomic(
      _pendingFile(scopeKey),
      jsonEncode({
        'schemaVersion': _pendingSchema,
        'scopeKey': scopeKey,
        'pending': {
          for (final entry in pending.entries) entry.key: entry.value.toJson(),
        },
      }),
    );
  }

  Future<Map<String, CachedRemotePersonalRecord>> _loadRemote(
    String scopeKey,
  ) async {
    final text = await kv.read(_remoteFile(scopeKey));
    if (text == null) return {};
    try {
      final raw = jsonDecode(text);
      if (raw is! Map || raw['schemaVersion'] != _remoteSchema) return {};
      final storedScope = raw['scopeKey']?.toString();
      if (storedScope != null && storedScope != scopeKey) return {};
      return _parseRemoteRecords(raw['records']);
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveRemoteCache(
    String scopeKey,
    Map<String, CachedRemotePersonalRecord> records,
  ) async {
    await kv.writeAtomic(
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

  Future<Map<String, PersonalRecordCardModel?>> _practiceCardsFromStore(
    PracticeStore store, {
    required String? scopeKey,
    required int generation,
  }) async {
    final cache = _cacheFor(scopeKey);
    final pending = await _loadPending(scopeKey);
    if (generation != _accountSyncGeneration) {
      return {for (final d in personalRecordDifficulties) d: null};
    }
    final out = <String, PersonalRecordCardModel?>{};
    for (final difficulty in personalRecordDifficulties) {
      final local = await store.personalBestForDifficulty(
        difficulty,
        rulesVersion: personalRecordsPracticeRules,
        preferredGeneratorVersion: personalRecordsPracticeGenerator,
      );
      final remoteBest = _bestRemotePractice(cache.remoteByKey, difficulty);
      final pend = pending[difficulty];
      PersonalRecordCardModel? best;
      void consider(PersonalRecordCardModel card) {
        if (best == null || card.score > best!.score) best = card;
      }

      if (local != null) {
        consider(
          PersonalRecordCardModel(
            difficulty: difficulty,
            score: local.score,
            rulesVersion: local.rulesVersion,
            generatorVersion: local.generatorVersion,
            achievedAt: local.completedAt,
            completionId: local.sessionId,
            moveCount: local.moveCount,
            displaySource: PersonalRecordDisplaySource.practice,
            localOnly: !_isVerified,
          ),
        );
      }
      if (remoteBest != null) {
        consider(
          PersonalRecordCardModel(
            difficulty: difficulty,
            score: remoteBest.score,
            rulesVersion: remoteBest.rulesVersion,
            generatorVersion: remoteBest.generatorVersion,
            achievedAt: remoteBest.achievedAt,
            completionId: remoteBest.completionId,
            displaySource: PersonalRecordDisplaySource.practice,
          ),
        );
      }
      if (pend != null) {
        consider(
          PersonalRecordCardModel(
            difficulty: difficulty,
            score: pend.score,
            rulesVersion: pend.rulesVersion,
            generatorVersion: pend.generatorVersion,
            achievedAt: pend.achievedAt,
            completionId: pend.completionId,
            displaySource: PersonalRecordDisplaySource.practice,
            localOnly: true,
          ),
        );
      }
      out[difficulty] = best;
    }
    return out;
  }

  Map<String, PersonalRecordCardModel?> _tournamentCardsFromRemote(
    _ScopedCache cache,
  ) {
    final out = <String, PersonalRecordCardModel?>{};
    for (final difficulty in personalRecordDifficulties) {
      CachedRemotePersonalRecord? best;
      for (final record in cache.remoteByKey.values) {
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

  /// Test hook: apply ack without HTTP (still reloads durable pending).
  Future<void> debugApplyAcknowledgement({
    required String scopeKey,
    required String difficulty,
    required int localRevision,
    required int remoteScore,
  }) async {
    final generation = _accountSyncGeneration;
    await _applySyncResponse(
      scopeKey: scopeKey,
      generation: generation,
      acknowledgements: [
        {
          'difficulty': difficulty,
          'localRevision': localRevision,
          'remoteScore': remoteScore,
          'acceptedScore': remoteScore,
          'rulesVersion': personalRecordsPracticeRules,
          'generatorVersion': personalRecordsPracticeGenerator,
        },
      ],
      records: const [],
    );
  }

  /// Test helper: durable pending scores for [scopeKey].
  Future<Map<String, int>> debugPendingScores(String scopeKey) async {
    final pending = await _loadPending(scopeKey);
    return {for (final e in pending.entries) e.key: e.value.score};
  }
}
