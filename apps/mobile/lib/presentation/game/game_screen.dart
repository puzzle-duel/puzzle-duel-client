import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/application/game_session.dart';
import 'package:puzzle_duel_mobile/presentation/audio/game_sfx.dart';
import 'package:puzzle_duel_mobile/presentation/audio/game_sfx_scope.dart';
import 'package:puzzle_duel_mobile/presentation/debug/interaction_perf.dart';
import 'package:puzzle_duel_mobile/presentation/feedback/move_feedback_toast.dart';
import 'package:puzzle_duel_mobile/presentation/game/board/accessible_board.dart';
import 'package:puzzle_duel_mobile/presentation/game/offer_tray.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/arcade_backdrop.dart';
import 'package:puzzle_duel_mobile/theme/game_tokens.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

/// Playable round screen — board-first arcade HUD.
final class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.session});

  final GameSession session;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

final class _GameScreenState extends State<GameScreen> {
  @override
  void initState() {
    super.initState();
    InteractionPerf.mark('game_screen.init');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      InteractionPerf.mark('game_screen.first_frame');
      // Ensure audio warm-up completed even if home prepare was skipped/muted.
      // ignore: discarded_futures
      GameSfxScope.maybeOf(context)?.prepare();
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final view = session.view;
        final state = view.canonicalState;
        final profile = view.profile;
        final difficulty = switch (profile) {
          DifficultyProfile.easy => 'Easy',
          DifficultyProfile.medium => 'Medium',
          DifficultyProfile.hard => 'Hard',
          null => 'Round',
        };

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ArcadeBackdrop(
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final landscape =
                      constraints.maxWidth > constraints.maxHeight;
                  final tray = OfferTray(
                    offers:
                        state?.offers ??
                        const [OfferEmpty(), OfferEmpty(), OfferEmpty()],
                    selectedIndex: view.selectedOfferIndex,
                    enabled: view.acceptsInput,
                    onSelect: session.selectOffer,
                  );
                  final board = AccessibleBoard(session: session, view: view);
                  final hud = _HudBar(view: view);
                  final hint = _HintLine(view: view);

                  return Stack(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _TopNav(
                            title: difficulty,
                            resolving: view.isResolving,
                            onBack: session.returnToMenu,
                            onSkip: view.isResolving
                                ? () => session.skipResolution(
                                    generation: view.generation,
                                    resolutionId: view.activeResolutionId,
                                  )
                                : null,
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
                            child: hud,
                          ),
                          Expanded(
                            child: landscape
                                ? Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            12,
                                            0,
                                            6,
                                            8,
                                          ),
                                          child: board,
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            6,
                                            0,
                                            12,
                                            8,
                                          ),
                                          child: Column(
                                            children: [
                                              hint,
                                              const Spacer(),
                                              tray,
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : Column(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        child: hint,
                                      ),
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            8,
                                            4,
                                            8,
                                            4,
                                          ),
                                          child: board,
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          10,
                                          0,
                                          10,
                                          10,
                                        ),
                                        child: tray,
                                      ),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                      MoveFeedbackToast(session: session),
                      if (view.phase == GameScreenPhase.ended)
                        _EndOverlay(session: session, view: view),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

final class _TopNav extends StatelessWidget {
  const _TopNav({
    required this.title,
    required this.resolving,
    required this.onBack,
    required this.onSkip,
  });

  final String title;
  final bool resolving;
  final VoidCallback onBack;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back to difficulty selection',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            color: GameTokens.textPrimary,
          ),
          Expanded(
            child: Column(
              children: [
                const Text(
                  'PUZZLE DUEL',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w700,
                    color: GameTokens.textMuted,
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: GameTokens.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          if (resolving && onSkip != null)
            TextButton(onPressed: onSkip, child: const Text('Skip'))
          else
            const SizedBox(width: 64),
        ],
      ),
    );
  }
}

final class _HudBar extends StatelessWidget {
  const _HudBar({required this.view});

  final GameSessionView view;

  @override
  Widget build(BuildContext context) {
    final scoreDelta = view.activeScript?.applied.scoreDelta;
    final showDelta = view.isResolving && scoreDelta != null && scoreDelta > 0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: GameTokens.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(GameTokens.radiusMd),
        border: Border.all(color: GameTokens.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                liveRegion: true,
                label: 'Score ${view.score}',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SCORE',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                        color: GameTokens.textMuted,
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Flexible(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: Text(
                              '${view.score}',
                              key: ValueKey(view.score),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 32,
                                height: 1.05,
                                fontWeight: FontWeight.w800,
                                color: GameTokens.textPrimary,
                              ),
                            ),
                          ),
                        ),
                        if (showDelta) ...[
                          const SizedBox(width: 6),
                          Text(
                            '+$scoreDelta',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: GameTokens.scoreGlow,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Container(width: 1, height: 42, color: GameTokens.border),
            const SizedBox(width: 14),
            Expanded(
              child: Semantics(
                liveRegion: true,
                label: 'Moves remaining ${view.movesRemaining}',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'MOVES LEFT',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                        color: GameTokens.textMuted,
                      ),
                    ),
                    Text(
                      '${view.movesRemaining}',
                      style: TextStyle(
                        fontSize: 32,
                        height: 1.05,
                        fontWeight: FontWeight.w800,
                        color: view.movesRemaining <= 2
                            ? GameTokens.danger
                            : GameTokens.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _HintLine extends StatelessWidget {
  const _HintLine({required this.view});

  final GameSessionView view;

  @override
  Widget build(BuildContext context) {
    final selected = view.selectedOfferIndex;
    final text = selected == null
        ? 'Select a piece, then tap an empty cell.'
        : 'Selected offer ${selected + 1}. Tap an empty cell.';
    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: GameTokens.textSecondary,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

final class _EndOverlay extends StatefulWidget {
  const _EndOverlay({required this.session, required this.view});

  final GameSession session;
  final GameSessionView view;

  @override
  State<_EndOverlay> createState() => _EndOverlayState();
}

final class _EndOverlayState extends State<_EndOverlay> {
  var _playedRoundEnd = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_playedRoundEnd) return;
    _playedRoundEnd = true;
    GameSfxScope.maybeOf(context)?.play(GameSfxEvent.roundEnd);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final view = widget.view;
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.62),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: GameTokens.surface,
                borderRadius: BorderRadius.circular(GameTokens.radiusLg),
                border: Border.all(color: GameTokens.borderBright),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 28,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'ROUND COMPLETE',
                      style: TextStyle(
                        letterSpacing: 1.8,
                        fontWeight: FontWeight.w800,
                        color: GameTokens.accent,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        'Final score ${view.score}',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: GameTokens.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Local practice score only.',
                      style: TextStyle(color: GameTokens.textMuted),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: session.playAgain,
                        child: const Text('Play Again'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: session.returnToMenu,
                        child: const Text('Change Difficulty'),
                      ),
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
