import 'package:flame/game.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/application/animation_script.dart';
import 'package:puzzle_duel_mobile/application/game_session.dart';
import 'package:puzzle_duel_mobile/presentation/game/board/puzzle_board_game.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/piece_glyph.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

/// Flame visual board with a Flutter semantics/input overlay.
final class AccessibleBoard extends StatefulWidget {
  const AccessibleBoard({super.key, required this.session, required this.view});

  final GameSession session;
  final GameSessionView view;

  @override
  State<AccessibleBoard> createState() => _AccessibleBoardState();
}

final class _AccessibleBoardState extends State<AccessibleBoard> {
  late final PuzzleBoardGame _game;
  AnimationScript? _playing;

  @override
  void initState() {
    super.initState();
    _game = PuzzleBoardGame(
      onResolutionComplete: (generation) {
        widget.session.completeResolution(generation: generation);
      },
    );
  }

  bool get _reducedMotion {
    final mq = MediaQuery.maybeOf(context);
    final disableAnim = mq?.disableAnimations ?? false;
    final platformReduce = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .reduceMotion;
    return disableAnim || platformReduce;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTheme();
    _syncBoard();
  }

  @override
  void didUpdateWidget(covariant AccessibleBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncBoard();
  }

  void _syncTheme() {
    final scheme = Theme.of(context).colorScheme;
    _game.configurePalette(
      cell: scheme.surfaceContainerHighest,
      blocked: scheme.outline.withValues(alpha: 0.55),
      grid: scheme.outline,
      circle: scheme.primary,
      diamond: scheme.tertiary,
      triangle: scheme.secondary,
      stroke: scheme.onSurface,
      flash: scheme.tertiaryContainer,
    );
  }

  void _syncBoard() {
    final view = widget.view;
    final state = view.canonicalState;
    if (state == null) return;

    final reducedMotion = _reducedMotion;
    _game.setReducedMotion(reducedMotion);

    final script = view.activeScript;
    if (view.isResolving && script != null && !identical(script, _playing)) {
      _playing = script;
      _game.playScript(script, reducedMotion: reducedMotion);
      return;
    }

    if (!view.isResolving) {
      _playing = null;
      _game.showSettled(state, generation: view.generation);
    }
  }

  @override
  void dispose() {
    _game.disposeGame();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.view.canonicalState;
    if (state == null) {
      return const SizedBox.shrink();
    }
    return AspectRatio(
      aspectRatio: 1,
      child: Semantics(
        label: 'Puzzle board, ${state.boardSize} by ${state.boardSize}',
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Visual-only Flame layer; input goes through the semantics grid.
            IgnorePointer(child: GameWidget(game: _game)),
            // Semantics/input use canonical state (authoritative after commit).
            _SemanticsGrid(
              state: state,
              enabled: widget.view.acceptsInput,
              onTapCell: (coord) => widget.session.submitTap(coord),
            ),
          ],
        ),
      ),
    );
  }
}

final class _SemanticsGrid extends StatelessWidget {
  const _SemanticsGrid({
    required this.state,
    required this.enabled,
    required this.onTapCell,
  });

  final GameState state;
  final bool enabled;
  final ValueChanged<Coordinate> onTapCell;

  @override
  Widget build(BuildContext context) {
    final n = state.boardSize;
    final blocked = {for (final b in state.blocked) '${b.row}:${b.column}'};
    return Column(
      children: [
        for (var row = 0; row < n; row++)
          Expanded(
            child: Row(
              children: [
                for (var col = 0; col < n; col++)
                  Expanded(
                    child: _CellSemantics(
                      row: row,
                      column: col,
                      piece: state.cells[row][col],
                      blocked: blocked.contains('$row:$col'),
                      enabled: enabled,
                      onTap: () => onTapCell(Coordinate(row: row, column: col)),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

final class _CellSemantics extends StatelessWidget {
  const _CellSemantics({
    required this.row,
    required this.column,
    required this.piece,
    required this.blocked,
    required this.enabled,
    required this.onTap,
  });

  final int row;
  final int column;
  final Piece? piece;
  final bool blocked;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final content = blocked
        ? 'blocked'
        : piece == null
        ? 'empty'
        : PieceGlyph.semanticsLabel(piece!);
    final label = 'Row ${row + 1}, column ${column + 1}, $content';
    return Semantics(
      button: enabled && !blocked,
      enabled: enabled && !blocked,
      label: label,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: enabled && !blocked ? onTap : null,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}
