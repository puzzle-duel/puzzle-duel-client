/// Semantic kinds for the centralized Top Banner presenter (PZD-54).
enum AppFeedbackKind { info, warning, success }

/// One transient user-facing feedback request owned by the active account scope.
final class AppFeedbackNotice {
  const AppFeedbackNotice({
    required this.generation,
    required this.accountEpoch,
    required this.kind,
    required this.message,
    this.semanticsKey,
  });

  /// Monotonic id so stale timers/animations cannot dismiss a newer banner.
  final int generation;

  /// [TournamentController.accountStateEpoch] at presentation time.
  final int accountEpoch;

  final AppFeedbackKind kind;
  final String message;

  /// Optional widget key (e.g. `auth-logout-success`) for tests/a11y.
  final String? semanticsKey;

  String get signature => '${kind.name}|$message|${semanticsKey ?? ''}';
}
