/// Documented local testing seed for deterministic UAT (PZD-23).
///
/// Not a production daily-challenge or ranked seed policy.
const int kUatChallengeSeed = 42;

/// Shared Practice / Tournament pause after resolution settles before results
/// or challenge-transition navigation. Reduce Motion skips this beat.
const Duration kResolutionCompletionBeat = Duration(milliseconds: 420);
