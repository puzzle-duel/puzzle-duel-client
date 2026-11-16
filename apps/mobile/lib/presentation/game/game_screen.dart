import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/application/game_session.dart';
import 'package:puzzle_duel_mobile/presentation/game/board/accessible_board.dart';
import 'package:puzzle_duel_mobile/presentation/game/offer_tray.dart';

/// Playable round screen for first UAT.
final class GameScreen extends StatelessWidget {
  const GameScreen({super.key, required this.session});

  final GameSession session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final view = session.view;
        final theme = Theme.of(context);
        final state = view.canonicalState;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Puzzle Duel'),
            leading: IconButton(
              tooltip: 'Back to difficulty selection',
              onPressed: session.returnToMenu,
              icon: const Icon(Icons.arrow_back),
            ),
            actions: [
              if (view.isResolving)
                TextButton(
                  onPressed: () =>
                      session.skipResolution(generation: view.generation),
                  child: const Text('Skip'),
                ),
            ],
          ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final landscape = constraints.maxWidth > constraints.maxHeight;
                final board = AccessibleBoard(session: session, view: view);
                final side = _StatusColumn(session: session, view: view);
                final tray = OfferTray(
                  offers: state?.offers ?? const [null, null, null],
                  selectedIndex: view.selectedOfferIndex,
                  enabled: view.acceptsInput,
                  onSelect: session.selectOffer,
                );

                final column = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Text(
                        _subtitle(view),
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    if (view.feedbackKind != MoveFeedbackKind.none)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _feedbackText(view),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color:
                                  view.feedbackKind == MoveFeedbackKind.unsafe
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: landscape
                          ? Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: board,
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: side,
                                  ),
                                ),
                              ],
                            )
                          : Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                children: [
                                  Expanded(child: board),
                                  const SizedBox(height: 12),
                                  side,
                                ],
                              ),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: tray,
                    ),
                  ],
                );

                return column;
              },
            ),
          ),
        );
      },
    );
  }

  static String _subtitle(GameSessionView view) {
    final profile = view.profile?.wire ?? 'round';
    final seed = view.seed ?? '—';
    return '${_titleCase(profile)} · seed $seed'
        '${view.isResolving ? ' · resolving' : ''}';
  }

  static String _titleCase(String wire) {
    if (wire.isEmpty) return wire;
    return '${wire[0].toUpperCase()}${wire.substring(1)}';
  }

  static String _feedbackText(GameSessionView view) {
    return switch (view.feedbackKind) {
      MoveFeedbackKind.none => '',
      MoveFeedbackKind.rejected =>
        'Move rejected: ${view.feedbackCode ?? 'rejected'}',
      MoveFeedbackKind.unsafe =>
        'Move could not be applied safely: ${view.feedbackCode ?? 'unsafe'}',
    };
  }
}

final class _StatusColumn extends StatelessWidget {
  const _StatusColumn({required this.session, required this.view});

  final GameSession session;
  final GameSessionView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = view.selectedOfferIndex;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          label: 'Score ${view.score}',
          child: Text(
            'Score ${view.score}',
            style: theme.textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: 4),
        Semantics(
          liveRegion: true,
          label: 'Moves remaining ${view.movesRemaining}',
          child: Text(
            'Moves left ${view.movesRemaining}',
            style: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          selected == null
              ? 'Select an offer, then tap an empty cell.'
              : 'Selected offer ${selected + 1}. Tap an empty cell.',
          style: theme.textTheme.bodyMedium,
        ),
        if (view.phase == GameScreenPhase.ended) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              'Round complete. Final score ${view.score}.',
              style: theme.textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: session.playAgain,
            child: const Text('Play again'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: session.returnToMenu,
            child: const Text('New difficulty'),
          ),
        ],
      ],
    );
  }
}
