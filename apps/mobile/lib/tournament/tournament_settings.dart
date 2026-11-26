import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/diagnostics/diagnostic_runtime.dart';
import 'package:puzzle_duel_mobile/diagnostics/firebase_crashlytics_adapter.dart';
import 'package:puzzle_duel_mobile/diagnostics/puzzle_duel_logger.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/arcade_backdrop.dart';
import 'package:puzzle_duel_mobile/theme/game_tokens.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_controller.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_copy.dart';

/// Sound and haptics. This does not add gameplay settings.
final class TournamentSettingsScreen extends StatelessWidget {
  const TournamentSettingsScreen({super.key, required this.controller});

  final TournamentController controller;

  @override
  Widget build(BuildContext context) {
    final copy = TournamentCopy.of(context);
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
                      subtitle: const Text('Son güvenli hata kayıtlarını gönder'),
                      onTap: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          // Session recovery has no verified tournament session:
                          // authenticated report endpoint cannot be used without
                          // inventing an auth bypass. Prefer server report when
                          // bearer exists; otherwise flush Crashlytics breadcrumbs.
                          if (controller.sessionRecoveryRequired ||
                              controller.api.bearer.trim().isEmpty) {
                            await DiagnosticRuntime.logger.log(LogEvent(
                              level: LogLevel.warning,
                              code: LogCode.diagnosticFailure,
                              operation: 'guest_recovery_settings_report',
                              requestId:
                                  controller.sessionRecovery?.lastRequestId,
                              errorCode: controller.tournamentNoticeCode ??
                                  'GUEST_RECOVERY_REQUIRED',
                            ));
                            if (!context.mounted) return;
                            final rid =
                                controller.sessionRecovery?.lastRequestId;
                            messenger.showSnackBar(SnackBar(
                              content: Text(rid == null
                                  ? 'Crashlytics breadcrumb gönderildi (oturum yok).'
                                  : 'Crashlytics breadcrumb gönderildi. requestId=$rid'),
                            ));
                            return;
                          }
                          final result =
                              await controller.api.sendDiagnosticReport();
                          if (!context.mounted) return;
                          final reportId = result.map['reportId'];
                          messenger.showSnackBar(SnackBar(
                            content: Text(result.status == 201 &&
                                    reportId is String
                                ? 'Log gönderildi. Rapor: $reportId'
                                : 'Log gönderilemedi (${result.status}).'),
                          ));
                        } catch (_) {
                          if (!context.mounted) return;
                          messenger.showSnackBar(const SnackBar(
                            content: Text('Log gönderilemedi.'),
                          ));
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      key: const Key('settings-staging-crash-test'),
                      leading: const Icon(Icons.warning_amber_rounded),
                      title: const Text('Crash Test (STAGING)'),
                      subtitle: Text(FirebaseDiagnostics.enabled &&
                              FirebaseDiagnostics.stagingDiagnosticsEnabled
                          ? 'Onaydan sonra test crash oluşturur'
                          : 'Firebase Crashlytics staging yapılandırması gerekli'),
                      onTap: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        if (!FirebaseDiagnostics.enabled ||
                            !FirebaseDiagnostics.stagingDiagnosticsEnabled) {
                          messenger.showSnackBar(const SnackBar(
                            content: Text(
                                'Crash testi kullanılamıyor: staging Firebase yapılandırmasını kontrol edin.'),
                          ));
                          return;
                        }
                        final approved = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('Staging Crash Test'),
                            content: const Text(
                                'Bu işlem uygulamayı bilerek kapatır. Devam edilsin mi?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialogContext, false),
                                child: const Text('İptal'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(dialogContext, true),
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
