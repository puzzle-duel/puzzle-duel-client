import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/presentation/feedback/app_feedback.dart';
import 'package:puzzle_duel_mobile/theme/game_tokens.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_controller.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_copy.dart';

/// Exclusive transient Top Banner presenter (info / warning / success).
///
/// Owns entrance/exit animation, auto-dismiss timers, swipe-up dismiss, and
/// generation fencing so stale callbacks cannot mutate a newer banner.
final class AppTopBannerHost extends StatefulWidget {
  const AppTopBannerHost({
    super.key,
    required this.controller,
    required this.copy,
    required this.notice,
    required this.syncing,
    required this.infoBanners,
  });

  final TournamentController controller;
  final TournamentCopy copy;
  final String? notice;
  final bool syncing;

  /// When false (startup/background), suppress blue info toasts.
  final bool infoBanners;

  @override
  State<AppTopBannerHost> createState() => AppTopBannerHostState();
}

/// Lifecycle identity for one visible banner instance.
///
/// Explicit [AppFeedbackNotice] instances are keyed by generation + account
/// epoch. Tournament notices use an episode content key that is cleared on
/// each refresh episode — never permanently suppressing identical copy.
@visibleForTesting
final class BannerLifecycleId {
  const BannerLifecycleId.appFeedback({
    required this.generation,
    required this.accountEpoch,
  }) : noticeContentKey = null;

  const BannerLifecycleId.notice(this.noticeContentKey)
    : generation = null,
      accountEpoch = null;

  final int? generation;
  final int? accountEpoch;
  final String? noticeContentKey;

  bool get isAppFeedback => generation != null;

  @override
  bool operator ==(Object other) =>
      other is BannerLifecycleId &&
      other.generation == generation &&
      other.accountEpoch == accountEpoch &&
      other.noticeContentKey == noticeContentKey;

  @override
  int get hashCode => Object.hash(generation, accountEpoch, noticeContentKey);

  @override
  String toString() => isAppFeedback
      ? 'fb:$generation@$accountEpoch'
      : 'notice:$noticeContentKey';
}

@visibleForTesting
final class AppTopBannerHostState extends State<AppTopBannerHost>
    with TickerProviderStateMixin {
  static const slideIn = Duration(milliseconds: 240);
  static const infoHold = Duration(milliseconds: 2500);
  static const warningHold = Duration(milliseconds: 4000);
  static const slideOut = Duration(milliseconds: 280);
  static const snapBack = Duration(milliseconds: 200);
  static const dismissDistance = 48.0;
  static const dismissVelocity = 600.0;

  late final AnimationController motion = AnimationController(
    vsync: this,
    duration: slideIn,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, -1.15),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: motion, curve: Curves.easeOutCubic));
  late final Animation<double> _fade = CurvedAnimation(
    parent: motion,
    curve: Curves.easeOut,
  );

  late final AnimationController _snap = AnimationController(
    vsync: this,
    duration: snapBack,
  );
  VoidCallback? _snapListener;

  Timer? _dismiss;
  int _motionEpoch = 0;
  AppFeedbackKind? _kind;
  String? _text;
  String? _semanticsKey;
  BannerLifecycleId? _activeId;

  /// Episode-scoped suppression for tournament notices only (not app feedback).
  String? _dismissedNoticeContentKey;
  var _wasSyncing = false;
  var _didDepend = false;
  var _dragging = false;
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _wasSyncing = widget.syncing;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didDepend) return;
    _didDepend = true;
    _apply(fromSyncEdge: false);
  }

  @override
  void didUpdateWidget(covariant AppTopBannerHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final finishedSync =
        (_wasSyncing && !widget.syncing && widget.notice == null) ||
        (oldWidget.notice != null &&
            widget.notice == null &&
            !widget.syncing &&
            widget.controller.tournamentReady);
    _wasSyncing = widget.syncing;
    _apply(fromSyncEdge: finishedSync);
  }

  @override
  void dispose() {
    _dismiss?.cancel();
    _detachSnapListener();
    _snap.dispose();
    motion.dispose();
    super.dispose();
  }

  bool get _reduceMotion {
    final media = MediaQuery.maybeOf(context);
    return media?.disableAnimations == true ||
        WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .reduceMotion;
  }

  Color get _accent => switch (_kind) {
    AppFeedbackKind.info => GameTokens.notifyInfo,
    AppFeedbackKind.warning => GameTokens.notifyError,
    AppFeedbackKind.success => GameTokens.notifySuccess,
    null => GameTokens.notifyInfo,
  };

  /// Unified rule: explicit app feedback always auto-dismisses (even while
  /// tournament sync is in flight). Tournament notices wait until !syncing.
  bool _shouldScheduleAutoDismiss({required bool hasExplicitFeedback}) {
    return hasExplicitFeedback || !widget.syncing;
  }

  void _detachSnapListener() {
    final listener = _snapListener;
    if (listener != null) {
      _snap.removeListener(listener);
      _snapListener = null;
    }
  }

  void _stopSnap({required bool resetOffset}) {
    _detachSnapListener();
    _snap.stop();
    _snap.reset();
    if (resetOffset) {
      _dragOffset = 0;
    }
  }

  void _clearBanner({required BannerLifecycleId? dismissed}) {
    _stopSnap(resetOffset: true);
    setState(() {
      _kind = null;
      _text = null;
      _semanticsKey = null;
      _activeId = null;
      if (dismissed != null && !dismissed.isAppFeedback) {
        _dismissedNoticeContentKey = dismissed.noticeContentKey;
      }
      _dragOffset = 0;
      _dragging = false;
    });
  }

  Duration _holdFor(AppFeedbackKind kind, {required bool explicitFeedback}) {
    if (explicitFeedback) return warningHold;
    return kind == AppFeedbackKind.warning ? warningHold : infoHold;
  }

  void _scheduleDismiss({
    required AppFeedbackKind kind,
    required BannerLifecycleId id,
    required bool reduceMotion,
    required bool explicitFeedback,
  }) {
    if (!_shouldScheduleAutoDismiss(hasExplicitFeedback: explicitFeedback)) {
      return;
    }
    final hold = _holdFor(kind, explicitFeedback: explicitFeedback);
    final epoch = ++_motionEpoch;
    _dismiss?.cancel();
    _dismiss = Timer(hold, () {
      if (!mounted || epoch != _motionEpoch || _activeId != id) {
        return;
      }
      if (_dragging) {
        // Keep ownership; resume after drag ends via unified reschedule.
        return;
      }
      _dismissVisible(
        id: id,
        epoch: epoch,
        reduceMotion: reduceMotion,
        reason: 'auto',
      );
    });
  }

  void _rescheduleAfterDrag({
    required BannerLifecycleId id,
    required AppFeedbackKind kind,
    required bool reduceMotion,
  }) {
    _scheduleDismiss(
      kind: kind,
      id: id,
      reduceMotion: reduceMotion,
      explicitFeedback: id.isAppFeedback,
    );
  }

  void _dismissVisible({
    required BannerLifecycleId id,
    required int epoch,
    required bool reduceMotion,
    required String reason,
  }) {
    if (!mounted || epoch != _motionEpoch || _activeId != id) {
      return;
    }
    _stopSnap(resetOffset: false);
    final generation = id.generation;
    if (generation != null) {
      // Pass expected generation — never dismiss a newer feedback instance.
      widget.controller.dismissAppFeedback(
        reason: reason,
        generation: generation,
      );
    }
    void finish() {
      if (!mounted || epoch != _motionEpoch || _activeId != id) {
        return;
      }
      _clearBanner(dismissed: id);
    }

    if (reduceMotion) {
      motion.value = 0;
      finish();
      return;
    }
    motion.duration = slideOut;
    motion.reverse().whenComplete(finish);
  }

  void _apply({required bool fromSyncEdge}) {
    final reduceMotion = _reduceMotion;
    final notice = widget.notice;
    final feedback = widget.controller.appFeedback;
    final infoOk = widget.infoBanners;
    AppFeedbackKind? nextKind;
    String? nextText;
    String? nextSemanticsKey;
    BannerLifecycleId? nextId;

    // A new refresh episode may re-announce the same offline copy.
    if (widget.syncing || fromSyncEdge) {
      _dismissedNoticeContentKey = null;
    }

    // Explicit app feedback owns the channel (logout/login/diagnostics).
    if (feedback != null) {
      // Drop stale feedback from a previous account scope.
      if (feedback.accountEpoch != widget.controller.accountStateEpoch) {
        widget.controller.clearAppFeedback(feedback.generation);
      } else {
        nextKind = feedback.kind;
        nextText = feedback.message;
        nextSemanticsKey = feedback.semanticsKey;
        nextId = BannerLifecycleId.appFeedback(
          generation: feedback.generation,
          accountEpoch: feedback.accountEpoch,
        );
      }
    }
    if (nextId == null) {
      if (notice == 'OFFLINE') {
        nextKind = AppFeedbackKind.warning;
        nextText = widget.copy.connectionUnavailable;
      } else if (notice == 'TIMEOUT') {
        nextKind = AppFeedbackKind.warning;
        nextText = widget.copy.timedOut;
      } else if (notice == 'UNAUTHENTICATED' ||
          notice == 'WRITER_NOT_AUTHORIZED') {
        nextKind = AppFeedbackKind.warning;
        nextText = widget.copy.forTournamentRefreshError(notice);
      } else if (notice == 'RANKED_AUTH_REQUIRED') {
        // Guest Home CTA already explains auth — suppress redundant banner.
        nextKind = null;
        nextText = null;
      } else if (notice != null) {
        nextKind = AppFeedbackKind.warning;
        nextText = widget.copy.forTournamentRefreshError(notice);
      } else if (infoOk && fromSyncEdge && widget.controller.tournamentReady) {
        nextKind = AppFeedbackKind.info;
        nextText = widget.copy.tournamentRefreshSuccess;
      } else if (widget.syncing) {
        nextKind = null;
        nextText = null;
      }
      if (nextKind != null && nextText != null) {
        nextId = BannerLifecycleId.notice('${nextKind.name}|$nextText');
      }
    }

    if (nextKind == null || nextText == null || nextId == null) {
      _dismiss?.cancel();
      _dismiss = null;
      if (_text != null) {
        final epoch = ++_motionEpoch;
        final leaving = _activeId;
        if (reduceMotion) {
          motion.value = 0;
          _clearBanner(dismissed: leaving);
        } else {
          motion.duration = slideOut;
          motion.reverse().whenComplete(() {
            if (!mounted || epoch != _motionEpoch) return;
            _clearBanner(dismissed: leaving);
          });
        }
      }
      return;
    }

    // Same lifecycle instance — keep timers/animations intact, but tournament
    // notices held during sync must gain an auto-dismiss timer once sync ends
    // even when notice content did not change.
    if (nextId == _activeId) {
      if (fromSyncEdge &&
          !nextId.isAppFeedback &&
          !_dragging &&
          _dismiss == null &&
          _shouldScheduleAutoDismiss(hasExplicitFeedback: false)) {
        _scheduleDismiss(
          kind: nextKind,
          id: nextId,
          reduceMotion: reduceMotion,
          explicitFeedback: false,
        );
      }
      return;
    }
    // Tournament notices only: suppress re-show of the same content within
    // one refresh episode. App feedback always uses unique generation.
    if (!nextId.isAppFeedback &&
        nextId.noticeContentKey != null &&
        nextId.noticeContentKey == _dismissedNoticeContentKey) {
      return;
    }

    _dismiss?.cancel();
    _dismiss = null;
    _stopSnap(resetOffset: true);
    final changed = nextText != _text || nextKind != _kind;
    final explicit = nextId.isAppFeedback;
    setState(() {
      _kind = nextKind;
      _text = nextText;
      _semanticsKey = nextSemanticsKey;
      _activeId = nextId;
      _dragOffset = 0;
      _dragging = false;
    });
    if (reduceMotion) {
      motion.value = 1;
    } else if (changed) {
      motion.duration = slideIn;
      motion.forward(from: 0);
    } else if (motion.value < 1) {
      motion.forward();
    }

    _scheduleDismiss(
      kind: nextKind,
      id: nextId,
      reduceMotion: reduceMotion,
      explicitFeedback: explicit,
    );
  }

  void _onDragStart(DragStartDetails _) {
    if (_text == null || _kind == null || _activeId == null) return;
    _stopSnap(resetOffset: false);
    _dragging = true;
    _dismiss?.cancel();
    _dismiss = null;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_dragging) return;
    // Follow finger upward only; clamp downward so it cannot be dragged down.
    final next = (_dragOffset + details.delta.dy).clamp(-180.0, 0.0);
    if (next == _dragOffset) return;
    setState(() => _dragOffset = next);
  }

  void _animateSnapBack({
    required BannerLifecycleId id,
    required AppFeedbackKind kind,
    required bool reduceMotion,
  }) {
    if (reduceMotion) {
      setState(() {
        _dragging = false;
        _dragOffset = 0;
      });
      _rescheduleAfterDrag(id: id, kind: kind, reduceMotion: reduceMotion);
      return;
    }
    final from = _dragOffset;
    final snapEpoch = _motionEpoch;
    _dragging = false;
    _detachSnapListener();
    _snap
      ..duration = snapBack
      ..reset();
    final anim = Tween<double>(
      begin: from,
      end: 0,
    ).animate(CurvedAnimation(parent: _snap, curve: Curves.easeOutCubic));
    void listener() {
      if (!mounted || _activeId != id || snapEpoch != _motionEpoch) return;
      setState(() => _dragOffset = anim.value);
    }

    _snapListener = listener;
    _snap.addListener(listener);
    _snap.forward().whenComplete(() {
      if (!mounted || _activeId != id || snapEpoch != _motionEpoch) return;
      _detachSnapListener();
      setState(() => _dragOffset = 0);
      _rescheduleAfterDrag(id: id, kind: kind, reduceMotion: reduceMotion);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_dragging) return;
    final id = _activeId;
    final kind = _kind;
    final reduceMotion = _reduceMotion;
    final velocity = details.primaryVelocity ?? 0;
    final shouldDismiss =
        id != null &&
        kind != null &&
        (_dragOffset <= -dismissDistance || velocity <= -dismissVelocity);
    if (shouldDismiss) {
      _dragging = false;
      final epoch = ++_motionEpoch;
      _dismissVisible(
        id: id,
        epoch: epoch,
        reduceMotion: reduceMotion,
        reason: 'gesture',
      );
      return;
    }
    if (id == null || kind == null) {
      _dragging = false;
      setState(() => _dragOffset = 0);
      return;
    }
    _animateSnapBack(id: id, kind: kind, reduceMotion: reduceMotion);
  }

  void _onDragCancel() {
    if (!_dragging) return;
    final id = _activeId;
    final kind = _kind;
    if (id == null || kind == null) {
      _dragging = false;
      setState(() => _dragOffset = 0);
      return;
    }
    _animateSnapBack(id: id, kind: kind, reduceMotion: _reduceMotion);
  }

  void _semanticsDismiss() {
    final id = _activeId;
    if (id == null) return;
    final epoch = ++_motionEpoch;
    _dismiss?.cancel();
    _dismissVisible(
      id: id,
      epoch: epoch,
      reduceMotion: _reduceMotion,
      reason: 'gesture',
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    final kind = _kind;
    if (text == null || kind == null) return const SizedBox.shrink();
    final accent = _accent;
    final fill = Color.alphaBlend(
      accent.withValues(alpha: 0.42),
      GameTokens.surface,
    ).withValues(alpha: 0.94);
    // Backward-compatible keys: warning keeps tournament-status-error.
    final kindKey = kind == AppFeedbackKind.warning
        ? 'tournament-status-error'
        : 'tournament-status-${kind.name}';
    return Transform.translate(
      offset: Offset(0, _dragOffset),
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: GestureDetector(
            onVerticalDragStart: _onDragStart,
            onVerticalDragUpdate: _onDragUpdate,
            onVerticalDragEnd: _onDragEnd,
            onVerticalDragCancel: _onDragCancel,
            behavior: HitTestBehavior.opaque,
            child: Material(
              key: Key(kindKey),
              color: Colors.transparent,
              elevation: 0,
              shadowColor: Colors.transparent,
              child: DecoratedBox(
                key: const Key('tournament-status'),
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(GameTokens.radiusMd),
                  border: Border.all(color: accent.withValues(alpha: 0.72)),
                ),
                child: Semantics(
                  liveRegion: true,
                  container: true,
                  label: text,
                  button: true,
                  onDismiss: _semanticsDismiss,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Text(
                      text,
                      key: _semanticsKey != null
                          ? Key(_semanticsKey!)
                          : const Key('tournament-status-text'),
                      softWrap: true,
                      style: const TextStyle(
                        color: GameTokens.textPrimary,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
