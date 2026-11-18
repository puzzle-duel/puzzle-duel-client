import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/presentation/audio/game_sfx.dart';
import 'package:puzzle_duel_mobile/presentation/audio/game_sfx_scope.dart';
import 'package:puzzle_duel_mobile/presentation/game/board/accessible_board.dart';
import 'package:puzzle_duel_mobile/presentation/game/offer_tray.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/arcade_backdrop.dart';
import 'package:puzzle_duel_mobile/theme/app_theme.dart';
import 'package:puzzle_duel_mobile/theme/game_tokens.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_controller.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_copy.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_nav.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

export 'tournament_controller.dart';

void runTournamentUatApp(UatConfig config, {UatApi? api}) {
  runApp(TournamentUatApp(config: config, api: api));
}

final class TournamentUatApp extends StatefulWidget {
  const TournamentUatApp({
    super.key,
    required this.config,
    this.api,
    this.stateDirectory,
    this.haptics,
    this.locale,
    this.textScaler,
  });

  final UatConfig config;
  final UatApi? api;
  final Directory? stateDirectory;
  final TournamentHaptics? haptics;
  final Locale? locale;
  final TextScaler? textScaler;

  @override
  State<TournamentUatApp> createState() => _TournamentUatAppState();
}

final class _TournamentUatAppState extends State<TournamentUatApp> {
  late final TournamentController _controller = TournamentController(
    config: widget.config,
    api: widget.api,
    stateDirectory: widget.stateDirectory,
    haptics: widget.haptics ?? const DeviceTournamentHaptics(),
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
        title: 'Puzzle Duel',
        debugShowCheckedModeBanner: false,
        theme: PuzzleDuelTheme.dark(),
        locale: const Locale('en'),
        supportedLocales: const [Locale('en')],
        localizationsDelegates: const [
          TournamentCopyDelegate(),
        ],
        builder: (context, child) {
          final requested = widget.locale ?? View.of(context).platformDispatcher.locale;
          final copyLocale = requested.languageCode == 'tr'
              ? const Locale('tr')
              : const Locale('en');
          final wrapped = TournamentLocale(
            locale: copyLocale,
            child: child ?? const SizedBox.shrink(),
          );
          final scaler = widget.textScaler;
          if (scaler == null) return wrapped;
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: scaler),
            child: wrapped,
          );
        },
        home: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => _TournamentShell(controller: _controller),
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

final class _TournamentShell extends StatelessWidget {
  const _TournamentShell({required this.controller});

  final TournamentController controller;

  @override
  Widget build(BuildContext context) {
    final place = controller.route.place;
    final atHome = place == TournamentPlace.home;
    return PopScope(
      canPop: atHome && !controller.booting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (place == TournamentPlace.playing || place == TournamentPlace.transition) {
          _confirmLeave(context, controller);
          return;
        }
        controller.back();
      },
      child: _body(context, place),
    );
  }

  Widget _body(BuildContext context, TournamentPlace place) {
    if (controller.booting || (controller.busy && controller.day == null)) {
      return _Loading(label: TournamentCopy.of(context).loading);
    }
    return switch (place) {
      TournamentPlace.playing => _PlayScreen(controller: controller),
      TournamentPlace.transition => _TransitionScreen(controller: controller),
      TournamentPlace.results => _ResultsScreen(controller: controller),
      TournamentPlace.daily || TournamentPlace.weekly => _LeaderboardScreen(controller: controller),
      TournamentPlace.overview => _OverviewScreen(controller: controller),
      TournamentPlace.recovery => _RecoveryScreen(controller: controller),
      TournamentPlace.home => _HomeScreen(controller: controller),
    };
  }
}

Future<void> _confirmLeave(BuildContext context, TournamentController controller) async {
  final copy = TournamentCopy.of(context);
  final leave = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(copy.leaveTitle),
      content: Text(copy.leaveBody),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(copy.stay)),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(copy.leave)),
      ],
    ),
  );
  if (leave == true) await controller.showHome();
}

final class _Loading extends StatelessWidget {
  const _Loading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ArcadeBackdrop(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

final class _HomeScreen extends StatelessWidget {
  const _HomeScreen({required this.controller});

  final TournamentController controller;

  @override
  Widget build(BuildContext context) {
    final copy = TournamentCopy.of(context);
    final day = controller.day;
    final phase = day?.phase ?? DayPhase.ready;
    final verified = tournamentInt(controller.results['all']);
    final score = phase == DayPhase.completed ? verified ?? day?.seriesScore : day?.seriesScore;
    final scoreLabel = phase == DayPhase.completed && verified != null
        ? copy.verifiedScore
        : score == null
        ? copy.scoreUnavailable
        : copy.currentScore;
    final badge = phase == DayPhase.completed && controller.results.isNotEmpty
        ? (controller.results['onTimeAwarded'] == true ? copy.onTime : copy.onTimeMissing)
        : null;
    final primary = switch (phase) {
      DayPhase.completed => copy.viewResults,
      DayPhase.betweenGames => copy.continueNext,
      DayPhase.inProgress => copy.resume,
      _ => copy.playToday,
    };
    return Scaffold(
      body: ArcadeBackdrop(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            children: [
              Text(
                copy.appTitle.toUpperCase(),
                key: const Key('home-title'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  letterSpacing: 2.4,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(copy.tagline, textAlign: TextAlign.center, style: TextStyle(color: GameTokens.accent)),
              const SizedBox(height: 4),
              Text(controller.config.playerLabel, textAlign: TextAlign.center),
              const SizedBox(height: 22),
              _DailyCard(
                copy: copy,
                day: day,
                score: score,
                scoreLabel: scoreLabel,
                phase: phase,
                badge: badge,
              ),
              const SizedBox(height: 18),
              FilledButton(
                key: const Key('primary-action'),
                onPressed: phase == DayPhase.completed ? controller.openResults : controller.resume,
                child: Text(primary),
              ),
              const SizedBox(height: 10),
              OutlinedButton(onPressed: controller.showOverview, child: Text(copy.seeGames)),
              const SizedBox(height: 10),
              OutlinedButton(
                key: const Key('daily-leaderboard'),
                onPressed: controller.openDaily,
                child: Text(copy.dailyBoard),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                key: const Key('weekly-leaderboard'),
                onPressed: controller.openWeekly,
                child: Text(copy.weeklyBoard),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _DailyCard extends StatelessWidget {
  const _DailyCard({
    required this.copy,
    required this.day,
    required this.score,
    required this.scoreLabel,
    required this.phase,
    required this.badge,
  });

  final TournamentCopy copy;
  final TournamentDay? day;
  final int? score;
  final String scoreLabel;
  final DayPhase phase;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final label = day?.label ?? 'E1';
    final tone = _tone(label);
    final body = switch (phase) {
      DayPhase.completed => copy.completedBody,
      DayPhase.ready when day?.original == false => copy.alreadyClaimed,
      _ => copy.readyBody,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: GameTokens.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(GameTokens.radiusLg),
        border: Border.all(color: tone.withValues(alpha: 0.8), width: 1.4),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(copy.dailyChallenge, style: TextStyle(color: tone, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(label, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(body),
            const SizedBox(height: 14),
            _Pips(completed: day?.completedGames ?? 0, current: day?.ordinal),
            const SizedBox(height: 14),
            Text(scoreLabel, style: const TextStyle(color: GameTokens.textMuted)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                score == null ? '—' : '$score',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: GameTokens.scoreGlow,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (badge != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(badge!, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      ),
    );
  }

}

final class _OverviewScreen extends StatelessWidget {
  const _OverviewScreen({required this.controller});

  final TournamentController controller;

  @override
  Widget build(BuildContext context) {
    final copy = TournamentCopy.of(context);
    final current = controller.day?.ordinal;
    return _Page(
      title: copy.overviewTitle,
      onBack: controller.back,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(copy.overviewBody),
          const SizedBox(height: 16),
          for (final entry in tournamentOrdinalLabels.entries)
            _GameRow(
              label: entry.value,
              difficulty: copy.difficultyOf(entry.value),
              current: entry.key == current,
              done: (controller.day?.completedGames ?? 0) >= entry.key,
            ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('primary-action'),
            onPressed: controller.day?.phase == DayPhase.completed
                ? controller.openResults
                : controller.resume,
            child: Text(
              controller.day?.phase == DayPhase.completed ? copy.viewResults : copy.resume,
            ),
          ),
        ],
      ),
    );
  }
}

final class _GameRow extends StatelessWidget {
  const _GameRow({
    required this.label,
    required this.difficulty,
    required this.current,
    required this.done,
  });

  final String label;
  final String difficulty;
  final bool current;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final tone = _tone(label);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: current ? tone.withValues(alpha: 0.16) : GameTokens.surface,
          borderRadius: BorderRadius.circular(GameTokens.radiusMd),
          border: Border.all(color: current ? tone : GameTokens.border),
        ),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: tone.withValues(alpha: 0.2),
            child: Text(label, style: TextStyle(color: tone, fontWeight: FontWeight.w800)),
          ),
          title: Text(difficulty),
          trailing: Icon(
            done ? Icons.check_circle : Icons.circle_outlined,
            color: done ? GameTokens.success : GameTokens.textMuted,
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
    final copy = TournamentCopy.of(context);
    final day = controller.day;
    final view = controller.session.view;
    final size = view.canonicalState?.boardSize ?? day?.boardSize ?? 0;
    final moves = view.movesRemaining;
    final tone = _tone(day?.label);
    final notice = controller.noticeCode;
    return Scaffold(
      body: ArcadeBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
                child: Row(
                  children: [
                    IconButton(
                      key: const Key('nav-back'),
                      tooltip: copy.back,
                      onPressed: () => _confirmLeave(context, controller),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    Text(
                      day?.label ?? '',
                      style: TextStyle(color: tone, fontWeight: FontWeight.w800, fontSize: 18),
                    ),
                    const Spacer(),
                    Text(
                      '${day?.seriesScore ?? '—'}',
                      style: const TextStyle(
                        color: GameTokens.scoreGlow,
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(child: _Pips(completed: day?.completedGames ?? 0, current: day?.ordinal)),
                    const SizedBox(width: 8),
                    Text(copy.movesLeft(moves)),
                    const SizedBox(width: 8),
                    _IdleClock(
                      label: copy.idle,
                      deadlineMs: controller.deadlineMs,
                      serverNowMs: controller.serverNowMs,
                      syncedAt: controller.syncedAt,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(copy.objective(moves, size)),
              ),
              if (controller.moveInFlight)
                Text(copy.sending, style: const TextStyle(color: GameTokens.accent)),
              if (notice != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(copy.forError(notice), style: const TextStyle(color: GameTokens.danger)),
                ),
              if (controller.scoreDelta != null)
                Text(
                  '+${controller.scoreDelta}',
                  key: const Key('score-delta'),
                  style: const TextStyle(
                    color: GameTokens.success,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
              if (controller.hasPendingCommand)
                TextButton(onPressed: controller.retryUnknown, child: Text(copy.retrySame)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: ListenableBuilder(
                    listenable: controller.session,
                    builder: (context, _) => AccessibleBoard(
                      session: controller.session,
                      view: controller.session.view,
                      showPlacementPreview: true,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: ListenableBuilder(
                  listenable: controller.session,
                  builder: (context, _) {
                    final live = controller.session.view;
                    final locked = !live.acceptsInput ||
                        controller.hasPendingCommand ||
                        controller.moveInFlight ||
                        controller.session.authoritativeOutcomeUnknown;
                    return OfferTray(
                      offers: live.canonicalState?.offers ??
                          const [OfferEmpty(), OfferEmpty(), OfferEmpty()],
                      selectedIndex: live.selectedOfferIndex,
                      enabled: !locked,
                      selectionLabel: copy.selectPiece,
                      onSelect: (index) {
                        controller.session.selectOffer(index);
                        controller.haptics.selection();
                      },
                    );
                  },
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
    final copy = TournamentCopy.of(context);
    final day = controller.day;
    final next = nextOrdinalLabel(day?.ordinal);
    final tone = _tone(day?.label);
    return _Page(
      title: copy.finishedTitle,
      onBack: () => _confirmLeave(context, controller),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Text(
            day?.label ?? '',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(color: tone, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(copy.finishReason(day?.terminalReason)),
          const SizedBox(height: 18),
          _ScoreLine(label: copy.gameScore, value: day?.gameScore),
          _ScoreLine(label: copy.totalScore, value: day?.seriesScore),
          const SizedBox(height: 12),
          _Pips(completed: day?.completedGames ?? 0, current: day?.ordinal),
          if (next != null) ...[
            const SizedBox(height: 16),
            Text('${copy.nextGame}  $next  ${copy.difficultyOf(next)}'),
          ],
          if (controller.noticeCode != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(copy.forError(controller.noticeCode), style: const TextStyle(color: GameTokens.danger)),
            ),
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('continue-next'),
            onPressed: controller.hasPendingCommand ? controller.retryUnknown : controller.advance,
            child: Text(controller.hasPendingCommand ? copy.retrySame : copy.continueNext),
          ),
        ],
      ),
    );
  }
}

final class _ResultsScreen extends StatelessWidget {
  const _ResultsScreen({required this.controller});

  final TournamentController controller;

  @override
  Widget build(BuildContext context) {
    final copy = TournamentCopy.of(context);
    final results = controller.results;
    final total = tournamentInt(results['all']);
    final games = results['games'];
    final published = total != null;
    return _Page(
      title: copy.resultsTitle,
      onBack: controller.showHome,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(copy.verifiedScore, style: const TextStyle(color: GameTokens.textMuted)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              published ? '$total' : '—',
              key: const Key('results-score'),
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                color: GameTokens.scoreGlow,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (!published)
            Text(
              copy.resultsPending,
              style: const TextStyle(color: GameTokens.danger),
            ),
          if (controller.resultsError != null)
            Text('${copy.reference}: ${controller.resultsError}', style: const TextStyle(color: GameTokens.textMuted)),
          const SizedBox(height: 8),
          Text(results['onTimeAwarded'] == true ? copy.onTime : copy.onTimeMissing),
          const SizedBox(height: 12),
          _Pips(completed: published ? 6 : controller.day?.completedGames ?? 0, current: null),
          const SizedBox(height: 12),
          _ScoreLine(label: copy.easy, value: tournamentInt(results['easy'])),
          _ScoreLine(label: copy.medium, value: tournamentInt(results['medium'])),
          _ScoreLine(label: copy.hard, value: tournamentInt(results['hard'])),
          _ScoreLine(label: copy.all, value: total),
          if (games is List) ...[
            const SizedBox(height: 8),
            for (final item in games)
              if (item is Map)
                _ScoreLine(
                  label: item['label']?.toString() ?? '',
                  value: tournamentInt(item['score']),
                ),
          ],
          const SizedBox(height: 18),
          FilledButton(
            key: const Key('daily-leaderboard'),
            onPressed: controller.openDaily,
            child: Text(copy.dailyBoard),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            key: const Key('weekly-leaderboard'),
            onPressed: controller.openWeekly,
            child: Text(copy.weeklyBoard),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            key: const Key('return-home'),
            onPressed: controller.showHome,
            child: Text(copy.returnHome),
          ),
        ],
      ),
    );
  }
}

final class _LeaderboardScreen extends StatelessWidget {
  const _LeaderboardScreen({required this.controller});

  final TournamentController controller;

  @override
  Widget build(BuildContext context) {
    final copy = TournamentCopy.of(context);
    final weekly = controller.route.place == TournamentPlace.weekly;
    final rows = controller.leaderboard['rows'];
    final list = rows is List ? rows : const [];
    final self = controller.leaderboard['self'];
    final title = weekly
        ? '${copy.weeklyBoard}  ${controller.weekStart ?? ''}'
        : '${copy.dailyBoard}  ${controller.leaderboard['period'] ?? ''}';
    return _Page(
      title: title,
      onBack: controller.back,
      child: Column(
        children: [
          if (weekly)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                controller.weeklyFinal ? copy.finalLabel : copy.provisional,
                style: TextStyle(
                  color: controller.weeklyFinal ? GameTokens.success : GameTokens.triangleFill,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              for (final category in ['EASY', 'MEDIUM', 'HARD', 'ALL'])
                ChoiceChip(
                  label: Text(copy.categoryLabel(category)),
                  selected: controller.category == category,
                  onSelected: (_) => controller.setCategory(category),
                ),
            ],
          ),
          if (weekly)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final week in controller.weeks)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(week),
                        selected: controller.weekStart == week,
                        onSelected: (_) => controller.openWeekly(week),
                      ),
                    ),
                ],
              ),
            ),
          if (self is Map)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('${copy.you}  ${copy.rankLabel(self['rank'])}  ${self['score']}'),
            )
          else
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(copy.notOnPage),
            ),
          Expanded(
            child: list.isEmpty
                ? Center(child: Text(copy.emptyBoard))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      final row = list[index];
                      if (row is! Map) return const SizedBox.shrink();
                      final mine = row['self'] == true;
                      return ListTile(
                        tileColor: mine ? GameTokens.accent.withValues(alpha: 0.14) : null,
                        leading: Text(
                          '${row['rank']}',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                        ),
                        title: Text(mine ? copy.you : copy.rankLabel(row['rank'])),
                        subtitle: row['onTimeAwarded'] == true ? Text(copy.onTime) : null,
                        trailing: Text(
                          '${row['score']}',
                          style: const TextStyle(color: GameTokens.scoreGlow, fontWeight: FontWeight.w800),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

final class _RecoveryScreen extends StatelessWidget {
  const _RecoveryScreen({required this.controller});

  final TournamentController controller;

  @override
  Widget build(BuildContext context) {
    final copy = TournamentCopy.of(context);
    final code = controller.errorCode;
    return Scaffold(
      body: ArcadeBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(copy.appTitle, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                Text(copy.forError(code), textAlign: TextAlign.center),
                if (code != null && code.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${copy.reference}: $code',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: GameTokens.textMuted),
                  ),
                ],
                const Spacer(),
                FilledButton(
                  onPressed: controller.recover,
                  child: Text(controller.hasPendingCommand ? copy.retrySame : copy.tryAgain),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _Page extends StatelessWidget {
  const _Page({required this.title, required this.onBack, required this.child});

  final String title;
  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ArcadeBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    key: const Key('nav-back'),
                    tooltip: TournamentCopy.of(context).back,
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

final class _Pips extends StatelessWidget {
  const _Pips({required this.completed, required this.current});

  final int completed;
  final int? current;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 1; i <= 6; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                children: [
                  Text(
                    tournamentOrdinalLabels[i] ?? '',
                    style: const TextStyle(fontSize: 10, color: GameTokens.textMuted),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: i <= completed
                          ? _tone(tournamentOrdinalLabels[i])
                          : GameTokens.surfaceHigh,
                      borderRadius: BorderRadius.circular(4),
                      border: i == current
                          ? Border.all(color: GameTokens.textPrimary, width: 1)
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

final class _ScoreLine extends StatelessWidget {
  const _ScoreLine({required this.label, required this.value});

  final String label;
  final int? value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value == null ? '—' : '$value',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

final class _IdleClock extends StatefulWidget {
  const _IdleClock({
    required this.label,
    required this.deadlineMs,
    required this.serverNowMs,
    required this.syncedAt,
  });

  final String label;
  final int? deadlineMs;
  final int? serverNowMs;
  final DateTime? syncedAt;

  @override
  State<_IdleClock> createState() => _IdleClockState();
}

final class _IdleClockState extends State<_IdleClock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deadline = widget.deadlineMs;
    final serverNow = widget.serverNowMs;
    final synced = widget.syncedAt;
    if (deadline == null || serverNow == null || synced == null) {
      return const SizedBox.shrink();
    }
    final elapsed = DateTime.now().difference(synced).inMilliseconds;
    final leftMs = deadline - (serverNow + elapsed);
    final left = Duration(milliseconds: leftMs < 0 ? 0 : leftMs);
    final text =
        '${widget.label} ${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}';
    return Text(text, style: const TextStyle(color: GameTokens.textSecondary));
  }
}

Color _tone(String? label) {
  if (label == null) return GameTokens.accent;
  if (label.startsWith('E')) return GameTokens.easyAccent;
  if (label.startsWith('M')) return GameTokens.mediumAccent;
  if (label.startsWith('H')) return GameTokens.hardAccent;
  return GameTokens.accent;
}
