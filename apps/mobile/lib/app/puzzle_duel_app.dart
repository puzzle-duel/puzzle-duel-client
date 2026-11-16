import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/application/challenge_session.dart';
import 'package:puzzle_duel_mobile/presentation/home/home_screen.dart';
import 'package:puzzle_duel_mobile/theme/app_theme.dart';

/// Entry used by [main] and widget tests.
void runPuzzleDuelApp(ChallengeSession session) {
  runApp(PuzzleDuelApp(session: session));
}

/// Root application shell. Offline-capable; no backend URL required.
final class PuzzleDuelApp extends StatelessWidget {
  const PuzzleDuelApp({super.key, required this.session});

  final ChallengeSession session;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Puzzle Duel',
      debugShowCheckedModeBanner: false,
      theme: PuzzleDuelTheme.light(),
      // Bridge supplies theme/localizations to Flame (legacy Material imports).
      // It does not make legacy public types assignable to material_ui types.
      // Deprecated notice is expected until Flame migrates off flutter/material.
      builder: (context, child) {
        // ignore: deprecated_member_use
        return MaterialUiCompatibilityBridge(
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: HomeScreen(session: session),
    );
  }
}
