import 'package:flame/game.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/application/animation_script.dart';
import 'package:puzzle_duel_mobile/application/game_session.dart';
import 'package:puzzle_duel_mobile/presentation/audio/game_sfx_scope.dart';
import 'package:puzzle_duel_mobile/presentation/game/board/puzzle_board_game.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/piece_glyph.dart';
import 'package:puzzle_duel_mobile/theme/game_tokens.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

/// Flame visual board with a Flutter semantics/input overlay.
final class AccessibleBoard extends StatefulWidget {
  const AccessibleBoard({
    super.key,
    required this.session,
    required this.view,
    this.showPlacementPreview = false,
  });

  final GameSession session;
  final GameSessionView view;

  /// Highlights empty legal taps for the selected piece. Off unless a caller
  /// opts in, so existing board goldens keep their pixels.
  final bool showPlacementPreview;

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
      onResolutionComplete: ({required generation, required resolutionId}) {
        widget.session.completeResolution(
          generation: generation,
          resolutionId: resolutionId,
        );
      },
      onSfx: (event) {
        if (!mounted) return;
        GameSfxScope.maybeOf(context)?.play(event);
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
    _game.configurePalette(
      cell: GameTokens.cellEmpty,
      blocked: GameTokens.cellBlocked,
      grid: GameTokens.gridLine,
      circle: GameTokens.circleFill,
      diamond: GameTokens.diamondFill,
      triangle: GameTokens.triangleFill,
      stroke: const Color(0xFF061018),
      flash: GameTokens.cellFlash,
    );
  }

  void _syncBoard() {
    final view = widget.view;
    final state = view.canonicalState;
    if (state == null) return;

    final reducedMotion = _reducedMotion;
    _game.setReducedMotion(reducedMotion);

    final script = view.activeScript;
    if (view.isResolving && script != null) {
      final same =
          _playing != null &&
          _playing!.generation == script.generation &&
          _playing!.resolutionId == script.resolutionId;
      if (!same) {
        _playing = script;
        _game.playScript(script, reducedMotion: reducedMotion);
      }
      return;
    }

    if (!view.isResolving) {
      // Skip path: settle visuals to canonical final before clearing script id.
      if (_playing != null) {
        _game.showSettled(state, generation: view.generation, resolutionId: 0);
      } else {
        _game.showSettled(state, generation: view.generation, resolutionId: 0);
      }
      _playing = null;
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

    // Interactive labels must reflect the pre-move board while resolving so
    // that "empty" semantics are not rewritten by the committed finalState.
    // Input is disabled during resolving; settled play uses canonical state.
    final interactionState =
        widget.view.isResolving && widget.view.activeScript != null
        ? widget.view.activeScript!.preState
        : state;

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        return Center(
          child: SizedBox(
            width: side,
            height: side,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: GameTokens.bgDeep.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(GameTokens.radiusMd),
                border: Border.all(color: GameTokens.borderBright, width: 1.4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Semantics(
                  label:
                      'Puzzle board, ${state.boardSize} by ${state.boardSize}',
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      IgnorePointer(child: GameWidget(game: _game)),
                      _SemanticsGrid(
                        state: interactionState,
                        enabled: widget.view.acceptsInput,
                        previewOfferIndex: widget.showPlacementPreview
                            ? widget.view.selectedOfferIndex
                            : null,
                        onTapCell: (coord) => widget.session.submitTap(coord),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

final class _SemanticsGrid extends StatelessWidget {
  const _SemanticsGrid({
    required this.state,
    required this.enabled,
    required this.previewOfferIndex,
    required this.onTapCell,
  });

  final GameState state;
  final bool enabled;
  final int? previewOfferIndex;
  final ValueChanged<Coordinate> onTapCell;

  @override
  Widget build(BuildContext context) {
    final n = state.boardSize;
    final blocked = {for (final b in state.blocked) '${b.row}:${b.column}'};
    final selected = previewOfferIndex;
    final piece = selected == null || selected < 0 || selected >= state.offers.length
        ? null
        : state.offers[selected].pieceOrNull;
    return Column(
      children: [
        for (var row = 0; row < n; row++)
          Expanded(
            child: Row(
              children: [
                for (var col = 0; col < n; col++)
                  Expanded(
                    child: _CellSemantics(
                      key: ValueKey('board-cell-$row-$col'),
                      row: row,
                      column: col,
                      piece: state.cells[row][col],
                      blocked: blocked.contains('$row:$col'),
                      legalPreview: piece != null &&
                          canPlaceAt(
                            boardSize: state.boardSize,
                            cells: state.cells,
                            blocked: state.blocked,
                            piece: piece,
                            tap: Coordinate(row: row, column: col),
                          ),
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
    super.key,
    required this.row,
    required this.column,
    required this.piece,
    required this.blocked,
    required this.legalPreview,
    required this.enabled,
    required this.onTap,
  });

  final int row;
  final int column;
  final Piece? piece;
  final bool blocked;
  final bool legalPreview;
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
          key: ValueKey('board-ink-$row-$column'),
          onTap: enabled && !blocked ? onTap : null,
          child: legalPreview
              ? DecoratedBox(
                  key: ValueKey('board-legal-$row-$column'),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: GameTokens.accent.withValues(alpha: 0.85),
                      width: 1.2,
                    ),
                  ),
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: GameTokens.accent.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                      ),
                      child: const SizedBox(width: 7, height: 7),
                    ),
                  ),
                )
              : const SizedBox.expand(),
        ),
      ),
    );
  }
}
