import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/application/game_session.dart';
import 'package:puzzle_duel_mobile/presentation/game/game_screen.dart';
import 'package:puzzle_duel_mobile/presentation/home/home_screen.dart';
import 'package:puzzle_duel_mobile/theme/app_theme.dart';

/// Entry used by [main] and widget tests.
void runPuzzleDuelApp(GameSession session) {
  runApp(PuzzleDuelApp(session: session));
}

/// Root application shell. Offline-capable; no backend URL required.
final class PuzzleDuelApp extends StatelessWidget {
  const PuzzleDuelApp({super.key, required this.session});

  final GameSession session;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Puzzle Duel',
      debugShowCheckedModeBanner: false,
      theme: PuzzleDuelTheme.dark(),
      // Bridge supplies theme/localizations to Flame (legacy Material imports).
      builder: (context, child) {
        // ignore: deprecated_member_use
        return MaterialUiCompatibilityBridge(
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final phase = session.view.phase;
          if (phase == GameScreenPhase.menu) {
            return HomeScreen(session: session);
          }
          return GameScreen(session: session);
        },
      ),
    );
  }
}
