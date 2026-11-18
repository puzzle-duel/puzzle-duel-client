import 'package:material_ui/material_ui.dart';
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
                      Text(copy.settingsTitle, style: Theme.of(context).textTheme.headlineSmall),
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
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: GameTokens.textPrimary)),
        subtitle: Text(body),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
