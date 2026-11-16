part of '../puzzle_duel_rules.dart';

/// Internal fail-closed reasons for [MoveUnsafe].
///
/// These are not [GameplayRejection] transport codes.
enum MoveSafety {
  tapOutOfBounds('tap_out_of_bounds'),
  offerUnavailable('offer_unavailable'),
  unresolvedPreMoveMatch('unresolved_pre_move_match'),
  emptyStreamNotTerminal('empty_stream_not_terminal'),
  earlyBoardEndEmptyStream('early_board_end_empty_stream'),
  cascadeCorrupt('cascade_corrupt'),
  cascadeBoundExceeded('cascade_bound_exceeded'),
  invalidShiftGeometry('invalid_shift_geometry'),
  invalidFinalState('invalid_final_state');

  const MoveSafety(this.wire);

  final String wire;
}

/// One successful clearing wave inside a resolved move.
final class WaveResult {
  WaveResult({
    required this.wave,
    required List<Coordinate> cleared,
    required this.scoreDelta,
    required List<MovedPiece> moved,
  }) : cleared = List<Coordinate>.unmodifiable(cleared),
       moved = List<MovedPiece>.unmodifiable(moved);

  final int wave;
  final List<Coordinate> cleared;
  final int scoreDelta;
  final List<MovedPiece> moved;

  Map<String, Object?> toJson() => {
    'wave': wave,
    'cleared': [for (final cell in cleared) cell.toJson()],
    'scoreDelta': scoreDelta,
    'moved': [for (final piece in moved) piece.toJson()],
  };

  @override
  bool operator ==(Object other) {
    return other is WaveResult &&
        other.wave == wave &&
        other.scoreDelta == scoreDelta &&
        _sameCoordinates(other.cleared, cleared) &&
        _sameMoved(other.moved, moved);
  }

  @override
  int get hashCode => Object.hash(
    wave,
    scoreDelta,
    Object.hashAll(cleared),
    Object.hashAll(moved),
  );
}

/// Result of [applyMove].
sealed class MoveResult {
  const MoveResult();
}

/// Fully resolved legal move. [finalState] is immutable and validated.
final class MoveApplied extends MoveResult {
  MoveApplied({
    required this.landing,
    required this.turnsUsed,
    required this.scoreDelta,
    required List<WaveResult> waves,
    required this.finalState,
  }) : waves = List<WaveResult>.unmodifiable(waves);

  final Coordinate landing;
  final int turnsUsed;
  final int scoreDelta;
  final List<WaveResult> waves;
  final GameState finalState;

  Map<String, Object?> toJson() => {
    'legal': true,
    'landing': landing.toJson(),
    'turnsUsed': turnsUsed,
    'scoreDelta': scoreDelta,
    'waves': [for (final wave in waves) wave.toJson()],
    'finalState': finalState.toJson(),
  };

  @override
  bool operator ==(Object other) {
    return other is MoveApplied &&
        other.landing == landing &&
        other.turnsUsed == turnsUsed &&
        other.scoreDelta == scoreDelta &&
        other.finalState == finalState &&
        _sameWaves(other.waves, waves);
  }

  @override
  int get hashCode => Object.hash(
    landing,
    turnsUsed,
    scoreDelta,
    Object.hashAll(waves),
    finalState,
  );
}

/// Approved gameplay rejection. [state] is the unchanged input.
final class MoveRejected extends MoveResult {
  const MoveRejected({required this.code, required this.state});

  final GameplayRejection code;
  final GameState state;

  Map<String, Object?> toJson() => {
    'legal': false,
    'error': {'code': code.wire},
    'state': state.toJson(),
  };
}

/// Internal fail-closed stop. [state] is the unchanged input.
final class MoveUnsafe extends MoveResult {
  const MoveUnsafe({required this.reason, required this.state});

  final MoveSafety reason;
  final GameState state;
}

bool _sameMoved(List<MovedPiece> left, List<MovedPiece> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _sameWaves(List<WaveResult> left, List<WaveResult> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

int _occupiedCount(List<List<Piece?>> cells) {
  var count = 0;
  for (final row in cells) {
    for (final cell in row) {
      if (cell != null) count += 1;
    }
  }
  return count;
}

List<List<Piece?>> _copyCells(List<List<Piece?>> cells) {
  return [
    for (final row in cells) [for (final cell in row) cell],
  ];
}

List<Piece?> _copyOffers(List<Piece?> offers) {
  return [for (final offer in offers) offer];
}

/// Resolves one complete CORE-001 move: placement, cascades, score, offers, end.
///
/// Never mutates [state]. Rejected and unsafe outcomes return the original
/// snapshot. Successful outcomes validate the constructed final state before
/// returning.
MoveResult applyMove(GameState state, Move move) {
  final placement = applyPlacement(state, move);
  switch (placement) {
    case PlacementRejected(:final code, :final state):
      return MoveRejected(code: code, state: state);
    case PlacementUnsafe(:final reason, :final state):
      return MoveUnsafe(
        reason: switch (reason) {
          PlacementSafety.tapOutOfBounds => MoveSafety.tapOutOfBounds,
          PlacementSafety.offerUnavailable => MoveSafety.offerUnavailable,
        },
        state: state,
      );
    case final PlacementApplied applied:
      // Placement accepted, but a corrupt resume board must not score pre-existing
      // runs as part of this move's cascade. Check the pre-move snapshot only.
      if (state.hasOrthogonalRun) {
        return MoveUnsafe(
          reason: MoveSafety.unresolvedPreMoveMatch,
          state: state,
        );
      }
      switch (_resolveCascades(
        cells: applied.cells,
        blocked: state.blocked,
        original: state,
      )) {
        case _CascadeFail(:final result):
          return result;
        case final _CascadeOk resolved:
          switch (_commitOffers(
            before: state,
            consumption: applied.offerConsumption,
            budgetExhausted: applied.turnsUsed >= state.moveLimit,
            boardFull: _emptyPlayable(resolved.cells, state.blocked) == 0,
          )) {
            case _OfferFail(:final result):
              return result;
            case final _OfferCommit committed:
              return _finishApplied(
                original: state,
                applied: applied,
                resolved: resolved,
                committed: committed,
              );
          }
      }
  }
}

MoveResult _finishApplied({
  required GameState original,
  required PlacementApplied applied,
  required _CascadeOk resolved,
  required _OfferCommit committed,
}) {
  final turnsUsed = applied.turnsUsed;
  final scoreDelta = resolved.scoreDelta;
  final score = original.score + scoreDelta;
  final boardFull = _emptyPlayable(resolved.cells, original.blocked) == 0;
  final budgetExhausted = turnsUsed >= original.moveLimit;
  final status = budgetExhausted || boardFull
      ? GameStatus.ended
      : GameStatus.inProgress;

  if (status == GameStatus.inProgress &&
      committed.offers.any((slot) => slot == null)) {
    return MoveUnsafe(reason: MoveSafety.invalidFinalState, state: original);
  }

  try {
    final finalState = GameState._(
      rulesVersion: original.rulesVersion,
      boardSize: original.boardSize,
      moveLimit: original.moveLimit,
      blocked: original.blocked,
      cells: resolved.cells,
      offers: committed.offers,
      futurePieces: committed.futurePieces,
      turnsUsed: turnsUsed,
      score: score,
      status: status,
    );
    _requireResolvedFinal(finalState);
    return MoveApplied(
      landing: applied.landing,
      turnsUsed: turnsUsed,
      scoreDelta: scoreDelta,
      waves: resolved.waves,
      finalState: finalState,
    );
  } on ValidationFailure {
    return MoveUnsafe(reason: MoveSafety.invalidFinalState, state: original);
  } on StateError {
    return MoveUnsafe(reason: MoveSafety.invalidFinalState, state: original);
  }
}

void _requireResolvedFinal(GameState state) {
  if (state.hasOrthogonalRun) {
    throw StateError('final state still contains a match');
  }
  final parsed = parseGameState(state.toJson());
  if (parsed != state) {
    throw StateError('final state failed round-trip validation');
  }
}

sealed class _CascadeOutcome {
  const _CascadeOutcome();
}

final class _CascadeFail extends _CascadeOutcome {
  const _CascadeFail(this.result);

  final MoveUnsafe result;
}

final class _CascadeOk extends _CascadeOutcome {
  _CascadeOk({
    required List<List<Piece?>> cells,
    required List<WaveResult> waves,
    required this.scoreDelta,
  }) : cells = _freezeCells(cells),
       waves = List<WaveResult>.unmodifiable(waves);

  final List<List<Piece?>> cells;
  final List<WaveResult> waves;
  final int scoreDelta;
}

_CascadeOutcome _resolveCascades({
  required List<List<Piece?>> cells,
  required List<Coordinate> blocked,
  required GameState original,
}) {
  var board = _copyCells(cells);
  final waves = <WaveResult>[];
  final maxWaves = _occupiedCount(board) ~/ 3;

  MoveUnsafe fail(MoveSafety reason) =>
      MoveUnsafe(reason: reason, state: original);

  while (true) {
    late final MatchClearResult match;
    try {
      match = clearMatches(board);
    } on ValidationFailure {
      return _CascadeFail(fail(MoveSafety.invalidShiftGeometry));
    }
    if (!match.foundMatch) break;

    if (waves.length >= maxWaves) {
      return _CascadeFail(fail(MoveSafety.cascadeBoundExceeded));
    }
    if (match.uniqueClearedCount < 3) {
      return _CascadeFail(fail(MoveSafety.cascadeCorrupt));
    }

    final before = _occupiedCount(board);
    final afterClear = match.cells;
    if (_occupiedCount(afterClear) != before - match.uniqueClearedCount) {
      return _CascadeFail(fail(MoveSafety.cascadeCorrupt));
    }

    late final ShiftResult shift;
    try {
      shift = applyShift(afterClear, blocked: blocked);
    } on ValidationFailure {
      return _CascadeFail(fail(MoveSafety.invalidShiftGeometry));
    } on StateError {
      return _CascadeFail(fail(MoveSafety.cascadeCorrupt));
    }

    if (_occupiedCount(shift.cells) != before - match.uniqueClearedCount) {
      return _CascadeFail(fail(MoveSafety.cascadeCorrupt));
    }

    final waveNumber = waves.length + 1;
    final waveScore = match.uniqueClearedCount * 100 * waveNumber;
    waves.add(
      WaveResult(
        wave: waveNumber,
        cleared: match.cleared,
        scoreDelta: waveScore,
        moved: shift.moved,
      ),
    );
    board = _copyCells(shift.cells);
  }

  return _CascadeOk(
    cells: board,
    waves: waves,
    scoreDelta: waves.fold<int>(0, (sum, wave) => sum + wave.scoreDelta),
  );
}

sealed class _OfferOutcome {
  const _OfferOutcome();
}

final class _OfferFail extends _OfferOutcome {
  const _OfferFail(this.result);

  final MoveUnsafe result;
}

final class _OfferCommit extends _OfferOutcome {
  _OfferCommit({
    required List<Piece?> offers,
    required List<Piece> futurePieces,
  }) : offers = List<Piece?>.unmodifiable(offers),
       futurePieces = List<Piece>.unmodifiable(futurePieces);

  final List<Piece?> offers;
  final List<Piece> futurePieces;
}

_OfferOutcome _commitOffers({
  required GameState before,
  required OfferConsumption consumption,
  required bool budgetExhausted,
  required bool boardFull,
}) {
  switch (consumption) {
    case OfferWillReplace(
      :final offerIndex,
      :final replacement,
      :final remainingFuture,
    ):
      final offers = _copyOffers(before.offers);
      offers[offerIndex] = replacement;
      return _OfferCommit(offers: offers, futurePieces: remainingFuture);
    case OfferReplacementDeferred(:final offerIndex):
      switch (before.rulesVersion) {
        case RulesVersion.core001V1:
          return _OfferFail(
            MoveUnsafe(
              reason: MoveSafety.emptyStreamNotTerminal,
              state: before,
            ),
          );
        case RulesVersion.core001V2:
          if (budgetExhausted) {
            final offers = _copyOffers(before.offers);
            offers[offerIndex] = null;
            return _OfferCommit(offers: offers, futurePieces: const []);
          }
          if (boardFull) {
            return _OfferFail(
              MoveUnsafe(
                reason: MoveSafety.earlyBoardEndEmptyStream,
                state: before,
              ),
            );
          }
          return _OfferFail(
            MoveUnsafe(
              reason: MoveSafety.emptyStreamNotTerminal,
              state: before,
            ),
          );
      }
  }
}
