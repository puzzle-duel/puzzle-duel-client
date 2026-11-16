import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/presentation/widgets/piece_glyph.dart';
import 'package:puzzle_duel_rules/puzzle_duel_rules.dart';

/// Three-slot offer tray. Never generates pieces; displays engine offers only.
final class OfferTray extends StatelessWidget {
  const OfferTray({
    super.key,
    required this.offers,
    required this.selectedIndex,
    required this.enabled,
    required this.onSelect,
  });

  final List<Piece?> offers;
  final int? selectedIndex;
  final bool enabled;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    assert(offers.length == 3);
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: 'Offer tray, three pieces',
      child: Row(
        children: [
          for (var i = 0; i < 3; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _OfferSlot(
                  index: i,
                  piece: offers[i],
                  selected: selectedIndex == i,
                  enabled: enabled && offers[i] != null,
                  onSelect: onSelect,
                  theme: theme,
                ),
              ),
            ),
        ],
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
    required this.theme,
  });

  final int index;
  final Piece? piece;
  final bool selected;
  final bool enabled;
  final ValueChanged<int> onSelect;
  final ThemeData theme;

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
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            width: selected ? 3 : 1,
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: InkWell(
          onTap: enabled ? () => onSelect(index) : null,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 88,
            child: Center(
              child: piece == null
                  ? Text(
                      '—',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : PieceGlyph(
                      piece: piece!,
                      size: 52,
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
