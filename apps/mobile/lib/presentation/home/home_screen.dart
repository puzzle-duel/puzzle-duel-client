import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/application/challenge_session.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/flame_smoke_host.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

/// Guest-first startup screen. No sign-in, network, or backend URL.
final class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.session});

  final ChallengeSession session;

  static const _devSeed = 42;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final snap = session.snapshot;
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
                          snap.ready
                              ? 'Ready for local play. No network or sign-in required.'
                              : 'Starting…',
                          style: textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Difficulty profiles',
                          style: textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final profile in session.supportedProfiles)
                              Semantics(
                                button: true,
                                label:
                                    'Generate ${profile.wire} challenge with seed $_devSeed',
                                child: FilledButton.tonal(
                                  onPressed: () {
                                    session.runGeneratorSmokeTest(
                                      profile: profile,
                                      seed: _devSeed,
                                    );
                                  },
                                  child: Text(_profileLabel(profile)),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Development generator smoke test (seed $_devSeed). '
                          'This is not a playable board.',
                          style: textTheme.bodySmall,
                        ),
                        const SizedBox(height: 16),
                        _ResultCard(snapshot: snap),
                        const SizedBox(height: 24),
                        Text(
                          'Flame rendering probe',
                          style: textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const SizedBox(
                          height: 96,
                          child: FlameSmokeHost(),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Flame hosts a disposable smoke surface only. '
                          'Canonical rules state stays in puzzle_duel_rules.',
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

  static String _profileLabel(DifficultyProfile profile) {
    final name = switch (profile) {
      DifficultyProfile.easy => 'Easy',
      DifficultyProfile.medium => 'Medium',
      DifficultyProfile.hard => 'Hard',
    };
    return '$name ${profile.boardSize}×${profile.boardSize} '
        '/ ${profile.moveLimit} moves';
  }
}

final class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.snapshot});

  final ChallengeSessionSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (snapshot.hasFailure) {
      return Semantics(
        liveRegion: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Generator failure: ${snapshot.lastErrorMessage ?? 'unknown'}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ),
      );
    }

    final challenge = snapshot.lastChallenge;
    if (challenge == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'No challenge generated yet. Choose a profile above.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DefaultTextStyle(
          style: theme.textTheme.bodyMedium!.copyWith(
            color: theme.colorScheme.onPrimaryContainer,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Generator OK',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 8),
              Text('profile: ${challenge.profile.wire}'),
              Text('seed: ${challenge.seed}'),
              Text('generator: ${challenge.generatorVersion.id}'),
              Text('rules: ${challenge.rulesVersion.id}'),
              Text(
                'board: ${challenge.state.boardSize}×${challenge.state.boardSize}',
              ),
              Text('moveLimit: ${challenge.state.moveLimit}'),
              Text('blocked: ${challenge.state.blocked.length}'),
              Text(
                'score: ${challenge.state.score} '
                '(local engine field; not a ranked result)',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
