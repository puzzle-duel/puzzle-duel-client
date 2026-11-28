import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/theme/game_tokens.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_copy.dart';
import 'package:puzzle_duel_mobile/tournament/weekly_tournament_overview.dart';

/// Owner-approved 4+3 weekly day selector inside the Home tournament card.
final class WeeklyTournamentCalendar extends StatelessWidget {
  const WeeklyTournamentCalendar({
    super.key,
    required this.overview,
    required this.selectedDate,
    required this.onSelect,
    required this.accountScoped,
  });

  final WeeklyTournamentOverview overview;
  final String? selectedDate;
  final ValueChanged<String> onSelect;
  final bool accountScoped;

  @override
  Widget build(BuildContext context) {
    final days = overview.days;
    if (days.length != 7) return const SizedBox.shrink();
    final top = days.take(4).toList(growable: false);
    final bottom = days.skip(4).toList(growable: false);
    return Column(
      key: const Key('weekly-tournament-calendar'),
      children: [
        _DayRow(
          days: top,
          selectedDate: selectedDate,
          onSelect: onSelect,
          accountScoped: accountScoped,
        ),
        const SizedBox(height: GameTokens.spaceSm),
        _DayRow(
          days: bottom,
          selectedDate: selectedDate,
          onSelect: onSelect,
          accountScoped: accountScoped,
        ),
      ],
    );
  }
}

final class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.days,
    required this.selectedDate,
    required this.onSelect,
    required this.accountScoped,
  });

  final List<WeeklyTournamentDay> days;
  final String? selectedDate;
  final ValueChanged<String> onSelect;
  final bool accountScoped;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          children: [
            for (var i = 0; i < days.length; i++) ...[
              if (i > 0) const SizedBox(width: GameTokens.spaceXs),
              Expanded(
                child: _DayCard(
                  day: days[i],
                  selected: days[i].date == selectedDate,
                  onSelect: onSelect,
                  accountScoped: accountScoped,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

final class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.day,
    required this.selected,
    required this.onSelect,
    required this.accountScoped,
  });

  final WeeklyTournamentDay day;
  final bool selected;
  final ValueChanged<String> onSelect;
  final bool accountScoped;

  @override
  Widget build(BuildContext context) {
    final copy = TournamentCopy.of(context);
    final locale = TournamentLocale.of(context);
    final style = _styleFor(day, accountScoped: accountScoped);
    final weekday = _weekdayShort(day.date, locale);
    final semantics = [
      _fullDateLabel(day.date, locale),
      style.label(copy),
      if (day.isToday) copy.readyHeadline,
      if (selected) 'selected',
    ].join('. ');
    return Semantics(
      button: true,
      selected: selected,
      label: semantics,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('week-day-${day.date}'),
          onTap: () => onSelect(day.date),
          borderRadius: BorderRadius.circular(GameTokens.radiusSm),
          child: Ink(
            decoration: BoxDecoration(
              color: style.fill,
              borderRadius: BorderRadius.circular(GameTokens.radiusSm),
              border: Border.all(
                color: selected ? GameTokens.accent : style.border,
                width: selected || day.isToday ? 2 : 1.2,
              ),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      weekday,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: style.foreground,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Icon(style.icon, size: 16, color: style.foreground),
                    const SizedBox(height: 2),
                    Text(
                      style.shortLabel(copy, day),
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: style.foreground,
                        fontWeight: FontWeight.w700,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _DayVisual {
  const _DayVisual({
    required this.border,
    required this.fill,
    required this.foreground,
    required this.icon,
    required this.label,
    required this.shortLabel,
  });

  final Color border;
  final Color fill;
  final Color foreground;
  final IconData icon;
  final String Function(TournamentCopy copy) label;
  final String Function(TournamentCopy copy, WeeklyTournamentDay day) shortLabel;
}

_DayVisual _styleFor(
  WeeklyTournamentDay day, {
  required bool accountScoped,
}) {
  // Guest/public: never imply personal completion.
  final status = (!accountScoped &&
          (day.status == WeeklyDayStatus.completed ||
              day.status == WeeklyDayStatus.inProgress))
      ? (day.isToday
            ? WeeklyDayStatus.availableToday
            : WeeklyDayStatus.availablePast)
      : day.status;

  return switch (status) {
    WeeklyDayStatus.completed => _DayVisual(
      border: GameTokens.success,
      fill: GameTokens.success.withValues(alpha: 0.12),
      foreground: GameTokens.success,
      icon: Icons.check_rounded,
      label: (c) => c.completedDayLabel,
      shortLabel: (c, _) => c.pick('Done', 'Tamam'),
    ),
    WeeklyDayStatus.availablePast => _DayVisual(
      border: GameTokens.scoreGlow,
      fill: GameTokens.scoreGlow.withValues(alpha: 0.12),
      foreground: GameTokens.scoreGlow,
      icon: Icons.play_arrow_rounded,
      label: (c) => c.playDayLabel,
      shortLabel: (c, _) => c.playDayLabel,
    ),
    WeeklyDayStatus.availableToday => _DayVisual(
      border: GameTokens.accent,
      fill: GameTokens.accent.withValues(alpha: 0.14),
      foreground: GameTokens.accent,
      icon: Icons.play_circle_filled_rounded,
      label: (c) => c.playDayLabel,
      shortLabel: (c, _) => c.playDayLabel,
    ),
    WeeklyDayStatus.inProgress => _DayVisual(
      border: GameTokens.accent,
      fill: GameTokens.accent.withValues(alpha: 0.12),
      foreground: GameTokens.accent,
      icon: Icons.timelapse_rounded,
      label: (c) => c.continueTournament,
      shortLabel: (c, d) => '${d.completedBoardCount}/${d.totalBoardCount}',
    ),
    WeeklyDayStatus.lockedFuture => _DayVisual(
      border: GameTokens.border,
      fill: GameTokens.surface.withValues(alpha: 0.55),
      foreground: GameTokens.textMuted,
      icon: Icons.lock_rounded,
      label: (c) => c.notAvailableYet,
      shortLabel: (c, _) => c.pick('Locked', 'Kilit'),
    ),
    WeeklyDayStatus.closed ||
    WeeklyDayStatus.unavailable ||
    WeeklyDayStatus.unknown => _DayVisual(
      border: GameTokens.border,
      fill: GameTokens.surface.withValues(alpha: 0.4),
      foreground: GameTokens.textMuted,
      icon: Icons.help_outline_rounded,
      label: (c) => c.weekClosed,
      shortLabel: (c, _) => c.pick('Closed', 'Kapalı'),
    ),
  };
}

String _weekdayShort(String date, Locale locale) {
  final parsed = DateTime.tryParse('${date}T00:00:00.000Z');
  if (parsed == null) return date;
  const tr = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
  const en = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final labels = locale.languageCode == 'tr' ? tr : en;
  return labels[(parsed.weekday + 6) % 7];
}

String _fullDateLabel(String date, Locale locale) {
  final parsed = DateTime.tryParse('${date}T00:00:00.000Z');
  if (parsed == null) return date;
  final monthsTr = [
    'Ocak',
    'Şubat',
    'Mart',
    'Nisan',
    'Mayıs',
    'Haziran',
    'Temmuz',
    'Ağustos',
    'Eylül',
    'Ekim',
    'Kasım',
    'Aralık',
  ];
  final monthsEn = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  final months = locale.languageCode == 'tr' ? monthsTr : monthsEn;
  return '${parsed.day} ${months[parsed.month - 1]} ${parsed.year}';
}
