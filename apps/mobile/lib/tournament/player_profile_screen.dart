import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/diagnostics/diagnostic_runtime.dart';
import 'package:puzzle_duel_mobile/diagnostics/firebase_crashlytics_adapter.dart';
import 'package:puzzle_duel_mobile/diagnostics/puzzle_duel_logger.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/arcade_backdrop.dart';
import 'package:puzzle_duel_mobile/theme/game_tokens.dart';
import 'package:puzzle_duel_mobile/presentation/feedback/app_feedback.dart';
import 'package:puzzle_duel_mobile/tournament/badge_catalog.dart';
import 'package:puzzle_duel_mobile/tournament/personal_records_repository.dart';
import 'package:puzzle_duel_mobile/tournament/practice_store.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_controller.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_copy.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';

/// Personal overview, version-aware practice bests, and authoritative badges.
/// Distinct from official Tournament leaderboards.
final class PlayerProfileScreen extends StatefulWidget {
  const PlayerProfileScreen({super.key, required this.controller});

  final TournamentController controller;

  @override
  State<PlayerProfileScreen> createState() => _PlayerProfileScreenState();
}

final class _PlayerProfileScreenState extends State<PlayerProfileScreen> {
  PracticeStats _stats = const PracticeStats(
    completedCount: 0,
    difficultyCounts: {},
  );
  PersonalRecordsViewModel? _recordsViewModel;
  PersonalRecordSegment _recordsSegment = PersonalRecordSegment.all;
  BadgeCollectionSnapshot _badges = BadgeCollectionSnapshot.lockedCatalog(
    status: BadgeCollectionStatus.loading,
  );

  /// Last successful badge snapshot keyed by verified player id (never guest).
  final Map<String, BadgeCollectionSnapshot> _badgeCacheByPlayer = {};
  var _loadingBadges = true;
  var _accountStateEpoch = -1;
  var _localLoadGeneration = 0;
  var _badgeLoadGeneration = 0;
  String? _activeBadgeCacheKey;

  /// Verified remote GET in flight after local paint (All/Tournament empty label).
  var _awaitingVerifiedRemote = false;

  /// True after at least one settled verified remote attempt for this account scope.
  var _verifiedRemoteSettled = false;

  bool get _isVerifiedAccount =>
      widget.controller.sessionAuth?.cachedAccess?.isVerified == true;

  String? get _verifiedPlayerCacheKey {
    final access = widget.controller.sessionAuth?.cachedAccess;
    if (access == null || !access.isVerified) return null;
    final playerId = access.playerId.trim().toLowerCase();
    if (playerId.isEmpty) return null;
    final origin = UatApi.apiOrigin(widget.controller.api.baseUrl);
    return '$origin|$playerId';
  }

  @override
  void initState() {
    super.initState();
    _accountStateEpoch = widget.controller.accountStateEpoch;
    widget.controller.addListener(_onControllerChanged);
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(covariant PlayerProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _beginAccountScopedRefresh(
        epoch: widget.controller.accountStateEpoch,
        clearImmediately: true,
      );
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final epoch = widget.controller.accountStateEpoch;
    if (epoch != _accountStateEpoch) {
      _beginAccountScopedRefresh(epoch: epoch, clearImmediately: true);
      return;
    }
    setState(() {});
  }

  void _clearAccountScopedUi() {
    _stats = const PracticeStats(completedCount: 0, difficultyCounts: {});
    _recordsViewModel = null;
    _awaitingVerifiedRemote = false;
    _verifiedRemoteSettled = false;
    _loadingBadges = true;
    _activeBadgeCacheKey = _verifiedPlayerCacheKey;
    final cached = _activeBadgeCacheKey == null
        ? null
        : _badgeCacheByPlayer[_activeBadgeCacheKey!];
    _badges =
        cached ??
        BadgeCollectionSnapshot.lockedCatalog(
          status: BadgeCollectionStatus.loading,
        );
  }

  void _beginAccountScopedRefresh({
    required int epoch,
    required bool clearImmediately,
  }) {
    _accountStateEpoch = epoch;
    final localGeneration = ++_localLoadGeneration;
    final badgeGeneration = ++_badgeLoadGeneration;
    if (clearImmediately) {
      _clearAccountScopedUi();
      // New verified scope defaults to All; guest has no segment UI.
      _recordsSegment = PersonalRecordSegment.all;
    }
    setState(() {});
    // Verified account transitions must remote-refresh; guest stays local-only.
    final remote = _isVerifiedAccount;
    unawaited(
      _reloadLocal(
        expectedEpoch: epoch,
        generation: localGeneration,
        remote: remote,
      ),
    );
    unawaited(_loadBadges(expectedEpoch: epoch, generation: badgeGeneration));
  }

  bool _isStaleLoad({
    required int expectedEpoch,
    required int generation,
    required int currentGeneration,
  }) {
    return !mounted ||
        expectedEpoch != widget.controller.accountStateEpoch ||
        expectedEpoch != _accountStateEpoch ||
        generation != currentGeneration;
  }

  Future<void> _reloadLocal({
    required int expectedEpoch,
    required int generation,
    bool remote = false,
  }) async {
    unawaited(
      DiagnosticRuntime.logger.log(
        LogEvent(
          level: LogLevel.info,
          code: LogCode.screenOpened,
          operation: 'profile_personal_records_requested',
        ),
      ),
    );
    final repo = widget.controller.personalRecords;
    // Always paint local/cached Practice records first — never block on remote.
    final localView = await repo.loadViewModel();
    if (_isStaleLoad(
      expectedEpoch: expectedEpoch,
      generation: generation,
      currentGeneration: _localLoadGeneration,
    )) {
      unawaited(
        DiagnosticRuntime.logger.log(
          LogEvent(
            level: LogLevel.info,
            code: LogCode.screenOpened,
            operation: 'profile_personal_records_stale_discarded',
          ),
        ),
      );
      return;
    }
    setState(() {
      _stats = localView.practiceStats;
      _recordsViewModel = localView;
      if (remote && _isVerifiedAccount) {
        _awaitingVerifiedRemote = true;
      }
    });

    if (!remote || !_isVerifiedAccount) return;

    final syncGeneration = repo.accountSyncGeneration;
    await repo.refreshAndSync(expectedGeneration: syncGeneration);
    if (_isStaleLoad(
      expectedEpoch: expectedEpoch,
      generation: generation,
      currentGeneration: _localLoadGeneration,
    )) {
      unawaited(
        DiagnosticRuntime.logger.log(
          LogEvent(
            level: LogLevel.info,
            code: LogCode.screenOpened,
            operation: 'profile_personal_records_stale_discarded',
          ),
        ),
      );
      return;
    }
    // Discard remote outcome writes if account generation changed mid-flight.
    if (syncGeneration != repo.accountSyncGeneration) return;

    final remoteView = await repo.loadViewModel();
    if (_isStaleLoad(
      expectedEpoch: expectedEpoch,
      generation: generation,
      currentGeneration: _localLoadGeneration,
    )) {
      return;
    }
    setState(() {
      _stats = remoteView.practiceStats;
      _recordsViewModel = remoteView;
      _awaitingVerifiedRemote = false;
      _verifiedRemoteSettled = true;
    });
    if (!mounted) return;
    final status = remoteView.syncStatus;
    if (status == PersonalRecordsSyncStatus.serverError ||
        status == PersonalRecordsSyncStatus.unauthorized) {
      final message = TournamentCopy.of(
        context,
      ).personalRecordsSyncStatus(status);
      if (message.isNotEmpty) {
        widget.controller.presentAppFeedback(
          kind: AppFeedbackKind.warning,
          message: message,
          semanticsKey: 'profile-records-fetch-failed',
        );
      }
    }
  }

  Future<void> _loadBadges({
    required int expectedEpoch,
    required int generation,
  }) async {
    final cacheKey = _verifiedPlayerCacheKey;
    _activeBadgeCacheKey = cacheKey;
    unawaited(
      DiagnosticRuntime.logger.log(
        LogEvent(
          level: LogLevel.info,
          code: LogCode.screenOpened,
          operation: 'profile_badges_requested',
        ),
      ),
    );
    if (!_isStaleLoad(
      expectedEpoch: expectedEpoch,
      generation: generation,
      currentGeneration: _badgeLoadGeneration,
    )) {
      final cached = cacheKey == null ? null : _badgeCacheByPlayer[cacheKey];
      setState(() {
        _loadingBadges = true;
        _badges =
            cached ??
            BadgeCollectionSnapshot.lockedCatalog(
              status: BadgeCollectionStatus.loading,
            );
      });
    }
    try {
      // Account-scoped profile path — no tournament gameplay session required.
      var result = await widget.controller.api.get('/v1/profile/me/badges');
      if (result.status == 404) {
        result = await widget.controller.api.get('/v1/tournament/me/badges');
      }
      if (_isStaleLoad(
        expectedEpoch: expectedEpoch,
        generation: generation,
        currentGeneration: _badgeLoadGeneration,
      )) {
        unawaited(
          DiagnosticRuntime.logger.log(
            LogEvent(
              level: LogLevel.info,
              code: LogCode.screenOpened,
              operation: 'profile_badges_stale_response_discarded',
            ),
          ),
        );
        return;
      }
      if (result.status == 0) {
        final cached = cacheKey == null ? null : _badgeCacheByPlayer[cacheKey];
        setState(() {
          _loadingBadges = false;
          if (cached != null) {
            _badges = BadgeCollectionSnapshot(
              badges: cached.badges,
              status: BadgeCollectionStatus.stale,
              errorCode: result.error,
            );
            unawaited(
              DiagnosticRuntime.logger.log(
                LogEvent(
                  level: LogLevel.info,
                  code: LogCode.screenOpened,
                  operation: 'profile_badges_cache_used',
                ),
              ),
            );
          } else {
            _badges = BadgeCollectionSnapshot.lockedCatalog(
              status: result.error == 'TIMEOUT'
                  ? BadgeCollectionStatus.serverError
                  : BadgeCollectionStatus.offline,
              errorCode: result.error,
            );
          }
        });
        unawaited(
          DiagnosticRuntime.logger.log(
            LogEvent(
              level: LogLevel.warning,
              code: LogCode.httpFailed,
              operation: 'profile_badges_failed',
              errorCode: result.error,
            ),
          ),
        );
        return;
      }
      if (result.status == 401 || result.status == 403) {
        setState(() {
          _loadingBadges = false;
          // Do not claim "locked / not earned" on auth failure.
          _badges = BadgeCollectionSnapshot(
            badges: const [],
            status: BadgeCollectionStatus.unauthorized,
            errorCode: result.error,
          );
        });
        unawaited(
          DiagnosticRuntime.logger.log(
            LogEvent(
              level: LogLevel.warning,
              code: LogCode.authExpired,
              operation: 'profile_badges_failed',
              httpStatus: result.status,
              errorCode: result.error,
            ),
          ),
        );
        return;
      }
      if (result.status < 200 || result.status >= 300) {
        final cached = cacheKey == null ? null : _badgeCacheByPlayer[cacheKey];
        setState(() {
          _loadingBadges = false;
          if (cached != null) {
            _badges = BadgeCollectionSnapshot(
              badges: cached.badges,
              status: BadgeCollectionStatus.stale,
              errorCode: result.error,
            );
          } else {
            _badges = BadgeCollectionSnapshot(
              badges: const [],
              status: BadgeCollectionStatus.serverError,
              errorCode: result.error,
            );
          }
        });
        unawaited(
          DiagnosticRuntime.logger.log(
            LogEvent(
              level: LogLevel.warning,
              code: LogCode.httpFailed,
              operation: 'profile_badges_failed',
              httpStatus: result.status,
              errorCode: result.error,
            ),
          ),
        );
        return;
      }
      final snapshot = BadgeCollectionSnapshot.fromServerPayload(result.map);
      if (cacheKey != null) {
        _badgeCacheByPlayer[cacheKey] = snapshot;
      }
      setState(() {
        _loadingBadges = false;
        _badges = snapshot;
      });
      unawaited(
        DiagnosticRuntime.logger.log(
          LogEvent(
            level: LogLevel.info,
            code: LogCode.httpCompleted,
            operation: 'profile_badges_completed',
            httpStatus: result.status,
          ),
        ),
      );
    } catch (_) {
      if (_isStaleLoad(
        expectedEpoch: expectedEpoch,
        generation: generation,
        currentGeneration: _badgeLoadGeneration,
      )) {
        return;
      }
      final cached = cacheKey == null ? null : _badgeCacheByPlayer[cacheKey];
      setState(() {
        _loadingBadges = false;
        _badges = cached != null
            ? BadgeCollectionSnapshot(
                badges: cached.badges,
                status: BadgeCollectionStatus.stale,
              )
            : const BadgeCollectionSnapshot(
                badges: [],
                status: BadgeCollectionStatus.serverError,
              );
      });
    }
  }

  Future<void> _refresh() async {
    final epoch = widget.controller.accountStateEpoch;
    _accountStateEpoch = epoch;
    final localGeneration = ++_localLoadGeneration;
    final badgeGeneration = ++_badgeLoadGeneration;
    await Future.wait([
      _reloadLocal(
        expectedEpoch: epoch,
        generation: localGeneration,
        remote: true,
      ),
      _loadBadges(expectedEpoch: epoch, generation: badgeGeneration),
    ]);
  }

  /// Guest presentation is always Practice-only regardless of retained segment.
  PersonalRecordSegment get _effectiveRecordsSegment {
    if (!_isVerifiedAccount) return PersonalRecordSegment.practice;
    return _recordsSegment;
  }

  Map<String, PersonalRecordCardModel?> get _visibleRecords {
    final view = _recordsViewModel;
    if (view == null) {
      return const {'easy': null, 'medium': null, 'hard': null};
    }
    return view.forSegment(_effectiveRecordsSegment);
  }

  String? get _recordsSyncCaption {
    if (!_isVerifiedAccount) return null;
    final status =
        _recordsViewModel?.syncStatus ?? PersonalRecordsSyncStatus.idle;
    final text = TournamentCopy.of(context).personalRecordsSyncStatus(status);
    return text.isEmpty ? null : text;
  }

  /// All/Tournament empty cards must not look like genuine "no record" before a
  /// settled successful remote snapshot (or after server/offline/auth failure).
  /// Practice segment remains local-first and may show genuine empty.
  String _emptyRecordLabel(TournamentCopy copy) {
    if (!_isVerifiedAccount) return copy.noPersonalBest;
    final segment = _effectiveRecordsSegment;
    if (segment == PersonalRecordSegment.practice) {
      return copy.noPersonalBest;
    }

    final status =
        _recordsViewModel?.syncStatus ?? PersonalRecordsSyncStatus.idle;
    final loading = _awaitingVerifiedRemote ||
        status == PersonalRecordsSyncStatus.syncing ||
        (!_verifiedRemoteSettled && status == PersonalRecordsSyncStatus.idle);
    if (loading) {
      final text = copy.personalRecordsSyncStatus(
        PersonalRecordsSyncStatus.syncing,
      );
      return text.isEmpty ? copy.personalRecordsLoading : text;
    }

    switch (status) {
      case PersonalRecordsSyncStatus.serverError:
      case PersonalRecordsSyncStatus.offline:
      case PersonalRecordsSyncStatus.unauthorized:
        final text = copy.personalRecordsSyncStatus(status);
        return text.isEmpty ? copy.noPersonalBest : text;
      case PersonalRecordsSyncStatus.idle:
      case PersonalRecordsSyncStatus.syncing:
      case PersonalRecordsSyncStatus.pendingUpload:
      case PersonalRecordsSyncStatus.upToDate:
        // Genuine empty only after a successful remote settle (upToDate /
        // pendingUpload). Idle/syncing are handled above.
        return copy.noPersonalBest;
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = TournamentCopy.of(context);
    final verified = _isVerifiedAccount;
    final accountLabel = verified
        ? copy.accountStatusVerified
        : copy.accountStatusGuest;
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
                  accountLabel: accountLabel,
                  verified: verified,
                  stats: _stats,
                  copy: copy,
                ),
                const SizedBox(height: 12),
                _AccountStatusCard(
                  verified: verified,
                  busy: widget.controller.authUiBusy,
                  copy: copy,
                  onSignIn:
                      widget.controller.onRequestRankedAuth == null ||
                          widget.controller.authUiBusy
                      ? null
                      : () {
                          unawaited(
                            DiagnosticRuntime.logger.log(
                              LogEvent(
                                level: LogLevel.info,
                                code: LogCode.screenOpened,
                                operation: 'profile_signin_tapped',
                              ),
                            ),
                          );
                          widget.controller.onRequestRankedAuth!();
                        },
                  onSignOut:
                      widget.controller.onRequestSignOut == null ||
                          widget.controller.authUiBusy
                      ? null
                      : widget.controller.onRequestSignOut,
                ),
                const SizedBox(height: 20),
                Text(
                  verified ? copy.personalRecordsTitle : copy.practiceRecordsTitle,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  verified ? copy.personalRecordsBlurb : copy.practiceRecordsBlurb,
                  style: const TextStyle(
                    color: GameTokens.textSecondary,
                    height: 1.35,
                  ),
                ),
                if (verified) ...[
                  const SizedBox(height: 12),
                  _PersonalRecordsSegmentedControl(
                    segment: _recordsSegment,
                    copy: copy,
                    onChanged: (segment) =>
                        setState(() => _recordsSegment = segment),
                  ),
                  if (_recordsSyncCaption != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _recordsSyncCaption!,
                      key: const Key('profile-records-sync'),
                      style: const TextStyle(
                        color: GameTokens.textMuted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 12),
                _PersonalBestCard(
                  key: const Key('profile-best-easy'),
                  title: copy.easy,
                  boardLabel: '5×5',
                  accent: GameTokens.easyAccent,
                  cardColor: GameTokens.easyCard,
                  record: _visibleRecords['easy'],
                  emptyLabel: _emptyRecordLabel(copy),
                  copy: copy,
                ),
                const SizedBox(height: 10),
                _PersonalBestCard(
                  key: const Key('profile-best-medium'),
                  title: copy.medium,
                  boardLabel: '6×6',
                  accent: GameTokens.mediumAccent,
                  cardColor: GameTokens.mediumCard,
                  record: _visibleRecords['medium'],
                  emptyLabel: _emptyRecordLabel(copy),
                  copy: copy,
                ),
                const SizedBox(height: 10),
                _PersonalBestCard(
                  key: const Key('profile-best-hard'),
                  title: copy.hard,
                  boardLabel: '7×7',
                  accent: GameTokens.hardAccent,
                  cardColor: GameTokens.hardCard,
                  record: _visibleRecords['hard'],
                  emptyLabel: _emptyRecordLabel(copy),
                  copy: copy,
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
                  onRetry: () {
                    final epoch = widget.controller.accountStateEpoch;
                    _accountStateEpoch = epoch;
                    final generation = ++_badgeLoadGeneration;
                    unawaited(
                      _loadBadges(expectedEpoch: epoch, generation: generation),
                    );
                  },
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
                          content: const Text(
                            'This will close the staging app. Relaunch it to upload the crash report.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Crash'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await FirebaseDiagnostics.forceTestCrash();
                      }
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
    required this.busy,
    required this.copy,
    this.onSignIn,
    this.onSignOut,
  });

  final bool verified;
  final bool busy;
  final TournamentCopy copy;
  final VoidCallback? onSignIn;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final statusLabel = verified
        ? copy.accountStatusVerified
        : copy.accountStatusGuest;
    return Semantics(
      container: true,
      label: statusLabel,
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
                  verified ? Icons.verified_user_rounded : Icons.person_outline,
                  color: verified
                      ? GameTokens.success
                      : GameTokens.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    statusLabel,
                    key: Key(
                      verified
                          ? 'profile-account-verified'
                          : 'profile-account-guest',
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: GameTokens.textPrimary,
                    ),
                  ),
                ),
                if (busy)
                  const SizedBox(
                    key: Key('profile-auth-busy'),
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            if (!verified && onSignIn != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('profile-sign-in'),
                  onPressed: busy ? null : onSignIn,
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
                  onPressed: busy ? null : onSignOut,
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
    required this.accountLabel,
    required this.verified,
    required this.stats,
    required this.copy,
  });

  final String accountLabel;
  final bool verified;
  final PracticeStats stats;
  final TournamentCopy copy;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '${copy.profile}, $accountLabel',
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
                verified ? Icons.verified_user_rounded : Icons.person_rounded,
                color: verified ? GameTokens.success : GameTokens.accent,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    accountLabel,
                    key: Key(
                      verified
                          ? 'profile-header-verified'
                          : 'profile-header-guest',
                    ),
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

final class _PersonalRecordsSegmentedControl extends StatelessWidget {
  const _PersonalRecordsSegmentedControl({
    required this.segment,
    required this.copy,
    required this.onChanged,
  });

  final PersonalRecordSegment segment;
  final TournamentCopy copy;
  final ValueChanged<PersonalRecordSegment> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: copy.personalRecordsTitle,
      child: SegmentedButton<PersonalRecordSegment>(
        key: const Key('profile-records-segment'),
        showSelectedIcon: false,
        segments: [
          ButtonSegment(
            value: PersonalRecordSegment.all,
            label: Text(copy.personalRecordsSegmentAll),
          ),
          ButtonSegment(
            value: PersonalRecordSegment.practice,
            label: Text(copy.personalRecordsSegmentPractice),
          ),
          ButtonSegment(
            value: PersonalRecordSegment.tournament,
            label: Text(copy.personalRecordsSegmentTournament),
          ),
        ],
        selected: {segment},
        onSelectionChanged: (selected) {
          if (selected.isEmpty) return;
          onChanged(selected.first);
        },
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
    required this.record,
    required this.copy,
    this.emptyLabel,
  });

  final String title;
  final String boardLabel;
  final Color accent;
  final Color cardColor;
  final PersonalRecordCardModel? record;
  final TournamentCopy copy;
  final String? emptyLabel;

  @override
  Widget build(BuildContext context) {
    final empty = record == null;
    final emptyText = emptyLabel ?? copy.noPersonalBest;
    return Semantics(
      label: empty
          ? '$title $boardLabel, $emptyText'
          : '$title $boardLabel, ${copy.groupedScore(record!.score)}',
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
                if (!empty && record!.displaySource != null)
                  Text(
                    record!.displaySource ==
                            PersonalRecordDisplaySource.tournament
                        ? copy.personalRecordsSourceTournament
                        : copy.personalRecordsSourcePractice,
                    style: const TextStyle(
                      color: GameTokens.textMuted,
                      fontSize: 11,
                    ),
                  )
                else if (empty || record!.localOnly)
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
                emptyText,
                style: const TextStyle(color: GameTokens.textSecondary),
              )
            else ...[
              Text(
                copy.groupedScore(record!.score),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: GameTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                copy.recordMeta(
                  completedAt: record!.achievedAt ?? '',
                  rulesVersion: record!.rulesVersion,
                  moveCount: record!.moveCount,
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
      BadgeCollectionStatus.stale => copy.badgeStale,
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
