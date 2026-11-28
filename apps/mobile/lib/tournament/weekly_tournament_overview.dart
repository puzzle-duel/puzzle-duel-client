/// PZD-55 weekly tournament overview contract (GET /v1/tournament/calendar).
library;

enum WeeklyDayStatus {
  availableToday,
  availablePast,
  inProgress,
  completed,
  lockedFuture,
  unavailable,
  closed,
  unknown,
}

enum CompletionTiming { onTime, late }

final class WeeklyTournamentDay {
  const WeeklyTournamentDay({
    required this.date,
    required this.status,
    required this.isToday,
    required this.canStart,
    required this.canResume,
    required this.canViewResults,
    required this.completedBoardCount,
    required this.totalBoardCount,
    this.seriesId,
    this.manifestDigest,
    this.verifiedScore,
    this.completionTiming,
  });

  final String date;
  final WeeklyDayStatus status;
  final bool isToday;
  final bool canStart;
  final bool canResume;
  final bool canViewResults;
  final String? seriesId;
  final String? manifestDigest;
  final int completedBoardCount;
  final int totalBoardCount;
  final int? verifiedScore;
  final CompletionTiming? completionTiming;

  static WeeklyDayStatus parseStatus(Object? raw) {
    return switch (raw?.toString()) {
      'AVAILABLE_TODAY' => WeeklyDayStatus.availableToday,
      'AVAILABLE_PAST' => WeeklyDayStatus.availablePast,
      'IN_PROGRESS' => WeeklyDayStatus.inProgress,
      'COMPLETED' => WeeklyDayStatus.completed,
      'LOCKED_FUTURE' => WeeklyDayStatus.lockedFuture,
      'UNAVAILABLE' => WeeklyDayStatus.unavailable,
      'CLOSED' => WeeklyDayStatus.closed,
      _ => WeeklyDayStatus.unknown,
    };
  }

  static CompletionTiming? parseTiming(Object? raw) {
    return switch (raw?.toString()) {
      'ON_TIME' => CompletionTiming.onTime,
      'LATE' => CompletionTiming.late,
      _ => null,
    };
  }

  static WeeklyTournamentDay? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final date = raw['date']?.toString();
    if (date == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) {
      return null;
    }
    final completed = raw['completedBoardCount'];
    final total = raw['totalBoardCount'];
    final score = raw['verifiedScore'];
    return WeeklyTournamentDay(
      date: date,
      status: parseStatus(raw['status']),
      isToday: raw['isToday'] == true,
      canStart: raw['canStart'] == true,
      canResume: raw['canResume'] == true,
      canViewResults: raw['canViewResults'] == true,
      seriesId: raw['seriesId']?.toString(),
      manifestDigest: raw['manifestDigest']?.toString(),
      completedBoardCount: completed is int
          ? completed
          : int.tryParse(completed?.toString() ?? '') ?? 0,
      totalBoardCount: total is int
          ? total
          : int.tryParse(total?.toString() ?? '') ?? 6,
      verifiedScore: score is int
          ? score
          : int.tryParse(score?.toString() ?? ''),
      completionTiming: parseTiming(raw['completionTiming']),
    );
  }
}

final class WeeklyTournamentOverview {
  const WeeklyTournamentOverview({
    required this.weekStartUtc,
    required this.weekEndUtc,
    required this.serverNowMs,
    required this.currentTournamentDate,
    required this.completedDayCount,
    required this.playablePastDayCount,
    required this.accountScoped,
    required this.days,
  });

  final String weekStartUtc;
  final String weekEndUtc;
  final int serverNowMs;
  final String currentTournamentDate;
  final int completedDayCount;
  final int playablePastDayCount;
  final bool accountScoped;
  final List<WeeklyTournamentDay> days;

  WeeklyTournamentDay? dayFor(String date) {
    for (final day in days) {
      if (day.date == date) return day;
    }
    return null;
  }

  WeeklyTournamentDay? get selectedOrToday {
    final today = dayFor(currentTournamentDate);
    return today ?? (days.isEmpty ? null : days.first);
  }

  static WeeklyTournamentOverview? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final weekStart = raw['weekStartUtc']?.toString();
    final weekEnd = raw['weekEndUtc']?.toString();
    final current = raw['currentTournamentDate']?.toString();
    final serverNow = raw['serverNowMs'];
    final daysRaw = raw['days'];
    if (weekStart == null ||
        weekEnd == null ||
        current == null ||
        daysRaw is! List) {
      return null;
    }
    final days = <WeeklyTournamentDay>[];
    for (final item in daysRaw) {
      final day = WeeklyTournamentDay.tryParse(item);
      if (day != null) days.add(day);
    }
    if (days.length != 7) return null;
    return WeeklyTournamentOverview(
      weekStartUtc: weekStart,
      weekEndUtc: weekEnd,
      serverNowMs: serverNow is int
          ? serverNow
          : int.tryParse(serverNow?.toString() ?? '') ?? 0,
      currentTournamentDate: current,
      completedDayCount: raw['completedDayCount'] is int
          ? raw['completedDayCount'] as int
          : int.tryParse(raw['completedDayCount']?.toString() ?? '') ?? 0,
      playablePastDayCount: raw['playablePastDayCount'] is int
          ? raw['playablePastDayCount'] as int
          : int.tryParse(raw['playablePastDayCount']?.toString() ?? '') ?? 0,
      accountScoped: raw['accountScoped'] == true,
      days: days,
    );
  }
}
