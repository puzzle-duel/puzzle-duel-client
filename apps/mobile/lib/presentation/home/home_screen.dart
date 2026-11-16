import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/application/game_constants.dart';
import 'package:puzzle_duel_mobile/application/game_session.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/arcade_backdrop.dart';
import 'package:puzzle_duel_mobile/theme/game_tokens.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

/// Guest-first difficulty selection — premium arcade menu.
final class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.session});

  final GameSession session;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final view = session.view;
        return Scaffold(
          body: ArcadeBackdrop(
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 56,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'PUZZLE DUEL',
                            textAlign: TextAlign.center,
                            style: textTheme.headlineMedium?.copyWith(
                              letterSpacing: 2.2,
                              fontWeight: FontWeight.w800,
                              color: GameTokens.textPrimary,
                            ),
                            semanticsLabel: 'Puzzle Duel',
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Match shapes. Ride the cascade.',
                            textAlign: TextAlign.center,
                            style: textTheme.titleMedium?.copyWith(
                              color: GameTokens.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Offline practice — no account required.',
                            textAlign: TextAlign.center,
                            style: textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 28),
                          for (final profile in view.supportedProfiles) ...[
                            _DifficultyCard(
                              profile: profile,
                              onPlay: () {
                                session.startRound(
                                  profile: profile,
                                  seed: kUatChallengeSeed,
                                );
                              },
                            ),
                            const SizedBox(height: 14),
                          ],
                          if (view.generationFailure != null)
                            Text(
                              'Could not start: ${view.generationFailure!.wire}',
                              style: textTheme.bodyMedium?.copyWith(
                                color: GameTokens.danger,
                              ),
                            ),
                          const SizedBox(height: 8),
                          Text(
                            'Pick a piece from the tray, then tap an empty cell. '
                            'Local score is practice only.',
                            textAlign: TextAlign.center,
                            style: textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
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

final class _DifficultyCard extends StatelessWidget {
  const _DifficultyCard({required this.profile, required this.onPlay});

  final DifficultyProfile profile;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final accent = GameTokens.difficultyAccent(profile);
    final fill = GameTokens.difficultyCard(profile);
    final name = switch (profile) {
      DifficultyProfile.easy => 'Easy',
      DifficultyProfile.medium => 'Medium',
      DifficultyProfile.hard => 'Hard',
    };
    return Semantics(
      button: true,
      label:
          '$name, ${profile.boardSize} by ${profile.boardSize} board, '
          '${profile.moveLimit} moves',
      child: Material(
        color: fill,
        elevation: 2,
        shadowColor: Colors.black54,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GameTokens.radiusLg),
          side: BorderSide(color: accent.withValues(alpha: 0.55), width: 1.4),
        ),
        child: InkWell(
          onTap: onPlay,
          borderRadius: BorderRadius.circular(GameTokens.radiusLg),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 56,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: GameTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${profile.boardSize}×${profile.boardSize} board',
                        style: const TextStyle(
                          color: GameTokens.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${profile.moveLimit} moves',
                        style: const TextStyle(color: GameTokens.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: GameTokens.bgDeep,
                    minimumSize: const Size(72, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: onPlay,
                  child: const Text('Play'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
