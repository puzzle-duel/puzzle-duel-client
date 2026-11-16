import 'dart:async' as async;
import 'dart:ui';

import 'package:flame/game.dart';
import 'package:puzzle_duel_mobile/application/animation_script.dart';
import 'package:puzzle_duel_mobile/application/presentation_board.dart';
import 'package:puzzle_duel_mobile/presentation/game/board/board_paint_utils.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

typedef ResolutionComplete = void Function(int generation);

/// Flame board renderer. Canonical rules stay in the application layer.
final class PuzzleBoardGame extends FlameGame {
  PuzzleBoardGame({required this.onResolutionComplete});

  final ResolutionComplete onResolutionComplete;

  PresentationBoard? _board;
  List<Coordinate> _highlight = const [];
  int _generation = 0;
  async.Timer? _stepTimer;
  List<AnimationStep> _steps = const [];
  int _stepIndex = 0;
  bool _disposed = false;

  Color cellColor = const Color(0xFFE8F0EC);
  Color blockedColor = const Color(0xFF9AA5A0);
  Color gridColor = const Color(0xFF5C6B64);
  Color circleFill = const Color(0xFF1B4D3E);
  Color diamondFill = const Color(0xFF5B3A8C);
  Color triangleFill = const Color(0xFF8A5A1E);
  Color strokeColor = const Color(0xFF122018);
  Color clearFlash = const Color(0xFFFFF3B0);

  void configurePalette({
    required Color cell,
    required Color blocked,
    required Color grid,
    required Color circle,
    required Color diamond,
    required Color triangle,
    required Color stroke,
    required Color flash,
  }) {
    cellColor = cell;
    blockedColor = blocked;
    gridColor = grid;
    circleFill = circle;
    diamondFill = diamond;
    triangleFill = triangle;
    strokeColor = stroke;
    clearFlash = flash;
  }

  void showSettled(GameState state, {required int generation}) {
    _cancelTimer();
    _generation = generation;
    _board = PresentationBoard.fromGameState(state);
    _highlight = const [];
    _steps = const [];
    _stepIndex = 0;
  }

  void setReducedMotion(bool value) {
    // Tracked by the host widget; playScript receives the concrete flag.
  }

  void playScript(AnimationScript script, {required bool reducedMotion}) {
    if (_disposed) return;
    _cancelTimer();
    _generation = script.generation;
    _board = PresentationBoard.fromGameState(script.preState);
    _highlight = const [];
    if (reducedMotion) {
      _board = PresentationBoard.fromGameState(script.finalState);
      // Defer so callers are not notified during widget build.
      async.scheduleMicrotask(() => _finish(script.generation));
      return;
    }
    _steps = buildAnimationSteps(script);
    _stepIndex = 0;
    _runNextStep();
  }

  void skipToFinal(GameState finalState, {required int generation}) {
    if (_disposed) return;
    _cancelTimer();
    _generation = generation;
    _board = PresentationBoard.fromGameState(finalState);
    _highlight = const [];
    _finish(generation);
  }

  void disposeGame() {
    _disposed = true;
    _cancelTimer();
  }

  void _runNextStep() {
    if (_disposed) return;
    if (_stepIndex >= _steps.length) {
      _finish(_generation);
      return;
    }
    final step = _steps[_stepIndex++];
    switch (step.kind) {
      case AnimationStepKind.place:
        _board?.place(step.landing!, step.piece!);
        _schedule(const Duration(milliseconds: 220));
      case AnimationStepKind.clearWave:
        _highlight = step.cleared;
        _schedule(
          const Duration(milliseconds: 180),
          after: () {
            _board?.clearCells(step.cleared);
            _highlight = const [];
          },
        );
      case AnimationStepKind.shiftWave:
        _board?.applyMoves(step.moved);
        _schedule(const Duration(milliseconds: 240));
      case AnimationStepKind.settle:
        _finish(_generation);
    }
  }

  void _schedule(Duration delay, {void Function()? after}) {
    _stepTimer = async.Timer(delay, () {
      after?.call();
      _runNextStep();
    });
  }

  void _finish(int generation) {
    _cancelTimer();
    if (_disposed) return;
    // Always defer: reduced-motion path may run during build/layout.
    async.scheduleMicrotask(() {
      if (_disposed) return;
      onResolutionComplete(generation);
    });
  }

  void _cancelTimer() {
    _stepTimer?.cancel();
    _stepTimer = null;
  }

  @override
  Color backgroundColor() => const Color(0x00000000);

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final board = _board;
    if (board == null) return;
    final size = board.boardSize;
    final w = canvasSize.x;
    final h = canvasSize.y;
    final cell = (w < h ? w : h) / size;
    final originX = (w - cell * size) / 2;
    final originY = (h - cell * size) / 2;

    for (var row = 0; row < size; row++) {
      for (var col = 0; col < size; col++) {
        final rect = Rect.fromLTWH(
          originX + col * cell,
          originY + row * cell,
          cell,
          cell,
        );
        final blocked = board.isBlocked(row, col);
        final flash = _highlight.any((c) => c.row == row && c.column == col);
        final paint = Paint()
          ..color = flash ? clearFlash : (blocked ? blockedColor : cellColor);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.deflate(1.5), const Radius.circular(6)),
          paint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.deflate(1.5), const Radius.circular(6)),
          Paint()
            ..color = gridColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
        if (blocked) {
          final p = Paint()
            ..color = strokeColor.withValues(alpha: 0.55)
            ..strokeWidth = 2;
          canvas.drawLine(
            Offset(rect.left + 8, rect.top + 8),
            Offset(rect.right - 8, rect.bottom - 8),
            p,
          );
          canvas.drawLine(
            Offset(rect.right - 8, rect.top + 8),
            Offset(rect.left + 8, rect.bottom - 8),
            p,
          );
          continue;
        }
        final piece = board.pieceAt(row, col);
        if (piece != null) {
          final fill = switch (piece.shape) {
            Shape.circle => circleFill,
            Shape.diamond => diamondFill,
            Shape.triangle => triangleFill,
          };
          paintPieceGlyph(
            canvas,
            center: rect.center,
            size: cell * 0.82,
            piece: piece,
            fill: fill,
            stroke: strokeColor,
          );
        }
      }
    }
  }

  /// Maps a local board offset to a coordinate, or null if outside.
  Coordinate? coordinateAt(Offset local) {
    final board = _board;
    if (board == null) return null;
    final size = board.boardSize;
    final w = canvasSize.x;
    final h = canvasSize.y;
    final cell = (w < h ? w : h) / size;
    final originX = (w - cell * size) / 2;
    final originY = (h - cell * size) / 2;
    final col = ((local.dx - originX) / cell).floor();
    final row = ((local.dy - originY) / cell).floor();
    if (row < 0 || col < 0 || row >= size || col >= size) return null;
    return Coordinate(row: row, column: col);
  }
}
