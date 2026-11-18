import 'package:puzzle_duel_mobile/application/game_session.dart';

/// Maps internal feedback codes to short player-facing copy.
///
/// Never surface raw wire codes (`occupied_tap`, etc.) in the UI.
abstract final class MoveFeedbackCopy {
  static String? playerMessage({
    required MoveFeedbackKind kind,
    String? code,
  }) {
    if (kind == MoveFeedbackKind.none) return null;
    final mapped = _byCode[code];
    if (mapped != null) return mapped;
    return switch (kind) {
      MoveFeedbackKind.rejected => 'That move won’t work.',
      MoveFeedbackKind.unsafe => 'That move can’t be played.',
      MoveFeedbackKind.none => null,
    };
  }

  /// True when [text] looks like a leaked technical wire/debug string.
  static bool looksTechnical(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('move rejected:')) return true;
    if (lower.contains('could not be applied safely')) return true;
    if (RegExp(r'\b[a-z]+_[a-z_]+\b').hasMatch(lower) &&
        !lower.contains(' ')) {
      return true;
    }
    for (final code in _byCode.keys) {
      if (code != null && lower.contains(code)) return true;
    }
    return false;
  }

  static const Map<String?, String> _byCode = {
    'occupied_tap': 'That slot is taken!',
    'blocked_tap': 'That tile is blocked.',
    'select_offer_first': 'Pick a piece first.',
    'outcome_unknown': 'That move was not confirmed.',
    // Alias kept for older/debug wording; never shown raw.
    'no_offer_selected': 'Pick a piece first.',
    'offer_unavailable': 'That piece isn’t available.',
    'tap_out_of_bounds': 'Stay on the board.',
    'game_ended': 'The round is over.',
    'unresolved_pre_move_match': 'That move can’t be played.',
    'empty_stream_not_terminal': 'That move can’t be played.',
    'early_board_end_empty_stream': 'That move can’t be played.',
    'cascade_corrupt': 'That move can’t be played.',
    'cascade_bound_exceeded': 'That move can’t be played.',
    'invalid_shift_geometry': 'That move can’t be played.',
    'invalid_final_state': 'That move can’t be played.',
  };
}
