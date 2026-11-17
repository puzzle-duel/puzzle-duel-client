part of '../puzzle_duel_rules.dart';

/// Structural validation codes.
///
/// These are not gameplay rejections. See [GameplayRejection] for
/// `blocked_tap`, `occupied_tap`, and `game_ended`.
enum ValidationCode {
  missingField('missing_field'),
  unexpectedProperty('unexpected_property'),
  unknownRulesVersion('unknown_rules_version'),
  malformedBoard('malformed_board'),
  malformedCoordinate('malformed_coordinate'),
  blockedOutOfRange('blocked_out_of_range'),
  duplicateBlocked('duplicate_blocked'),
  blockedNotRowMajor('blocked_not_row_major'),
  blockedCellOccupied('blocked_cell_occupied'),
  malformedPiece('malformed_piece'),
  malformedShape('malformed_shape'),
  malformedDirection('malformed_direction'),
  malformedOffers('malformed_offers'),
  nullOffer('null_offer'),
  nullOfferWhileActive('null_offer_while_active'),
  multipleNullOffers('multiple_null_offers'),
  nullOfferNotTerminal('null_offer_not_terminal'),
  illegalTurnCount('illegal_turn_count'),
  malformedScore('malformed_score'),
  inconsistentStatus('inconsistent_status'),
  unresolvedInitialMatch('unresolved_initial_match'),
  malformedMove('malformed_move'),
  illegalOfferIndex('illegal_offer_index'),
  malformedOfferSlot('malformed_offer_slot'),
  inconsistentTerminalReason('inconsistent_terminal_reason'),
  spentWithFuturePieces('spent_with_future_pieces'),
  noLegalInitialPlacement('no_legal_initial_placement'),
  integerOutOfRange('integer_out_of_range');

  const ValidationCode(this.wire);

  final String wire;
}

final class ValidationFailure implements Exception {
  ValidationFailure(List<ValidationCode> codes)
    : codes = List<ValidationCode>.unmodifiable(codes);

  final List<ValidationCode> codes;

  List<String> get wires => [for (final code in codes) code.wire];

  @override
  bool operator ==(Object other) {
    if (other is! ValidationFailure || other.codes.length != codes.length) {
      return false;
    }
    for (var index = 0; index < codes.length; index++) {
      if (other.codes[index] != codes[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(codes);

  @override
  String toString() => 'ValidationFailure(${wires.join(', ')})';
}
