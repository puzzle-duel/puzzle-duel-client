import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/badges/domain/badge_definition.dart';
import 'package:puzzle_duel_mobile/badges/domain/badge_prestige.dart';
import 'package:puzzle_duel_mobile/badges/domain/badge_prestige_resolver.dart';
import 'package:puzzle_duel_mobile/badges/presentation/badge_medallion.dart';
import 'package:puzzle_duel_mobile/badges/presentation/badge_prestige_palette.dart';
import 'package:puzzle_duel_mobile/diagnostics/diagnostic_runtime.dart';
import 'package:puzzle_duel_mobile/diagnostics/puzzle_duel_logger.dart';
import 'package:puzzle_duel_mobile/theme/game_tokens.dart';
import 'package:puzzle_duel_mobile/tournament/tournament_copy.dart';

/// Staging/debug-only visual verification tool. Never mutates real awards.
final class BadgeEvolutionStudioScreen extends StatefulWidget {
  const BadgeEvolutionStudioScreen({super.key});

  @override
  State<BadgeEvolutionStudioScreen> createState() =>
      _BadgeEvolutionStudioScreenState();
}

final class _BadgeEvolutionStudioScreenState
    extends State<BadgeEvolutionStudioScreen> {
  static const _defaults = <BadgeId, int>{
    BadgeId.loyalty: 76,
    BadgeId.onTime: 76,
    BadgeId.practiceMaster: 76,
    BadgeId.tournamentGuru: 12,
    BadgeId.champion: 10,
    BadgeId.risingStar: 5,
    BadgeId.unstoppable: 12,
  };

  late final Map<BadgeId, int> _counts = Map<BadgeId, int>.from(_defaults);
  BadgeId _selected = BadgeId.onTime;

  @override
  void initState() {
    super.initState();
    DiagnosticRuntime.logger.log(
      LogEvent(
        level: LogLevel.info,
        code: LogCode.screenOpened,
        operation: 'badge_evolution_studio_opened',
      ),
    );
  }

  BadgeDefinition get _definition =>
      kBadgeCatalog.firstWhere((d) => d.id == _selected);

  int get _count => _counts[_selected] ?? 0;

  set _count(int value) => _counts[_selected] = value < 0 ? 0 : value;

  String _upperPrestige(TournamentCopy copy, BadgePrestige prestige) {
    final name = copy.badgePrestigeName(prestige);
    if (copy.isTurkish) {
      return name.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();
    }
    return name.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final copy = TournamentCopy.of(context);
    final resolution = const BadgePrestigeResolver().resolve(
      thresholds: _definition.thresholds,
      earnedCount: _count,
    );
    final prestige = resolution.prestige;
    final colors = prestige == null
        ? BadgePrestigeColors.locked
        : BadgePrestigeColors.forPrestige(prestige);
    final maxSlider = (_definition.thresholds.mythic * 1.5).ceil().toDouble();

    return Scaffold(
      key: const Key('badge-evolution-studio'),
      backgroundColor: BadgePrestigePalette.canvasBackground,
      appBar: AppBar(
        title: Text(copy.badgeEvolutionStudioTitle),
        backgroundColor: GameTokens.surface,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            copy.badgeEvolutionStudioBlurb,
            style: const TextStyle(color: GameTokens.textSecondary),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final definition in kBadgeCatalog)
                ChoiceChip(
                  key: Key('studio-badge-${definition.id.wire}'),
                  label: Text(definition.name(copy)),
                  selected: definition.id == _selected,
                  onSelected: (_) => setState(() => _selected = definition.id),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: BadgeMedallion(
              key: const Key('studio-main-medallion'),
              badgeId: _selected,
              prestige: prestige,
              earnedCount: _count,
              prestigeLabel: prestige == null
                  ? ''
                  : _upperPrestige(copy, prestige),
              semanticLabel: _definition.name(copy),
              width: 240,
              paintBackground: true,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            prestige == null
                ? copy.badgeLocked
                : '${copy.badgePrestigeName(prestige)} · ×$_count',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.highlight,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 7,
              child: LinearProgressIndicator(
                value: resolution.visualProgress,
                backgroundColor: BadgePrestigePalette.progressTrack,
                color: colors.primary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(
                key: const Key('studio-count-minus'),
                onPressed: () => setState(() => _count = _count - 1),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Expanded(
                child: Slider(
                  key: const Key('studio-count-slider'),
                  value: _count.clamp(0, maxSlider.toInt()).toDouble(),
                  min: 0,
                  max: maxSlider,
                  divisions: maxSlider.toInt(),
                  label: '$_count',
                  onChanged: (v) => setState(() => _count = v.round()),
                ),
              ),
              IconButton(
                key: const Key('studio-count-plus'),
                onPressed: () => setState(() => _count = _count + 1),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          TextButton(
            key: const Key('studio-reset-count'),
            onPressed: () => setState(() {
              _count = _defaults[_selected] ?? 0;
            }),
            child: Text(copy.tryAgain),
          ),
          TextButton(
            key: const Key('studio-locked-zero'),
            onPressed: () => setState(() => _count = 0),
            child: Text(copy.badgeLocked),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final tier in BadgePrestige.values)
                InkWell(
                  key: Key('studio-prestige-${tier.wire}'),
                  onTap: () => setState(() {
                    _count = _definition.thresholds.forPrestige(tier);
                  }),
                  child: BadgeMedallion(
                    badgeId: _selected,
                    prestige: tier,
                    earnedCount: _definition.thresholds.forPrestige(tier),
                    prestigeLabel: _upperPrestige(copy, tier),
                    semanticLabel: copy.badgePrestigeName(tier),
                    width: 88,
                    showPrestigeLabel: false,
                    paintBackground: true,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
