import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/application/game_session.dart';
import 'package:puzzle_duel_mobile/presentation/audio/game_sfx.dart';
import 'package:puzzle_duel_mobile/presentation/debug/interaction_perf.dart';
import 'package:puzzle_duel_mobile/tournament/local_kv_store.dart';
import 'package:puzzle_duel_mobile/tournament/local_settings.dart';
import 'package:puzzle_duel_mobile/tournament/practice_identity.dart';
import 'package:puzzle_duel_mobile/tournament/practice_store.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_home_snapshot.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_nav.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

/// Local features vs authoritative Tournament refresh.
enum TournamentSyncState { idle, syncing, ready, degraded }

/// Why a Tournament refresh was requested. Banner UX depends on this origin.
enum TournamentRefreshOrigin {
  /// Automatic launch refresh: silent on success; red banner on failure.
  startup,

  /// Explicit Home pull: blue loading/completed; red on failure.
  pullToRefresh,

  /// Other non-user refreshes: silent success; user-relevant errors only.
  background,
}

/// Local UAT identity. The bearer is issued by the UAT server, not by the app.
final class UatConfig {
  const UatConfig({
    required this.baseUrl,
    required this.bearer,
    required this.playerLabel,
  });

  final String baseUrl;
  final String bearer;
  final String playerLabel;
}

abstract class TournamentHaptics {
  void selection();
  void accepted();
  void rejected();
  void cleared();
  void completed();
}

final class DeviceTournamentHaptics implements TournamentHaptics {
  DeviceTournamentHaptics({this.enabled = _yes, this.successAllowed = _yes});

  static bool _yes() => true;

  final bool Function() enabled;
  final bool Function() successAllowed;

  @override
  void selection() {
    if (enabled()) HapticFeedback.selectionClick();
  }

  @override
  void accepted() {
    if (enabled()) HapticFeedback.lightImpact();
  }

  @override
  void rejected() {
    if (enabled()) HapticFeedback.heavyImpact();
  }

  @override
  void cleared() {
    if (enabled() && successAllowed()) HapticFeedback.mediumImpact();
  }

  @override
  void completed() {
    if (enabled() && successAllowed()) HapticFeedback.heavyImpact();
  }
}

final class SilentTournamentHaptics implements TournamentHaptics {
  const SilentTournamentHaptics();

  @override
  void selection() {}

  @override
  void accepted() {}

  @override
  void rejected() {}

  @override
  void cleared() {}

  @override
  void completed() {}
}

final class _QuietSfx extends GameSfx {
  @override
  bool muted = true;

  @override
  bool get isPrepared => true;

  @override
  Future<void> prepare() async {}

  @override
  void play(GameSfxEvent event) {}
}

final class TournamentController extends ChangeNotifier {
  TournamentController({
    required this.config,
    required this.stateDirectory,
    required this.identity,
    UatApi? api,
    TournamentHaptics? haptics,
    GameSfx? sfx,
    LocalSettings? settings,
  }) : api =
           api ??
           UatApi(
             baseUrl: UatApi.apiOrigin(config.baseUrl),
             bearer: config.bearer,
           ),
       haptics = haptics ?? DeviceTournamentHaptics(),
       sfx = sfx ?? _QuietSfx(),
       settings = settings ?? LocalSettings.load(stateDirectory),
       _kv = DirectoryKvStore(stateDirectory),
       _stateFile = File('${stateDirectory.path}/pzd-uat-session.json');

  final UatConfig config;
  final Directory stateDirectory;
  final PracticeIdentityStore identity;
  final UatApi api;
  final TournamentHaptics haptics;
  final GameSfx sfx;
  final LocalSettings settings;
  final LocalKvStore _kv;
  final File _stateFile;
  final GameSession session = GameSession();
  late final TournamentHomeSnapshotStore _homeSnapshots =
      TournamentHomeSnapshotStore(_kv);

  /// Practice persistence for the active guest or verified player scope.
  PracticeStore practiceStore() => PracticeStore(
    directory: stateDirectory,
    store: _kv,
    scope: identity.activeScope,
    identity: identity,
  );

  TournamentRoute route = const TournamentRoute();
  TournamentDay? day;
  Map<String, Object?> board = const {};
  Map<String, Object?> results = const {};
  Map<String, Object?> leaderboard = const {};
  String? nextCursor;
  String? seriesId;
  String category = 'ALL';
  String? weekStart;
  List<String> weeks = const [];
  bool weeklyFinal = false;

  /// True once local identity/settings are ready. Practice never waits for HTTP.
  bool localReady = false;

  /// Authoritative Tournament refresh lifecycle (independent of [localReady]).
  TournamentSyncState tournamentSync = TournamentSyncState.idle;

  /// Last successful Home summary for the active identity (may be stale).
  TournamentHomeSnapshot? homeSnapshot;
  bool homeSnapshotStale = false;

  bool booting = true;
  bool busy = false;
  bool moveInFlight = false;
  String? noticeCode;
  String? errorCode;

  /// Tournament-area banner when refresh fails without blocking Practice.
  String? tournamentNoticeCode;
  String? resultsError;
  int? scoreDelta;
  int? deadlineMs;
  int? serverNowMs;
  DateTime? syncedAt;

  Map<String, Object?>? _claim;
  Object? _pending;
  String? _pendingKey;
  int _tournamentEpoch = 0;
  Future<void>? _refreshInFlight;
  TournamentRefreshOrigin _refreshOrigin = TournamentRefreshOrigin.background;

  bool get hasPendingCommand => _pending != null;

  bool get tournamentReady => tournamentSync == TournamentSyncState.ready;

  /// Origin of the current or just-finished Tournament refresh (banner policy).
  TournamentRefreshOrigin get tournamentRefreshOrigin => _refreshOrigin;

  /// Confirmed offline/timeout preventing Tournament refresh (not auth/writer).
  bool get tournamentConnectivityLost {
    final code = tournamentNoticeCode;
    return code == 'OFFLINE' || code == 'TIMEOUT';
  }

  /// True while a ranked refresh Future is shared (pull-to-refresh dedupe).
  bool get tournamentRefreshInFlight => _refreshInFlight != null;

  /// Info toasts only for explicit Home pull-to-refresh.
  bool get tournamentInfoBannersEnabled =>
      _refreshOrigin == TournamentRefreshOrigin.pullToRefresh;

  /// The exact command waiting for reconciliation. Retries send this object.
  Object? get pendingCommand => _pending;

  /// Local-only boot: Home + Practice usable without Tournament HTTP.
  Future<void> beginLocal() async {
    InteractionPerf.mark('tournament.beginLocal');
    sfx.muted = !settings.sound;
    session.onAuthoritativeTap = _submitTap;
    await _hydrateHomeSnapshot();
    localReady = true;
    booting = false;
    errorCode = null;
    route = const TournamentRoute();
    notifyListeners();
  }

  /// Ranked Home refresh. Failures stay in the Tournament area.
  ///
  /// Concurrent callers join one in-flight Future. A pull that joins startup
  /// upgrades [_refreshOrigin] so the user still sees pull feedback.
  Future<void> refreshTournament({
    TournamentRefreshOrigin origin = TournamentRefreshOrigin.background,
  }) {
    if (_refreshInFlight != null) {
      if (origin == TournamentRefreshOrigin.pullToRefresh &&
          _refreshOrigin != TournamentRefreshOrigin.pullToRefresh) {
        _refreshOrigin = TournamentRefreshOrigin.pullToRefresh;
        notifyListeners();
      }
      return _refreshInFlight!;
    }
    _refreshOrigin = origin;
    return _refreshInFlight = _refreshTournamentBody().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<void> _refreshTournamentBody() async {
    final epoch = ++_tournamentEpoch;
    InteractionPerf.mark('tournament.refresh.start');
    tournamentSync = TournamentSyncState.syncing;
    tournamentNoticeCode = null;
    errorCode = null;
    notifyListeners();
    final sessionOk = await _restoreSession(degradedOnFailure: true);
    if (epoch != _tournamentEpoch) return;
    if (!sessionOk || api.sessionSecret == null) {
      if (epoch == _tournamentEpoch &&
          tournamentSync == TournamentSyncState.syncing) {
        tournamentSync = TournamentSyncState.degraded;
        notifyListeners();
      }
      return;
    }
    await loadDay(presentHome: true, epoch: epoch);
  }

  /// Compatibility entry used by older tests: local ready then ranked refresh.
  Future<void> start() async {
    await beginLocal();
    await refreshTournament(origin: TournamentRefreshOrigin.startup);
  }

  /// Reads today's series. Opening Home after this does not claim again.
  Future<void> loadDay({required bool presentHome, int? epoch}) async {
    final activeEpoch = epoch ?? _tournamentEpoch;
    busy = true;
    notifyListeners();
    final claim = await api.post('/v1/tournament/claims/daily', {
      'originalUtcDate': _today(),
    });
    if (activeEpoch != _tournamentEpoch) return;
    if (!_accepted(claim, const {200, 201}, degradedOnFailure: true)) return;
    _claim = claim.map;
    seriesId = claim.map['seriesId']?.toString();
    final id = seriesId;
    if (id == null || id.isEmpty) {
      _fail('MALFORMED_REQUEST', degradedOnFailure: true);
      return;
    }
    final view = await api.get('/v1/tournament/series/$id/board');
    if (activeEpoch != _tournamentEpoch) return;
    if (!_accepted(view, const {200}, degradedOnFailure: true)) return;
    _applyBoard(view.map, reveal: false);
    if (day?.phase == DayPhase.completed) {
      await _loadResults();
    }
    if (activeEpoch != _tournamentEpoch) return;
    await _persistHomeSnapshot();
    homeSnapshotStale = false;
    busy = false;
    booting = false;
    errorCode = null;
    tournamentNoticeCode = null;
    tournamentSync = TournamentSyncState.ready;
    if (presentHome) route = const TournamentRoute();
    InteractionPerf.mark('tournament.refresh.ready');
    notifyListeners();
  }

  Future<void> showHome() async {
    noticeCode = null;
    errorCode = null;
    route = const TournamentRoute();
    notifyListeners();
    if (!tournamentReady && tournamentSync != TournamentSyncState.syncing) {
      await refreshTournament(origin: TournamentRefreshOrigin.background);
    }
  }

  /// Returns the shell to Home without starting a network refresh.
  /// Used when a pushed Leaderboard route is popped.
  void returnToHomeShell() {
    noticeCode = null;
    errorCode = null;
    if (route.place == TournamentPlace.home) return;
    route = const TournamentRoute();
    notifyListeners();
  }

  void showOverview() {
    route = const TournamentRoute(place: TournamentPlace.overview);
    notifyListeners();
  }

  Future<void> resume() => _reload(reveal: true, followGameplay: false);

  Future<void> openResults() async {
    await _loadResults();
    route = const TournamentRoute(place: TournamentPlace.results);
    errorCode = null;
    notifyListeners();
  }

  void setSound(bool value) {
    settings.sound = value;
    settings.save();
    sfx.muted = !value;
    notifyListeners();
  }

  void setHaptics(bool value) {
    settings.haptics = value;
    settings.save();
    notifyListeners();
  }

  void noteSelection() {
    sfx.play(GameSfxEvent.place);
    _haptic((feel) => feel.selection());
  }

  void _haptic(void Function(TournamentHaptics feel) call) {
    if (settings.haptics) call(haptics);
  }

  Future<void> openDaily() => _openLeaderboard(weekly: false);

  /// [fromHome] selects WEEKLY / ALL and the server's current week, which is
  /// the first week in the canonical visible-week list.
  Future<void> openWeekly({String? week, bool fromHome = false}) =>
      _openLeaderboard(weekly: true, week: week, fromHome: fromHome);

  Future<void> setCategory(String next) async {
    category = next;
    await _openLeaderboard(
      weekly: route.place == TournamentPlace.weekly,
      preserveReturn: true,
    );
  }

  Future<void> back() async {
    final next = route.back();
    if (next.place == TournamentPlace.home && day == null) {
      await showHome();
      return;
    }
    route = next;
    notifyListeners();
  }

  Future<void> recover() async {
    if (hasPendingCommand) {
      await retryUnknown();
      return;
    }
    errorCode = null;
    tournamentNoticeCode = null;
    route = const TournamentRoute();
    notifyListeners();
    await refreshTournament(origin: TournamentRefreshOrigin.background);
  }

  Future<void> advance() async {
    if (moveInFlight || hasPendingCommand) return;
    final id = seriesId;
    final ordinal = day?.ordinal;
    if (id == null || ordinal == null) return;
    final key = _pendingKey ?? 'advance-$id-$ordinal';
    final body = {'commandType': 'advance', 'idempotencyKey': key};
    await _sendCommand(body, key: key, fromPlay: false);
  }

  Future<void> retryUnknown() async {
    final pending = _pending;
    if (pending is! Map || moveInFlight) return;
    await _sendCommand(
      pending,
      key: _pendingKey ?? '',
      fromPlay: route.place == TournamentPlace.playing,
    );
  }

  Future<void> _submitTap(int offerIndex, Coordinate tap) async {
    if (moveInFlight ||
        hasPendingCommand ||
        session.authoritativeOutcomeUnknown) {
      return;
    }
    if (route.place != TournamentPlace.playing) return;
    final id = seriesId;
    if (id == null) return;
    final revision = board['boardRevision'];
    final writer = board['writerGeneration'];
    final key =
        _pendingKey ??
        'tap-$id-${board['ordinal']}-$revision-$offerIndex-${tap.row}-${tap.column}';
    final body = {
      'commandType': 'move',
      'idempotencyKey': key,
      'move': {
        'offerIndex': offerIndex,
        'tap': [tap.row, tap.column],
        'expectedBoardRevision': revision,
        'writerGeneration': writer,
      },
    };
    await _sendCommand(body, key: key, fromPlay: true);
  }

  Future<void> _sendCommand(
    Object body, {
    required String key,
    required bool fromPlay,
  }) async {
    final id = seriesId;
    if (id == null) return;
    final before = day?.seriesScore;
    moveInFlight = true;
    scoreDelta = null;
    noticeCode = null;
    notifyListeners();
    try {
      final response = await api.post(
        '/v1/tournament/series/$id/commands',
        body,
      );
      if (response.status == 0) {
        _pending = body;
        _pendingKey = key;
        noticeCode = 'outcome_unknown';
        if (fromPlay) session.markAuthoritativeUnknown();
        return;
      }
      _pending = null;
      _pendingKey = null;
      session.clearAuthoritativeUnknown();
      if (response.status == 200) {
        final ok = await _reload(reveal: true, followGameplay: true);
        if (!ok) return;
        final delta = fromPlay && before != null && day?.seriesScore != null
            ? day!.seriesScore! - before
            : 0;
        scoreDelta = delta > 0 && route.place == TournamentPlace.playing
            ? delta
            : null;
        if (route.place == TournamentPlace.results) {
          sfx.play(GameSfxEvent.chainComplete);
          _haptic((feel) => feel.completed());
        } else if (route.place == TournamentPlace.transition) {
          if (delta > 0) {
            sfx.play(GameSfxEvent.clear);
            _haptic((feel) => feel.cleared());
          }
          sfx.play(GameSfxEvent.roundEnd);
          _haptic((feel) => feel.completed());
        } else if (fromPlay) {
          if (delta > 0) {
            sfx.play(GameSfxEvent.clear);
            _haptic((feel) => feel.cleared());
          } else {
            sfx.play(GameSfxEvent.place);
            _haptic((feel) => feel.accepted());
          }
        }
        return;
      }
      sfx.play(GameSfxEvent.reject);
      if (response.status == 401) {
        _fail('UNAUTHENTICATED', degradedOnFailure: localReady);
        _haptic((feel) => feel.rejected());
        return;
      }
      if (response.error == 'WRITER_NOT_AUTHORIZED') {
        // Soft, non-network notice: do not auto-retry or invent scores.
        _pending = null;
        _pendingKey = null;
        session.clearAuthoritativeUnknown();
        noticeCode = 'WRITER_NOT_AUTHORIZED';
        errorCode = null;
        if (route.place == TournamentPlace.playing) {
          session.showServerRejection('WRITER_NOT_AUTHORIZED');
        }
        _haptic((feel) => feel.rejected());
        return;
      }
      final ok = await _reload(reveal: true, followGameplay: false);
      noticeCode = response.error;
      if (ok && route.place == TournamentPlace.playing) {
        session.showServerRejection(response.error);
      }
      _haptic((feel) => feel.rejected());
    } finally {
      moveInFlight = false;
      notifyListeners();
    }
  }

  Future<bool> _reload({
    required bool reveal,
    required bool followGameplay,
  }) async {
    final id = seriesId;
    if (id == null) return false;
    final view = await api.get('/v1/tournament/series/$id/board');
    if (!_accepted(view, const {200}, degradedOnFailure: localReady)) {
      return false;
    }
    _applyBoard(view.map, reveal: reveal);
    final phase = day?.phase ?? DayPhase.unknown;
    if (phase == DayPhase.completed) {
      if (followGameplay) {
        await _loadResults();
        route = const TournamentRoute(place: TournamentPlace.results);
      } else {
        route = const TournamentRoute();
      }
    } else if (day?.awaitAdvance == true) {
      scoreDelta = null;
      route = const TournamentRoute(place: TournamentPlace.transition);
    } else if (reveal) {
      route = const TournamentRoute(place: TournamentPlace.playing);
    }
    errorCode = null;
    notifyListeners();
    return true;
  }

  Future<void> _openLeaderboard({
    required bool weekly,
    String? week,
    bool preserveReturn = false,
    bool fromHome = false,
  }) async {
    if (fromHome) category = 'ALL';
    final opened = preserveReturn
        ? TournamentRoute(
            place: weekly ? TournamentPlace.weekly : TournamentPlace.daily,
            leaderboardReturn: route.leaderboardReturn ?? TournamentPlace.home,
          )
        : route.open(weekly ? TournamentPlace.weekly : TournamentPlace.daily);
    // Commit tab/place before any await so the first painted frame matches
    // the requested board (Home → Weekly must not flash Daily).
    final switching = route.place != opened.place;
    route = opened;
    if (switching || fromHome) {
      leaderboard = const {};
      nextCursor = null;
      weeklyFinal = false;
    }
    busy = true;
    errorCode = null;
    notifyListeners();

    if (weekly && weeks.isEmpty) {
      final listed = await api.get('/v1/tournament/leaderboards/weeks');
      if (!_accepted(listed, const {200}, degradedOnFailure: true)) {
        busy = false;
        notifyListeners();
        return;
      }
      weeks = [
        for (final item in (listed.map['weeks'] as List? ?? const []))
          item.toString(),
      ];
      weekStart ??= weeks.isEmpty ? null : weeks.first;
    }
    if (weekly && fromHome && weeks.isNotEmpty) weekStart = weeks.first;
    final selectedWeek = week ?? weekStart;
    if (weekly) weekStart = selectedWeek;
    if (weekly && (selectedWeek == null || selectedWeek.isEmpty)) {
      leaderboard = const {'rows': []};
      weeklyFinal = false;
      busy = false;
      notifyListeners();
      return;
    }
    final path = _leaderboardPath(weekly: weekly, week: selectedWeek);
    final response = await api.get(path);
    if (!_accepted(response, const {200}, degradedOnFailure: true)) {
      busy = false;
      notifyListeners();
      return;
    }
    leaderboard = response.map;
    nextCursor = _cursor(response.map['nextCursor']);
    weeklyFinal = response.map['state'] == 'FINAL';
    tournamentNoticeCode = null;
    busy = false;
    notifyListeners();
  }

  /// Appends the next server page. It does not invent rows.
  Future<void> loadMoreLeaderboard() async {
    final cursor = nextCursor;
    if (cursor == null || busy) return;
    final weekly = route.place == TournamentPlace.weekly;
    busy = true;
    notifyListeners();
    final response = await api.get(
      _leaderboardPath(weekly: weekly, week: weekStart, cursor: cursor),
    );
    if (!_accepted(response, const {200}, degradedOnFailure: true)) return;
    final existing = leaderboard['rows'];
    final more = response.map['rows'];
    leaderboard = {
      ...response.map,
      'rows': [if (existing is List) ...existing, if (more is List) ...more],
    };
    nextCursor = _cursor(response.map['nextCursor']);
    weeklyFinal = response.map['state'] == 'FINAL';
    busy = false;
    notifyListeners();
  }

  String _leaderboardPath({
    required bool weekly,
    String? week,
    String? cursor,
  }) {
    final base = weekly
        ? '/v1/tournament/leaderboards/weekly?weekStart=$week&category=$category&pageSize=50'
        : '/v1/tournament/leaderboards/daily?date=${_today()}&category=$category&pageSize=50';
    if (cursor == null || cursor.isEmpty) return base;
    return '$base&cursor=${Uri.encodeQueryComponent(cursor)}';
  }

  String? _cursor(Object? value) {
    final text = value?.toString();
    if (text == null || text.isEmpty || text == 'null') return null;
    return text;
  }

  Future<void> _loadResults() async {
    final id = seriesId;
    if (id == null) return;
    final response = await api.get('/v1/tournament/series/$id/results');
    if (response.status == 200) {
      results = response.map;
      resultsError = null;
    } else {
      results = const {};
      resultsError = response.status == 0 ? response.error : response.error;
    }
  }

  void _applyBoard(Map<String, Object?> view, {required bool reveal}) {
    board = view;
    deadlineMs = tournamentInt(view['idleDeadlineAtMs']);
    serverNowMs = tournamentInt(view['serverNowMs']);
    syncedAt = DateTime.now();
    final claim = _claim;
    if (claim != null) day = dayFromPayload(claim: claim, board: view);
    if (!reveal) return;
    final state = view['state'];
    if (state is! Map) {
      noticeCode = 'BOARD_UNREADABLE';
      return;
    }
    try {
      session.showAuthoritative(parseGameState(state));
    } catch (_) {
      noticeCode = 'BOARD_UNREADABLE';
    }
  }

  bool _accepted(
    UatHttpResult response,
    Set<int> ok, {
    bool degradedOnFailure = false,
  }) {
    if (ok.contains(response.status)) return true;
    if (response.status == 0) {
      _fail(
        response.isTimeout ? 'TIMEOUT' : 'OFFLINE',
        degradedOnFailure: degradedOnFailure,
      );
      return false;
    }
    if (response.status == 401) {
      _fail('UNAUTHENTICATED', degradedOnFailure: degradedOnFailure);
      return false;
    }
    _fail(response.error, degradedOnFailure: degradedOnFailure);
    return false;
  }

  void _fail(String code, {bool degradedOnFailure = false}) {
    busy = false;
    booting = false;
    moveInFlight = false;
    final soft = degradedOnFailure && localReady;
    if (soft) {
      errorCode = null;
      tournamentNoticeCode = code;
      tournamentSync = TournamentSyncState.degraded;
      if (route.place == TournamentPlace.recovery) {
        route = const TournamentRoute();
      }
      notifyListeners();
      return;
    }
    errorCode = code;
    tournamentNoticeCode = code;
    tournamentSync = TournamentSyncState.degraded;
    route = const TournamentRoute(place: TournamentPlace.recovery);
    notifyListeners();
  }

  /// Returns true only when a usable session secret is ready for ranked calls.
  Future<bool> _restoreSession({bool degradedOnFailure = false}) async {
    final binding = UatApi.authBinding(config.bearer);
    final origin = UatApi.apiOrigin(config.baseUrl);
    InteractionPerf.mark('tournament.session.restore.start');
    if (InteractionPerf.enabled) {
      // Origin only — never bearer, secret, or Authorization.
      debugPrint('PZD_PERF tournament.api.origin=$origin');
    }

    final saved = _readBoundSession(binding: binding, origin: origin);
    if (saved != null) {
      api.sessionSecret = saved;
      final current = await api.get('/v1/tournament/session');
      if (current.status == 200) {
        InteractionPerf.mark('tournament.session.restore.hit');
        await _bindPlayerId(current.map['playerId']?.toString());
        await _hydrateHomeSnapshot();
        return true;
      }
      if (current.status == 0) {
        // Bound session + network failure: keep practice scope, do not POST.
        api.sessionSecret = saved;
        _fail(
          current.isTimeout ? 'TIMEOUT' : 'OFFLINE',
          degradedOnFailure: degradedOnFailure,
        );
        return false;
      }
      // Expired / rejected: drop secret and open a fresh session with bearer.
      api.sessionSecret = null;
      if (current.status == 401) {
        await identity.clearAuthenticatedPlayer();
        await _hydrateHomeSnapshot();
      }
      InteractionPerf.mark('tournament.session.restore.rejected');
    } else {
      api.sessionSecret = null;
      InteractionPerf.mark('tournament.session.restore.unbound');
    }

    final opened = await api.post('/v1/tournament/session');
    if (opened.status != 201) {
      if (opened.status == 401) {
        await identity.clearAuthenticatedPlayer();
        await _hydrateHomeSnapshot();
        _fail('UNAUTHENTICATED', degradedOnFailure: degradedOnFailure);
        return false;
      }
      // Offline / timeout: never clear a previously verified practice binding.
      _fail(
        opened.isTimeout ? 'TIMEOUT' : 'OFFLINE',
        degradedOnFailure: degradedOnFailure,
      );
      return false;
    }
    api.sessionSecret = opened.map['sessionSecret']?.toString();
    await _bindPlayerId(opened.map['playerId']?.toString());
    await _hydrateHomeSnapshot();
    _persistBoundSession(
      secret: api.sessionSecret,
      binding: binding,
      origin: origin,
    );
    InteractionPerf.mark('tournament.session.restore.opened');
    return api.sessionSecret != null && api.sessionSecret!.isNotEmpty;
  }

  /// Returns a secret only when the vault proves same auth + API origin.
  ///
  /// Secrets are keyed by [authBinding] so Player A → B → A on one device
  /// restores each player's writer session instead of POSTing a new device
  /// binding that would hit WRITER_NOT_AUTHORIZED on an existing claim.
  String? _readBoundSession({
    required String binding,
    required String origin,
  }) {
    final vault = _loadSessionVault();
    final entry = vault[binding];
    if (entry == null) return null;
    if (entry.origin != origin) return null;
    if (entry.secret.isEmpty) return null;
    return entry.secret;
  }

  void _persistBoundSession({
    required String? secret,
    required String binding,
    required String origin,
  }) {
    if (secret == null || secret.isEmpty) return;
    final vault = _loadSessionVault();
    vault[binding] = (secret: secret, origin: origin);
    _writeSessionVault(vault);
  }

  Map<String, ({String secret, String origin})> _loadSessionVault() {
    final out = <String, ({String secret, String origin})>{};
    if (!_stateFile.existsSync()) return out;
    try {
      final saved = jsonDecode(_stateFile.readAsStringSync());
      if (saved is! Map) return out;
      final sessions = saved['sessions'];
      if (sessions is Map) {
        for (final entry in sessions.entries) {
          final key = entry.key.toString();
          final value = entry.value;
          if (value is! Map) continue;
          final secret = value['secret']?.toString();
          final origin = value['apiOrigin']?.toString();
          if (secret == null ||
              secret.isEmpty ||
              origin == null ||
              origin.isEmpty) {
            continue;
          }
          out[key] = (secret: secret, origin: origin);
        }
      }
      // Migrate legacy single-binding files without wiping other identities.
      final legacySecret = saved['secret']?.toString();
      final legacyBinding = saved['authBinding']?.toString();
      final legacyOrigin = saved['apiOrigin']?.toString();
      if (legacySecret != null &&
          legacySecret.isNotEmpty &&
          legacyBinding != null &&
          legacyBinding.isNotEmpty &&
          legacyOrigin != null &&
          legacyOrigin.isNotEmpty &&
          !out.containsKey(legacyBinding)) {
        out[legacyBinding] = (secret: legacySecret, origin: legacyOrigin);
      }
    } catch (_) {
      return out;
    }
    return out;
  }

  void _writeSessionVault(Map<String, ({String secret, String origin})> vault) {
    _stateFile.parent.createSync(recursive: true);
    final sessions = <String, Object?>{
      for (final entry in vault.entries)
        entry.key: {
          'secret': entry.value.secret,
          'apiOrigin': entry.value.origin,
        },
    };
    final tmp = File('${_stateFile.path}.tmp');
    tmp.writeAsStringSync(
      jsonEncode({
        'version': 2,
        'sessions': sessions,
      }),
      flush: true,
    );
    // Preserve the last valid vault until its replacement is durable.
    tmp.renameSync(_stateFile.path);
  }

  Future<void> _hydrateHomeSnapshot() async {
    final snap = await _homeSnapshots.load(identity.activeScope);
    homeSnapshot = snap;
    if (snap == null) {
      homeSnapshotStale = false;
      return;
    }
    // Never apply another identity's cache.
    if (snap.scopeKey != identity.activeScope.storageKey) {
      homeSnapshot = null;
      homeSnapshotStale = false;
      return;
    }
    if (day == null) {
      day = snap.toDay();
      seriesId = snap.seriesId;
      if (snap.verifiedAll != null || snap.onTimeAwarded != null) {
        results = {
          if (snap.verifiedAll != null) 'all': snap.verifiedAll,
          if (snap.onTimeAwarded != null) 'onTimeAwarded': snap.onTimeAwarded,
        };
      }
      // Cached summaries are never live clocks.
      deadlineMs = null;
      serverNowMs = null;
      homeSnapshotStale = true;
    }
  }

  Future<void> _persistHomeSnapshot() async {
    final current = day;
    if (current == null) return;
    final snap = TournamentHomeSnapshot.fromLive(
      scope: identity.activeScope,
      day: current,
      originalUtcDate: _today(),
      capturedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      results: results,
    );
    if (snap == null) return;
    final previous = homeSnapshot;
    if (previous != null &&
        previous.scopeKey == snap.scopeKey &&
        previous.capturedAtMs > snap.capturedAtMs) {
      return;
    }
    homeSnapshot = snap;
    await _homeSnapshots.save(snap);
  }

  Future<void> _bindPlayerId(String? playerId) async {
    if (playerId == null || playerId.isEmpty) {
      // Session without a verified internal id cannot isolate authenticated
      // practice. Stay on the local guest scope rather than inventing one.
      await identity.clearAuthenticatedPlayer();
      return;
    }
    final bound = await identity.bindAuthenticatedPlayer(playerId);
    if (!bound) {
      await identity.clearAuthenticatedPlayer();
    }
  }

  /// Clears authenticated practice binding after logout / identity switch.
  Future<void> clearAuthenticatedPracticeScope() =>
      identity.clearAuthenticatedPlayer();

  String _today() => DateTime.now().toUtc().toIso8601String().substring(0, 10);
}
