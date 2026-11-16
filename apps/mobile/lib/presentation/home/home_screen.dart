import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/application/game_constants.dart';
import 'package:puzzle_duel_mobile/application/game_session.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

/// Guest-first difficulty selection. No sign-in or network.
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
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 40,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Puzzle Duel',
                          style: textTheme.headlineMedium,
                          semanticsLabel: 'Puzzle Duel',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Play offline. No network or sign-in required.',
                          style: textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'UAT seed $kUatChallengeSeed (deterministic local testing).',
                          style: textTheme.bodySmall,
                        ),
                        const SizedBox(height: 24),
                        Text('Choose difficulty', style: textTheme.titleMedium),
                        const SizedBox(height: 12),
                        for (final profile in view.supportedProfiles) ...[
                          FilledButton.tonal(
                            onPressed: () {
                              session.startRound(
                                profile: profile,
                                seed: kUatChallengeSeed,
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(_label(profile)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        if (view.generationFailure != null)
                          Text(
                            'Could not generate challenge: '
                            '${view.generationFailure!.wire}',
                            style: textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        const SizedBox(height: 16),
                        Text(
                          'Select a piece from the tray, then tap an empty '
                          'board cell. Landing follows piece direction. '
                          'Local score is not a ranked result.',
                          style: textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  static String _label(DifficultyProfile profile) {
    final name = switch (profile) {
      DifficultyProfile.easy => 'Easy',
      DifficultyProfile.medium => 'Medium',
      DifficultyProfile.hard => 'Hard',
    };
    return '$name · ${profile.boardSize}×${profile.boardSize} · '
        '${profile.moveLimit} moves';
  }
}
