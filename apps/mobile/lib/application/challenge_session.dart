import 'package:flutter/foundation.dart';
import 'package:puzzle_duel_mobile/application/challenge_factory.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

/// Immutable view of the latest generator smoke-test outcome.
final class ChallengeSessionSnapshot {
  const ChallengeSessionSnapshot({
    required this.ready,
    this.lastProfile,
    this.lastSeed,
    this.lastChallenge,
    this.lastFailure,
    this.lastErrorMessage,
  });

  /// Application shell is ready; no network or auth wait.
  final bool ready;

  final DifficultyProfile? lastProfile;
  final int? lastSeed;
  final GeneratedChallenge? lastChallenge;
  final ChallengeGenerationError? lastFailure;
  final String? lastErrorMessage;

  bool get hasChallenge => lastChallenge != null;
  bool get hasFailure => lastFailure != null;

  ChallengeSessionSnapshot copyWith({
    bool? ready,
    DifficultyProfile? lastProfile,
    int? lastSeed,
    GeneratedChallenge? lastChallenge,
    ChallengeGenerationError? lastFailure,
    String? lastErrorMessage,
    bool clearChallenge = false,
    bool clearFailure = false,
  }) {
    return ChallengeSessionSnapshot(
      ready: ready ?? this.ready,
      lastProfile: lastProfile ?? this.lastProfile,
      lastSeed: lastSeed ?? this.lastSeed,
      lastChallenge: clearChallenge ? null : (lastChallenge ?? this.lastChallenge),
      lastFailure: clearFailure ? null : (lastFailure ?? this.lastFailure),
      lastErrorMessage: clearFailure
          ? null
          : (lastErrorMessage ?? this.lastErrorMessage),
    );
  }
}

/// Application-layer session. Owns an immutable snapshot; does not mutate
/// engine [GameState] objects returned by the generator.
final class ChallengeSession extends ChangeNotifier {
  ChallengeSession({
    ChallengeFactory? factory,
    ChallengeSessionSnapshot? initial,
  }) : _factory = factory ?? const ChallengeFactory(),
       _snapshot = initial ?? const ChallengeSessionSnapshot(ready: true);

  final ChallengeFactory _factory;
  ChallengeSessionSnapshot _snapshot;

  ChallengeSessionSnapshot get snapshot => _snapshot;

  /// Supported MVP profiles from Accepted generator contracts.
  List<DifficultyProfile> get supportedProfiles => DifficultyProfile.values;

  /// Invokes the accepted generator. Preserves typed failure semantics.
  void runGeneratorSmokeTest({
    required DifficultyProfile profile,
    required int seed,
  }) {
    final result = _factory.generate(profile: profile, seed: seed);
    switch (result) {
      case GeneratedChallenge():
        _snapshot = ChallengeSessionSnapshot(
          ready: true,
          lastProfile: profile,
          lastSeed: seed,
          lastChallenge: result,
        );
      case ChallengeGenerationFailure(:final code):
        _snapshot = ChallengeSessionSnapshot(
          ready: true,
          lastProfile: profile,
          lastSeed: seed,
          lastFailure: code,
          lastErrorMessage: code.wire,
        );
    }
    notifyListeners();
  }

  /// Test/injection seam for presenting a failure without calling the engine.
  @visibleForTesting
  void injectFailure(ChallengeGenerationError code) {
    _snapshot = ChallengeSessionSnapshot(
      ready: true,
      lastFailure: code,
      lastErrorMessage: code.wire,
    );
    notifyListeners();
  }
}
