import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/application/game_session.dart';
import 'package:puzzle_duel_mobile/presentation/audio/game_sfx.dart';
import 'package:puzzle_duel_mobile/presentation/audio/game_sfx_scope.dart';
import 'package:puzzle_duel_mobile/presentation/game/board/accessible_board.dart';
import 'package:puzzle_duel_mobile/presentation/game/offer_tray.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/arcade_backdrop.dart';
import 'package:puzzle_duel_mobile/theme/game_tokens.dart';
import 'package:puzzle_duel_mobile/tournament/practice_store.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_copy.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_controller.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

/// Offline practice. It never calls the tournament API.
final class PracticeFlow extends StatefulWidget {
  const PracticeFlow({
    super.key,
    required this.directory,
    required this.haptics,
  });

  final Directory directory;
  final TournamentHaptics haptics;

  @override
  State<PracticeFlow> createState() => _PracticeFlowState();
}

final class _PracticeFlowState extends State<PracticeFlow> {
  final GameSession _session = GameSession();
  late final PracticeStore _store = PracticeStore(widget.directory);
  DifficultyProfile? _profile;
  int? _seed;
  bool _recorded = false;
  bool _review = false;
  bool _replayed = false;
  GameState? _finished;
  int? _deviceBest;
  int _seenResolution = 0;
  MoveFeedbackKind? _seenFeedback;

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSession);
  }

  void _onSession() {
    final view = _session.view;
    final script = view.activeScript;
    if (script != null && script.resolutionId != _seenResolution) {
      _seenResolution = script.resolutionId;
      if (script.applied.scoreDelta > 0) {
        widget.haptics.cleared();
      } else {
        widget.haptics.accepted();
      }
    }
    if (view.feedbackKind == MoveFeedbackKind.rejected && _seenFeedback != MoveFeedbackKind.rejected) {
      widget.haptics.rejected();
      GameSfxScope.maybeOf(context)?.play(GameSfxEvent.reject);
    }
    _seenFeedback = view.feedbackKind;
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    _session.dispose();
    super.dispose();
  }

  void _start(DifficultyProfile profile, {int? seed, bool replay = false}) {
    final issued = seed ?? _store.nextSeed();
    final started = _session.startRound(profile: profile, seed: issued);
    if (!started) return;
    setState(() {
      _profile = profile;
      _seed = issued;
      _recorded = false;
      _review = false;
      _replayed = replay;
    });
  }

  void _maybeRecord() {
    if (!mounted || _recorded) return;
    final state = _session.view.canonicalState;
    final profile = _profile;
    final seed = _seed;
    if (state == null || profile == null || seed == null || state.status != GameStatus.ended) {
      return;
    }
    _recorded = true;
    _finished = state;
    final when = DateTime.now().toUtc().toIso8601String();
    _store.append(
      PracticeRecord(
        sessionId: 'practice-$seed-$when',
        difficulty: profile.wire,
        rulesVersion: state.rulesVersion.id,
        generatorVersion: GeneratorVersion.gen001V1.id,
        seed: seed,
        score: state.score,
        terminalReason: state.terminalReason?.wire ?? 'ended',
        completedAt: when,
      ),
    );
    final best = _store.bestScore(profile.wire);
    GameSfxScope.maybeOf(context)?.play(GameSfxEvent.roundEnd);
    widget.haptics.completed();
    if (mounted) setState(() => _deviceBest = best);
  }

  Future<void> _changeDifficulty() async {
    final state = _session.view.canonicalState;
    final inProgress = state != null && state.turnsUsed > 0 && state.status != GameStatus.ended;
    if (inProgress) {
      final copy = TournamentCopy.of(context);
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(copy.leaveTitle),
          content: Text(copy.leaveBody),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(copy.stay)),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(copy.changeDifficulty)),
          ],
        ),
      );
      if (leave != true || !mounted) return;
    }
    setState(() {
      _profile = null;
      _seed = null;
    });
  }

  Future<void> _leave() async {
    final state = _session.view.canonicalState;
    final inProgress = state != null && state.turnsUsed > 0 && state.status != GameStatus.ended;
    if (inProgress) {
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
      if (leave != true || !mounted) return;
      Navigator.pop(context);
      return;
    }
    if (_replayed && _finished != null) {
      setState(() {
        _review = true;
        _replayed = false;
      });
      return;
    }
    setState(() {
      _profile = null;
      _seed = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final copy = TournamentCopy.of(context);
    return ListenableBuilder(
      listenable: _session,
      builder: (context, _) {
        final state = _session.view.canonicalState;
        if (_review && _finished != null && _profile != null) {
          return PracticeResultView(
            copy: copy,
            state: _finished!,
            profile: _profile!,
            onReplay: () => _start(_profile!, seed: _seed, replay: true),
            onNew: () => _start(_profile!),
            onDifficulty: () => setState(() {
              _review = false;
              _profile = null;
              _seed = null;
            }),
            onHome: () => Navigator.pop(context),
            deviceBest: _deviceBest,
          );
        }
        if (state != null && state.status == GameStatus.ended) {
          if (!_recorded) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _maybeRecord();
            });
          }
          return PracticeResultView(
            copy: copy,
            state: state,
            profile: _profile!,
            onReplay: () => _start(_profile!, seed: _seed, replay: true),
            onNew: () => _start(_profile!),
            onDifficulty: () => setState(() {
              _profile = null;
              _seed = null;
            }),
            onHome: () => Navigator.pop(context),
            deviceBest: _deviceBest,
          );
        }
        if (state == null || _profile == null) {
          return _PracticePicker(copy: copy, onPick: _start, onClose: () => Navigator.pop(context));
        }
        return _PracticePlay(
          copy: copy,
          session: _session,
          haptics: widget.haptics,
          onLeave: _leave,
          onChangeDifficulty: _changeDifficulty,
        );
      },
    );
  }
}

final class _PracticePicker extends StatelessWidget {
  const _PracticePicker({required this.copy, required this.onPick, required this.onClose});

  final TournamentCopy copy;
  final void Function(DifficultyProfile profile) onPick;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ArcadeBackdrop(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  key: const Key('nav-back'),
                  onPressed: onClose,
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
              Text(copy.practiceTitle, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(copy.practiceBlurb),
              const SizedBox(height: 18),
              Text(copy.chooseDifficulty, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              _DifficultyButton(
                keyName: 'practice-easy',
                label: copy.easy,
                detail: copy.budgetLine(5, 15),
                onPressed: () => onPick(DifficultyProfile.easy),
              ),
              _DifficultyButton(
                keyName: 'practice-medium',
                label: copy.medium,
                detail: copy.budgetLine(6, 12),
                onPressed: () => onPick(DifficultyProfile.medium),
              ),
              _DifficultyButton(
                keyName: 'practice-hard',
                label: copy.hard,
                detail: copy.budgetLine(7, 10),
                onPressed: () => onPick(DifficultyProfile.hard),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _DifficultyButton extends StatelessWidget {
  const _DifficultyButton({
    required this.keyName,
    required this.label,
    required this.detail,
    required this.onPressed,
  });

  final String keyName;
  final String label;
  final String detail;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FilledButton(
        key: Key(keyName),
        onPressed: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(detail),
            ],
          ),
        ),
      ),
    );
  }
}

final class _PracticePlay extends StatelessWidget {
  const _PracticePlay({
    required this.copy,
    required this.session,
    required this.haptics,
    required this.onLeave,
    required this.onChangeDifficulty,
  });

  final TournamentCopy copy;
  final GameSession session;
  final TournamentHaptics haptics;
  final Future<void> Function() onLeave;
  final Future<void> Function() onChangeDifficulty;

  @override
  Widget build(BuildContext context) {
    final state = session.view.canonicalState!;
    return Scaffold(
      body: ArcadeBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: 52,
                child: Row(
                  children: [
                    IconButton(
                      key: const Key('nav-back'),
                      onPressed: () => onLeave(),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    Text(copy.practiceTitle, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const Spacer(),
                    Text(
                      '${state.score}',
                      key: const Key('practice-score'),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
              ),
              SizedBox(
                height: 28,
                child: Text(
                  '${copy.budgetLine(state.boardSize, state.moveLimit)} · ${copy.movesLeft(session.view.movesRemaining)}',
                  key: const Key('practice-budget'),
                ),
              ),
              SizedBox(
                height: 36,
                child: TextButton(
                  key: const Key('practice-change'),
                  onPressed: () => onChangeDifficulty(),
                  child: Text(copy.changeDifficulty),
                ),
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
                          child: AccessibleBoard(session: session, view: session.view, showPlacementPreview: true),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: OfferTray(
                    offers: state.offers,
                    selectedIndex: session.view.selectedOfferIndex,
                    enabled: session.view.acceptsInput,
                    selectionLabel: copy.selectPiece,
                    onSelect: (index) {
                      session.selectOffer(index);
                      GameSfxScope.maybeOf(context)?.play(GameSfxEvent.place);
                      haptics.selection();
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

final class PracticeResultView extends StatelessWidget {
  const PracticeResultView({
    super.key,
    required this.copy,
    required this.state,
    required this.profile,
    required this.onReplay,
    required this.onNew,
    required this.onDifficulty,
    required this.onHome,
    this.deviceBest,
  });

  final TournamentCopy copy;
  final GameState state;
  final DifficultyProfile profile;
  final VoidCallback onReplay;
  final VoidCallback onNew;
  final VoidCallback onDifficulty;
  final VoidCallback onHome;
  final int? deviceBest;

  @override
  Widget build(BuildContext context) {
    final tone = GameTokens.difficultyAccent(profile);
    final best = deviceBest;
    return Scaffold(
      body: ArcadeBackdrop(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            children: [
              Text(copy.practiceDone, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 6),
              Text(
                '${copy.difficultyOf(profile == DifficultyProfile.easy ? 'E1' : profile == DifficultyProfile.medium ? 'M1' : 'H1')} · ${copy.budgetLine(state.boardSize, state.moveLimit)}',
                style: TextStyle(color: tone, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                copy.groupedScore(state.score),
                key: const Key('practice-result-score'),
                style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w800, color: GameTokens.scoreGlow, height: 1),
              ),
              const SizedBox(height: 8),
              Text(copy.finishReason(state.terminalReason?.wire)),
              if (best != null) ...[
                const SizedBox(height: 8),
                Text(
                  state.score >= best
                      ? copy.personalBest
                      : '${copy.bestOnDevice} ${copy.groupedScore(best)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
              const SizedBox(height: 8),
              Text(copy.practiceLocal, style: const TextStyle(color: GameTokens.textSecondary)),
              const SizedBox(height: 22),
              FilledButton(key: const Key('practice-new'), onPressed: onNew, child: Text(copy.newPuzzle)),
              const SizedBox(height: 10),
              OutlinedButton(key: const Key('practice-replay'), onPressed: onReplay, child: Text(copy.samePuzzle)),
              const SizedBox(height: 4),
              TextButton(onPressed: onDifficulty, child: Text(copy.changeDifficulty)),
              TextButton(key: const Key('practice-home'), onPressed: onHome, child: Text(copy.homeAction)),
            ],
          ),
        ),
      ),
    );
  }
}
