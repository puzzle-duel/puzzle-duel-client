import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/diagnostics/screen_breadcrumb_observer.dart';
import 'package:puzzle_duel_mobile/application/game_session.dart';
import 'package:puzzle_duel_mobile/presentation/audio/game_sfx.dart';
import 'package:puzzle_duel_mobile/presentation/audio/game_sfx_scope.dart';
import 'package:puzzle_duel_mobile/presentation/debug/interaction_perf.dart';
import 'package:puzzle_duel_mobile/presentation/game/game_screen.dart';
import 'package:puzzle_duel_mobile/theme/app_theme.dart';

/// Legacy isolated gameplay harness for widget tests only; never used by main.dart.
void runPuzzleDuelApp(GameSession session, {GameSfx? sfx}) {
  runApp(PuzzleDuelApp(session: session, sfx: sfx));
}

/// Non-release gameplay test harness. The legacy difficulty selection UI is removed.
final class PuzzleDuelApp extends StatefulWidget {
  const PuzzleDuelApp({super.key, required this.session, this.sfx});

  final GameSession session;

  /// Optional override (tests). When null, an [AssetGameSfx] is owned here.
  final GameSfx? sfx;

  @override
  State<PuzzleDuelApp> createState() => _PuzzleDuelAppState();
}

final class _PuzzleDuelAppState extends State<PuzzleDuelApp> {
  late final GameSfx _sfx;
  late final bool _ownsSfx;

  @override
  void initState() {
    super.initState();
    _ownsSfx = widget.sfx == null;
    _sfx = widget.sfx ?? AssetGameSfx();
    InteractionPerf.mark('app.init');
    // Warm audio off the critical path after the first home frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      InteractionPerf.mark('app.first_frame');
      // ignore: discarded_futures
      _sfx.prepare();
    });
  }

  @override
  void dispose() {
    if (_ownsSfx) {
      _sfx.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GameSfxScope(
      sfx: _sfx,
      child: MaterialApp(
        title: 'Puzzle Duel',
        debugShowCheckedModeBanner: false,
        navigatorObservers: [ScreenBreadcrumbObserver()],
        theme: PuzzleDuelTheme.dark(),
        // Bridge supplies theme/localizations to Flame (legacy Material imports).
        builder: (context, child) {
          // ignore: deprecated_member_use
          return MaterialUiCompatibilityBridge(
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: ListenableBuilder(
          listenable: widget.session,
          builder: (context, _) {
            final phase = widget.session.view.phase;
            if (phase == GameScreenPhase.menu) {
              return const Scaffold(
                body: Center(
                  child: Text(
                    'Tournament staging is required',
                    key: Key('tournament-only-gate'),
                  ),
                ),
              );
            }
            return GameScreen(session: widget.session);
          },
        ),
      ),
    );
  }
}
