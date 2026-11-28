import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/diagnostics/crash_reporter.dart';
import 'package:puzzle_duel_mobile/diagnostics/diagnostic_runtime.dart';
import 'package:puzzle_duel_mobile/diagnostics/firebase_crashlytics_adapter.dart';
import 'package:puzzle_duel_mobile/presentation/feedback/app_feedback.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/arcade_backdrop.dart';
import 'package:puzzle_duel_mobile/theme/game_tokens.dart';
import 'package:puzzle_duel_mobile/tournament/guest_session_recovery.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_controller.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_copy.dart';

/// Sound and haptics. This does not add gameplay settings.
final class TournamentSettingsScreen extends StatefulWidget {
  const TournamentSettingsScreen({
    super.key,
    required this.controller,
    this.crashReporter,
  });

  final TournamentController controller;
  final CrashReporter? crashReporter;

  @override
  State<TournamentSettingsScreen> createState() =>
      _TournamentSettingsScreenState();
}

final class _TournamentSettingsScreenState
    extends State<TournamentSettingsScreen> {
  var _diagnosticUploadInFlight = false;

  @override
  Widget build(BuildContext context) {
    final copy = TournamentCopy.of(context);
    final controller = widget.controller;
    final crashReporter = widget.crashReporter;
    return Scaffold(
      body: ArcadeBackdrop(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
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
                      Text(
                        copy.settingsTitle,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SettingSwitch(
                    icon: Icons.volume_up_rounded,
                    title: copy.soundSetting,
                    body: copy.soundBody,
                    value: controller.settings.sound,
                    onChanged: controller.setSound,
                    switchKey: const Key('settings-sound'),
                  ),
                  const SizedBox(height: 12),
                  _SettingSwitch(
                    icon: Icons.vibration_rounded,
                    title: copy.hapticsSetting,
                    body: copy.hapticsBody,
                    value: controller.settings.haptics,
                    onChanged: controller.setHaptics,
                    switchKey: const Key('settings-haptics'),
                  ),
                  if (DiagnosticRuntime.policy.manualReportEnabled) ...[
                    const SizedBox(height: 12),
                    ListTile(
                      key: const Key('settings-send-diagnostics'),
                      leading: const Icon(Icons.bug_report_outlined),
                      title: const Text('Log Gönder (UAT)'),
                      subtitle: Text(
                        _diagnosticUploadInFlight
                            ? 'Gönderiliyor…'
                            : 'Son güvenli hata kayıtlarını gönder',
                      ),
                      onTap: _diagnosticUploadInFlight
                          ? null
                          : () async {
                              setState(() => _diagnosticUploadInFlight = true);
                              try {
                                final result =
                                    await sendStagingManualDiagnostics(
                                      operation: 'settings_manual_report',
                                      requestId: controller
                                          .activeSessionRecovery
                                          ?.lastRequestId,
                                      errorCode:
                                          controller.tournamentNoticeCode,
                                      crashReporter: crashReporter,
                                      api: controller.api,
                                    );
                                if (!context.mounted) return;
                                final message =
                                    result.serverDelivered &&
                                        result.serverReportId != null
                                    ? '${result.userMessage} (${result.serverReportId})'
                                    : result.userMessage;
                                if (result.serverDelivered &&
                                    result.serverReportId != null) {
                                  await Clipboard.setData(
                                    ClipboardData(text: result.serverReportId!),
                                  );
                                }
                                controller.presentAppFeedback(
                                  kind: result.serverDelivered
                                      ? AppFeedbackKind.success
                                      : AppFeedbackKind.warning,
                                  message: message,
                                  semanticsKey: 'settings-diagnostics-feedback',
                                );
                              } finally {
                                if (mounted) {
                                  setState(
                                    () => _diagnosticUploadInFlight = false,
                                  );
                                }
                              }
                            },
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      key: const Key('settings-staging-crash-test'),
                      leading: const Icon(Icons.warning_amber_rounded),
                      title: const Text('Crash Test (STAGING)'),
                      subtitle: Text(FirebaseDiagnostics.readinessMessage),
                      onTap: () async {
                        if (!FirebaseDiagnostics.enabled ||
                            !FirebaseDiagnostics.stagingDiagnosticsEnabled) {
                          controller.presentAppFeedback(
                            kind: AppFeedbackKind.warning,
                            message:
                                'Crash testi kullanılamıyor: ${FirebaseDiagnostics.readinessMessage}',
                            semanticsKey: 'settings-crash-test-unavailable',
                          );
                          return;
                        }
                        final approved = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('Staging Crash Test'),
                            content: const Text(
                              'Bu işlem uygulamayı bilerek kapatır. Devam edilsin mi?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                child: const Text('İptal'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, true),
                                child: const Text('Test crash oluştur'),
                              ),
                            ],
                          ),
                        );
                        if (approved == true) {
                          await FirebaseDiagnostics.forceTestCrash();
                        }
                      },
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

final class _SettingSwitch extends StatelessWidget {
  const _SettingSwitch({
    required this.icon,
    required this.title,
    required this.body,
    required this.value,
    required this.onChanged,
    required this.switchKey,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Key switchKey;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: GameTokens.surface.withValues(alpha: 0.94),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GameTokens.radiusLg),
        side: const BorderSide(color: GameTokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: SwitchListTile(
        key: switchKey,
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        secondary: Icon(icon, color: GameTokens.accent),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: GameTokens.textPrimary,
          ),
        ),
        subtitle: Text(body),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
