import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/diagnostics/diagnostic_runtime.dart';
import 'package:puzzle_duel_mobile/diagnostics/firebase_crashlytics_adapter.dart';
import 'package:puzzle_duel_mobile/diagnostics/puzzle_duel_logger.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/arcade_backdrop.dart';
import 'package:puzzle_duel_mobile/theme/game_tokens.dart';
import 'package:puzzle_duel_mobile/tournament/badge_catalog.dart';
import 'package:puzzle_duel_mobile/tournament/practice_store.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_controller.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_copy.dart';

/// Personal overview, version-aware practice bests, and authoritative badges.
/// Distinct from official Tournament leaderboards.
final class PlayerProfileScreen extends StatefulWidget {
  const PlayerProfileScreen({super.key, required this.controller});

  final TournamentController controller;

  @override
  State<PlayerProfileScreen> createState() => _PlayerProfileScreenState();
}

final class _PlayerProfileScreenState extends State<PlayerProfileScreen> {
  static const _practiceRules = 'core-001.v2';
  static const _practiceGenerator = 'gen-001.v1';

  late PracticeStore _store;
  PracticeStats _stats = const PracticeStats(
    completedCount: 0,
    difficultyCounts: {},
  );
  Map<String, PracticeBest?> _bests = const {
    'easy': null,
    'medium': null,
    'hard': null,
  };
  BadgeCollectionSnapshot _badges = BadgeCollectionSnapshot.lockedCatalog(
    status: BadgeCollectionStatus.loading,
  );
  var _loadingBadges = true;

  @override
  void initState() {
    super.initState();
    _reloadLocal();
    _loadBadges();
  }

  Future<void> _reloadLocal() async {
    _store = widget.controller.practiceStore();
    final stats = await _store.stats();
    final bests = <String, PracticeBest?>{};
    for (final difficulty in const ['easy', 'medium', 'hard']) {
      bests[difficulty] = await _store.personalBestForDifficulty(
        difficulty,
        rulesVersion: _practiceRules,
        preferredGeneratorVersion: _practiceGenerator,
      );
    }
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _bests = bests;
    });
  }

  Future<void> _loadBadges() async {
    setState(() {
      _loadingBadges = true;
      _badges = BadgeCollectionSnapshot.lockedCatalog(
        status: BadgeCollectionStatus.loading,
      );
    });
    try {
      final result = await widget.controller.api.get(
        '/v1/tournament/me/badges',
      );
      if (!mounted) return;
      if (result.status == 0) {
        setState(() {
          _loadingBadges = false;
          _badges = BadgeCollectionSnapshot.lockedCatalog(
            status: result.error == 'TIMEOUT'
                ? BadgeCollectionStatus.serverError
                : BadgeCollectionStatus.offline,
            errorCode: result.error,
          );
        });
        return;
      }
      if (result.status == 401) {
        setState(() {
          _loadingBadges = false;
          _badges = BadgeCollectionSnapshot.lockedCatalog(
            status: BadgeCollectionStatus.unauthorized,
            errorCode: result.error,
          );
        });
        return;
      }
      if (result.status < 200 || result.status >= 300) {
        setState(() {
          _loadingBadges = false;
          _badges = BadgeCollectionSnapshot.lockedCatalog(
            status: BadgeCollectionStatus.serverError,
            errorCode: result.error,
          );
        });
        return;
      }
      setState(() {
        _loadingBadges = false;
        _badges = BadgeCollectionSnapshot.fromServerPayload(result.map);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingBadges = false;
        _badges = BadgeCollectionSnapshot.lockedCatalog(
          status: BadgeCollectionStatus.serverError,
        );
      });
    }
  }

  Future<void> _refresh() async {
    await _reloadLocal();
    await _loadBadges();
  }

  @override
  Widget build(BuildContext context) {
    final copy = TournamentCopy.of(context);
    final displayName = widget.controller.config.playerLabel.trim().isEmpty
        ? copy.playerFallback
        : widget.controller.config.playerLabel;
    return Scaffold(
      backgroundColor: GameTokens.bgDeep,
      body: ArcadeBackdrop(
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refresh,
            color: GameTokens.accent,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Row(
                  children: [
                    IconButton(
                      key: const Key('nav-back'),
                      tooltip: copy.back,
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        copy.profile,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _ProfileHeader(
                  displayName: displayName,
                  stats: _stats,
                  copy: copy,
                ),
                const SizedBox(height: 12),
                _AccountStatusCard(
                  verified: widget.controller.sessionAuth?.cachedAccess
                          ?.isVerified ==
                      true,
                  copy: copy,
                  onSignIn: widget.controller.onRequestRankedAuth == null
                      ? null
                      : () {
                          unawaited(DiagnosticRuntime.logger.log(LogEvent(
                            level: LogLevel.info,
                            code: LogCode.screenOpened,
                            operation: 'profile_signin_tapped',
                          )));
                          widget.controller.onRequestRankedAuth!();
                        },
                  onSignOut: widget.controller.onRequestSignOut,
                ),
                const SizedBox(height: 20),
                Text(
                  copy.personalRecordsTitle,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  copy.practiceLocal,
                  style: const TextStyle(
                    color: GameTokens.textSecondary,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                _PersonalBestCard(
                  key: const Key('profile-best-easy'),
                  title: copy.easy,
                  boardLabel: '5×5',
                  accent: GameTokens.easyAccent,
                  cardColor: GameTokens.easyCard,
                  best: _bests['easy'],
                  copy: copy,
                  rulesVersion: _practiceRules,
                ),
                const SizedBox(height: 10),
                _PersonalBestCard(
                  key: const Key('profile-best-medium'),
                  title: copy.medium,
                  boardLabel: '6×6',
                  accent: GameTokens.mediumAccent,
                  cardColor: GameTokens.mediumCard,
                  best: _bests['medium'],
                  copy: copy,
                  rulesVersion: _practiceRules,
                ),
                const SizedBox(height: 10),
                _PersonalBestCard(
                  key: const Key('profile-best-hard'),
                  title: copy.hard,
                  boardLabel: '7×7',
                  accent: GameTokens.hardAccent,
                  cardColor: GameTokens.hardCard,
                  best: _bests['hard'],
                  copy: copy,
                  rulesVersion: _practiceRules,
                ),
                const SizedBox(height: 24),
                Text(
                  copy.badgeCollectionTitle,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  copy.badgeCollectionBlurb,
                  style: const TextStyle(
                    color: GameTokens.textSecondary,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                _BadgeStatusBanner(
                  snapshot: _badges,
                  loading: _loadingBadges,
                  copy: copy,
                  onRetry: _loadBadges,
                ),
                const SizedBox(height: 12),
                if (FirebaseDiagnostics.stagingDiagnosticsEnabled) ...[
                  const SizedBox(height: 24),
                  const Text('Developer Diagnostics'),
                  OutlinedButton(
                    key: const Key('diagnostics-nonfatal'),
                    onPressed: () async {
                      await FirebaseDiagnostics.sendTestNonFatal();
                    },
                    child: const Text('Send Test Non-Fatal'),
                  ),
                  OutlinedButton(
                    key: const Key('diagnostics-crash'),
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Force test crash?'),
                          content: const Text('This will close the staging app. Relaunch it to upload the crash report.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Crash')),
                          ],
                        ),
                      );
                      if (confirmed == true) await FirebaseDiagnostics.forceTestCrash();
                    },
                    child: const Text('Force Test Crash'),
                  ),
                ],
                _BadgeGrid(
                  snapshot: _badges,
                  copy: copy,
                  onSelect: (badge) => _showBadgeDetail(context, badge, copy),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showBadgeDetail(
    BuildContext context,
    BadgeProgress badge,
    TournamentCopy copy,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: GameTokens.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(GameTokens.radiusLg),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  badge.definition.name(copy),
                  key: const Key('badge-detail-title'),
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  badge.definition.description(copy),
                  style: const TextStyle(
                    color: GameTokens.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  badge.definition.rule(copy),
                  style: const TextStyle(
                    color: GameTokens.textPrimary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  badge.earned
                      ? copy.badgeEarnedCount(badge.earnedCount)
                      : copy.badgeLocked,
                  style: TextStyle(
                    color: badge.earned
                        ? GameTokens.success
                        : GameTokens.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (badge.lastEarnedAt != null && badge.earned) ...[
                  const SizedBox(height: 6),
                  Text(
                    copy.badgeLastEarned(badge.lastEarnedAt!),
                    style: const TextStyle(color: GameTokens.textSecondary),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  copy.badgeProvenanceLabel(
                    badge.provenance == BadgeProvenance.f2bPublication
                        ? BadgeProvenanceLabel.f2bPublication
                        : BadgeProvenanceLabel.unavailable,
                  ),
                  style: const TextStyle(
                    color: GameTokens.textMuted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const Key('badge-detail-close'),
                    onPressed: () => Navigator.pop(context),
                    child: Text(copy.back),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

final class _AccountStatusCard extends StatelessWidget {
  const _AccountStatusCard({
    required this.verified,
    required this.copy,
    this.onSignIn,
    this.onSignOut,
  });

  final bool verified;
  final TournamentCopy copy;
  final VoidCallback? onSignIn;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: verified ? copy.accountStatusVerified : copy.accountStatusGuest,
      child: Container(
        key: const Key('profile-account-status'),
        padding: const EdgeInsets.all(GameTokens.spaceMd),
        decoration: BoxDecoration(
          color: GameTokens.surface,
          borderRadius: BorderRadius.circular(GameTokens.radiusMd),
          border: Border.all(color: GameTokens.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  verified
                      ? Icons.verified_user_rounded
                      : Icons.person_outline,
                  color: verified
                      ? GameTokens.success
                      : GameTokens.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    verified
                        ? copy.accountStatusVerified
                        : copy.accountStatusGuest,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: GameTokens.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            if (!verified && onSignIn != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('profile-sign-in'),
                  onPressed: onSignIn,
                  child: Text(
                    copy.signInToPlay,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            if (verified && onSignOut != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('profile-sign-out'),
                  onPressed: onSignOut,
                  child: Text(copy.signOut),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

final class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.displayName,
    required this.stats,
    required this.copy,
  });

  final String displayName;
  final PracticeStats stats;
  final TournamentCopy copy;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '${copy.profile}, $displayName',
      child: Container(
        key: const Key('profile-header'),
        padding: const EdgeInsets.all(GameTokens.spaceMd),
        decoration: BoxDecoration(
          color: GameTokens.surface,
          borderRadius: BorderRadius.circular(GameTokens.radiusMd),
          border: Border.all(color: GameTokens.border),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: GameTokens.surfaceHigh,
              child: Icon(
                Icons.person_rounded,
                color: GameTokens.accent,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    stats.completedCount == 0
                        ? copy.profileNoActivity
                        : copy.profileActivitySummary(stats.completedCount),
                    style: const TextStyle(
                      color: GameTokens.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _PersonalBestCard extends StatelessWidget {
  const _PersonalBestCard({
    super.key,
    required this.title,
    required this.boardLabel,
    required this.accent,
    required this.cardColor,
    required this.best,
    required this.copy,
    required this.rulesVersion,
  });

  final String title;
  final String boardLabel;
  final Color accent;
  final Color cardColor;
  final PracticeBest? best;
  final TournamentCopy copy;
  final String rulesVersion;

  @override
  Widget build(BuildContext context) {
    final empty = best == null;
    return Semantics(
      label: empty
          ? '$title $boardLabel, ${copy.noPersonalBest}'
          : '$title $boardLabel, ${copy.groupedScore(best!.score)}',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(GameTokens.spaceMd),
        decoration: BoxDecoration(
          color: cardColor.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(GameTokens.radiusMd),
          border: Border.all(color: accent.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$title — $boardLabel',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(color: accent, fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  copy.unverifiedLocal,
                  style: const TextStyle(
                    color: GameTokens.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (empty)
              Text(
                copy.noPersonalBest,
                style: const TextStyle(color: GameTokens.textSecondary),
              )
            else ...[
              Text(
                copy.groupedScore(best!.score),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: GameTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                copy.recordMeta(
                  completedAt: best!.completedAt,
                  rulesVersion: rulesVersion,
                  moveCount: best!.moveCount,
                ),
                style: const TextStyle(
                  color: GameTokens.textSecondary,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

final class _BadgeStatusBanner extends StatelessWidget {
  const _BadgeStatusBanner({
    required this.snapshot,
    required this.loading,
    required this.copy,
    required this.onRetry,
  });

  final BadgeCollectionSnapshot snapshot;
  final bool loading;
  final TournamentCopy copy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading || snapshot.status == BadgeCollectionStatus.loading) {
      return Text(copy.badgeLoading, key: const Key('badge-status-loading'));
    }
    final message = switch (snapshot.status) {
      BadgeCollectionStatus.ready => null,
      BadgeCollectionStatus.offline => copy.badgeOffline,
      BadgeCollectionStatus.unauthorized => copy.badgeAuthRequired,
      BadgeCollectionStatus.serverError => copy.badgeServerError,
      BadgeCollectionStatus.loading => copy.badgeLoading,
    };
    if (message == null) {
      final anyEarned = snapshot.badges.any((badge) => badge.earned);
      if (!anyEarned) {
        return Text(
          copy.badgeEmpty,
          key: const Key('badge-status-empty'),
          style: const TextStyle(color: GameTokens.textSecondary),
        );
      }
      return const SizedBox.shrink();
    }
    return Container(
      key: const Key('badge-status-banner'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: GameTokens.surface,
        borderRadius: BorderRadius.circular(GameTokens.radiusSm),
        border: Border.all(color: GameTokens.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: GameTokens.textSecondary,
                height: 1.35,
              ),
            ),
          ),
          TextButton(
            key: const Key('badge-retry'),
            onPressed: onRetry,
            child: Text(copy.tryAgain),
          ),
        ],
      ),
    );
  }
}

final class _BadgeGrid extends StatelessWidget {
  const _BadgeGrid({
    required this.snapshot,
    required this.copy,
    required this.onSelect,
  });

  final BadgeCollectionSnapshot snapshot;
  final TournamentCopy copy;
  final ValueChanged<BadgeProgress> onSelect;

  @override
  Widget build(BuildContext context) {
    // Key lives outside LayoutBuilder so finders/scroll helpers can locate the
    // section before the wrap is laid out in the ListView cache window.
    return KeyedSubtree(
      key: const Key('badge-grid'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final columns = width >= 420
              ? 3
              : width >= 280
              ? 2
              : 1;
          final gap = 10.0;
          final tileWidth = columns == 1
              ? width
              : (width - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final badge in snapshot.badges)
                SizedBox(
                  width: tileWidth,
                  child: _BadgeTile(
                    badge: badge,
                    copy: copy,
                    onTap: () => onSelect(badge),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

final class _BadgeTile extends StatelessWidget {
  const _BadgeTile({
    required this.badge,
    required this.copy,
    required this.onTap,
  });

  final BadgeProgress badge;
  final TournamentCopy copy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final earned = badge.earned;
    final name = badge.definition.name(copy);
    return Semantics(
      button: true,
      label: earned
          ? '$name, ${copy.badgeEarnedCount(badge.earnedCount)}'
          : '$name, ${copy.badgeLocked}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('badge-tile-${badge.definition.id.wire}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(GameTokens.radiusMd),
          child: Ink(
            decoration: BoxDecoration(
              color: earned ? GameTokens.surfaceHigh : GameTokens.surface,
              borderRadius: BorderRadius.circular(GameTokens.radiusMd),
              border: Border.all(
                color: earned
                    ? GameTokens.success.withValues(alpha: 0.5)
                    : GameTokens.border,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 28,
                    color: earned ? GameTokens.success : GameTokens.textMuted,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: earned
                          ? GameTokens.textPrimary
                          : GameTokens.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    earned
                        ? copy.badgeEarnedCount(badge.earnedCount)
                        : copy.badgeLocked,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: earned ? GameTokens.accent : GameTokens.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
