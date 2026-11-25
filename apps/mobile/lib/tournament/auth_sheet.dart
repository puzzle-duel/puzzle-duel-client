import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/diagnostics/diagnostic_runtime.dart';
import 'package:puzzle_duel_mobile/diagnostics/puzzle_duel_logger.dart';
import 'package:puzzle_duel_mobile/theme/game_tokens.dart';
import 'package:puzzle_duel_mobile/tournament/auth_coordinator.dart';
import 'package:puzzle_duel_mobile/tournament/provider_sign_in.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_copy.dart';

/// Modal authentication sheet for ranked entry (Apple or Google — one is enough).
Future<AuthFlowResult?> showRankedAuthSheet({
  required BuildContext context,
  required AuthCoordinator coordinator,
  bool allowExplicitLogin = true,
  AuthFlowResult? recoverySeed,
}) {
  return showModalBottomSheet<AuthFlowResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: GameTokens.surfaceHigh,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => _AuthSheetBody(
      coordinator: coordinator,
      allowExplicitLogin: allowExplicitLogin,
      recoverySeed: recoverySeed,
    ),
  );
}

final class _AuthSheetBody extends StatefulWidget {
  const _AuthSheetBody({
    required this.coordinator,
    required this.allowExplicitLogin,
    this.recoverySeed,
  });

  final AuthCoordinator coordinator;
  final bool allowExplicitLogin;
  final AuthFlowResult? recoverySeed;

  @override
  State<_AuthSheetBody> createState() => _AuthSheetBodyState();
}

final class _AuthSheetBodyState extends State<_AuthSheetBody> {
  var _busy = false;
  String? _errorCode;
  var _conflict = false;
  var _recovery = false;
  AuthProviderKind? _recoveryProvider;

  @override
  void initState() {
    super.initState();
    final seed = widget.recoverySeed;
    if (seed != null && seed.outcome == AuthFlowOutcome.recoveryRequired) {
      _recovery = true;
      _recoveryProvider = seed.recoveryProvider;
      _errorCode = seed.errorCode ?? 'SECURE_STORE_UNAVAILABLE';
    }
    unawaited(DiagnosticRuntime.logger.log(LogEvent(
      level: LogLevel.info,
      code: LogCode.screenOpened,
      operation: 'auth_sheet_opened',
    )));
  }

  Future<void> _run(Future<AuthFlowResult> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _errorCode = null;
    });
    final result = await action();
    if (!mounted) return;
    if (result.outcome == AuthFlowOutcome.conflict) {
      setState(() {
        _busy = false;
        _conflict = true;
        _recovery = false;
        _errorCode = 'ACCOUNT_CONFLICT';
      });
      return;
    }
    if (result.outcome == AuthFlowOutcome.recoveryRequired) {
      setState(() {
        _busy = false;
        _conflict = false;
        _recovery = true;
        _recoveryProvider = result.recoveryProvider;
        _errorCode = result.errorCode ?? 'SECURE_STORE_UNAVAILABLE';
      });
      return;
    }
    if (result.outcome == AuthFlowOutcome.failed &&
        result.errorCode == 'RECOVERY_RETRY_LINK') {
      // Link never committed; guest still valid — return to link buttons.
      setState(() {
        _busy = false;
        _conflict = false;
        _recovery = false;
        _recoveryProvider = null;
        _errorCode = 'RECOVERY_RETRY_LINK';
      });
      return;
    }
    if (result.outcome == AuthFlowOutcome.cancelled) {
      setState(() {
        _busy = false;
        _errorCode = null;
      });
      return;
    }
    if (result.outcome == AuthFlowOutcome.failed) {
      setState(() {
        _busy = false;
        _errorCode = result.errorCode ?? 'AUTH_UNAVAILABLE';
      });
      return;
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final copy = TournamentCopy.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final showExplicitLogin =
        (_conflict || _recovery) && widget.allowExplicitLogin;
    final showLoginApple = showExplicitLogin &&
        (_recoveryProvider == null ||
            _recoveryProvider == AuthProviderKind.apple);
    final showLoginGoogle = showExplicitLogin &&
        (_recoveryProvider == null ||
            _recoveryProvider == AuthProviderKind.google);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: GameTokens.textSecondary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              copy.authSheetTitle,
              key: const Key('auth-sheet-title'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: GameTokens.textPrimary,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              _recovery
                  ? copy.authRecoveryBody
                  : _conflict
                      ? copy.authConflictBody
                      : copy.authSheetBody,
              style: const TextStyle(color: GameTokens.textSecondary),
            ),
            if (_errorCode != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  copy.authError(_errorCode!),
                  key: const Key('auth-sheet-error'),
                  style: TextStyle(color: GameTokens.danger),
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (!showExplicitLogin) ...[
              _ProviderButton(
                key: const Key('auth-apple'),
                label: copy.continueWithApple,
                background: Colors.black,
                foreground: Colors.white,
                enabled: !_busy,
                onPressed: () => _run(
                  () => widget.coordinator.linkCurrentGuest(AuthProviderKind.apple),
                ),
              ),
              const SizedBox(height: 12),
              _ProviderButton(
                key: const Key('auth-google'),
                label: copy.continueWithGoogle,
                background: Colors.white,
                foreground: Colors.black87,
                border: true,
                enabled: !_busy,
                onPressed: () => _run(
                  () => widget.coordinator.linkCurrentGuest(AuthProviderKind.google),
                ),
              ),
            ] else ...[
              if (showLoginApple)
                _ProviderButton(
                  key: const Key('auth-login-apple'),
                  label: copy.signInExistingApple,
                  background: Colors.black,
                  foreground: Colors.white,
                  enabled: !_busy,
                  onPressed: () => _run(
                    () => _recovery
                        ? widget.coordinator
                            .recoverPendingLink(AuthProviderKind.apple)
                        : widget.coordinator
                            .loginExisting(AuthProviderKind.apple),
                  ),
                ),
              if (showLoginApple && showLoginGoogle) const SizedBox(height: 12),
              if (showLoginGoogle)
                _ProviderButton(
                  key: const Key('auth-login-google'),
                  label: copy.signInExistingGoogle,
                  background: Colors.white,
                  foreground: Colors.black87,
                  border: true,
                  enabled: !_busy,
                  onPressed: () => _run(
                    () => _recovery
                        ? widget.coordinator
                            .recoverPendingLink(AuthProviderKind.google)
                        : widget.coordinator
                            .loginExisting(AuthProviderKind.google),
                  ),
                ),
              if (_conflict) ...[
                const SizedBox(height: 12),
                TextButton(
                  key: const Key('auth-keep-guest'),
                  onPressed: _busy
                      ? null
                      : () => Navigator.of(context).pop(
                            const AuthFlowResult(
                              outcome: AuthFlowOutcome.cancelled,
                              errorCode: 'ACCOUNT_CONFLICT_KEEP_GUEST',
                            ),
                          ),
                  child: Text(copy.keepGuestProgress),
                ),
              ],
            ],
            const SizedBox(height: 8),
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            TextButton(
              key: const Key('auth-cancel'),
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: Text(copy.cancel),
            ),
          ],
        ),
      ),
    );
  }
}

final class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    required this.enabled,
    required this.onPressed,
    this.border = false,
  });

  final String label;
  final Color background;
  final Color foreground;
  final bool enabled;
  final VoidCallback onPressed;
  final bool border;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: SizedBox(
        height: 48,
        child: ElevatedButton(
          onPressed: enabled ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: background,
            foregroundColor: foreground,
            disabledBackgroundColor: background.withValues(alpha: 0.5),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: border
                  ? BorderSide(color: GameTokens.textSecondary.withValues(alpha: 0.4))
                  : BorderSide.none,
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ),
      ),
    );
  }
}
