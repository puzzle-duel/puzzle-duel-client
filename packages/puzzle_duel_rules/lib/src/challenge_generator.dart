part of '../puzzle_duel_rules.dart';

/// Accepted generator algorithm id (GEN-02).
enum GeneratorVersion {
  gen001V1('gen-001.v1');

  const GeneratorVersion(this.id);

  final String id;

  static GeneratorVersion? tryParse(Object? value) {
    for (final version in values) {
      if (version.id == value) return version;
    }
    return null;
  }
}

/// MVP difficulty profiles (PD-06 / GEN-03). Not empirically validated ratings.
enum DifficultyProfile {
  easy(
    wire: 'easy',
    boardSize: 5,
    moveLimit: 15,
    obstacleCount: 1,
    occupiedCount: 6,
  ),
  medium(
    wire: 'medium',
    boardSize: 6,
    moveLimit: 12,
    obstacleCount: 2,
    occupiedCount: 10,
  ),
  hard(
    wire: 'hard',
    boardSize: 7,
    moveLimit: 10,
    obstacleCount: 4,
    occupiedCount: 16,
  );

  const DifficultyProfile({
    required this.wire,
    required this.boardSize,
    required this.moveLimit,
    required this.obstacleCount,
    required this.occupiedCount,
  });

  final String wire;
  final int boardSize;
  final int moveLimit;
  final int obstacleCount;
  final int occupiedCount;

  static DifficultyProfile? tryParse(Object? value) {
    for (final profile in values) {
      if (profile.wire == value) return profile;
    }
    return null;
  }
}

/// Immutable generation request. Defaults match Accepted Easy/Medium/Hard.
final class ChallengeGenerationConfig {
  const ChallengeGenerationConfig({
    required this.profile,
    this.generatorVersion = GeneratorVersion.gen001V1,
    this.rulesVersion = RulesVersion.core001V2,
    this.boardSize,
    this.moveLimit,
    this.obstacleCount,
    this.occupiedCount,
  });

  factory ChallengeGenerationConfig.profile(DifficultyProfile profile) {
    return ChallengeGenerationConfig(profile: profile);
  }

  final DifficultyProfile profile;
  final GeneratorVersion generatorVersion;
  final RulesVersion rulesVersion;
  final int? boardSize;
  final int? moveLimit;
  final int? obstacleCount;
  final int? occupiedCount;

  int get resolvedBoardSize => boardSize ?? profile.boardSize;
  int get resolvedMoveLimit => moveLimit ?? profile.moveLimit;
  int get resolvedObstacleCount => obstacleCount ?? profile.obstacleCount;
  int get resolvedOccupiedCount => occupiedCount ?? profile.occupiedCount;

  Map<String, Object?> toJson() => {
    'boardSize': resolvedBoardSize,
    'moveLimit': resolvedMoveLimit,
    'obstacleCount': resolvedObstacleCount,
    'occupiedCount': resolvedOccupiedCount,
  };
}

/// Typed fail-closed generation errors (GEN-05).
enum ChallengeGenerationError {
  invalidConfig('invalid_config'),
  generationExhausted('generation_exhausted');

  const ChallengeGenerationError(this.wire);

  final String wire;
}

/// Result of [generateChallenge].
sealed class ChallengeGenerationResult {
  const ChallengeGenerationResult();
}

final class ChallengeGenerationFailure extends ChallengeGenerationResult {
  const ChallengeGenerationFailure(this.code);

  final ChallengeGenerationError code;
}

/// Deterministic challenge with outer generator metadata (GEN-07).
final class GeneratedChallenge extends ChallengeGenerationResult {
  GeneratedChallenge({
    required this.generatorVersion,
    required this.rulesVersion,
    required this.seed,
    required this.profile,
    required this.config,
    required this.state,
  });

  final GeneratorVersion generatorVersion;
  final RulesVersion rulesVersion;
  final int seed;
  final DifficultyProfile profile;
  final ChallengeGenerationConfig config;
  final GameState state;

  Map<String, Object?> toJson() => {
    'generatorVersion': generatorVersion.id,
    'rulesVersion': rulesVersion.id,
    'seed': seed,
    'profile': profile.wire,
    'config': config.toJson(),
    'blocked': [for (final cell in state.blocked) cell.toJson()],
    'cells': [
      for (final row in state.cells) [for (final cell in row) cell?.toJson()],
    ],
    'offers': [for (final offer in state.offers) offer.toJsonFor(rulesVersion)],
    'futurePieces': [for (final piece in state.futurePieces) piece.toJson()],
    'turnsUsed': state.turnsUsed,
    'score': state.score,
    'status': state.status.wire,
  };
}

const _shapes = [Shape.circle, Shape.diamond, Shape.triangle];
const _directions = [
  Direction.up,
  Direction.right,
  Direction.down,
  Direction.left,
];

const int defaultMaxGenerationAttempts = 256;

/// Accepted `gen-001.v1` challenge generator.
///
/// [maxAttempts] defaults to 256. Overriding it is a test seam only; production
/// callers must keep the Accepted constant.
ChallengeGenerationResult generateChallenge(
  ChallengeGenerationConfig config,
  int seed, {
  int maxAttempts = defaultMaxGenerationAttempts,
}) {
  final validation = _validateConfig(config, seed, maxAttempts);
  if (validation != null) return validation;

  final boardSize = config.resolvedBoardSize;
  final moveLimit = config.resolvedMoveLimit;
  final obstacleCount = config.resolvedObstacleCount;
  final occupiedCount = config.resolvedOccupiedCount;

  final rng = Pcg32()..seed32(seed);
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    final board = _tryBuildBoard(
      rng: rng,
      boardSize: boardSize,
      obstacleCount: obstacleCount,
      occupiedCount: occupiedCount,
    );
    if (board == null) continue;

    final supplyLength = moveLimit + 2;
    final supply = <Piece>[
      for (var index = 0; index < supplyLength; index++) _drawPiece(rng),
    ];
    final offers = List<OfferSlot>.unmodifiable([
      for (final piece in supply.sublist(0, 3)) OfferLive(piece),
    ]);
    final future = List<Piece>.unmodifiable(supply.sublist(3));

    final state = GameState._(
      rulesVersion: config.rulesVersion,
      boardSize: boardSize,
      moveLimit: moveLimit,
      blocked: board.blocked,
      cells: board.cells,
      offers: offers,
      futurePieces: future,
      turnsUsed: 0,
      score: 0,
      status: GameStatus.inProgress,
      terminalReason: null,
    );

    try {
      final parsed = parseInitialGameState(state.toJson());
      if (parsed != state) {
        continue;
      }
    } on ValidationFailure {
      continue;
    }

    if (_emptyPlayable(state.cells, state.blocked) < 1) {
      continue;
    }
    if (state.offers.length != 3 ||
        state.offers.any((slot) => slot is! OfferLive)) {
      continue;
    }
    if (state.futurePieces.length != moveLimit - 1) {
      // supplyLength = moveLimit + 2 → future = moveLimit - 1
      continue;
    }

    return GeneratedChallenge(
      generatorVersion: config.generatorVersion,
      rulesVersion: config.rulesVersion,
      seed: seed,
      profile: config.profile,
      config: config,
      state: state,
    );
  }

  return const ChallengeGenerationFailure(
    ChallengeGenerationError.generationExhausted,
  );
}

ChallengeGenerationFailure? _validateConfig(
  ChallengeGenerationConfig config,
  int seed,
  int maxAttempts,
) {
  if (maxAttempts < 1) {
    return const ChallengeGenerationFailure(
      ChallengeGenerationError.invalidConfig,
    );
  }
  if (seed < 0 || seed > 4294967295) {
    return const ChallengeGenerationFailure(
      ChallengeGenerationError.invalidConfig,
    );
  }
  if (config.generatorVersion != GeneratorVersion.gen001V1) {
    return const ChallengeGenerationFailure(
      ChallengeGenerationError.invalidConfig,
    );
  }
  if (config.rulesVersion != RulesVersion.core001V2) {
    return const ChallengeGenerationFailure(
      ChallengeGenerationError.invalidConfig,
    );
  }

  final boardSize = config.resolvedBoardSize;
  final moveLimit = config.resolvedMoveLimit;
  final obstacleCount = config.resolvedObstacleCount;
  final occupiedCount = config.resolvedOccupiedCount;
  final cells = boardSize * boardSize;

  if (boardSize != config.profile.boardSize ||
      moveLimit != config.profile.moveLimit ||
      obstacleCount != config.profile.obstacleCount ||
      occupiedCount != config.profile.occupiedCount) {
    // Accepted gen-001.v1 only ships the three exact profiles.
    return const ChallengeGenerationFailure(
      ChallengeGenerationError.invalidConfig,
    );
  }
  if (boardSize < 1 ||
      moveLimit < 1 ||
      obstacleCount < 0 ||
      occupiedCount < 0) {
    return const ChallengeGenerationFailure(
      ChallengeGenerationError.invalidConfig,
    );
  }
  if (obstacleCount >= cells) {
    return const ChallengeGenerationFailure(
      ChallengeGenerationError.invalidConfig,
    );
  }
  final free = cells - obstacleCount;
  if (occupiedCount > free) {
    return const ChallengeGenerationFailure(
      ChallengeGenerationError.invalidConfig,
    );
  }
  if (free - occupiedCount < 1) {
    return const ChallengeGenerationFailure(
      ChallengeGenerationError.invalidConfig,
    );
  }
  return null;
}

final class _BoardAttempt {
  _BoardAttempt({required List<Coordinate> blocked, required this.cells})
    : blocked = List<Coordinate>.unmodifiable(blocked);

  final List<Coordinate> blocked;
  final List<List<Piece?>> cells;
}

_BoardAttempt? _tryBuildBoard({
  required Pcg32 rng,
  required int boardSize,
  required int obstacleCount,
  required int occupiedCount,
}) {
  final cells = _allCells(boardSize);
  final blockedSelected = _selectK(rng, cells, obstacleCount);
  final blocked = [...blockedSelected]
    ..sort((left, right) {
      final byRow = left.row.compareTo(right.row);
      return byRow != 0 ? byRow : left.column.compareTo(right.column);
    });
  final blockedKeys = {
    for (final cell in blocked) '${cell.row},${cell.column}',
  };
  final free = [
    for (final cell in cells)
      if (!blockedKeys.contains('${cell.row},${cell.column}')) cell,
  ];
  final occupiedSelected = _selectK(rng, free, occupiedCount);
  final grid = [
    for (var row = 0; row < boardSize; row++)
      [for (var column = 0; column < boardSize; column++) null as Piece?],
  ];
  for (final cell in occupiedSelected) {
    grid[cell.row][cell.column] = _drawPiece(rng);
  }
  if (_orthogonalRun(grid)) return null;
  return _BoardAttempt(blocked: blocked, cells: grid);
}

List<Coordinate> _allCells(int boardSize) {
  return [
    for (var row = 0; row < boardSize; row++)
      for (var column = 0; column < boardSize; column++)
        Coordinate._(row, column),
  ];
}

List<T> _selectK<T>(Pcg32 rng, List<T> pool, int k) {
  final work = List<T>.of(pool);
  final m = work.length;
  if (k < 0 || k > m) {
    throw StateError('selectK bounds');
  }
  for (var i = 0; i < k; i++) {
    final j = i + rng.randBound(m - i);
    final tmp = work[i];
    work[i] = work[j];
    work[j] = tmp;
  }
  return work.sublist(0, k);
}

Piece _drawPiece(Pcg32 rng) {
  return Piece(
    shape: _shapes[rng.randBound(3)],
    direction: _directions[rng.randBound(4)],
  );
}
