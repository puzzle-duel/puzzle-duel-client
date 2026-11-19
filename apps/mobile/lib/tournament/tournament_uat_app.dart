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
import 'package:puzzle_duel_mobile/tournament/local_settings.dart';
import 'package:puzzle_duel_mobile/tournament/practice_flow.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_controller.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_leaderboard_view.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_settings.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_copy.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_nav.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

export 'tournament_controller.dart';

void runTournamentUatApp(UatConfig config, {UatApi? api}) {
  runApp(
    TournamentUatApp(
      config: config,
      api: api,
      sfx: AssetGameSfx(coupledHaptics: false),
      ownsSfx: true,
    ),
  );
}

final class TournamentUatApp extends StatefulWidget {
  const TournamentUatApp({
    super.key,
    required this.config,
    this.api,
    this.stateDirectory,
    this.haptics,
    this.sfx,
    this.ownsSfx = false,
    this.locale,
    this.textScaler,
  });

  final UatConfig config;
  final UatApi? api;
  final Directory? stateDirectory;
  final TournamentHaptics? haptics;
  final GameSfx? sfx;
  final bool ownsSfx;
  final Locale? locale;
  final TextScaler? textScaler;

  @override
  State<TournamentUatApp> createState() => _TournamentUatAppState();
}

final class _TournamentUatAppState extends State<TournamentUatApp> {
  late final GameSfx _sfx = widget.sfx ?? SilentGameSfx();
  late final LocalSettings _settings = LocalSettings.load(
    widget.stateDirectory ?? Directory.systemTemp,
  );
  late final TournamentController _controller = TournamentController(
    config: widget.config,
    api: widget.api,
    stateDirectory: widget.stateDirectory,
    sfx: _sfx,
    settings: _settings,
    haptics: widget.haptics ??
        DeviceTournamentHaptics(
          enabled: () => _settings.haptics,
          successAllowed: () =>
              !WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.reduceMotion,
        ),
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
    if (widget.ownsSfx || widget.sfx == null) _sfx.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GameSfxScope(
      sfx: _sfx,
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
      TournamentPlace.daily || TournamentPlace.weekly => TournamentLeaderboardView(controller: controller),
      TournamentPlace.overview => _OverviewScreen(controller: controller),
      TournamentPlace.recovery => _RecoveryScreen(controller: controller),
      TournamentPlace.home => _HomeScreen(controller: controller),
    };
  }
}

final class _PlayFeedback extends StatelessWidget {
  const _PlayFeedback({required this.controller, required this.notice, required this.copy});

  final TournamentController controller;
  final String? notice;
  final TournamentCopy copy;

  @override
  Widget build(BuildContext context) {
    final delta = controller.scoreDelta;
    if (controller.hasPendingCommand) {
      return TextButton(onPressed: controller.retryUnknown, child: Text(copy.retrySame));
    }
    if (notice != null) {
      return Text(
        copy.forError(notice),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: GameTokens.danger),
      );
    }
    if (delta != null && delta > 0) {
      return Text(
        '+$delta',
        key: const Key('score-delta'),
        style: const TextStyle(color: GameTokens.success, fontWeight: FontWeight.w800, fontSize: 20),
      );
    }
    if (controller.moveInFlight) {
      return Text(copy.sending, style: const TextStyle(color: GameTokens.accent));
    }
    return const SizedBox.shrink();
  }
}

void _openSettings(BuildContext context, TournamentController controller) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => TournamentSettingsScreen(controller: controller),
    ),
  );
}

void _showProfileHold(BuildContext context) {
  final copy = TournamentCopy.of(context);
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(copy.profile),
      content: Text(copy.profileLater),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(copy.back)),
      ],
    ),
  );
}

void _openPractice(BuildContext context, TournamentController controller) {
  controller.haptics.selection();
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => PracticeFlow(
        directory: controller.settings.file.parent,
        haptics: controller.haptics,
      ),
    ),
  );
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
      DayPhase.betweenGames || DayPhase.inProgress => copy.continueTournament,
      _ => copy.playToday,
    };
    final headline = switch (phase) {
      DayPhase.completed => copy.completedHeadline,
      DayPhase.inProgress || DayPhase.betweenGames => copy.progressHeadline,
      _ => copy.readyHeadline,
    };
    return Scaffold(
      body: ArcadeBackdrop(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          copy.appTitle.toUpperCase(),
                          key: const Key('home-title'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            letterSpacing: 1.6,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          copy.tagline,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: GameTokens.accent),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('profile'),
                    tooltip: copy.profile,
                    onPressed: () => _showProfileHold(context),
                    icon: const Icon(Icons.person_rounded),
                  ),
                  IconButton(
                    key: const Key('settings'),
                    tooltip: copy.settingsTitle,
                    onPressed: () => _openSettings(context, controller),
                    icon: const Icon(Icons.settings_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _DailyCard(
                copy: copy,
                day: day,
                score: score,
                scoreLabel: scoreLabel,
                phase: phase,
                badge: badge,
                headline: headline,
                action: primary,
                onAction: phase == DayPhase.completed ? controller.openResults : controller.resume,
              ),
              const SizedBox(height: 32),
              _HomeActions(controller: controller),
            ],
          ),
        ),
      ),
    );
  }
}

final class _HomeActions extends StatelessWidget {
  const _HomeActions({required this.controller});

  final TournamentController controller;

  @override
  Widget build(BuildContext context) {
    final copy = TournamentCopy.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final stacked = MediaQuery.sizeOf(context).width < 360 || scale > 1.25;
    final leaderboard = _ActionCard(
      cardKey: const Key('leaderboard'),
      icon: Icons.emoji_events_rounded,
      iconColor: GameTokens.scoreGlow,
      title: copy.leaderboard,
      subtitle: copy.weeklyRankings,
      onTap: () => controller.openWeekly(fromHome: true),
    );
    final practice = _ActionCard(
      cardKey: const Key('practice'),
      icon: Icons.sports_esports_rounded,
      iconColor: GameTokens.diamondFill,
      title: copy.practice,
      subtitle: copy.practiceLevels,
      onTap: () => _openPractice(context, controller),
    );
    if (stacked) {
      return Column(
        children: [
          leaderboard,
          const SizedBox(height: 12),
          practice,
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: leaderboard),
          const SizedBox(width: 12),
          Expanded(child: practice),
        ],
      ),
    );
  }
}

final class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.cardKey,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Key cardKey;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      child: Material(
        color: GameTokens.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(GameTokens.radiusLg),
        child: InkWell(
          key: cardKey,
          onTap: onTap,
          borderRadius: BorderRadius.circular(GameTokens.radiusLg),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(GameTokens.radiusLg),
              border: Border.all(color: iconColor.withValues(alpha: 0.7)),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 136),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: iconColor, size: 32),
                    const SizedBox(height: 12),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: GameTokens.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: GameTokens.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
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
    required this.headline,
    required this.action,
    required this.onAction,
  });

  final TournamentCopy copy;
  final TournamentDay? day;
  final int? score;
  final String scoreLabel;
  final DayPhase phase;
  final String? badge;
  final String headline;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final label = day?.label ?? 'E1';
    final tone = phase == DayPhase.completed ? GameTokens.success : _tone(label);
    final body = switch (phase) {
      DayPhase.completed => copy.completedBody,
      DayPhase.ready when day?.original == false => copy.alreadyClaimed,
      DayPhase.inProgress || DayPhase.betweenGames => label,
      _ => copy.readyBody,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tone.withValues(alpha: 0.22),
            GameTokens.surface.withValues(alpha: 0.96),
          ],
        ),
        borderRadius: BorderRadius.circular(GameTokens.radiusLg),
        border: Border.all(color: tone.withValues(alpha: 0.85), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: tone.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              copy.dailyChallenge.toUpperCase(),
              style: TextStyle(color: tone, fontWeight: FontWeight.w800, letterSpacing: 1.1),
            ),
            const SizedBox(height: 8),
            Text(headline, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(body, maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 14),
            _Pips(completed: day?.completedGames ?? 0, current: phase == DayPhase.completed ? null : day?.ordinal),
            const SizedBox(height: 14),
            Text(scoreLabel, style: const TextStyle(color: GameTokens.textMuted)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                score == null ? '—' : copy.groupedScore(score!),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: GameTokens.scoreGlow,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (badge != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(badge!, style: TextStyle(fontWeight: FontWeight.w800, color: tone)),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('primary-action'),
                onPressed: onAction,
                child: Text(action, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
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
      child: Material(
        color: current ? tone.withValues(alpha: 0.16) : GameTokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GameTokens.radiusMd),
          side: BorderSide(color: current ? tone : GameTokens.border),
        ),
        clipBehavior: Clip.antiAlias,
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
              SizedBox(
                height: 52,
                child: Padding(
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
              ),
              SizedBox(
                height: 40,
                child: Padding(
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
              ),
              SizedBox(
                height: 48,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      copy.objective(moves, size),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              SizedBox(
                key: const Key('play-feedback'),
                height: 44,
                child: Center(child: _PlayFeedback(controller: controller, notice: notice, copy: copy)),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final side = constraints.biggest.shortestSide;
                      return Center(
                        child: SizedBox(
                          key: const Key('play-board'),
                          width: side,
                          height: side,
                          child: ListenableBuilder(
                            listenable: controller.session,
                            builder: (context, _) => AccessibleBoard(
                              session: controller.session,
                              view: controller.session.view,
                              showPlacementPreview: true,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              SizedBox(
                key: const Key('offer-tray-frame'),
                height: 152,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
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
                          controller.noteSelection();
                        },
                      );
                    },
                  ),
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
      title: copy.stageComplete,
      onBack: () => _confirmLeave(context, controller),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            day?.label ?? '',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(color: tone, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(copy.finishReason(day?.terminalReason)),
          const SizedBox(height: 16),
          _ScoreHero(label: copy.gameScore, value: day?.gameScore, copy: copy),
          const SizedBox(height: 10),
          _ScoreHero(label: copy.totalScore, value: day?.seriesScore, copy: copy, compact: true),
          const SizedBox(height: 16),
          _Pips(completed: day?.completedGames ?? 0, current: day?.ordinal),
          if (next != null) ...[
            const SizedBox(height: 16),
            Material(
              color: GameTokens.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(GameTokens.radiusMd),
                side: BorderSide(color: _tone(next).withValues(alpha: 0.8)),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: Icon(Icons.flag_rounded, color: _tone(next)),
                title: Text('${copy.nextGame}  $next'),
                subtitle: Text(copy.difficultyOf(next)),
              ),
            ),
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
    final onTime = results['onTimeAwarded'] == true;
    return _Page(
      title: copy.resultsTitle,
      onBack: controller.showHome,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const Icon(Icons.emoji_events_rounded, color: GameTokens.scoreGlow, size: 36),
          const SizedBox(height: 8),
          Text(copy.verifiedScore, style: const TextStyle(color: GameTokens.textMuted)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              published ? copy.groupedScore(total) : '—',
              key: const Key('results-score'),
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                color: GameTokens.scoreGlow,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (!published)
            Text(copy.resultsPending, style: const TextStyle(color: GameTokens.danger)),
          if (controller.resultsError != null)
            Text(copy.forError(controller.resultsError), style: const TextStyle(color: GameTokens.textMuted)),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: (onTime ? GameTokens.success : GameTokens.textMuted).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(
                  onTime ? copy.onTime : copy.onTimeMissing,
                  style: TextStyle(fontWeight: FontWeight.w800, color: onTime ? GameTokens.success : GameTokens.textSecondary),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _Pips(completed: published ? 6 : controller.day?.completedGames ?? 0, current: null),
          const SizedBox(height: 12),
          if (games is List)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in games)
                  if (item is Map)
                    _StageChip(
                      label: item['label']?.toString() ?? '',
                      value: tournamentInt(item['score']),
                      copy: copy,
                    ),
              ],
            ),
          const SizedBox(height: 12),
          _ScoreLine(label: copy.easy, value: tournamentInt(results['easy'])),
          _ScoreLine(label: copy.medium, value: tournamentInt(results['medium'])),
          _ScoreLine(label: copy.hard, value: tournamentInt(results['hard'])),
          const SizedBox(height: 18),
          FilledButton(
            key: const Key('leaderboard'),
            onPressed: () => controller.openWeekly(fromHome: true),
            child: Text(copy.viewLeaderboard),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            key: const Key('practice'),
            onPressed: () => _openPractice(context, controller),
            child: Text(copy.practice),
          ),
          const SizedBox(height: 4),
          TextButton(
            key: const Key('return-home'),
            onPressed: controller.showHome,
            child: Text(copy.returnHome),
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

final class _ScoreHero extends StatelessWidget {
  const _ScoreHero({required this.label, required this.value, required this.copy, this.compact = false});

  final String label;
  final int? value;
  final TournamentCopy copy;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: GameTokens.surface,
        borderRadius: BorderRadius.circular(GameTokens.radiusMd),
        border: Border.all(color: GameTokens.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(color: GameTokens.textSecondary))),
            Text(
              value == null ? '—' : copy.groupedScore(value!),
              style: TextStyle(
                color: GameTokens.scoreGlow,
                fontWeight: FontWeight.w800,
                fontSize: compact ? 22 : 32,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _StageChip extends StatelessWidget {
  const _StageChip({required this.label, required this.value, required this.copy});

  final String label;
  final int? value;
  final TournamentCopy copy;

  @override
  Widget build(BuildContext context) {
    final tone = _tone(label);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(GameTokens.radiusMd),
        border: Border.all(color: tone.withValues(alpha: 0.7)),
      ),
      child: SizedBox(
        width: 96,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: tone, fontWeight: FontWeight.w800)),
              Text(
                value == null ? '—' : copy.groupedScore(value!),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _ScoreLine extends StatelessWidget {
  const _ScoreLine({required this.label, required this.value});

  final String label;
  final int? value;

  @override
  Widget build(BuildContext context) {
    final copy = TournamentCopy.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value == null ? '—' : copy.groupedScore(value!),
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
