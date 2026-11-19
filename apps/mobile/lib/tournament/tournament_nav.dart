/// Explicit tournament destinations. Refreshing a claim is not navigation.
enum TournamentPlace {
  home,
  overview,
  playing,
  transition,
  results,
  daily,
  weekly,
  recovery,
}

enum DayPhase { unknown, ready, inProgress, betweenGames, completed }

const Map<int, String> tournamentOrdinalLabels = {
  1: 'E1',
  2: 'E2',
  3: 'E3',
  4: 'M1',
  5: 'M2',
  6: 'H1',
};

String? nextOrdinalLabel(int? ordinal) {
  if (ordinal == null) return null;
  return tournamentOrdinalLabels[ordinal + 1];
}

/// Where Back goes. Leaderboards remember the screen that opened them.
final class TournamentRoute {
  const TournamentRoute({
    this.place = TournamentPlace.home,
    this.leaderboardReturn,
  });

  final TournamentPlace place;
  final TournamentPlace? leaderboardReturn;

  TournamentRoute open(TournamentPlace next) {
    if (next == TournamentPlace.daily || next == TournamentPlace.weekly) {
      if (place == TournamentPlace.daily || place == TournamentPlace.weekly) {
        return TournamentRoute(
          place: next,
          leaderboardReturn: leaderboardReturn,
        );
      }
      final from =
          place == TournamentPlace.results ||
              place == TournamentPlace.home ||
              place == TournamentPlace.overview
          ? place
          : TournamentPlace.home;
      return TournamentRoute(place: next, leaderboardReturn: from);
    }
    return TournamentRoute(place: next);
  }

  /// Back never reopens Results just because today's series is complete.
  TournamentRoute back() {
    switch (place) {
      case TournamentPlace.daily:
      case TournamentPlace.weekly:
        final dest = leaderboardReturn;
        if (dest == TournamentPlace.results ||
            dest == TournamentPlace.overview) {
          return TournamentRoute(place: dest!);
        }
        return const TournamentRoute();
      case TournamentPlace.home:
        return this;
      case TournamentPlace.overview:
      case TournamentPlace.playing:
      case TournamentPlace.transition:
      case TournamentPlace.results:
      case TournamentPlace.recovery:
        return const TournamentRoute();
    }
  }
}

int? tournamentInt(Object? value) => value is num ? value.toInt() : null;

Map<String, Object?>? tournamentMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return null;
}

/// Server snapshot for today's series. It does not choose a screen.
final class TournamentDay {
  const TournamentDay({
    required this.seriesId,
    required this.original,
    required this.claimStatus,
    this.ordinal,
    this.ordinalLabel,
    this.seriesScore,
    this.gameScore,
    this.awaitAdvance = false,
    this.resultsPublished = false,
    this.terminalReason,
    this.turnsUsed,
    this.moveLimit,
    this.boardSize,
  });

  final String seriesId;
  final bool original;
  final String claimStatus;
  final int? ordinal;
  final String? ordinalLabel;
  final int? seriesScore;
  final int? gameScore;
  final bool awaitAdvance;
  final bool resultsPublished;
  final String? terminalReason;
  final int? turnsUsed;
  final int? moveLimit;
  final int? boardSize;

  DayPhase get phase {
    if (resultsPublished || claimStatus == 'COMPLETED')
      return DayPhase.completed;
    if (awaitAdvance) return DayPhase.betweenGames;
    if ((ordinal ?? 1) == 1 && (turnsUsed ?? 0) == 0) return DayPhase.ready;
    return DayPhase.inProgress;
  }

  int get completedGames {
    if (phase == DayPhase.completed) return 6;
    final current = ordinal ?? 1;
    if (awaitAdvance) return current.clamp(0, 6);
    return (current - 1).clamp(0, 6);
  }

  String get label => ordinalLabel ?? tournamentOrdinalLabels[ordinal] ?? '';
}

TournamentDay dayFromPayload({
  required Map<String, Object?> claim,
  Map<String, Object?>? board,
}) {
  final state = tournamentMap(board?['state']);
  final ordinal = tournamentInt(board?['ordinal']);
  return TournamentDay(
    seriesId: claim['seriesId']?.toString() ?? '',
    original: claim['original'] == true,
    claimStatus: claim['status']?.toString() ?? '',
    ordinal: ordinal,
    ordinalLabel:
        board?['ordinalLabel']?.toString() ?? tournamentOrdinalLabels[ordinal],
    seriesScore: tournamentInt(board?['seriesScore']),
    gameScore: tournamentInt(board?['score']),
    awaitAdvance: board?['awaitAdvance'] == true,
    resultsPublished: board?['resultsPublished'] == true,
    terminalReason: board?['terminalReason']?.toString(),
    turnsUsed: tournamentInt(state?['turnsUsed']),
    moveLimit: tournamentInt(state?['moveLimit']),
    boardSize: tournamentInt(state?['boardSize']),
  );
}
