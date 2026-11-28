import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_nav.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_uat_app.dart';
import 'package:puzzle_duel_mobile/tournament/weekly_tournament_overview.dart';

WeeklyTournamentDay _day({
  required String date,
  required WeeklyDayStatus status,
  int? verifiedScore,
  CompletionTiming? timing,
  String? seriesId,
  int completed = 0,
  bool canStart = false,
  bool canResume = false,
  bool canViewResults = false,
  bool isToday = false,
}) {
  return WeeklyTournamentDay(
    date: date,
    status: status,
    isToday: isToday,
    canStart: canStart,
    canResume: canResume,
    canViewResults: canViewResults,
    completedBoardCount: completed,
    totalBoardCount: 6,
    seriesId: seriesId,
    verifiedScore: verifiedScore,
    completionTiming: timing,
  );
}

void main() {
  test('active gameplay matches only when date + series align', () {
    final selected = _day(
      date: '2026-11-23',
      status: WeeklyDayStatus.inProgress,
      seriesId: 'series-mon',
      canResume: true,
      completed: 3,
    );
    final active = const TournamentDay(
      seriesId: 'series-sat',
      original: true,
      claimStatus: 'ACTIVE',
      ordinal: 4,
      seriesScore: 10600,
    );
    expect(
      activeGameplayMatchesSelection(
        hidePersonal: false,
        accountScoped: true,
        selectedDate: '2026-11-23',
        selected: selected,
        activeManifestUtcDate: '2026-11-28',
        activeSeriesId: 'series-sat',
        day: active,
      ),
      isFalse,
    );
    expect(
      activeGameplayMatchesSelection(
        hidePersonal: false,
        accountScoped: true,
        selectedDate: '2026-11-28',
        selected: _day(
          date: '2026-11-28',
          status: WeeklyDayStatus.completed,
          seriesId: 'series-sat',
          verifiedScore: 10600,
          canViewResults: true,
          isToday: true,
        ),
        activeManifestUtcDate: '2026-11-28',
        activeSeriesId: 'series-sat',
        day: active,
      ),
      isTrue,
    );
    expect(
      activeGameplayMatchesSelection(
        hidePersonal: true,
        accountScoped: true,
        selectedDate: '2026-11-28',
        selected: null,
        activeManifestUtcDate: '2026-11-28',
        activeSeriesId: 'series-sat',
        day: active,
      ),
      isFalse,
    );
    expect(
      activeGameplayMatchesSelection(
        hidePersonal: false,
        accountScoped: false,
        selectedDate: '2026-11-28',
        selected: _day(
          date: '2026-11-28',
          status: WeeklyDayStatus.completed,
          seriesId: 'series-sat',
          verifiedScore: 10600,
          canViewResults: true,
          isToday: true,
        ),
        activeManifestUtcDate: '2026-11-28',
        activeSeriesId: 'series-sat',
        day: active,
      ),
      isFalse,
    );
  });

  test('mismatched series on same date does not match', () {
    expect(
      activeGameplayMatchesSelection(
        hidePersonal: false,
        accountScoped: true,
        selectedDate: '2026-11-25',
        selected: _day(
          date: '2026-11-25',
          status: WeeklyDayStatus.completed,
          seriesId: 'series-wed',
          verifiedScore: 8000,
          canViewResults: true,
        ),
        activeManifestUtcDate: '2026-11-25',
        activeSeriesId: 'series-other',
        day: const TournamentDay(
          seriesId: 'series-other',
          original: true,
          claimStatus: 'COMPLETED',
          seriesScore: 9999,
          resultsPublished: true,
        ),
      ),
      isFalse,
    );
  });
}
