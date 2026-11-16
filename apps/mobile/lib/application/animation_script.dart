import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

/// Presentation-only script derived from a successful [MoveApplied].
final class AnimationScript {
  const AnimationScript({
    required this.generation,
    required this.resolutionId,
    required this.preState,
    required this.applied,
    required this.placedPiece,
  });

  /// Round / session generation. Invalidates work after restart or menu.
  final int generation;

  /// Per-move resolution token. Unique for each accepted [MoveApplied].
  final int resolutionId;

  final GameState preState;
  final MoveApplied applied;
  final Piece placedPiece;

  Coordinate get landing => applied.landing;
  List<WaveResult> get waves => applied.waves;
  GameState get finalState => applied.finalState;
}

/// Steps the UI may play; order is canonical.
enum AnimationStepKind { place, clearWave, shiftWave, settle }

final class AnimationStep {
  const AnimationStep.place(this.landing, this.piece)
    : kind = AnimationStepKind.place,
      wave = null,
      cleared = const [],
      moved = const [];

  const AnimationStep.clear(this.wave, this.cleared)
    : kind = AnimationStepKind.clearWave,
      landing = null,
      piece = null,
      moved = const [];

  const AnimationStep.shift(this.wave, this.moved)
    : kind = AnimationStepKind.shiftWave,
      landing = null,
      piece = null,
      cleared = const [];

  const AnimationStep.settle()
    : kind = AnimationStepKind.settle,
      landing = null,
      piece = null,
      wave = null,
      cleared = const [],
      moved = const [];

  final AnimationStepKind kind;
  final Coordinate? landing;
  final Piece? piece;
  final int? wave;
  final List<Coordinate> cleared;
  final List<MovedPiece> moved;
}

List<AnimationStep> buildAnimationSteps(AnimationScript script) {
  final steps = <AnimationStep>[
    AnimationStep.place(script.landing, script.placedPiece),
  ];
  for (final wave in script.waves) {
    steps.add(AnimationStep.clear(wave.wave, wave.cleared));
    if (wave.moved.isNotEmpty) {
      steps.add(AnimationStep.shift(wave.wave, wave.moved));
    }
  }
  steps.add(const AnimationStep.settle());
  return steps;
}
