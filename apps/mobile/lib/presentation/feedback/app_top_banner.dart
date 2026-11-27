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

@visibleForTesting
final class AppTopBannerHostState extends State<AppTopBannerHost>
    with SingleTickerProviderStateMixin {
  static const slideIn = Duration(milliseconds: 240);
  static const infoHold = Duration(milliseconds: 2500);
  static const warningHold = Duration(milliseconds: 4000);
  static const slideOut = Duration(milliseconds: 280);
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

  Timer? _dismiss;
  int _motionEpoch = 0;
  AppFeedbackKind? _kind;
  String? _text;
  String? _semanticsKey;
  String? _activeSignature;
  String? _dismissedSignature;
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

  void _clearBanner({required String? dismissedFor}) {
    setState(() {
      _kind = null;
      _text = null;
      _semanticsKey = null;
      _activeSignature = null;
      _dismissedSignature = dismissedFor;
      _dragOffset = 0;
      _dragging = false;
    });
  }

  void _scheduleDismiss({
    required AppFeedbackKind kind,
    required String signature,
    required bool reduceMotion,
  }) {
    // Explicit app feedback (auth/diagnostics) needs the longer hold so users
    // and widget settles can observe it; pull-to-refresh info stays short.
    final hold = kind == AppFeedbackKind.info &&
            widget.controller.appFeedback == null
        ? infoHold
        : warningHold;
    final epoch = ++_motionEpoch;
    _dismiss?.cancel();
    _dismiss = Timer(hold, () {
      if (!mounted || epoch != _motionEpoch || _activeSignature != signature) {
        return;
      }
      if (_dragging) {
        // Resume after drag ends via _onDragEnd / cancel path.
        _scheduleDismiss(
          kind: kind,
          signature: signature,
          reduceMotion: reduceMotion,
        );
        return;
      }
      _dismissVisible(
        signature: signature,
        epoch: epoch,
        reduceMotion: reduceMotion,
        reason: 'auto',
      );
    });
  }

  void _dismissVisible({
    required String signature,
    required int epoch,
    required bool reduceMotion,
    required String reason,
  }) {
    if (!mounted || epoch != _motionEpoch || _activeSignature != signature) {
      return;
    }
    final feedback = widget.controller.appFeedback;
    final feedbackGen = feedback != null && feedback.signature == signature
        ? feedback.generation
        : null;
    if (feedbackGen != null) {
      widget.controller.dismissAppFeedback(reason: reason);
    }
    void finish() {
      if (!mounted || epoch != _motionEpoch || _activeSignature != signature) {
        return;
      }
      _clearBanner(dismissedFor: signature);
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

    // A new refresh episode may re-announce the same offline copy.
    if (widget.syncing || fromSyncEdge) {
      _dismissedSignature = null;
    }

    // Explicit app feedback owns the channel (logout/login/diagnostics).
    if (feedback != null) {
      nextKind = feedback.kind;
      nextText = feedback.message;
      nextSemanticsKey = feedback.semanticsKey;
    } else if (notice == 'OFFLINE') {
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

    if (nextKind == null || nextText == null) {
      _dismiss?.cancel();
      _dismiss = null;
      if (_text != null) {
        final epoch = ++_motionEpoch;
        final leaving = _activeSignature;
        if (reduceMotion) {
          motion.value = 0;
          _clearBanner(dismissedFor: leaving);
        } else {
          motion.duration = slideOut;
          motion.reverse().whenComplete(() {
            if (!mounted || epoch != _motionEpoch) return;
            _clearBanner(dismissedFor: leaving);
          });
        }
      }
      return;
    }

    final signature = feedback?.signature ?? '${nextKind.name}|$nextText|';
    if (signature == _activeSignature) {
      return;
    }
    if (signature == _dismissedSignature) {
      return;
    }

    _dismiss?.cancel();
    _dismiss = null;
    final changed = nextText != _text || nextKind != _kind;
    setState(() {
      _kind = nextKind;
      _text = nextText;
      _semanticsKey = nextSemanticsKey;
      _activeSignature = signature;
      _dismissedSignature = null;
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

    if (!widget.syncing || feedback != null) {
      _scheduleDismiss(
        kind: nextKind,
        signature: signature,
        reduceMotion: reduceMotion,
      );
    }
  }

  void _onDragStart(DragStartDetails _) {
    if (_text == null || _kind == null) return;
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

  void _onDragEnd(DragEndDetails details) {
    if (!_dragging) return;
    final signature = _activeSignature;
    final kind = _kind;
    final reduceMotion = _reduceMotion;
    final velocity = details.primaryVelocity ?? 0;
    final shouldDismiss =
        signature != null &&
        kind != null &&
        (_dragOffset <= -dismissDistance || velocity <= -dismissVelocity);
    _dragging = false;
    if (shouldDismiss) {
      final epoch = ++_motionEpoch;
      _dismissVisible(
        signature: signature,
        epoch: epoch,
        reduceMotion: reduceMotion,
        reason: 'gesture',
      );
      return;
    }
    // Snap back.
    setState(() => _dragOffset = 0);
    if (signature != null && kind != null && !widget.syncing) {
      _scheduleDismiss(
        kind: kind,
        signature: signature,
        reduceMotion: reduceMotion,
      );
    }
  }

  void _onDragCancel() {
    if (!_dragging) return;
    final signature = _activeSignature;
    final kind = _kind;
    setState(() {
      _dragging = false;
      _dragOffset = 0;
    });
    if (signature != null && kind != null && !widget.syncing) {
      _scheduleDismiss(
        kind: kind,
        signature: signature,
        reduceMotion: _reduceMotion,
      );
    }
  }

  void _semanticsDismiss() {
    final signature = _activeSignature;
    if (signature == null) return;
    final epoch = ++_motionEpoch;
    _dismiss?.cancel();
    _dismissVisible(
      signature: signature,
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
