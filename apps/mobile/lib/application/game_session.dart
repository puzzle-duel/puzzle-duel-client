import 'package:flutter/foundation.dart';
import 'package:puzzle_duel_mobile/application/animation_script.dart';
import 'package:puzzle_duel_mobile/application/challenge_factory.dart';
import 'package:puzzle_duel_mobile/application/game_constants.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

enum GameScreenPhase {
  /// Difficulty picker / home.
  menu,

  /// Active round; accepting selection and taps when not resolving.
  playing,

  /// Engine returned MoveApplied; presentation animating toward finalState.
  resolving,

  /// Round finished (status ended) and settled.
  ended,
}

enum MoveFeedbackKind { none, rejected, unsafe }

/// Immutable view published to presentation.
final class GameSessionView {
  const GameSessionView({
    required this.phase,
    required this.generation,
    required this.activeResolutionId,
    required this.supportedProfiles,
    this.profile,
    this.seed,
    this.canonicalState,
    this.selectedOfferIndex,
    this.activeScript,
    this.feedbackKind = MoveFeedbackKind.none,
    this.feedbackCode,
    this.generationFailure,
  });

  final GameScreenPhase phase;
  final int generation;

  /// Active per-move resolution token, or 0 when not resolving.
  final int activeResolutionId;

  final List<DifficultyProfile> supportedProfiles;
  final DifficultyProfile? profile;
  final int? seed;
  final GameState? canonicalState;
  final int? selectedOfferIndex;
  final AnimationScript? activeScript;
  final MoveFeedbackKind feedbackKind;
  final String? feedbackCode;
  final ChallengeGenerationError? generationFailure;

  bool get isResolving => phase == GameScreenPhase.resolving;
  bool get acceptsInput =>
      phase == GameScreenPhase.playing && canonicalState != null;

  int get score => canonicalState?.score ?? 0;
  int get movesRemaining {
    final state = canonicalState;
    if (state == null) return 0;
    return (state.moveLimit - state.turnsUsed).clamp(0, state.moveLimit);
  }

  bool get isEnded =>
      phase == GameScreenPhase.ended ||
      canonicalState?.status == GameStatus.ended;
}

/// In-memory playable session. Engine is the only gameplay authority.
final class GameSession extends ChangeNotifier {
  GameSession({ChallengeFactory? factory})
    : _factory = factory ?? const ChallengeFactory();

  final ChallengeFactory _factory;

  int _generation = 0;
  int _resolutionSeq = 0;
  int _activeResolutionId = 0;
  GameScreenPhase _phase = GameScreenPhase.menu;
  DifficultyProfile? _profile;
  int? _seed;
  GameState? _canonical;
  int? _selectedOffer;
  AnimationScript? _script;
  MoveFeedbackKind _feedbackKind = MoveFeedbackKind.none;
  String? _feedbackCode;
  ChallengeGenerationError? _generationFailure;

  /// Optional hook for tests: count of applyMove invocations.
  @visibleForTesting
  int applyMoveCallCount = 0;

  /// Injectable applyMove for tests.
  @visibleForTesting
  MoveResult Function(GameState state, Move move)? applyMoveOverride;

  GameSessionView get view => GameSessionView(
    phase: _phase,
    generation: _generation,
    activeResolutionId: _activeResolutionId,
    supportedProfiles: DifficultyProfile.values,
    profile: _profile,
    seed: _seed,
    canonicalState: _canonical,
    selectedOfferIndex: _selectedOffer,
    activeScript: _script,
    feedbackKind: _feedbackKind,
    feedbackCode: _feedbackCode,
    generationFailure: _generationFailure,
  );

  void returnToMenu() {
    _invalidateResolutions();
    _generation += 1;
    _phase = GameScreenPhase.menu;
    _profile = null;
    _seed = null;
    _canonical = null;
    _selectedOffer = null;
    _clearFeedback();
    _generationFailure = null;
    notifyListeners();
  }

  /// Starts a new in-memory round from the accepted generator.
  bool startRound({
    required DifficultyProfile profile,
    int seed = kUatChallengeSeed,
  }) {
    final result = _factory.generate(profile: profile, seed: seed);
    _invalidateResolutions();
    _generation += 1;
    _profile = profile;
    _seed = seed;
    _selectedOffer = null;
    _clearFeedback();
    switch (result) {
      case GeneratedChallenge(:final state):
        _canonical = state;
        _generationFailure = null;
        _phase = state.status == GameStatus.ended
            ? GameScreenPhase.ended
            : GameScreenPhase.playing;
        notifyListeners();
        return true;
      case ChallengeGenerationFailure(:final code):
        _canonical = null;
        _generationFailure = code;
        _phase = GameScreenPhase.menu;
        notifyListeners();
        return false;
    }
  }

  void selectOffer(int index) {
    if (!view.acceptsInput) return;
    if (index < 0 || index > 2) return;
    final offers = _canonical!.offers;
    if (offers[index] == null) return;
    _selectedOffer = index;
    _clearFeedback();
    notifyListeners();
  }

  /// Single serialized move path. Returns false when the tap is ignored.
  bool submitTap(Coordinate tap) {
    if (!view.acceptsInput) return false;
    final selected = _selectedOffer;
    if (selected == null) {
      _feedbackKind = MoveFeedbackKind.rejected;
      _feedbackCode = 'select_offer_first';
      notifyListeners();
      return false;
    }
    if (_canonical!.status == GameStatus.ended) return false;

    final preState = _canonical!;
    final placedPiece = preState.offers[selected];
    if (placedPiece == null) {
      _feedbackKind = MoveFeedbackKind.unsafe;
      _feedbackCode = MoveSafety.offerUnavailable.wire;
      notifyListeners();
      return false;
    }

    final move = Move(offerIndex: selected, tap: tap);
    applyMoveCallCount += 1;
    final apply = applyMoveOverride ?? applyMove;
    final result = apply(preState, move);

    switch (result) {
      case MoveApplied():
        _resolutionSeq += 1;
        _activeResolutionId = _resolutionSeq;
        _canonical = result.finalState;
        _selectedOffer = null;
        _clearFeedback();
        _script = AnimationScript(
          generation: _generation,
          resolutionId: _activeResolutionId,
          preState: preState,
          applied: result,
          placedPiece: placedPiece,
        );
        _phase = GameScreenPhase.resolving;
        notifyListeners();
        return true;
      case MoveRejected(:final code):
        _feedbackKind = MoveFeedbackKind.rejected;
        _feedbackCode = code.wire;
        notifyListeners();
        return true;
      case MoveUnsafe(:final reason):
        _feedbackKind = MoveFeedbackKind.unsafe;
        _feedbackCode = reason.wire;
        notifyListeners();
        return true;
    }
  }

  /// Completes presentation for a specific move resolution.
  ///
  /// Requires both [generation] and [resolutionId] to match the active script.
  /// Duplicate or stale callbacks are no-ops and never unlock a newer move.
  void completeResolution({
    required int generation,
    required int resolutionId,
  }) {
    if (generation != _generation) return;
    if (resolutionId != _activeResolutionId) return;
    if (_phase != GameScreenPhase.resolving) return;
    if (_script == null) return;
    if (_script!.resolutionId != resolutionId) return;

    _script = null;
    _activeResolutionId = 0;
    _phase = _canonical?.status == GameStatus.ended
        ? GameScreenPhase.ended
        : GameScreenPhase.playing;
    notifyListeners();
  }

  /// Skips remaining animation for the active resolution only.
  void skipResolution({required int generation, required int resolutionId}) {
    completeResolution(generation: generation, resolutionId: resolutionId);
  }

  void playAgain() {
    final profile = _profile;
    final seed = _seed ?? kUatChallengeSeed;
    if (profile == null) {
      returnToMenu();
      return;
    }
    startRound(profile: profile, seed: seed);
  }

  void _invalidateResolutions() {
    _script = null;
    _activeResolutionId = 0;
  }

  void _clearFeedback() {
    _feedbackKind = MoveFeedbackKind.none;
    _feedbackCode = null;
  }
}
