import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/application/game_session.dart';
import 'package:puzzle_duel_mobile/presentation/audio/game_sfx.dart';
import 'package:puzzle_duel_mobile/presentation/audio/game_sfx_scope.dart';
import 'package:puzzle_duel_mobile/presentation/feedback/move_feedback_copy.dart';
import 'package:puzzle_duel_mobile/theme/game_tokens.dart';

/// Floating, auto-dismissing player feedback chip. Replaces prior toast.
final class MoveFeedbackToast extends StatefulWidget {
  const MoveFeedbackToast({super.key, required this.session});

  final GameSession session;

  @override
  State<MoveFeedbackToast> createState() => _MoveFeedbackToastState();
}

final class _MoveFeedbackToastState extends State<MoveFeedbackToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade;
  String? _message;
  int _token = 0;
  Timer? _hide;
  MoveFeedbackKind _lastKind = MoveFeedbackKind.none;
  String? _lastCode;
  int _lastGeneration = -1;
  GameSfx? _sfx;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
      reverseDuration: const Duration(milliseconds: 220),
    );
    widget.session.addListener(_onSession);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sfx = GameSfxScope.maybeOf(context);
    _onSession();
  }

  @override
  void didUpdateWidget(covariant MoveFeedbackToast oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(_onSession);
      widget.session.addListener(_onSession);
      _onSession();
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSession);
    _hide?.cancel();
    _fade.dispose();
    super.dispose();
  }

  void _onSession() {
    final view = widget.session.view;
    // No spam while a resolution animation owns the board.
    if (view.isResolving) {
      if (_message != null) {
        _hide?.cancel();
        final token = ++_token;
        _fade.reverse().whenComplete(() {
          if (!mounted || token != _token) return;
          setState(() => _message = null);
        });
      }
      return;
    }

    final kind = view.feedbackKind;
    final code = view.feedbackCode;
    if (kind == MoveFeedbackKind.none) return;

    final text = MoveFeedbackCopy.playerMessage(kind: kind, code: code);
    if (text == null) return;

    final sameFeedback =
        kind == _lastKind &&
        code == _lastCode &&
        view.generation == _lastGeneration;
    final visible = _message != null && _fade.value > 0;

    // Ignore InheritedWidget / rebuild echoes of the same rejection.
    // A later identical rejection still refreshes the chip after dismiss.
    if (sameFeedback && visible) return;

    // One chip only: replace/restart; never stack.
    _lastKind = kind;
    _lastCode = code;
    _lastGeneration = view.generation;

    // Debounce lives in GameSfx — safe to call on each rejection.
    _sfx?.play(GameSfxEvent.reject);

    _hide?.cancel();
    final token = ++_token;
    setState(() => _message = text);
    if (!visible) {
      _fade.forward(from: 0);
    }
    _hide = Timer(const Duration(milliseconds: 1700), () {
      if (!mounted || token != _token) return;
      _fade.reverse().whenComplete(() {
        if (!mounted || token != _token) return;
        setState(() => _message = null);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final message = _message;
    if (message == null) return const SizedBox.shrink();

    return IgnorePointer(
      child: FadeTransition(
        opacity: _fade,
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Semantics(
              liveRegion: true,
              label: message,
              child: Material(
                color: GameTokens.surfaceHigh.withValues(alpha: 0.96),
                elevation: 6,
                shadowColor: Colors.black54,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(GameTokens.radiusMd),
                  side: const BorderSide(color: GameTokens.borderBright),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: GameTokens.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
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
