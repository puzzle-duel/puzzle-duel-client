import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/application/game_session.dart';
import 'package:puzzle_duel_mobile/presentation/audio/game_sfx.dart';
import 'package:puzzle_duel_mobile/presentation/audio/game_sfx_scope.dart';
import 'package:puzzle_duel_mobile/presentation/game/board/accessible_board.dart';
import 'package:puzzle_duel_mobile/presentation/game/offer_tray.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/arcade_backdrop.dart';
import 'package:puzzle_duel_mobile/theme/app_theme.dart';
import 'package:puzzle_duel_mobile/theme/game_tokens.dart';
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

enum UatScreen { loading, home, playing, transition, results, daily, weekly, error }

final class TournamentController extends ChangeNotifier {
  TournamentController({required this.config, UatApi? api, Directory? stateDirectory})
    : api = api ?? UatApi(baseUrl: config.baseUrl, bearer: config.bearer),
      _stateFile = File(
        '${(stateDirectory ?? Directory.systemTemp).path}/pzd-uat-${config.playerLabel}.json',
      );

  final UatConfig config;
  final UatApi api;
  final File _stateFile;
  final GameSession session = GameSession();

  UatScreen screen = UatScreen.loading;
  String message = '';
  String? seriesId;
  Map<String, Object?> board = const {};
  Map<String, Object?> results = const {};
  Map<String, Object?> leaderboard = const {};
  String category = 'ALL';
  String? weekStart;
  List<String> weeks = const [];
  bool weeklyFinal = false;
  Object? _pendingCommand;
  String? _pendingKey;

  Future<void> start() async {
    session.onAuthoritativeTap = _submitTap;
    await _restoreSession();
    if (screen == UatScreen.error) return;
    await refreshHome();
  }

  Future<void> refreshHome() async {
    _set(UatScreen.loading, '');
    final today = _today();
    final claim = await api.post('/v1/tournament/claims/daily', {
      'originalUtcDate': today,
    });
    if (claim.status == 0) {
      _set(UatScreen.error, claim.error == 'TIMEOUT' ? 'The server timed out.' : 'Offline. The move was not sent.');
      return;
    }
    if (claim.status == 401) {
      _set(UatScreen.error, 'Unauthorized. Issue a new UAT bearer and relaunch.');
      return;
    }
    if (claim.status != 200 && claim.status != 201) {
      _set(UatScreen.error, claim.error);
      return;
    }
    seriesId = claim.map['seriesId']?.toString();
    final status = claim.map['status']?.toString();
    if (status == 'COMPLETED' || claim.map['original'] == false && status == 'COMPLETED') {
      await openResults();
      return;
    }
    _set(UatScreen.home, claim.map['original'] == false ? 'Today is already claimed. Continue the same series.' : '');
  }

  Future<void> continuePlay() async {
    final id = seriesId;
    if (id == null) return;
    final view = await api.get('/v1/tournament/series/$id/board');
    if (!_ok(view)) return;
    board = view.map;
    _showBoard(view.map);
    if (view.map['resultsPublished'] == true) {
      await openResults();
      return;
    }
    if (view.map['awaitAdvance'] == true) {
      _set(UatScreen.transition, '${view.map['ordinalLabel']} is complete.');
      return;
    }
    _set(UatScreen.playing, '');
  }

  Future<void> advance() async {
    final id = seriesId;
    if (id == null) return;
    final ordinal = board['ordinal'];
    final key = 'advance-$id-$ordinal';
    final response = await api.post('/v1/tournament/series/$id/commands', {
      'commandType': 'advance',
      'idempotencyKey': key,
    });
    if (response.status == 0) {
      _pendingKey = key;
      _pendingCommand = {
        'commandType': 'advance',
        'idempotencyKey': key,
      };
      _set(UatScreen.error, 'Advance outcome is unknown. Retry the same command. Do not start another game.');
      return;
    }
    _pendingCommand = null;
    await continuePlay();
  }

  Future<void> retryUnknown() async {
    final pending = _pendingCommand;
    final id = seriesId;
    if (pending is! Map || id == null) return;
    final response = await api.post('/v1/tournament/series/$id/commands', pending);
    if (response.status == 0) {
      _set(UatScreen.error, 'Still unknown. Retry the same command only.');
      return;
    }
    _pendingCommand = null;
    session.clearAuthoritativeUnknown();
    await continuePlay();
  }

  Future<void> openResults() async {
    final id = seriesId;
    if (id == null) return;
    final response = await api.get('/v1/tournament/series/$id/results');
    if (!_ok(response)) return;
    results = response.map;
    _set(UatScreen.results, '');
  }

  Future<void> openDaily() => _openBoard(weekly: false);

  Future<void> openWeekly([String? week]) => _openBoard(weekly: true, week: week);

  Future<void> _openBoard({required bool weekly, String? week}) async {
    if (weekly && weeks.isEmpty) {
      final listed = await api.get('/v1/tournament/leaderboards/weeks');
      if (!_ok(listed)) return;
      weeks = [
        for (final item in (listed.map['weeks'] as List<Object?>? ?? const []))
          item.toString(),
      ];
      weekStart = weeks.isEmpty ? null : weeks.first;
    }
    final selectedWeek = week ?? weekStart;
    if (weekly) weekStart = selectedWeek;
    final today = _today();
    final path = weekly
        ? '/v1/tournament/leaderboards/weekly?weekStart=$selectedWeek&category=$category&pageSize=50'
        : '/v1/tournament/leaderboards/daily?date=$today&category=$category&pageSize=50';
    final response = await api.get(path);
    if (!_ok(response)) return;
    leaderboard = response.map;
    weeklyFinal = response.map['state'] == 'FINAL';
    _set(weekly ? UatScreen.weekly : UatScreen.daily, '');
  }

  Future<void> setCategory(String next) async {
    category = next;
    if (screen == UatScreen.weekly) {
      await openWeekly(weekStart);
    } else {
      await openDaily();
    }
  }

  Future<void> _submitTap(int offerIndex, Coordinate tap) async {
    if (_pendingCommand != null) return;
    final id = seriesId;
    if (id == null) return;
    final revision = board['boardRevision'];
    final writer = board['writerGeneration'];
    final key = _pendingKey ?? 'tap-$id-${board['ordinal']}-$revision-$offerIndex-${tap.row}-${tap.column}';
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
    final response = await api.post('/v1/tournament/series/$id/commands', body);
    if (response.status == 0) {
      _pendingCommand = body;
      _pendingKey = key;
      session.markAuthoritativeUnknown();
      _set(UatScreen.playing, 'Command outcome is unknown. Retry only this move.');
      return;
    }
    _pendingKey = null;
    _pendingCommand = null;
    session.clearAuthoritativeUnknown();
    if (response.status == 409 && response.error == 'WRITER_NOT_AUTHORIZED') {
      _set(UatScreen.error, 'This device is not the active writer. Continue on the device that claimed today.');
      return;
    }
    if (response.status != 200) {
      message = response.error;
      notifyListeners();
      await continuePlay();
      return;
    }
    await continuePlay();
    if (board['awaitAdvance'] == true) {
      _set(UatScreen.transition, '${board['ordinalLabel']} is complete.');
    } else if (board['resultsPublished'] == true) {
      await openResults();
    }
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
      _set(
        UatScreen.error,
        opened.status == 401
            ? 'Unauthorized. Issue a new UAT bearer and relaunch.'
            : opened.error,
      );
      return;
    }
    api.sessionSecret = opened.map['sessionSecret']?.toString();
    _stateFile.writeAsStringSync(jsonEncode({'secret': api.sessionSecret}));
  }

  void _showBoard(Map<String, Object?> view) {
    final state = view['state'];
    if (state == null) return;
    session.showAuthoritative(parseGameState(state));
  }

  bool _ok(UatHttpResult response) {
    if (response.status == 200) return true;
    if (response.status == 0) {
      _set(UatScreen.error, response.error == 'TIMEOUT' ? 'The server timed out.' : 'Offline.');
      return false;
    }
    if (response.status == 401) {
      _set(UatScreen.error, 'Unauthorized.');
      return false;
    }
    _set(UatScreen.error, response.error);
    return false;
  }

  void _set(UatScreen next, String text) {
    screen = next;
    message = text;
    notifyListeners();
  }

  String _today() => DateTime.now().toUtc().toIso8601String().substring(0, 10);
}

void runTournamentUatApp(UatConfig config, {UatApi? api}) {
  runApp(TournamentUatApp(config: config, api: api));
}

final class TournamentUatApp extends StatefulWidget {
  const TournamentUatApp({super.key, required this.config, this.api});

  final UatConfig config;
  final UatApi? api;

  @override
  State<TournamentUatApp> createState() => _TournamentUatAppState();
}

final class _TournamentUatAppState extends State<TournamentUatApp> {
  late final TournamentController _controller = TournamentController(
    config: widget.config,
    api: widget.api,
  );

  @override
  void initState() {
    super.initState();
    _controller.start();
  }

  @override
  void dispose() {
    _controller.session.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GameSfxScope(
      sfx: SilentGameSfx(),
      child: MaterialApp(
        title: 'Puzzle Duel Tournament',
        debugShowCheckedModeBanner: false,
        theme: PuzzleDuelTheme.dark(),
        home: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => _UatScaffold(controller: _controller),
        ),
      ),
    );
  }
}

final class SilentGameSfx extends GameSfx {
  @override
  bool muted = true;

  @override
  bool get isPrepared => true;

  @override
  Future<void> prepare() async {}

  @override
  void play(GameSfxEvent event) {}
}

final class _UatScaffold extends StatelessWidget {
  const _UatScaffold({required this.controller});

  final TournamentController controller;

  @override
  Widget build(BuildContext context) {
    final screen = controller.screen;
    if (screen == UatScreen.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return switch (screen) {
      UatScreen.playing => _PlayScreen(controller: controller),
      UatScreen.transition => _TransitionScreen(controller: controller),
      UatScreen.results => _ResultsScreen(controller: controller),
      UatScreen.daily || UatScreen.weekly => _LeaderboardScreen(controller: controller),
      UatScreen.error => _MessageScreen(
        title: 'Tournament',
        body: controller.message,
        action: controller._pendingCommand == null ? 'Try again' : 'Retry the same command',
        onAction: controller._pendingCommand == null ? controller.refreshHome : controller.retryUnknown,
      ),
      _ => _HomeScreen(controller: controller),
    };
  }
}

final class _HomeScreen extends StatelessWidget {
  const _HomeScreen({required this.controller});

  final TournamentController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ArcadeBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('TOURNAMENT', style: Theme.of(context).textTheme.headlineMedium, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(controller.config.playerLabel, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Text(
                  controller.message.isEmpty ? "Play today's six games. The server scores them." : controller.message,
                  textAlign: TextAlign.center,
                ),
                const Spacer(),
                FilledButton(onPressed: controller.continuePlay, child: const Text("Play today's challenge")),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: controller.openDaily, child: const Text('Daily leaderboard')),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: controller.openWeekly, child: const Text('Weekly leaderboard')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _PlayScreen extends StatelessWidget {
  const _PlayScreen({required this.controller});

  final TournamentController controller;

  @override
  Widget build(BuildContext context) {
    final board = controller.board;
    final deadline = board['idleDeadlineAtMs'];
    final now = board['serverNowMs'];
    final remaining = deadline is num && now is num ? Duration(milliseconds: (deadline - now).clamp(0, 1 << 31).toInt()) : null;
    return Scaffold(
      body: ArcadeBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    Text('${board['ordinalLabel'] ?? ''}  ${board['seriesScore'] ?? board['score'] ?? 0}'),
                    const Spacer(),
                    Text(remaining == null ? '' : '${remaining.inMinutes}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')}'),
                  ],
                ),
              ),
              if (controller.message.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(controller.message, style: const TextStyle(color: GameTokens.danger)),
                ),
              if (controller._pendingCommand != null)
                TextButton(onPressed: controller.retryUnknown, child: const Text('Retry the same move')),
              Expanded(
                child: ListenableBuilder(
                  listenable: controller.session,
                  builder: (context, _) => AccessibleBoard(
                    session: controller.session,
                    view: controller.session.view,
                  ),
                ),
              ),
              ListenableBuilder(
                listenable: controller.session,
                builder: (context, _) => OfferTray(
                  offers: controller.session.view.canonicalState?.offers ?? const [OfferEmpty(), OfferEmpty(), OfferEmpty()],
                  selectedIndex: controller.session.view.selectedOfferIndex,
                  enabled: controller.session.view.acceptsInput && controller._pendingCommand == null,
                  onSelect: controller.session.selectOffer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _TransitionScreen extends StatelessWidget {
  const _TransitionScreen({required this.controller});

  final TournamentController controller;

  @override
  Widget build(BuildContext context) {
    return _MessageScreen(
      title: 'Game complete',
      body: controller.message,
      action: 'Next game',
      onAction: controller.advance,
    );
  }
}

final class _ResultsScreen extends StatelessWidget {
  const _ResultsScreen({required this.controller});

  final TournamentController controller;

  @override
  Widget build(BuildContext context) {
    final results = controller.results;
    return Scaffold(
      body: ArcadeBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Verified results', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                Text('Easy ${results['easy']}'),
                Text('Medium ${results['medium']}'),
                Text('Hard ${results['hard']}'),
                Text('All ${results['all']}'),
                const SizedBox(height: 8),
                Text(results['onTimeAwarded'] == true ? 'On-Time badge awarded' : 'On-Time badge not awarded'),
                const Spacer(),
                FilledButton(onPressed: controller.openDaily, child: const Text('Daily leaderboard')),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: controller.openWeekly, child: const Text('Weekly leaderboard')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _LeaderboardScreen extends StatelessWidget {
  const _LeaderboardScreen({required this.controller});

  final TournamentController controller;

  @override
  Widget build(BuildContext context) {
    final rows = controller.leaderboard['rows'];
    final list = rows is List ? rows : const [];
    final self = controller.leaderboard['self'];
    return Scaffold(
      body: ArcadeBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  controller.screen == UatScreen.weekly
                      ? 'Weekly ${controller.weekStart ?? ''} ${controller.weeklyFinal ? 'FINAL' : 'PROVISIONAL'}'
                      : 'Daily ${controller.leaderboard['period'] ?? ''}',
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final category in ['EASY', 'MEDIUM', 'HARD', 'ALL'])
                    ChoiceChip(
                      label: Text(category),
                      selected: controller.category == category,
                      onSelected: (_) => controller.setCategory(category),
                    ),
                ],
              ),
              if (controller.screen == UatScreen.weekly)
                SizedBox(
                  height: 42,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final week in controller.weeks)
                        TextButton(
                          onPressed: () => controller.openWeekly(week),
                          child: Text(week),
                        ),
                    ],
                  ),
                ),
              if (self is Map)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('You  rank ${self['rank']}  score ${self['score']}'),
                ),
              Expanded(
                child: list.isEmpty
                    ? const Center(child: Text('No verified scores on this board yet.'))
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (context, index) {
                          final row = list[index];
                          if (row is! Map) return const SizedBox.shrink();
                          final mine = row['self'] == true;
                          return ListTile(
                            title: Text(mine ? 'You' : 'Player ${row['displayPosition']}'),
                            subtitle: Text('Rank ${row['rank']}'),
                            trailing: Text('${row['score']}'),
                          );
                        },
                      ),
              ),
              TextButton(onPressed: controller.refreshHome, child: const Text('Back')),
            ],
          ),
        ),
      ),
    );
  }
}

final class _MessageScreen extends StatelessWidget {
  const _MessageScreen({
    required this.title,
    required this.body,
    required this.action,
    required this.onAction,
  });

  final String title;
  final String body;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ArcadeBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                Text(body, textAlign: TextAlign.center),
                const Spacer(),
                FilledButton(onPressed: onAction, child: Text(action)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
