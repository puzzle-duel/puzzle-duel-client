import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/application/game_session.dart';
import 'package:puzzle_duel_mobile/presentation/audio/game_sfx.dart';
import 'package:puzzle_duel_mobile/tournament/local_settings.dart';
import 'package:puzzle_duel_mobile/tournament/practice_identity.dart';
import 'package:puzzle_duel_mobile/tournament/practice_store.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_nav.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

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
  }) : api = api ?? UatApi(baseUrl: config.baseUrl, bearer: config.bearer),
       haptics = haptics ?? DeviceTournamentHaptics(),
       sfx = sfx ?? _QuietSfx(),
       settings = settings ?? LocalSettings.load(stateDirectory),
       _stateFile = File('${stateDirectory.path}/pzd-uat-session.json');

  final UatConfig config;
  final Directory stateDirectory;
  final PracticeIdentityStore identity;
  final UatApi api;
  final TournamentHaptics haptics;
  final GameSfx sfx;
  final LocalSettings settings;
  final File _stateFile;
  final GameSession session = GameSession();

  /// Practice persistence for the active guest or verified player scope.
  PracticeStore practiceStore() => PracticeStore(
    directory: stateDirectory,
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
  bool booting = true;
  bool busy = false;
  bool moveInFlight = false;
  String? noticeCode;
  String? errorCode;
  String? resultsError;
  int? scoreDelta;
  int? deadlineMs;
  int? serverNowMs;
  DateTime? syncedAt;

  Map<String, Object?>? _claim;
  Object? _pending;
  String? _pendingKey;

  bool get hasPendingCommand => _pending != null;

  /// The exact command waiting for reconciliation. Retries send this object.
  Object? get pendingCommand => _pending;

  Future<void> start() async {
    sfx.muted = !settings.sound;
    session.onAuthoritativeTap = _submitTap;
    await _restoreSession();
    if (errorCode != null) return;
    await loadDay(presentHome: true);
  }

  /// Reads today's series. Opening Home after this does not claim again.
  Future<void> loadDay({required bool presentHome}) async {
    busy = true;
    notifyListeners();
    final claim = await api.post('/v1/tournament/claims/daily', {
      'originalUtcDate': _today(),
    });
    if (!_accepted(claim, const {200, 201})) return;
    _claim = claim.map;
    seriesId = claim.map['seriesId']?.toString();
    final id = seriesId;
    if (id == null || id.isEmpty) {
      _fail('MALFORMED_REQUEST');
      return;
    }
    final view = await api.get('/v1/tournament/series/$id/board');
    if (!_accepted(view, const {200})) return;
    _applyBoard(view.map, reveal: false);
    if (day?.phase == DayPhase.completed) {
      await _loadResults();
    }
    busy = false;
    booting = false;
    errorCode = null;
    if (presentHome) route = const TournamentRoute();
    notifyListeners();
  }

  Future<void> showHome() async {
    noticeCode = null;
    if (day == null) {
      await loadDay(presentHome: true);
      return;
    }
    errorCode = null;
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
    if (api.sessionSecret == null) {
      booting = true;
      notifyListeners();
      await start();
      return;
    }
    await showHome();
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
      if (response.error == 'WRITER_NOT_AUTHORIZED' || response.status == 401) {
        _fail(response.status == 401 ? 'UNAUTHENTICATED' : response.error);
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
    if (!_accepted(view, const {200})) return false;
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
    if (weekly && weeks.isEmpty) {
      final listed = await api.get('/v1/tournament/leaderboards/weeks');
      if (!_accepted(listed, const {200})) return;
      weeks = [
        for (final item in (listed.map['weeks'] as List<Object?>? ?? const []))
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
      route = opened;
      errorCode = null;
      notifyListeners();
      return;
    }
    final path = _leaderboardPath(weekly: weekly, week: selectedWeek);
    final response = await api.get(path);
    if (!_accepted(response, const {200})) return;
    leaderboard = response.map;
    nextCursor = _cursor(response.map['nextCursor']);
    weeklyFinal = response.map['state'] == 'FINAL';
    route = opened;
    errorCode = null;
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
    if (!_accepted(response, const {200})) return;
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

  bool _accepted(UatHttpResult response, Set<int> ok) {
    if (ok.contains(response.status)) return true;
    if (response.status == 0) {
      _fail(response.error == 'TIMEOUT' ? 'TIMEOUT' : 'OFFLINE');
      return false;
    }
    if (response.status == 401) {
      _fail('UNAUTHENTICATED');
      return false;
    }
    _fail(response.error);
    return false;
  }

  void _fail(String code) {
    errorCode = code;
    busy = false;
    booting = false;
    moveInFlight = false;
    route = const TournamentRoute(place: TournamentPlace.recovery);
    notifyListeners();
  }

  Future<void> _restoreSession() async {
    if (_stateFile.existsSync()) {
      try {
        final saved = jsonDecode(_stateFile.readAsStringSync());
        if (saved is Map && saved['secret'] is String) {
          api.sessionSecret = saved['secret'] as String;
          final current = await api.get('/v1/tournament/session');
          if (current.status == 200) {
            await _bindPlayerId(current.map['playerId']?.toString());
            return;
          }
        }
      } catch (_) {
        // Fall through and open a fresh session.
      }
    }
    final opened = await api.post('/v1/tournament/session');
    if (opened.status != 201) {
      await identity.clearAuthenticatedPlayer();
      _fail(opened.status == 401 ? 'UNAUTHENTICATED' : opened.error);
      return;
    }
    api.sessionSecret = opened.map['sessionSecret']?.toString();
    await _bindPlayerId(opened.map['playerId']?.toString());
    _stateFile.parent.createSync(recursive: true);
    final tmp = File('${_stateFile.path}.tmp');
    tmp.writeAsStringSync(
      jsonEncode({'secret': api.sessionSecret}),
      flush: true,
    );
    // Preserve the last valid session until its replacement is durable.
    tmp.renameSync(_stateFile.path);
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
