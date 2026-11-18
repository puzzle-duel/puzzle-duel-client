import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/application/game_session.dart';
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
}

final class DeviceTournamentHaptics implements TournamentHaptics {
  const DeviceTournamentHaptics();

  @override
  void selection() => HapticFeedback.selectionClick();

  @override
  void accepted() => HapticFeedback.lightImpact();

  @override
  void rejected() => HapticFeedback.mediumImpact();
}

final class SilentTournamentHaptics implements TournamentHaptics {
  const SilentTournamentHaptics();

  @override
  void selection() {}

  @override
  void accepted() {}

  @override
  void rejected() {}
}

final class TournamentController extends ChangeNotifier {
  TournamentController({
    required this.config,
    UatApi? api,
    Directory? stateDirectory,
    TournamentHaptics? haptics,
  }) : api = api ?? UatApi(baseUrl: config.baseUrl, bearer: config.bearer),
       haptics = haptics ?? const DeviceTournamentHaptics(),
       _stateFile = File(
         '${(stateDirectory ?? Directory.systemTemp).path}/pzd-uat-${config.playerLabel}.json',
       );

  final UatConfig config;
  final UatApi api;
  final TournamentHaptics haptics;
  final File _stateFile;
  final GameSession session = GameSession();

  TournamentRoute route = const TournamentRoute();
  TournamentDay? day;
  Map<String, Object?> board = const {};
  Map<String, Object?> results = const {};
  Map<String, Object?> leaderboard = const {};
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

  Future<void> openDaily() => _openLeaderboard(weekly: false);

  Future<void> openWeekly([String? week]) => _openLeaderboard(weekly: true, week: week);

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
    await _sendCommand(pending, key: _pendingKey ?? '', fromPlay: route.place == TournamentPlace.playing);
  }

  Future<void> _submitTap(int offerIndex, Coordinate tap) async {
    if (moveInFlight || hasPendingCommand || session.authoritativeOutcomeUnknown) return;
    if (route.place != TournamentPlace.playing) return;
    final id = seriesId;
    if (id == null) return;
    final revision = board['boardRevision'];
    final writer = board['writerGeneration'];
    final key = _pendingKey ??
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
      final response = await api.post('/v1/tournament/series/$id/commands', body);
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
        if (ok &&
            fromPlay &&
            route.place == TournamentPlace.playing &&
            before != null &&
            day?.seriesScore != null) {
          scoreDelta = day!.seriesScore! - before;
        }
        if (ok) haptics.accepted();
        return;
      }
      if (response.error == 'WRITER_NOT_AUTHORIZED' || response.status == 401) {
        _fail(response.status == 401 ? 'UNAUTHENTICATED' : response.error);
        haptics.rejected();
        return;
      }
      final ok = await _reload(reveal: true, followGameplay: false);
      noticeCode = response.error;
      if (ok && route.place == TournamentPlace.playing) {
        session.showServerRejection(response.error);
      }
      haptics.rejected();
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
  }) async {
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
    final path = weekly
        ? '/v1/tournament/leaderboards/weekly?weekStart=$selectedWeek&category=$category&pageSize=50'
        : '/v1/tournament/leaderboards/daily?date=${_today()}&category=$category&pageSize=50';
    final response = await api.get(path);
    if (!_accepted(response, const {200})) return;
    leaderboard = response.map;
    weeklyFinal = response.map['state'] == 'FINAL';
    route = opened;
    errorCode = null;
    notifyListeners();
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
      final saved = jsonDecode(_stateFile.readAsStringSync());
      if (saved is Map && saved['secret'] is String) {
        api.sessionSecret = saved['secret'] as String;
        final current = await api.get('/v1/tournament/session');
        if (current.status == 200) return;
      }
    }
    final opened = await api.post('/v1/tournament/session');
    if (opened.status != 201) {
      _fail(opened.status == 401 ? 'UNAUTHENTICATED' : opened.error);
      return;
    }
    api.sessionSecret = opened.map['sessionSecret']?.toString();
    _stateFile.writeAsStringSync(jsonEncode({'secret': api.sessionSecret}));
  }

  String _today() => DateTime.now().toUtc().toIso8601String().substring(0, 10);
}
