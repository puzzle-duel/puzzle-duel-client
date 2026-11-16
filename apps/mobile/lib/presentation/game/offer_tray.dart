import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/piece_glyph.dart';
import 'package:puzzle_duel_mobile/theme/game_tokens.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

/// Three-slot offer tray with tactile selection chrome.
final class OfferTray extends StatelessWidget {
  const OfferTray({
    super.key,
    required this.offers,
    required this.selectedIndex,
    required this.enabled,
    required this.onSelect,
  });

  /// Versioned tray slots (`OfferLive` / `OfferEmpty` / `OfferSpent`).
  ///
  /// UI treats non-selectable slots (historical v2 null / v3 spent) as empty.
  final List<OfferSlot> offers;
  final int? selectedIndex;
  final bool enabled;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    assert(offers.length == 3);
    return Semantics(
      container: true,
      label: 'Offer tray, three pieces',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: GameTokens.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(GameTokens.radiusLg),
          border: Border.all(color: GameTokens.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
          child: Row(
            children: [
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: _OfferSlot(
                      index: i,
                      piece: offers[i].pieceOrNull,
                      selected: selectedIndex == i,
                      enabled: enabled && offers[i].isSelectable,
                      onSelect: onSelect,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _OfferSlot extends StatelessWidget {
  const _OfferSlot({
    required this.index,
    required this.piece,
    required this.selected,
    required this.enabled,
    required this.onSelect,
  });

  final int index;
  final Piece? piece;
  final bool selected;
  final bool enabled;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final label = piece == null
        ? 'Offer slot ${index + 1}, empty'
        : 'Offer slot ${index + 1}, ${PieceGlyph.semanticsLabel(piece!)}'
              '${selected ? ', selected' : ''}';
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        height: 100,
        transform: selected
            ? Matrix4.translationValues(0, -3, 0)
            : Matrix4.identity(),
        decoration: BoxDecoration(
          color: selected
              ? GameTokens.surfaceHigh
              : GameTokens.bgMid.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(GameTokens.radiusMd),
          border: Border.all(
            width: selected ? 3 : 1.2,
            color: selected ? GameTokens.accent : GameTokens.border,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: GameTokens.accent.withValues(alpha: 0.4),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: enabled ? () => onSelect(index) : null,
            borderRadius: BorderRadius.circular(GameTokens.radiusMd),
            child: Center(
              child: piece == null
                  ? const Text(
                      '—',
                      style: TextStyle(
                        fontSize: 28,
                        color: GameTokens.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : PieceGlyph(
                      piece: piece!,
                      size: 56,
                      selected: selected,
                      muted: !enabled && !selected,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
