import 'dart:async' as async;
import 'dart:ui';

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:puzzle_duel_mobile/application/animation_script.dart';
import 'package:puzzle_duel_mobile/application/presentation_board.dart';
import 'package:puzzle_duel_mobile/presentation/audio/game_sfx.dart';
import 'package:puzzle_duel_mobile/presentation/game/board/board_paint_utils.dart';
import 'package:puzzle_duel_mobile/theme/game_tokens.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

typedef ResolutionComplete = void Function({
  required int generation,
  required int resolutionId,
});

typedef AnimationSfx = void Function(GameSfxEvent event);

final class _FlyingPiece {
  _FlyingPiece({
    required this.piece,
    required this.from,
    required this.to,
    required this.progress,
  });

  final Piece piece;
  final Coordinate from;
  final Coordinate to;
  double progress;
}

/// Flame board renderer. Canonical rules stay in the application layer.
final class PuzzleBoardGame extends FlameGame {
  PuzzleBoardGame({required this.onResolutionComplete, this.onSfx});

  final ResolutionComplete onResolutionComplete;
  final AnimationSfx? onSfx;

  PresentationBoard? _board;
  List<Coordinate> _highlight = const [];
  List<_FlyingPiece> _flying = const [];
  int _generation = 0;
  int _resolutionId = 0;
  async.Timer? _stepTimer;
  List<AnimationStep> _steps = const [];
  int _stepIndex = 0;
  bool _clearedAnyWave = false;
  bool _disposed = false;
  /// Prevents duplicate SFX across reduced-motion, skip, rebuild, or stale work.
  bool _sfxEmittedForResolution = false;
  double _shiftElapsed = 0;
  static const _shiftDuration = 0.28;
  double _placePulse = 1;
  Coordinate? _placeAt;

  Color cellColor = GameTokens.cellEmpty;
  Color blockedColor = GameTokens.cellBlocked;
  Color gridColor = GameTokens.gridLine;
  Color circleFill = GameTokens.circleFill;
  Color diamondFill = GameTokens.diamondFill;
  Color triangleFill = GameTokens.triangleFill;
  Color strokeColor = const Color(0xFF061018);
  Color clearFlash = GameTokens.cellFlash;

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

  void showSettled(
    GameState state, {
    required int generation,
    required int resolutionId,
  }) {
    _cancelTimer();
    _generation = generation;
    _resolutionId = resolutionId;
    _board = PresentationBoard.fromGameState(state);
    _highlight = const [];
    _flying = const [];
    _placeAt = null;
    _placePulse = 1;
    _steps = const [];
    _stepIndex = 0;
  }

  void setReducedMotion(bool value) {
    // Host passes the concrete flag into [playScript].
  }

  void playScript(AnimationScript script, {required bool reducedMotion}) {
    if (_disposed) return;
    _cancelTimer();
    _clearedAnyWave = false;
    _sfxEmittedForResolution = false;
    _generation = script.generation;
    _resolutionId = script.resolutionId;
    _board = PresentationBoard.fromGameState(script.preState);
    _highlight = const [];
    _flying = const [];
    if (reducedMotion) {
      _board = PresentationBoard.fromGameState(script.finalState);
      // Preserve outcome audio from actual MoveApplied waves (no invented clears).
      _emitScriptSfxOnce(script);
      async.scheduleMicrotask(
        () => _finish(
          generation: script.generation,
          resolutionId: script.resolutionId,
        ),
      );
      return;
    }
    _steps = buildAnimationSteps(script);
    _stepIndex = 0;
    _runNextStep();
  }

  void skipToFinal(
    GameState finalState, {
    required int generation,
    required int resolutionId,
  }) {
    if (_disposed) return;
    _cancelTimer();
    _generation = generation;
    _resolutionId = resolutionId;
    _board = PresentationBoard.fromGameState(finalState);
    _highlight = const [];
    _flying = const [];
    // Do not re-fire SFX on skip — animated steps (or reduced-motion emit)
    // already covered what was heard; remaining waves stay silent.
    _sfxEmittedForResolution = true;
    _finish(generation: generation, resolutionId: resolutionId);
  }

  void _emitScriptSfxOnce(AnimationScript script) {
    if (_disposed || _sfxEmittedForResolution) return;
    if (script.generation != _generation ||
        script.resolutionId != _resolutionId) {
      return;
    }
    _sfxEmittedForResolution = true;
    for (final event in sfxEventsForWaves(script.waves.map((w) => w.wave))) {
      onSfx?.call(event);
    }
  }

  void _emitStepSfx(GameSfxEvent event) {
    if (_disposed || _sfxEmittedForResolution) return;
    onSfx?.call(event);
  }

  void disposeGame() {
    _disposed = true;
    _cancelTimer();
  }

  /// Test-only: run presentation steps without a full [AnimationScript].
  @visibleForTesting
  void debugRunSteps(List<AnimationStep> steps) {
    if (_disposed) return;
    _cancelTimer();
    _clearedAnyWave = false;
    _sfxEmittedForResolution = false;
    _generation = 1;
    _resolutionId = 1;
    _highlight = const [];
    _flying = const [];
    _steps = steps;
    _stepIndex = 0;
    _runNextStep();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_placeAt != null && _placePulse < 1.0) {
      _placePulse = (_placePulse + dt * 4.2).clamp(0.0, 1.0);
    }
    if (_flying.isEmpty) return;
    _shiftElapsed += dt;
    final raw = (_shiftElapsed / _shiftDuration).clamp(0.0, 1.0);
    final t = 1 - (1 - raw) * (1 - raw) * (1 - raw);
    for (final flyer in _flying) {
      flyer.progress = t;
    }
    if (raw >= 1.0) {
      final moved = [
        for (final flyer in _flying)
          MovedPiece(
            sourceIndex:
                flyer.from.row * (_board?.boardSize ?? 0) + flyer.from.column,
            from: flyer.from,
            to: flyer.to,
            shape: flyer.piece.shape,
            direction: flyer.piece.direction,
          ),
      ];
      _board?.applyMoves(moved);
      _flying = const [];
      _schedule(Duration.zero);
    }
  }

  void _runNextStep() {
    if (_disposed) return;
    if (_stepIndex >= _steps.length) {
      _finish(generation: _generation, resolutionId: _resolutionId);
      return;
    }
    final step = _steps[_stepIndex++];
    switch (step.kind) {
      case AnimationStepKind.place:
        _board?.place(step.landing!, step.piece!);
        _placeAt = step.landing;
        _placePulse = 0.55;
        _emitStepSfx(GameSfxEvent.place);
        _schedule(const Duration(milliseconds: 260));
      case AnimationStepKind.clearWave:
        _highlight = step.cleared;
        _clearedAnyWave = true;
        _emitStepSfx(sfxForClearWave(step.wave ?? 1));
        _schedule(
          const Duration(milliseconds: 220),
          after: () {
            _board?.clearCells(step.cleared);
            _highlight = const [];
          },
        );
      case AnimationStepKind.shiftWave:
        // Lift pieces off the grid and interpolate presentation-only.
        for (final item in step.moved) {
          _board?.cells[item.from.row][item.from.column] = null;
        }
        _flying = [
          for (final item in step.moved)
            _FlyingPiece(
              piece: Piece(shape: item.shape, direction: item.direction),
              from: item.from,
              to: item.to,
              progress: 0,
            ),
        ];
        _shiftElapsed = 0;
      // Advancement continues from [update] when interpolation completes.
      case AnimationStepKind.settle:
        if (_clearedAnyWave) {
          _emitStepSfx(GameSfxEvent.chainComplete);
        }
        // Mark complete so skip/rebuild cannot duplicate the sequence.
        _sfxEmittedForResolution = true;
        _finish(generation: _generation, resolutionId: _resolutionId);
    }
  }

  void _schedule(Duration delay, {void Function()? after}) {
    _stepTimer = async.Timer(delay, () {
      if (_disposed) return;
      if (_resolutionId == 0) return;
      after?.call();
      _runNextStep();
    });
  }

  void _finish({required int generation, required int resolutionId}) {
    _cancelTimer();
    if (_disposed) return;
    final g = generation;
    final r = resolutionId;
    async.scheduleMicrotask(() {
      if (_disposed) return;
      // Drop if a newer resolution replaced this one while deferred.
      if (g != _generation || r != _resolutionId) return;
      onResolutionComplete(generation: g, resolutionId: r);
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
        if (flash) {
          final spark = Paint()..color = clearFlash.withValues(alpha: 0.9);
          final c = rect.center;
          final r = cell * 0.08;
          canvas.drawCircle(c.translate(-cell * 0.22, -cell * 0.18), r, spark);
          canvas.drawCircle(c.translate(cell * 0.2, -cell * 0.12), r * 0.7, spark);
          canvas.drawCircle(c.translate(0, cell * 0.2), r * 0.85, spark);
        }
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
          final pulse = (_placeAt?.row == row && _placeAt?.column == col)
              ? (0.86 + 0.14 * _placePulse)
              : 1.0;
          _paintPiece(canvas, rect.center, cell * pulse, piece);
        }
      }
    }

    for (final flyer in _flying) {
      final from = Offset(
        originX + (flyer.from.column + 0.5) * cell,
        originY + (flyer.from.row + 0.5) * cell,
      );
      final to = Offset(
        originX + (flyer.to.column + 0.5) * cell,
        originY + (flyer.to.row + 0.5) * cell,
      );
      final pos = Offset.lerp(from, to, flyer.progress)!;
      _paintPiece(canvas, pos, cell, flyer.piece);
    }
  }

  void _paintPiece(Canvas canvas, Offset center, double cell, Piece piece) {
    final fill = switch (piece.shape) {
      Shape.circle => circleFill,
      Shape.diamond => diamondFill,
      Shape.triangle => triangleFill,
    };
    paintPieceGlyph(
      canvas,
      center: center,
      size: cell * 0.9,
      piece: piece,
      fill: fill,
      stroke: strokeColor,
    );
  }
}
