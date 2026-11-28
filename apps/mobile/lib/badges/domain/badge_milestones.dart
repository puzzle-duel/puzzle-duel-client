// PZD-56 pure milestone math — must match backend `badge-milestones.mts`.

final class BadgeSevenDayWindow {
  const BadgeSevenDayWindow({
    required this.startUtcDate,
    required this.endUtcDate,
  });

  final String startUtcDate;
  final String endUtcDate;

  String get evidenceKey => 'unstoppable:window:$startUtcDate:$endUtcDate';
}

final class BadgeMilestones {
  const BadgeMilestones._();

  static final _utcDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static String assertUtcDate(String value) {
    if (!_utcDate.hasMatch(value)) {
      throw FormatException('INVALID_UTC_DATE', value);
    }
    return value;
  }

  static String shiftUtcDate(String utcDate, int deltaDays) {
    assertUtcDate(utcDate);
    final parsed = DateTime.parse('${utcDate}T00:00:00.000Z');
    return parsed.add(Duration(days: deltaDays)).toIso8601String().substring(0, 10);
  }

  static String utcDayFromEpochMs(int completedAtMs) {
    if (completedAtMs < 0) {
      throw ArgumentError.value(completedAtMs, 'completedAtMs');
    }
    return DateTime.fromMillisecondsSinceEpoch(
      completedAtMs,
      isUtc: true,
    ).toIso8601String().substring(0, 10);
  }

  static int practiceMasterOccurrences(int completedGames) {
    if (completedGames < 0) return 0;
    return completedGames ~/ 10;
  }

  /// Non-overlapping seven-day consecutive windows from distinct active UTC dates.
  static List<BadgeSevenDayWindow> nonOverlappingSevenDayWindows(
    Iterable<String> distinctActiveUtcDates,
  ) {
    final sorted = distinctActiveUtcDates.map(assertUtcDate).toSet().toList()
      ..sort();
    final windows = <BadgeSevenDayWindow>[];
    var i = 0;
    while (i < sorted.length) {
      var runEnd = i;
      while (runEnd + 1 < sorted.length &&
          shiftUtcDate(sorted[runEnd], 1) == sorted[runEnd + 1]) {
        runEnd += 1;
      }
      final runLength = runEnd - i + 1;
      final completeWindows = runLength ~/ 7;
      for (var w = 0; w < completeWindows; w++) {
        windows.add(
          BadgeSevenDayWindow(
            startUtcDate: sorted[i + w * 7],
            endUtcDate: sorted[i + w * 7 + 6],
          ),
        );
      }
      i = runEnd + 1;
    }
    return windows;
  }

  static String loyaltyEvidenceKey(String utcDate) =>
      'loyalty:utc:${assertUtcDate(utcDate)}';

  static String practiceMasterEvidenceKey(int occurrence) {
    if (occurrence < 1) throw ArgumentError.value(occurrence, 'occurrence');
    return 'practice_master:occurrence:$occurrence';
  }

  static const practiceBadgeSyncMaxCompletions = 40;
}
