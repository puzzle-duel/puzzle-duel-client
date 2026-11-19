import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/arcade_backdrop.dart';
import 'package:puzzle_duel_mobile/theme/game_tokens.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_controller.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_copy.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_nav.dart';

/// Arcade leaderboard. Ranks and scores are the server payload only.
final class TournamentLeaderboardView extends StatelessWidget {
  const TournamentLeaderboardView({super.key, required this.controller});

  final TournamentController controller;

  @override
  Widget build(BuildContext context) {
    final copy = TournamentCopy.of(context);
    final weekly = controller.route.place == TournamentPlace.weekly;
    final rows = [
      for (final row
          in controller.leaderboard['rows'] is List
              ? controller.leaderboard['rows'] as List
              : const [])
        if (row is Map) row,
    ];
    final self = controller.leaderboard['self'];
    final period = weekly
        ? copy.weekRange(controller.weekStart ?? '')
        : copy.dayLabel(controller.leaderboard['period']?.toString() ?? '');
    return Scaffold(
      body: ArcadeBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              _Header(copy: copy, onBack: controller.back),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    _Segment(
                      weekly: weekly,
                      copy: copy,
                      onWeekly: controller.openWeekly,
                      onDaily: controller.openDaily,
                    ),
                    const SizedBox(height: 12),
                    _PeriodRow(
                      controller: controller,
                      copy: copy,
                      weekly: weekly,
                      period: period,
                    ),
                    const SizedBox(height: 12),
                    _Categories(controller: controller, copy: copy),
                    const SizedBox(height: 16),
                    _RankCard(
                      copy: copy,
                      self: self,
                      waiting: controller.busy && self is! Map,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      copy.serverRanks,
                      style: const TextStyle(
                        color: GameTokens.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    if (rows.length >= 3) ...[
                      const SizedBox(height: 14),
                      _Podium(copy: copy, rows: rows),
                    ],
                    const SizedBox(height: 14),
                    if (controller.busy && rows.isEmpty)
                      _EmptyBoard(copy: copy, message: copy.boardLoading)
                    else if (rows.isEmpty)
                      _EmptyBoard(copy: copy)
                    else ...[
                      if (rows.length == 1)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            copy.oneVerified,
                            style: const TextStyle(
                              color: GameTokens.textSecondary,
                            ),
                          ),
                        ),
                      for (final row in rows) _RankRow(copy: copy, row: row),
                    ],
                    if (controller.nextCursor != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: OutlinedButton(
                          key: const Key('leaderboard-more'),
                          onPressed: controller.busy
                              ? null
                              : controller.loadMoreLeaderboard,
                          child: Text(
                            controller.busy ? copy.loading : copy.showMore,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _Header extends StatelessWidget {
  const _Header({required this.copy, required this.onBack});

  final TournamentCopy copy;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Row(
        children: [
          IconButton(
            key: const Key('nav-back'),
            tooltip: copy.back,
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
          ),
          const Icon(
            Icons.emoji_events_rounded,
            color: GameTokens.scoreGlow,
            size: 28,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              copy.leaderboard,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

final class _Segment extends StatelessWidget {
  const _Segment({
    required this.weekly,
    required this.copy,
    required this.onWeekly,
    required this.onDaily,
  });

  final bool weekly;
  final TournamentCopy copy;
  final VoidCallback onWeekly;
  final VoidCallback onDaily;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: GameTokens.bgDeep.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(GameTokens.radiusMd),
        border: Border.all(color: GameTokens.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            Expanded(
              child: _SegmentButton(
                key: const Key('board-weekly'),
                label: copy.weeklyTab,
                selected: weekly,
                onPressed: onWeekly,
              ),
            ),
            Expanded(
              child: _SegmentButton(
                key: const Key('board-daily'),
                label: copy.dailyTab,
                selected: !weekly,
                onPressed: onDaily,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? GameTokens.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 48,
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: selected
                      ? GameTokens.bgDeep
                      : GameTokens.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _PeriodRow extends StatelessWidget {
  const _PeriodRow({
    required this.controller,
    required this.copy,
    required this.weekly,
    required this.period,
  });

  final TournamentController controller;
  final TournamentCopy copy;
  final bool weekly;
  final String period;

  @override
  Widget build(BuildContext context) {
    final weeks = controller.weeks;
    final index = weeks.indexOf(controller.weekStart ?? '');
    final older = weekly && index >= 0 && index + 1 < weeks.length
        ? weeks[index + 1]
        : null;
    final newer = weekly && index > 0 ? weeks[index - 1] : null;
    final finalWeek = controller.weeklyFinal;
    return SizedBox(
      key: const Key('period-row'),
      height: 72,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: GameTokens.surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(GameTokens.radiusMd),
        ),
        child: Row(
          children: [
            _PeriodStep(
              visible: weekly,
              button: IconButton(
                key: const Key('week-older'),
                tooltip: copy.previousWeek,
                onPressed: older == null
                    ? null
                    : () => controller.openWeekly(week: older),
                icon: const Icon(Icons.chevron_left),
              ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    period,
                    key: const Key('period-label'),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      height: 1.15,
                    ),
                  ),
                  Text(
                    finalWeek ? copy.finalLabel : copy.provisional,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: finalWeek
                          ? GameTokens.success
                          : GameTokens.triangleFill,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
            _PeriodStep(
              visible: weekly,
              button: IconButton(
                key: const Key('week-newer'),
                tooltip: copy.newerWeek,
                onPressed: newer == null
                    ? null
                    : () => controller.openWeekly(week: newer),
                icon: const Icon(Icons.chevron_right),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reserves the arrow slot in both periods so Daily stays the same height.
final class _PeriodStep extends StatelessWidget {
  const _PeriodStep({required this.visible, required this.button});

  final bool visible;
  final Widget button;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      child: visible ? button : const SizedBox.shrink(),
    );
  }
}

final class _Categories extends StatelessWidget {
  const _Categories({required this.controller, required this.copy});

  final TournamentController controller;
  final TournamentCopy copy;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final category in ['ALL', 'EASY', 'MEDIUM', 'HARD'])
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _CategoryButton(
                label: copy.categoryLabel(category),
                selected: controller.category == category,
                onPressed: () => controller.setCategory(category),
              ),
            ),
          ),
      ],
    );
  }
}

final class _CategoryButton extends StatelessWidget {
  const _CategoryButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? GameTokens.surfaceHigh : GameTokens.surface,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected ? GameTokens.accent : GameTokens.border,
              ),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: selected ? GameTokens.accent : GameTokens.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _RankCard extends StatelessWidget {
  const _RankCard({
    required this.copy,
    required this.self,
    required this.waiting,
  });

  final TournamentCopy copy;
  final Object? self;
  final bool waiting;

  @override
  Widget build(BuildContext context) {
    final Map<dynamic, dynamic>? map = self is Map
        ? Map<dynamic, dynamic>.from(self as Map)
        : null;
    final rank = map == null ? null : tournamentInt(map['rank']);
    final score = map == null ? null : tournamentInt(map['score']);
    final ranked = rank != null && score != null;
    return DecoratedBox(
      key: const Key('self-rank'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(GameTokens.radiusLg),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A3D62), Color(0xFF141E33)],
        ),
        border: Border.all(
          color: GameTokens.scoreGlow.withValues(alpha: 0.75),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: GameTokens.scoreGlow.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: ranked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    copy.yourRank,
                    style: const TextStyle(
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w800,
                      color: GameTokens.scoreGlow,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.bottomLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '#$rank',
                                style: const TextStyle(
                                  fontSize: 56,
                                  fontWeight: FontWeight.w800,
                                  height: 1,
                                  color: GameTokens.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                copy.rankCaption,
                                style: const TextStyle(
                                  color: GameTokens.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            copy.groupedScore(score),
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: GameTokens.scoreGlow,
                            ),
                          ),
                          Text(
                            copy.verifiedScore,
                            style: const TextStyle(
                              color: GameTokens.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    copy.yourRank,
                    style: const TextStyle(
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w800,
                      color: GameTokens.scoreGlow,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '—',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(waiting ? copy.boardLoading : copy.unranked),
                ],
              ),
      ),
    );
  }
}

final class _Podium extends StatelessWidget {
  const _Podium({required this.copy, required this.rows});

  final TournamentCopy copy;
  final List<Map<dynamic, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    final ordered = [...rows]
      ..sort((a, b) {
        final left = tournamentInt(a['rank']) ?? 999;
        final right = tournamentInt(b['rank']) ?? 999;
        return left.compareTo(right);
      });
    final top = ordered.take(3).toList();
    final visual = [top[1], top[0], top[2]];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final row in visual)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _PodiumPlace(
                copy: copy,
                row: row,
                tall: identical(row, top[0]),
              ),
            ),
          ),
      ],
    );
  }
}

final class _PodiumPlace extends StatelessWidget {
  const _PodiumPlace({
    required this.copy,
    required this.row,
    required this.tall,
  });

  final TournamentCopy copy;
  final Map<dynamic, dynamic> row;
  final bool tall;

  @override
  Widget build(BuildContext context) {
    final rank = tournamentInt(row['rank']) ?? 0;
    final score = tournamentInt(row['score']);
    final color = _medal(rank) ?? GameTokens.textSecondary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(GameTokens.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.8)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(6, tall ? 10 : 16, 6, 10),
        child: Column(
          children: [
            Text(
              '#$rank',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: tall ? 22 : 16,
              ),
            ),
            Text(
              row['self'] == true ? copy.you : copy.verifiedPlayer,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              score == null ? '—' : copy.groupedScore(score),
              style: const TextStyle(
                color: GameTokens.scoreGlow,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _RankRow extends StatelessWidget {
  const _RankRow({required this.copy, required this.row});

  final TournamentCopy copy;
  final Map<dynamic, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final mine = row['self'] == true;
    final rank = tournamentInt(row['rank']);
    final score = tournamentInt(row['score']);
    final medal = _medal(rank);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: mine
              ? GameTokens.accent.withValues(alpha: 0.12)
              : GameTokens.surface,
          borderRadius: BorderRadius.circular(GameTokens.radiusMd),
          border: Border.all(
            color: mine ? GameTokens.accent : GameTokens.border,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color:
                      medal?.withValues(alpha: 0.18) ?? GameTokens.surfaceHigh,
                  shape: BoxShape.circle,
                  border: Border.all(color: medal ?? GameTokens.border),
                ),
                child: Text(
                  rank == null ? '—' : '$rank',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: medal ?? GameTokens.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mine ? copy.you : copy.verifiedPlayer,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    if (row['onTimeAwarded'] == true)
                      Text(
                        copy.onTime,
                        style: const TextStyle(
                          color: GameTokens.success,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                score == null ? '—' : copy.groupedScore(score),
                style: const TextStyle(
                  color: GameTokens.scoreGlow,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _EmptyBoard extends StatelessWidget {
  const _EmptyBoard({required this.copy, this.message});

  final TournamentCopy copy;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: GameTokens.surface,
        borderRadius: BorderRadius.circular(GameTokens.radiusLg),
        border: Border.all(color: GameTokens.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        child: Column(
          children: [
            const Icon(
              Icons.emoji_events_outlined,
              color: GameTokens.textMuted,
              size: 36,
            ),
            const SizedBox(height: 10),
            Text(message ?? copy.emptyBoard, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

Color? _medal(int? rank) {
  return switch (rank) {
    1 => GameTokens.scoreGlow,
    2 => const Color(0xFFD5DEEF),
    3 => const Color(0xFFE0A36A),
    _ => null,
  };
}
